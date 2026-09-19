import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/OrderModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/firestore_instrumentation.dart';
import 'package:emartconsumer/services/order_history_cache.dart';
import 'package:flutter/foundation.dart';

/// Shared, app-session-scoped replacement for the old per-screen
/// FireStoreUtils.getOrders() (2026-09-06). That version opened a brand-new
/// Firestore listener every time OrdersScreen was constructed - which
/// sounds correct, but ContainerScreen's drawer places OrdersScreen at the
/// same widget-tree slot on every tap with no key, so Flutter reused the
/// same Element/State and initState() (and therefore getOrders()) only
/// ever ran on the FIRST Orders visit for that app session. Confirmed live:
/// one account's Orders list stayed frozen at its state from days earlier,
/// straight through two real new orders that independently verified as
/// correctly matching the query.
///
/// This class inverts the ownership: the listener is opened once per
/// account (not per screen), stays alive for the whole session, and every
/// OrdersScreen visit - 1st or 50th - just reads whatever this already has
/// in memory. The only "cost" comes from real order activity (a new order,
/// a status change), not from how many times the customer happens to check
/// the tab - same shared-singleton shape as vendorApp/vendorWeb's
/// watchOrdersStatus (see FirebaseHelper.dart there), and the same
/// start()/stop() lifecycle as PurchaseCompletionListener in this app.
///
/// 2026-09-09 rewrite: the above closed the "re-listen every screen visit"
/// waste, but every cold start (a genuinely new app process) still re-paid
/// the full cost of re-reading the same ~20 recent orders from Firestore
/// twice over (a forced .get() plus .snapshots()' own first emission -
/// confirmed live via device log, "up to 40 reads" on every first Orders
/// visit per session) even when nothing about them had changed since the
/// last time. Root cause: a settled (Completed/Rejected/etc.) order is
/// immutable from that point on, but the old query treated every visit as
/// if it needed to re-verify the whole recent-history window from scratch.
///
/// Now: settled-and-old orders live in a local on-device cache
/// (order_history_cache.dart) and are never re-fetched. Only two things are
/// ever asked of Firestore on start(): (1) anything created after the
/// newest order already known (catches a genuinely new order, including a
/// vendor-sent Bill Pay request, arriving live), and (2) an explicit re-check
/// of whichever known orders aren't yet proven safe to stop watching -
/// typically 0-3 documents for a normal customer, never the whole history.
/// Both are bounded to kTopWatchWindow (25) orders, which is also the safety
/// margin for a vendor-sent Bill Pay request's 60-minute response deadline:
/// such a request is brand new the moment it exists, so it can never fall
/// outside "the most recent 25" while it's still actually live. A separate,
/// deliberately infrequent (weekly) full reconciliation pass exists purely
/// as a defensive backstop against something neither of the above would be
/// watching for (e.g. an admin-side correction to an already-settled order).
///
/// Same merge-by-Firestore-doc-id logic as the old getOrders() (never
/// wholesale-replaced across sources) - see that method's own doc comment
/// for the exact production bug (either source can independently come back
/// missing a handful of the customer's own recent orders) this guards
/// against.
class SharedOrdersWatcher {
  SharedOrdersWatcher._();

  // Bounds both the "what's new" and the (rare) full-reconciliation queries.
  // Also the safety margin discussed above for a vendor-sent Bill Pay
  // request's live-response window - see the class doc comment.
  static const int kTopWatchWindow = 25;

  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _newSub;
  static final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _activeSubs = [];
  static final StreamController<List<OrderModel>> _controller =
      StreamController<List<OrderModel>>.broadcast();
  static final Map<String, OrderModel> _ordersById = {};
  static List<OrderModel>? _latest;
  static String? _activeUid;

  /// Call from OrdersScreen.initState() instead of the old getOrders(). Safe
  /// to call every time the screen opens - only starts a real listener the
  /// first time for this uid; every later call just returns the same shared
  /// stream, seeded with whatever's already known so a fresh subscriber
  /// never has to wait for a network round trip to show something.
  static Stream<List<OrderModel>> watch(String uid) {
    if (_activeUid != uid || _newSub == null) start(uid);
    return _replay();
  }

  /// PASSIVE subscription to whatever this watcher is ALREADY emitting.
  ///
  /// Unlike [watch], this deliberately never calls [start] - so subscribing
  /// costs zero Firestore reads. A passive subscriber simply hears nothing
  /// until something else (today: OrdersScreen) starts the watcher for real.
  ///
  /// Added 2026-09-15 for PurchaseCompletionListener, which used to run its
  /// own independent vendor_orders query on every cold start purely to notice
  /// orders reaching "Order Completed". Those exact documents are already read
  /// here whenever the customer opens their Orders screen, so piggy-backing on
  /// this stream gets the same signal for free instead of paying for it twice.
  /// Callers MUST NOT treat silence as "no completed orders" - it usually just
  /// means the watcher isn't running.
  ///
  /// 2026-09-16: now replays whatever [_latest] the watcher already knows
  /// (same "seed from what's already known" as [_replay]/[watch], just
  /// without ever calling [start]) - previously returned [_controller.stream]
  /// directly, so an order that had already completed by the time a passive
  /// subscriber attached (e.g. OrdersScreen was already open and delivered
  /// it before PurchaseCompletionListener subscribed) was missed on this
  /// path entirely, silently falling through to the weekly full-sweep
  /// backstop instead of being noticed immediately. Each access to this
  /// getter returns a fresh single-subscription stream (same as [_replay]),
  /// so it's safe for a new subscriber to call this again later even while
  /// an earlier one is still listening.
  static Stream<List<OrderModel>> get passiveStream => _passiveReplay();

