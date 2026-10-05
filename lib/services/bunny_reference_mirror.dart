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
    // 2026-09-27: when a copy is already on the phone, ask the CDN "changed
    // since?" - an unchanged file comes back as an empty 304 (~0.9 KB of
    // headers, measured) instead of the whole file again (vendor list
    // 12 KB compressed, categories 40 KB, section menu 98 KB).
    final stored = await ConfigRefreshGate.peekRaw(cacheKey);
    final result = await _conditionalBunnyGet(cacheKey, url, stored);
    if (result.notModified) {
      await ConfigRefreshGate.markRefreshed(cacheKey);
      debugPrint('[ConfigCache] $cacheKey unchanged on Bunny CDN (304) - '
          'kept the on-phone copy, 0 bytes of body downloaded');
      return stored;
    }
    final body = result.body;
    if (body == null) {
      return ConfigRefreshGate.readRawIgnoringTtl(cacheKey);
    }
    debugPrint('[ConfigCache] $cacheKey fetched fresh from Bunny CDN and '
        'cached (${body.length} bytes)');
    return body;
  } catch (_) {
    // Timeout/offline - an expired local copy still beats sending the caller
    // into a billed Firestore query.
    return ConfigRefreshGate.readRawIgnoringTtl(cacheKey);
  }
}

class _BunnyGetResult {
  final bool notModified;
  final String? body; // new body (already stored), or null on failure
  const _BunnyGetResult(this.notModified, this.body);
}

/// Last time each key was actually downloaded in this app process, so a
/// "has it changed?" check right after a real download is skipped.
final Map<String, DateTime> _bunnyDownloadedAt = {};

/// One GET, conditional when [stored] exists. A 200 is stored (body +
/// validators) before returning. Throws on network errors/timeouts.
Future<_BunnyGetResult> _conditionalBunnyGet(
    String cacheKey, String url, String? stored) async {
  final headers = <String, String>{};
  if (stored != null) {
    final v = await ConfigRefreshGate.readValidators(cacheKey);
    if (v['etag'] != null) headers['If-None-Match'] = v['etag']!;
    if (v['lastModified'] != null) headers['If-Modified-Since'] = v['lastModified']!;
  }
  final resp = await http
      .get(Uri.parse(url), headers: headers)
      .timeout(const Duration(seconds: 8));
  if (resp.statusCode == 304 && stored != null) {
    return const _BunnyGetResult(true, null);
  }
  if (resp.statusCode != 200) return const _BunnyGetResult(false, null);
  await ConfigRefreshGate.writeRaw(cacheKey, resp.body);
  await ConfigRefreshGate.writeValidators(
      cacheKey, resp.headers['etag'], resp.headers['last-modified']);
  _bunnyDownloadedAt[cacheKey] = DateTime.now();
  return _BunnyGetResult(false, resp.body);
}

