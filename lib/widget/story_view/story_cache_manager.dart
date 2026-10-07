import 'package:emartconsumer/services/app_cache_config.dart'
    show ImmutableFileService;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Cache for story images (JPEG/PNG/GIF).
/// 50 files × ~1 MB avg ≈ 50 MB ceiling. 24-hour TTL matches story expiry.
class StoryImageCacheManager {
  static const cacheKey = 'storyImageCache';

  // 2026-10-07: the Config is kept (not built inline) so ImageOrphanSweeper can
  // read this cache's database and folder.
  static final Config config = Config(
    cacheKey,
    stalePeriod: const Duration(hours: 24),
    maxNrOfCacheObjects: 50,
  );

  static final CacheManager instance = CacheManager(config);
}

/// Rolling disk cache for story videos (2026-10-03).
///
/// Bunny Stream HLS (.m3u8) cannot be cached (the player streams it as many
/// chunks and keeps no copy), so a Bunny story video is played from its
/// 480p MP4 copy instead: [mp4UrlFor]. Bunny's 480p rendition is capped at
/// 1,400 kbps (about 0.175 MB/s), so a story of up to 20 s (the admin
/// `videoDuration` cap) is at most about 3.5 MB; [maxFiles] files stay
/// under about 70 MB.
///
/// Rolling: when a new video is stored beyond [maxFiles], the least recently
/// used file is evicted. A file also leaves the cache when unused for
/// [stalePeriod] (a story lives 14 days at most, backstopMaxDays).
///
/// Validity: every Bunny video has its own GUID in the URL, so the bytes behind
/// a URL never change; [ImmutableFileService] therefore treats a download as
/// valid for a year (no daily re-check). Which stories are shown, and when they
/// expire (views used up, 14-day cap, deleted, un-approved), is decided by the
/// story list (StoryModel.isExpired + the 6-hour StoryCache refresh); this cache
/// only supplies bytes for stories that list already allows. View counting is a
/// separate Firestore write and is unaffected by a cache hit.
class StoryVideoCacheManager {
  static const cacheKey = 'storyVideoCache';

  /// 20 files at most about 3.5 MB each (see class doc) = about 70 MB.
  static const int maxFiles = 20;

  /// A story lives at most 14 days (settings/story.backstopMaxDays).
  static const Duration stalePeriod = Duration(days: 14);

  // 2026-10-07: kept so ImageOrphanSweeper can read this cache's database.
  static final Config config = Config(
    cacheKey,
    stalePeriod: stalePeriod,
    maxNrOfCacheObjects: maxFiles,
    fileService: ImmutableFileService(),
  );

  static final CacheManager instance = CacheManager(config);

  /// The 480p MP4 copy of a Bunny Stream HLS playlist URL
  /// (`.../<guid>/playlist.m3u8` -> `.../<guid>/play_480p.mp4`), or null when
  /// [url] is not a Bunny playlist URL. The MP4 may not exist for every video
  /// (MP4 fallback encoding must be on, and the source must be 480p or larger),
  /// so callers fall back to the HLS URL when the download fails.
  static String? mp4UrlFor(String url) {
    final lower = url.toLowerCase();
    final i = lower.lastIndexOf('/playlist.m3u8');
    if (i < 0) return null;
    return '${url.substring(0, i)}/play_480p.mp4';
  }

  /// Drops a story's cached video once the story list no longer shows it, so
  /// the disk is not held by expired stories until the file cap evicts them.
  ///
  /// 2026-10-07: also deletes the file itself. flutter_cache_manager 3.4.1's
  /// removeFile (and its least-recently-used / stale / emptyCache cleanup) only
  /// drops the database row - its file lookup uses the bare relative path - so
  /// the video stayed on the phone with nothing left that knew about it.
  static Future<void> evictFor(String url) async {
    try {
      final mp4 = mp4UrlFor(url) ?? url;
      final hit = await instance.getFileFromCache(mp4, ignoreMemCache: true);
      await instance.removeFile(mp4);
      final f = hit?.file;
      if (f != null && await f.exists()) await f.delete();
    } catch (_) {}
  }
}
