import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/BookTableModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/firestore_instrumentation.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dine-in booking History tab (2026-09-26) - same idea as
/// SharedOrdersWatcher + order_history_cache for orders:
///
/// - past bookings older than [kLiveWindow] are finished history: kept on
///   the device (newest [kMaxCached]) and never downloaded again;
/// - past bookings inside [kLiveWindow] can still change (vendor marks the
///   visit completed / no-show, a deposit refund) so they come from a live
///   Firestore listener, with NO count limit;
/// - a newly-seen finished booking is cached straight away;
/// - an empty cache (cleared data / reinstall / new phone) loads only the
///   recent [kFirstPage] finished bookings; "Show older bookings" pages
///   [kOlderPage] more at a time.
///
/// Measured before this (device audit 2026-09-26, heavy test customer):
/// every History open re-downloaded all 12 past bookings = 12 reads,
/// 112.6 KB, because nothing was kept on the device. Upcoming bookings are
/// unchanged (FireStoreUtils.getBookingOrders, live, no limit).
class BookingHistoryWatcher {
  BookingHistoryWatcher(this.uid) : sectionId = sectionConstantModel?.id ?? '';

  static const Duration kLiveWindow = Duration(days: 3);
  static const int kFirstPage = 5;
  static const int kOlderPage = 10;
  static const int kMaxCached = 20;
  static const String _keyPrefix = 'cached_booking_history_';

  final String uid;
  final String sectionId;

  final ValueNotifier<bool> hasOlder = ValueNotifier<bool>(false);
  final ValueNotifier<bool> loadingOlder = ValueNotifier<bool>(false);

  final _controller = StreamController<List<BookTableModel>>.broadcast();
  final Map<String, BookTableModel> _byId = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _liveSub;
  // (date, createdAt) of the last booking shown - several bookings often share
  // the same date (same slot), so a date-only cursor would skip them
  // (caught by verify_orders_paging.py on production data).
  List<Object>? _olderCursor;
  // (date, createdAt) of the newest cached booking while a gap above the
  // cache is being filled - used as an exclusive endBefore bound.
  List<Object>? _olderFloor;
  bool _disposed = false;
  List<BookTableModel>? _latest;

  String get _key => '$_keyPrefix${uid}_$sectionId';

  Stream<List<BookTableModel>> get stream async* {
    if (_latest != null) yield _latest!;
    yield* _controller.stream;
  }

  Query<Map<String, dynamic>> get _mine => FireStoreUtils.firestore
      .collection(ORDERS_TABLE)
      .where('authorID', isEqualTo: uid)
      .where('section_id', isEqualTo: sectionId);

  // Same index as the History tab always used (authorID, section_id,
  // date desc, createdAt desc) - every query here only adds date bounds.
  Query<Map<String, dynamic>> _ordered(Query<Map<String, dynamic>> q) =>
      q.orderBy('date', descending: true).orderBy('createdAt', descending: true);

  Future<void> start() async {
    if (uid.isEmpty || sectionId.isEmpty) {
      _emit();
      return;
    }
    final cached = await _loadCache();
    if (_disposed) return;
    for (final b in cached) {
      _byId[b.id] = b;
    }
    if (cached.isNotEmpty) _emit();

    final now = Timestamp.now();
    final liveSince = Timestamp.fromDate(DateTime.now().subtract(kLiveWindow));

    // Live part: past bookings from the last kLiveWindow - no limit.
    var firstLive = true;
    _liveSub = _ordered(_mine
            .where('date', isLessThan: now)
            .where('date', isGreaterThanOrEqualTo: liveSince))
        .snapshotsLogged('BookingHistory:live')
        .listen((snap) {
      _merge(snap.docs);
      if (firstLive) {
        firstLive = false;
        unawaited(_fillHistory(cached, liveSince));
      } else {
        _emit();
      }
    }, onError: (Object e) {
      debugPrint('[BookingHistory] live stream error: $e');
      if (firstLive) {
        firstLive = false;
        unawaited(_fillHistory(cached, liveSince));
      }
    });
  }

  /// Finished bookings newer than the newest cached one (or the recent
  /// kFirstPage when the cache is empty), then cache everything finished.
  Future<void> _fillHistory(List<BookTableModel> cached, Timestamp liveSince) async {
    BookTableModel? newest;
    for (final b in cached) {
      if (newest == null) {
        newest = b;
        continue;
      }
      final byDate = b.date.compareTo(newest.date);
      if (byDate > 0 || (byDate == 0 && b.createdAt.compareTo(newest.createdAt) > 0)) newest = b;
    }
    final newestCached = newest == null ? null : <Object>[newest.date, newest.createdAt];
    try {
      // Newer than the newest cached booking: an exclusive (date, createdAt)
      // end bound - several bookings can share one date, and an inclusive
      // date bound would re-download the newest cached booking every time.
      var q = _ordered(_mine.where('date', isLessThan: liveSince));
      if (newestCached != null) q = q.endBefore(newestCached);
      final snap = await q.limit(kFirstPage).getLogged('BookingHistory:recent');
      if (_disposed) return;
      _merge(snap.docs);
      if (newestCached != null && snap.docs.length == kFirstPage) {
        _olderCursor = _cursorOf(snap.docs.last.data());
        _olderFloor = newestCached;
      } else {
        _olderCursor = _oldestKnown();
        _olderFloor = null;
      }
      hasOlder.value = !(cached.isEmpty && snap.docs.length < kFirstPage) && _olderCursor != null;
    } catch (e) {
      debugPrint('[BookingHistory] recent fetch failed: $e');
      _olderCursor = _oldestKnown();
      hasOlder.value = _olderCursor != null;
    }
    _emit();
    unawaited(_saveFinished());
  }

