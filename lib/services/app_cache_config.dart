import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

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
  static const int maxImageFiles = 120;
  static const Duration imageStalePeriod = Duration(days: 7);

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
  static final AppImageCacheManager images = AppImageCacheManager(
    Config(
      imageCacheKey,
      stalePeriod: imageStalePeriod,
      maxNrOfCacheObjects: maxImageFiles,
    ),
  );

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
