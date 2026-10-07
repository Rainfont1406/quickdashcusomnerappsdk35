import 'package:emartconsumer/services/app_cache_config.dart' show ImmutableFileService;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 2026-10-07: disk cache for chat video messages.
///
/// Chat videos used to stream from Firebase Storage every time they were
/// opened (the video player keeps no copy), so every replay was downloaded
/// again at Firebase's egress price. They now live on Bunny Storage and a played
/// video is kept on the phone: [maxFiles] files, unused for [stalePeriod]
/// leaves the cache. The client compresses a chat video to 640x480 before
/// upload (about 1-2 MB per 10 s) and the server caps it at 25 MB, so the
/// folder stays small. Every upload gets a new random name, so the bytes
/// behind a URL never change ([ImmutableFileService]).
///
/// flutter_cache_manager 3.4.1 drops only the database row when it evicts, so
/// ImageOrphanSweeper also sweeps this folder daily.
class ChatVideoCacheManager {
  static const cacheKey = 'chatVideoCache';
  static const int maxFiles = 10;
  static const Duration stalePeriod = Duration(days: 14);

  static final Config config = Config(
    cacheKey,
    stalePeriod: stalePeriod,
    maxNrOfCacheObjects: maxFiles,
    fileService: ImmutableFileService(),
  );

  static final CacheManager instance = CacheManager(config);
}
