import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:emartconsumer/services/chat_video_cache.dart';
import 'package:emartconsumer/widget/story_view/story_cache_manager.dart';

// On-device cache ceilings (2026-09-10).
//
// Nothing here was literally unbounded before this file existed, but the
// ceilings were expressed in the wrong unit for this app's data. flutter_
// cache_manager caps by FILE COUNT, not bytes: cached_network_image's
// DefaultCacheManager allows 200 objects for 30 days. That is a sane ceiling
// for ~100 KB images and a bad one here — store photos were measured on
// 2026-09-10 averaging 1,247,482 bytes (largest 2.26 MB), because Bunny's
// image Optimizer is deliberately off, so the app receives full-resolution
// camera uploads. 200 × 1.25 MB is a ~250 MB on-device ceiling.
//
// Two separate limits matter and they are easy to conflate:
//   • DISK  — how many bytes sit in app storage between launches.
//   • MEMORY — how many bytes the decoded bitmaps occupy while on screen.
// The second is the sharper risk: a 2.26 MB JPEG is not 2.26 MB decoded, it
// is width × height × 4 bytes. A 4000×3000 photo decodes to ~48 MB of RAM,
// and Flutter's default in-memory ImageCache allows 1000 objects / 100 MB —
// so a handful of full-res vendor cards can dominate the heap on a low-end
// device regardless of how small the file was on disk.
//
// Story media already had correct, explicitly bounded managers before this
// (see story_cache_manager.dart — 50 images / 5 videos, both 24 h to match
// story expiry), so watching 100 stories has always evicted down to 50. This
// file covers everything else: vendor photos, banners, product images.

/// The class-modifier pattern flutter_cache_manager itself documents for
/// getting disk-side resize: ImageCacheManager is a mixin on
/// BaseCacheManager, not something CacheManager gets by default.
class AppImageCacheManager extends CacheManager with ImageCacheManager {
  AppImageCacheManager(super.config);

  /// 2026-10-05: also remembers which cache keys each image address used
  /// (the original under its url key, and the display-sized copy under
  /// `resized_w{w}_h{h}_{key}`), so ImageKeyRegistry.evict can later remove an
  /// expired or replaced picture from disk instead of leaving it to occupy a
  /// slot until the 60-day / 1000-file rule pushes it out.
  @override
  Stream<FileResponse> getImageFile(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
    int? maxHeight,
    int? maxWidth,
  }) {
    ImageKeyRegistry.note(key ?? url, maxWidth, maxHeight);
    return super.getImageFile(url,
        key: key,
        headers: headers,
        withProgress: withProgress,
        maxHeight: maxHeight,
        maxWidth: maxWidth);
  }
}

/// 2026-10-05: which cache keys belong to which image address, so a picture
/// that is no longer wanted (an expired Local Offer, a replaced banner) can be
/// deleted from the on-device cache. Kept in memory and saved (debounced) in
/// SharedPreferences; pictures cached before this existed are not listed and
/// simply age out by the normal 60-day / 1000-file rule. Every operation is
/// best-effort: a failure here must never affect showing an image.
class ImageKeyRegistry {
  static const String _prefKey = 'image_cache_keys_v1';
  // Upper bound on remembered addresses (oldest dropped first).
  static const int _maxBases = 2500;
  static Map<String, List<String>>? _map;
  static Future<void>? _loading;
  static Timer? _saveTimer;

