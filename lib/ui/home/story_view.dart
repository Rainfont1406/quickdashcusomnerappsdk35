import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:video_player/video_player.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/model/story_model.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/behavior/behavior_event_types.dart';
import 'package:emartconsumer/services/behavior/behavior_tracker.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/utils/network_image_widget.dart';
import 'package:emartconsumer/widget/story_view/controller/story_controller.dart';
import 'package:emartconsumer/widget/story_view/hls_preload_registry.dart';
import 'package:emartconsumer/widget/story_view/story_cache_manager.dart'
    show StoryImageCacheManager, StoryVideoCacheManager;
import 'package:emartconsumer/widget/story_view/utils.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../widget/story_view/widgets/story_view.dart';
import '../vendorProductsScreen/newVendorProductsScreen.dart';

/// Full-screen story viewer opened from HomeScreen.
///
/// Uses [PageView] for left/right swipe between vendors (exactly like
/// Instagram Stories) while [StoryView] handles tap-to-advance and
/// tap-to-rewind within a single vendor's story items.
class MoreStories extends StatefulWidget {
  final List<StoryModel> storyList;
  final int index;
  final String orderType;
  // Called whenever a view is successfully written to Firestore so that the
  // HomeScreen circle row can immediately update the ring colour to grey.
  final void Function(String storyID)? onViewRecorded;

  const MoreStories({
    super.key,
    required this.index,
    required this.storyList,
    required this.orderType,
    this.onViewRecorded,
  });

  @override
  MoreStoriesState createState() => MoreStoriesState();
}

class MoreStoriesState extends State<MoreStories> with WidgetsBindingObserver {
  late PageController _pageController;
  late int _currentIndex;
  Timer? _prefetchTimer;
  DateTime? _storyStartTime;
  // Holds the currently-active vendor page's StoryController so lifecycle
  // events can pause/resume it when the app is backgrounded.
  StoryController? _currentController;

