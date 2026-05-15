import 'dart:async';
import 'dart:io';

import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

class FullScreenVideoViewer extends StatefulWidget {
  final String videoUrl;
  final String heroTag;
  final File? videoFile;

  const FullScreenVideoViewer(
      {Key? key, required this.videoUrl, required this.heroTag, this.videoFile})
      : super(key: key);

  @override
  _FullScreenVideoViewerState createState() => _FullScreenVideoViewerState();
}

class _FullScreenVideoViewerState extends State<FullScreenVideoViewer>
    with SingleTickerProviderStateMixin {
  late VideoPlayerController _controller;
  bool _showControls = true;
  bool _muted = false;
  Timer? _hideTimer;
  late AnimationController _fadeCtrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200), value: 1);
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut);

    _controller = widget.videoFile == null
        ? VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
        : VideoPlayerController.file(widget.videoFile!);

    _controller.initialize().then((_) {
      setState(() {});
      _controller.play();
      _startHideTimer();
    });
    _controller.setLooping(true);
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _hideTimer?.cancel();
    _fadeCtrl.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() => _showControls = false);
        _fadeCtrl.reverse();
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _fadeCtrl.forward();
      _startHideTimer();
    } else {
      _fadeCtrl.reverse();
    }
  }

  void _togglePlayPause() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _hideTimer?.cancel();
        setState(() => _showControls = true);
        _fadeCtrl.forward();
      } else {
        _controller.play();
        _startHideTimer();
      }
    });
  }

  void _toggleMute() {
    setState(() {
      _muted = !_muted;
      _controller.setVolume(_muted ? 0 : 1);
    });
    _startHideTimer();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final initialized = _controller.value.isInitialized;
    final isPlaying = _controller.value.isPlaying;
    final isBuffering = _controller.value.isBuffering;
    final position = _controller.value.position;
    final duration = _controller.value.duration;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video
            Center(
              child: Hero(
                tag: widget.heroTag,
                child: initialized
                    ? AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: VideoPlayer(_controller),
                      )
                    : const SizedBox.shrink(),
              ),
            ),

            // Loading spinner
            if (!initialized || isBuffering)
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 2.5,
                    ),
                  ),
                ),
              ),

            // Error state
            if (_controller.value.hasError)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.white54, size: 52),
                    const SizedBox(height: 12),
                    Text(
                      'Failed to load video',
                      style: TextStyle(color: Colors.white60, fontSize: 14, fontFamily: AppThemeData.regular),
                    ),
                  ],
                ),
              ),

            // Controls overlay
            if (initialized)
              FadeTransition(
                opacity: _fade,
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.35),
                    child: Column(
                      children: [
                        // Top bar
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
                            ),
                          ),
                          padding: EdgeInsets.fromLTRB(8, MediaQuery.of(context).padding.top + 4, 8, 20),
                          child: Row(
                            children: [
                              _iconBtn(Icons.arrow_back_ios_new_rounded, () => Navigator.pop(context)),
                              const Spacer(),
                              _iconBtn(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, _toggleMute),
                            ],
                          ),
                        ),
                        // Center play/pause
                        Expanded(
                          child: Center(
                            child: GestureDetector(
                              onTap: _togglePlayPause,
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
                                ),
                                child: Icon(
                                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 34,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Bottom seek bar
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                            ),
                          ),
                          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Seek slider
                              SliderTheme(
                                data: SliderThemeData(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                  activeTrackColor: AppThemeData.primary500,
                                  inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                                  thumbColor: Colors.white,
                                  overlayColor: Colors.white.withValues(alpha: 0.15),
                                ),
                                child: Slider(
                                  value: duration.inMilliseconds > 0
                                      ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
                                      : 0.0,
                                  onChanged: (v) {
                                    _controller.seekTo(Duration(
                                      milliseconds: (v * duration.inMilliseconds).round(),
                                    ));
                                    _startHideTimer();
                                  },
                                ),
                              ),
                              // Time row
                              Row(
                                children: [
                                  Text(
                                    _formatDuration(position),
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: AppThemeData.medium),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _formatDuration(duration),
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12, fontFamily: AppThemeData.regular),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}
