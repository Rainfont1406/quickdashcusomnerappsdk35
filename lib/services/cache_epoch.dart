import 'package:emartconsumer/services/perf_diagnostic_file_service.dart' show perfDiagnosticCacheManager;
import 'package:emartconsumer/services/chat_video_cache.dart';
import 'package:emartconsumer/services/app_cache_config.dart';
import 'package:emartconsumer/widget/story_view/story_cache_manager.dart'
    show StoryImageCacheManager, StoryVideoCacheManager;
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remote kill switch for the on-device picture and story-video caches
/// (2026-10-03).
///
/// WHY: pictures are cached for up to 60 days and treated as unchangeable
/// (every upload gets a new random address). If a picture is ever replaced
/// IN PLACE at the same address, or a bad file gets cached, phones would keep
/// showing the old one. This lets the owner clear every phone's picture and
/// video cache without shipping a release.
///
/// HOW: set the Remote Config number `clear_cache_epoch` to a value higher
/// than the previous one (e.g. 1, then 2, ...). The first time a phone sees
/// a value above the one it last applied, it empties the picture cache, the
/// story picture and video caches and the in-memory picture cache, then
/// remembers the value. Leaving it unset or lowering it does nothing.
///
/// Called from ForceUpdateGate right after Remote Config is fetched (app start
/// and resume after 30 minutes), so it adds no extra network call. Failures
/// are swallowed: this must never block the app.
class CacheEpoch {
  CacheEpoch._();

  static const String _remoteKey = 'clear_cache_epoch';
  static const String _prefKey = 'cache_epoch_applied';

  static Future<void> applyIfChanged(FirebaseRemoteConfig remoteConfig) async {
    try {
      final remote = remoteConfig.getInt(_remoteKey);
      final prefs = await SharedPreferences.getInstance();
      final applied = prefs.getInt(_prefKey) ?? 0;
      if (remote <= applied) return;

      await AppCacheConfig.images.emptyCache();
      await StoryImageCacheManager.instance.emptyCache();
      await StoryVideoCacheManager.instance.emptyCache();
      await ChatVideoCacheManager.instance.emptyCache();
      await perfDiagnosticCacheManager.emptyCache();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await prefs.setInt(_prefKey, remote);
      debugPrint('[CacheEpoch] clear_cache_epoch $applied -> $remote: '
          'picture and story caches emptied');
    } catch (e) {
      debugPrint('[CacheEpoch] check failed (ignored): $e');
    }
  }
}
