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

  // 2026-09-26 (customer rule): finished orders come from the device cache;
  // live orders come from Firestore with NO count limit; when the cache is
  // empty (cleared data / reinstall / new phone) only the recent
  // kFirstHistoryPage finished orders are fetched, and "Show older orders"
  // pages kOlderPage more at a time. Also the weekly check's size.
  static const int kFirstHistoryPage = 5;
  static const int kOlderPage = 10;

  /// Whether "Show older orders" can still find anything, and whether a page
  /// is loading - read by OrdersScreen's list footer.
  static final ValueNotifier<bool> hasOlder = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> loadingOlder = ValueNotifier<bool>(false);

  // "Show older" pages from _olderCursor downwards. While a gap between the
  // newest cached order and the start-up fetch is still being filled,
  // _olderFloor stops the page at the newest cached order.
  static Timestamp? _olderCursor;
  static Timestamp? _olderFloor;
  // The start-up history fetch runs once per uid per app process, not on
  // every resume (restartIfActive) - resumes are covered by the listeners.
  static String? _historyFilledFor;

  // 2026-09-26: raw documents of the orders this watcher is ALREADY
  // listening to live, shared with SharedOrderDetailWatcher. Without this,
  // Order Details opened its own document listener on an order the live
  // query was already watching - two server targets on one order, so every
  // status change was billed twice while the details screen was open.
  static final Map<String, DocumentSnapshot<Map<String, dynamic>>> _rawById = {};
  static final Map<String, StreamController<DocumentSnapshot<Map<String, dynamic>>>> _docStreams = {};
  static Set<String> _liveQueryIds = {};
  static Set<String> _activeByIdIds = {};

  /// True when [orderId] is currently delivered by this watcher's live
  /// listeners (the live query, or the by-id listener for older live orders).
  static bool isWatchingLive(String orderId) =>
      (_newSub != null && _liveQueryIds.contains(orderId)) ||
      (_activeSubs.isNotEmpty && _activeByIdIds.contains(orderId));

  /// True when [orderId] is known here and finished (it can't change any more).
  static bool isKnownFinished(String orderId) {
    final order = _ordersById[orderId];
    return order != null && isOrderSafeToCachePermanently(order);
  }

  /// Latest raw document for [orderId] from the live listeners, then every
  /// update (including its final state when it finishes - see
  /// _captureFinished). Costs no extra reads.
  static Stream<DocumentSnapshot<Map<String, dynamic>>> liveDocStream(String orderId) async* {
    final controller = _docStreams.putIfAbsent(
        orderId, () => StreamController<DocumentSnapshot<Map<String, dynamic>>>.broadcast());
    final latest = _rawById[orderId];
    if (latest != null) yield latest;
    yield* controller.stream;
  }

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

    if (_historyFilledFor != uid) {
      _historyFilledFor = uid;
      await _fillRecentHistory(uid, cached);
    }

    // Skip the reconciliation check when there was no local cache to seed
    // from (fresh install / cleared storage) - _fillRecentHistory just
    // fetched the recent orders from the server, re-checking them again
    // would pay for the same documents twice.
    if (cached.isNotEmpty && await fullReconciliationDue(uid)) {
      unawaited(_runFullReconciliation(uid));
    }
  }

  static CollectionReference<Map<String, dynamic>> get _orders =>
      FireStoreUtils.firestore.collection(ORDERS);

  static Query<Map<String, dynamic>> _mine(String uid) => _orders
      .where('authorID', isEqualTo: uid)
      .where('section_id', isEqualTo: sectionConstantModel!.id);

  static void _mergeDocs(Iterable<DocumentSnapshot<Map<String, dynamic>>> docs, String label) {
    for (final doc in docs) {
      final data = doc.data();
      if (data == null) continue;
      try {
        _ordersById[doc.id] = OrderModel.fromJson(data);
      } catch (e) {
        debugPrint('[SharedOrdersWatcher] $label parse error ${doc.id} $e');
      }
      _rawById[doc.id] = doc;
      final c = _docStreams[doc.id];
      if (c != null && !c.isClosed) c.add(doc);
    }
  }

  static Timestamp? _oldestKnown() {
    Timestamp? oldest;
    for (final o in _ordersById.values) {
      if (oldest == null || o.createdAt.compareTo(oldest) < 0) oldest = o.createdAt;
    }
    return oldest;
  }

  /// Start-up history fetch (once per uid per process): the newest
  /// kFirstHistoryPage orders created after the newest cached one (or the
  /// newest kFirstHistoryPage overall when the cache is empty). Catches
  /// orders that finished while the Orders screen wasn't being watched -
  /// they are cached straight away, so the next visit costs 1 read (an
  /// empty query) and no data. Any status, so an order in a status missing
  /// from kLiveOrderStatuses can only be late, never lost.
  static Future<void> _fillRecentHistory(String uid, List<OrderModel> cached) async {
    Timestamp? newestCached;
    for (final o in cached) {
      if (newestCached == null || o.createdAt.compareTo(newestCached) > 0) newestCached = o.createdAt;
    }
    try {
      var q = _mine(uid);
      // Exclusive: an inclusive bound would re-download the newest cached
      // order on every start. createdAt is millisecond-precise, so one
      // customer never has two orders on the same instant.
      if (newestCached != null) q = q.where('createdAt', isGreaterThan: newestCached);
      final snap = await q
          .orderBy('createdAt', descending: true)
          .limit(kFirstHistoryPage)
          .getLogged('SharedOrdersWatcher:recent');
      if (_activeUid != uid) return;
      _mergeDocs(snap.docs, 'recent');
      final gapMayContinue = newestCached != null && snap.docs.length == kFirstHistoryPage;
      if (gapMayContinue) {
        _olderCursor = snap.docs.last.data()['createdAt'] as Timestamp?;
        _olderFloor = newestCached;
      } else {
        _olderCursor = _oldestKnown();
        _olderFloor = null;
      }
      // Empty cache and fewer than a page back = this is everything.
      hasOlder.value = !(cached.isEmpty && snap.docs.length < kFirstHistoryPage) && _olderCursor != null;
      _emit();
      _promoteSettledOrders(uid);
      _watchActiveOutsideWindow(uid);
    } catch (e) {
      debugPrint('[SharedOrdersWatcher] recent history fetch failed: $e');
      _olderCursor = _oldestKnown();
      hasOlder.value = _olderCursor != null;
      _emit();
    }
  }

  /// "Show older orders": the next kOlderPage finished orders below what's
  /// on screen. Pages that load are cached like any other finished order
  /// (the device cache keeps the newest kMaxCachedSettledOrders).
  static Future<void> loadOlder() async {
    final uid = _activeUid;
    final cursor = _olderCursor;
    if (uid == null || cursor == null || loadingOlder.value || sectionConstantModel == null) return;
    loadingOlder.value = true;
    try {
      var q = _mine(uid);
      final floor = _olderFloor;
      if (floor != null) q = q.where('createdAt', isGreaterThan: floor);
      // startAfter (not createdAt < cursor) so orders sharing the cursor's
      // exact timestamp are never skipped - verified on production data.
      final snap = await q
          .orderBy('createdAt', descending: true)
          .startAfter([cursor])
          .limit(kOlderPage)
          .getLogged('SharedOrdersWatcher:older');
      if (_activeUid != uid) return;
      _mergeDocs(snap.docs, 'older');
      if (snap.docs.length == kOlderPage) {
        _olderCursor = snap.docs.last.data()['createdAt'] as Timestamp?;
      } else if (floor != null) {
        // Gap filled - carry on below the cached orders next time.
        _olderFloor = null;
        _olderCursor = _oldestKnown();
      } else {
        hasOlder.value = false;
      }
      _emit();
      _promoteSettledOrders(uid);
    } catch (e) {
      debugPrint('[SharedOrdersWatcher] load older failed: $e');
    } finally {
      loadingOlder.value = false;
    }
  }

  /// A live order just left the live listener (it finished): read its final
  /// state once and cache it, so every later visit serves it from the device.
  static Future<void> _captureFinished(String uid, String orderId) async {
    try {
      final doc = await _orders.doc(orderId).getLogged('SharedOrdersWatcher:finished');
      if (_activeUid != uid || !doc.exists) return;
      _mergeDocs([doc], 'finished');
      _emit();
      _promoteSettledOrders(uid);
    } catch (e) {
      debugPrint('[SharedOrdersWatcher] finished-order fetch failed $orderId: $e');
    }
  }

  static void _attachLiveQueries(String uid) {
    // 2026-09-26: live = still in progress (kLiveOrderStatuses) and created
    // within kLiveOrderWindow - NO count limit, every live order shows.
    // Finished orders are not in this query at all: they come from the
    // device cache. When a live order finishes it drops out of the query
    // (a "removed" change) and _captureFinished caches its final state.
    // Replaces the old "newer than the newest cached, limit 25" query.
    final liveSince = Timestamp.fromDate(DateTime.now().subtract(kLiveOrderWindow));
    _liveSince = liveSince;
    // Orders this process already knew as live (only after a resume) - any
    // that finished while the app was in the background won't show up as a
    // "removed" change on this brand-new listener, so the first snapshot
    // checks for them explicitly.
    final knownLive = _ordersById.values
        .where((o) => !isOrderSafeToCachePermanently(o) && o.createdAt.compareTo(liveSince) > 0)
        .map((o) => o.id)
        .toSet();
    var firstSnapshot = true;
    final liveQuery = _mine(uid)
        .where('status', whereIn: kLiveOrderStatuses)
        .where('createdAt', isGreaterThan: liveSince)
        .orderBy('createdAt', descending: true);
    _newSub = liveQuery.snapshotsLogged('SharedOrdersWatcher:live').listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.removed) {
          unawaited(_captureFinished(uid, change.doc.id));
        }
      }
      if (firstSnapshot) {
        firstSnapshot = false;
        final stillLive = snap.docs.map((d) => d.id).toSet();
        for (final id in knownLive.difference(stillLive)) {
          unawaited(_captureFinished(uid, id));
        }
      }
      _liveQueryIds = snap.docs.map((d) => d.id).toSet();
      _mergeDocs(snap.docs, 'live');
      _emit();
      _promoteSettledOrders(uid);
    }, onError: (Object e) {
      debugPrint('[SharedOrdersWatcher] live-order stream error: $e');
      _emit();
    });

    _watchActiveOutsideWindow(uid);
  }

  static Timestamp? _liveSince;

  /// Known orders that aren't finished but were created before the live
  /// window (e.g. an order scheduled days ahead) - watched by id so they
  /// still update live. Usually none. Orders inside the window are already
  /// covered by the live query, so nothing is watched twice.
  static void _watchActiveOutsideWindow(String uid) {
    for (final sub in _activeSubs) {
      sub.cancel();
    }
    _activeSubs.clear();
    final since = _liveSince;
    final activeIds = _ordersById.values
        .where((o) => !isOrderSafeToCachePermanently(o) && (since == null || o.createdAt.compareTo(since) <= 0))
        .map((o) => o.id)
        .toList();
    _activeByIdIds = activeIds.toSet();
    for (final chunk in _chunk(activeIds, 30)) {
      final sub = _orders
          .where(FieldPath.documentId, whereIn: chunk)
          .snapshotsLogged('SharedOrdersWatcher:active')
          .listen((snap) {
        _mergeDocs(snap.docs, 'active-order');
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
          .limit(kFirstHistoryPage)
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
    _historyFilledFor = null;
    _rawById.clear();
    for (final c in _docStreams.values) {
      c.close();
    }
    _docStreams.clear();
    _liveQueryIds = {};
    _activeByIdIds = {};
    _olderCursor = null;
    _olderFloor = null;
    hasOlder.value = false;
    loadingOlder.value = false;
    if (uid != null) unawaited(clearCachedOrders(uid));
  }
}
