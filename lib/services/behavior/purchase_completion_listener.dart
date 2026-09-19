import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/OrderModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/behavior/behavior_event_types.dart';
import 'package:emartconsumer/services/behavior/behavior_tracker.dart';
import 'package:emartconsumer/services/firestore_instrumentation.dart';
import 'package:emartconsumer/services/shared_orders_watcher.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────
// Purchase-preference completion listener (2026-07-22) - COLLECTION ONLY,
// same posture as BehaviorTracker itself.
//
// WHY THIS EXISTS: a placed order is a purchase ATTEMPT, not a successful
// purchase - payment can still fail to settle, the vendor can reject it,
// the customer can cancel, a duplicate payment retry can occur. None of
// that should shape a customer's long-term preference profile. This class
// fires purchase-derived preference signals (category/cuisine/restaurant
// preference, budget profile, order-mode preference, product preference)
// only once an order genuinely reaches ORDER_STATUS_COMPLETED - the same
// single, universal status transition that already drives vendorApp/
// vendorWeb's dailyProductSales/monthlyProductSales/productPairings,
// confirmed to cover every order type (delivery/takeaway/dine-in/bill pay)
// through one common path on the vendor side.
//
// WHY A CLIENT-SIDE LISTENER, NOT A VENDOR-SIDE OR SERVER-SIDE HOOK:
// customer preference data (users/{uid}/behavior_summary) is owner-scoped
// by Firestore rule (`request.auth.uid == uid`) - a vendor's own session
// can never legally write into it, and adding a Cloud Function to bridge
// that gap was explicitly ruled out earlier in this project ("no server,
// fully client-side"). So instead, the CUSTOMER's own app watches the
// CUSTOMER's own orders (already readable via `isOwner('authorID')`) and
// fires the preference update from the customer's own authenticated
// session the moment it observes one of them complete - zero Cloud
// Functions, zero rule changes, zero vendor involvement.
//
// WHY NOT ATTACHED TO A UI SCREEN: preference learning must not depend on
// whether the customer happens to have a particular screen open. This is
// a global, app-session-scoped service, started once after login and
// stopped on logout - the analytics equivalent of an auth or notification
// listener, not a screen-owned subscription.
//
// EXACTLY-ONCE PROCESSING (2026-07-22, revised): the order document is
// NEVER written back to - it stays fully immutable from the customer's
// side after creation. Instead, the durable, authoritative guard is a
// deterministic-ID MARKER DOCUMENT the listener creates at
// users/{uid}/behavior_batches/orderCompletionMarker_{orderId}, reusing
// the *existing* behavior_batches security rule as-is:
//   allow create: if request.auth.uid == uid;
//   allow update, delete: if isAdminPanel();
// Firestore evaluates a `.set()` against `create` only when the target
// doc does not yet exist; once it exists, the SAME call is evaluated
// against `update`, which the owner has no permission for. So the first
// attempt to create a given order's marker succeeds - and every
// subsequent attempt (replay, reconnect, listener restart, new device)
// is rejected server-side with `permission-denied`. That rejection IS
// the dedup signal - no flag to read-then-trust, no transaction, no new
// collection or rule. It survives reinstall/new device because it lives
// in Firestore under the customer's own uid, not on the device.
// _processingOrderIds below is a same-session, in-memory-only guard so
// two near-simultaneous snapshot events for the same order don't both
// race to attempt the create; it is not the source of truth.
//
// This costs one extra write ATTEMPT per completed order (vs. the prior
// design's zero-additional-reads goal) - accepted because it's bounded
// by order volume, not browsing volume, and buys atomic correctness
// without touching security rules or the order document.
//
// DEFERRED THIS PHASE - Combo Purchase Learning (kEvtComboOrdered:
// comboOrderCount/comboPriceTotal/comboChildProductCounts): the previous
// (checkout-time) implementation needed each line item's full ProductModel
// (isCombo, comboProducts) via an extra read per item, which this class
// deliberately does not perform (zero-additional-reads requirement). No
// combo signal is learned from purchases until a follow-up extends
// analyticsSnapshot itself with lightweight combo metadata (e.g.
// isCombo/comboProductIds per line item, captured once at order creation,
// same pattern as everything else in the snapshot) so this listener can
// keep firing kEvtComboOrdered with zero new reads once that lands.
// ─────────────────────────────────────────────────────────────────────────
class PurchaseCompletionListener {
  PurchaseCompletionListener._();

  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  /// Passive subscription to SharedOrdersWatcher - the zero-read primary path
  /// (see _fullSweepInterval's comment). Separate from [_sub] because the two
  /// have different lifetimes: this one lives for the whole session, while
  /// [_sub] only exists on the rare launch that runs the backstop sweep.
  static StreamSubscription<List<OrderModel>>? _passiveSub;

