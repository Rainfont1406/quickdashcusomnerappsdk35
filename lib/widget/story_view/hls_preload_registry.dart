import 'package:video_player/video_player.dart';

/// Holds pre-initialized [VideoPlayerController]s for HLS story videos.
///
/// MoreStoriesState pre-initializes the next vendor's HLS video at 30% of the
/// current story. StoryVideoState picks it up here, skipping the expensive
/// initialize() call and eliminating the loading spinner between stories.
class HlsPreloadRegistry {
  HlsPreloadRegistry._();

  static final Map<String, VideoPlayerController> _controllers = {};

  /// Claim a pre-initialized controller for [url]. Returns null if none exists.
  /// Caller takes ownership — must call dispose() when done.
  static VideoPlayerController? take(String url) => _controllers.remove(url);

  /// Store a fully-initialized controller. Any previous entry for [url] is disposed.
  static void store(String url, VideoPlayerController controller) {
    _controllers.remove(url)?.dispose();
    _controllers[url] = controller;
  }

  /// Dispose all cached controllers. Call when the story viewer closes.
  static void disposeAll() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
  }
}
