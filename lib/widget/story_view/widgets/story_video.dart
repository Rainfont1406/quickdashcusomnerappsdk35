import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';

import '../story_cache_manager.dart' show StoryVideoCacheManager;
import '../controller/story_controller.dart';
import '../hls_preload_registry.dart';
import '../utils.dart';

class VideoLoader {
  final String url;
  final Map<String, dynamic>? requestHeaders;

  File? videoFile;
  LoadState state = LoadState.loading;

  VideoLoader(this.url, {this.requestHeaders});

  void loadVideo(VoidCallback onComplete) {
    if (videoFile != null) {
      state = LoadState.success;
      onComplete();
      return;
    }

    final stream = StoryVideoCacheManager.instance
        .getFileStream(url, headers: requestHeaders as Map<String, String>?);

    stream.listen(
      (fileResponse) {
        if (fileResponse is FileInfo && videoFile == null) {
          state = LoadState.success;
          videoFile = fileResponse.file;
          onComplete();
        }
      },
      onError: (_) {
        state = LoadState.failure;
        onComplete();
      },
    );
  }
}

class StoryVideo extends StatefulWidget {
  final StoryController? storyController;
  final VideoLoader videoLoader;
  final Widget? loadingWidget;
  final Widget? errorWidget;

  StoryVideo(this.videoLoader, {
    Key? key,
    this.storyController,
    this.loadingWidget,
    this.errorWidget,
  }) : super(key: key ?? UniqueKey());

  static StoryVideo url(String url, {
    StoryController? controller,
    Map<String, dynamic>? requestHeaders,
    Key? key,
    Widget? loadingWidget,
    Widget? errorWidget,
  }) {
    return StoryVideo(
      VideoLoader(url, requestHeaders: requestHeaders),
      storyController: controller,
      key: key,
      loadingWidget: loadingWidget,
      errorWidget: errorWidget,
    );
  }

  @override
  State<StatefulWidget> createState() => StoryVideoState();
}

class StoryVideoState extends State<StoryVideo> {
  StreamSubscription<PlaybackState>? _playbackSubscription;
  // Subscribed during initialization only; re-pauses the story timer if the
  // parent calls play() before the video controller is ready (e.g. when the
  // user swipes to this vendor while the HLS stream is still buffering).
  StreamSubscription<PlaybackState>? _loadingGuardSub;
  VideoPlayerController? _playerController;

  bool _isLoading = true;
  bool _isBuffering = false;
  bool _hasError = false;

  // True while we are waiting for an initial/mid-story buffer fill.
  // While this flag is set, pause events from storyController must NOT be
  // forwarded to the video player — the native player needs to keep
  // downloading in the background so it can resume as soon as the buffer
  // fills. Without this guard, pausing the player stops the download and
  // the video never recovers (especially visible on iOS/AVPlayer).
  bool _pausedForBuffering = false;

  // Guards so we fire each event exactly once per video load.
  bool _durationReported = false;
  bool _endReported = false;

  // TEMPORARY [STORY-PERF] - timing instrumentation for the story-loading
  // investigation. Remove once done.
  Stopwatch? _loadSw;

  @override
  void initState() {
    super.initState();
    widget.storyController?.pause();
    _armLoadingGuard();
    _loadVideo();
  }

  // Subscribes a guard that re-pauses the story controller whenever play()
  // arrives while _isLoading is still true. Called in initState and _retry so
  // the bar stays frozen during the full async initialize() window each time.
  void _armLoadingGuard() {
    _loadingGuardSub?.cancel();
    _loadingGuardSub = widget.storyController?.playbackNotifier.listen((state) {
      if (_isLoading && state == PlaybackState.play) {
        widget.storyController?.pause();
      }
    });
  }

  // ─── Loading ─────────────────────────────────────────────────────────────

  // HLS manifests (Bunny Stream's playlist.m3u8) reference many segment
  // files — flutter_cache_manager would just download the few-hundred-byte
  // manifest text and hand it to VideoPlayerController.file(), which can't
  // play it. Those need native HLS streaming instead of download-then-play.
  bool get _isHlsUrl => widget.videoLoader.url.toLowerCase().contains('.m3u8');

