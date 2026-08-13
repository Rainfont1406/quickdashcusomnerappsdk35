import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/perf_diagnostic_file_service.dart';
import 'package:emartconsumer/theme/responsive.dart';
import 'package:emartconsumer/widget/shimmer_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

// A failed DNS lookup / no route to host means the device has no working
// internet connection right now — it says nothing about whether this image
// actually exists. Showing a "broken image" look (and, worse, leaking the
// raw exception text) for a connectivity gap reads as "this content is
// missing" when the honest state is "still trying, network is down" — so
// this treats connectivity failures as a loading state (shimmer), not an
// error state. A genuinely bad/missing URL (404, malformed URL, etc.) still
// falls through to the real error fallback below.
bool _isConnectivityError(Object error) {
  if (error is SocketException) return true;
  final s = error.toString().toLowerCase();
  return s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('no address associated with hostname') ||
      s.contains('network is unreachable') ||
      s.contains('connection timed out') ||
      s.contains('connection closed while receiving data') ||
      s.contains('connection reset by peer');
}

// Same Bunny Optimizer mechanism as the shared bunnyOptimizedUrl() in
// constants.dart, but sized precisely from this widget's actual display
// width × device pixel ratio instead of that function's generic 800px
// fallback — NetworkImageWidget always knows (or can compute) its real
// display size, so it can do better than the app-wide default. Passing
// width alone (not height) lets Bunny scale proportionally, avoiding any
// distortion risk from forcing an exact height that doesn't match the
// source aspect ratio.
String _preciseBunnyUrl(String url, BuildContext context, double? displayWidth) {
  final logicalWidth = displayWidth ?? Responsive.width(15, context);
  if (logicalWidth <= 0 || logicalWidth.isNaN || logicalWidth.isInfinite) {
    return bunnyOptimizedUrl(url);
  }
  final dpr = MediaQuery.of(context).devicePixelRatio;
  final targetWidth = (logicalWidth * dpr).round().clamp(1, 2000);
  return bunnyOptimizedUrl(url, width: targetWidth);
}

/// Warms the cache for an upcoming carousel image using the exact same
/// resized-URL computation NetworkImageWidget itself uses, so the cache key
/// matches and the image is already decoded by the time a PageView actually
/// scrolls to it — call this for the "next" page as soon as the "current"
/// one settles, giving it a full tick interval of lead time instead of only
/// starting the fetch the moment the carousel wants to advance (which is
/// what caused the brief shimmer/white flash on the incoming photo).
/// Errors are swallowed — a failed precache just means that page falls back
/// to its own normal loading state, same as if this was never called.
/// [resizeWidth], if provided, must match whatever the corresponding
/// NetworkImageWidget render call passes as its own `resizeWidth` (or
/// `width`, if that render call doesn't override it) - otherwise this
/// precaches a different-sized URL than the one that ends up on screen,
/// and the cache silently misses.
/// [cacheManager], if provided, must match the corresponding
/// NetworkImageWidget render call's own `cacheManager` for the same reason -
/// Flutter's in-memory image cache keys on the resolved URL regardless of
/// which disk CacheManager fetched it, but a mismatched CacheManager still
/// means a cold-start re-render (or a fresh CachedNetworkImage instance)
/// re-downloads instead of hitting disk.
void precacheCarouselImage(BuildContext context, String imageUrl,
    {double? width, double? resizeWidth, BaseCacheManager? cacheManager}) {
  final resolvedUrl = _preciseBunnyUrl(imageUrl, context, resizeWidth ?? width);
  precacheImage(
          CachedNetworkImageProvider(resolvedUrl, cacheManager: cacheManager),
          context)
      .catchError((_) {});
}

