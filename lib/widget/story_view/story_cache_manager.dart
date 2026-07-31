import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Cache for story images (JPEG/PNG/GIF).
/// 50 files × ~1 MB avg ≈ 50 MB ceiling. 24-hour TTL matches story expiry.
class StoryImageCacheManager {
  static const _cacheKey = 'storyImageCache';

  static final CacheManager instance = CacheManager(
    Config(
      _cacheKey,
      stalePeriod: const Duration(hours: 24),
      maxNrOfCacheObjects: 50,
    ),
  );
}

/// Cache for non-HLS story videos (MP4, WebM, etc.).
/// 5 files × ~30 MB avg ≈ 150 MB ceiling. 24-hour TTL matches story expiry.
///
/// Bunny Stream HLS (.m3u8) videos are NOT handled here — VideoLoader streams
/// those directly via VideoPlayerController.networkUrl and the platform's own
/// adaptive buffering manages their transient storage.
class StoryVideoCacheManager {
  static const _cacheKey = 'storyVideoCache';

  static final CacheManager instance = CacheManager(
    Config(
      _cacheKey,
      stalePeriod: const Duration(hours: 24),
      maxNrOfCacheObjects: 5,
    ),
  );
}
