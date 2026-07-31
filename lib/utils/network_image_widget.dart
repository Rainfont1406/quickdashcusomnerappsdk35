import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:emartconsumer/constants.dart';
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
  });

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: _preciseBunnyUrl(imageUrl, context, width),
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