  static Future<void> _ensureLoaded() {
    return _loading ??= () async {
      final map = <String, List<String>>{};
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_prefKey);
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          decoded.forEach((k, v) => map[k] = [for (final x in v as List) x.toString()]);
        }
      } catch (_) {}
      _map = map;
    }();
  }

  static void note(String baseKey, int? maxWidth, int? maxHeight) {
    unawaited(_note(baseKey, maxWidth, maxHeight));
  }

  static Future<void> _note(String baseKey, int? maxWidth, int? maxHeight) async {
    try {
      await _ensureLoaded();
      final map = _map!;
      var changed = false;
      final list = map.putIfAbsent(baseKey, () {
        changed = true;
        return <String>[];
      });
      if (maxWidth != null || maxHeight != null) {
        var rk = 'resized';
        if (maxWidth != null) rk += '_w$maxWidth';
        if (maxHeight != null) rk += '_h$maxHeight';
        rk += '_$baseKey';
        if (!list.contains(rk)) {
          list.add(rk);
          changed = true;
        }
      }
      if (map.length > _maxBases) {
        for (final k in map.keys.take(map.length - _maxBases).toList()) {
          map.remove(k);
        }
        changed = true;
      }
      if (changed) _scheduleSave();
    } catch (_) {}
  }

  static void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 5), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefKey, jsonEncode(_map));
      } catch (_) {}
    });
  }

  /// 2026-10-05: flutter_cache_manager 3.4.1's removeFile() deletes only the
  /// database row - its internal delete opens io.File(relativePath), a bare
  /// file name that is not inside the cache folder, so the picture itself
  /// stayed on disk (found on the test phone: 87 of 137 files, 65.8 MB, had no
  /// row). So: look the file up through the manager (it resolves the real path
  /// inside the cache folder), delete THAT file, then remove the row. If the
  /// file is already gone the stale row is still removed.
  static Future<void> _removeWithFile(CacheManager manager, String key) async {
    try {
      final info = await manager.getFileFromCache(key, ignoreMemCache: true);
      if (info != null) {
        try {
          if (await info.file.exists()) await info.file.delete();
        } catch (e) {
          debugPrint('ImageKeyRegistry: could not delete file for $key: $e');
        }
      }
    } catch (_) {}
    await manager.removeFile(key);
  }

  /// Deletes every remembered cache file whose address starts with one of
  /// [rawUrls] (the cache key is the raw address plus the width/quality query
  /// the app adds). Returns how many addresses were evicted.
  static Future<int> evict(CacheManager manager, Iterable<String> rawUrls) async {
    var evicted = 0;
    try {
      await _ensureLoaded();
      final map = _map!;
      final wanted = rawUrls.where((u) => u.isNotEmpty).toList();
      if (wanted.isEmpty) return 0;
      for (final base in map.keys.toList()) {
        if (!wanted.any(base.startsWith)) continue;
        for (final rk in map[base] ?? const <String>[]) {
          await _removeWithFile(manager, rk);
        }
        await _removeWithFile(manager, base);
        map.remove(base);
        evicted++;
      }
      if (evicted > 0) _scheduleSave();
    } catch (e) {
      debugPrint('ImageKeyRegistry.evict failed: $e');
    }
    return evicted;
  }
}

/// 2026-10-05: removes the cached pictures of a GROUP of addresses that are no
/// longer wanted (an expired Local Offer, a replaced vendor photo, a vendor
/// that left the list). Remembers the last full set of the group in
/// SharedPreferences, so a change made while the app was closed is caught on
/// the next load. Every group keeps its own saved set.
class ImageSetJanitor {
  /// [currentUrls] must be the FULL set of addresses the group shows right now
  /// (never a filtered or partial list). An empty set is ignored - a failed or
  /// offline load must never wipe the cache.
  static Future<void> sync(String group, Iterable<String> currentUrls) async {
    try {
      final current = currentUrls.where((u) => u.isNotEmpty).toSet();
      if (current.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final prefKey = 'image_set_$group';
      final previous = (prefs.getStringList(prefKey) ?? const <String>[]).toSet();
      final gone = previous.difference(current);
      if (gone.isNotEmpty) {
        final n = await ImageKeyRegistry.evict(AppCacheConfig.images, gone);
        debugPrint('ImageSetJanitor[$group]: ${gone.length} address(es) gone, $n evicted from cache');
      }
      await prefs.setStringList(prefKey, current.toList());
    } catch (e) {
      debugPrint('ImageSetJanitor[$group].sync failed: $e');
    }
  }
}

/// 2026-10-05: deletes ORPHAN files of the image cache: a file that sits
/// directly inside this cache's own folder AND that no row of this cache's
/// database references (left behind by the library's own eviction/expiry, which
/// deletes rows but not files). Conservative by design:
///  - only this cache's folder (its basename must be the cache key); never any
///    other path, never subfolders;
///  - only plain files older than [_minAge] (a download in progress may not
///    have its row yet);
///  - nothing is deleted if the database cannot be read or lists no rows at all
///    (an unreadable database must not turn every file into an "orphan");
///  - at most [_maxDeletesPerRun] files per run and at most one run per
///    [_every] (a flag in SharedPreferences, set only after a finished run).
class ImageOrphanSweeper {
  static const String _prefKey = 'image_orphan_sweep_at_v1';
  // Test-only switches: a build with --dart-define=SWEEP_EVERY_MIN=2
  // --dart-define=SWEEP_MIN_AGE_MIN=1 runs the sweep every 2 minutes on files
  // older than 1 minute. Release builds pass neither, so the defaults apply.
  static const Duration _every =
      Duration(minutes: int.fromEnvironment('SWEEP_EVERY_MIN', defaultValue: 24 * 60));
  static const Duration _minAge =
      Duration(minutes: int.fromEnvironment('SWEEP_MIN_AGE_MIN', defaultValue: 15));
  static const int _maxDeletesPerRun = 400;
  static bool _running = false;

