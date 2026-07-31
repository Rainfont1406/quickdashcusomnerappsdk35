import 'dart:math';

import 'package:emartconsumer/services/behavior/behavior_event_types.dart';

// Veg/Non-Veg preference classification (2026-07-25) - see
// BehaviorSummarySnapshot.dietaryPreference for the confidence rule.
// Deliberately only 3 states, no "leans veg"/"leans non-veg" middle
// ground - a soft lean isn't confident enough evidence to filter a
// customer's menu by (see mostLovedHere's own doc comment for why a
// filter, not a rank boost, is what this drives), so anything short of
// "exclusively added one type, several times" reports none.
enum DietaryPreference { none, vegOnly, nonVegOnly }

// Read-side counterpart to BehaviorTracker's write-only behavior_summary
// docs (lib/services/behavior/behavior_tracker.dart - see
// _computeSummaryUpdates() there for the exact field names/shape this
// merges). Pure data holder, no Firebase imports - constructed by
// FireStoreUtils._fetchBehaviorSummary from up to
// kBehaviorSummaryRetentionMonths (12, extended from 3 on 2026-07-18 for
// Cross-Session Search Interest) raw Firestore doc snapshots and handed to
// RecommendationEngine, which never touches Firestore itself.
class BehaviorSummarySnapshot {
  final Map<String, int> restaurantVisitCounts;
  final Map<String, int> cuisineInteractionCounts;
  final Map<String, int> categoryInteractionCounts;
  final Map<String, int> productViewCounts;
  final Map<String, int> productOrderQuantities;
  final Set<String> favoriteRestaurantIds;

  // Dynamic-engine price-compatibility signal - already written by
  // BehaviorTracker._computeSummaryUpdates (avgOrderValue/orderCount), just
  // not read back until it got a real consumer. avgOrderValue is a
  // per-ORDER average, not per-item - a coarse but honest proxy, never
  // claimed to be more precise than that (see
  // RecommendationEngine._priceCompatibility).
  final double avgOrderValue;
  final int orderCount;

  // Explorer Score feature (2026-07-17) - re-exposed after being
  // deliberately removed earlier for having no consumer. It has one now:
  // discoveryPreferenceScore's search-diversity term below. Still frequency-
  // only, not chronological (SearchScreen's own "Recent" section is a
  // separate, better, genuinely chronological local list and is untouched
  // by this).
  final Map<String, int> topSearchKeywords;

  // Search Confidence (2026-07-18) - one presence-flag map per escalation
  // tier reached (restaurant opened / product viewed / added to cart /
  // ordered, after being reached via that specific search query). The
  // "Typed Search" tier (10%) needs no field of its own - it's exactly
  // "this query is present in topSearchKeywords with no higher tier
  // reached", reusing data already tracked. See searchConfidenceFor below
  // for how these combine into "the highest confidence reached for query X".
  final Map<String, int> searchConfidenceOpened;
  final Map<String, int> searchConfidenceViewed;
  final Map<String, int> searchConfidenceCarted;
  final Map<String, int> searchConfidenceOrdered;

  // Cross-Session Search Interest (2026-07-18) - true day-level tracking.
  // Composite keys '{query}|{yyyy-MM-dd}', one entry per DISTINCT day a
  // query was searched (not per search - repeat searches the same day
  // just increment the same key). Only aggregated presence counters, never
  // raw search history. See distinctSearchDaysFor/lastSearchDateFor/
  // crossSessionSearchInterestFor below for how this is consumed.
  final Map<String, int> searchDayHits;

  // Combo Purchase Learning (2026-07-19) - written by BehaviorTracker's
  // kEvtComboOrdered handler whenever an ordered line item is a combo
  // product (fired alongside, never instead of, the normal
  // productOrderQuantities increment for that same product). Running sums,
  // not pre-divided - avgComboPrice/avgComboSize below derive the averages
  // at read time, same pattern as avgOrderValue/orderCount, so no
  // read-before-write is ever needed on the write side.
  final int comboOrderCount;
  final double comboPriceTotal;
  final int comboChildCountTotal;
  // "How often has THIS product arrived inside an ordered combo" - distinct
  // from productOrderQuantities (that product ordered on its own). Feeds
  // RecommendationEngine.comboEligibilityScore's cross-combo generalization
  // term: a customer who's never ordered THIS combo before, but has
  // repeatedly received one of its child products via a DIFFERENT combo,
  // still has real evidence behind them.
  final Map<String, int> comboChildProductCounts;

