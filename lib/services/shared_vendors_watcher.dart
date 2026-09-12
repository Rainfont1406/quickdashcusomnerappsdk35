import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/bunny_reference_mirror.dart';
import 'package:emartconsumer/services/firestore_instrumentation.dart';
import 'package:flutter/foundation.dart';

/// Shared, app-session-scoped replacement for HomeScreen calling
/// FireStoreUtils.getAllStores() itself on every visit (2026-09-06, rebuilt
/// 2026-09-07 around a Bunny mirror + live status aggregate).
///
/// 2026-09-07 rebuild: the vendor geo-listener was the dominant Home screen
/// EGRESS cost (~5.2KB avg x N vendors, confirmed real production average -
/// see the 2026-09-06/07 audit), not a read-count problem - read count is
/// cheap, egress bytes are the actual concern. A client-side cap was tried
/// and rejected: Firestore transfers the full matching set before any
/// client-side truncation can happen, so it doesn't reduce egress at all.
///
/// The real fix splits the data by how often it actually changes:
///   - Static-ish fields (title, photo, location, cuisines, workingHours,
///     rating) come from a Bunny mirror (BunnyVendorListMirrorController) -
///     near-zero egress, refreshed on every vendor write via
///     syncVendorListToBunny.
///   - The ONE field that genuinely needs to be live - a vendor's manual
///     reststatus toggle - comes from a tiny per-section aggregate document
///     (vendor_status/{sectionId}, shape {statuses: {vendorId: bool}}),
///     patched directly by syncVendorStatusAggregate on every vendor write.
///     A single live listener on this one small document replaces the full
///     per-vendor live listener for status purposes.
///
/// Verified NOT a correctness regression for the two things that matter:
///   - Working-hours-based "closed for the night" already computes
///     entirely client-side (VendorModel.isAcceptingOrders combines
///     reststatus with isOpen(), which compares workingHours against
///     DateTime.now() locally) - it was never a server push in the first
///     place, so mirroring workingHours changes nothing here.
///   - A vendor's manual "close now" toggle stays fully live via the
///     status aggregate above.
/// Accepted trade-off (explicit): reviewsCount/reviewsSum moves from an
/// instant live push (another customer's review re-sorting your already-
/// open Home screen mid-session) to eventually-consistent (next mirror
/// refresh or pull-to-refresh). Confirmed real via FieldValue.increment()
/// in updateVendorReviewStats - genuinely instant today, not a batched job -
/// so this is a real, knowingly-accepted behavior change, not a non-issue.
///
/// Own-location-change sorting actually improves under this design: the
/// whole section's vendor list is already in memory, so recomputing
/// distances against a new location is a free client-side operation instead
/// of tearing down and reopening a live geo-query.
///
/// 2026-09-11: also migrated onto this watcher - DineInScreen (was its own
/// raw GeoFirestore listener via FireStoreUtils.getAllDineInRestaurants(),
/// filtered here client-side for enabledDiveInFuture), MapViewScreen (was
/// its own getAllStores() fallback for when allstoreList is empty), and
/// view_all_popular_store_screen.dart (was its own getAllStores() call).
/// All three previously opened an independent live geo-listener duplicating
/// whatever HomeScreen already had open - and DineInScreen's, being a raw
/// query at the section's admin-configured 13,000km ("effectively
/// unlimited") radius with no .getLogged() wrapper, was an invisible read
/// cost (confirmed live: ~179 reads for one Dine-In visit, zero matching
/// lines in the app's own Firestore-read log).
class SharedVendorsWatcher {
  SharedVendorsWatcher._();

  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSub;
  static final StreamController<List<VendorModel>> _controller =
      StreamController<List<VendorModel>>.broadcast();
  static List<VendorModel> _baseVendors = [];
  static Map<String, bool> _liveStatuses = {};
  static List<VendorModel>? _latest;
  static String? _activeKey;

  static String _keyFor(String sectionId, double lat, double lng) {
    // Rounded to ~1km so tiny GPS jitter between visits doesn't count as a
    // "location changed, restart" event.
    return '$sectionId:${lat.toStringAsFixed(2)}:${lng.toStringAsFixed(2)}';
  }

  /// Call from HomeScreen.getData() instead of fireStoreUtils.getAllStores()
  /// directly. Safe to call on every visit - only does a real Bunny fetch +
  /// opens the tiny status listener the first time for this (section,
  /// location); every later call just returns the same shared stream,
  /// seeded with whatever's already known.
  static Stream<List<VendorModel>> watch(
      String sectionId, double lat, double lng) {
    final key = _keyFor(sectionId, lat, lng);
    if (_activeKey != key || _statusSub == null) {
      start(sectionId, lat, lng);
    }
    return _replay();
  }

  static Stream<List<VendorModel>> _replay() async* {
    if (_latest != null) yield _latest!;
    yield* _controller.stream;
  }

