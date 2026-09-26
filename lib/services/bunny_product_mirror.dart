import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../model/ProductModel.dart';
// cachedBunnyGet + the shared per-mirror TTL constants live here so both
// mirror files route through one cached-GET implementation.
import 'bunny_reference_mirror.dart';
import 'config_refresh_gate.dart';

// Bunny Pull Zone hostname product-list mirrors are served from - the same
// CDN host every other Bunny-hosted asset in this app already resolves to
// (vendor photos, product images uploaded via bunny_storage.dart's proxy).
// Confirmed 2026-09-05 via the Bunny dashboard: storage zone "quickdash" ->
// pull zone "quickdash-storage-pull1" -> custom domain cdn.quickdash.co.in
// (matches Laravel's BUNNY_STORAGE_CDN_HOST). Reads go straight to Bunny's
// edge, deliberately bypassing admin.quickdash.co.in, since routing CDN
// reads back through the origin server would defeat the point of the mirror.
const _kBunnyCdnHost = 'cdn.quickdash.co.in';

/// Fetches a vendor's mirrored product list from Bunny's CDN instead of
/// querying Firestore directly - see BunnyProductMirrorController (Laravel)
/// for how this blob gets built and kept fresh after every product write.
/// Returns null on ANY failure (404 - vendor has no mirror yet, network
/// error, malformed blob) so every call site falls back to the original
/// Firestore query; never throws.
///
/// Deliberately does not change ranking behavior - the returned list is the
/// same candidate set the Firestore query would have produced, just served
/// from a CDN edge instead of Firestore origin. RecommendationEngine and the
/// existing per-device _productsCache TTL are both untouched by this.
/// Fetches the Home screen's whole-section product rail from Bunny instead
/// of querying Firestore directly - see BunnySectionProductMirrorController
/// (Laravel). Different scope from fetchVendorProductsFromBunny above (one
/// vendor's menu vs. the whole section's catalog). Returns null on any
/// failure so the caller falls back to the original Firestore query.
/// 2026-09-26: products already on the phone from earlier Bunny fetches (the
/// section menu used by Search, a restaurant's own menu) - ANY age, no
/// network at all. For stable per-product facts (veg / non-veg, digital)
/// where a stale copy is still correct. Empty map when nothing is cached.
Future<Map<String, ProductModel>> onDeviceProductsById({String? sectionId, String? vendorId}) async {
  final out = <String, ProductModel>{};
  void addAll(String? body, String listKey) {
    if (body == null) return;
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      for (final item in (decoded[listKey] as List<dynamic>? ?? const [])) {
        final map = Map<String, dynamic>.from(item as Map);
        final createdAtMillis = map['createdAt'];
        if (createdAtMillis is int) map['createdAt'] = Timestamp.fromMillisecondsSinceEpoch(createdAtMillis);
        try {
          final p = ProductModel.fromJson(map);
          if (p.id.isNotEmpty) out[p.id] = p;
        } catch (_) {}
      }
    } catch (_) {}
  }
  if (vendorId != null && vendorId.isNotEmpty) {
    addAll(await ConfigRefreshGate.readRawIgnoringTtl('bunny_vendorProducts_$vendorId'), 'products');
  }
  if (sectionId != null && sectionId.isNotEmpty) {
    addAll(await ConfigRefreshGate.readRawIgnoringTtl('bunny_sectionProducts_$sectionId'), 'items');
  }
  return out;
}

Future<List<ProductModel>?> fetchSectionProductsFromBunny(String sectionId) async {
  try {
    // Matches _productsCacheTtl (10 min) - this blob carries PRICES, so its
    // freshness window is deliberately NOT extended here. The read saving on
    // this mirror comes entirely from cachedBunnyGet's stale-while-error path,
    // which matters most precisely here: this mirror's Firestore fallback is
    // the whole-catalog query, up to 500 documents - the most expensive
    // fallback in the app.
    final body = await cachedBunnyGet(
        'bunny_sectionProducts_$sectionId',
        'https://$_kBunnyCdnHost/section-product-lists/$sectionId.json',
        kBunnyShortTtl);
    if (body == null) return null;

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final rawItems = decoded['items'] as List<dynamic>?;
    if (rawItems == null) return null;

    return rawItems.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      final createdAtMillis = map['createdAt'];
      if (createdAtMillis is int) {
        map['createdAt'] = Timestamp.fromMillisecondsSinceEpoch(createdAtMillis);
      }
      return ProductModel.fromJson(map);
    }).toList();
  } catch (_) {
    return null;
  }
}

Future<List<ProductModel>?> fetchVendorProductsFromBunny(String vendorId) async {
  try {
    final body = await cachedBunnyGet(
        'bunny_vendorProducts_$vendorId',
        'https://$_kBunnyCdnHost/product-lists/$vendorId.json',
        kBunnyShortTtl);
    if (body == null) return null;

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final rawProducts = decoded['products'] as List<dynamic>?;
    if (rawProducts == null) return null;

    return rawProducts.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      // Firestore's REST API (Laravel side) encodes createdAt as a
      // timestampValue string, converted server-side to epoch millis for
      // the JSON blob; ProductModel.fromJson only accepts a real Timestamp
      // (`is Timestamp` check) - rebuilt here so RecommendationEngine's
      // recency signal sees the same value it would have from Firestore
      // directly, instead of silently losing it.
      final createdAtMillis = map['createdAt'];
      if (createdAtMillis is int) {
        map['createdAt'] = Timestamp.fromMillisecondsSinceEpoch(createdAtMillis);
      }
      return ProductModel.fromJson(map);
    }).toList();
  } catch (_) {
    return null;
  }
}