  // Veg/Non-Veg preference signal (2026-07-25) - plain running counts,
  // written by BehaviorTracker's kEvtProductAddedToCart case (see that
  // file). Cart-add-based, not order-based - ProductModel.veg/.nonveg
  // (the only place this flag lives) is only in scope at add-to-cart
  // time; see BehaviorTracker's own doc comment on that event for why an
  // order-level signal would need a CartProducts schema migration this
  // codebase deliberately avoids. See dietaryPreference below for how
  // these two scalars become a preference classification.
  final int vegCartAddCount;
  final int nonVegCartAddCount;

  const BehaviorSummarySnapshot({
    this.restaurantVisitCounts = const {},
    this.cuisineInteractionCounts = const {},
    this.categoryInteractionCounts = const {},
    this.productViewCounts = const {},
    this.productOrderQuantities = const {},
    this.favoriteRestaurantIds = const {},
    this.avgOrderValue = 0.0,
    this.orderCount = 0,
    this.topSearchKeywords = const {},
    this.searchConfidenceOpened = const {},
    this.searchConfidenceViewed = const {},
    this.searchConfidenceCarted = const {},
    this.searchConfidenceOrdered = const {},
    this.searchDayHits = const {},
    this.comboOrderCount = 0,
    this.comboPriceTotal = 0.0,
    this.comboChildCountTotal = 0,
    this.comboChildProductCounts = const {},
    this.vegCartAddCount = 0,
    this.nonVegCartAddCount = 0,
  });

  factory BehaviorSummarySnapshot.empty() => const BehaviorSummarySnapshot();

  /// Average price of combos this customer has actually ordered - 0 (no
  /// signal, not a penalty) until the first combo order. Same coarse-but-
  /// honest philosophy as avgOrderValue: a per-ORDER average, not claimed
  /// to be more precise than that.
  double get avgComboPrice => comboOrderCount > 0 ? comboPriceTotal / comboOrderCount : 0.0;

  /// Average number of distinct products per combo this customer has
  /// ordered - the "preferred meal size" signal. 0 until the first combo
  /// order.
  double get avgComboSize =>
      comboOrderCount > 0 ? comboChildCountTotal / comboOrderCount : 0.0;

  // Minimum same-type cart-adds before a preference is trusted at all -
  // one or two adds could be a one-off, a gift order, or someone else's
  // order placed from a shared device.
  static const int _dietaryPreferenceMinSamples = 3;

  /// Veg/Non-Veg preference, symmetric in both directions: vegOnly requires
  /// at least [_dietaryPreferenceMinSamples] veg cart-adds AND ZERO
  /// non-veg ones ever (not a ratio/majority) - the same "exclusively,
  /// every time" bar a real dietary restriction would show up as, not a
  /// fuzzy lean. nonVegOnly is the exact mirror. Anything else (mixed
  /// history, or not enough samples yet) reports `none`, which every
  /// caller must treat as "show today's unfiltered result" - see
  /// RecommendationEngine.mostLovedHere.
  DietaryPreference get dietaryPreference {
    if (vegCartAddCount >= _dietaryPreferenceMinSamples && nonVegCartAddCount == 0) {
      return DietaryPreference.vegOnly;
    }
    if (nonVegCartAddCount >= _dietaryPreferenceMinSamples && vegCartAddCount == 0) {
      return DietaryPreference.nonVegOnly;
    }
    return DietaryPreference.none;
  }

  bool get isEmpty =>
      restaurantVisitCounts.isEmpty &&
      cuisineInteractionCounts.isEmpty &&
      categoryInteractionCounts.isEmpty &&
      productViewCounts.isEmpty &&
      productOrderQuantities.isEmpty &&
      favoriteRestaurantIds.isEmpty &&
      orderCount == 0;

  static int _sum(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);

