import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/behavior/behavior_event_types.dart';
import 'package:emartconsumer/services/behavior/behavior_queue_store.dart';
import 'package:emartconsumer/services/behavior/global_analytics_api.dart';
import 'package:emartconsumer/services/behavior/recent_restaurant_session_store.dart';
import 'package:emartconsumer/services/behavior/combo_metadata_store.dart';
import 'package:emartconsumer/services/firestore_instrumentation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// ─────────────────────────────────────────────────────────────────────────
// Customer behavior collection - COLLECTION ONLY.
//
// This system observes and records customer behavior (restaurant/product
// interactions, search, purchases, offers, stories, navigation, dwell
// interest) to build a data foundation for a FUTURE recommendation engine.
// It does not read this data back anywhere, does not personalize anything,
// and adds no UI. See the plan at the time this was built for the full
// rationale (local-first, batch-uploaded, never blocks UI, very low
// Firestore cost, no continuous timers).
//
// Usage from anywhere in the app:
//   BehaviorTracker.track(kEvtRestaurantOpened, {'vendorId': v.id, ...});
// track() is synchronous and fire-and-forget - never awaited, never throws
// to the caller, never blocks the UI thread on network I/O.
// ─────────────────────────────────────────────────────────────────────────
class BehaviorTracker {
  BehaviorTracker._();

  // 30-50 events per the design - 40 splits the difference.
  static const int _flushThreshold = 40;

  // Time-based flush floor (2026-07-25) - the threshold/background/
  // reconnect triggers above leave one real gap uncovered: a long,
  // continuous FOREGROUND session with low event velocity (slow browsing,
  // never hitting 40 events, never backgrounding) could otherwise sit
  // unflushed indefinitely - the data exists (queued in memory, mirrored to
  // SharedPreferences by BehaviorQueueStore for crash/kill recovery), but
  // never REACHES Firestore/the backend until something else triggers a
  // flush. This is a genuine ceiling, not a replacement for the other
  // triggers - whichever of the four (threshold/background/reconnect/this
  // timer) fires first wins, same "OR conditions" design as everywhere else
  // in this file. A no-op call when the queue is already empty (see
  // _flush()'s own early-return), so an idle app with nothing tracked costs
  // nothing extra.
  static const Duration _periodicFlushInterval = Duration(minutes: 10);
  static Timer? _periodicFlushTimer;

  // Category preference weighting (2026-07-22, revised same day) - an
  // order is a far stronger signal of real category interest than a view,
  // so it counts for more toward categoryInteractionCounts, not the same
  // +1. Single named, easily-retuned constant, same convention as every
  // other tuning value in this file. 3x chosen deliberately over something
  // more extreme: strong enough that purchase-backed categories clearly
  // outweigh idle browsing, not so strong that one order could swamp
  // dozens of real exploratory views in the same category.
  //
  // Deliberately a FLAT per-order-per-category boost, NOT scaled by
  // quantity or by how many distinct products in that category appear in
  // one order (see kEvtOrderCompleted's categoryIds - already deduplicated
  // at the source, in the order's own analyticsSnapshot, before this ever
  // runs - not via an in-flush dedup Set anymore) - the signal being
  // learned is "does this customer like Biryani", not "how many biryanis
  // did they buy". Scaling by quantity would let a single group/family
  // order (5 coffees for a table) or a multi-dish order in one category (3
  // different biryanis) overstate one person's actual preference relative
  // to a customer who quietly orders 1 of something they genuinely love
  // every time.
  static const int _categoryOrderWeight = 3;

  // Cart-add confidence weight (2026-07-27) - between a view (1x, "looked
  // at it") and an order (3x, "paid for it"), a cart-add is real intent
  // without full purchase confirmation yet (could still be abandoned - see
  // kEvtProductRemovedFromCart/kEvtProductQuantityChanged, tracked
  // separately and NOT netted against this signal; a customer who adds then
  // removes still meaningfully signalled interest in the category/cuisine
  // in the moment). Same flat-per-category/per-cuisine, not-quantity-scaled
  // treatment as _categoryOrderWeight, for the identical reason: this is a
  // preference signal ("likes Biryani"), not a consumption-volume one.
  static const int _categoryCartWeight = 2;

  static final List<Map<String, dynamic>> _queue = [];
  static bool _flushing = false;
  static bool _initialized = false;
  static final String _sessionId = const Uuid().v4();

  // Short-lived, in-memory only (never persisted) - the last few
  // (vendorId, query) pairs a customer reached via a search result this
  // session. Originally just vendorId (for the searchToOrderCount scalar);
  // now also carries the query text (already present in the
  // kEvtRestaurantSelectedFromSearch/CuisineSearch payload, see
  // SearchScreen.dart's _vendorCard) so Search Confidence (below) can
  // escalate the SPECIFIC query that led to a restaurant, not just detect
  // "some search happened". Capped and time-windowed so it can't grow
  // unbounded or wrongly attribute a later action to a search from hours/
  // days earlier.
  static final List<_RecentSearchHit> _recentSearchHits = [];
  static const int _recentSearchWindowMinutes = 15;
  static const int _recentSearchMaxEntries = 20;

  // ── Phase 2 (2026-07-24): Restaurant Engagement / Search Conversion /
  // Banner Analytics - COLLECTION ONLY. See behavior_event_types.dart's own
  // header comment for why none of this touches _computeSummaryUpdates.
  //
  // Entry-source attribution: every screen that can navigate a customer to
  // NewVendorProductsScreen/DineInRestaurantDetailsScreen calls
  // setNextEntrySource(...) immediately before push(context, ...) - the
  // destination screen's initState then calls startRestaurantSession(),
  // which consumes (reads + resets to 'Direct') this value. A single
  // pending slot, not a queue, is deliberate: exactly one navigation
  // happens between "set" and "consume" in every real flow (Flutter's
  // Navigator is synchronous push, and initState runs before the next
  // frame), so there is never a second setter call to race against a
  // still-unconsumed first one.
  static String _pendingEntrySource = 'Direct';

  static void setNextEntrySource(String source) {
    _pendingEntrySource = source;
  }

  static String _consumeNextEntrySource() {
    final s = _pendingEntrySource;
    _pendingEntrySource = 'Direct';
    return s;
  }

  // Search Conversion context - set by SearchScreen immediately before
  // pushing a search result, consumed the same way as entry source above.
  // Deliberately folded into the SAME restaurantEngagement doc
  // (kEvtRestaurantSessionEnded) rather than a second "search conversion"
  // collection - the fields Section 2 of the phase-2 spec asks for (menu
  // duration, product views, cart adds, order conversion) are IDENTICAL to
  // Section 1's, so a search-originated visit just carries two extra
  // non-empty fields (searchKeyword/searchType) on the one doc instead of
  // duplicating the whole row in a parallel collection.
  static String _pendingSearchKeyword = '';
  static String _pendingSearchType = '';

  static void setNextSearchContext(String query, String type) {
    _pendingSearchKeyword = query;
    _pendingSearchType = type;
  }

  static ({String keyword, String type}) _consumeNextSearchContext() {
    final ctx = (keyword: _pendingSearchKeyword, type: _pendingSearchType);
    _pendingSearchKeyword = '';
    _pendingSearchType = '';
    return ctx;
  }

  // One active-or-recent restaurant-engagement session per vendor visit -
  // same capped/time-windowed in-memory list shape as _recentSearchHits
  // above, so a session id started on the menu screen can still be found
  // by CheckoutScreen/PaymentScreen minutes later (cart -> checkout is a
  // multi-screen hop, unlike the single-tap search->restaurant case, hence
  // the longer window).
  static final List<_RecentRestaurantSession> _recentRestaurantSessions = [];
  static const int _recentRestaurantSessionWindowMinutes = 120;
  static const int _recentRestaurantSessionMaxEntries = 20;

  // Combo metadata cache (2026-07-24) - keyed by productId (not vendorId or
  // a time window, unlike the caches above) because a combo's own
  // composition doesn't change moment-to-moment the way "which restaurant
  // did I just search for" does; what matters is bounding total size, not
  // recency. See ComboMetadataStore's own doc comment for the full
  // rationale (zero-extra-read bridge from add-to-cart time to checkout/
  // order-completion time).
  static final Map<String, _ComboMetadata> _recentComboMetadata = {};
  static const int _recentComboMetadataMaxEntries = 30;

  // Last banner tap, used to attribute the NEXT placed order to a banner
  // click the same way recentSearchQueryFor attributes one to a search -
  // single slot (not vendor-keyed): a banner always leads to exactly one
  // destination per tap, so "was any banner clicked recently" is the whole
  // question, no vendor-matching needed.
  static String? _lastBannerClickId;
  static DateTime? _lastBannerClickAt;
  static const int _recentBannerClickWindowMinutes = 60;

  // Local (never-read-from-Firestore) running totals for the derived
  // summary scalars (avgOrderValue, preferredPaymentMethod,
  // preferredOrderMode) - updated live as order_completed events are
  // tracked (2026-07-22: fired by PurchaseCompletionListener now, not at
  // checkout), reset on a real calendar-month change. Keeping this local
  // (rather than deriving it from a Firestore read) is what keeps the
  // flush a pure write with zero read cost.
  static const String _monthlyTotalsPrefsKey = 'behavior_monthly_totals_v1';
  static const String _lastPrunedMonthPrefsKey = 'behavior_last_pruned_month_v1';

  // Restaurant-switching / category+cuisine-transition detection
  // (2026-07-21, collection-only). Deliberately LIFETIME, not monthly-reset
  // like _monthlyTotalsPrefsKey above - detecting "did this order switch
  // vendor from the last one" needs the TRUE last order regardless of
  // month boundary, or the first order of every new month would wrongly
  // look like a fresh start. The resulting COUNTS still land in the
  // current month's behavior_summary doc (via _monthlyTotalsPrefsKey,
  // below), consistent with every other field there - only this raw
  // "what was last ordered" comparison state is lifetime.
  static const String _lastOrderContextPrefsKey = 'behavior_last_order_context_v1';

  // Sequential ordering pattern / restaurant co-occurrence (2026-07-21,
  // collection-only) - both are capped LOCAL lists (never an unbounded
  // event log), snapshot-written to their own dedicated docs at flush time.
  // Lifetime, not monthly-reset, same reasoning as _lastOrderContextPrefsKey.
  static const String _orderSequencePrefsKey = 'behavior_order_sequence_v1';
  static const int _orderSequenceMaxEntries = 15;
  static const String _vendorHistoryPrefsKey = 'behavior_vendor_history_v1';
  static const int _vendorHistoryMaxEntries = 20;

  // Kill switch for the restaurant-pairing analytics collection - off by
  // default, no Firestore write traffic from this feature until it's
  // switched on, same reversibility convention as vendorApp/vendorWeb's
  // _productPairingTrackingEnabled. This one is the single dataset in the
  // whole audit that isn't fully free (needs the local vendor-history
  // read below), so it stays opt-in even though it's cheap in absolute terms.
  static const bool _restaurantPairingTrackingEnabled = false;