  // In-memory-only guard against two near-simultaneous snapshot events for
  // the same order both racing to attempt the marker-doc create within one
  // running session - NOT the source of truth (that's the marker doc's
  // existence in Firestore, see _processIfNeeded), just a narrow
  // race-closer that avoids a redundant create attempt.
  static final Set<String> _processingOrderIds = {};

  // Local, this-device cache of order IDs already confirmed handled (marker
  // created OR marker already existed) - persisted so a listener restart
  // (app relaunch, token refresh, resume-cycle restart) doesn't re-attempt a
  // network write for every completed order in the account's full history
  // every single time. Firestore's permission-denied-on-existing-marker
  // check (see _processIfNeeded) remains the actual source of truth and
  // still runs for anything not in this cache - this is purely a
  // this-session/this-device shortcut, safe to lose (e.g. reinstall):
  // worst case is falling back to the same one-write-attempt-per-order
  // behavior this class always had.
  static const String _processedOrdersPrefsKey =
      'purchase_completion_processed_order_ids';
  // Caps unbounded growth on accounts with very large order histories.
  static const int _processedOrdersCacheLimit = 1000;
  static Set<String>? _knownProcessedOrderIds;

  static Future<Set<String>> _loadKnownProcessedOrderIds() async {
    if (_knownProcessedOrderIds != null) return _knownProcessedOrderIds!;
    try {
      final sp = await SharedPreferences.getInstance();
      _knownProcessedOrderIds =
          (sp.getStringList(_processedOrdersPrefsKey) ?? const []).toSet();
    } catch (_) {
      _knownProcessedOrderIds = {};
    }
    return _knownProcessedOrderIds!;
  }

  static Future<void> _markOrderProcessedLocally(String orderId) async {
    try {
      final known = await _loadKnownProcessedOrderIds();
      known.add(orderId);
      var list = known.toList();
      if (list.length > _processedOrdersCacheLimit) {
        list = list.sublist(list.length - _processedOrdersCacheLimit);
        _knownProcessedOrderIds = list.toSet();
      }
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(_processedOrdersPrefsKey, list);
    } catch (_) {
      // Best-effort only - Firestore's own check is still the source of
      // truth, so losing this write just means one extra network round
      // trip next time, not a correctness issue.
    }
  }

  // 2026-09-15: catch-up window for the query below. Bounding by createdAt
  // (not a "completedAt" - confirmed live against production that
  // statusUpdatedAt is missing/null on 8 of 10 real completed orders, so an
  // inequality filter on it would silently exclude most orders entirely,
  // the same "missing field never matches" trap documented elsewhere in
  // this codebase). 60 days is generous enough that a genuinely delayed
  // completion (dispute resolution, a slow vendor) is still caught, while
  // bounding the every-cold-start cost that used to be this customer's
  // ENTIRE lifetime completed-order history - confirmed live: 218 documents
  // on a single test account, on every single login, invisible to
  // FirestoreReadStats because this call was never wrapped in
  // snapshotsLogged. A rolling window (recomputed fresh each start(), not a
  // persisted high-water-mark cursor) is deliberate: it can never
  // permanently miss a late completion the way an advancing cursor could if
  // an order's createdAt falls before the cursor but its status only
  // changes to Completed afterward - the tradeoff is re-fetching whatever's
  // still within the window on every cold start, rather than a strictly
  // shrinking set, which is an acceptable cost for a collection-only,
  // non-critical analytics signal (see this file's own header comment).
  static const Duration _catchUpWindow = Duration(days: 60);

