import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/OrderModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/behavior/behavior_event_types.dart';
import 'package:emartconsumer/services/behavior/behavior_tracker.dart';
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

  /// Start watching this customer's own orders for completions. Safe to
  /// call multiple times (e.g. token refresh firing authStateChanges
  /// again) - always stops any previous subscription first, so exactly
  /// one listener is ever active, for exactly one uid, at a time.
  static void start(String uid) {
    stop();
    if (uid.isEmpty) return;
    try {
      _sub = FireStoreUtils.firestore
          .collection(ORDERS)
          .where('authorID', isEqualTo: uid)
          .where('status', isEqualTo: ORDER_STATUS_COMPLETED)
          .snapshots()
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
    _sub?.cancel();
    _sub = null;
    _processingOrderIds.clear();
  }

  static Future<void> _processIfNeeded(
      DocumentSnapshot<Map<String, dynamic>> doc) async {
    try {
      final data = doc.data();
      if (data == null) return;
      final snapshot = data['analyticsSnapshot'] as Map<String, dynamic>?;
      // Orders created before this migration have no snapshot at all -
      // nothing to safely learn from (no guarantee the fields this class
      // depends on ever existed), so they're skipped, not guessed at.
      if (snapshot == null) return;
      if ((await _loadKnownProcessedOrderIds()).contains(doc.id)) return;
      if (!_processingOrderIds.add(doc.id)) return;

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
          final orderModel = OrderModel.fromJson(data);
          calls = _buildAnalyticsCalls(orderModel, snapshot);
        } catch (e) {
          debugPrint('[PurchaseCompletionListener] failed to build '
              'analytics for order ${doc.id}, marker NOT claimed, will '
              'retry on next listener attach: $e');
          return;
        }

        final markerRef = FireStoreUtils.firestore
            .collection('users')
            .doc(uid)
            .collection('behavior_batches')
            .doc('orderCompletionMarker_${doc.id}');

        try {
          await markerRef.set({
            'userId': uid,
            'type': 'orderCompletionMarker',
            'orderId': doc.id,
            'processedAt': FieldValue.serverTimestamp(),
          });
        } on FirebaseException catch (e) {
          if (e.code == 'permission-denied') {
            // Marker already exists (this order was already processed,
            // e.g. an earlier session, a prior listener restart, or a
            // near-simultaneous snapshot event) - expected, not an error.
            // ignore: unawaited_futures
            _markOrderProcessedLocally(doc.id);
            return;
          }
          rethrow;
        }

        // ignore: unawaited_futures
        _markOrderProcessedLocally(doc.id);

        // STEP 2 - marker create just won; this call is the exclusive,
        // exactly-once owner of firing this order's analytics. track()
        // cannot throw (its whole body is try{}catch(_){}) and the
        // payloads were already built and validated in STEP 1, so this
        // loop is not expected to ever fail.
        for (final call in calls) {
          BehaviorTracker.track(call.eventType, call.payload);
        }
      } finally {
        _processingOrderIds.remove(doc.id);
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
