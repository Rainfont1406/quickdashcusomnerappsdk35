import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../model/VendorCategoryModel.dart';
import '../model/VendorModel.dart';
import '../model/offer_model.dart';
import '../model/LocalOfferCategoryModel.dart';
import '../model/LocalOfferModel.dart';
import '../model/BannerModel.dart';
import 'config_refresh_gate.dart';

// Same Bunny Pull Zone as bunny_product_mirror.dart - see that file's own
// comment for why this is hardcoded rather than fetched from a config
// endpoint.
const _kBunnyCdnHost = 'cdn.quickdash.co.in';

/// Shared cached GET for every Bunny mirror (2026-09-15).
///
/// WHY THIS EXISTS - it is NOT primarily about saving CDN bandwidth. Each
/// mirror function below returns null on failure so its caller falls back to
/// the original FIRESTORE query, and these fetches carry an 8-second timeout.
/// On a slow connection that timeout is genuinely reachable - measured
/// on-device 2026-09-15: 9-12s Firestore round trips and 4.7-5.5s OSRM calls
/// in the same session, and a cold start that logged
/// `getHomeTopBanner:MENU_ITEM docs=3` even though that mirror is healthy
/// (verified live, HTTP 200).
///
/// So a slow network silently converts a working CDN mirror into BILLED
/// Firestore reads - and for the product mirror that fallback is the
/// whole-catalog query (up to 500 documents). Serving the last known-good
/// response from disk first removes that failure mode entirely, and skips the
/// HTTP round trip on the happy path too, so the screen paints sooner.
///
/// Caches the raw response TEXT, not a parsed model, so the cached path runs
/// through exactly the same jsonDecode + fromJson as the live path - there is
/// no second parsing implementation that could drift or drop fields.
///
/// Returns null only when there is neither a cached copy (of any age) nor a
/// successful fetch - i.e. only a genuinely uncached, genuinely failing
/// request sends the caller to its Firestore fallback.
///
/// STALE-WHILE-ERROR, not stale-by-default. This distinction is the whole
/// point, and an earlier version of this helper got it wrong:
///
///   1. Cached copy still inside [ttl] -> serve it, no network at all.
///   2. Expired -> fetch normally, and store the new copy.
///   3. Fetch FAILS or times out -> serve the EXPIRED cached copy rather than
///      returning null, because returning null sends the caller into its
///      Firestore fallback.
///
/// Step 3 is what actually saves reads, and it does so WITHOUT needing a long
/// TTL. That matters because several of these TTLs are deliberate product
/// decisions that must not be quietly extended - most pointedly coupons, cut
/// from 30 minutes to 5 "at explicit request" (see _couponsCacheTtl in
/// FirebaseHelper) precisely so an admin-disabled coupon stops being offered
/// quickly. A long blanket cache here would have silently reversed that.
///
/// Serving a slightly stale copy on a failed fetch is strictly better than the
/// alternative it replaces: the fallback path re-queries Firestore for data
/// that is just as stale (it is the same content the mirror was built from),
/// only billed - and for the product mirror that fallback is the whole-catalog
/// query, up to 500 documents.
Future<String?> cachedBunnyGet(String cacheKey, String url, Duration ttl) async {
  // 2026-09-15: the two SUCCESS paths below (fresh cache hit, successful new
  // fetch) had zero debug output - only the failure/stale-fallback path
  // logged anything (see ConfigRefreshGate.readRawIgnoringTtl). That meant
  // this caching layer could never be verified as actually WORKING from
  // device logs, only ever caught when it was failing - confirmed live
  // 2026-09-15 trying to verify the local-offers screen's caching and finding
  // nothing to look at either way. Both success paths now log explicitly.
  final fresh = await ConfigRefreshGate.readRaw(cacheKey, ttl);
  if (fresh != null) {
    debugPrint('[ConfigCache] $cacheKey served from fresh Bunny cache '
        '(still inside TTL) - 0 network calls');
    return fresh;
  }
  try {
    final resp =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      return ConfigRefreshGate.readRawIgnoringTtl(cacheKey);
    }
    // ignore: unawaited_futures
    ConfigRefreshGate.writeRaw(cacheKey, resp.body);
    debugPrint('[ConfigCache] $cacheKey fetched fresh from Bunny CDN and '
        'cached (${resp.body.length} bytes)');
    return resp.body;
  } catch (_) {
    // Timeout/offline - an expired local copy still beats sending the caller
    // into a billed Firestore query.
    return ConfigRefreshGate.readRawIgnoringTtl(cacheKey);
  }
}