  void _loadVideo() {
    if (!mounted) return;
    _loadSw = Stopwatch()..start();
    debugPrint('[STORY-PERF][VIDEO] START (isHls=$_isHlsUrl) — ${widget.videoLoader.url}');
    setState(() {
      _isLoading = true;
      _hasError = false;
      _durationReported = false;
      _endReported = false;
    });

    if (_isHlsUrl) {
      _initPlayer(networkUrl: widget.videoLoader.url);
      return;
    }

    widget.videoLoader.loadVideo(() {
      if (!mounted) return;
      if (widget.videoLoader.state == LoadState.success) {
        _initPlayer();
      } else {
        setState(() { _isLoading = false; _hasError = true; });
      }
    });
  }

  Future<void> _initPlayer({String? networkUrl}) async {
    // NOTE: do NOT cancel _loadingGuardSub here — it must stay active through
    // the await below so a mid-load isActive flip (user swipes to this vendor
    // while HLS is still initialising) cannot start the progress bar early.

    try {
      // Convert Map<String,dynamic>? → Map<String,String> safely; a bare `as`
      // cast from Map<String,dynamic> to Map<String,String> throws TypeError at
      // runtime in Dart's reified generics even when all values are strings.
      final Map<String, String> headers =
          widget.videoLoader.requestHeaders?.map(
                (k, v) => MapEntry(k, v.toString()),
              ) ??
              const {};

      VideoPlayerController controller;
      if (networkUrl != null) {
        // For HLS streams: check whether MoreStoriesState already pre-initialized
        // this controller at the 30% prefetch point. If so, skip initialize() —
        // the native HLS player has already buffered the first segments.
        final preloaded = HlsPreloadRegistry.take(networkUrl);
        if (preloaded != null && preloaded.value.isInitialized) {
          controller = preloaded;
        } else {
          preloaded?.dispose(); // discard a failed/stale entry
          controller = VideoPlayerController.networkUrl(
            Uri.parse(networkUrl),
            httpHeaders: headers,
          );
          await controller.initialize(); // guard stays alive during this await
        }
      } else {
        controller = VideoPlayerController.file(widget.videoLoader.videoFile!);
        await controller.initialize();
      }

      if (!mounted) { controller.dispose(); return; }

      _playerController = controller;

      // Initialisation is complete — disarm the loading guard and arm the real
      // playback-state subscription. Cancelling here (not at the top of the
      // function) guarantees the guard was active for the entire initialize()
      // call, so no premature play() could have advanced the progress bar.
      _loadingGuardSub?.cancel();
      _loadingGuardSub = null;

      // ── Report actual duration so the progress bar matches exactly ──────
      final actualDuration = controller.value.duration;
      if (!_durationReported && actualDuration > Duration.zero) {
        _durationReported = true;
        widget.storyController?.notifyDuration(actualDuration);
      }

      controller.addListener(_onPlayerValue);

      // Mirror playback-state stream onto the video player.
      // Exception: while we are waiting for a buffer fill (_pausedForBuffering),
      // skip the pause so the native player keeps downloading segments.
      _playbackSubscription =
          widget.storyController?.playbackNotifier.listen((state) {
        if (!mounted || _playerController == null) return;
        if (state == PlaybackState.pause) {
          if (!_pausedForBuffering) _playerController!.pause();
        } else if (state == PlaybackState.play) {
          _playerController!.play();
        }
      });

      setState(() { _isLoading = false; _hasError = false; });
      debugPrint('[STORY-PERF][VIDEO] READY-TO-PLAY — ${_loadSw?.elapsedMilliseconds}ms — ${widget.videoLoader.url}');

      // Start playback — the animation controller in StoryView will now be
      // driven by the corrected duration.
      widget.storyController?.play();
    } catch (e, st) {
      debugPrint('StoryVideo._initPlayer error: $e\n$st');
      debugPrint('[STORY-PERF][VIDEO] ERROR — ${_loadSw?.elapsedMilliseconds}ms — ${widget.videoLoader.url}');
      if (!mounted) return;
      setState(() { _isLoading = false; _hasError = true; });
      // Freeze the progress bar so it does not auto-advance while the error
      // widget is visible (the 10-second default duration would otherwise
      // silently skip the vendor's story slot as if it had played).
      widget.storyController?.pause();
    }
  }