  @override
  void initState() {
    super.initState();
    // TEMPORARY [STORY-PERF] - marks when the story viewer itself opens, so
    // the per-item [STORY-PERF][IMG]/[VIDEO] logs below can be lined up
    // against it in a capture. Remove once the investigation is done.
    debugPrint('[STORY-PERF] MoreStories.initState — viewer opened at index ${widget.index}');
    WidgetsBinding.instance.addObserver(this);
    _currentIndex = widget.index;
    _pageController = PageController(initialPage: _currentIndex);
    _schedulePrefetchAt30(_currentIndex);
    // Keep the screen on for the whole story-viewing session (Instagram/
    // Snapchat behavior) — without this, Android's normal screen-timeout
    // still fires while a story is playing since swiping/tapping through
    // stories doesn't reset it on its own. Wrapped: the plugin's native
    // channel can be briefly unavailable (e.g. right after adding the
    // dependency, before a full rebuild) - must not surface as an
    // unhandled exception for something this non-critical.
    WakelockPlus.enable().catchError((Object e) {
      debugPrint('[STORY-PERF] WakelockPlus.enable failed: $e');
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _currentController?.pause();
    } else if (state == AppLifecycleState.resumed) {
      _currentController?.play();
    }
  }

  // Estimated total display time for a story — used only as the initial 30%
  // trigger before the video player reports its actual duration.
  // Images: 5 s each. Videos: 10 s each (corrected later by _onActualDuration).
  Duration _expectedStoryDuration(StoryModel story) {
    final ms = story.imageUrl.length * 5000 +
        (story.hasVideo && !story.isMediaProcessing
            ? story.videoUrl.length * 10000
            : 0);
    return Duration(milliseconds: ms > 0 ? ms : 5000);
  }

  // Schedules a prefetch for the story AFTER [index] to fire at 30% of the
  // current story's estimated duration. The timer is recalibrated automatically
  // by _onActualDuration once the video player reports the true length.
  void _schedulePrefetchAt30(int index) {
    _prefetchTimer?.cancel();
    _storyStartTime = DateTime.now();
    if (index + 1 >= widget.storyList.length) return;
    final delay = _expectedStoryDuration(widget.storyList[index]) * 0.3;
    _prefetchTimer = Timer(delay, () {
      if (mounted) _prefetchNextStory(index);
    });
  }

  // Called by _VendorStoryPage when the video player reports the true duration.
  // Recalculates the 30% point accounting for time already elapsed.
  void _onActualDuration(Duration actual, int index) {
    if (!mounted || _storyStartTime == null) return;
    if (index != _currentIndex) return; // stale callback from a previous story
    if (index + 1 >= widget.storyList.length) return;
    final elapsed = DateTime.now().difference(_storyStartTime!);
    final target = actual * 0.3;
    final remaining = target - elapsed;
    _prefetchTimer?.cancel();
    if (remaining <= Duration.zero) {
      // Already past 30% — prefetch immediately.
      _prefetchNextStory(index);
    } else {
      _prefetchTimer = Timer(remaining, () {
        if (mounted) _prefetchNextStory(index);
      });
    }
  }

  // Warms assets for the NEXT vendor's story only.
  //
  // Images → written to StoryImageCacheManager disk cache; ImageLoader reads
  //           from the same cache via getFileStream(), so they arrive pre-warmed.
  //
  // HLS videos → pre-initialize a VideoPlayerController so the native player
  //              starts buffering segments now. Stored in HlsPreloadRegistry;
  //              StoryVideoState claims it and skips the expensive initialize().
  //
  // Direct MP4 → written to StoryVideoCacheManager disk cache (rare in prod).
  void _prefetchNextStory(int currentIndex) {
    final nextIndex = currentIndex + 1;
    if (nextIndex >= widget.storyList.length) return;
    final next = widget.storyList[nextIndex];

    // Prefetch images.
    for (final url in next.imageUrl) {
      final s = url.toString();
      if (s.isNotEmpty) {
        StoryImageCacheManager.instance
            .getSingleFile(s)
            .then<void>((_) {}, onError: (_) {});
      }
    }

    // Prefetch videos.
    for (final url in next.videoUrl) {
      final s = url.toString();
      if (s.isEmpty) continue;
      if (s.toLowerCase().contains('.m3u8')) {
        // HLS: pre-initialize controller so native HLS layer buffers ahead.
        final ctrl = VideoPlayerController.networkUrl(
          Uri.parse(s),
          httpHeaders: const {'Referer': 'https://admin.quickdash.co.in'},
        );
        ctrl.initialize().then<void>((_) {
          if (mounted) {
            HlsPreloadRegistry.store(s, ctrl);
          } else {
            ctrl.dispose();
          }
        }).catchError((_) { ctrl.dispose(); });
      } else {
        // Direct MP4: file-cache it.
        StoryVideoCacheManager.instance
            .getSingleFile(s,
                headers: const {'Referer': 'https://admin.quickdash.co.in'})
            .then<void>((_) {}, onError: (_) {});
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable().catchError((Object e) {
      debugPrint('[STORY-PERF] WakelockPlus.disable failed: $e');
    });
    _prefetchTimer?.cancel();
    HlsPreloadRegistry.disposeAll();
    _pageController.dispose();
    super.dispose();
  }

  void _advanceToNext() {
    if (!mounted) return;
    if (_currentIndex < widget.storyList.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        // ClampingScrollPhysics prevents over-scrolling past the first/last
        // vendor, matching the Instagram experience.
        physics: const ClampingScrollPhysics(),
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
          _schedulePrefetchAt30(index);
        },
        itemCount: widget.storyList.length,
        itemBuilder: (context, index) {
          return _VendorStoryPage(
            key: ValueKey('story_vendor_$index'),
            story: widget.storyList[index],
            orderType: widget.orderType,
            isActive: index == _currentIndex,
            onComplete: _advanceToNext,
            onClose: () => Navigator.pop(context),
            onActualDuration: (d) => _onActualDuration(d, index),
            onViewRecorded: widget.onViewRecorded,
            onControllerReady: (ctrl) => _currentController = ctrl,
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// One vendor's story page (owns its StoryController)
// ─────────────────────────────────────────────────────────────────────────────

class _VendorStoryPage extends StatefulWidget {
  final StoryModel story;
  final String orderType;
  final bool isActive;
  final VoidCallback onComplete;
  final VoidCallback onClose;
  // Called when the video player reports its actual duration so MoreStoriesState
  // can recalibrate the 30% prefetch timer with the real length.
  final void Function(Duration)? onActualDuration;
  // Called after a view is successfully written to Firestore. Bubbles up so
  // HomeScreen can immediately grey out the ring without waiting for a reload.
  final void Function(String storyID)? onViewRecorded;
  // Called when this page's StoryController is ready (initState + on isActive
  // flip) so MoreStoriesState can pause/resume it on app lifecycle events.
  final void Function(StoryController)? onControllerReady;

  const _VendorStoryPage({
    super.key,
    required this.story,
    required this.orderType,
    required this.isActive,
    required this.onComplete,
    required this.onClose,
    this.onActualDuration,
    this.onViewRecorded,
    this.onControllerReady,
  });

  @override
  State<_VendorStoryPage> createState() => _VendorStoryPageState();
}

class _VendorStoryPageState extends State<_VendorStoryPage> {
  late StoryController _controller;
  late List<StoryItem> _items;
  bool _viewRecorded = false;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _bufferingSub;
  // Started on every onStoryShow; fires _recordView after 3 s of uninterrupted
  // viewing so that a quick tap-through doesn't inflate view counts.
  Timer? _viewTimer;

  // Behavior tracking: "completed" is reserved strictly for reaching the
  // natural end of this vendor's story queue (StoryView's own onComplete);
  // any other way this page stops being active (swiped to a different
  // vendor, swiped down to dismiss, backgrounded/torn down) counts as
  // "skipped". Guards prevent double-firing across dispose()/didUpdateWidget.
  bool _completed = false;
  bool _skipTracked = false;
  DateTime? _shownAt;
  // Session-only (never persisted) - distinguishes a first view of a story
  // from a replay within the same app session. Static so it survives this
  // widget being rebuilt/recreated as the user swipes between vendors.
  static final Set<String> _sessionViewedStoryIds = {};

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _shownAt = DateTime.now();
    _controller = StoryController();
    _items = _buildItems();
    // Page is built before it becomes visible — keep paused until active.
    if (!widget.isActive) _controller.pause();
    // Always notify the parent so lifecycle pause/resume is wired from the start.
    widget.onControllerReady?.call(_controller);
    // Forward actual video duration to MoreStoriesState so it can recalibrate
    // the 30% prefetch timer from estimated → real duration.
    // Also start the view-count timer here for video stories: durationNotifier
    // fires inside _initPlayer() only after initialize() completes and the video
    // is genuinely ready to play — so loading time is never counted toward the
    // 3-second threshold.
    _durationSub = _controller.durationNotifier.listen((d) {
      widget.onActualDuration?.call(d);
      if (widget.isActive && !_viewRecorded) {
        _viewTimer?.cancel();
        _viewTimer = Timer(_viewThresholdFor(d), _recordView);
      }
    });

    // Cancel the view timer while the video player is buffering (network stall)
    // so that dead-air time is never counted as watch time. When the buffer
    // clears, restart the full 3-second countdown from zero — conservatively
    // requiring 3 uninterrupted seconds of actual playback.
    _bufferingSub = _controller.bufferingNotifier.listen((isBuffering) {
      if (_viewRecorded) return;
      if (isBuffering) {
        _viewTimer?.cancel();
        _viewTimer = null;
      } else if (widget.isActive) {
        // Buffer cleared — only restart if a duration is known (i.e. the video
        // is fully initialised and genuinely playing, not still loading).
        final knownDuration = _controller.durationNotifier.valueOrNull;
        if (knownDuration != null) {
          _viewTimer?.cancel();
          _viewTimer = Timer(_viewThresholdFor(knownDuration), _recordView);
        }
      }
    });
  }

  // Videos shorter than the normal 3-second dwell threshold could otherwise
  // never be marked watched at all (the clip ends/loops before 3 continuous
  // seconds elapse) — for those, 500ms of uninterrupted playback is enough.
  Duration _viewThresholdFor(Duration videoDuration) {
    return videoDuration < const Duration(seconds: 3)
        ? const Duration(milliseconds: 500)
        : const Duration(seconds: 3);
  }

  // Records a unique view for this story, deduped per (story, user, day) so
  // a returning viewer on a later calendar day still counts as a new view
  // against the vendor's purchased view package - but re-opening the same
  // story multiple times today does not.
  Future<void> _recordView() async {
    if (_viewRecorded) return;

    // MyAppState.currentUser is populated from a Firestore fetch during
    // login/session-restore, which can still be in flight (e.g. right after
    // a fresh login following a data clear, or a fast tap into a story
    // before that fetch resolves) - Firebase Auth's own currentUser is
    // cached locally the instant sign-in completes, so it's the more
    // reliable fallback here rather than silently dropping the view.
    final userID = MyAppState.currentUser?.userID ??
        auth.FirebaseAuth.instance.currentUser?.uid;
    final storyID = widget.story.storyID;
    if (userID == null || userID.isEmpty || storyID == null || storyID.isEmpty) {
      // Don't set _viewRecorded - user/story identity may become available
      // a moment later (e.g. still mid-login), and this same dwell-complete
      // moment would otherwise never get another chance to record the view.
      return;
    }
    _viewRecorded = true; // client-side debounce, set only once we can actually record

    // This fires the moment the dwell threshold (3s image / video-ready) is
    // satisfied - independent of the Firestore view-count write below
    // succeeding or being server-side deduped for today, so it's tracked
    // unconditionally here rather than inside the try/transaction.
    final isReplay = _sessionViewedStoryIds.contains(storyID);
    _sessionViewedStoryIds.add(storyID);
    BehaviorTracker.track(
      isReplay ? kEvtStoryReplayed : kEvtStoryViewed,
      {'storyId': storyID, 'vendorId': widget.story.vendorID},
    );

    final now = DateTime.now();
    final dateKey =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

    final firestore = FirebaseFirestore.instance;
    final viewRef =
        firestore.collection('story_views').doc('${storyID}_${userID}_$dateKey');
    final storyRef = firestore.collection(STORY).doc(storyID);

    try {
      bool alreadyCounted = false;
      await firestore.runTransaction((tx) async {
        final existing = await tx.get(viewRef);
        if (existing.exists) {
          alreadyCounted = true;
          return;
        }
        tx.set(viewRef, {
          'storyID': storyID,
          'userID': userID,
          'vendorID': widget.story.vendorID,
          'dateKey': dateKey,
          'viewedAt': Timestamp.now(),
        });
        tx.update(storyRef, {'viewCount': FieldValue.increment(1)});
      });
      // Notify the UI regardless of alreadyCounted — the story is viewed
      // either way (just now, or in an earlier session/watch today), and the
      // ring needs to reflect that. Only the viewCount increment above is
      // conditional on this being the first view today.
      widget.onViewRecorded?.call(storyID);
    } catch (e) {
      // Expected once the story's purchased view package is exhausted —
      // firestore.rules hard-caps viewCount at viewPackageSize (2026-07-26),
      // so this specific viewer's increment is the one that got rejected by
      // the server, not applied then rolled back. Not actionable from here;
      // the story will also stop appearing in _filterStories() (isExpired)
      // on the next fetch. Logged for debugging only.
      //
      // Still notify the UI even though the write failed — a slow/degraded
      // connection can time out this transaction (it's two round trips: a
      // tx.get() then a commit) without the user having watched any less of
      // the story. The comment above already says the ring must reflect
      // "viewed either way" — this call was previously missing from this
      // branch, so any transaction failure (not just the view-package-
      // exhausted case) silently left the ring grey-less despite a genuine
      // watch. Analytics/viewCount are allowed to be lossy here; the local
      // "you've seen this" indicator should not be.
      widget.onViewRecorded?.call(storyID);
    }
  }

  // Reaching the natural end of this vendor's story queue (StoryView's own
  // onComplete) - the only path that counts as "completed" rather than
  // "skipped". See the field comments above for the full decision.
  void _handleComplete() {
    _completed = true;
    BehaviorTracker.track(kEvtStoryCompleted, {'vendorId': widget.story.vendorID});
    widget.onComplete();
  }

  void _trackSkipIfNeeded() {
    // _shownAt is only ever set while this page was genuinely active -
    // guards against tracking a "skip" for a page the user never actually
    // saw (e.g. PageView pre-building an adjacent, not-yet-visible page).
    if (_shownAt == null || _completed || _skipTracked) return;
    _skipTracked = true;
    final watchedMs = _shownAt == null
        ? null
        : DateTime.now().difference(_shownAt!).inMilliseconds;
    BehaviorTracker.track(kEvtStorySkipped, {
      'storyId': widget.story.storyID ?? '',
      'vendorId': widget.story.vendorID,
      if (watchedMs != null) 'watchedMs': watchedMs,
    });
  }

  @override
  void didUpdateWidget(_VendorStoryPage old) {
    super.didUpdateWidget(old);
    if (old.isActive != widget.isActive) {
      if (widget.isActive) {
        _shownAt = DateTime.now();
        _skipTracked = false;
        widget.onControllerReady?.call(_controller);
        _controller.play();
        // Restart the view timer when the user swipes back to this story
        // within the same session. _durationSub only fires once (BehaviorSubject
        // doesn't re-emit to an existing subscriber), so we restart manually
        // using the already-known duration.
        if (!_viewRecorded) {
          final isVideoStory =
              widget.story.hasVideo && !widget.story.isMediaProcessing;
          if (isVideoStory) {
            // Only restart if the video duration was already reported.
            // If not yet known, _durationSub will handle it when it fires.
            if (_controller.durationNotifier.valueOrNull != null) {
              _viewTimer?.cancel();
              _viewTimer = Timer(const Duration(seconds: 3), _recordView);
            }
          } else {
            _viewTimer?.cancel();
            _viewTimer = Timer(const Duration(seconds: 1), _recordView);
          }
        }
      } else {
        _viewTimer?.cancel(); // user swiped away — don't count the view
        _controller.pause();
        // Swiped to a different vendor's story before this one naturally
        // completed - a skip. If it HAD just completed, _handleComplete
        // already set _completed and this is a no-op.
        _trackSkipIfNeeded();
      }
    }
  }

  @override
  void dispose() {
    // Covers swipe-down-to-dismiss and the whole viewer being popped/torn
    // down (backgrounded, closed) while this page was still active - the
    // isActive-false branch in didUpdateWidget only fires for a horizontal
    // swipe to a different vendor, not for the page being destroyed outright.
    _trackSkipIfNeeded();
    _viewTimer?.cancel();
    _durationSub?.cancel();
    _bufferingSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // Shown while the HLS video controller initialises.
  // Displays the Bunny-generated thumbnail at full cover + a dark scrim +
  // the standard progress spinner so the user knows something is loading.
  Widget _videoLoadingWidget() {
    final thumb = widget.story.videoThumbnail ?? '';
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (thumb.isNotEmpty)
            Image.network(
              thumb,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: Colors.black),
            )
          else
            const ColoredBox(color: Colors.black),
          // Scrim so the thumbnail reads as "loading", not "loaded".
          ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
          const Center(
            child: SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Shown while the image is being read from cache / downloaded.
  // Displays a blurred version of the same image so the screen is not
  // a blank black flash — the blur makes the loading state obvious.
  Widget _imageLoadingWidget(String imageUrl) {
    if (imageUrl.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 70,
          height: 70,
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            strokeWidth: 3,
          ),
        ),
      );
    }
    return SizedBox.expand(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        // Blurred beyond recognition anyway - a tiny transform is plenty and
        // avoids a second full-resolution fetch competing for bandwidth with
        // the real image loading in parallel via ImageLoader.loadImage above.
        child: Image.network(
          bunnyOptimizedUrl(imageUrl, width: 150, quality: 40),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black),
        ),
      ),
    );
  }

  List<StoryItem> _buildItems() {
    final story = widget.story;
    final items = <StoryItem>[];

    if (widget.orderType == "Delivery".tr() && story.hasImage) {
      for (final url in story.imageUrl) {
        final urlStr = url.toString();
        items.add(StoryItem.pageImage(
          // Story images were being fetched at full original upload
          // resolution (no width/quality transform), unlike every other
          // image in the app - a multi-MB camera photo took ~8s to load
          // (measured via [STORY-PERF][IMG]). Full-screen display never
          // needs more than screen width.
          url: bunnyOptimizedUrl(urlStr, width: 1080),
          controller: _controller,
          imageFit: BoxFit.contain,
          duration: const Duration(seconds: 5),
          loadingWidget: _imageLoadingWidget(urlStr),
        ));
      }
    } else if ((widget.orderType == "Dineaway".tr() ||
            widget.orderType == "Takeaway".tr()) &&
        story.takeaway) {
      if (story.hasVideo) {
        if (story.isMediaProcessing) {
          // Bunny Stream is still transcoding this upload — there is no
          // playable URL yet, so show an explanatory placeholder instead of
          // trying (and failing) to play an empty/not-yet-ready video.
          items.add(StoryItem.text(
            title: 'This video is still processing. Please check back shortly.'.tr(),
            backgroundColor: Colors.black,
            duration: const Duration(seconds: 4),
          ));
        } else {
          for (final url in story.videoUrl) {
            final urlStr = url.toString();
            if (urlStr.isNotEmpty) {
              // Default 10 s — will be corrected to actual video length by
              // StoryVideo → StoryController.notifyDuration → StoryViewState.
              items.add(StoryItem.pageVideo(
                urlStr,
                controller: _controller,
                requestHeaders: const {
                  'Referer': 'https://admin.quickdash.co.in',
                },
                loadingWidget: _videoLoadingWidget(),
              ));
            }
          }
        }
      } else if (story.hasImage) {
        for (final url in story.imageUrl) {
          final urlStr = url.toString();
          items.add(StoryItem.pageImage(
            url: urlStr,
            controller: _controller,
            imageFit: BoxFit.contain,
            duration: const Duration(seconds: 5),
            loadingWidget: _imageLoadingWidget(urlStr),
          ));
        }
      }
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      // Nothing to show — advance immediately (skip this vendor).
      WidgetsBinding.instance
          .addPostFrameCallback((_) => widget.onComplete());
      return const SizedBox.shrink();
    }

    final topPad = MediaQuery.of(context).viewPadding.top;

    return Stack(
      children: [
        // ── Story content ────────────────────────────────────────────────
        StoryView(
          storyItems: _items,
          controller: _controller,
          progressPosition: ProgressPosition.top,
          repeat: false,
          onComplete: _handleComplete,
          onStoryShow: (storyItem, index) {
            // Always cancel any running timer so that switching to a new item
            // within the same vendor page resets the countdown.
            _viewTimer?.cancel();
            _viewTimer = null;
            // Image / text stories: content is served from cache (sub-100 ms),
            // so start the 3-second timer immediately.
            // Video stories: durationNotifier fires in _durationSub once the
            // HLS controller has finished initialising — the timer starts there
            // so loading time is never counted toward the 3-second threshold.
            final isVideoStory =
                widget.story.hasVideo && !widget.story.isMediaProcessing;
            if (!isVideoStory) {
              _viewTimer = Timer(const Duration(seconds: 1), _recordView);
            }
          },
          onVerticalSwipeComplete: (direction) {
            if (direction == Direction.down) widget.onClose();
          },
          indicatorHeight: IndicatorHeight.small,
          indicatorOuterPadding: EdgeInsets.only(
            left: 12,
            right: 12,
            top: topPad + 6,
            bottom: 0,
          ),
        ),

        // ── Top gradient scrim (behind vendor header) ────────────────────
        Positioned(
          top: 0, left: 0, right: 0,
          height: topPad + 140,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xCC000000), Colors.transparent],
              ),
            ),
          ),
        ),

        // ── Vendor header ────────────────────────────────────────────────
        Positioned(
          top: topPad + 50,
          left: 16,
          right: 56,
          child: _VendorHeader(
            vendorId: widget.story.vendorID.toString(),
            storyController: _controller,
          ),
        ),

        // ── Close button ─────────────────────────────────────────────────
        Positioned(
          top: topPad + 8,
          right: 12,
          child: GestureDetector(
            onTap: widget.onClose,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25), width: 1),
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vendor header — avatar + name + rating + "Visit" chip
// ─────────────────────────────────────────────────────────────────────────────

class _VendorHeader extends StatelessWidget {
  final String vendorId;
  final StoryController storyController;

  const _VendorHeader({
    required this.vendorId,
    required this.storyController,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VendorModel?>(
      future: FireStoreUtils.getVendor(vendorId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSkeleton();
        }
        if (snapshot.hasError || snapshot.data == null) {
          return const SizedBox.shrink();
        }
        final vendor = snapshot.data!;
        return GestureDetector(
          onTap: () {
            storyController.pause();
            BehaviorTracker.setNextEntrySource('Story');
            push(context, NewVendorProductsScreen(vendorModel: vendor));
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.85), width: 2),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8)
                  ],
                ),
                child: ClipOval(
                  child: NetworkImageWidget(
                    imageUrl: vendor.photo.toString(),
                    width: 44, height: 44,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Name + rating
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      vendor.title.toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontFamily: AppThemeData.semiBold,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: Color(0xFFFBBC05), size: 13),
                        const SizedBox(width: 3),
                        Text(
                          "${calculateReview(reviewCount: vendor.reviewsCount.toString(), reviewSum: vendor.reviewsSum.toString())} reviews",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                            fontFamily: AppThemeData.medium,
                            shadows: const [
                              Shadow(color: Colors.black38, blurRadius: 4)
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Visit chip
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35), width: 1),
                ),
                child: Text(
                  'Visit'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontFamily: AppThemeData.semiBold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSkeleton() {
    return Row(
      children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.2)),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 13, width: 120,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6)),
            ),
            const SizedBox(height: 6),
            Container(
              height: 10, width: 80,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5)),
            ),
          ],
        ),
      ],
    );
  }
}