  /// Starts (or restarts) the shared watcher for this (section, location).
  /// Always stops any previous subscription first. Called directly by
  /// HomeScreen's pull-to-refresh (the one thing that should force a
  /// genuinely fresh check of both the static list and live statuses).
  static void start(String sectionId, double lat, double lng) {
    stop();
    if (sectionId.isEmpty) return;
    _activeKey = _keyFor(sectionId, lat, lng);

    _loadBaseVendors(sectionId, lat, lng);
    _statusSub = FireStoreUtils.firestore
        .collection('vendor_status')
        .doc(sectionId)
        .snapshots()
        .listen((snap) {
      final data = snap.data();
      final rawStatuses = data?['statuses'];
      _liveStatuses = rawStatuses is Map
          ? rawStatuses.map((k, v) => MapEntry(k.toString(), v == true))
          : {};
      _emit();
    }, onError: (Object e) {
      debugPrint('[SharedVendorsWatcher] status listener error: $e');
    });
  }

  static Future<void> _loadBaseVendors(
      String sectionId, double lat, double lng) async {
    try {
      final mirrored = await fetchVendorListFromBunny(sectionId);
      List<VendorModel> vendors;
      if (mirrored != null) {
        vendors = mirrored;
      } else {
        // Bunny mirror unavailable (not built yet for this section, or a
        // transient failure) - fall back to a real, one-time Firestore read
        // of the whole section (same approved/active filter getAllStores()
        // applies), rather than leaving Home with nothing.
        final snap = await FireStoreUtils.firestore
            .collection(VENDORS)
            .where('section_id', isEqualTo: sectionId)
            .getLogged('SharedVendorsWatcher:VENDORS-fallback');
        vendors = [];
        for (final doc in snap.docs) {
          final data = doc.data();
          // Same approved/active filter as getAllStores()'s own callback -
          // fetchVendorListFromBunny already applies this internally for
          // the mirror path, but this raw-Firestore fallback needs its own
          // copy since it isn't going through that function.
          final storeStatus = data['store_status'] as String?;
          final isActive = data['isActive'];
          if (!((storeStatus == null || storeStatus == 'approved') && isActive != false)) {
            continue;
          }
          try {
            vendors.add(VendorModel.fromJson(data));
          } catch (_) {}
        }
      }

      // Radius filter - the mirror is whole-section, not radius-scoped, so
      // this replaces geoflutterfire's server-side filtering. Cheap either
      // way at this section's current scale (a few dozen vendors); the
      // whole point of mirroring is that this stays cheap even if that
      // grows, since it's Bunny bandwidth, not Firestore egress.
      //
      // nearByRadius is stored and admin-configured in KILOMETERS already
      // (confirmed against every legacy geoflutterfire caller -
      // getAllStores/getAllDineInRestaurants/getVendorsByCuisineID all pass
      // sectionConstantModel!.nearByRadius straight into geoflutterfire's
      // own `radius` param with zero conversion, and geoflutterfire's own
      // API is documented in km) - NOT meters. A prior version of this line
      // divided by 1000, silently shrinking an admin-configured 13,000 km
      // (effectively unlimited) radius down to 13 km, hiding every
      // legitimately-visible vendor beyond that for every customer in the
      // section. Found 2026-09-08 via a real report of two restaurants
      // missing from Home despite being online/approved/active.
      //
      // No hardcoded fallback number - this is an admin-controlled setting
      // (SectionModel.fromJson already defaults it to a real value once the
      // section doc loads), so if sectionConstantModel itself isn't loaded
      // yet, skip the distance filter entirely rather than guessing a km
      // value that isn't the admin's to begin with.
      final radiusKm = sectionConstantModel?.nearByRadius?.toDouble();
      if (radiusKm != null) {
        vendors = vendors.where((v) {
          final distanceKm = _distanceKm(lat, lng, v.latitude, v.longitude);
          return distanceKm <= radiusKm;
        }).toList();
      }

      _baseVendors = vendors;
      _emit();
    } catch (e) {
      debugPrint('[SharedVendorsWatcher] base vendor load error: $e');
    }
  }

  // Standard Haversine formula - only used for the "still within radius"
  // filter and (indirectly, via HomeScreen's own _sortRestaurants) display
  // sorting, never for anything financial, so a small-angle approximation
  // difference from Geolocator's own distanceBetween is fine.
  static double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) * math.cos(_degToRad(lat2)) *
            math.sin(dLng / 2) * math.sin(dLng / 2);
    final c = 2 * math.asin(math.min(1.0, math.sqrt(a)));
    return earthRadiusKm * c;
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);

  static void _emit() {
    if (_baseVendors.isEmpty) return;
    final merged = _baseVendors.map((v) {
      final liveStatus = _liveStatuses[v.id];
      if (liveStatus != null) v.reststatus = liveStatus;
      return v;
    }).toList();
    _latest = merged;
    if (!_controller.isClosed) _controller.add(merged);
  }

  /// Restarts the watcher only if one was already active - called on app
  /// resume, same defensive reconnect PurchaseCompletionListener/
  /// SharedOrdersWatcher already rely on.
  static void restartIfActive() {
    final key = _activeKey;
    if (key == null) return;
    final parts = key.split(':');
    if (parts.length != 3) return;
    final lat = double.tryParse(parts[1]);
    final lng = double.tryParse(parts[2]);
    if (lat == null || lng == null) return;
    start(parts[0], lat, lng);
  }

  static void stop() {
    _statusSub?.cancel();
    _statusSub = null;
    _activeKey = null;
    _baseVendors = [];
    _liveStatuses = {};
    _latest = null;
  }
}