  static Future<void> maybeRun() async {
    if (_running) return;
    _running = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_prefKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - last < _every.inMilliseconds) return;
      final ok = await _sweep();
      if (ok) await prefs.setInt(_prefKey, now);
    } catch (e) {
      debugPrint('ImageOrphanSweeper failed: $e');
    } finally {
      _running = false;
    }
  }

  /// Returns true when every folder was swept to completion (also when nothing
  /// was an orphan); false when one refused to run (then it is retried next
  /// time).
  static Future<bool> _sweep() async {
    // Restaurant / offer / product images first - it refuses to run on an empty
    // database (kept from the first version of this sweep).
    final imagesOk = await _sweepFolder(
      label: 'images',
      manager: AppCacheConfig.images,
      cfg: AppCacheConfig._imageConfig,
      expectedFolder: AppCacheConfig.imageCacheKey,
      refuseWhenNoRows: true,
    );
    // 2026-10-07: the story caches have the same problem (the library never
    // deletes the file when it drops a row - least-recently-used, stale,
    // emptyCache) and had no sweep at all. Their database may legitimately be
    // empty (everything expired), so an empty database is not a reason to stop.
    final videosOk = await _sweepFolder(
      label: 'story videos',
      manager: StoryVideoCacheManager.instance,
      cfg: StoryVideoCacheManager.config,
      expectedFolder: StoryVideoCacheManager.cacheKey,
      refuseWhenNoRows: false,
    );
    final storyImagesOk = await _sweepFolder(
      label: 'story images',
      manager: StoryImageCacheManager.instance,
      cfg: StoryImageCacheManager.config,
      expectedFolder: StoryImageCacheManager.cacheKey,
      refuseWhenNoRows: false,
    );
    // 2026-10-07: chat videos (own folder, may legitimately be empty).
    final chatVideosOk = await _sweepFolder(
      label: 'chat videos',
      manager: ChatVideoCacheManager.instance,
      cfg: ChatVideoCacheManager.config,
      expectedFolder: ChatVideoCacheManager.cacheKey,
      refuseWhenNoRows: false,
    );
    return imagesOk && videosOk && storyImagesOk && chatVideosOk;
  }

  static Future<bool> _sweepFolder({
    required String label,
    required CacheManager manager,
    required Config cfg,
    required String expectedFolder,
    required bool refuseWhenNoRows,
  }) async {
    // The cache database opens lazily on the manager's first use; reading it
    // before that threw "Null check operator" on the test phone. A lookup of
    // a key that cannot exist makes the manager open it (and returns null).
    await manager.getFileFromCache('orphan-sweep-warmup');
    final rows = await cfg.repo.getAllObjects();
    if (rows.isEmpty && refuseWhenNoRows) {
      debugPrint('ImageOrphanSweeper[$label]: database lists no rows - refusing to delete anything');
      return false;
    }
    final referenced = <String>{for (final r in rows) r.relativePath};
    final probe = await cfg.fileSystem.createFile('.orphan_probe');
    final dir = io.Directory(probe.parent.path);
    final dirName = dir.path.split(RegExp(r'[\\/]')).where((e) => e.isNotEmpty).last;
    if (dirName != expectedFolder) {
      debugPrint('ImageOrphanSweeper[$label]: unexpected folder "$dirName" - refusing to run');
      return false;
    }
    if (!await dir.exists()) return true;
    final cutoff = DateTime.now().subtract(_minAge);
    var seen = 0, deleted = 0, bytes = 0;
    await for (final e in dir.list(followLinks: false)) {
      if (e is! io.File) continue;
      seen++;
      final name = e.path.split(RegExp(r'[\\/]')).last;
      if (referenced.contains(name)) continue;
      try {
        final stat = await e.stat();
        if (stat.modified.isAfter(cutoff)) continue;
        if (deleted >= _maxDeletesPerRun) break;
        final len = stat.size;
        await e.delete();
        deleted++;
        bytes += len;
      } catch (_) {}
    }
    debugPrint('ImageOrphanSweeper[$label]: $seen files in folder, ${rows.length} database rows, '
        '$deleted orphan file(s) deleted, ${(bytes / 1048576).toStringAsFixed(1)} MB freed');
    return true;
  }
}