// Per-mirror TTLs. These deliberately MATCH the in-memory TTL each caller
// already had, so this layer never extends a freshness window someone chose on
// purpose; the read saving comes from the stale-while-error path above, not
// from holding data longer.
//   - Reference data that genuinely changes on the order of weeks, and whose
//     longer window was explicitly approved (2026-09-15).
const Duration kBunnyReferenceTtl = Duration(hours: 24);
//   - Matches _cuisinesCacheTtl / _productsCacheTtl (10 minutes).
const Duration kBunnyShortTtl = Duration(minutes: 10);
//   - Matches _couponsCacheTtl, shortened to 5 minutes at explicit request so
//     an admin-disabled coupon stops being offered quickly. Do not extend.
const Duration kBunnyCouponTtl = Duration(minutes: 5);
//   - Matches _localOffersCacheTtl (6 hours).
const Duration kBunnyPromoTtl = Duration(hours: 6);

/// Fetches the Home screen's cuisine/category row from Bunny instead of
/// querying Firestore directly - see BunnyCategoryMirrorController (Laravel)
/// for how this blob gets built and kept fresh. Returns null on ANY failure
/// (404 - section has no mirror yet, network error, malformed blob) so the
/// caller falls back to the original Firestore query; never throws.
Future<List<VendorCategoryModel>?> fetchCategoriesFromBunny(String sectionId) async {
  try {
    final body = await cachedBunnyGet(
        'bunny_categories_$sectionId',
        'https://$_kBunnyCdnHost/category-lists/$sectionId.json',
        kBunnyShortTtl);
    if (body == null) return null;

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final rawItems = decoded['items'] as List<dynamic>?;
    if (rawItems == null) return null;

    return rawItems
        .map((item) => VendorCategoryModel.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  } catch (_) {
    return null;
  }
}

/// Fetches the Home screen's top banner carousel from Bunny instead of
/// querying Firestore directly - see BunnyTopBannerMirrorController (Laravel).
/// Same "read on every cold start by every user" fan-out as the cuisine
/// mirror above, and just as small (2026-09-06 audit: 3 docs / ~1KB on the
/// live Restaurants section). Sorted by set_order client-side to match the
/// original query's orderBy, since the mirror blob itself is unordered.
/// Returns null on any failure so the caller falls back to the original
/// Firestore query + its own existing 10-minute cache; never throws.
Future<List<BannerModel>?> fetchTopBannerFromBunny(String sectionId) async {
  try {
    final body = await cachedBunnyGet(
        'bunny_topBanner_$sectionId',
        'https://$_kBunnyCdnHost/top-banner-lists/$sectionId.json',
        kBunnyReferenceTtl);
    if (body == null) return null;

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final rawItems = decoded['items'] as List<dynamic>?;
    if (rawItems == null) return null;

    final banners = rawItems
        .map((item) => BannerModel.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    banners.sort((a, b) => (a.setOrder ?? 0).compareTo(b.setOrder ?? 0));
    return banners;
  } catch (_) {
    return null;
  }
}

/// Fetches the Home screen's vendor list from Bunny instead of the live
/// geo-listener - see BunnyVendorListMirrorController (Laravel). Carries
/// static-ish fields only (title, photo, location, cuisines, workingHours,
/// rating); live open/closed status is NOT trusted from this blob - see
/// SharedVendorsWatcher, which overlays the separately-live-listened
/// vendor_status/{sectionId} aggregate on top of whatever reststatus this
/// mirror happens to have. Whole-section, not radius-scoped - the caller
/// must still apply its own radius/distance filter. Returns null on any
/// failure so the caller falls back to the original live geo query; never
/// throws.
Future<List<VendorModel>?> fetchVendorListFromBunny(String sectionId) async {
  try {
    // Reference TTL is safe here even though a restaurant's open/closed state
    // is volatile: SharedVendorsWatcher deliberately splits that out into a
    // separate LIVE listener on vendor_status/{sectionId}, so this blob only
    // carries the static-ish fields (title, photo, location, hours, rating).
    final body = await cachedBunnyGet(
        'bunny_vendorList_$sectionId',
        'https://$_kBunnyCdnHost/vendor-lists/$sectionId.json',
        kBunnyReferenceTtl);
    if (body == null) return null;

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final rawItems = decoded['items'] as List<dynamic>?;
    if (rawItems == null) return null;

    final vendors = <VendorModel>[];
    for (final item in rawItems) {
      final map = Map<String, dynamic>.from(item as Map);

      // Same approved/active filter getAllStores()'s own callback applies
      // to a live Firestore read - VendorModel has no store_status/isActive
      // fields of its own (they're checked on the raw map, then discarded),
      // so this MUST run here, before fromJson(), or an unapproved/
      // deactivated vendor would silently start showing up on Home the
      // moment this mirror path is used instead of the live query.
      final storeStatus = map['store_status'] as String?;
      final isActive = map['isActive'];
      if (!((storeStatus == null || storeStatus == 'approved') && isActive != false)) {
        continue;
      }

      // createdAt is epoch millis in the mirror blob (see
      // MirrorsToBunny::rebuildBunnyMirror's timestampFields conversion);
      // VendorModel.fromJson expects a real Timestamp - same reconstruction
      // pattern as fetchCouponsFromBunny below. Every other field
      // (including the geoflutterfire "g" indexing field, whose nested
      // geopoint decodes to a plain {lat,lng} map here, not a real
      // GeoPoint) already parses safely as-is - VendorModel.fromJson's own
      // `is GeoPoint` type check treats that as null, which is exactly what
      // it should be since nothing on Home reads it (latitude/longitude
      // top-level fields are what distance calculations actually use).
      final createdAtMillis = map['createdAt'];
      if (createdAtMillis is int) {
        map['createdAt'] = Timestamp.fromMillisecondsSinceEpoch(createdAtMillis);
      }
      try {
        vendors.add(VendorModel.fromJson(map));
      } catch (_) {
        // Skip a single malformed entry rather than failing the whole mirror.
      }
    }
    return vendors;
  } catch (_) {
    return null;
  }
}

/// Fetches the Home screen's active-coupons list from Bunny instead of
/// querying Firestore directly - see BunnyCouponMirrorController (Laravel).
/// Unlike categories/products this is one global blob, not scoped per
/// section/vendor. Returns null on any failure so the caller falls back to
/// the original Firestore query.
Future<List<OfferModel>?> fetchCouponsFromBunny() async {
  try {
    final body = await cachedBunnyGet('bunny_coupons',
        'https://$_kBunnyCdnHost/coupon-list.json', kBunnyCouponTtl);
    if (body == null) return null;

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final rawItems = decoded['items'] as List<dynamic>?;
    if (rawItems == null) return null;

    final now = Timestamp.now();
    final coupons = <OfferModel>[];
    for (final item in rawItems) {
      final map = Map<String, dynamic>.from(item as Map);
      // expiresAt is epoch millis in the mirror blob (see
      // BunnyCouponMirrorController); OfferModel.fromJson assigns it
      // straight into a Timestamp? field with no type check, so this must
      // be rebuilt into a real Timestamp before parsing or it throws.
      final expiresAtMillis = map['expiresAt'];
      if (expiresAtMillis is int) {
        map['expiresAt'] = Timestamp.fromMillisecondsSinceEpoch(expiresAtMillis);
      }
      final offer = OfferModel.fromJson(map);
      // Same validity filter FirebaseHelper.getAllCoupons applies today.
      if (offer.expireOfferDate == null || offer.expireOfferDate!.compareTo(now) >= 0) {
        coupons.add(offer);
      }
    }
    return coupons;
  } catch (_) {
    return null;
  }
}

/// {lat, lng} map (see FirestoreRest::fsDecodeValue's geoPointValue case) ->
/// a real GeoPoint, or null if the shape doesn't match. LocalOfferModel/
/// CtaButton assign resolvedLocation straight into a GeoPoint? field with no
/// type check, same as the Timestamp fields below - this must run before
/// fromJson or it throws.
GeoPoint? _geoPointFromMirrorMap(dynamic value) {
  if (value is! Map) return null;
  final lat = value['lat'];
  final lng = value['lng'];
  if (lat is num && lng is num) return GeoPoint(lat.toDouble(), lng.toDouble());
  return null;
}

Timestamp? _timestampFromMirrorMillis(dynamic value) {
  if (value is int) return Timestamp.fromMillisecondsSinceEpoch(value);
  return null;
}

/// Fetches the "Offers & Discounts" drawer screen's category chips from
/// Bunny instead of querying Firestore directly - see
/// BunnyLocalOfferMirrorController::rebuildCategories (Laravel), triggered
/// instantly on every local_offer_categories write by
/// functions/index.js's syncLocalOfferCategoriesToBunny - so this blob is
/// always current the moment an admin saves; caching it client-side (see
/// FirebaseHelper.getLocalOfferCategories) is purely to avoid re-downloading
/// it on every screen open, same plain-TTL shape as the product-list mirror
/// cache. No Timestamp/GeoPoint fields on this model, so no reconstruction
/// needed. Sorted by sortOrder client-side to match the original query's
/// orderBy('sortOrder'), since the mirror blob itself is unordered. Returns
/// null on any failure so the caller falls back to the original Firestore
/// query; never throws.
Future<List<LocalOfferCategoryModel>?> fetchLocalOfferCategoriesFromBunny() async {
  try {
    final body = await cachedBunnyGet('bunny_localOfferCategories',
        'https://$_kBunnyCdnHost/local-offer-categories.json', kBunnyReferenceTtl);
    if (body == null) return null;

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final rawItems = decoded['items'] as List<dynamic>?;
    if (rawItems == null) return null;

    final categories = rawItems
        .map((item) => LocalOfferCategoryModel.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    categories.sort((a, b) => (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0));
    return categories;
  } catch (_) {
    return null;
  }
}

/// Fetches the "Offers & Discounts" drawer screen's active offers from
/// Bunny instead of querying Firestore directly - see
/// BunnyLocalOfferMirrorController::rebuildOffers (Laravel), triggered
/// instantly on every local_offers write by functions/index.js's
/// syncLocalOffersToBunny - so this blob is always current the moment an
/// admin saves; caching it client-side (see
/// FirebaseHelper.getAllActiveLocalOffers) is purely to avoid
/// re-downloading it on every screen open, same plain-TTL shape as the
/// product-list mirror cache. Reconstructs every Timestamp (top-level
/// startDate/validTill/createdAt AND each offers[] heading's own
/// startDate/validTill) and every GeoPoint (top-level resolvedLocation AND
/// each ctaButtons[] entry's resolvedLocation) before calling
/// LocalOfferModel.fromJson, since that model assigns every one of those
/// fields straight in with no type check. Only global, unfiltered-by-category
/// fetches are mirrored - matches the only way LocalOffersListScreen
/// actually calls getAllActiveLocalOffers today (no categoryId; filtering
/// happens client-side after fetch). Returns null on any failure so the
/// caller falls back to the original Firestore query; never throws.
Future<List<LocalOfferModel>?> fetchLocalOffersFromBunny() async {
  try {
    final body = await cachedBunnyGet('bunny_localOffers',
        'https://$_kBunnyCdnHost/local-offers.json', kBunnyPromoTtl);
    if (body == null) return null;

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final rawItems = decoded['items'] as List<dynamic>?;
    if (rawItems == null) return null;

    final offers = <LocalOfferModel>[];
    for (final item in rawItems) {
      final map = Map<String, dynamic>.from(item as Map);

      map['startDate'] = _timestampFromMirrorMillis(map['startDate']);
      map['validTill'] = _timestampFromMirrorMillis(map['validTill']);
      map['createdAt'] = _timestampFromMirrorMillis(map['createdAt']);
      map['resolvedLocation'] = _geoPointFromMirrorMap(map['resolvedLocation']);

      final rawOffers = map['offers'];
      if (rawOffers is List) {
        map['offers'] = rawOffers.map((h) {
          if (h is! Map) return h;
          final heading = Map<String, dynamic>.from(h);
          heading['startDate'] = _timestampFromMirrorMillis(heading['startDate']);
          heading['validTill'] = _timestampFromMirrorMillis(heading['validTill']);
          return heading;
        }).toList();
      }

      final rawCtaButtons = map['ctaButtons'];
      if (rawCtaButtons is List) {
        map['ctaButtons'] = rawCtaButtons.map((b) {
          if (b is! Map) return b;
          final button = Map<String, dynamic>.from(b);
          button['resolvedLocation'] = _geoPointFromMirrorMap(button['resolvedLocation']);
          return button;
        }).toList();
      }

      offers.add(LocalOfferModel.fromJson(map));
    }
    return offers;
  } catch (_) {
    return null;
  }
}