  Future<void> loadOlder() async {
    final cursor = _olderCursor;
    if (cursor == null || loadingOlder.value || _disposed) return;
    loadingOlder.value = true;
    try {
      final floor = _olderFloor;
      var q = _ordered(_mine).startAfter(cursor);
      if (floor != null) q = q.endBefore(floor);
      final snap = await q.limit(kOlderPage).getLogged('BookingHistory:older');
      if (_disposed) return;
      _merge(snap.docs);
      if (snap.docs.length == kOlderPage) {
        _olderCursor = _cursorOf(snap.docs.last.data());
      } else if (floor != null) {
        _olderFloor = null;
        _olderCursor = _oldestKnown();
      } else {
        hasOlder.value = false;
      }
      _emit();
      unawaited(_saveFinished());
    } catch (e) {
      debugPrint('[BookingHistory] load older failed: $e');
    } finally {
      if (!_disposed) loadingOlder.value = false;
    }
  }

  void _merge(Iterable<DocumentSnapshot<Map<String, dynamic>>> docs) {
    for (final doc in docs) {
      final data = doc.data();
      if (data == null) continue;
      try {
        _byId[doc.id] = BookTableModel.fromJson(data);
      } catch (e) {
        debugPrint('[BookingHistory] parse error ${doc.id} $e');
      }
    }
  }

  static List<Object>? _cursorOf(Map<String, dynamic> data) {
    final date = data['date'];
    final createdAt = data['createdAt'];
    if (date is! Timestamp || createdAt is! Timestamp) return null;
    return [date, createdAt];
  }

  List<Object>? _oldestKnown() {
    BookTableModel? oldest;
    for (final b in _byId.values) {
      if (oldest == null) {
        oldest = b;
        continue;
      }
      final byDate = b.date.compareTo(oldest.date);
      if (byDate < 0 || (byDate == 0 && b.createdAt.compareTo(oldest.createdAt) < 0)) oldest = b;
    }
    return oldest == null ? null : [oldest.date, oldest.createdAt];
  }

  void _emit() {
    if (_disposed) return;
    final list = _byId.values.toList()
      ..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
      });
    _latest = list;
    _controller.add(list);
  }

  // ── device cache (SharedPreferences, same encoding as order_history_cache) ──

  static Object? _encodeFallback(Object? obj) {
    // Full precision (seconds + nanoseconds) - see order_history_cache.dart.
    if (obj is Timestamp) return {'__ts_s': obj.seconds, '__ts_ns': obj.nanoseconds};
    if (obj is GeoPoint) return {'__geo_lat': obj.latitude, '__geo_lng': obj.longitude};
    throw UnsupportedError('Cannot cache booking field of type ${obj.runtimeType}');
  }

  static Object? _decodeReviver(Object? key, Object? value) {
    if (value is Map && value.containsKey('__ts_s')) {
      return Timestamp(value['__ts_s'] as int, value['__ts_ns'] as int);
    }
    if (value is Map && value.containsKey('__ts')) {
      return Timestamp.fromMillisecondsSinceEpoch(value['__ts'] as int);
    }
    if (value is Map && value.containsKey('__geo_lat')) {
      return GeoPoint((value['__geo_lat'] as num).toDouble(), (value['__geo_lng'] as num).toDouble());
    }
    return value;
  }

  Future<List<BookTableModel>> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      final decoded = json.decode(raw, reviver: _decodeReviver) as List<dynamic>;
      final out = <BookTableModel>[];
      for (final e in decoded) {
        try {
          out.add(BookTableModel.fromJson(Map<String, dynamic>.from(e as Map)));
        } catch (err) {
          debugPrint('[BookingHistory] skipping unreadable cached booking: $err');
        }
      }
      debugPrint('[BookingHistory] ${out.length} finished bookings from on-device cache - 0 Firestore reads');
      return out;
    } catch (e) {
      debugPrint('[BookingHistory] cache load failed, ignoring cache: $e');
      return [];
    }
  }

  /// Caches every known booking whose date is older than kLiveWindow
  /// (finished), newest kMaxCached kept.
  Future<void> _saveFinished() async {
    try {
      final cutoff = DateTime.now().subtract(kLiveWindow);
      // Same (date, createdAt) order as the queries, so the kept block is
      // contiguous and "Show older" continues exactly below it.
      final finished = _byId.values.where((b) => b.date.toDate().isBefore(cutoff)).toList()
        ..sort((a, b) {
          final byDate = b.date.compareTo(a.date);
          return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
        });
      if (finished.isEmpty) return;
      final encoded = json.encode(
        finished.take(kMaxCached).map((b) => b.toJson()).toList(),
        toEncodable: _encodeFallback,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, encoded);
    } catch (e) {
      debugPrint('[BookingHistory] cache write failed, skipping: $e');
    }
  }

  /// Call on logout - another account on this device must never see these.
  static Future<void> clear(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys().where((k) => k.startsWith('$_keyPrefix${uid}_')).toList()) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    _liveSub?.cancel();
    _controller.close();
    hasOlder.dispose();
    loadingOlder.dispose();
  }
}