  static Stream<List<OrderModel>> _replay() async* {
    if (_latest != null) yield _latest!;
    yield* _controller.stream;
  }

  static Stream<List<OrderModel>> _passiveReplay() async* {
    if (_latest != null) yield _latest!;
    yield* _controller.stream;
  }

  static void _emit() {
    final sorted = _ordersById.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _latest = sorted;
    if (!_controller.isClosed) _controller.add(sorted);
  }

  // Debounces the actual disk write below - both live listeners call
  // _promoteSettledOrders() after every single emission, and
  // mergeSettledOrdersIntoCache() re-reads and rewrites the whole cache
  // blob each time it actually runs. Two quick, unrelated field updates on
  // the same order (a real, observed pattern - e.g. status then a courier
  // field moments later) would otherwise mean two full cache rewrites for
  // zero additional benefit. Collapsing bursts into one write after a short
  // quiet period fixes that without changing what ends up cached.
  static Timer? _cacheWriteDebounce;
  static final Set<String> _pendingPromotionIds = {};

  /// Marks whichever currently-known orders have now become safe to cache
  /// permanently (terminal status + past the age margin - see
  /// order_history_cache.dart) and schedules a debounced write. Cheap and
  /// safe to call after every listener emission - it's a no-op unless
  /// something actually just settled.
  static void _promoteSettledOrders(String uid) {
    final newlySettled =
        _ordersById.values.where(isOrderSafeToCachePermanently);
    for (final order in newlySettled) {
      _pendingPromotionIds.add(order.id);
    }
    if (_pendingPromotionIds.isEmpty) return;

    _cacheWriteDebounce?.cancel();
    _cacheWriteDebounce = Timer(const Duration(seconds: 2), () {
      if (_activeUid != uid) return; // account switched while this was pending
      final toWrite = _pendingPromotionIds
          .map((id) => _ordersById[id])
          .whereType<OrderModel>()
          .toList();
      _pendingPromotionIds.clear();
      unawaited(mergeSettledOrdersIntoCache(uid, toWrite));
    });
  }

  /// Starts (or restarts) the shared watcher for this uid. Only tears down
  /// this instance's own live listeners - deliberately does NOT clear
  /// _ordersById/_latest or the on-disk cache (that's stop()'s job, for
  /// logout only). A prior version of this method called the old stop() -
  /// which DID clear everything - unconditionally on every start(), meaning
  /// even an app resume (see restartIfActive() below) silently threw away
  /// and re-paid for the whole in-memory state. Fixed as part of this same
  /// rewrite, since it would have quietly defeated the entire point of the
  /// new local cache otherwise.
  static void start(String uid) {
    _stopListenersOnly();
    if (uid.isEmpty || sectionConstantModel == null) return;
    _activeUid = uid;
    unawaited(_startAsync(uid));
  }

  static Future<void> _startAsync(String uid) async {
    // Seed from the on-device cache first - instant, zero network cost, and
    // gives the "newest known order" cutoff the live queries below need.
    final cached = await loadCachedSettledOrders(uid);
    if (_activeUid != uid) return; // a different uid started while this awaited
    for (final order in cached) {
      _ordersById[order.id] = order;
    }
    if (cached.isNotEmpty) _emit();

    _attachLiveQueries(uid);

    // Skip the reconciliation check entirely when there was no local cache
    // to seed from (a fresh install, or storage was cleared) - the "new
    // orders" query above already had no cutoff in that case, so it just
    // fetched the top kTopWatchWindow fresh from the server itself. Running
    // the reconciliation pass too would re-fetch that exact same window a
    // second time for nothing (confirmed while reasoning through the
    // cleared-storage case: this would otherwise cost up to 2x
    // kTopWatchWindow reads on a cleared-storage user's first reopen,
    // instead of kTopWatchWindow once).
    if (cached.isNotEmpty && await fullReconciliationDue(uid)) {
      unawaited(_runFullReconciliation(uid));
    }
  }