/// Warms the vendor-details header image the instant a vendor is tapped
/// (from Home, Search, QR scan, or anywhere else that opens
/// NewVendorProductsScreen) - before that screen even starts building - so
/// the larger hero-res fetch is already in flight, or finished, by the time
/// its header actually renders. Without this, the header requests a bigger,
/// precisely DPR-scaled image than the small thumbnail shown wherever the
/// user tapped from, which is a guaranteed cache miss (different resolved
/// URL) no matter how fast the network is - that gap is what reads as "the
/// same image loading again, slowly".
/// Mirrors newVendorProductsScreen.dart's own `_cardPhotos` getter and its
/// header's width/resizeWidth math exactly, and shares its
/// `perfDiagnosticCacheManager` cache store, so this is a genuine hit rather
/// than landing in a different cache than the header reads from.
void precacheVendorHeroImage(BuildContext context, VendorModel vendorModel) {
  final allPhotos = vendorModel.photos
      .map((e) => VendorModel.coverPhotoUrl(e))
      .where((s) => s.isNotEmpty && s != 'null')
      .toList();
  final cardPhotos = allPhotos.length > 1 ? allPhotos.sublist(1) : <String>[];
  final heroUrl =
      cardPhotos.isNotEmpty ? cardPhotos.first : vendorModel.photo.toString();
  if (heroUrl.isEmpty || heroUrl == 'null') return;

  final heroWidth = Responsive.width(100, context);
  final heroHeight = Responsive.height(40, context);
  final heroResizeWidth = math.max(heroWidth, heroHeight * 16 / 9);
  precacheCarouselImage(
    context,
    heroUrl,
    width: heroWidth,
    resizeWidth: heroResizeWidth,
    cacheManager: perfDiagnosticCacheManager,
  );
}

class NetworkImageWidget extends StatelessWidget {
  final String imageUrl;
  final double? height;
  final double? width;
  final Widget? errorWidget;
  final BoxFit? fit;
  final double? borderRadius;
  final Color? color;
  // Optional, additive-only perf hooks — every existing call site that
  // doesn't pass these keeps its exact previous behavior (imageBuilder stays
  // null, so CachedNetworkImage uses its own default rendering).
  final VoidCallback? onLoaded;
  final void Function(Object error)? onError;
  // TEMPORARY diagnostic hook: lets a call site swap in an instrumented
  // CacheManager. Null (the default for every existing call site) means
  // CachedNetworkImage uses its normal DefaultCacheManager — no behavior
  // change anywhere except the two HomeScreen sites under investigation.
  final BaseCacheManager? cacheManager;
  // Optional override for the Bunny resize computation only - `width`
  // continues to drive the widget's own layout size unchanged. Needed
  // when `width` alone isn't a reliable proxy for how large the image will
  // actually render under BoxFit.cover: if the display box is taller
  // (relative to its width) than the source photo's own aspect ratio,
  // cover scales the image up based on HEIGHT, not width, so a resize
  // request sized off `width` alone fetches an image smaller than what
  // ends up on screen - visible as blur from upscaling. Null (every
  // existing call site) preserves the previous width-only behavior.
  final double? resizeWidth;

  const NetworkImageWidget({
    super.key,
    this.height,
    this.width,
    this.fit,
    required this.imageUrl,
    this.borderRadius,
    this.errorWidget,
    this.color,
    this.onLoaded,
    this.onError,
    this.cacheManager,
    this.resizeWidth,
  });

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: _preciseBunnyUrl(imageUrl, context, resizeWidth ?? width),
      cacheManager: cacheManager,
      fit: fit ?? BoxFit.fitWidth,
      height: height ?? Responsive.height(8, context),
      width: width ?? Responsive.width(15, context),
      color: color,
      imageBuilder: onLoaded == null
          ? null
          : (context, imageProvider) {
              onLoaded!();
              return Image(
                image: imageProvider,
                fit: fit ?? BoxFit.fitWidth,
                height: height ?? Responsive.height(8, context),
                width: width ?? Responsive.width(15, context),
                color: color,
              );
            },
      progressIndicatorBuilder: (context, url, downloadProgress) => ShimmerBox(
        width: width ?? Responsive.width(15, context),
        height: height ?? Responsive.height(8, context),
        borderRadius: borderRadius ?? 0,
      ),
      errorWidget: (context, url, error) {
        onError?.call(error);
        if (_isConnectivityError(error)) {
          // No internet right now — not "this image is broken". Keep
          // showing the loading look instead of a broken-image state (and
          // never render the raw exception to the user).
          return ShimmerBox(
            width: width ?? Responsive.width(15, context),
            height: height ?? Responsive.height(8, context),
            borderRadius: borderRadius ?? 0,
          );
        }
        return errorWidget ??
            Image.network(
              placeholderImage,
              fit: fit ?? BoxFit.fitWidth,
              height: height ?? Responsive.height(8, context),
              width: width ?? Responsive.width(15, context),
            );
      },
    );
  }
}
