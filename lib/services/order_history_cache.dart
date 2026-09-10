import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/OrderModel.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local, on-device long-term cache for orders that will never change again
/// (2026-09-09) - companion to SharedOrdersWatcher. Root problem this closes:
/// that watcher's query re-reads the same ~20 most recent orders from
/// Firestore on every single app cold start, even when literally nothing
/// about them has changed since the last time - confirmed live via device
/// log (20 documents read via a forced .get(), then the SAME 20 read AGAIN
/// via .snapshots()' own first emission - "up to 40 reads" on every first
/// Orders visit per session, for every customer, every day, regardless of
/// whether anything actually happened).
///
/// A completed/rejected order is immutable from that point on - re-reading
/// it from the server on every reopen buys nothing. This file persists
/// exactly those orders (and only those) to SharedPreferences as JSON, so
/// SharedOrdersWatcher can paint them instantly with zero network cost and
/// only ever ask Firestore about orders that could plausibly still change.
///
/// Deliberately NOT a new Drift/Moor table alongside CartProducts in
/// localDatabase.dart - this project has no moor_generator/build_runner/
/// drift_dev dependency in pubspec.yaml, so localDatabase.g.dart cannot be
/// regenerated here, and hand-writing Moor's generated boilerplate correctly
/// without being able to run the generator is not a safe bet. SharedPreferences
/// + JSON is the same storage mechanism this codebase already trusts for the
/// `sections` cache and the cached user profile (see main.dart) - proven,
/// zero-build-step, good enough for what's realistically a few hundred KB
/// even for a very active customer's settled-order history.
///
/// Timestamp fields (createdAt, statusUpdatedAt, etc.) are not natively
/// JSON-string-encodable - reuses the exact same {'__ts': millis} / GeoPoint
/// marker scheme main.dart's _cacheEncodeFallback/_cacheDecodeReviver already
/// use for the cached user profile, duplicated locally here (small, stable,
/// not worth a shared-utility refactor of main.dart for two call sites).
Object? _orderCacheEncodeFallback(Object? obj) {
  if (obj is Timestamp) return {'__ts': obj.millisecondsSinceEpoch};
  if (obj is GeoPoint) return {'__geo_lat': obj.latitude, '__geo_lng': obj.longitude};
  throw UnsupportedError('Cannot cache order field of type ${obj.runtimeType}');
}

Object? _orderCacheDecodeReviver(Object? key, Object? value) {
  if (value is Map && value.containsKey('__ts')) {
    return Timestamp.fromMillisecondsSinceEpoch(value['__ts'] as int);
  }
  if (value is Map && value.containsKey('__geo_lat')) {
    return GeoPoint((value['__geo_lat'] as num).toDouble(), (value['__geo_lng'] as num).toDouble());
  }
  return value;
}

// Every status a vendor_orders document can reach with zero legitimate
// outgoing transition left - verified against firestore.rules'
// isValidVendorStatusTransition() (Admin Panel repo) rather than guessed:
// Order Placed -> Order Accepted -> Order Completed, or Order Placed ->
// Order Rejected; a vendor-sent Bill Pay request separately terminates at
// Declined by Customer / Expired / Cancelled by Vendor. Delivery orders have
// no formally-enforced state machine at all (that rules branch is
// deliberately left unrestricted) - status alone is NOT trusted as proof of
// terminality for them, which is exactly what the age margin below is for.
const Set<String> kTerminalOrderStatuses = {
  ORDER_STATUS_COMPLETED,
  ORDER_STATUS_REJECTED,
  BILLPAY_STATUS_DECLINED,
  BILLPAY_STATUS_EXPIRED,
  BILLPAY_STATUS_CANCELLED,
};

// Age margin required on TOP OF a terminal status before an order is
// considered safe to cache permanently and drop from live watching - not
// just an arbitrary safety buffer. This is what makes the Delivery-status
// uncertainty above harmless (any real correction/dispute plays out within
// hours, not exactly at the terminal-status instant), and it's also why no
// separate special-case is needed for a vendor-sent Bill Pay request: that
// document is created by the vendor and always starts at "Pending Approval"
// (never terminal), with a 60-minute response deadline - it is structurally
// impossible for one to be both terminal AND old enough to pass this margin
// while still needing a customer's live attention.
const Duration kOrderSettledAgeMargin = Duration(hours: 24);