  // Confidence-weighted diversity ratio: distinctCount/totalCount is
  // naturally bounded 0..1 by construction, but noisy at low volume (one
  // product ordered once looks identical to "always explores" from a
  // single data point). Blends toward the neutral 0.5 default until
  // there's enough volume to trust the ratio - the same confidence-
  // dampening pattern used throughout RecommendationEngine (e.g. rating
  // confidence). totalCount <= 0 (no data at all) returns exactly 0.5.
  static double _diversityRatio(int distinctCount, int totalCount,
      {int minVolumeForConfidence = 10}) {
    if (totalCount <= 0) return 0.5;
    final confidence = (totalCount / minVolumeForConfidence).clamp(0.0, 1.0);
    final raw = (distinctCount / totalCount).clamp(0.0, 1.0);
    return confidence * raw + (1 - confidence) * 0.5;
  }

  /// Explorer Score - 0.0 (strongly prefers familiar products) to 1.0
  /// (frequently explores new products/restaurants), 0.5 = balanced.
  /// Computed entirely client-side from data already in this snapshot - no
  /// new tracking events, no new Firestore writes, no new Firestore reads
  /// (BehaviorTracker's write path only ever sees one flush-batch at a
  /// time and has no visibility into cumulative distinct-key counts
  /// without a read, which would violate Phase 1's "never reads its own
  /// writes back" design - computing this at read time, from the already-
  /// merged snapshot, is the only place distinct counts are actually
  /// available).
  ///
  /// Four sub-signals, each a confidence-weighted diversity ratio
  /// (distinct keys / total interactions - naturally 0..1, blends toward
  /// 0.5 when data is sparse):
  /// - Product exploration (35%): distinct products ordered / total units
  ///   ordered. Also stands in for "repeat behaviour" (a low ratio here
  ///   already means orders repeatedly contain the same products) -
  ///   deliberately not computed as a second, separate signal, since no
  ///   distinct-ORDER-count data exists anywhere (productOrderQuantities is
  ///   cumulative quantity, not order count - see
  ///   RECOMMENDATION_SYSTEM_ARCHITECTURE.html Section 15.4), so a true
  ///   order-level repeat signal would necessarily be computed from the
  ///   exact same inputs and would just double-count this one.
  /// - Restaurant exploration (30%): distinct restaurants visited / total visits.
  /// - Cuisine exploration (20%): distinct cuisines interacted with / total
  ///   cuisine interactions (cuisineInteractionCounts increments once per
  ///   cuisine on every restaurant visit, so this ratio behaves the same
  ///   way as the other two - concentrated in 1-2 cuisines vs. spread wide).
  /// - Search diversity (15%): distinct search terms / total searches.
  double get discoveryPreferenceScore {
    final productSignal =
        _diversityRatio(productOrderQuantities.length, _sum(productOrderQuantities));
    final restaurantSignal =
        _diversityRatio(restaurantVisitCounts.length, _sum(restaurantVisitCounts));
    final cuisineSignal =
        _diversityRatio(cuisineInteractionCounts.length, _sum(cuisineInteractionCounts));
    final searchSignal =
        _diversityRatio(topSearchKeywords.length, _sum(topSearchKeywords));
    return (productSignal * 0.35 +
            restaurantSignal * 0.30 +
            cuisineSignal * 0.20 +
            searchSignal * 0.15)
        .clamp(0.0, 1.0);
  }

  // Search Confidence tier values - Typed 10% / Opened 30% / Viewed 60% /
  // Carted 80% / Ordered 100%. Defined here (not in behavior_tracker.dart)
  // because the write side never needs the percentage values themselves -
  // it only ever increments a presence flag, structurally, per tier
  // reached; the % values are purely a read-time concern.
  static const double kSearchConfidenceTyped = 0.10;
  static const double kSearchConfidenceOpened = 0.30;
  static const double kSearchConfidenceViewed = 0.60;
  static const double kSearchConfidenceCarted = 0.80;
  static const double kSearchConfidenceOrdered = 1.00;

  /// The highest confidence tier reached for [query] (already normalized -
  /// trim + lowercase, matching how topSearchKeywords keys are stored).
  /// 0.0 if this query was never searched at all. "Do not discard
  /// unsuccessful searches" is satisfied by construction: a query that
  /// never escalates past being typed still returns 0.10, not 0 - it's a
  /// weak signal, not a discarded one.
  double searchConfidenceFor(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return 0.0;
    if ((searchConfidenceOrdered[q] ?? 0) > 0) return kSearchConfidenceOrdered;
    if ((searchConfidenceCarted[q] ?? 0) > 0) return kSearchConfidenceCarted;
    if ((searchConfidenceViewed[q] ?? 0) > 0) return kSearchConfidenceViewed;
    if ((searchConfidenceOpened[q] ?? 0) > 0) return kSearchConfidenceOpened;
    if ((topSearchKeywords[q] ?? 0) > 0) return kSearchConfidenceTyped;
    return 0.0;
  }

