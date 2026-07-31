import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../story_cache_manager.dart' show StoryImageCacheManager;
import '../utils.dart';
import '../controller/story_controller.dart';

/// Utitlity to load image (gif, png, jpg, etc) media just once. Resource is
/// cached to disk with default configurations of [DefaultCacheManager].
class ImageLoader {
  ui.Codec? frames;

  String url;

  Map<String, dynamic>? requestHeaders;

  LoadState state = LoadState.loading; // by default

  ImageLoader(this.url, {this.requestHeaders});

  /// Load image from disk cache first, if not found then load from network.
  /// `onComplete` is called when [imageBytes] become available.
  void loadImage(VoidCallback onComplete) {
    // TEMPORARY [STORY-PERF] - timing instrumentation for the story-loading
    // investigation. Remove once done.
    final sw = Stopwatch()..start();
    debugPrint('[STORY-PERF][IMG] START — $url');

    if (frames != null) {
      state = LoadState.success;
      debugPrint('[STORY-PERF][IMG] already-cached-in-memory — $url');
      onComplete();
    }

    final fileStream = StoryImageCacheManager.instance.getFileStream(url,
        headers: requestHeaders as Map<String, String>?);

    fileStream.listen(
      (fileResponse) {
        if (fileResponse is! FileInfo) return;
        // the reason for this is that, when the cache manager fetches
        // the image again from network, the provided `onComplete` should
        // not be called again
        if (frames != null) {
          return;
        }

        final imageBytes = fileResponse.file.readAsBytesSync();

        state = LoadState.success;

        ui.instantiateImageCodec(imageBytes).then((codec) {
          frames = codec;
          debugPrint('[STORY-PERF][IMG] DECODE-COMPLETE — ${sw.elapsedMilliseconds}ms — $url');
          onComplete();
        }, onError: (error) {
          state = LoadState.failure;
          debugPrint('[STORY-PERF][IMG] DECODE-ERROR — ${sw.elapsedMilliseconds}ms — $url — $error');
          onComplete();
        });
      },
      onError: (error) {
        state = LoadState.failure;
        debugPrint('[STORY-PERF][IMG] FETCH-ERROR — ${sw.elapsedMilliseconds}ms — $url — $error');
        onComplete();
      },
    );
  }
}

/// Widget to display animated gifs or still images. Shows a loader while image
/// is being loaded. Listens to playback states from [controller] to pause and
/// forward animated media.
class StoryImage extends StatefulWidget {
  final ImageLoader imageLoader;

  final BoxFit? fit;

  final StoryController? controller;
  final Widget? loadingWidget;
  final Widget? errorWidget;

  StoryImage(
    this.imageLoader, {
    Key? key,
    this.controller,
    this.fit,
    this.loadingWidget,
    this.errorWidget,
  }) : super(key: key ?? UniqueKey());

  /// Use this shorthand to fetch images/gifs from the provided [url]
  factory StoryImage.url(
    String url, {
    StoryController? controller,
    Map<String, dynamic>? requestHeaders,
    BoxFit fit = BoxFit.fitWidth,
    Widget? loadingWidget,
    Widget? errorWidget,
    Key? key,
  }) {
    return StoryImage(
        ImageLoader(
          url,
          requestHeaders: requestHeaders,
        ),
        controller: controller,
        fit: fit,
        loadingWidget: loadingWidget,
        errorWidget: errorWidget,
        key: key,
    );
  }

  @override
  State<StatefulWidget> createState() => StoryImageState();
}

class StoryImageState extends State<StoryImage> {
  ui.Image? currentFrame;

  Timer? _timer;
  Timer? _errorTimer; // auto-advances after a delay when image load fails

  StreamSubscription<PlaybackState>? _streamSubscription;

  @override
  void initState() {
    super.initState();

    if (widget.controller != null) {
      _streamSubscription =
          widget.controller!.playbackNotifier.listen((playbackState) {
        if (widget.imageLoader.frames == null) {
          // Image still loading — re-pause if the parent plays prematurely
          // (e.g. isActive flip while cache-fetch is in progress) so the
          // StoryView progress bar doesn't advance before the image is ready.
          if (playbackState == PlaybackState.play) {
            widget.controller!.pause();
          }
          return;
        }

        // GIF playback control.
        if (playbackState == PlaybackState.pause) {
          _timer?.cancel();
        } else {
          forward();
        }
      });
    }

    widget.controller?.pause();

    widget.imageLoader.loadImage(() async {
      if (mounted) {
        if (widget.imageLoader.state == LoadState.success) {
          widget.controller?.play();
          forward();
        } else {
          setState(() {});
          // Auto-advance after 6 s so a network failure never traps the user
          // on a broken story slot forever.
          _errorTimer = Timer(const Duration(seconds: 6), () {
            if (mounted) widget.controller?.next();
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _errorTimer?.cancel();
    _streamSubscription?.cancel();

    super.dispose();
  }

  @override
  void setState(fn) {
    if (mounted) {
      super.setState(fn);
    }
  }

  void forward() async {
    _timer?.cancel();

    if (widget.controller != null &&
        widget.controller!.playbackNotifier.stream.value ==
            PlaybackState.pause) {
      return;
    }

    final nextFrame = await widget.imageLoader.frames!.getNextFrame();

    currentFrame = nextFrame.image;

    if (nextFrame.duration > const Duration(milliseconds: 0)) {
      _timer = Timer(nextFrame.duration, forward);
    }

    setState(() {});
  }

  Widget getContentView() {
    switch (widget.imageLoader.state) {
      case LoadState.success:
        return RawImage(
          image: currentFrame,
          fit: widget.fit,
        );
      case LoadState.failure:
        return Center(
            child: widget.errorWidget?? const Text(
          "Image failed to load.",
          style: TextStyle(
            color: Colors.white,
          ),
        ));
      default:
        return Center(
          child: widget.loadingWidget?? const SizedBox(
            width: 70,
            height: 70,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              strokeWidth: 3,
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: getContentView(),
    );
  }
}