/// Local Offers: all active offers' banners + all category icons.
class LocalOfferImageJanitor {
  static Future<void> sync(Iterable<String> currentUrls) =>
      ImageSetJanitor.sync('local_offers', currentUrls);
}

/// 2026-10-03: treats every downloaded image as immutable.
///
/// Every upload is saved under a new random name (server: UploadsToBunny.php,
/// folder/uuid.ext) and the Vendor App deletes the old file when a photo is
/// replaced, so the content behind an image URL never changes. Bunny answers
/// with `cache-control: public, max-age=2592000` (30 days) and NO ETag, and
/// flutter_cache_manager can only revalidate with an ETag - so once the 30 days
/// ran out it downloaded the whole, unchanged file again. A file now stays
/// valid for a year; it leaves the cache only when it is unused for
/// [AppCacheConfig.imageStalePeriod] or evicted by the file-count cap.
class ImmutableFileService extends HttpFileService {
  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    final response = await super.get(url, headers: headers);
    return _LongLivedResponse(response);
  }
}

class _LongLivedResponse implements FileServiceResponse {
  _LongLivedResponse(this._inner);

  final FileServiceResponse _inner;
  static const Duration _validFor = Duration(days: 365);

  @override
  Stream<List<int>> get content => _inner.content;

  @override
  int? get contentLength => _inner.contentLength;

  @override
  int get statusCode => _inner.statusCode;

  @override
  DateTime get validTill => DateTime.now().add(_validFor);

  @override
  String? get eTag => _inner.eTag;

  @override
  String get fileExtension => _inner.fileExtension;
}

class AppCacheConfig {
  // ── Disk: general app imagery ───────────────────────────────────────────
  //
  // 120 objects instead of DefaultCacheManager's 200, and 7 days instead of
  // 30. Rationale for both numbers, so a future reader can re-derive them:
  //
  //  • 120 files — at the measured ~1.25 MB average that is a ~150 MB
  //    ceiling; if the images are ever resized at upload (~120 KB, the
  //    recommendation in the egress plan) the same count is a ~14 MB
  //    ceiling. Sized so the cap is tolerable under today's oversized
  //    images without being wastefully small once they are fixed.
  //  • 7 days — vendor photos, menus and banners change on a business
  //    cadence, not a monthly one. 30 days mostly retained images for
  //    restaurants the user never revisits, which is storage spent on
  //    nothing.
  //
  // Deliberately NOT smaller: eviction is not free. Every evicted image is
  // re-downloaded from Bunny at full size, which is exactly the CDN
  // bandwidth line the egress plan is trying to hold down. This is a
  // storage/bandwidth trade, not a pure win in either direction.
  static const String imageCacheKey = 'appImageCache';
  // 2026-10-03: 120 -> 500. Only pictures a user actually looked at are cached
  // (nothing downloads a whole menu), typically 5-10 per restaurant, so 500
  // files cover about 30 restaurants. Each picture can take TWO files (the
  // downloaded original and its resized copy under a second key), so 500 files
  // is about 250 pictures: roughly 25-60 MB at today's ~100 KB menu pictures,
  // at most about 110 MB if they were all 300 KB. Least recently used go first.
  // Revised same day: 500 -> 1000 because many menu pictures are only 30-100 KB
  // (1000 files = about 500 pictures = about 20-80 MB; 300 KB pictures would
  // reach 150-220 MB, which is the accepted worst case).
  // Test-only: --dart-define=IMAGE_CACHE_MAX_FILES=20 makes the library evict
  // rows early so the orphan sweep can be proven on a phone. Release builds
  // pass nothing, so this stays 1000.
  static const int maxImageFiles = int.fromEnvironment('IMAGE_CACHE_MAX_FILES', defaultValue: 1000);
  // 2026-10-03: 7 -> 30 days. With the file count capped (maxImageFiles) the
  // disk is bounded either way; a longer period only stops a diner who comes
  // back after 8-30 days from downloading the whole menu again.
  // Revised same day: 30 -> 60 days. A picture never changes at its address and
  // diners return to the same restaurants every few days; a file is dropped when
  // unused for 60 days or when the file cap pushes it out.
  // Test-only: --dart-define=IMAGE_STALE_MIN=5 treats a picture as unused after 5
  // minutes instead of 60 days (never change the phone's clock to test this).
  static const Duration imageStalePeriod =
      Duration(minutes: int.fromEnvironment('IMAGE_STALE_MIN', defaultValue: 60 * 24 * 60));

