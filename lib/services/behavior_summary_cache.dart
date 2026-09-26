import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On-device cache for behavior_summary/behavior_summary_search monthly
/// docs (2026-09-20) - same motivating problem as WalletHistoryCache
/// (wallet_history_cache.dart), applied to the OTHER in-memory-only cache
/// this codebase still had: FirebaseHelper._behaviorSummaryCache is a
/// Map that never survives a cold start, so the full retention-window
/// fetch (3 core months + 12 search months) was paid again on the FIRST
/// restaurant visit of every single app session, forever, even though
/// every month except the current one is immutable once written.
///
/// WHY A MONTH IS SAFE TO CACHE PERMANENTLY: BehaviorTracker._flush only
/// ever writes to the CURRENT calendar month's docs (both
/// behavior_summary/{yearMonth} and behavior_summary_search/{yearMonth},
/// see that file's split write) - once a month rolls over, its docs are
/// never touched again by anything. So unlike WalletHistoryCache (where
/// "terminal" depends on a field on EACH row and must be re-checked), here
/// it is a single, cheap string comparison: a cached month is trustworthy
/// forever unless it equals the CURRENT year-month.
///
/// WHAT IS CACHED: the raw decoded field maps for each month, exactly as
/// Firestore returned them (before BehaviorSummarySnapshot.merge combines
/// them) - keeping the cache at the same granularity Firestore itself
/// uses means a newly-entered month can be added without re-touching
/// anything already cached, same "additive, not a full rewrite" shape as
/// WalletHistoryCache.merge.
class BehaviorSummaryCache {
  BehaviorSummaryCache._();

  static const String _prefsKeyPrefix = 'cached_behavior_summary_v1_';

  // 2026-09-26: the summary docs contain Firestore Timestamps, which plain
  // jsonEncode rejects - every write failed ("Converting object to an
  // encodable object failed: Instance of 'Timestamp'", seen on the device),
  // so nothing was ever cached and all months were re-read after every cold
  // start / 10-minute memory expiry. Encoded with full precision and turned
  // back into Timestamps on read, so consumers see the same types as from
  // Firestore.
  static Object? _encodeFallback(Object? v) {
    if (v is Timestamp) return {'__ts_s': v.seconds, '__ts_ns': v.nanoseconds};
    if (v is DateTime) return {'__ts_s': v.millisecondsSinceEpoch ~/ 1000, '__ts_ns': (v.millisecondsSinceEpoch % 1000) * 1000000};
    if (v is GeoPoint) return {'__geo_lat': v.latitude, '__geo_lng': v.longitude};
    throw UnsupportedError('Cannot cache behavior summary value of type ${v.runtimeType}');
  }

  static Object? _decodeReviver(Object? key, Object? value) {
    if (value is Map && value.containsKey('__ts_s')) {
      return Timestamp(value['__ts_s'] as int, value['__ts_ns'] as int);
    }
    if (value is Map && value.containsKey('__geo_lat')) {
      return GeoPoint((value['__geo_lat'] as num).toDouble(), (value['__geo_lng'] as num).toDouble());
    }
    return value;
  }
  static String _prefsKey(String userId) => '$_prefsKeyPrefix$userId';

  /// A month is safe to trust from cache forever once it is no longer the
  /// current calendar month - see class doc comment for why.
  static bool isSealed(String yearMonth, String currentYearMonth) =>
      yearMonth != currentYearMonth;

  /// Returns the cached (core months, search months) field-map pairs for
  /// [userId], or two empty maps on any read failure / first-ever open.
  static Future<(Map<String, Map<String, dynamic>>, Map<String, Map<String, dynamic>>)>
      read(String userId) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefsKey(userId));
      if (raw == null || raw.isEmpty) return (<String, Map<String, dynamic>>{}, <String, Map<String, dynamic>>{});
      final decoded = jsonDecode(raw, reviver: _decodeReviver);
      if (decoded is! Map) return (<String, Map<String, dynamic>>{}, <String, Map<String, dynamic>>{});
      final core = _decodeMonths(decoded['core']);
      final search = _decodeMonths(decoded['search']);
      return (core, search);
    } catch (_) {
      return (<String, Map<String, dynamic>>{}, <String, Map<String, dynamic>>{});
    }
  }

  static Map<String, Map<String, dynamic>> _decodeMonths(dynamic raw) {
    final out = <String, Map<String, dynamic>>{};
    if (raw is! Map) return out;
    raw.forEach((k, v) {
      if (v is Map) out[k.toString()] = v.cast<String, dynamic>();
    });
    return out;
  }

  /// Persists the union of whatever is already cached and [freshCore]/
  /// [freshSearch] (fresh wins per-month, same "newer data replaces older"
  /// rule as WalletHistoryCache.merge) - callers pass only the months they
  /// actually fetched this call, not the full merged set, so a partial
  /// fetch (e.g. only the current month, the common case after the first
  /// seed) never drops already-cached sealed months that weren't
  /// re-fetched this time.
  static Future<void> write(
    String userId, {
    required Map<String, Map<String, dynamic>> existingCore,
    required Map<String, Map<String, dynamic>> existingSearch,
    required Map<String, Map<String, dynamic>> freshCore,
    required Map<String, Map<String, dynamic>> freshSearch,
  }) async {
    try {
      final mergedCore = {...existingCore, ...freshCore};
      final mergedSearch = {...existingSearch, ...freshSearch};
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefsKey(userId),
          jsonEncode({'core': mergedCore, 'search': mergedSearch}, toEncodable: _encodeFallback));
    } catch (e) {
      debugPrint('[BehaviorSummaryCache] write failed (non-fatal): $e');
    }
  }

  /// Clears this user's cached summary - for logout, so one account's
  /// behavior history can never be shown under another.
  static Future<void> clear(String userId) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_prefsKey(userId));
    } catch (_) {}
  }
}