bool isOrderSafeToCachePermanently(OrderModel order) {
  if (!kTerminalOrderStatuses.contains(order.status)) return false;
  final referenceTime = (order.statusUpdatedAt ?? order.createdAt).toDate();
  return DateTime.now().difference(referenceTime) > kOrderSettledAgeMargin;
}

const String _cachedOrdersKeyPrefix = 'cached_settled_orders_';
const String _lastFullSyncAtKeyPrefix = 'orders_last_full_sync_at_';

// How often the "blanket" catch-up query (most recent N orders, regardless
// of what's already cached) is allowed to run - a deliberate defensive
// safety net against something the narrow, targeted queries wouldn't be
// watching for (e.g. an admin-side correction to an already-settled order),
// not the primary sync mechanism. Long horizon since settled order history
// essentially never changes on its own - unlike `sections` (admin config
// that legitimately changes a few times a year), this is purely insurance.
const Duration kFullReconciliationInterval = Duration(days: 7);

Future<List<OrderModel>> loadCachedSettledOrders(String uid) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_cachedOrdersKeyPrefix$uid');
    if (raw == null) return [];
    final decoded = json.decode(raw, reviver: _orderCacheDecodeReviver) as List<dynamic>;
    final orders = <OrderModel>[];
    for (final entry in decoded) {
      try {
        orders.add(OrderModel.fromJson(entry as Map<String, dynamic>));
      } catch (e) {
        debugPrint('[OrderHistoryCache] failed to parse one cached order, skipping it: $e');
      }
    }
    return orders;
  } catch (e) {
    debugPrint('[OrderHistoryCache] loadCachedSettledOrders failed, ignoring cache: $e');
    return [];
  }
}

// Hard cap on how many settled orders this cache will ever hold on disk
// (2026-09-09) - without one, both the on-disk SharedPreferences blob and
// the in-memory _ordersById map it seeds on every start() would grow
// without bound over a customer's lifetime of app usage (SharedPreferences/
// plist-backed storage is not built for a large, ever-growing single blob -
// every write rewrites the whole thing). 25 matches
// SharedOrdersWatcher.kTopWatchWindow - the app has never shown more than
// that many orders at once anyway (no pagination past it exists in
// OrdersScreen today), so this removes nothing a user could actually see,
// it just stops the cache from growing forever. Older settled orders are
// pruned on write, oldest-createdAt-first.
const int kMaxCachedSettledOrders = 25;

/// Merges `newlySettled` into whatever's already cached (by order id, newest
/// write wins), prunes down to kMaxCachedSettledOrders (oldest first), and
/// persists the result. Safe to call repeatedly with an empty list -
/// callers don't need to check "is there anything new" first.
Future<void> mergeSettledOrdersIntoCache(String uid, List<OrderModel> newlySettled) async {
  if (newlySettled.isEmpty) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadCachedSettledOrders(uid);
    final byId = {for (final o in existing) o.id: o};
    for (final order in newlySettled) {
      byId[order.id] = order;
    }
    final capped = byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final kept = capped.take(kMaxCachedSettledOrders).toList();
    final encoded = json.encode(
      kept.map((o) => o.toJson()).toList(),
      toEncodable: _orderCacheEncodeFallback,
    );
    await prefs.setString('$_cachedOrdersKeyPrefix$uid', encoded);
  } catch (e) {
    debugPrint('[OrderHistoryCache] mergeSettledOrdersIntoCache failed, skipping: $e');
  }
}

Future<bool> fullReconciliationDue(String uid) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt('$_lastFullSyncAtKeyPrefix$uid');
    if (millis == null) return true;
    final lastSync = DateTime.fromMillisecondsSinceEpoch(millis);
    return DateTime.now().difference(lastSync) > kFullReconciliationInterval;
  } catch (_) {
    return true;
  }
}

Future<void> markFullReconciliationDone(String uid) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_lastFullSyncAtKeyPrefix$uid', DateTime.now().millisecondsSinceEpoch);
  } catch (e) {
    debugPrint('[OrderHistoryCache] markFullReconciliationDone failed, skipping: $e');
  }
}

/// Call on logout - a different account on the same device must never see a
/// previous customer's cached order history. Mirrors
/// SharedOrdersWatcher.stop()'s own per-account clearing intent.
Future<void> clearCachedOrders(String uid) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_cachedOrdersKeyPrefix$uid');
    await prefs.remove('$_lastFullSyncAtKeyPrefix$uid');
  } catch (_) {}
}