/// 2026-09-27: "show the phone's copy, then check" - asks the CDN whether
/// [url] changed since the copy on the phone, regardless of its TTL.
/// Returns the NEW body only when it really changed (the caller then
/// re-renders); null when unchanged (304), identical, nothing stored yet,
/// just downloaded, or on any failure (the phone's copy stays in use).
Future<String?> revalidateBunnyIfChanged(String cacheKey, String url) async {
  try {
    final last = _bunnyDownloadedAt[cacheKey];
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 60)) {
      return null;
    }
    final stored = await ConfigRefreshGate.peekRaw(cacheKey);
    if (stored == null) return null; // the normal load path downloads it
    final result = await _conditionalBunnyGet(cacheKey, url, stored);
    if (result.notModified) {
      await ConfigRefreshGate.markRefreshed(cacheKey);
      debugPrint('[ConfigCache] $cacheKey revalidated: unchanged (304) - 0 bytes of body');
      return null;
    }
    final body = result.body;
    if (body == null || body == stored) {
      debugPrint('[ConfigCache] $cacheKey revalidated: no change');
      return null;
    }
    debugPrint('[ConfigCache] $cacheKey revalidated: CHANGED on Bunny - '
        'downloaded ${body.length} bytes');
    return body;
  } catch (_) {
    return null;
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
/// rating). Open/closed is NOT in it any more (2026-09-27, Option B) - it is
/// the separate vendor-status/{sectionId}.json, see fetchVendorStatusesFromBunny
/// (re-checked every 5 min while Home is on screen); Cart re-reads vendor_live.
/// Whole-section, not radius-scoped - the caller
/// must still apply its own radius/distance filter. Returns null on any
/// failure so the caller falls back to the original live geo query; never
/// throws.
Future<List<VendorModel>?> fetchVendorListFromBunny(String sectionId) async {
  try {
    // Reference TTL is safe here even though a restaurant's open/closed state
    // is volatile: open/closed is not in this blob (see
    // fetchVendorStatusesFromBunny); this only carries the static-ish fields.
    final body = await cachedBunnyGet(
        'bunny_vendorList_$sectionId',
        'https://$_kBunnyCdnHost/vendor-lists/$sectionId.json',
        kBunnyReferenceTtl);
    if (body == null) return null;
    return _parseVendorList(body);
  } catch (_) {
    return null;
  }
}

/// 2026-10-05: true only when the on-phone vendor list can be trusted to be
/// COMPLETE. The list file itself has no count or version (only _builtAt +
/// items), but the server writes a second file, vendor-status/{section}.json,
/// from the SAME vendor query (and a vendor save patches both together), so
/// the two must name exactly the same vendors. Used to decide whether a
/// cleanup that deletes cached pictures is allowed: a short but valid list
/// must never delete legitimate pictures. Fails closed: any error, missing
/// file, empty file or mismatch returns false.
Future<bool> vendorListLooksComplete(String sectionId,
    {Duration statusTtl = const Duration(hours: 6)}) async {
  try {
    final listBody = await cachedBunnyGet(
        'bunny_vendorList_$sectionId',
        'https://$_kBunnyCdnHost/vendor-lists/$sectionId.json',
        kBunnyReferenceTtl);
    if (listBody == null) return false;
    final decoded = jsonDecode(listBody);
    final items = decoded is Map ? decoded['items'] : null;
    if (items is! List || items.isEmpty) return false;
    final listIds = <String>{
      for (final i in items)
        if (i is Map && i['id'] != null) i['id'].toString()
    };
    if (listIds.isEmpty) return false;
    final statuses = await fetchVendorStatusesFromBunny(sectionId, statusTtl);
    if (statuses == null || statuses.isEmpty) return false;
    final ok = listIds.length == statuses.length && listIds.containsAll(statuses.keys);
    if (!ok) {
      debugPrint('[VendorListCheck] list has ${listIds.length} vendors, status file '
          '${statuses.length} - not verified complete, picture cleanup skipped');
    }
    return ok;
  } catch (_) {
    return false;
  }
}

/// 2026-09-27: the vendor list only when it changed on Bunny since the copy
/// on the phone (e.g. a vendor's new working hours) - null when unchanged.
/// Used on cold start and pull-to-refresh after the phone's copy is shown.
Future<List<VendorModel>?> revalidateVendorListFromBunny(String sectionId) async {
  final body = await revalidateBunnyIfChanged('bunny_vendorList_$sectionId',
      'https://$_kBunnyCdnHost/vendor-lists/$sectionId.json');
  if (body == null) return null;
  try {
    return _parseVendorList(body);
  } catch (_) {
    return null;
  }
}

/// 2026-09-27 (Option B): {vendorId: open?} from vendor-status/{sectionId}.json
/// - written by VendorListMirror (Laravel) on every vendor save, ~30 B a
/// vendor. The phone's copy is used while younger than [ttl]; after that a
/// conditional GET (unchanged = empty 304). null when Bunny has nothing and
/// the phone has no copy.
Future<Map<String, bool>?> fetchVendorStatusesFromBunny(String sectionId, Duration ttl) async {
  try {
    final body = await cachedBunnyGet('bunny_vendorStatus_$sectionId',
        'https://$_kBunnyCdnHost/vendor-status/$sectionId.json', ttl);
    return body == null ? null : _parseVendorStatuses(body);
  } catch (_) {
    return null;
  }
}

/// Pull-to-refresh: asks Bunny now whatever the phone copy's age; returns
/// the new map only when it changed, else null.
Future<Map<String, bool>?> revalidateVendorStatusesFromBunny(String sectionId) async {
  final body = await revalidateBunnyIfChanged('bunny_vendorStatus_$sectionId',
      'https://$_kBunnyCdnHost/vendor-status/$sectionId.json');
  if (body == null) return null;
  try {
    return _parseVendorStatuses(body);
  } catch (_) {
    return null;
  }
}

Map<String, bool>? _parseVendorStatuses(String body) {
  final decoded = jsonDecode(body);
  final raw = decoded is Map ? decoded['statuses'] : null;
  if (raw is! Map) return null;
  return raw.map((k, v) => MapEntry(k.toString(), v == true));
}

List<VendorModel>? _parseVendorList(String body) {
  {
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

/// Terms & Conditions / Privacy Policy text (2026-09-25) from the admin
/// panel's legal/*.json Bunny mirror (BunnyLegalMirrorController) - the same
/// settings/termsAndConditions / settings/privacyPolicy text, copied with
/// the same field name. Uses the 24h reference cache, so a repeat open costs
/// no network at all. Returns null on any failure/empty text so the caller
/// falls back to its original Firestore read.
Future<String?> fetchLegalTextFromBunny(String file, String field) async {
  try {
    final body = await cachedBunnyGet('bunny_legal_$file',
        'https://$_kBunnyCdnHost/legal/$file', kBunnyReferenceTtl);
    if (body == null) return null;
    final text = (jsonDecode(body) as Map<String, dynamic>)[field];
    return text is String && text.trim().isNotEmpty ? text : null;
  } catch (_) {
    return null;
  }
}
