import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';

import '../controller/story_controller.dart';
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

    final stream = DefaultCacheManager()
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
  VideoPlayerController? _playerController;

  bool _isLoading = true;
  bool _isBuffering = false;
  bool _hasError = false;

  // Guards so we fire each event exactly once per video load.
  bool _durationReported = false;
  bool _endReported = false;

  @override
  void initState() {
    super.initState();
    widget.storyController?.pause();
    _loadVideo();
  }

  // ─── Loading ─────────────────────────────────────────────────────────────

  void _loadVideo() {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
      _durationReported = false;
      _endReported = false;
    });

    widget.videoLoader.loadVideo(() {
      if (!mounted) return;
      if (widget.videoLoader.state == LoadState.success) {
        _initPlayer();
      } else {
        setState(() { _isLoading = false; _hasError = true; });
      }
    });
  }

  Future<void> _initPlayer() async {
    try {
      final controller =
          VideoPlayerController.file(widget.videoLoader.videoFile!);
      await controller.initialize();

      if (!mounted) { controller.dispose(); return; }

      _playerController = controller;

      // ── Report actual duration so the progress bar matches exactly ──────
      final actualDuration = controller.value.duration;
      if (!_durationReported && actualDuration > Duration.zero) {
        _durationReported = true;
        widget.storyController?.notifyDuration(actualDuration);
      }

      controller.addListener(_onPlayerValue);

      // Mirror playback-state stream onto the video player.
      _playbackSubscription =
          widget.storyController?.playbackNotifier.listen((state) {
        if (!mounted || _playerController == null) return;
        if (state == PlaybackState.pause) {
          _playerController!.pause();
        } else if (state == PlaybackState.play) {
          _playerController!.play();
        }
      });

      setState(() { _isLoading = false; _hasError = false; });

      // Start playback — the animation controller in StoryView will now be
      // driven by the corrected duration.
      widget.storyController?.play();
    } catch (_) {
      if (!mounted) return;
      setState(() { _isLoading = false; _hasError = true; });
    }
  }

  // ─── Player value listener ────────────────────────────────────────────────

  void _onPlayerValue() {
    if (_playerController == null || !mounted) return;
    final v = _playerController!.value;

    // Buffering — pause the story timer while buffering, resume when done.
    if (v.isBuffering != _isBuffering) {
      setState(() => _isBuffering = v.isBuffering);
      if (v.isBuffering) {
        widget.storyController?.pause();
      } else if (v.isPlaying) {
        widget.storyController?.play();
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
    _playbackSubscription?.cancel();
    _playbackSubscription = null;
    _playerController?.removeListener(_onPlayerValue);
    _playerController?.dispose();
    _playerController = null;
    // Reset loader so it re-fetches from cache / network.
    widget.videoLoader.videoFile = null;
    widget.videoLoader.state = LoadState.loading;
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

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Full-screen contain: shows the complete video frame, no crop ──
        Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: _playerController!.value.size.width,
              height: _playerController!.value.size.height,
              child: VideoPlayer(_playerController!),
            ),
          ),
        ),

        // ── Buffering overlay ──────────────────────────────────────────────
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
    _playbackSubscription?.cancel();
    _playerController?.removeListener(_onPlayerValue);
    _playerController?.dispose();
    super.dispose();
  }
}