  static void _attachLiveQueries(String uid) {
    final sectionId = sectionConstantModel!.id;
    final base = FireStoreUtils.firestore
        .collection(ORDERS)
        .where('authorID', isEqualTo: uid)
        .where('section_id', isEqualTo: sectionId);

    // Fixed at attach time, not recomputed per-event - any order created
    // later in this same session still satisfies createdAt > cutoff for the
    // life of this listener, so it never needs to be torn down and
    // recreated mid-session just because a new order arrived.
    Timestamp? cutoff;
    for (final order in _ordersById.values) {
      if (cutoff == null || order.createdAt.compareTo(cutoff) > 0) {
        cutoff = order.createdAt;
      }
    }

    // "What's new" - attaches genuinely empty (zero read cost) whenever
    // nothing has actually happened since the last known order, which is
    // the common case on a routine reopen.
    final newQuery = (cutoff != null
            ? base.where('createdAt', isGreaterThan: cutoff)
            : base)
        .orderBy('createdAt', descending: true)
        .limit(kTopWatchWindow);
    _newSub = newQuery.snapshotsLogged('SharedOrdersWatcher:new').listen((snap) {
      for (final doc in snap.docs) {
        try {
          _ordersById[doc.id] = OrderModel.fromJson(doc.data());
        } catch (e) {
          debugPrint('[SharedOrdersWatcher] new-order parse error ${doc.id} $e');
        }
      }
      _emit();
      _promoteSettledOrders(uid);
    }, onError: (Object e) {
      debugPrint('[SharedOrdersWatcher] new-order stream error: $e');
      _emit();
    });

    // Explicit re-check of every currently-known order not yet proven safe
    // to stop watching - typically 0-3 documents for a normal customer.
    // Queried by document id directly (no authorID/section_id filter
    // needed - these ids only ever came from this same account's own
    // cache/live results in the first place, and Firestore rules already
    // gate read access on authorID regardless of query shape).
    final activeIds = _ordersById.values
        .where((o) => !isOrderSafeToCachePermanently(o))
        .map((o) => o.id)
        .toList();
    for (final chunk in _chunk(activeIds, 30)) {
      final sub = FireStoreUtils.firestore
          .collection(ORDERS)
          .where(FieldPath.documentId, whereIn: chunk)
          .snapshotsLogged('SharedOrdersWatcher:active')
          .listen((snap) {
        for (final doc in snap.docs) {
          try {
            _ordersById[doc.id] = OrderModel.fromJson(doc.data());
          } catch (e) {
            debugPrint('[SharedOrdersWatcher] active-order parse error ${doc.id} $e');
          }
        }
        _emit();
        _promoteSettledOrders(uid);
      }, onError: (Object e) {
        debugPrint('[SharedOrdersWatcher] active-order stream error: $e');
        _emit();
      });
      _activeSubs.add(sub);
    }
  }

  static Iterable<List<String>> _chunk(List<String> ids, int size) sync* {
    for (var i = 0; i < ids.length; i += size) {
      yield ids.sublist(i, i + size > ids.length ? ids.length : i + size);
    }
  }

  /// Deliberately infrequent (kFullReconciliationInterval, currently 7 days)
  /// blanket re-read of the most recent kTopWatchWindow orders regardless of
  /// what's already cached - a defensive backstop for something the two
  /// targeted queries above wouldn't be watching for (an admin-side
  /// correction to an order already believed settled), not the primary sync
  /// path. One-time server read, not a listener.
  static Future<void> _runFullReconciliation(String uid) async {
    try {
      final sectionId = sectionConstantModel!.id;
      final snap = await FireStoreUtils.firestore
          .collection(ORDERS)
          .where('authorID', isEqualTo: uid)
          .where('section_id', isEqualTo: sectionId)
          .orderBy('createdAt', descending: true)
          .limit(kTopWatchWindow)
          .getLogged('SharedOrdersWatcher:reconciliation', const GetOptions(source: Source.server));
      if (_activeUid != uid) return; // account switched while this awaited
      for (final doc in snap.docs) {
        try {
          _ordersById[doc.id] = OrderModel.fromJson(doc.data());
        } catch (e) {
          debugPrint('[SharedOrdersWatcher] reconciliation parse error ${doc.id} $e');
        }
      }
      _emit();
      _promoteSettledOrders(uid);
      await markFullReconciliationDone(uid);
    } catch (e) {
      debugPrint('[SharedOrdersWatcher] full reconciliation failed: $e');
    }
  }

  /// Restarts the watcher only if one was already active for a real uid -
  /// called on every app resume, unconditionally-safe the same way
  /// PurchaseCompletionListener's resume restart is (start() is idempotent).
  /// Deliberately does nothing for a customer who has never opened Orders
  /// this session, so resuming the app never costs a read nobody asked for.
  /// Cheap even when it does run now, thanks to the start()/stop() split
  /// above - a resume no longer discards the in-memory state first.
  static void restartIfActive() {
    final uid = _activeUid;
    if (uid != null) start(uid);
  }

  static void _stopListenersOnly() {
    _newSub?.cancel();
    _newSub = null;
    for (final sub in _activeSubs) {
      sub.cancel();
    }
    _activeSubs.clear();
  }

  /// Full stop - call on logout so a different account on the same device
  /// never sees a previous customer's cached order list, in memory or on
  /// disk.
  static void stop() {
    final uid = _activeUid;
    _stopListenersOnly();
    _cacheWriteDebounce?.cancel();
    _cacheWriteDebounce = null;
    _pendingPromotionIds.clear();
    _activeUid = null;
    _ordersById.clear();
    _latest = null;
    if (uid != null) unawaited(clearCachedOrders(uid));
  }
}