  // 2026-09-15 (second pass): the 60-day bound above fixed the "entire
  // lifetime history" leak (218 -> 93 docs) but NOT the per-launch cost -
  // 93 documents were still re-read on EVERY cold start and every
  // app-resume restart. Proven live, twice, against the project's own
  // document/read_count metric: two controlled cold starts billed 199 and
  // 128 document reads, of which this one listener's 93 was the single
  // largest item (~74% of the second run's 126 billed QUERY reads). It was
  // invisible in the app's own logs because a listener's first emission is
  // served from the local cache (source=CACHE), while Firestore still bills
  // the full matching set for the server-side watch that backs it -
  // attaching a listener costs its whole result set, cached first emission
  // or not.
  //
  // So the window is now ADAPTIVE rather than always 60 days:
  //   - at most once per _fullSweepInterval, attach with the full 60-day
  //     window (the real catch-up sweep);
  //   - every other start() - which is most of them, since main.dart
  //     restarts this listener on every app resume - attaches with
  //     _recentWindow instead, which matches only the handful of genuinely
  //     recent orders.
  //
  // Why this keeps the rolling window's correctness (see the long comment
  // above): the 60-day sweep is THROTTLED, never replaced by an advancing
  // cursor. A late completion (order created weeks ago, status flipped to
  // Completed today) is still found by the next full sweep, because that
  // sweep re-queries the whole 60 days from scratch exactly as before. The
  // only behaviour change is LATENCY: such a late completion can now be
  // learned up to _fullSweepInterval later than it would have been, instead
  // of at the very next app launch. That is an explicitly acceptable
  // tradeoff for a collection-only, non-critical analytics signal (this
  // file's header) - and it is a delay, never a loss.
  // 2026-09-15 (third pass): the 2-day "recent" window is GONE entirely, and
  // with it the last per-cold-start cost of this class.
  //
  // The realisation that made it removable: every document that window was
  // reading is ALREADY read elsewhere, for free. SharedOrdersWatcher watches
  // this same customer's own orders whenever they open the Orders screen, and
  // ORDER_STATUS_COMPLETED is the first entry in kTerminalOrderStatuses - so
  // a completed order is guaranteed to pass through that watcher's stream.
  // Paying for a second, independent query on every launch to learn the same
  // fact was pure duplication.
  //
  // So this class now subscribes PASSIVELY to SharedOrdersWatcher
  // (see passiveStream's doc: it never starts the watcher, so a subscription
  // costs zero reads) and processes completions out of data the app was
  // already reading. Cold-start cost for this listener: 0 documents.
  //
  // Accepted tradeoff (explicit product decision, 2026-09-15): preference
  // analytics for a completed order now fires the next time the customer
  // opens their Orders screen, rather than on the next app launch. Nothing is
  // ever lost - the marker-document dedup is permanent and server-side, so a
  // deferred order is still processed exactly once whenever it is finally
  // seen - and the periodic sweep below remains as insurance for a customer
  // who rarely opens Orders at all.
  //
  // The sweep interval is correspondingly relaxed from 24h to 7 days: it is
  // now a backstop rather than the primary mechanism.
  static const Duration _fullSweepInterval = Duration(days: 7);
  static const String _lastFullSweepPrefsKey =
      'purchase_completion_last_full_sweep_ms';

  // Guards against an async start() finishing after a stop()/newer start()
  // already happened - without this, the awaited prefs read below opens a
  // window where a cancelled start could still attach a stray listener.
  static int _startGeneration = 0;

  /// Start watching this customer's own orders for completions. Safe to
  /// call multiple times (e.g. token refresh firing authStateChanges
  /// again) - always stops any previous subscription first, so exactly
  /// one listener is ever active, for exactly one uid, at a time.
  static void start(String uid) {
    stop();
    if (uid.isEmpty) return;
    final generation = ++_startGeneration;
    // ignore: unawaited_futures
    _startInternal(uid, generation);
  }

