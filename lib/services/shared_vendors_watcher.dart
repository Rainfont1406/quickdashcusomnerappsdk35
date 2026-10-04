import 'dart:async';
import 'dart:math' as math;

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
///     2026-09-27 (Option B): that listener is REMOVED. Open/closed comes
///     from the Bunny file vendor-status/{sectionId}.json (rewritten on
///     every vendor write), re-checked every 5 min while Home is on screen;
///     see kStatusRefreshTtl below. The server still writes vendor_status:
///     older app builds listen to it, and this build reads it once only as
///     a fallback when Bunny has no status file.
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

  static final StreamController<List<VendorModel>> _controller =
      StreamController<List<VendorModel>>.broadcast();
  static List<VendorModel> _baseVendors = [];
  // True once the section list has loaded for the active (section, location),
  // so an EMPTY in-radius list can be told apart from "not loaded yet" and
  // still reach Home (which then shows its "not available in this region"
  // message instead of waiting forever behind the loading skeleton).
  static bool _baseLoaded = false;
  static List<VendorModel>? _latest;
  static String? _activeKey;

  /// 2026-09-27 (Option B): open/closed comes from its own tiny Bunny file,
  /// vendor-status/{sectionId}.json ({vendorId: open?}, ~30 B a vendor),
  /// laid over the vendor list (which no longer carries reststatus). The
  /// vendor_status live listener is gone, so a vendor switching open/closed
  /// costs customers 0 Firestore reads and never makes them re-download the
  /// big list. The status file is re-checked with a conditional GET
  /// (unchanged = empty 304) once it is older than [kStatusRefreshTtl];
  /// Home drives that check only while it is on screen. Showing a status up
  /// to ~5 min old is safe: Cart re-reads vendor_live from Firestore before
  /// checkout, and the server gates (createVerifiedOrderPayment/WalletOrder/
  /// CodOrder, createS2SUpiIntent) re-check the real vendor doc.
  static const Duration kStatusRefreshTtl = Duration(minutes: 5);
  static Map<String, bool>? _statuses;
  static bool _checking = false;
  static String? _pendingSection; // a load asked for while one was running
  static bool _pendingForce = false;
  static DateTime? _lastFirestoreFallbackAt;

  /// 2026-09-25: a vendor from the list this watcher already holds on the
  /// phone (Bunny vendor list + Bunny open/closed overlay) - 0 Firestore
  /// reads. null when the list isn't loaded yet, the vendor isn't in it
  /// (unapproved/inactive vendors are filtered out of it), or - when
  /// [sectionId] is given - the list belongs to a different section.
  static VendorModel? findInCurrentList(String vendorId, {String? sectionId}) {
    final key = _activeKey;
    final list = _latest;
    if (key == null || list == null || vendorId.isEmpty) return null;
    if (sectionId != null && sectionId.isNotEmpty && !key.startsWith('$sectionId:')) {
      return null;
    }
    for (final v in list) {
      if (v.id == vendorId) return v;
    }
    return null;
  }

  /// For screens that only need a vendor to show it and open its page (e.g.
  /// the story header): the on-phone list first, else the existing
  /// 10-minute-cached full read.
  static Future<VendorModel?> resolveForDisplay(String vendorId) async {
    return findInCurrentList(vendorId) ?? await FireStoreUtils.getVendor(vendorId);
  }

  static String _keyFor(String sectionId, double lat, double lng) {
    // Rounded to ~1km so tiny GPS jitter between visits doesn't count as a
    // "location changed, restart" event.
    return '$sectionId:${lat.toStringAsFixed(2)}:${lng.toStringAsFixed(2)}';
  }

  /// Call from HomeScreen.getData() instead of fireStoreUtils.getAllStores()
  /// directly. Safe to call on every visit - only loads the list the first
  /// time for this (section, location); every later call returns the same
  /// shared stream, seeded with whatever's already known, and re-checks the
  /// status file only once it is older than [kStatusRefreshTtl].
  static Stream<List<VendorModel>> watch(
      String sectionId, double lat, double lng) {
    final key = _keyFor(sectionId, lat, lng);
    if (_activeKey != key) {
      start(sectionId, lat, lng);
    } else {
      refreshIfStale();
    }
    return _replay();
  }

  /// Brings open/closed up to date if the phone's copy of the status file
  /// is older than [kStatusRefreshTtl] (the age is tracked by the Bunny
  /// cache itself, across app restarts). Inside that window this is a local
  /// read only - so it is safe to call from timers, rebuilds and route
  /// changes. Past it: one conditional GET (unchanged = empty 304).
  static void refreshIfStale() {
    final key = _activeKey;
    if (key == null) return;
    _loadStatuses(key.split(':').first);
  }

  static Stream<List<VendorModel>> _replay() async* {
    if (_latest != null) yield _latest!;
    yield* _controller.stream;
  }

  /// Starts (or restarts) the shared watcher for this (section, location).
  /// Called directly by HomeScreen's pull-to-refresh with [revalidate] set
  /// (the one thing that should force a fresh check right away).
  ///
  /// 2026-09-27: the list first comes from the phone (up to 24 h old), then
  /// ONE "has it changed on Bunny?" check runs - on the first start of this
  /// app process (cold start) and when [revalidate] is set (pull-to-refresh).
  /// Unchanged = empty 304 (~0.9 KB), 0 Firestore; changed = the new list is
  /// downloaded and shown (e.g. a vendor's new working hours). Open/closed
  /// comes from the status file ([_loadStatuses]); [revalidate] forces that
  /// check too.
  static void start(String sectionId, double lat, double lng, {bool revalidate = false}) {
    final previousSection = _activeKey?.split(':').first;
    final previousStatuses = _statuses;
    stop();
    if (sectionId.isEmpty) return;
    _activeKey = _keyFor(sectionId, lat, lng);
    // Same section (location change, pull-to-refresh): keep showing the
    // open/closed we already have until the fresh copy arrives.
    if (previousSection == sectionId) _statuses = previousStatuses;

    final checkList = revalidate || _checkedThisProcess.add(sectionId);
    _loadBaseVendors(sectionId, lat, lng).then((_) {
      if (checkList) _revalidate(sectionId, lat, lng);
    });
    _loadStatuses(sectionId, force: revalidate);
  }

  static final Set<String> _checkedThisProcess = {};

  static Future<void> _revalidate(String sectionId, double lat, double lng) async {
    final changed = await revalidateVendorListFromBunny(sectionId);
    if (changed == null) return;
    if (_activeKey != _keyFor(sectionId, lat, lng)) return; // moved on meanwhile
    _baseVendors = _withinRadius(changed, lat, lng);
    _emit();
  }

  /// Loads the open/closed map: the phone's copy while it is younger than
  /// [kStatusRefreshTtl], else a conditional GET of the Bunny status file
  /// ([force] = ask Bunny now, for pull-to-refresh). Only if Bunny has
  /// nothing at all (e.g. the file isn't published yet) does it fall back to
  /// ONE Firestore read of vendor_status - at most once per
  /// [kStatusRefreshTtl], never on a timer loop.
  static Future<void> _loadStatuses(String sectionId, {bool force = false}) async {
    if (sectionId.isEmpty) return;
    if (_checking) {
      _pendingSection = sectionId;
      _pendingForce = _pendingForce || force;
      return;
    }
    _checking = true;
    try {
      Map<String, bool>? statuses;
      if (force) statuses = await revalidateVendorStatusesFromBunny(sectionId);
      statuses ??= await fetchVendorStatusesFromBunny(sectionId, kStatusRefreshTtl);
      statuses ??= await _statusesFromFirestore(sectionId);
      final key = _activeKey;
      if (key == null || key.split(':').first != sectionId) return; // moved on
      if (statuses == null) {
        // Nothing from Bunny or Firestore (offline, no copy on the phone):
        // still show the list rather than nothing; the next check retries.
        if (_statuses == null) {
          _statuses = const {};
          _emit();
        }
        return;
      }
      if (mapEquals(statuses, _statuses)) return; // nothing changed on screen
      _statuses = statuses;
      _emit();
    } finally {
      _checking = false;
      final pending = _pendingSection;
      if (pending != null) {
        final pendingForce = _pendingForce;
        _pendingSection = null;
        _pendingForce = false;
        _loadStatuses(pending, force: pendingForce);
      }
    }
  }

  static Future<Map<String, bool>?> _statusesFromFirestore(String sectionId) async {
    final last = _lastFirestoreFallbackAt;
    if (last != null && DateTime.now().difference(last) < kStatusRefreshTtl) return null;
    _lastFirestoreFallbackAt = DateTime.now();
    try {
      final snap = await FireStoreUtils.firestore
          .collection('vendor_status')
          .doc(sectionId)
          .getLogged('SharedVendorsWatcher:vendor_status-fallback');
      final raw = snap.data()?['statuses'];
      if (raw is! Map) return null;
      return raw.map((k, v) => MapEntry(k.toString(), v == true));
    } catch (e) {
      debugPrint('[SharedVendorsWatcher] status fallback read failed: $e');
      return null;
    }
  }

  // TEST BUILDS ONLY: `--dart-define=TEST_RADIUS_KM=1` overrides the section's
  // nearByRadius so an empty region / a real cap can be tried on a phone without
  // touching the live admin value. Unset (the default, and every release build
  // meant for users) = no override.
  static final double _testRadiusKm =
      double.tryParse(const String.fromEnvironment('TEST_RADIUS_KM')) ?? -1;

  static List<VendorModel> _withinRadius(List<VendorModel> vendors, double lat, double lng) {
    final radiusKm = _testRadiusKm > 0
        ? _testRadiusKm
        : sectionConstantModel?.nearByRadius?.toDouble();
    if (radiusKm == null) return vendors;
    return vendors.where((v) => _distanceKm(lat, lng, v.latitude, v.longitude) <= radiusKm).toList();
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
      _baseVendors = _withinRadius(vendors, lat, lng);
      _baseLoaded = true;
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
    // Wait for open/closed too: the list no longer carries it, and showing
    // the list first would flash every restaurant as closed.
    final statuses = _statuses;
    if ((_baseVendors.isEmpty && !_baseLoaded) || statuses == null) return;
    final list = _baseVendors.map((v) {
      final open = statuses[v.id];
      if (open != null) v.reststatus = open;
      return v;
    }).toList();
    _latest = list;
    if (!_controller.isClosed) _controller.add(list);
  }

  /// Called on app resume after a long background (main.dart). There is no
  /// live listener to reconnect any more, so this just re-checks the status
  /// file if it is older than [kStatusRefreshTtl].
  static void restartIfActive() => refreshIfStale();

  static void stop() {
    _activeKey = null;
    _baseVendors = [];
    _baseLoaded = false;
    _statuses = null;
    _latest = null;
  }
}