  // ─── Player value listener ────────────────────────────────────────────────

  void _onPlayerValue() {
    if (_playerController == null || !mounted) return;
    final v = _playerController!.value;

    // Buffering — pause the STORY TIMER while the native player buffers, then
    // resume when the buffer fills. The video player itself is NOT paused so
    // the native codec keeps downloading segments in the background.
    if (v.isBuffering != _isBuffering) {
      setState(() => _isBuffering = v.isBuffering);
      if (v.isBuffering) {
        _pausedForBuffering = true;
        widget.storyController?.pause(); // _playbackSubscription skips player.pause()
        widget.storyController?.notifyBuffering(true);
      } else {
        _pausedForBuffering = false;
        widget.storyController?.play();
        widget.storyController?.notifyBuffering(false);
      }
    }

    // ── End-of-video detection ──────────────────────────────────────────
    // Fire next() when the video has genuinely finished (isPlaying went
    // false AND position reached the end), so there is ZERO black screen.
    if (!_endReported &&
        v.isInitialized &&
        v.duration > Duration.zero &&
        !v.isPlaying &&
        !v.isBuffering &&
        v.position >= v.duration - const Duration(milliseconds: 150)) {
      _endReported = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.storyController?.next();
      });
    }
  }

  // ─── Retry ───────────────────────────────────────────────────────────────

  void _retry() {
    _pausedForBuffering = false;
    _playbackSubscription?.cancel();
    _playbackSubscription = null;
    _playerController?.removeListener(_onPlayerValue);
    _playerController?.dispose();
    _playerController = null;
    // Reset loader so it re-fetches from cache / network.
    widget.videoLoader.videoFile = null;
    widget.videoLoader.state = LoadState.loading;
    // Re-freeze the bar and re-arm the guard for the new loading cycle.
    widget.storyController?.pause();
    _armLoadingGuard();
    _loadVideo();
  }

  // ─── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_hasError) return _buildErrorState();
    if (_isLoading ||
        _playerController == null ||
        !_playerController!.value.isInitialized) {
      return _buildLoadingState();
    }

    final size = _playerController!.value.size;
    final videoChild = size.width > 0 && size.height > 0
        ? Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: VideoPlayer(_playerController!),
              ),
            ),
          )
        : SizedBox.expand(child: VideoPlayer(_playerController!));

    return Stack(
      fit: StackFit.expand,
      children: [
        videoChild,

        // Buffering overlay — shown when the native player stalls mid-play.
        if (_isBuffering)
          Container(
            color: Colors.black.withValues(alpha: 0.35),
            child: Center(
              child: SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white.withValues(alpha: 0.9),
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return widget.loadingWidget ??
        Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white.withValues(alpha: 0.9),
              backgroundColor: Colors.white.withValues(alpha: 0.15),
            ),
          ),
        );
  }

  Widget _buildErrorState() {
    return widget.errorWidget ??
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded,
                  color: Colors.white.withValues(alpha: 0.6), size: 42),
              const SizedBox(height: 14),
              Text(
                'Failed to load video',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                  fontFamily: 'RadioCanadaBig-Medium',
                ),
              ),
              const SizedBox(height: 18),
              GestureDetector(
                onTap: _retry,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3), width: 1),
                  ),
                  child: Text(
                    'Tap to retry',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                      fontFamily: 'RadioCanadaBig-Medium',
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
  }

  // ─── Lifecycle ───────────────────────────────────────────────────────────

  @override
  void dispose() {
    _loadingGuardSub?.cancel();
    _playbackSubscription?.cancel();
    _playerController?.removeListener(_onPlayerValue);
    _playerController?.dispose();
    super.dispose();
  }
}