  /// Decides whether this attach is a full 60-day catch-up sweep or a cheap
  /// recent-only attach, then opens the listener. Returns without attaching
  /// if a stop()/newer start() landed while the prefs read was in flight.
  static Future<bool> _shouldRunFullSweep() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final lastMs = sp.getInt(_lastFullSweepPrefsKey);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (lastMs != null &&
          now - lastMs < _fullSweepInterval.inMilliseconds &&
          // Guard against a device clock moved backwards leaving a
          // far-future timestamp that would suppress sweeps indefinitely.
          now >= lastMs) {
        return false;
      }
      await sp.setInt(_lastFullSweepPrefsKey, now);
      return true;
    } catch (_) {
      // Prefs unavailable - fall back to the old always-full-sweep
      // behaviour rather than silently narrowing the safety net.
      return true;
    }
  }

  static Future<void> _startInternal(String uid, int generation) async {
    try {
      // ZERO-COST primary path: listen to orders the app is already reading
      // for the Orders screen. Never starts that watcher itself.
      _passiveSub = SharedOrdersWatcher.passiveStream.listen((orders) {
        for (final order in orders) {
          if (order.status != ORDER_STATUS_COMPLETED) continue;
          // ignore: unawaited_futures
          _processOrderIfNeeded(order);
        }
      }, onError: (Object error) {
        debugPrint('[PurchaseCompletionListener] passive stream error: $error');
      });

      final fullSweep = await _shouldRunFullSweep();
      // A stop() or a newer start() happened while we were awaiting prefs.
      if (generation != _startGeneration) return;
      if (!fullSweep) {
        debugPrint('[PurchaseCompletionListener] passive mode only - no '
            'Firestore query this start (0 reads). Completions are picked up '
            'from SharedOrdersWatcher when the customer opens Orders.');
        return;
      }

      final cutoff = Timestamp.fromDate(DateTime.now().subtract(_catchUpWindow));
      debugPrint('[PurchaseCompletionListener] running FULL '
          '${_catchUpWindow.inDays}-day backstop sweep '
          '(cutoff=${cutoff.toDate().toIso8601String()})');
      _sub = FireStoreUtils.firestore
          .collection(ORDERS)
          .where('authorID', isEqualTo: uid)
          .where('status', isEqualTo: ORDER_STATUS_COMPLETED)
          .where('createdAt', isGreaterThanOrEqualTo: cutoff)
          .snapshotsLogged('PurchaseCompletionListener:vendor_orders (7-day backstop sweep)')
          .listen((snapshot) {
        // DocumentChangeType.added fires exactly when a document ENTERS
        // this query's result set - i.e. the moment an order's status
        // becomes ORDER_STATUS_COMPLETED (or the moment this listener
        // first attaches and finds already-completed orders it hasn't
        // seen yet, e.g. after a fresh login). Modified/removed changes
        // to an already-completed order (rare - e.g. staff fields) are
        // deliberately ignored; only first-time entry matters here.
        for (final change in snapshot.docChanges) {
          if (change.type != DocumentChangeType.added) continue;
          // ignore: unawaited_futures
          _processIfNeeded(change.doc);
        }
      }, onError: (Object error) {
        // Collection only - a stream error must never surface anywhere in
        // the app. But it must not be totally silent either: this used to
        // be an empty callback, which is indistinguishable from "nothing
        // ever went wrong" - debugPrint is this codebase's existing
        // convention for "make a collection-only failure visible" (no
        // Crashlytics/Sentry exists here). The next authStateChanges/
        // app-resume cycle (see main.dart's AppLifecycleState.resumed
        // branch) actually restarts this listener now.
        debugPrint('[PurchaseCompletionListener] stream error: $error');
      });
    } catch (_) {
      // Never let listener setup itself throw into the caller.
    }
  }

  /// Stop watching - call on logout. Also clears the in-memory guard set,
  /// since it's meaningless once no uid is being watched.
  static void stop() {
    // Invalidates any _startInternal still awaiting its prefs read, so it
    // cannot attach a stray listener after this stop().
    _startGeneration++;
    _sub?.cancel();
    _sub = null;
    _passiveSub?.cancel();
    _passiveSub = null;
    _processingOrderIds.clear();
  }

  /// Sweep path: adapts a raw Firestore document to the shared implementation.
  static Future<void> _processIfNeeded(
      DocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    if (data == null) return;
    try {
      return await _processOrderIfNeeded(OrderModel.fromJson(data));
    } catch (_) {
      // Malformed document - same posture as before, never disrupt the app.
    }
  }

  /// Shared implementation for BOTH paths (passive SharedOrdersWatcher stream
  /// and the periodic backstop sweep).
  ///
  /// Keying on [OrderModel.id] rather than a DocumentSnapshot id is safe and
  /// deliberate: verified against live production data 2026-09-15 that
  /// vendor_orders documents always carry an `id` field identical to their own
  /// document id. That equality is what lets the passive path - which only
  /// ever sees OrderModels, never DocumentSnapshots - produce exactly the same
  /// marker-document id as before, so the existing exactly-once dedup keeps
  /// working unchanged and no already-processed order can re-fire.
  static Future<void> _processOrderIfNeeded(OrderModel order) async {
    try {
      final orderId = order.id;
      if (orderId.isEmpty) return;
      if (order.status != ORDER_STATUS_COMPLETED) return;
      final snapshot = order.analyticsSnapshot;
      // Orders created before this migration have no snapshot at all -
      // nothing to safely learn from (no guarantee the fields this class
      // depends on ever existed), so they're skipped, not guessed at.
      if (snapshot == null) return;
      if ((await _loadKnownProcessedOrderIds()).contains(orderId)) return;
      if (!_processingOrderIds.add(orderId)) return;

      try {
        final uid = FireStoreUtils.getCurrentUid();
        if (uid.isEmpty) return;

        // STEP 1 - build everything BEFORE claiming the marker. Building
        // is pure/local (OrderModel.fromJson + plain map/list derivation,
        // no I/O) and can throw on malformed data. If it throws here,
        // nothing has been claimed yet, so a future listener restart (app
        // relaunch, the resumed-cycle restart in main.dart, or a token
        // refresh) will see this order as "added" again and can retry
        // cleanly. Previously the marker was created FIRST and the order
        // was only parsed/fired afterwards - any throw in that window
        // permanently lost the event, since the marker's mere existence
        // is the entire dedup check (confirmed in production: order
        // 674586857 has a committed marker but zero corresponding
        // order_completed/product_ordered events - this exact loss
        // window, caught in the wild).
        List<_AnalyticsCall> calls;
        try {
          calls = _buildAnalyticsCalls(order, snapshot);
        } catch (e) {
          debugPrint('[PurchaseCompletionListener] failed to build '
              'analytics for order $orderId, marker NOT claimed, will '
              'retry next time this order is seen: $e');
          return;
        }

        final markerRef = FireStoreUtils.firestore
            .collection('users')
            .doc(uid)
            .collection('behavior_batches')
            .doc('orderCompletionMarker_$orderId');

        try {
          await markerRef.set({
            'userId': uid,
            'type': 'orderCompletionMarker',
            'orderId': orderId,
            'processedAt': FieldValue.serverTimestamp(),
          });
        } on FirebaseException catch (e) {
          if (e.code == 'permission-denied') {
            // Marker already exists (this order was already processed,
            // e.g. an earlier session, a prior listener restart, or a
            // near-simultaneous snapshot event) - expected, not an error.
            // ignore: unawaited_futures
            _markOrderProcessedLocally(orderId);
            return;
          }
          rethrow;
        }

        // ignore: unawaited_futures
        _markOrderProcessedLocally(orderId);

        // STEP 2 - marker create just won; this call is the exclusive,
        // exactly-once owner of firing this order's analytics. track()
        // cannot throw (its whole body is try{}catch(_){}) and the
        // payloads were already built and validated in STEP 1, so this
        // loop is not expected to ever fail.
        for (final call in calls) {
          BehaviorTracker.track(call.eventType, call.payload);
        }
      } finally {
        _processingOrderIds.remove(orderId);
      }
    } catch (_) {
      // Collection only - must never disrupt the app.
    }
  }

  /// Pure data-shaping - identical content to the previous _fireAnalytics,
  /// but RETURNS the calls instead of firing them, so the marker-claiming
  /// code above can build (and validate) everything before committing to
  /// the exactly-once marker, not after.
  static List<_AnalyticsCall> _buildAnalyticsCalls(
      OrderModel orderModel, Map<String, dynamic> snapshot) {
    final searchQuery = (snapshot['reachedViaSearchQuery'] ?? '').toString();
    final categoryIds = ((snapshot['categoryIds'] as List?) ?? const [])
        .map((c) => c.toString())
        .where((c) => c.isNotEmpty)
        .toList();
    final cuisineIds = ((snapshot['cuisineIds'] as List?) ?? const [])
        .map((c) => c.toString())
        .where((c) => c.isNotEmpty)
        .toList();
    final vendorId =
        (snapshot['restaurantId'] as String?) ?? orderModel.vendorID;

    final calls = <_AnalyticsCall>[
      _AnalyticsCall(kEvtOrderCompleted, {
        'orderId': orderModel.id,
        'vendorId': vendorId,
        'amount': (snapshot['totalAmount'] as num?) ?? 0,
        'paymentMethod': (snapshot['paymentMethod'] ?? 'unknown').toString(),
        'couponCode': (snapshot['couponCode'] ?? '').toString(),
        'hasSpecialDiscount': snapshot['hasSpecialDiscount'] == true,
        'orderMode': (snapshot['orderMode'] ?? 'unknown').toString(),
        'categoryId': categoryIds.isNotEmpty ? categoryIds.first : '',
        'cuisineIds': cuisineIds,
        'categoryIds': categoryIds,
        'searchQuery': searchQuery,
        // Restaurant Engagement completion linkage (Phase 2, 2026-07-24,
        // collection-only) - an extra field on this SAME kEvtOrderCompleted
        // event, not a new event type. _computeSummaryUpdates' existing
        // kEvtOrderCompleted case (behavior_tracker.dart) never reads this
        // key, so this cannot change anything it feeds into
        // behavior_summary/RecommendationEngine; only
        // _addRestaurantEngagementWrites' own separate kEvtOrderCompleted
        // check (added the same day) reads it, to flip
        // restaurantEngagement/{sessionId}.orderCompleted true.
        'restaurantSessionId':
            (snapshot['restaurantSessionId'] ?? '').toString(),
        // Search-conversion funnel (collection-only, additive field) -
        // read by _computeSummaryUpdates' NEW kEvtOrderCompleted branch to
        // bump behavior_summary.searchConversion.ordered when this order
        // originated from a Search/Cuisine-attributed restaurant visit.
        // Does not change any existing field this event already feeds.
        'entrySource': (snapshot['entrySource'] ?? '').toString(),
      }),
    ];

    for (final item in orderModel.products) {
      calls.add(_AnalyticsCall(kEvtProductOrdered, {
        'productId': item.id.split('~').first,
        'vendorId': vendorId,
        'quantity': item.quantity,
        'orderId': orderModel.id,
        // categoryId (2026-07-24) - CartProduct already carries this
        // (copied from the catalog product at add-to-cart time), so this
        // is a zero-extra-read addition. Closes the gap where
        // productOrderQuantities was keyed by productId alone with no way
        // to join back to a category without a catalog lookup.
        'categoryId': item.category_id ?? '',
      }));
    }

    // Combo Purchase Learning (2026-07-24) - fires kEvtComboOrdered ONCE
    // PER COMBO LINE ITEM, never per child product inside it - the combo
    // itself already got its own kEvtProductOrdered above (it's a real
    // catalog product like any other), and its children never did and
    // never will get a fake kEvtProductOrdered/productOrderQuantities
    // bump - they were never actually, individually purchased as their own
    // line item, only implied by ordering the combo. comboLineItems comes
    // from analyticsSnapshot (populated at checkout from
    // BehaviorTracker.comboMetadataFor, itself populated at add-to-cart
    // time) - reading it here is zero extra Firestore reads, closing the
    // gap this class's own header comment flagged as deferred.
    final comboLineItems = (snapshot['comboLineItems'] as List?) ?? const [];
    for (final raw in comboLineItems) {
      if (raw is! Map) continue;
      final combo = raw.cast<String, dynamic>();
      calls.add(_AnalyticsCall(kEvtComboOrdered, {
        'productId': (combo['productId'] ?? '').toString(),
        'vendorId': vendorId,
        'quantity': (combo['quantity'] as num?) ?? 1,
        'price': (combo['price'] ?? '0').toString(),
        'comboProductIds': ((combo['comboProductIds'] as List?) ?? const [])
            .map((c) => c.toString())
            .toList(),
        'comboCategoryIds': ((combo['comboCategoryIds'] as List?) ?? const [])
            .map((c) => c.toString())
            .toList(),
        'orderId': orderModel.id,
      }));
    }
    return calls;
  }
}

class _AnalyticsCall {
  final String eventType;
  final Map<String, dynamic> payload;
  _AnalyticsCall(this.eventType, this.payload);
}
