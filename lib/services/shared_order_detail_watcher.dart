import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/firestore_instrumentation.dart';
import 'package:flutter/foundation.dart';

/// Shared, per-order-id live listener for OrderDetailsScreen (2026-09-15).
///
/// WHY THIS EXISTS - two real, confirmed problems, both from the same root
/// cause: OrderDetailsScreen previously opened its OWN raw `.snapshots()`
/// listener on `ORDERS/{orderId}` as a plain instance field, both problems
/// following directly from that:
///
///   1. WITHIN one screen visit, it opened TWO separate listeners on the
///      SAME document - `_cachedOrderStatusStream` (for the main UI) and
///      `getCurrentOrder()` (for the map/driver-tracking side, via
///      `FireStoreUtils.getOrderByID`) - confirmed live 2026-09-15 as two
///      distinct `[FirestoreListener]` lines, `getOrderByID:ORDERS` and
///      `watchOrderStatus:ORDERS`, both `docs=1`, for the identical order.
///   2. ACROSS repeat visits, a customer checking their order status by
///      backing out and re-opening this screen re-attached BOTH listeners
///      fresh every single time, because instance fields die with the
///      widget - unlike SharedOrdersWatcher/SharedVendorsWatcher, which are
///      already session-scoped singletons for exactly this reason.
///
/// This class fixes both: ONE real listener per order id, shared by every
/// consumer within a visit AND reused across repeat visits to the same
/// order, via the same "watch() returns the existing stream if already
/// open" pattern already established elsewhere in this codebase.
///
/// Deliberately keyed per-order (a Map of watchers), not a single global
/// stream like SharedOrdersWatcher - a customer only ever has one order
/// detail screen open at a time in practice, but nothing here assumes that;
/// two different orders watched concurrently just get two independent
/// entries.
class SharedOrderDetailWatcher {
  SharedOrderDetailWatcher._();

  static final Map<String, _WatchEntry> _entries = {};

  // Grace period before a real listener is actually torn down after its last
  // subscriber unwatches. Covers the common "tapped back, immediately tapped
  // back in again" case with zero re-fetch cost, while still releasing a
  // genuinely abandoned order's listener eventually instead of leaking it for
  // the rest of the session.
  static const Duration _teardownGracePeriod = Duration(minutes: 2);

  /// Starts (or reuses) the live listener for [orderId] and returns its
  /// broadcast stream of raw document snapshots - callers parse into
  /// whatever shape they need (OrderModel, or read fields directly), exactly
  /// as the single listener this replaces already allowed both of its
  /// consumers to do independently.
  ///
  /// Replays the latest known snapshot immediately on subscribe (if any),
  /// same "seed from what's already known" pattern as
  /// SharedVendorsWatcher/SharedOrdersWatcher, so a second consumer
  /// subscribing moments after the first doesn't have to wait for a fresh
  /// server round trip to see data that already arrived.
  ///
  /// Call [unwatch] with the same [orderId] when a consumer no longer needs
  /// updates (typically the screen's dispose()) - failing to call it leaks
  /// the listener for the rest of the app session, same risk any live
  /// listener carries.
  static Stream<DocumentSnapshot<Map<String, dynamic>>> watch(String orderId) {
    final entry = _entries.putIfAbsent(orderId, () => _WatchEntry(orderId));
    entry.refCount++;
    entry.teardownTimer?.cancel();
    entry.teardownTimer = null;
    entry.ensureStarted();
    return entry.replayStream();
  }

  /// Releases one subscriber's interest in [orderId]. The real listener stays
  /// open for [_teardownGracePeriod] after the last one unwatches, in case
  /// the same order is watched again shortly (e.g. the user backs out and
  /// back in within a couple of minutes) - only torn down if nothing re-
  /// watches within that window.
  static void unwatch(String orderId) {
    final entry = _entries[orderId];
    if (entry == null) return;
    entry.refCount--;
    if (entry.refCount > 0) return;
    entry.teardownTimer?.cancel();
    entry.teardownTimer = Timer(_teardownGracePeriod, () {
      final current = _entries[orderId];
      if (current == null || current.refCount > 0) return;
      current.dispose();
      _entries.remove(orderId);
    });
  }
}

class _WatchEntry {
  _WatchEntry(this.orderId);

  final String orderId;
  int refCount = 0;
  Timer? teardownTimer;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  final StreamController<DocumentSnapshot<Map<String, dynamic>>> _controller =
      StreamController<DocumentSnapshot<Map<String, dynamic>>>.broadcast();
  DocumentSnapshot<Map<String, dynamic>>? _latest;

  Stream<DocumentSnapshot<Map<String, dynamic>>> replayStream() async* {
    final latest = _latest;
    if (latest != null) yield latest;
    yield* _controller.stream;
  }

  void ensureStarted() {
    if (_sub != null) return;
    _sub = FireStoreUtils.firestore
        .collection(ORDERS)
        .doc(orderId)
        .snapshotsLogged('SharedOrderDetailWatcher:ORDERS')
        .listen((snap) {
      _latest = snap;
      if (!_controller.isClosed) _controller.add(snap);
    }, onError: (Object e) {
      debugPrint('[SharedOrderDetailWatcher] $orderId stream error: $e');
    });
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _controller.close();
  }
}
