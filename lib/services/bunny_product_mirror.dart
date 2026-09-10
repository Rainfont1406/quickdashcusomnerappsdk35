import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../model/ProductModel.dart';

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
Future<List<ProductModel>?> fetchSectionProductsFromBunny(String sectionId) async {
  try {
    final resp = await http
        .get(Uri.parse('https://$_kBunnyCdnHost/section-product-lists/$sectionId.json'))
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return null;

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
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
    final resp = await http
        .get(Uri.parse('https://$_kBunnyCdnHost/product-lists/$vendorId.json'))
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return null;

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
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