  // ── Cross-Session Search Interest (2026-07-18) ─────────────────────────

  /// How many DISTINCT calendar days [query] was searched on, across the
  /// full retained window (up to kBehaviorSummaryRetentionMonths). This is
  /// the whole point of day-level (not just count-level) tracking: 25
  /// searches in one evening is 1 distinct day; 25 searches spread across
  /// 25 different days is a genuinely different, stronger signal, and only
  /// the latter is what this returns.
  int distinctSearchDaysFor(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return 0;
    final prefix = '$q|';
    return searchDayHits.keys.where((k) => k.startsWith(prefix)).length;
  }

  /// The most recent calendar day [query] was searched on, or null if
  /// never searched. Parsed from the same composite keys
  /// distinctSearchDaysFor reads - no separate timestamp field needed.
  DateTime? lastSearchDateFor(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;
    final prefix = '$q|';
    DateTime? latest;
    for (final k in searchDayHits.keys) {
      if (!k.startsWith(prefix)) continue;
      final parts = k.substring(prefix.length).split('-');
      if (parts.length != 3) continue;
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y == null || m == null || d == null) continue;
      final date = DateTime(y, m, d);
      if (latest == null || date.isAfter(latest)) latest = date;
    }
    return latest;
  }

  // Distinct-days volume signal saturates around this many days - roughly
  // "searched about once a week for 6+ months", which is clearly a
  // long-term pattern rather than a coincidence. Tunable.
  static const int _crossSessionDayCeiling = 30;

  // Recency fully decays to 0 at exactly the retention boundary - a search
  // this old is about to be pruned anyway, so it should carry no weight by
  // the time it would be. Linear, not exponential: simple, predictable,
  // no extra curve-shape decision to justify without more specific guidance.
  static const int _crossSessionDecayDays = kBehaviorSummaryRetentionMonths * 30;

  /// 0.0..1.0 long-term interest in [query], combining how many DISTINCT
  /// DAYS it's been searched on (volume of sustained interest, 60%) with
  /// how far it's ever escalated via searchConfidenceFor (conversion
  /// quality - reusing that signal rather than building a parallel one,
  /// 40%), then decayed linearly by recency so a year-old search interest
  /// that hasn't recurred doesn't outweigh something searched last week.
  /// This is the RECOMMENDED entry point for ranking - searchConfidenceFor
  /// remains available as the narrower "this session's escalation" signal
  /// it always was, and is reused internally here, not replaced.
  double crossSessionSearchInterestFor(String query) {
    final days = distinctSearchDaysFor(query);
    if (days <= 0) return 0.0;

    final lastDate = lastSearchDateFor(query);
    final daysSinceLastSearch = lastDate == null
        ? _crossSessionDecayDays
        : DateTime.now().difference(lastDate).inDays;
    final recencyFactor =
        (1.0 - (daysSinceLastSearch / _crossSessionDecayDays)).clamp(0.0, 1.0);

    final daySignal =
        (log(1 + days) / log(1 + _crossSessionDayCeiling)).clamp(0.0, 1.0);
    final successSignal = searchConfidenceFor(query);

    final rawInterest = daySignal * 0.6 + successSignal * 0.4;
    return (rawInterest * recencyFactor).clamp(0.0, 1.0);
  }

  static Map<String, int> _mergeCounts(
      Iterable<Map<String, dynamic>> maps, String field) {
    final merged = <String, int>{};
    for (final m in maps) {
      final raw = m[field] as Map<String, dynamic>?;
      if (raw == null) continue;
      raw.forEach((k, v) {
        final n = (v as num?)?.toInt() ?? 0;
        merged[k] = (merged[k] ?? 0) + n;
      });
    }
    return merged;
  }

  /// Merges up to kBehaviorSummaryRetentionMonths (12) of raw
  /// behavior_summary doc data, matching BehaviorTracker's own rolling
  /// retention window, into one snapshot. [monthlyDocs] should be the raw
  /// `.data()` maps, oldest-or-newest order doesn't matter - every count
  /// signal here is a sum (searchDayHits' composite keys already encode
  /// their own date, so summing same-key values across months is correct
  /// - a day can only ever appear in one month's doc to begin with).
  factory BehaviorSummarySnapshot.merge(List<Map<String, dynamic>> monthlyDocs) {
    if (monthlyDocs.isEmpty) return BehaviorSummarySnapshot.empty();
    final favorites = <String>{};
    for (final doc in monthlyDocs) {
      final raw = doc['favoriteRestaurantIds'] as List<dynamic>?;
      if (raw == null) continue;
      favorites.addAll(raw.map((e) => e.toString()));
    }

    // Each monthly doc's avgOrderValue is that month's own average - a
    // naive average-of-averages would misweight a low-volume month equally
    // against a high-volume one, so merge weighted by that month's orderCount.
    int totalOrderCount = 0;
    double weightedOrderValueSum = 0;
    for (final doc in monthlyDocs) {
      final oc = (doc['orderCount'] as num?)?.toInt() ?? 0;
      final aov = (doc['avgOrderValue'] as num?)?.toDouble() ?? 0.0;
      totalOrderCount += oc;
      weightedOrderValueSum += aov * oc;
    }
    final mergedAvgOrderValue =
        totalOrderCount > 0 ? weightedOrderValueSum / totalOrderCount : 0.0;

    // Combo running sums (2026-07-19) - unlike avgOrderValue these are
    // written as plain FieldValue.increment scalars (never a per-month
    // average), so summing across months is correct as-is, no weighting needed.
    int totalComboOrderCount = 0;
    double totalComboPriceTotal = 0;
    int totalComboChildCountTotal = 0;
    // Veg/Non-Veg preference (2026-07-25) - same "plain increment scalar,
    // sum across months" shape as the combo totals above.
    int totalVegCartAddCount = 0;
    int totalNonVegCartAddCount = 0;
    for (final doc in monthlyDocs) {
      totalComboOrderCount += (doc['comboOrderCount'] as num?)?.toInt() ?? 0;
      totalComboPriceTotal += (doc['comboPriceTotal'] as num?)?.toDouble() ?? 0.0;
      totalComboChildCountTotal += (doc['comboChildCountTotal'] as num?)?.toInt() ?? 0;
      totalVegCartAddCount += (doc['vegCartAddCount'] as num?)?.toInt() ?? 0;
      totalNonVegCartAddCount += (doc['nonVegCartAddCount'] as num?)?.toInt() ?? 0;
    }

    return BehaviorSummarySnapshot(
      restaurantVisitCounts: _mergeCounts(monthlyDocs, 'restaurantVisitCounts'),
      cuisineInteractionCounts: _mergeCounts(monthlyDocs, 'cuisineInteractionCounts'),
      categoryInteractionCounts: _mergeCounts(monthlyDocs, 'categoryInteractionCounts'),
      productViewCounts: _mergeCounts(monthlyDocs, 'productViewCounts'),
      productOrderQuantities: _mergeCounts(monthlyDocs, 'productOrderQuantities'),
      favoriteRestaurantIds: favorites,
      avgOrderValue: mergedAvgOrderValue,
      orderCount: totalOrderCount,
      topSearchKeywords: _mergeCounts(monthlyDocs, 'topSearchKeywords'),
      searchConfidenceOpened: _mergeCounts(monthlyDocs, 'searchConfidenceOpened'),
      searchConfidenceViewed: _mergeCounts(monthlyDocs, 'searchConfidenceViewed'),
      searchConfidenceCarted: _mergeCounts(monthlyDocs, 'searchConfidenceCarted'),
      searchConfidenceOrdered: _mergeCounts(monthlyDocs, 'searchConfidenceOrdered'),
      searchDayHits: _mergeCounts(monthlyDocs, 'searchDayHits'),
      comboOrderCount: totalComboOrderCount,
      comboPriceTotal: totalComboPriceTotal,
      comboChildCountTotal: totalComboChildCountTotal,
      comboChildProductCounts: _mergeCounts(monthlyDocs, 'comboChildProductCounts'),
      vegCartAddCount: totalVegCartAddCount,
      nonVegCartAddCount: totalNonVegCartAddCount,
    );
  }
}