  // ── Public API ───────────────────────────────────────────────────────

  /// Hydrates the in-memory queue from local storage (crash/kill recovery).
  /// Call once at app startup, e.g. from main.dart's init sequence.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final persisted = await BehaviorQueueStore.load();
      _queue.addAll(persisted);
    } catch (_) {
      // Never let a corrupt local queue block app startup.
    }

    // Hydrate recent-restaurant-session cache (2026-07-24 durability fix) -
    // previously in-memory-only, so it went empty on every app restart,
    // silently blanking analyticsSnapshot.restaurantSessionId on orders
    // placed shortly after a fresh app launch even when a real menu visit
    // happened minutes earlier. Prune anything already past the existing
    // 120-minute window on load, same recency semantics as before, just
    // durable across process restarts now.
    try {
      final persistedSessions = await RecentRestaurantSessionStore.load();
      final cutoff = DateTime.now().subtract(
          const Duration(minutes: _recentRestaurantSessionWindowMinutes));
      _recentRestaurantSessions.addAll(persistedSessions
          .map(_RecentRestaurantSession.fromJson)
          .where((s) => s.at.isAfter(cutoff)));
      if (_recentRestaurantSessions.length > _recentRestaurantSessionMaxEntries) {
        _recentRestaurantSessions.removeRange(
            0, _recentRestaurantSessions.length - _recentRestaurantSessionMaxEntries);
      }
    } catch (_) {
      // Never let a corrupt local cache block app startup.
    }

    // Hydrate combo-metadata cache (2026-07-24) - see ComboMetadataStore's
    // own doc comment.
    try {
      final persistedCombo = await ComboMetadataStore.load();
      persistedCombo.forEach((productId, value) {
        if (value is Map<String, dynamic>) {
          _recentComboMetadata[productId] = _ComboMetadata.fromJson(value);
        }
      });
    } catch (_) {
      // Never let a corrupt local cache block app startup.
    }

    // Time-based flush floor - see _periodicFlushInterval's own doc
    // comment. One timer for the app's whole lifetime (this class is a
    // static singleton with no logout-scoped teardown elsewhere either -
    // _flush() itself already no-ops when nobody's signed in), started
    // once here rather than per-login.
    _periodicFlushTimer?.cancel();
    _periodicFlushTimer = Timer.periodic(_periodicFlushInterval, (_) {
      if (_queue.isNotEmpty) {
        // ignore: unawaited_futures
        _flush();
      }
    });
  }

  /// Records one behavior event. Synchronous and fire-and-forget - never
  /// awaited by callers, never throws.
  static void track(String eventType, Map<String, dynamic> payload) {
    try {
      final event = <String, dynamic>{
        'type': eventType,
        // Client-clock ISO8601, not FieldValue.serverTimestamp() - a
        // server-timestamp sentinel is not valid inside a Firestore array
        // element (only at the top level / in a map field), and these
        // events must survive being queued offline for hours anyway, so a
        // relative client clock is actually the more correct choice here.
        'timestamp': DateTime.now().toIso8601String(),
        'sessionId': _sessionId,
        ...payload,
      };
      _queue.add(event);
      // Fire-and-forget local persistence - never awaited by track()'s caller.
      // ignore: unawaited_futures
      BehaviorQueueStore.save(_queue);

      if (eventType == kEvtRestaurantSelectedFromSearch ||
          eventType == kEvtRestaurantSelectedFromCuisineSearch) {
        _recordRecentSearchHit(
            payload['vendorId']?.toString(), payload['query']?.toString());
      }
      if (eventType == kEvtOrderCompleted) {
        // ignore: unawaited_futures
        _recordOrderInLocalMonthlyTotals(payload);
        // ignore: unawaited_futures
        _recordOrderHistoryLocally(payload);
      }

      if (_queue.length >= _flushThreshold) {
        // ignore: unawaited_futures
        _flush();
      }
    } catch (_) {
      // Tracking must never crash or disrupt the feature it's observing.
    }
  }

  /// Wired from main.dart's didChangeAppLifecycleState for
  /// paused/inactive/detached.
  static void onAppBackgrounded() {
    if (_queue.isEmpty) return;
    // ignore: unawaited_futures
    _flush();
  }

  /// Wired from connectivity_gate.dart's offline->online transition.
  static void onReconnected() {
    if (_queue.isEmpty) return;
    // ignore: unawaited_futures
    _flush();
  }

  // ── Recent-search -> order correlation (in-memory only) ───────────────

  static void _recordRecentSearchHit(String? vendorId, String? query) {
    if (vendorId == null || vendorId.isEmpty) return;
    final q = (query ?? '').trim();
    if (q.isEmpty) return; // Search Confidence needs the query text - no query, nothing to escalate.
    _recentSearchHits.add(_RecentSearchHit(vendorId, q, DateTime.now()));
    if (_recentSearchHits.length > _recentSearchMaxEntries) {
      _recentSearchHits.removeAt(0);
    }
  }

  /// The query text that most recently led this customer to [vendorId] via
  /// a tapped search result, within the recency window - or null if this
  /// vendor wasn't reached via search recently. Used by Search Confidence
  /// (_computeSummaryUpdates below) to escalate the SPECIFIC query when a
  /// later action (restaurant opened / product viewed / added to cart /
  /// ordered) happens at that same vendor.
  static String? _recentSearchQueryFor(String vendorId) {
    final cutoff =
        DateTime.now().subtract(const Duration(minutes: _recentSearchWindowMinutes));
    for (var i = _recentSearchHits.length - 1; i >= 0; i--) {
      final h = _recentSearchHits[i];
      if (h.vendorId == vendorId && h.at.isAfter(cutoff)) return h.query;
    }
    return null;
  }

  static bool _wasRecentlyReachedViaSearch(String vendorId) =>
      _recentSearchQueryFor(vendorId) != null;

  /// Public wrapper (2026-07-22) - _recentSearchHits is a volatile,
  /// 15-minute-windowed, IN-MEMORY-ONLY list (see its own doc comment). It
  /// is only meaningful to check at order-CREATION time, while the search
  /// that led here is still fresh in this session - checking it again
  /// later, at order-COMPLETION time (potentially minutes to hours later,
  /// possibly a different app session with an empty list), would silently
  /// and permanently under-count both searchToOrderCount AND
  /// searchConfidenceOrdered (which needs the actual query text, not just
  /// a yes/no). So this is called once, at checkout (PaymentScreen/
  /// CheckoutScreen), and the query text (or null) is captured into the
  /// order's own analyticsSnapshot as 'reachedViaSearchQuery' -
  /// PurchaseCompletionListener reads that stored value later and derives
  /// BOTH signals from it, rather than re-deriving a check that can no
  /// longer be answered correctly by then.
  static String? recentSearchQueryFor(String vendorId) =>
      _recentSearchQueryFor(vendorId);

  // ── Restaurant Engagement session lifecycle (Phase 2, 2026-07-24) ─────

  /// Starts a new restaurant-engagement session for [vendorId]: mints a
  /// fresh session id, consumes whatever entry source/search context was
  /// staged via setNextEntrySource/setNextSearchContext (defaulting to
  /// 'Direct'/empty if the caller reached this screen through a path that
  /// doesn't tag one, e.g. deep link or an untagged legacy call site), and
  /// remembers it for recentRestaurantSessionFor to find later. Called once
  /// from NewVendorProductsScreen/DineInRestaurantDetailsScreen's
  /// initState - everything returned is the caller's to hold in local
  /// State fields and include verbatim in its own kEvtRestaurantSessionEnded
  /// event at dispose (entrySource/searchKeyword/searchType never need a
  /// second lookup).
  static ({String sessionId, String entrySource, String searchKeyword, String searchType})
      startRestaurantSession(String vendorId) {
    final sessionId = const Uuid().v4();
    final source = _consumeNextEntrySource();
    final searchCtx = _consumeNextSearchContext();
    _recentRestaurantSessions.add(_RecentRestaurantSession(
      vendorId: vendorId,
      sessionId: sessionId,
      entrySource: source,
      searchKeyword: searchCtx.keyword,
      searchType: searchCtx.type,
      at: DateTime.now(),
    ));
    if (_recentRestaurantSessions.length > _recentRestaurantSessionMaxEntries) {
      _recentRestaurantSessions.removeAt(0);
    }
    // ignore: unawaited_futures
    _persistRecentRestaurantSessions();
    return (
      sessionId: sessionId,
      entrySource: source,
      searchKeyword: searchCtx.keyword,
      searchType: searchCtx.type,
    );
  }

  /// The most recent restaurant-engagement session for [vendorId] within
  /// the recency window - used at checkout time to stamp
  /// restaurantSessionId onto the order's own analyticsSnapshot (see
  /// CheckoutScreen/PaymentScreen), so PurchaseCompletionListener can later
  /// attribute order completion back to the exact browsing session that
  /// led to it, even in a future app session where this in-memory list is
  /// long gone. Null when this vendor has no recent tracked visit (e.g. an
  /// order placed via Orders-history reorder with no fresh menu visit).
  static ({
    String sessionId,
    String entrySource,
    String searchKeyword,
    String searchType,
    DateTime startedAt
  })? recentRestaurantSessionFor(String vendorId) {
    final cutoff = DateTime.now()
        .subtract(const Duration(minutes: _recentRestaurantSessionWindowMinutes));
    for (var i = _recentRestaurantSessions.length - 1; i >= 0; i--) {
      final s = _recentRestaurantSessions[i];
      if (s.vendorId == vendorId && s.at.isAfter(cutoff)) {
        return (
          sessionId: s.sessionId,
          entrySource: s.entrySource,
          searchKeyword: s.searchKeyword,
          searchType: s.searchType,
          startedAt: s.at,
        );
      }
    }
    return null;
  }

  // Fire-and-forget persistence for _recentRestaurantSessions - see
  // RecentRestaurantSessionStore's own doc comment for why this exists.
  // Prunes anything already past the recency window on every write too,
  // not just on load, so this can't accumulate stale entries between app
  // restarts.
  static Future<void> _persistRecentRestaurantSessions() async {
    try {
      final cutoff = DateTime.now().subtract(
          const Duration(minutes: _recentRestaurantSessionWindowMinutes));
      _recentRestaurantSessions.removeWhere((s) => !s.at.isAfter(cutoff));
      await RecentRestaurantSessionStore.save(
          _recentRestaurantSessions.map((s) => s.toJson()).toList());
    } catch (_) {
      // Collection only - a failed persist must never disrupt the app.
    }
  }

  // ── Combo metadata cache (2026-07-24) ──────────────────────────────────
  // Call at add-to-cart time, only when productModel.isCombo - captures
  // exactly what PurchaseCompletionListener needs to fire kEvtComboOrdered
  // later, with zero extra reads at checkout or at order-completion time.
  //
  // Deliberately captures ONLY distinct child productIds, never each
  // child's own quantity-within-the-combo (ComboProductItem.quantity is
  // intentionally dropped by every caller of this method) - see
  // _computeSummaryUpdates' kEvtComboOrdered case for why: a combo's
  // child-quantity list describes serving size, not repeated purchase
  // intent, and this codebase never aggregates it as if it were.
  static void rememberComboMetadata(
    String productId, {
    required List<String> comboProductIds,
    required List<String> comboCategoryIds,
    required String price,
  }) {
    if (productId.isEmpty) return;
    _recentComboMetadata[productId] = _ComboMetadata(
      // Deduped defensively - a combo's own comboProducts list should
      // already be distinct-by-productId, but nothing upstream guarantees
      // that, and an accidental duplicate here would otherwise silently
      // violate "never increment a child product more than once per
      // combo order" if anything ever DOES aggregate this list per-entry.
      comboProductIds: comboProductIds.toSet().toList(),
      comboCategoryIds: comboCategoryIds.toSet().toList(),
      price: price,
      at: DateTime.now(),
    );
    if (_recentComboMetadata.length > _recentComboMetadataMaxEntries) {
      // Evict the oldest entry by timestamp - a plain Map has no insertion-
      // order eviction primitive, and this cache is small/infrequent enough
      // that an O(n) scan on overflow is a non-issue.
      String? oldestKey;
      DateTime? oldestAt;
      _recentComboMetadata.forEach((key, value) {
        if (oldestAt == null || value.at.isBefore(oldestAt!)) {
          oldestKey = key;
          oldestAt = value.at;
        }
      });
      if (oldestKey != null) _recentComboMetadata.remove(oldestKey);
    }
    // ignore: unawaited_futures
    _persistComboMetadata();
  }

  /// Looked up at checkout time (CheckoutScreen/PaymentScreen) per cart
  /// line item, by productId. Null for any non-combo product, or a combo
  /// added to cart in a previous app session more than
  /// _recentComboMetadataMaxEntries combo-adds ago (evicted).
  static ({List<String> comboProductIds, List<String> comboCategoryIds, String price})?
      comboMetadataFor(String productId) {
    final m = _recentComboMetadata[productId];
    if (m == null) return null;
    return (
      comboProductIds: m.comboProductIds,
      comboCategoryIds: m.comboCategoryIds,
      price: m.price,
    );
  }

  static Future<void> _persistComboMetadata() async {
    try {
      final json = <String, dynamic>{};
      _recentComboMetadata.forEach((key, value) => json[key] = value.toJson());
      await ComboMetadataStore.save(json);
    } catch (_) {
      // Collection only - a failed persist must never disrupt the app.
    }
  }

  // ── Shared, session-keyed live counters (2026-07-24) ──────────────────
  // NewVendorProductsScreen/DineInRestaurantDetailsScreen each keep their
  // OWN screen-local counters (_sessionProductViewCount etc.) because they
  // never share one session across more than one screen instance. But
  // ProductDetailsScreen CAN be reached directly (Home's "Popular near
  // you", Favourites) and can chain into itself ("more from this store"),
  // so several separate widget instances can legitimately share ONE
  // restaurant-visit session. A screen-local counter there would either
  // fragment one continuous visit into several restaurantEngagement docs,
  // or silently drop counts from every instance but the one that happens
  // to dispose last. This registry is the fix: counters live keyed by
  // sessionId, not by widget instance, so it doesn't matter which/how many
  // ProductDetailsScreen instances contributed to them.
  static final Map<String, _LiveRestaurantSessionCounters>
      _liveSessionCounters = {};

  static void bumpSessionProductView(String sessionId, {String? categoryId}) {
    if (sessionId.isEmpty) return;
    final c = _liveSessionCounters.putIfAbsent(
        sessionId, () => _LiveRestaurantSessionCounters());
    c.productViewCount++;
    if (categoryId != null && categoryId.isNotEmpty) {
      c.categoriesBrowsed.add(categoryId);
    }
  }

  static void bumpSessionAddToCart(String sessionId) {
    if (sessionId.isEmpty) return;
    _liveSessionCounters
        .putIfAbsent(sessionId, () => _LiveRestaurantSessionCounters())
        .addToCartCount++;
  }

  /// Fires kEvtRestaurantSessionEnded exactly once per sessionId - safe to
  /// call from more than one stacked screen instance sharing the same
  /// session, since the counters are removed from the registry on the
  /// FIRST call; every later call for the same id is a no-op. Whichever
  /// instance happens to dispose last still reports the FULL accumulated
  /// total across all of them, not just its own slice.
  static void endRestaurantSession(
    String sessionId, {
    required String vendorId,
    required String entrySource,
    required String searchKeyword,
    required String searchType,
    required DateTime startedAt,
  }) {
    if (sessionId.isEmpty) return;
    final counters = _liveSessionCounters.remove(sessionId);
    if (counters == null) return; // already ended by another instance
    track(kEvtRestaurantSessionEnded, {
      'vendorId': vendorId,
      'sessionId': sessionId,
      'entrySource': entrySource,
      'searchKeyword': searchKeyword,
      'searchType': searchType,
      'startedAt': startedAt.toIso8601String(),
      'menuDurationSeconds': DateTime.now().difference(startedAt).inSeconds,
      'productViewCount': counters.productViewCount,
      'categoriesBrowsedCount': counters.categoriesBrowsed.length,
      'addToCartCount': counters.addToCartCount,
    });
  }

  // ── Banner click attribution (Phase 2, 2026-07-24) ─────────────────────

  /// Call immediately after firing kEvtBannerClicked for a banner whose
  /// redirect actually leads somewhere orderable (store/product), so a
  /// subsequent placed order within the window can be attributed to it.
  static void setNextBannerClick(String bannerId) {
    _lastBannerClickId = bannerId;
    _lastBannerClickAt = DateTime.now();
  }

  /// The most recently clicked banner id within the attribution window, or
  /// null - read (not consumed) at checkout time, same peek semantics as
  /// recentSearchQueryFor.
  static String? recentBannerClickId() {
    final at = _lastBannerClickAt;
    if (at == null) return null;
    final cutoff = DateTime.now()
        .subtract(const Duration(minutes: _recentBannerClickWindowMinutes));
    return at.isAfter(cutoff) ? _lastBannerClickId : null;
  }

  // ── Local monthly totals (for accurate derived scalars, zero reads) ───

  static String _currentYearMonth() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  /// 'yyyy-MM-dd' day key from an event's own ISO8601 timestamp (see
  /// track()'s 'timestamp' field) - null on any parse failure, so a
  /// malformed timestamp just skips day-tracking for that one event
  /// instead of throwing.
  static String? _dayKeyFrom(String? isoTimestamp) {
    if (isoTimestamp == null) return null;
    final dt = DateTime.tryParse(isoTimestamp);
    if (dt == null) return null;
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  static Future<Map<String, dynamic>> _loadMonthlyTotals() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_monthlyTotalsPrefsKey);
    final month = _currentYearMonth();
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['yearMonth'] == month) return decoded;
      } catch (_) {
        // fall through to a fresh map
      }
    }
    // No stored totals, or they're for a previous month - start fresh.
    return {
      'yearMonth': month,
      'totalOrderAmount': 0.0,
      'orderCount': 0,
      'paymentMethodCounts': <String, dynamic>{},
      'orderModeCounts': <String, dynamic>{},
      // Restaurant-switching / category+cuisine-transition counters
      // (2026-07-21) - monthly-reset like everything else in this blob,
      // snapshot-written into behavior_summary the same way avgOrderValue
      // is below, not a Firestore FieldValue.increment (this file has zero
      // read cost by design, so "how many switches this month" is derived
      // from local running state, not a Firestore read-then-write).
      'vendorSwitchCount': 0,
      'categoryTransitionCounts': <String, dynamic>{},
      'cuisineTransitionCounts': <String, dynamic>{},
      // Customer budget profile (2026-07-21) - deliberately NOT a tiered
      // label ("low"/"mid"/"high"): fixed currency thresholds would be
      // wrong across regions and nothing consumes this yet anyway, so this
      // stores the raw min/max spread alongside the already-existing
      // avgOrderValue instead, giving a future V2 real material to derive
      // its own tiering from rather than trusting a guess made today.
      'minOrderAmount': null,
      'maxOrderAmount': null,
    };
  }

  /// Lifetime (never month-reset) "what was the last order" context - see
  /// _lastOrderContextPrefsKey's doc comment for why this is separate from
  /// _loadMonthlyTotals above.
  static Future<Map<String, dynamic>> _loadLastOrderContext() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastOrderContextPrefsKey);
    if (raw == null) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _recordOrderInLocalMonthlyTotals(
      Map<String, dynamic> orderPayload) async {
    final totals = await _loadMonthlyTotals();
    final amount = (orderPayload['amount'] as num?)?.toDouble() ?? 0.0;
    totals['totalOrderAmount'] = ((totals['totalOrderAmount'] as num?) ?? 0) + amount;
    totals['orderCount'] = ((totals['orderCount'] as num?) ?? 0) + 1;

    // Customer budget profile - running min/max, see _loadMonthlyTotals'
    // doc comment for why this is spread, not a tiered label.
    final currentMin = totals['minOrderAmount'] as num?;
    if (currentMin == null || amount < currentMin) totals['minOrderAmount'] = amount;
    final currentMax = totals['maxOrderAmount'] as num?;
    if (currentMax == null || amount > currentMax) totals['maxOrderAmount'] = amount;

    final paymentMethod = (orderPayload['paymentMethod'] as String?) ?? 'unknown';
    final paymentCounts = Map<String, dynamic>.from(totals['paymentMethodCounts'] ?? {});
    paymentCounts[paymentMethod] = ((paymentCounts[paymentMethod] as num?) ?? 0) + 1;
    totals['paymentMethodCounts'] = paymentCounts;

    final orderMode = (orderPayload['orderMode'] as String?) ?? 'unknown';
    final modeCounts = Map<String, dynamic>.from(totals['orderModeCounts'] ?? {});
    modeCounts[orderMode] = ((modeCounts[orderMode] as num?) ?? 0) + 1;
    totals['orderModeCounts'] = modeCounts;

    // Restaurant-switching / category+cuisine-transition detection
    // (2026-07-21) - compares this order's vendor/category/cuisine against
    // the lifetime "last order" context (never against a Firestore read).
    // A previous value of '' (never ordered before, or this dimension
    // wasn't present on a past order) never counts as a switch - only a
    // real A-to-B transition does.
    final vendorId = (orderPayload['vendorId'] as String?) ?? '';
    final categoryId = (orderPayload['categoryId'] as String?) ?? '';
    final cuisineIds = ((orderPayload['cuisineIds'] as List?) ?? const [])
        .map((c) => c.toString())
        .where((c) => c.isNotEmpty)
        .toList();
    final cuisineId = cuisineIds.isNotEmpty ? cuisineIds.first : '';

    final lastContext = await _loadLastOrderContext();
    final prevVendorId = (lastContext['lastVendorId'] as String?) ?? '';
    final prevCategoryId = (lastContext['lastCategoryId'] as String?) ?? '';
    final prevCuisineId = (lastContext['lastCuisineId'] as String?) ?? '';

    if (vendorId.isNotEmpty && prevVendorId.isNotEmpty && vendorId != prevVendorId) {
      totals['vendorSwitchCount'] = ((totals['vendorSwitchCount'] as num?) ?? 0) + 1;
    }
    if (categoryId.isNotEmpty && prevCategoryId.isNotEmpty && categoryId != prevCategoryId) {
      final key = '$prevCategoryId>$categoryId';
      final counts = Map<String, dynamic>.from(totals['categoryTransitionCounts'] ?? {});
      counts[key] = ((counts[key] as num?) ?? 0) + 1;
      totals['categoryTransitionCounts'] = counts;
    }
    if (cuisineId.isNotEmpty && prevCuisineId.isNotEmpty && cuisineId != prevCuisineId) {
      final key = '$prevCuisineId>$cuisineId';
      final counts = Map<String, dynamic>.from(totals['cuisineTransitionCounts'] ?? {});
      counts[key] = ((counts[key] as num?) ?? 0) + 1;
      totals['cuisineTransitionCounts'] = counts;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_monthlyTotalsPrefsKey, jsonEncode(totals));

    if (vendorId.isNotEmpty || categoryId.isNotEmpty || cuisineId.isNotEmpty) {
      await prefs.setString(
          _lastOrderContextPrefsKey,
          jsonEncode({
            'lastVendorId': vendorId.isNotEmpty ? vendorId : prevVendorId,
            'lastCategoryId': categoryId.isNotEmpty ? categoryId : prevCategoryId,
            'lastCuisineId': cuisineId.isNotEmpty ? cuisineId : prevCuisineId,
          }));
    }
  }

  /// Sequential ordering pattern / restaurant co-occurrence local state
  /// (2026-07-21, collection-only) - both capped lists, updated the moment
  /// an order is placed (same timing as _recordOrderInLocalMonthlyTotals
  /// above), snapshot-written to their own docs at the next flush. Never
  /// grows past their caps - not the unbounded-raw-log pattern flagged
  /// elsewhere in this system.
  static Future<void> _recordOrderHistoryLocally(
      Map<String, dynamic> orderPayload) async {
    final vendorId = (orderPayload['vendorId'] as String?) ?? '';
    final categoryId = (orderPayload['categoryId'] as String?) ?? '';
    final cuisineIds = ((orderPayload['cuisineIds'] as List?) ?? const [])
        .map((c) => c.toString())
        .where((c) => c.isNotEmpty)
        .toList();
    final cuisineId = cuisineIds.isNotEmpty ? cuisineIds.first : '';

    final prefs = await SharedPreferences.getInstance();

    // Vendor history - move-to-end-on-repeat, capped, oldest dropped.
    // Powers restaurant co-occurrence pair-generation at flush time.
    if (vendorId.isNotEmpty) {
      var history = <String>[];
      final raw = prefs.getString(_vendorHistoryPrefsKey);
      if (raw != null) {
        try {
          history = (jsonDecode(raw) as List).map((e) => e.toString()).toList();
        } catch (_) {}
      }
      history.remove(vendorId);
      history.add(vendorId);
      if (history.length > _vendorHistoryMaxEntries) {
        history = history.sublist(history.length - _vendorHistoryMaxEntries);
      }
      await prefs.setString(_vendorHistoryPrefsKey, jsonEncode(history));
    }

    // Order sequence - append, capped, oldest dropped.
    var sequence = <dynamic>[];
    final rawSeq = prefs.getString(_orderSequencePrefsKey);
    if (rawSeq != null) {
      try {
        sequence = jsonDecode(rawSeq) as List;
      } catch (_) {}
    }
    sequence.add({
      'vendorId': vendorId,
      'categoryId': categoryId,
      'cuisineId': cuisineId,
      'ts': DateTime.now().toIso8601String(),
    });
    if (sequence.length > _orderSequenceMaxEntries) {
      sequence = sequence.sublist(sequence.length - _orderSequenceMaxEntries);
    }
    await prefs.setString(_orderSequencePrefsKey, jsonEncode(sequence));
  }

  static String? _argmax(Map<String, dynamic> counts) {
    if (counts.isEmpty) return null;
    String? best;
    num bestCount = -1;
    counts.forEach((k, v) {
      final c = (v as num?) ?? 0;
      if (c > bestCount) {
        bestCount = c;
        best = k;
      }
    });
    return best;
  }

  // ── Flush ───────────────────────────────────────────────────────────

  static Future<void> _flush() async {
    if (_flushing || _queue.isEmpty) return;
    _flushing = true;
    try {
      final uid = FireStoreUtils.getCurrentUid();
      if (uid.isEmpty) {
        // Not signed in - keep events queued locally, try again next trigger.
        return;
      }

      final batch = List<Map<String, dynamic>>.from(_queue);
      final userRef = FireStoreUtils.firestore.collection('users').doc(uid);
      final batchRef = userRef.collection('behavior_batches').doc();
      final yearMonth = _currentYearMonth();
      final summaryRef = userRef.collection('behavior_summary').doc(yearMonth);

      final summaryUpdates = await _computeSummaryUpdates(batch, yearMonth);

      final writeBatch = FireStoreUtils.firestore.batch();
      writeBatch.set(batchRef, {
        'userId': uid,
        'flushedAt': FieldValue.serverTimestamp(),
        'eventCount': batch.length,
        'events': batch,
      });
      if (summaryUpdates.isNotEmpty) {
        writeBatch.set(summaryRef, summaryUpdates, SetOptions(merge: true));
      }

      // Seasonal ordering preference / sequential ordering pattern
      // (2026-07-21, collection-only) - both only apply when this flush's
      // batch actually contains a placed order; skipped entirely otherwise
      // so a pure-browsing flush never touches these docs. Restaurant
      // co-occurrence AGGREGATION also happens in this window (same gate,
      // unchanged) - but as of 2026-07-24 it no longer writes directly to
      // Firestore here; see restaurantPairAggregates below.
      List<Map<String, dynamic>> restaurantPairAggregates = const [];
      if (batch.any((e) => e['type'] == kEvtOrderCompleted)) {
        final seasonalUpdates = _computeSeasonalPreferenceUpdates(batch);
        if (seasonalUpdates.isNotEmpty) {
          final seasonalRef = userRef.collection('seasonalPreferences').doc('summary');
          writeBatch.set(seasonalRef, seasonalUpdates, SetOptions(merge: true));
        }

        final sequenceSnapshot = await _loadOrderSequenceSnapshot();
        if (sequenceSnapshot.isNotEmpty) {
          final sequenceRef = userRef.collection('orderSequence').doc('latest');
          writeBatch.set(sequenceRef,
              {'orders': sequenceSnapshot, 'updatedAt': FieldValue.serverTimestamp()});
        }

        if (_restaurantPairingTrackingEnabled) {
          restaurantPairAggregates = await _buildRestaurantPairingAggregates(batch);
        }
      }

      // Restaurant Engagement / Search Conversion (Phase 2, 2026-07-24,
      // collection-only) - one merge-write per kEvtRestaurantSessionEnded
      // event (already carries every field pre-computed by the screen) plus
      // one merge-write per kEvtOrderPlacedForEngagement event that carries
      // a resolvable restaurantSessionId. No-op on a batch with neither
      // event type. Writes to users/{uid}/restaurantEngagement, a sibling
      // of behavior_summary - never the same doc, never read by
      // RecommendationEngine. USER-OWNED, so this stays a direct client
      // write like everything else above - unaffected by the global-
      // analytics backend split below.
      _addRestaurantEngagementWrites(writeBatch, userRef, uid, batch);

      // Per-user banner-click breakdown (Phase 2, 2026-07-24) - USER-OWNED
      // (users/{uid}/bannerClicks/{bannerId}), stays a direct client write.
      _addBannerUserClickWrites(writeBatch, userRef, batch);

      // Global Analytics backend hand-off (2026-07-24) - bannerAnalytics
      // and restaurantPairings are GLOBAL, not user-owned, so they no
      // longer get written directly by the client at all (Firestore rules
      // now deny it - see firestore.rules). Instead this batch's events are
      // pre-aggregated into per-bannerId/per-pairId DELTAS, in-memory, here
      // - no Firestore write yet - and handed to
      // GlobalAnalyticsController::ingestBatch on the Laravel backend,
      // which verifies the caller's Firebase ID token and validates every
      // delta before committing. Sent BEFORE writeBatch.commit() below and
      // treated as part of the SAME all-or-nothing flush: a failure here
      // aborts the whole flush (queue stays intact, retried next trigger),
      // exactly like a writeBatch.commit() failure already does.
      //
      // Known, accepted edge case (same class of risk this whole file
      // already carries elsewhere, e.g. behavior_batches/behavior_summary
      // on a lost commit-confirmation): if THIS call succeeds server-side
      // but writeBatch.commit() below then fails, the queue is still left
      // intact (by design, since the two aren't one atomic unit), so the
      // NEXT flush attempt re-sends the same deltas and double-applies
      // them server-side. No idempotency key is added for this - it would
      // be new machinery this system doesn't use anywhere else for its
      // increment-style aggregates, and the failure window it guards
      // (HTTP succeeds, Firestore fails, in the same few hundred
      // milliseconds) is rare enough that this file's existing tradeoffs
      // already accept an equivalent risk without one.
      final bannerAggregates = _buildBannerAnalyticsAggregates(batch);
      if (bannerAggregates.isNotEmpty || restaurantPairAggregates.isNotEmpty) {
        final globalOk = await GlobalAnalyticsApi.sendBatch(
          banners: bannerAggregates,
          restaurantPairs: restaurantPairAggregates,
        );
        if (!globalOk) return; // leave queue untouched, retry next trigger
      }

      await writeBatch.commit();

      // Only clear on confirmed success - on any failure above, the queue
      // (memory + persisted) is left exactly as it was, so the next trigger
      // (threshold/background/reconnect) retries the same events. This is
      // the offline-durability contract.
      _queue.removeRange(0, batch.length);
      // ignore: unawaited_futures
      BehaviorQueueStore.save(_queue);

      await _pruneOldSummariesIfNeeded(userRef, yearMonth);
    } catch (_) {
      // Swallow - queue stays intact, retried on the next trigger. Tracking
      // must never surface an error to the rest of the app.
    } finally {
      _flushing = false;
    }
  }

  /// Seasonal ordering preference (2026-07-21, collection-only) - month-
  /// OF-YEAR buckets (1-12, accumulated across every year, not a specific
  /// calendar month like behavior_summary) so one doc can answer "does
  /// this customer order more soup in December" across every December,
  /// not just the last one. Purely a function of this batch's own
  /// kEvtOrderCompleted events - no local state, no read, fully idempotent
  /// if a flush retries.
  static Map<String, dynamic> _computeSeasonalPreferenceUpdates(
      List<Map<String, dynamic>> batch) {
    final updates = <String, dynamic>{};
    for (final e in batch) {
      if (e['type'] != kEvtOrderCompleted) continue;
      final orderedAt = DateTime.tryParse(e['timestamp'] as String? ?? '');
      if (orderedAt == null) continue;
      final month = orderedAt.month; // 1-12
      final categoryId = (e['categoryId'] as String?) ?? '';
      if (categoryId.isNotEmpty) {
        updates['month.$month.category.$categoryId'] = FieldValue.increment(1);
      }
      final cuisineIds = ((e['cuisineIds'] as List?) ?? const [])
          .map((c) => c.toString())
          .where((c) => c.isNotEmpty);
      for (final cuisineId in cuisineIds) {
        updates['month.$month.cuisine.$cuisineId'] = FieldValue.increment(1);
      }
    }
    return updates;
  }

  /// Sequential ordering pattern's read side of _recordOrderHistoryLocally
  /// above - just the current capped local list, ready to snapshot-write.
  static Future<List<dynamic>> _loadOrderSequenceSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_orderSequencePrefsKey);
    if (raw == null) return const [];
    try {
      return jsonDecode(raw) as List;
    } catch (_) {
      return const [];
    }
  }

  /// Restaurant co-occurrence (2026-07-21, collection-only, off by default
  /// - see _restaurantPairingTrackingEnabled). Pairs this flush's newly-
  /// ordered-from vendor(s) against the customer's own vendor history
  /// (already sitting locally, see _recordOrderHistoryLocally - no
  /// Firestore read), and returns one aggregate entry per distinct pair
  /// with its count DELTA for this batch - never writes to Firestore
  /// itself (2026-07-24: restaurantPairings is a GLOBAL, not user-owned,
  /// collection, so the actual write now happens server-side via
  /// GlobalAnalyticsApi.sendBatch -> GlobalAnalyticsController::ingestBatch
  /// - see this file's _flush() call site and firestore.rules for why).
  static Future<List<Map<String, dynamic>>> _buildRestaurantPairingAggregates(
      List<Map<String, dynamic>> batch) async {
    final orderedVendorIds = batch
        .where((e) => e['type'] == kEvtOrderCompleted)
        .map((e) => (e['vendorId'] as String?) ?? '')
        .where((v) => v.isNotEmpty)
        .toSet();
    if (orderedVendorIds.isEmpty) return const [];

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_vendorHistoryPrefsKey);
    if (raw == null) return const [];
    List<String> history;
    try {
      history = (jsonDecode(raw) as List).map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }

    final aggregates = <String, Map<String, dynamic>>{};
    for (final vendorId in orderedVendorIds) {
      for (final otherVendorId in history) {
        if (otherVendorId == vendorId) continue;
        final sortedPair = [vendorId, otherVendorId]..sort();
        final pairKey = '${sortedPair[0]}__${sortedPair[1]}';
        final entry = aggregates.putIfAbsent(
            pairKey,
            () => {
                  'vendorA': sortedPair[0],
                  'vendorB': sortedPair[1],
                  'countDelta': 0,
                });
        entry['countDelta'] = (entry['countDelta'] as int) + 1;
      }
    }
    return aggregates.values.toList();
  }

  /// Restaurant Engagement / Search Conversion writes (Phase 2,
  /// 2026-07-24) - see this file's _flush() call site for what feeds it.
  /// Purely a per-event dispatch to one merge-write each; no local
  /// accumulator is needed (unlike _computeSummaryUpdates' _pendingDeltas)
  /// because each session id gets at most one kEvtRestaurantSessionEnded
  /// in its lifetime (fired once, at dispose) and at most one
  /// kEvtOrderPlacedForEngagement (fired once, at checkout) - there is
  /// nothing for two events in the same batch to collide on.
  static void _addRestaurantEngagementWrites(WriteBatch writeBatch,
      DocumentReference userRef, String uid, List<Map<String, dynamic>> batch) {
    final engagementCollection = userRef.collection('restaurantEngagement');
    for (final e in batch) {
      final type = e['type'];
      if (type == kEvtRestaurantSessionEnded) {
        final sessionId = (e['sessionId'] ?? '').toString();
        if (sessionId.isEmpty) continue;
        final productViewCount = ((e['productViewCount'] as num?) ?? 0).toInt();
        final addToCartCount = ((e['addToCartCount'] as num?) ?? 0).toInt();
        final menuDurationSeconds =
            ((e['menuDurationSeconds'] as num?) ?? 0).toDouble();
        writeBatch.set(
          engagementCollection.doc(sessionId),
          {
            'userId': uid,
            'vendorId': e['vendorId'] ?? '',
            'sessionId': sessionId,
            'entrySource': e['entrySource'] ?? 'Direct',
            'searchKeyword': e['searchKeyword'] ?? '',
            'searchType': e['searchType'] ?? '',
            'menuDurationSeconds': menuDurationSeconds,
            'productViewCount': productViewCount,
            'categoriesBrowsedCount': (e['categoriesBrowsedCount'] as num?) ?? 0,
            'addToCartCount': addToCartCount,
            // orderPlaced/orderCompleted default false here and are only
            // ever flipped true by a LATER merge-write below/from
            // PurchaseCompletionListener - never overwritten back to false,
            // since neither of those write paths ever sets the field at all
            // unless it's true.
            'orderPlaced': false,
            'orderCompleted': false,
            'engagementScore': _computeEngagementScore(
              menuDurationSeconds: menuDurationSeconds,
              productViewCount: productViewCount,
              addToCartCount: addToCartCount,
            ),
            'startedAt': e['startedAt'] ?? '',
            'endedAt': e['timestamp'] ?? '',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } else if (type == kEvtOrderPlacedForEngagement) {
        final sessionId = (e['restaurantSessionId'] ?? '').toString();
        if (sessionId.isEmpty) continue;
        writeBatch.set(
          engagementCollection.doc(sessionId),
          {
            'orderPlaced': true,
            'orderPlacedAt': e['timestamp'] ?? '',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } else if (type == kEvtOrderCompleted) {
        // Fired much later than session-end (post-fulfillment, via
        // PurchaseCompletionListener) - see that class' own doc comment for
        // why restaurantSessionId rides along on this existing event
        // instead of a new one. A no-op for every order whose snapshot
        // predates this field or that never had a resolvable session.
        final sessionId = (e['restaurantSessionId'] ?? '').toString();
        if (sessionId.isEmpty) continue;
        writeBatch.set(
          engagementCollection.doc(sessionId),
          {
            'orderCompleted': true,
            'orderCompletedAt': e['timestamp'] ?? '',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    }
  }

  /// Lightweight 0-100 engagement score - stored for a FUTURE
  /// recommendation model to consume, not read by anything in this app
  /// today (see this file's Phase 2 header comment / the event-types file).
  /// Deliberately simple capped-linear contributions from dwell time,
  /// product exploration, and cart intent - not a claim of statistical
  /// rigor, just one sortable number so a future dashboard/model doesn't
  /// have to re-derive one from three raw fields every time.
  static int _computeEngagementScore({
    required double menuDurationSeconds,
    required int productViewCount,
    required int addToCartCount,
  }) {
    final durationScore = (menuDurationSeconds / 180.0).clamp(0.0, 1.0) * 40;
    final viewScore = (productViewCount / 10.0).clamp(0.0, 1.0) * 35;
    final cartScore = (addToCartCount / 5.0).clamp(0.0, 1.0) * 25;
    return (durationScore + viewScore + cartScore).round().clamp(0, 100);
  }

  /// Per-user banner-click breakdown (Phase 2, 2026-07-24, revised same
  /// day) - users/{uid}/bannerClicks/{bannerId}, USER-OWNED so this stays
  /// a direct client write like everything else under users/{uid} (powers
  /// a future "User A -> 5 clicks" dashboard via a
  /// collectionGroup('bannerClicks') query). The GLOBAL bannerAnalytics
  /// aggregate this used to also write is handled separately now - see
  /// _buildBannerAnalyticsAggregates below.
  static void _addBannerUserClickWrites(
      WriteBatch writeBatch, DocumentReference userRef, List<Map<String, dynamic>> batch) {
    final bannerClicksCollection = userRef.collection('bannerClicks');
    for (final e in batch) {
      if (e['type'] != kEvtBannerClicked) continue;
      final bannerId = (e['bannerId'] ?? '').toString();
      if (bannerId.isEmpty) continue;
      writeBatch.set(
        bannerClicksCollection.doc(bannerId),
        {
          'bannerId': bannerId,
          'clickCount': FieldValue.increment(1),
          'lastClickedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
  }

  /// Pure aggregation (no Firestore writes) of this flush's banner
  /// impression/click/order events into per-bannerId DELTAS, ready to POST
  /// via GlobalAnalyticsApi.sendBatch (2026-07-24: bannerAnalytics is a
  /// GLOBAL, not user-owned, collection - the client no longer writes it
  /// directly at all, see firestore.rules and
  /// GlobalAnalyticsController::ingestBatch on the Laravel backend for why).
  /// A local Map accumulator (keyed by bannerId) is needed here, unlike
  /// _addRestaurantEngagementWrites - several impressions/clicks of the
  /// SAME banner can land in one flush batch and must sum into one delta
  /// per field, not overwrite each other.
  static List<Map<String, dynamic>> _buildBannerAnalyticsAggregates(
      List<Map<String, dynamic>> batch) {
    final aggregates = <String, Map<String, dynamic>>{};

    Map<String, dynamic> entryFor(String bannerId) => aggregates.putIfAbsent(
        bannerId,
        () => {
              'bannerId': bannerId,
              'position': '',
              'slot': '',
              'impressionDelta': 0,
              'clickDelta': 0,
              'uniqueClickDelta': 0,
              'orderDelta': 0,
              'revenueDelta': 0.0,
            });

    for (final e in batch) {
      final type = e['type'];
      if (type == kEvtBannerImpression) {
        final bannerId = (e['bannerId'] ?? '').toString();
        if (bannerId.isEmpty) continue;
        final entry = entryFor(bannerId);
        entry['position'] = e['position'] ?? entry['position'];
        entry['slot'] = e['slot'] ?? entry['slot'];
        entry['impressionDelta'] = (entry['impressionDelta'] as int) + 1;
      } else if (type == kEvtBannerClicked) {
        final bannerId = (e['bannerId'] ?? '').toString();
        if (bannerId.isEmpty) continue;
        final entry = entryFor(bannerId);
        entry['position'] = e['position'] ?? entry['position'];
        entry['slot'] = e['slot'] ?? entry['slot'];
        entry['clickDelta'] = (entry['clickDelta'] as int) + 1;
        // localClickCount is the ALREADY-INCREMENTED on-device repeat
        // counter for (this device, this banner) - see
        // BehaviorCounters.increment's call site in HomeScreen.dart. ==1
        // means this device has never clicked this banner before, i.e. a
        // genuinely new unique clicker from this device's point of view -
        // a per-device, not cross-device-atomic, approximation (a customer
        // clicking the same banner from two different devices double-
        // counts as two uniques), same accepted trade-off as before this
        // moved server-side.
        if ((e['localClickCount'] as num?) == 1) {
          entry['uniqueClickDelta'] = (entry['uniqueClickDelta'] as int) + 1;
        }
      } else if (type == kEvtOrderPlacedForEngagement) {
        final bannerId = (e['reachedViaBannerId'] ?? '').toString();
        if (bannerId.isEmpty) continue;
        final entry = entryFor(bannerId);
        entry['orderDelta'] = (entry['orderDelta'] as int) + 1;
        // amount comes straight from the order's own analyticsSnapshot
        // (see FirebaseHelper.placeOrder) - real revenue, not a
        // placeholder.
        entry['revenueDelta'] = (entry['revenueDelta'] as double) +
            (((e['amount'] as num?) ?? 0).toDouble());
      }
    }

    return aggregates.values.toList();
  }

  static Future<Map<String, dynamic>> _computeSummaryUpdates(
      List<Map<String, dynamic>> batch, String yearMonth) async {
    final updates = <String, dynamic>{'yearMonth': yearMonth, 'updatedAt': FieldValue.serverTimestamp()};
    final favoriteIds = <String>{};
    var newSearchKeywords = 0;
    const maxNewKeywordsPerFlush = 20; // bounds topSearchKeywords growth
    var newSearchDayKeys = 0;
    const maxNewSearchDayKeysPerFlush = 20; // separate cap, same technique - bounds searchDayHits growth

    // Same-key accumulation within one flush (2026-07-22 fix) - inc/
    // incScalar used to do a plain `updates[key] = FieldValue.increment(by)`
    // map assignment, which OVERWRITES rather than merges when the same
    // key is touched more than once in one batch (e.g. ordering 3
    // different Biryani-category products in one checkout - 3 separate
    // kEvtProductOrdered events, same category, same flush). Firestore
    // only ever saw the LAST call's `by`, silently dropping the others.
    // _pendingDeltas tracks the running local sum per key so the single
    // FieldValue.increment sent per key is always correct for the whole
    // batch, not just whichever event happened to write to that key last.
    // Affects every field these two helpers back - not category/cuisine-
    // specific - so this one fix corrects the same latent under-count for
    // productViewCounts, productOrderQuantities, restaurantVisitCounts,
    // orderCount, and everything else in this function.
    final _pendingDeltas = <String, num>{};

    void inc(String field, String key, {num by = 1}) {
      if (key.isEmpty) return;
      final mapKey = '$field.$key';
      final total = (_pendingDeltas[mapKey] ?? 0) + by;
      _pendingDeltas[mapKey] = total;
      updates[mapKey] = FieldValue.increment(total);
    }

    void incScalar(String field, {num by = 1}) {
      final total = (_pendingDeltas[field] ?? 0) + by;
      _pendingDeltas[field] = total;
      updates[field] = FieldValue.increment(total);
    }

    // Search Confidence (2026-07-18): escalates the query that led a
    // customer to [vendorId] via a tapped search result, one presence-flag
    // field per tier reached. Firestore's FieldValue only supports
    // increment (no max()), so "use the highest confidence accumulated"
    // is expressed as 4 separate presence maps rather than one field that
    // would need a read-before-write to compute a max - the read-time
    // derivation (BehaviorSummarySnapshot.searchConfidenceFor) picks
    // whichever is the highest tier with a non-zero count. A no-op when
    // vendorId wasn't reached via a recent search (the common case).
    void escalateSearchConfidence(String field, String vendorId) {
      if (vendorId.isEmpty) return;
      final query = _recentSearchQueryFor(vendorId);
      if (query != null) inc(field, query);
    }

    for (final e in batch) {
      final type = e['type'] as String?;
      // TEMPORARY diagnostic instrumentation (2026-07-27) - pinpointing
      // whether category/cuisine learning is a stale-client-build issue,
      // an aggregation-logic issue, a Firestore-write issue, or a later
      // overwrite - see this session's investigation. Remove once resolved.
      // Logs the raw category/cuisine fields as received, for exactly the
      // event types that feed categoryInteractionCounts/
      // cuisineInteractionCounts, so a live comparison against the raw
      // event and the final behavior_summary doc is possible.
      if (type == kEvtProductViewed ||
          type == kEvtProductAddedToCart ||
          type == kEvtOrderCompleted ||
          type == kEvtSearchPerformed ||
          type == kEvtRestaurantOpened ||
          type == kEvtComboOrdered) {
        debugPrint('[CATCUISINE-DEBUG] event type=$type '
            'categoryId=${e['categoryId']} categoryIds=${e['categoryIds']} '
            'cuisineIds=${e['cuisineIds']} comboCategoryIds=${e['comboCategoryIds']}');
      }
      switch (type) {
        case kEvtRestaurantOpened:
          final vendorId = (e['vendorId'] ?? '').toString();
          inc('restaurantVisitCounts', vendorId);
          for (final c in (e['cuisineIds'] as List?) ?? const []) {
            inc('cuisineInteractionCounts', c.toString());
            debugPrint('[CATCUISINE-DEBUG]   -> cuisineInteractionCounts.$c += 1 (restaurant_opened)');
          }
          escalateSearchConfidence('searchConfidenceOpened', vendorId); // tier 2 of 5, 30%
          break;
        case kEvtRestaurantFavorited:
          favoriteIds.add((e['vendorId'] ?? '').toString());
          break;
        case kEvtProductViewed:
          inc('productViewCounts', (e['productId'] ?? '').toString());
          if (e['categoryId'] != null) {
            inc('categoryInteractionCounts', e['categoryId'].toString());
            debugPrint('[CATCUISINE-DEBUG]   -> categoryInteractionCounts.${e['categoryId']} += 1 (view)');
          }
          // Cuisine preference from viewing (2026-07-27) - low confidence,
          // same implicit weight (1, the inc() default) as the category
          // increment immediately above - see _categoryCartWeight's doc
          // comment for the full low/medium/highest scheme this completes.
          // cuisineIds comes from the vendor object already in memory at
          // both tracking call sites (ProductDetailsScreen.dart,
          // newVendorProductsScreen.dart) - no new Firestore read.
          for (final c in (e['cuisineIds'] as List?) ?? const []) {
            final cuisineId = c.toString();
            if (cuisineId.isEmpty) continue;
            inc('cuisineInteractionCounts', cuisineId);
            debugPrint('[CATCUISINE-DEBUG]   -> cuisineInteractionCounts.$cuisineId += 1 (view)');
          }
          escalateSearchConfidence(
              'searchConfidenceViewed', (e['vendorId'] ?? '').toString()); // tier 3 of 5, 60%
          break;
        case kEvtProductAddedToCart:
          escalateSearchConfidence(
              'searchConfidenceCarted', (e['vendorId'] ?? '').toString());
          // Veg/Non-Veg preference signal (2026-07-25, collection +
          // recommendation-input) - isVeg/isNonVeg are only present on
          // events fired after this date (older queued/replayed events
          // simply have neither key, so both checks below are false and
          // this is a clean no-op for them). See
          // BehaviorSummarySnapshot.dietaryPreference for how these two
          // scalars turn into a preference classification.
          if (e['isVeg'] == true) incScalar('vegCartAddCount');
          if (e['isNonVeg'] == true) incScalar('nonVegCartAddCount');
          // Category/Cuisine preference from cart-add (2026-07-27) - a
          // cart-add is real intent, weighted between a view (1x) and an
          // order (3x) - see _categoryCartWeight's own doc comment. Flat
          // per-category/per-cuisine, not quantity-scaled, same reasoning
          // as the order-completion weighting below: this learns "likes
          // Biryani"/"likes Italian", not "bought 5 of it". cuisineIds
          // comes from the vendor object already in memory at both
          // tracking call sites (ProductDetailsScreen.dart,
          // newVendorProductsScreen.dart) - no new Firestore read.
          if (e['categoryId'] != null &&
              e['categoryId'].toString().isNotEmpty) {
            inc('categoryInteractionCounts', e['categoryId'].toString(),
                by: _categoryCartWeight);
            debugPrint('[CATCUISINE-DEBUG]   -> categoryInteractionCounts.${e['categoryId']} '
                '+= $_categoryCartWeight (cart-add)');
          }
          for (final c in (e['cuisineIds'] as List?) ?? const []) {
            final cuisineId = c.toString();
            if (cuisineId.isEmpty) continue;
            inc('cuisineInteractionCounts', cuisineId, by: _categoryCartWeight);
            debugPrint('[CATCUISINE-DEBUG]   -> cuisineInteractionCounts.$cuisineId '
                '+= $_categoryCartWeight (cart-add)');
          }
          break;
        // Cart abandonment analytics (2026-07-21, collection-only) - both
        // events already fired unconditionally from CartScreen.dart with
        // productId/vendorId in their payload; they simply had no case
        // here before. Counts every removal/decrement, not just a final
        // "cart emptied" - a coarser but zero-extra-tracking-call signal
        // of "customer had this in their cart, then backed off it".
        case kEvtProductRemovedFromCart:
        case kEvtProductQuantityChanged:
          if (type == kEvtProductQuantityChanged && e['direction'] != 'dec') break;
          inc('cartAbandonProductCounts', (e['productId'] ?? '').toString());
          inc('cartAbandonRestaurantCounts', (e['vendorId'] ?? '').toString());
          break;
        case kEvtProductOrdered:
          final qty = (e['quantity'] as num?) ?? 1;
          inc('productOrderQuantities', (e['productId'] ?? '').toString(), by: qty);
          // searchConfidenceOrdered moved to kEvtOrderCompleted (2026-07-22)
          // - see that case's own comment for why.
          break;
        // Combo Purchase Learning (2026-07-19, revised 2026-07-24) - fired
        // ADDITIONALLY alongside kEvtProductOrdered above (never instead
        // of), only when that line item was a combo. comboOrderCount/
        // comboPriceTotal/comboChildCountTotal are running sums -
        // BehaviorSummarySnapshot derives the averages (avgComboPrice/
        // avgComboSize) at read time, same pattern as avgOrderValue below,
        // so no read-before-write is ever needed here. comboChildProductCounts
        // is "how often has THIS product arrived inside an ordered combo" -
        // a distinct signal from productOrderQuantities (that product
        // ordered on its own) - RecommendationEngine.comboEligibilityScore
        // already reads BOTH this map and avgComboSize (a real, live
        // consumer - do not stop feeding these without checking there
        // first). Explicitly NOT "3 burgers inside one combo" scaling: the
        // increment below is weighted by comboQty (how many COMBO UNITS
        // this order contains), never by a child's own serving-quantity
        // within the combo - that per-child quantity is never even
        // captured (see rememberComboMetadata's own doc comment) - and
        // comboProductIds arrives here already deduped to distinct
        // productIds (same method), so one combo order can never increment
        // the same child twice. A combo shared across a Dine-In table
        // still only counts as one chosen bundle, exactly like
        // comboOrderCount counts one combo order regardless of how many
        // people ate from it.
        case kEvtComboOrdered:
          final comboQty = (e['quantity'] as num?) ?? 1;
          incScalar('comboOrderCount', by: comboQty);
          incScalar('comboPriceTotal',
              by: (double.tryParse((e['price'] ?? '0').toString()) ?? 0) * comboQty);
          final childIds = ((e['comboProductIds'] as List?) ?? const [])
              .map((c) => c.toString())
              .where((c) => c.isNotEmpty)
              .toList();
          incScalar('comboChildCountTotal', by: childIds.length * comboQty);
          for (final childId in childIds) {
            inc('comboChildProductCounts', childId, by: comboQty);
          }
          // Combo category signal (2026-07-24, additive) - strengthens
          // categoryInteractionCounts for whatever categories the vendor
          // tagged this combo as spanning (ProductModel.comboCategoryIds -
          // "empty on every real combo today" per that field's own doc
          // comment, so this is a no-op until vendors start tagging
          // combos; NOT derived from each child's own category, which
          // would need a catalog read this class deliberately avoids).
          // Uses _categoryOrderWeight, same weight an ordinary product's
          // order-time category bump gets - a combo purchase is just as
          // strong a signal of category interest as a non-combo one.
          final comboCategoryIds = ((e['comboCategoryIds'] as List?) ?? const [])
              .map((c) => c.toString())
              .where((c) => c.isNotEmpty)
              .toSet();
          for (final catId in comboCategoryIds) {
            inc('categoryInteractionCounts', catId, by: _categoryOrderWeight * comboQty);
            debugPrint('[CATCUISINE-DEBUG]   -> categoryInteractionCounts.$catId '
                '+= ${_categoryOrderWeight * comboQty} (combo_ordered)');
          }
          break;
        case kEvtOrderCompleted:
          incScalar('orderCount');
          incScalar('totalOrderAmount', by: (e['amount'] as num?) ?? 0);
          inc('paymentMethodCounts', (e['paymentMethod'] ?? 'unknown').toString());
          inc('orderModeCounts', (e['orderMode'] ?? 'unknown').toString());
          if ((e['couponCode'] ?? '').toString().isNotEmpty) {
            incScalar('couponUsageCount');
          }
          if (e['hasSpecialDiscount'] == true) {
            incScalar('specialDiscountUsageCount');
          }
          final vendorId = (e['vendorId'] ?? '').toString();
          // searchQuery (2026-07-22) - captured at order-CREATION time now,
          // not re-checked here at completion time. See
          // recentSearchQueryFor's own doc comment for why. Drives BOTH
          // searchToOrderCount and searchConfidenceOrdered (tier 5 of 5,
          // 100% - moved here from kEvtProductOrdered, since this is a
          // per-ORDER/per-vendor signal, not a per-line-item one; firing
          // it once per order instead of once per line item is also more
          // correct, not just simpler).
          final searchQuery = (e['searchQuery'] ?? '').toString();
          if (searchQuery.isNotEmpty) {
            incScalar('searchToOrderCount');
            inc('searchConfidenceOrdered', searchQuery);
          }
          // Restaurant co-occurrence's own future data source (2026-07-21) -
          // which vendors this customer ordered from THIS month, a plain
          // per-event tally with no switch-detection needed (unlike
          // vendorSwitchCount above, which does).
          if (vendorId.isNotEmpty) {
            inc('distinctVendorsOrderedFrom', vendorId);
          }
          // Time-of-day / day-of-week ordering habits (2026-07-21) - purely
          // a function of this event's own timestamp, no local state or
          // switch-detection needed, unlike vendorSwitchCount/transition
          // counters above.
          final orderedAt = DateTime.tryParse(e['timestamp'] as String? ?? '');
          if (orderedAt != null) {
            inc('hourBucketCounts', orderedAt.hour.toString());
            inc('dayOfWeekCounts', orderedAt.weekday.toString()); // 1=Mon..7=Sun
          }
          // Category preference (2026-07-22, revised same day - moved here
          // from kEvtProductOrdered) - orders feed the SAME
          // categoryInteractionCounts kEvtProductViewed already writes to
          // (no new field), via _categoryOrderWeight above so purchase
          // intent outweighs browsing. Deliberately NOT quantity-scaled
          // and NOT per-line-item: this learns "the customer likes
          // Biryani", not "the customer likes Biryani 5x more because
          // they ordered 5 of it". e['categoryIds'] is ALREADY the unique
          // category set for this whole order, deduplicated at the source
          // (PaymentScreen.dart, before anything was queued) rather than
          // here at flush time - kEvtOrderCompleted fires exactly once per
          // order, one atomic queue-add, so there is no sequence of
          // per-line-item events a flush boundary could ever split - this
          // is structurally immune to the flush-timing edge case, not just
          // unlikely to hit it.
          final orderCategoryIds = ((e['categoryIds'] as List?) ?? const [])
              .map((c) => c.toString())
              .where((c) => c.isNotEmpty)
              .toSet(); // defensive re-dedupe; source already sends a Set
          for (final catId in orderCategoryIds) {
            inc('categoryInteractionCounts', catId, by: _categoryOrderWeight);
            debugPrint('[CATCUISINE-DEBUG]   -> categoryInteractionCounts.$catId '
                '+= $_categoryOrderWeight (order_completed)');
          }
          // Cuisine preference from order completion (2026-07-27) - same
          // weighting/reasoning as categoryInteractionCounts immediately
          // above (highest confidence, flat per-cuisine, not quantity-
          // scaled). e['cuisineIds'] is already on this event's payload
          // (PaymentScreen.dart's analyticsSnapshot -> purchase_completion_
          // listener.dart, unchanged by this) - previously computed but
          // never read for cuisine learning here.
          final orderCuisineIds = ((e['cuisineIds'] as List?) ?? const [])
              .map((c) => c.toString())
              .where((c) => c.isNotEmpty)
              .toSet();
          for (final cuisineId in orderCuisineIds) {
            inc('cuisineInteractionCounts', cuisineId, by: _categoryOrderWeight);
            debugPrint('[CATCUISINE-DEBUG]   -> cuisineInteractionCounts.$cuisineId '
                '+= $_categoryOrderWeight (order_completed)');
          }
          // Search-conversion funnel, "ordered" step (2026-07-24, additive
          // field only - see the entrySource field's own comment on this
          // event's payload in purchase_completion_listener.dart). Only
          // the final funnel step lives here; restaurantOpened/
          // productViewed/addedToCart/abandoned are derived from
          // kEvtRestaurantSessionEnded below, since that's where those
          // counts are actually known.
          final orderEntrySource = (e['entrySource'] ?? '').toString();
          if (orderEntrySource == 'Search' || orderEntrySource == 'Cuisine') {
            incScalar('searchConversion.ordered');
          }
          break;
        case kEvtRestaurantSessionEnded:
          // Search-conversion funnel, all other steps (2026-07-24,
          // additive-only new field names - does not touch any existing
          // field this event already feeds via _addRestaurantEngagementWrites,
          // which is a separate consumer of this same event). Only counts
          // visits actually attributed to a search/cuisine tap (see
          // SearchScreen.dart's tier != null guard) - a Home/Story/Banner/
          // Direct visit contributes nothing here.
          final sessionEntrySource = (e['entrySource'] ?? 'Direct').toString();
          if (sessionEntrySource == 'Search' || sessionEntrySource == 'Cuisine') {
            incScalar('searchConversion.restaurantOpened');
            final views = ((e['productViewCount'] as num?) ?? 0).toInt();
            final carts = ((e['addToCartCount'] as num?) ?? 0).toInt();
            if (views > 0) incScalar('searchConversion.productViewed');
            if (carts > 0) {
              incScalar('searchConversion.addedToCart');
            } else {
              // "Abandoned" here means the visit ended with nothing added
              // to cart - orderCompleted/orderPlaced aren't known yet at
              // session-end time (see the identical rationale in
              // NewVendorProductsScreen's _trackRestaurantSessionEnded),
              // so this is necessarily an approximation: a customer who
              // adds nothing to cart during the visit but places an order
              // later via a different route (e.g. reorder) would still
              // count as abandoned here AND ordered via the kEvtOrderCompleted
              // branch above - both can be true, and that's fine for a
              // funnel-shaped counter, not a strict partition.
              incScalar('searchConversion.abandoned');
            }
          }
          break;
        case kEvtOfferViewed:
          for (final id in (e['offerIds'] as List?) ?? const []) {
            inc('offerViewCounts', id.toString());
          }
          break;
        case kEvtOfferClicked:
          inc('offerClickCounts', (e['offerId'] ?? '').toString());
          break;
        case kEvtStoryViewed:
          incScalar('storyViewCount');
          if (e['vendorId'] != null) {
            inc('storyVendorEngagement', e['vendorId'].toString());
          }
          break;
        case kEvtStoryCompleted:
          incScalar('storyCompletedCount');
          break;
        case kEvtStorySkipped:
          incScalar('storySkippedCount');
          break;
        case kEvtStoryReplayed:
          incScalar('storyReplayedCount');
          break;
        case kEvtSearchPerformed:
          final query = (e['query'] as String?)?.trim().toLowerCase();
          if (query != null && query.isNotEmpty) {
            // Cap new distinct keywords per flush - only ever increment an
            // EXISTING key freely, but stop adding brand-new keys once the
            // cap is hit, so one-off queries can't grow this map unbounded.
            final alreadyTracked = updates.containsKey('topSearchKeywords.$query');
            if (alreadyTracked || newSearchKeywords < maxNewKeywordsPerFlush) {
              if (!alreadyTracked) newSearchKeywords++;
              inc('topSearchKeywords', query);
            }

            // Cross-Session Search Interest (2026-07-18): true day-level
            // tracking - "searched pizza on 25 different days" vs "searched
            // pizza 25 times in one evening" need to be distinguishable, so
            // topSearchKeywords' flat total isn't enough. Composite key
            // '{query}|{yyyy-MM-dd}' flattens the (keyword x day) pair into
            // ONE map (Firestore dot-paths don't nest cleanly two levels
            // deep via FieldValue.increment), using the EVENT's own
            // timestamp (not flush time - an offline-queued event might
            // flush hours or days after it actually happened) so the day
            // recorded is the day the search actually happened. Only
            // aggregated presence counters are kept - never raw search
            // history, never a list of what was searched.
            final eventDay = _dayKeyFrom(e['timestamp'] as String?);
            if (eventDay != null) {
              final dayCompositeKey = '$query|$eventDay';
              final alreadyTrackedDay =
                  updates.containsKey('searchDayHits.$dayCompositeKey');
              if (alreadyTrackedDay ||
                  newSearchDayKeys < maxNewSearchDayKeysPerFlush) {
                if (!alreadyTrackedDay) newSearchDayKeys++;
                inc('searchDayHits', dayCompositeKey);
              }
            }
          }

          // Search → Category Learning (2026-07-22) - feeds the SAME
          // categoryInteractionCounts field product views/completed orders
          // already write to (no new field, no new collection). Weighted
          // like a view (default +1 via inc()), not like a completed order -
          // a search match is browsing-strength evidence. SearchScreen
          // already deduplicates matched categories per query before this
          // ever fires (both by category name - "Coffee"/"Biryani" - and by
          // matched product name - "Mango Juice" -> Juice), so this loop
          // increments each category exactly once per search regardless of
          // how many products in that category matched.
          final searchCategoryIds = ((e['categoryIds'] as List?) ?? const [])
              .map((c) => c.toString())
              .where((c) => c.isNotEmpty)
              .toSet();
          for (final catId in searchCategoryIds) {
            inc('categoryInteractionCounts', catId);
            debugPrint('[CATCUISINE-DEBUG]   -> categoryInteractionCounts.$catId += 1 (search)');
          }
          // Search → Cuisine Learning (2026-07-27) - same weight (default
          // +1, "low confidence") as the category increment immediately
          // above. e['cuisineIds'] comes from SearchScreen's own Cuisine
          // Name match tier plus dish-name-matched vendors - see
          // SearchScreen._runSearch's doc comment for exactly how.
          final searchCuisineIds = ((e['cuisineIds'] as List?) ?? const [])
              .map((c) => c.toString())
              .where((c) => c.isNotEmpty)
              .toSet();
          for (final cuisineId in searchCuisineIds) {
            inc('cuisineInteractionCounts', cuisineId);
            debugPrint('[CATCUISINE-DEBUG]   -> cuisineInteractionCounts.$cuisineId += 1 (search)');
          }
          break;
        case kEvtNavOrderModeSwitched:
          incScalar('orderModeSwitchCount');
          break;
      }
    }

    if (favoriteIds.isNotEmpty) {
      updates['favoriteRestaurantIds'] = FieldValue.arrayUnion(favoriteIds.toList());
    }

    // Derived scalar snapshots - accurate for the whole month (not just this
    // batch) because they're computed from the local running totals kept in
    // _recordOrderInLocalMonthlyTotals, not from this batch alone.
    final monthlyTotals = await _loadMonthlyTotals();
    final orderCount = (monthlyTotals['orderCount'] as num?) ?? 0;
    if (orderCount > 0) {
      updates['avgOrderValue'] =
          ((monthlyTotals['totalOrderAmount'] as num?) ?? 0) / orderCount;
    }
    // Customer budget profile - raw spread, snapshot-written the same way
    // avgOrderValue is above.
    final minOrderAmount = monthlyTotals['minOrderAmount'] as num?;
    if (minOrderAmount != null) updates['minOrderAmount'] = minOrderAmount;
    final maxOrderAmount = monthlyTotals['maxOrderAmount'] as num?;
    if (maxOrderAmount != null) updates['maxOrderAmount'] = maxOrderAmount;
    final preferredPayment =
        _argmax(Map<String, dynamic>.from(monthlyTotals['paymentMethodCounts'] ?? {}));
    if (preferredPayment != null) updates['preferredPaymentMethod'] = preferredPayment;
    final preferredMode =
        _argmax(Map<String, dynamic>.from(monthlyTotals['orderModeCounts'] ?? {}));
    if (preferredMode != null) updates['preferredOrderMode'] = preferredMode;

    // Restaurant-switching / category+cuisine-transition snapshots
    // (2026-07-21) - same pattern as avgOrderValue above: local running
    // state, snapshot-written (not FieldValue.increment) since the
    // detection itself already happened locally in
    // _recordOrderInLocalMonthlyTotals, not from this batch alone.
    final vendorSwitchCount = (monthlyTotals['vendorSwitchCount'] as num?) ?? 0;
    if (vendorSwitchCount > 0) updates['vendorSwitchCount'] = vendorSwitchCount;
    final categoryTransitions =
        Map<String, dynamic>.from(monthlyTotals['categoryTransitionCounts'] ?? {});
    if (categoryTransitions.isNotEmpty) {
      updates['categoryTransitionCounts'] = categoryTransitions;
    }
    final cuisineTransitions =
        Map<String, dynamic>.from(monthlyTotals['cuisineTransitionCounts'] ?? {});
    if (cuisineTransitions.isNotEmpty) {
      updates['cuisineTransitionCounts'] = cuisineTransitions;
    }
    // lastOrdered*Id themselves are lifetime state (see
    // _lastOrderContextPrefsKey), not monthly, but still just a snapshot
    // write here like everything else in this block.
    final lastContext = await _loadLastOrderContext();
    final lastVendorId = (lastContext['lastVendorId'] as String?) ?? '';
    if (lastVendorId.isNotEmpty) updates['lastOrderedVendorId'] = lastVendorId;
    final lastCategoryId = (lastContext['lastCategoryId'] as String?) ?? '';
    if (lastCategoryId.isNotEmpty) updates['lastOrderedCategoryId'] = lastCategoryId;
    final lastCuisineId = (lastContext['lastCuisineId'] as String?) ?? '';
    if (lastCuisineId.isNotEmpty) updates['lastOrderedCuisineId'] = lastCuisineId;

    // TEMPORARY diagnostic instrumentation (2026-07-27) - see this
    // function's top-of-loop comment. This IS the exact payload the
    // caller's WriteBatch.set(..., merge:true) sends to Firestore -
    // logged here, immediately before return, so there is no gap between
    // "what this function decided" and "what actually gets written".
    // FieldValue.increment/arrayUnion sentinels print as their own
    // toString(), not a plain number - that's expected, not a bug in this
    // log.
    final categoryCuisineUpdates = Map.fromEntries(updates.entries.where((entry) =>
        entry.key.startsWith('categoryInteractionCounts.') ||
        entry.key.startsWith('cuisineInteractionCounts.')));
    debugPrint('[CATCUISINE-DEBUG] final category/cuisine keys in this flush\'s '
        'Firestore update payload: $categoryCuisineUpdates');
    debugPrint('[CATCUISINE-DEBUG] FULL update payload (all fields, this flush): $updates');

    return updates;
  }

  // Deletes behavior_summary docs older than the trailing 3 months - gated
  // by a locally-persisted flag so this only ever runs (and only ever
  // issues a query) once per real calendar-month change, never on every
  // flush.
  static Future<void> _pruneOldSummariesIfNeeded(
      DocumentReference userRef, String currentYearMonth) async {
    final prefs = await SharedPreferences.getInstance();
    final lastPruned = prefs.getString(_lastPrunedMonthPrefsKey);
    if (lastPruned == currentYearMonth) return;

    try {
      final now = DateTime.now();
      final keep = <String>{};
      // Retention extended 3 -> 12 months (2026-07-18) for Cross-Session
      // Search Interest / long-term preference signals - must stay in sync
      // with FirebaseHelper._loadBehaviorSummary's own fetch window.
      for (int i = 0; i < kBehaviorSummaryRetentionMonths; i++) {
        final d = DateTime(now.year, now.month - i, 1);
        keep.add('${d.year}-${d.month.toString().padLeft(2, '0')}');
      }
      // 2026-09-19: was a raw .get(), invisible to FirestoreReadStats - this
      // is rate-limited to once/user/month already, but still a real,
      // unlogged read of up to kBehaviorSummaryRetentionMonths documents.
      final existing = await userRef
          .collection('behavior_summary')
          .getLogged('BehaviorTracker:pruneOldSummaries');
      for (final doc in existing.docs) {
        if (!keep.contains(doc.id)) {
          await doc.reference.delete();
        }
      }
      await prefs.setString(_lastPrunedMonthPrefsKey, currentYearMonth);
    } catch (_) {
      // Non-critical housekeeping - retried next month-change if it fails.
    }
  }
}

class _RecentSearchHit {
  final String vendorId;
  final String query;
  final DateTime at;
  _RecentSearchHit(this.vendorId, this.query, this.at);
}

class _ComboMetadata {
  final List<String> comboProductIds;
  final List<String> comboCategoryIds;
  final String price;
  final DateTime at;
  _ComboMetadata({
    required this.comboProductIds,
    required this.comboCategoryIds,
    required this.price,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'comboProductIds': comboProductIds,
        'comboCategoryIds': comboCategoryIds,
        'price': price,
        'at': at.toIso8601String(),
      };

  static _ComboMetadata fromJson(Map<String, dynamic> j) => _ComboMetadata(
        comboProductIds: ((j['comboProductIds'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        comboCategoryIds: ((j['comboCategoryIds'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        price: (j['price'] ?? '0').toString(),
        at: DateTime.tryParse((j['at'] ?? '').toString()) ?? DateTime.now(),
      );
}

class _LiveRestaurantSessionCounters {
  int productViewCount = 0;
  int addToCartCount = 0;
  final Set<String> categoriesBrowsed = {};
}

class _RecentRestaurantSession {
  final String vendorId;
  final String sessionId;
  final String entrySource;
  final String searchKeyword;
  final String searchType;
  final DateTime at;
  _RecentRestaurantSession({
    required this.vendorId,
    required this.sessionId,
    required this.entrySource,
    required this.searchKeyword,
    required this.searchType,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'vendorId': vendorId,
        'sessionId': sessionId,
        'entrySource': entrySource,
        'searchKeyword': searchKeyword,
        'searchType': searchType,
        'at': at.toIso8601String(),
      };

  static _RecentRestaurantSession fromJson(Map<String, dynamic> j) =>
      _RecentRestaurantSession(
        vendorId: (j['vendorId'] ?? '').toString(),
        sessionId: (j['sessionId'] ?? '').toString(),
        entrySource: (j['entrySource'] ?? 'Direct').toString(),
        searchKeyword: (j['searchKeyword'] ?? '').toString(),
        searchType: (j['searchType'] ?? '').toString(),
        at: DateTime.tryParse((j['at'] ?? '').toString()) ?? DateTime.now(),
      );
}