  // MUST be ImageCacheManager, not the plain CacheManager. Found on-device
  // 2026-09-10: a plain CacheManager silently IGNORES maxWidthDiskCache and
  // memCacheWidth — cached_network_image's own _image_loader.dart guards the
  // resize path behind `cacheManager is ImageCacheManager`, with only a
  // debug-only assert (stripped from release builds) if it isn't. So the
  // first version of this fix compiled clean, produced no warning anywhere,
  // and did nothing: cache usage after browsing 4 vendors on a freshly
  // cleared cache measured 44.4 MB on-device — consistent with full-original
  // files, not resized ones. Confirmed by reading flutter_cache_manager's
  // actual source, not by re-guessing at the API.
  //
  // Honest limitation this brings with it: ImageCacheManager does not avoid
  // storing the original. getImageFile() caches the full-size fetch under
  // its normal key AND separately stores a resized copy under a
  // `resized_w{n}_h{n}_{key}` key — so a fresh image can occupy two of the
  // 120 LRU slots, not one, until the untouched original ages out. In
  // practice this self-corrects: every repeat view requests the same
  // maxWidth, so it only ever touches the resized entry, and the
  // now-unused original becomes the least-recently-used one and is what
  // eviction reclaims first.
  // 2026-10-05: the Config is now a named field (same values as before - no
  // size or period change) so ImageOrphanSweeper can reach this cache's own
  // database and folder.
  static final Config _imageConfig = Config(
    imageCacheKey,
    stalePeriod: imageStalePeriod,
    maxNrOfCacheObjects: maxImageFiles,
    fileService: ImmutableFileService(),
  );
  static final AppImageCacheManager images = AppImageCacheManager(_imageConfig);

  // ── Per-file size ceiling ───────────────────────────────────────────────
  //
  // Not a constant here on purpose. NetworkImageWidget already computes the
  // exact pixel width each image will render at (display width × device
  // pixel ratio, see _targetPixelWidth) in order to build the Bunny resize
  // URL, and it now passes that same number as maxWidthDiskCache/
  // memCacheWidth. A fixed constant would be strictly worse — a 240 px
  // avatar and a full-bleed header would share one ceiling.
  //
  // That resize happens BEFORE the disk write, so the cache stores a
  // display-sized copy rather than the original. It bounds STORAGE and
  // MEMORY, not bandwidth: the full file still crosses the network. Only
  // resizing at upload (or enabling the Bunny Optimizer) reduces the
  // download itself.

  // ── Memory + Firestore ceilings ─────────────────────────────────────────
  //
  // Called once from main(). Both values are explicit rather than inherited
  // defaults, so a future SDK default change cannot silently move them.
  static void applyRuntimeLimits() {
    // Halves Flutter's default 100 MB / 1000-object in-memory image cache.
    // With full-resolution decodes (see the header note) the object count is
    // the binding constraint long before the byte count is, so both are set.
    PaintingBinding.instance.imageCache
      ..maximumSizeBytes = 50 << 20 // 50 MB of decoded bitmaps
      ..maximumSize = 150; // decoded images held at once

    // Firestore's own persistence cache. The SDK default is already bounded
    // with LRU garbage collection, but it is set explicitly here so the
    // ceiling is visible and reviewable rather than implicit — 40 MB is
    // comfortably above this app's working set (the largest single
    // collection read anywhere is 25 order documents at ~3.9 KB each).
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 40 * 1024 * 1024,
      );
    } catch (e) {
      // Settings can only be assigned before the first Firestore call. If
      // something already touched Firestore this throws; the SDK default
      // (bounded, LRU) still applies, so this is not worth crashing over.
      debugPrint('[AppCacheConfig] Firestore settings not applied: $e');
    }
  }

  /// Clears the general image cache. Story media is intentionally untouched —
  /// it has its own 24-hour managers and its own expiry semantics.
  static Future<void> clearImageCache() async {
    await images.emptyCache();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}
