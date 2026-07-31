import 'dart:math';

import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/recommendation/behavior_summary_snapshot.dart';
import 'package:emartconsumer/services/recommendation/recommendation_config.dart';

// Phase 2 Smart Discovery & Recommendation Engine - pure Dart, synchronous,
// deliberately WITHOUT any Firebase import. Every method here takes
// already-loaded data as arguments and returns a plain scored/ranked
// result - callers (FireStoreUtils / the UI) are responsible for fetching
// data first. This isolation is what makes the engine swappable: a future
// server-side scorer can replace this class wholesale without any UI change,
// as long as it's fed the same RestaurantRecommendationContext shape.
//
// ── Dynamic candidate-source architecture (2026-07-17 rewrite) ───────────
// Replaces the previous fixed-percentage blend (40/30/20/10 across
// preference/speciality/bestSeller/crossSell) with independent candidate
// sources that each propose 0..N products with their own score, merged by
// computeMergedScores() (noisy-OR, Section 2 below) rather than any
// reserved slot or percentage per source. Adding a 6th source (time of day,
// weather, festival specials, AI ranking, collaborative filtering) means
// writing one more `List<SourceCandidate> Function(ctx)` and registering it
// in `defaultSources`/`_baseSourceWeights` below - zero changes to the
// merge, dedupe, or diversity logic.
//
// ── Explorer Score (2026-07-17 addition) ──────────────────────────────────
// Learns not just WHAT a customer likes but HOW they behave - loyal
// (repeatedly orders the familiar) vs. explorer (regularly tries new
// restaurants/cuisines/products). Computed entirely client-side from data
// already in BehaviorSummarySnapshot (see its discoveryPreferenceScore
// getter) - no new tracking events, no new Firestore reads or writes.
// Adjusts sourceWeightsFor() continuously (never a fixed percentage or
// reserved slot) so loyal customers naturally lean on preference/similar
// and explorers naturally lean on mustTry/discovery - applied inside
// computeMergedScores, so every caller (Recommended For You, menu reorder,
// pairs-well-with fill) inherits the adjustment with zero extra plumbing.
//
// ── No fake product ratings (2026-07-17 finding) ──────────────────────────
// ProductModel.reviewsCount/reviewsSum do NOT represent real per-product
// ratings. Traced in OrderRatingScreen.dart: a customer rates an entire
// ORDER once, and that single rating gets written to only the FIRST
// product in the order's product list - every other product in that same
// order gets nothing. This is order-position-dependent data with zero
// relationship to actual per-product quality, and must never be used as a
// per-product signal. VendorModel.reviewsCount/reviewsSum (restaurant-
// level, confirmed structurally separate) IS legitimate - it accumulates
// from every real order rating for that vendor - and is used ONLY as a
// small, uniform, restaurant-wide boost (see restaurantQualityBoost),
// never displayed or stored as a product rating, never a per-product
// differentiator.
//
// Restaurant Must Try (renamed from "Speciality") is fully automatic - no
// vendor configuration anywhere in this file. Vendor Featured (briefly the
// one deliberate vendor-configured exception) was fully reverted; see
// RECOMMENDATION_SYSTEM_ARCHITECTURE.html for the complete history.
//
// ── Search Confidence / Cross-Session Search Interest (2026-07-18) ────────
// See _searchConfidenceBoost/_restaurantSearchConfidenceBoost below and
// BehaviorSummarySnapshot.crossSessionSearchInterestFor for the mechanism.
// Deliberately NOT wired into every surface the original spec's "Future
// Recommendation Usage" list named:
// - Explorer Score's search-diversity sub-signal (distinct KEYWORDS
//   searched, breadth of exploration) is a different question than Cross-
//   Session Search Interest (persistence of interest in ONE keyword over
//   time) - conflating them would blur what each one means, so Explorer
//   Score's formula is untouched.
// - Discovery (_sourceDiscovery) is about surfacing what a customer hasn't
//   tried yet; Cross-Session Search Interest reinforces existing,
//   recurring interest - the two pull in different directions by design,
//   so Discovery is untouched.
// - Seasonal Preference remains fully deferred (Section 18/architecture
//   doc) - no schema, no logic, unaffected by this addition.
//
// ── Cold start, confidence bar, small-menu gating (2026-07-18) ────────────
// - hasSufficientRestaurantConfidence: a total rolling-90-day (3-month) sales floor
//   (minimumRestaurantConfidenceOrders) gates every restaurant-popularity
//   signal (bestSeller/mustTry/hiddenGem/discovery's never-interacted
//   term) so one or two early sales can't look like a trend. similar
//   (vendor-configured cross-sell) and preference (customer-level) are
//   deliberately left ungated - neither is a popularity claim. In a
//   complete cold start (new customer AND new/low-volume restaurant) every
//   source naturally returns nothing and recommendForYou returns [] - no
//   special-case code, no random filler (the old day-seeded Discovery
//   fallback was removed for exactly this reason - "must not generate fake
//   recommendations" means an empty source should mean "nothing to show",
//   not "show something anyway").
// - _sourceNewProduct: a 6th candidate source, small weight, deliberately
//   ungated by restaurant confidence (freshness is a fact, not a
//   popularity claim) - consumes ProductModel.createdAt, which is optional
//   and never backfilled/faked, so this is a genuine no-op today and only
//   starts mattering as real timestamps accumulate.
// - recommendationConfidenceScores: the green "recommendation confidence"
//   bar shown on every product card - reuses computeMergedScores as the
//   score, and picks ONE small customer-facing label from whichever real
//   signal dominates (see that function's own doc comment for the full
//   mapping/eligibility rules). Hidden entirely below
//   minimumRecommendationConfidence - never shows a faint/weak bar.
// - hasEnoughProductsForSections: menus under 10 products hide all 5
//   recommendation sections (customers can already see the whole menu at a
//   glance) - Pairs Well With is explicitly exempt, unaffected by this or
//   any other gate above.
// - exploreMenuSelection/shouldShowExploreMenuFallback (correction,
//   2026-07-18): the gap between "menu big enough for a section" and
//   "restaurant has enough sales history for a real signal" previously
//   just meant every section stayed empty - technically correct (no fake
//   data) but a poor experience for a growing restaurant. "✨ Explore the
//   Menu" fills exactly that gap: one product per category, in menu order,
//   ZERO scoring, ZERO popularity/personalization claim - shown INSTEAD OF
//   (never alongside) Recommended For You/Restaurant Must Try/Most Loved
//   Here/Hidden Gems, and automatically stops the instant
//   hasSufficientRestaurantConfidence(ctx) becomes true.
// - _normalizeConfidence: the boost+clamp step recommendForYou and
//   recommendationConfidenceScores both go through last, extracted into
//   one function specifically so "a displayed confidence can never exceed
//   100%" stays a guaranteed invariant as more candidate sources get added
//   later, not an incidental fact about today's formulas.
class SourceCandidate {
  final String productId;
  final double score; // 0..1, source-local scale; only >0 entries are ever returned
  const SourceCandidate(this.productId, this.score);
}

typedef CandidateSource = List<SourceCandidate> Function(
    RestaurantRecommendationContext ctx);

/// One Restaurant Type's Business Context profile - which Product Category
/// IDs (ProductModel.categoryID) represent that business, tiered. Plain
/// data, no scoring logic - see RecommendationEngine's Business Context
/// section for how these tiers are used. Admin-managed (2026-07-19): this
/// used to be hardcoded in a now-deleted business_context_config.dart;
/// instances are now parsed from the `business_context_type_profiles`
/// Firestore collection by FirebaseHelper.getBusinessContext and cached -
/// the engine itself never reads Firestore.
class RestaurantTypeCategoryProfile {
  final Set<String> primaryCategoryIds;
  final Set<String> secondaryCategoryIds;
  final Set<String> lowPriorityCategoryIds;
  const RestaurantTypeCategoryProfile({
    this.primaryCategoryIds = const {},
    this.secondaryCategoryIds = const {},
    this.lowPriorityCategoryIds = const {},
  });
}

class RestaurantRecommendationContext {
  final VendorModel vendor;
  final List<ProductModel> allProducts;
  final BehaviorSummarySnapshot behaviorSummary;
  final Map<String, int> rolling90DaySales;
  final Map<String, int> rolling7DaySales;
  final Map<String, int> crossSellFrequency;

  // Distinct-order counters (2026-07-23, Trending/Popular Choice confidence
  // rework) - DIFFERENT from rolling90DaySales/rolling7DaySales above,
  // which are quantity-sold sums used for RANKING (unchanged by this
  // change). These count DISTINCT ORDERS instead of units, and are used
  // ONLY for the confidence bar's fill value, computed after badge winners
  // are already decided - see _dynamicRoleAwareBadges. Default to
  // {}/0 so a context built without them (e.g. an existing test fixture)
  // degrades to "0% confidence", never an error - matches the pattern of
  // every other optional context field on this class.
  final Map<String, int> productOrders90;
  final Map<String, int> productOrders7;
  final int totalOrders90;
  final int totalOrders7;

  // Business Context (2026-07-19, admin-managed) - businessTypeId ->
  // profile, and cuisineId -> the category IDs that cuisine favors. Fetched
  // once and TTL-cached by FirebaseHelper.getBusinessContext (see that
  // method's own doc comment for the caching strategy), passed in here
  // already-resolved - matches every other field on this context ("already-
  // loaded data as arguments", per this file's own header). Both default
  // to {} so a context built without them (e.g. in a future test) degrades
  // exactly like "no business-context evidence yet", never an error.
  final Map<String, RestaurantTypeCategoryProfile> businessTypeProfiles;
  final Map<String, Set<String>> cuisineCategoryAffinity;

  const RestaurantRecommendationContext({
    required this.vendor,
    required this.allProducts,
    required this.behaviorSummary,
    required this.rolling90DaySales,
    required this.rolling7DaySales,
    required this.crossSellFrequency,
    this.productOrders90 = const {},
    this.productOrders7 = const {},
    this.totalOrders90 = 0,
    this.totalOrders7 = 0,
    this.businessTypeProfiles = const {},
    this.cuisineCategoryAffinity = const {},
  });
}

class _PreferenceRawMaps {
  final Map<String, int> behaviorRaw;
  final int maxBehavior;
  final Map<String, int> categoryRaw;
  final int maxCategory;
  const _PreferenceRawMaps({
    required this.behaviorRaw,
    required this.maxBehavior,
    required this.categoryRaw,
    required this.maxCategory,
  });
}

/// Customer-facing recommendation labels shown alongside the confidence bar
/// (see RecommendationEngine.recommendationConfidenceScores). Deliberately
/// small (7 values) - "Restaurant Specialities is fully automatic, no human
/// curator, so no 'Chef's Choice'" and "customers think about foods they
/// enjoy, not restaurants or cuisines by name" (2026-07-18 product
/// direction) means several internal signals share ONE customer-facing
/// label rather than each getting its own - see recommendationConfidenceScores'
/// doc comment for exactly which signals map to which label.
///
/// fitsYourBudget (2026-07-20, revised same day): can no longer be the
/// DISPLAYED label - on a menu with a narrow price range it was winning
/// against almost every other signal near-universally, since most dishes
/// end up "close enough" in price-tier to the customer's own tier (see
/// _priceCompatibility's doc comment). First attempt just hid the whole
/// badge whenever this label won (RecommendationConfidenceBadge's UI),
/// which threw away a real, valid score just because of which label it
/// carried. Now excluded directly from the label vote in
/// recommendationConfidenceScores, so the next-highest real signal becomes
/// the label instead and the badge still renders. _priceCompatibility
/// itself is untouched and still feeds the actual SCORE via
/// _tasteProfileScore - only its ability to win the label is gone. The
/// enum value stays (still referenced by the widget's label-text map) in
/// case a future milestone wants to surface it differently.
enum RecommendationLabel {
  mostOrdered,
  matchesYourTaste,
  basedOnSearches,
  fitsYourBudget,
  worthTrying,
  hiddenGem,
  popularChoice,
}

class ProductRecommendationConfidence {
  final double score; // 0..1, drives the bar's fill level
  final RecommendationLabel label;
  const ProductRecommendationConfidence(this.score, this.label);
}

/// Business-Context-derived badge role - see RecommendationEngine's
/// "DYNAMIC ROLE-AWARE BADGE ALLOCATION" section for how products are
/// split into these two groups.
enum ProductBadgeRole { main, side }

class RecommendationEngine {
  RecommendationEngine._();

  // ── Shared normalization helpers ────────────────────────────────────────

  static double _log1pScaled(int raw, int maxRaw) {
    if (raw <= 0 || maxRaw <= 0) return 0.0;
    return log(1 + raw) / log(1 + maxRaw);
  }

  static double _linearScaled(int raw, int maxRaw) {
    if (raw <= 0 || maxRaw <= 0) return 0.0;
    return raw / maxRaw;
  }

  /// Tallies how often each product id appears across every OTHER product's
  /// own vendor-configured recommendedProductIds within this one menu - the
  /// "Vendor Cross-Selling Frequency" signal. Zero new Firestore reads: the
  /// menu is already loaded by the caller. Reused by both the "Similar/
  /// Complementary" source below and the pre-existing "Pairs Well With"
  /// panel (fillPairsWellWith) - this function itself is unchanged.
  static Map<String, int> computeCrossSellFrequency(List<ProductModel> allProducts) {
    final freq = <String, int>{};
    for (final product in allProducts) {
      for (final id in product.recommendedProductIds) {
        freq[id] = (freq[id] ?? 0) + 1;
      }
    }
    return freq;
  }

  // ── Recommendation count (2026-07-18 addition) ──────────────────────────
  //
  // Single source of truth for "how many products does one recommendation
  // surface show" - every section above the menu (Recommended For You,
  // Restaurant Must Try, Explore the Menu, Hidden Gems, and now Most Loved
  // Here) AND the Add+ "Pairs Well With" popup all default to this same
  // number, so the recommendation experience is predictable across the
  // whole app rather than each surface picking its own count. Before this,
  // every call site independently passed a literal 5 (or, for Most Loved
  // Here specifically, an inconsistent literal 10 - a stray leftover with
  // no UX rationale behind it, fixed to match everything else here).
  static const int defaultSectionLimit = 5;

  // ── Dynamic section sizing (2026-07-19 addition) ────────────────────────
  //
  // defaultSectionLimit above stays as the flat fallback (Restaurant Must
  // Try / Most Loved Here - unchanged, not in scope for this table). This
  // table instead scales Recommended For You / Explore the Menu / Pairs
  // Well With to the restaurant's own active menu size - a 8-item cafe and
  // a 250-item multi-cuisine restaurant shouldn't both show a fixed 5.
  // O(1): a handful of comparisons against a count callers already have on
  // hand (ctx.allProducts.length - no new Firestore read, no extra pass
  // over the menu).
  //
  // <=10 band (2026-07-20, revised): deliberately does NOT show every
  // product the restaurant has. Showing all 10 upfront in a "teaser"
  // section removes any reason for the customer to keep exploring the real
  // menu below it - capped at 5 (or fewer if the menu itself has under 5)
  // so the section stays a genuine teaser, not the whole story. Every
  // other band is a flat cap from the approved product spec table.
  static int dynamicSectionLimit(int totalActiveProducts) {
    if (totalActiveProducts <= 10) return min(5, totalActiveProducts);
    if (totalActiveProducts <= 20) return 6;
    if (totalActiveProducts <= 40) return 8;
    if (totalActiveProducts <= 75) return 10;
    if (totalActiveProducts <= 120) return 12;
    if (totalActiveProducts <= 200) return 15;
    return 20; // 200+ - maximum cap
  }

  /// Single source of truth for Recommended For You / Explore the Menu's
  /// section size for one restaurant visit - both sections read the SAME
  /// ctx.allProducts, so calling this once per section (rather than each
  /// section maintaining its own literal) guarantees they can never disagree
  /// about "how many is normal" for this restaurant. The min() is a final
  /// explicit safety net ("never exceed total available products") on top
  /// of dynamicSectionLimit's own table, which already never exceeds it for
  /// a well-formed count.
  static int sectionLimitFor(RestaurantRecommendationContext ctx) =>
      min(dynamicSectionLimit(ctx.allProducts.length), ctx.allProducts.length);

  // Pairs Well With must stay a short, scannable row even for a 200+ item
  // restaurant, unlike the two full-page sections above - explicit product
  // requirement, independent of how large sectionLimitFor would otherwise
  // allow it to grow.
  static const int _pairsWellWithMaxItems = 8;

  // Small-menu teaser cap (2026-07-20): mirrors dynamicSectionLimit's own
  // "stay curious" rule for <=10-product restaurants, but Pairs Well With
  // gets one extra slot over Explore/Recommended's 5 (i.e. 6) - it's
  // already anchored to one specific product the customer just picked, not
  // a generic browse, so one more real suggestion stays useful without
  // giving away the whole menu. Above 10 products, falls through to the
  // existing flat _pairsWellWithMaxItems ceiling unchanged.
  static int pairingSectionLimitFor(RestaurantRecommendationContext ctx) {
    final total = ctx.allProducts.length;
    if (total <= 10) return min(6, total);
    return min(_pairsWellWithMaxItems, sectionLimitFor(ctx));
  }

  // ── Data-sufficiency gates (2026-07-18 addition) ────────────────────────
  //
  // Restaurant-popularity sections (Best Sellers / Restaurant Must Try /
  // Most Loved Here / Hidden Gems) must not activate after one or two early
  // sales - a single sale would otherwise make one dish look like a
  // long-standing trend. minimumRestaurantConfidenceOrders is a total
  // rolling-90-day (3-month) sales count ACROSS THE WHOLE MENU (not per-product),
  // matching the same "require enough real data before trusting it"
  // philosophy already used by _vendorRatingConfidenceThreshold below and
  // Search Confidence's tiering. Public + a named constant (not buried
  // inline) so it stays a single, easily-retuned number, per explicit
  // instruction that this must remain configurable from one place.
  static const int minimumRestaurantConfidenceOrders = 15;

  static bool hasSufficientRestaurantConfidence(RestaurantRecommendationContext ctx) {
    final total = ctx.rolling90DaySales.values.fold<int>(0, (a, b) => a + b);
    return total >= minimumRestaurantConfidenceOrders;
  }

  // Distinct from _diversityMinMenuSize below (same value today, different
  // concept) - this one governs whether the 5 recommendation SECTIONS show
  // at all, not diversity relaxation within one already-visible section.
  // Menus this small already let a customer see everything at a glance, so
  // a "Recommended"/"Best Sellers" section adds nothing.
  static const int minProductsForRecommendationSections = 10;

  static bool hasEnoughProductsForSections(RestaurantRecommendationContext ctx) =>
      ctx.allProducts.length >= minProductsForRecommendationSections;

  /// True exactly in the gap between "menu big enough to bother with a
  /// section" and "restaurant has enough sales history for a real
  /// popularity/personalization signal" - the scenario Explore the Menu
  /// (exploreMenuSelection, below) exists for. Callers should show that
  /// neutral section INSTEAD OF, never alongside, the 5 real recommendation
  /// sections whenever this is true.
  static bool shouldShowExploreMenuFallback(RestaurantRecommendationContext ctx) =>
      hasEnoughProductsForSections(ctx) && !hasSufficientRestaurantConfidence(ctx);

  /// NOT a manufactured recommendation - never invents a signal that isn't
  /// there. Used only via shouldShowExploreMenuFallback: a restaurant with
  /// enough products to make a section worthwhile but not yet enough sales
  /// history for any real signal would otherwise show nothing at all between
  /// "the raw menu" and "real recommendations" - this gives a quick, honest
  /// browsing aid instead: one product per distinct category, backfilled
  /// with the next unused products in menu order if there aren't enough
  /// distinct categories to fill [limit]. Automatically stops being relevant
  /// the moment hasSufficientRestaurantConfidence(ctx) becomes true -
  /// callers must re-check shouldShowExploreMenuFallback each render, not
  /// cache the decision, so the real sections take over the instant real
  /// data exists.
  ///
  /// Category ORDER (2026-07-19, Business Context): which category leads,
  /// within [limit], now prefers whichever categories businessContextScore
  /// rates highest for this vendor - Restaurant Type AND Cuisine combined
  /// (see _categoryOrderByBusinessType below), each tier internally still in
  /// first-appearance menu order (a stable partition of the category list).
  /// Exact no-op (identical menu-order category sequence) whenever
  /// businessContextScore has nothing to say for every category on the menu
  /// - e.g. a vendor with no businessTypeId/cuisineIds configured, or one
  /// whose Restaurant Type/Cuisines have no Admin Panel profile yet.
  ///
  /// Representative PRODUCT (2026-07-19, menu-order alignment): within the
  /// chosen category, the representative product is now whichever one
  /// reorderByScore(categoryProducts, scores) puts first - the EXACT same
  /// merged score (computeMergedScores) and the EXACT same reordering
  /// function newVendorProductsScreen's _productsForCategory already uses
  /// to decide what a customer sees when they scroll to that category on
  /// the real menu. Two consequences, both intentional: (a) Explore's pick
  /// can never visibly disagree with the real menu - whatever leads a
  /// category here is also what leads it when the customer scrolls there;
  /// (b) reorderByScore's own cold-start guard (all candidates score 0 ->
  /// untouched natural/menu order) means a category with genuinely zero
  /// signal on every one of its products still resolves exactly as before -
  /// no fabricated confidence, no rotation, a fully stable pick. No new
  /// scoring path was added: this reuses computeMergedScores/reorderByScore
  /// exactly as already used elsewhere in this file.
  ///
  /// Deliberately reads ctx.allProducts, NOT newVendorProductsScreen's live
  /// productList (2026-07-19, confirmed intentional - not an oversight if
  /// someone is tempted to "fix" this later): Explore represents restaurant-
  /// level cold-start recommendations and is intentionally independent of
  /// temporary UI state - Veg/Non-Veg toggle, dish search text, dine-away
  /// sub-mode. The scrollable menu below it (_productsForCategory) continues
  /// to respect those filters on its own; Explore's category leadership and
  /// representative pick should not flicker as a customer types a search
  /// query or flips a filter chip.
  static List<ProductModel> exploreMenuSelection(RestaurantRecommendationContext ctx,
      {int limit = defaultSectionLimit}) {
    final categoryOrder = _categoryOrderByBusinessType(ctx);
    // Explore weight inheritance (2026-07-22, revised) - TRUE fallback, not
    // a frozen duplicate: rfyWeights is whatever Recommended For You itself
    // would compute for this exact session (live, Explorer-Score-adjusted,
    // config-driven). When exploreOverrideEnabled is false (the default),
    // Explore uses rfyWeights completely unmodified - tuning RFY's weights
    // in the Admin Panel automatically carries through to Explore with zero
    // admin action, no duplicated configuration anywhere. Only when an
    // admin explicitly flips the override on do Explore's own 4 stored
    // values substitute in (preference/mustTry/similar are never
    // independently configurable for Explore, override or not).
    final exploreConfig = RecommendationConfig.current;
    final rfyWeights = sourceWeightsFor(ctx.behaviorSummary.discoveryPreferenceScore);
    final exploreWeights = exploreConfig.exploreOverrideEnabled
        ? (Map<String, double>.from(rfyWeights)
          ..['businessContext'] = exploreConfig.exploreBusinessContextWeight / 100
          ..['newProduct'] = exploreConfig.exploreNewProductBoostWeight / 100
          ..['bestSeller'] = exploreConfig.explorePopularProductsWeight / 100
          ..['discovery'] = exploreConfig.exploreDiscoveryWeight / 100)
        : rfyWeights;
    final scores = computeMergedScores(ctx, weights: exploreWeights);
    final chosen = <ProductModel>[];
    for (final catId in categoryOrder) {
      if (chosen.length >= limit) break;
      final categoryProducts =
          ctx.allProducts.where((p) => p.categoryID == catId).toList();
      final ranked = reorderByScore(categoryProducts, scores);
      // Combo Recommendation Rules, Section 3: a combo may only lead its
      // category's representative slot with strong per-customer confidence
      // (comboEligibilityScore) - otherwise fall through to the next
      // non-combo item in the same category (normal dishes keep leading,
      // exactly as today), or skip this category's slot entirely if only
      // weak-evidence combos remain rather than fabricate a representative.
      ProductModel? representative;
      for (final p in ranked) {
        if (!p.isCombo || comboEligibilityScore(p, ctx) >= comboEligibilityThreshold) {
          representative = p;
          break;
        }
      }
      if (representative != null) chosen.add(representative);
    }
    if (chosen.length < limit) {
      final chosenIds = chosen.map((p) => p.id).toSet();
      for (final p in ctx.allProducts) {
        if (chosen.length >= limit) break;
        if (!chosenIds.contains(p.id)) chosen.add(p);
      }
    }

    // Combo Recommendation Rules, Section 3/8: even once eligible per-category
    // (above), combos must never dominate the section and never occupy a
    // leading position in the final list - cap to
    // maxComboRecommendationsPerSection (keep the highest-scoring ones,
    // drop the rest entirely rather than replace them with anything
    // fabricated), then stable-partition individuals before combos. Category
    // leadership/backfill selection above is completely untouched by this -
    // it only reorders/trims the already-chosen set.
    final comboItemsInChosen = chosen.where((p) => p.isCombo).toList()
      ..sort((a, b) => (scores[b.id] ?? 0).compareTo(scores[a.id] ?? 0));
    if (comboItemsInChosen.length > maxComboRecommendationsPerSection) {
      final dropIds = comboItemsInChosen
          .skip(maxComboRecommendationsPerSection)
          .map((p) => p.id)
          .toSet();
      chosen.removeWhere((p) => dropIds.contains(p.id));
    }
    final individuals = chosen.where((p) => !p.isCombo).toList();
    final combos = chosen.where((p) => p.isCombo).toList();
    return [...individuals, ...combos];
  }

  /// Distinct category IDs in first-appearance menu order, stably
  /// partitioned by businessContextScore of one representative product per
  /// category (the function already combines Restaurant Type tier AND
  /// Cuisine affinity via noisy-OR - reused directly here, not
  /// reimplemented, so Explore's category order and every scored section's
  /// category relevance can never disagree about what businessContextScore
  /// says for a given category). businessContextScore only ever depends on
  /// p.categoryID, never any other product field, so evaluating it once per
  /// distinct category (via that category's first-seen product) is exactly
  /// equivalent to evaluating it per-product - just cheaper. Categories with
  /// no Business Context evidence at all naturally score 0 and stay in
  /// first-appearance order relative to each other (stable sort) - a vendor
  /// with no businessTypeId/cuisineIds configured, or no Admin Panel profile
  /// yet for either, gets plain, unchanged menu order for every category.
  static List<String> _categoryOrderByBusinessType(
      RestaurantRecommendationContext ctx) {
    final seen = <String>{};
    final menuOrder = <String>[];
    final representativeByCategory = <String, ProductModel>{};
    for (final p in ctx.allProducts) {
      if (seen.add(p.categoryID)) {
        menuOrder.add(p.categoryID);
        representativeByCategory[p.categoryID] = p;
      }
    }
    final indexed = menuOrder.asMap().entries.toList();
    indexed.sort((a, b) {
      final tierA = businessContextScore(representativeByCategory[a.value]!, ctx);
      final tierB = businessContextScore(representativeByCategory[b.value]!, ctx);
      final cmp = tierB.compareTo(tierA);
      return cmp != 0 ? cmp : a.key.compareTo(b.key); // stable: first-appearance order as tie-break
    });
    return indexed.map((e) => e.value).toList();
  }

  /// Customer's own per-category BEHAVIOR rank (2026-07-23, category-first
  /// redesign) - distinct category IDs on this menu, in first-appearance
  /// menu order, stably sorted by categoryInteractionCounts descending.
  /// Deliberately a DIFFERENT signal than _categoryOrderByBusinessType
  /// above (admin-configured Restaurant Type/Cuisine, used by Explore the
  /// Menu) - this one is pure real customer behavior, matching explicit
  /// product direction: "first analyze user category-wise behavior, then
  /// show good products from that category." A customer with no category
  /// interaction history at all on this menu (Stage 0, or simply hasn't
  /// touched any category here yet) gets every category tied at 0 - the
  /// stable sort then degrades to plain menu-category order, never a
  /// fabricated preference.
  static List<String> _categoryOrderByPreference(
      RestaurantRecommendationContext ctx) {
    final seen = <String>{};
    final menuOrder = <String>[];
    for (final p in ctx.allProducts) {
      if (seen.add(p.categoryID)) menuOrder.add(p.categoryID);
    }
    final indexed = menuOrder.asMap().entries.toList();
    indexed.sort((a, b) {
      // Cuisine bonus (2026-07-25, see _customerCuisineCategoryBonus's own
      // doc comment) is always < 1.0, so it can only ever break a tie
      // between categories with the SAME direct categoryInteractionCounts
      // value (most commonly both 0, at a restaurant the customer has no
      // category history at all) - it can never outrank a category this
      // customer has genuinely, directly interacted with more.
      final scoreA = (ctx.behaviorSummary.categoryInteractionCounts[a.value] ?? 0) +
          _customerCuisineCategoryBonus(a.value, ctx);
      final scoreB = (ctx.behaviorSummary.categoryInteractionCounts[b.value] ?? 0) +
          _customerCuisineCategoryBonus(b.value, ctx);
      final cmp = scoreB.compareTo(scoreA);
      return cmp != 0 ? cmp : a.key.compareTo(b.key); // stable: menu order tie-break
    });
    return indexed.map((e) => e.value).toList();
  }

  /// categoryID -> its rank position (0 = most-preferred) from
  /// _categoryOrderByPreference above, for O(1) lookup as a PRIMARY sort
  /// key. Used by recommendForYou, topBySource('preference', categoryFirst:
  /// true), and hiddenGems to make category preference the dominant sort
  /// key and product score the secondary one, without touching how either
  /// is actually SCORED - only the final ordering changes.
  static Map<String, int> _categoryRankIndex(
      RestaurantRecommendationContext ctx) {
    final order = _categoryOrderByPreference(ctx);
    return {for (final e in order.asMap().entries) e.value: e.key};
  }

  // ── Restaurant-level rating (legitimate data - see file header) ────────

  static const int _vendorRatingConfidenceThreshold = 15;

  /// 0..1 confidence-weighted restaurant quality signal. NEVER per-product -
  /// every product from one vendor gets the exact same value here.
  static double _vendorRatingSignal(VendorModel vendor) {
    final count = vendor.reviewsCount;
    if (count <= 0) return 0.0;
    final avg = (vendor.reviewsSum / count).clamp(0, 5);
    final confidence =
        (count / _vendorRatingConfidenceThreshold).clamp(0.0, 1.0);
    return (avg / 5.0) * confidence;
  }

  /// Small, uniform, restaurant-wide multiplier applied once to the final
  /// merged list in recommendForYou (never inside an individual source,
  /// where it would be a no-op for relative ranking since it's identical
  /// for every candidate from the same vendor). Roughly -0.12..+0.08,
  /// centered near a ~4.0-ish confidence-weighted baseline. Never stored,
  /// never displayed as a product rating.
  static double restaurantQualityBoost(VendorModel vendor) =>
      (_vendorRatingSignal(vendor) - 0.6) * 0.2;

  // ── Price compatibility + taste-profile approximation ──────────────────

  static double _effectivePrice(ProductModel p) {
    final dis = double.tryParse(p.disPrice ?? '0') ?? 0;
    final base = double.tryParse(p.price) ?? 0;
    return dis > 0 ? dis : base;
  }

  // Documented approximation - avgOrderValue is a per-ORDER average, not a
  // per-item spend figure, and no per-item spend data exists anywhere in
  // this platform. This constant makes that approximation explicit rather
  // than silently pretending order-level data is item-level.
  static const double _assumedItemsPerOrder = 2.0;

  /// 0..1: how close this product's own price sits to the price tier this
  /// customer's order history suggests they favor, relative to THIS
  /// restaurant's own menu price spread. 0 (no signal, not a penalty) when
  /// there's no order history or the menu has no price spread to compare against.
  static double _priceCompatibility(
      ProductModel product, RestaurantRecommendationContext ctx) {
    final aov = ctx.behaviorSummary.avgOrderValue;
    if (aov <= 0) return 0.0;
    final prices = ctx.allProducts.map(_effectivePrice).where((p) => p > 0).toList();
    if (prices.length < 2) return 0.0;
    final minP = prices.reduce(min), maxP = prices.reduce(max);
    if (maxP <= minP) return 0.0;
    final customerTier =
        ((aov / _assumedItemsPerOrder - minP) / (maxP - minP)).clamp(0.0, 1.0);
    final productTier =
        ((_effectivePrice(product) - minP) / (maxP - minP)).clamp(0.0, 1.0);
    return (1.0 - (productTier - customerTier).abs()).clamp(0.0, 1.0);
  }

  // ── Combo Recommendation Rules (2026-07-19) ─────────────────────────────
  //
  // Combo eligibility is a SEPARATE question from a combo's normal Business
  // Context/preference/best-seller score - those only ever say "this
  // CATEGORY is relevant", never "this specific customer wants a BUNDLE
  // over individual dishes". comboEligibilityScore answers that second
  // question, combining real per-customer evidence: has this exact combo
  // been ordered/viewed before, does the customer already independently
  // order/view the products this combo bundles together, and does the
  // combo's price fit their historical spend (Section 5 - one signal among
  // several, never the sole gate). Honestly 0 for a signal-less/true-cold-
  // start customer (Section 4) - no special-case code needed for that
  // requirement, it falls out of every sub-signal below requiring real
  // behaviorSummary data. Zero new Firestore reads - every input already
  // lives on ctx (comboProducts was added for the Add Product combo
  // feature; everything else is data this engine already reads elsewhere).
  static const double comboEligibilityThreshold = 0.35;

  // Shared by exploreMenuSelection and fillPairsWellWith (2026-07-25,
  // narrowed - recommendForYou now uses the dynamic, customer-adaptive
  // comboSlotAllocation below instead of this flat constant, see that
  // function's own doc comment for why): even once a combo clears
  // comboEligibilityThreshold, it must never dominate a section or occupy a
  // leading position - capped at 2, and always sorted after every
  // individual product regardless of its own score (see each function's own
  // combo partition logic below).
  static const int maxComboRecommendationsPerSection = 2;

  // ── Combo Recommendation Allocation (2026-07-25) ────────────────────────
  //
  // recommendForYou's combo share of a section - dynamic (scales with the
  // section's own [limit], not a flat count) AND customer-adaptive (scales
  // with how often THIS customer personally orders combos at all). Two
  // needs, one mechanism, both driven by data already on
  // BehaviorSummarySnapshot - no new tracking, no separate combo engine.

  // Baseline band (no personal combo-order history yet - the overwhelming
  // majority of customers today, before this signal has had time to
  // accumulate): individual products stay clearly dominant, ~80-85% of a
  // section, combos ~15-20%. 0.175 is that band's midpoint, used as a flat
  // ratio here (not "15% for small limits, 20% for large" - there's no
  // signal yet to justify leaning either way within the band).
  static const double _comboRatioBaseline = 0.175;

  /// How large a share of a recommendation section combos should occupy,
  /// adapted to THIS customer's own combo-ordering history
  /// (comboOrderCount/orderCount - both already on BehaviorSummarySnapshot,
  /// zero new tracking). A customer who orders combos MOST of the time
  /// (>=50% of their own orders) sees noticeably more combo representation
  /// (a 50-60% band, scaling up within it as their combo rate approaches
  /// 100%); one who rarely does sees only a small band (10-15%, scaling up
  /// within it as their combo rate approaches 50%) so individual products
  /// still clearly dominate; a customer with NO combo-order history at all
  /// falls back to _comboRatioBaseline - never fabricate a preference with
  /// zero evidence behind it, same "when data exists...when not, behave
  /// like the flat default" rule this file applies to every other adaptive
  /// signal (e.g. mostLovedHere's dietary preference filter).
  static double _comboRatioFor(RestaurantRecommendationContext ctx) {
    final orderCount = ctx.behaviorSummary.orderCount;
    final comboOrderCount = ctx.behaviorSummary.comboOrderCount;
    if (orderCount <= 0 || comboOrderCount <= 0) return _comboRatioBaseline;
    final comboOrderRatio = (comboOrderCount / orderCount).clamp(0.0, 1.0);
    if (comboOrderRatio >= 0.5) {
      // 0.5 -> 0.50, 1.0 -> 0.60
      return 0.50 + (comboOrderRatio - 0.5) * 0.20;
    }
    // 0.0 -> 0.10, 0.5 -> 0.15 (never reached at exactly 0.5 - the branch
    // above owns that boundary)
    return 0.10 + comboOrderRatio * 0.10;
  }

  /// How many of recommendForYou's [limit] slots combos may occupy -
  /// _comboRatioFor(ctx) applied to [limit], rounded, with a floor that
  /// exempts tiny sections entirely (a 3-item section reserving even 1
  /// combo slot would read as "dominating", not "a small portion", however
  /// the percentages work out) and a ceiling that can never exceed the
  /// section itself. Worked examples at the baseline ratio (0.175):
  /// limit=8 -> 1, limit=10 -> 2, limit=15 -> 3 - each within the spec's
  /// own 1-2 / 2 / 2-3 examples.
  static int comboSlotAllocation(int limit, RestaurantRecommendationContext ctx) {
    if (limit < 4) return 0;
    final ratio = _comboRatioFor(ctx);
    return (limit * ratio).round().clamp(0, limit);
  }

  static double comboEligibilityScore(
      ProductModel combo, RestaurantRecommendationContext ctx) {
    if (!combo.isCombo) return 1.0; // n/a - callers gate on isCombo first
    if (ctx.behaviorSummary.isEmpty) return 0.0; // true cold start -> never eligible

    final everOrdered = (ctx.behaviorSummary.productOrderQuantities[combo.id] ?? 0) > 0;
    final maxViews = ctx.behaviorSummary.productViewCounts.values.fold(0, max);
    final viewSignal =
        _log1pScaled(ctx.behaviorSummary.productViewCounts[combo.id] ?? 0, maxViews);

    // "Frequently ordering the same products that exist inside the combo" -
    // the single strongest, most literal signal available: how much of this
    // combo's own contents the customer already independently orders/views.
    double childOverlap = 0.0;
    if (combo.comboProducts.isNotEmpty) {
      final maxOrderQty = ctx.behaviorSummary.productOrderQuantities.values.fold(0, max);
      final maxComboChildQty =
          ctx.behaviorSummary.comboChildProductCounts.values.fold(0, max);
      double sum = 0.0;
      for (final child in combo.comboProducts) {
        final orderSignal = _log1pScaled(
            ctx.behaviorSummary.productOrderQuantities[child.productId] ?? 0, maxOrderQty);
        final childViewSignal = _log1pScaled(
            ctx.behaviorSummary.productViewCounts[child.productId] ?? 0, maxViews);
        // Combo Purchase Learning (2026-07-19): has this product arrived
        // inside a DIFFERENT combo the customer ordered before - a
        // cross-combo generalization signal, distinct from ordering the
        // product standalone (orderSignal above).
        final crossComboSignal = _log1pScaled(
            ctx.behaviorSummary.comboChildProductCounts[child.productId] ?? 0,
            maxComboChildQty);
        sum += orderSignal * 0.55 + childViewSignal * 0.2 + crossComboSignal * 0.25;
      }
      childOverlap = (sum / combo.comboProducts.length).clamp(0.0, 1.0);
    }

    final budgetSignal = _priceCompatibility(combo, ctx);

    // "Meal-size preference" (Combo Purchase Learning, Section 6/2): does
    // this combo's own item count match what the customer has historically
    // ordered in past combos. 0 (no penalty, not a negative signal) until
    // they've ordered at least one combo before - there's no "preferred
    // size" to compare against yet.
    double mealSizeSignal = 0.0;
    if (ctx.behaviorSummary.comboOrderCount > 0 && combo.comboProducts.isNotEmpty) {
      final preferredSize = ctx.behaviorSummary.avgComboSize;
      final thisSize = combo.comboProducts.length.toDouble();
      final spread = max(preferredSize, thisSize);
      mealSizeSignal =
          spread > 0 ? (1.0 - (thisSize - preferredSize).abs() / spread).clamp(0.0, 1.0) : 0.0;
    }

    // Combo Category Intelligence / Cold Start (2026-07-25): does this
    // combo REPRESENT categories the customer already shows real
    // preference for - "customer frequently orders Biryani + Burger; a
    // combo containing Biryani + Burger + Drink should receive a strong
    // category preference score" (explicit product example). THE
    // mechanism that lets a genuinely brand-new combo (zero sales, zero
    // views, never ordered, so everOrdered/childOverlap/viewSignal/
    // mealSizeSignal above are all 0) still clear the eligibility bar:
    // unlike every term above, this needs neither THIS combo's own
    // history NOR its EXACT child products to have been individually
    // interacted with - only the CATEGORIES it represents (see
    // _effectiveCategoryIds) to already be ones the customer favors.
    // Same max-not-sum reasoning as _preferenceRawMaps: one strongly-
    // favored represented category is enough, spanning more categories
    // doesn't inflate it further.
    final productById = {for (final p in ctx.allProducts) p.id: p};
    final maxCategoryInteraction =
        ctx.behaviorSummary.categoryInteractionCounts.values.fold(0, max);
    final categoryPreferenceSignal = _effectiveCategoryIds(combo, productById).fold(
        0.0,
        (best, catId) => max(
            best,
            _log1pScaled(
                ctx.behaviorSummary.categoryInteractionCounts[catId] ?? 0,
                maxCategoryInteraction)));

    // Weights rebalanced (2026-07-25, revised) to make categoryPreferenceSignal
    // the DOMINANT term - not just "comparable to the others" as an earlier
    // pass here had it (0.20, which topped out at 0.20 even at maximum
    // 1.0 strength - short of comboEligibilityThreshold, 0.35, on its own,
    // which directly contradicted the explicit product requirement that a
    // genuinely brand-new combo must be able to qualify through category
    // preference ALONE, before any sales/views/orders exist for it or its
    // children). At 0.40, a customer with real, strong category interest
    // (categoryPreferenceSignal at or near 1.0) now clears the threshold
    // by itself with margin, while a customer with only mild/noisy
    // category signal (a small fraction of 1.0) still can't - the bar is
    // on SIGNAL STRENGTH, not on stacking with other terms. Every other
    // term shrunk proportionally to make room, still summing to 1.0.
    return (everOrdered ? 1.0 : 0.0) * 0.20 +
        childOverlap * 0.15 +
        categoryPreferenceSignal * 0.40 +
        budgetSignal * 0.10 +
        viewSignal * 0.10 +
        mealSizeSignal * 0.05;
  }

  /// Cross-cuisine "taste profile" approximation - categoryMatch is the
  /// real mechanism here, not a proxy: ProductModel.categoryID references
  /// the flat, platform-wide `vendor_categories` collection (no vendor
  /// scoping), so categoryInteractionCounts is already a genuinely
  /// cross-restaurant signal with zero new tracking. A customer who
  /// repeatedly interacts with "Pizza"-category items elsewhere and visits
  /// an unrelated-cuisine restaurant that happens to share a category gets
  /// real signal here. True flavor/spice-level matching is NOT built - no
  /// such data exists anywhere in the platform (see plan doc Section 8).
  // Category/price split reverted to fixed constants (2026-07-22) - was
  // briefly configurable via RecommendationConfig.categoryPreferenceWeight/
  // budgetPreferenceWeight, deliberately reverted per explicit product
  // decision: Preference's internal Product/Category/Budget ratio is an
  // implementation detail, not an admin-facing control - only the overall
  // Preference source weight is configurable (see
  // RecommendationConfig.preferenceWeight, read in _baseSourceWeights
  // below).
  //
  // cuisineMatch added 2026-07-25 (see _customerCuisineMatchScore's own doc
  // comment) - a real third term, not a proxy folded into categoryMatch,
  // since it can be non-zero even when categoryMatch is 0 (a customer's
  // preferred cuisine matching this vendor, on a category they've never
  // personally interacted with anywhere yet). Weighted below category
  // (the stronger, more direct signal) and below price, deliberately
  // modest since cuisine-driven category affinity is itself an admin-
  // curated lookup, one layer more indirect than a customer's own
  // category interaction history.
  static double _tasteProfileScore(ProductModel p,
      RestaurantRecommendationContext ctx, int categoryRaw, int maxCategory) {
    final categoryMatch = _log1pScaled(categoryRaw, maxCategory);
    final priceMatch = _priceCompatibility(p, ctx);
    final cuisineMatch = _customerCuisineMatchScore(p, ctx);
    return categoryMatch * 0.5 + priceMatch * 0.35 + cuisineMatch * 0.15;
  }

  // ── Business Context: Restaurant Type + Cuisine (ID-based) ──────────────
  // (2026-07-19, revised same day per product review - see the revision's
  // own final report for the full "what changed and why")
  //
  // A restaurant's PRODUCTS should represent what kind of business it is,
  // not just what happens to sell - but that guidance must stay a BOOST,
  // never a replacement for real customer behavior/popularity (see the
  // Cafe-that-becomes-famous-for-Pizza example this revision is built
  // around). One scoring function (businessContextScore) two other things
  // build on:
  // 1) a new, independent candidate source (_sourceBusinessContext) feeding
  //    the existing noisy-OR merge, so Recommended For You/the confidence
  //    badge/Pairs Well With all inherit it automatically via
  //    computeMergedScores - zero changes needed at those call sites; and
  // 2) _applyBusinessContextMultiplier, a small BOOST-ONLY multiplier for
  //    the sections that deliberately read ONE named source's raw score
  //    instead of the merge (Restaurant Must Try, Hidden Gems, Most Loved
  //    Here) and would otherwise never see this signal at all.
  //
  // ID-based, not name/keyword-based: matches ctx.vendor.businessTypeId
  // and ctx.vendor.cuisineIds (both already exist on VendorModel - the
  // Cuisine implementation already worked this way) against
  // ctx.businessTypeProfiles/ctx.cuisineCategoryAffinity, whose Sets
  // contain Product Category document IDs (ProductModel.categoryID)
  // directly - no title resolution, no normalize(), no substring matching
  // anywhere in this file. Renaming a Restaurant Type, Cuisine, or Category
  // in the Admin Panel changes nothing here; the IDs never change.
  //
  // Admin-managed (2026-07-19, revision 3): ctx.businessTypeProfiles/
  // cuisineCategoryAffinity are fetched from Firestore and TTL-cached by
  // FirebaseHelper.getBusinessContext, NOT hardcoded in this file - see
  // that method's doc comment for the caching strategy. This engine only
  // ever reads the already-resolved maps off ctx, exactly like every other
  // field here (behaviorSummary, rolling90DaySales, ...) - "already-loaded
  // data as arguments", per this file's own header. There is no longer a
  // business_context_config.dart; that hardcoded file was deleted.
  //
  // Does NOT re-score Product Category on its own - that would double-
  // count the category-affinity signal _sourcePreference/_tasteProfileScore
  // already computes from real customer behavior (categoryInteractionCounts).
  // Category ID here is only ever the LOOKUP AXIS for Restaurant Type/
  // Cuisine matching, never an independent third score.
  //
  // Two independent sub-scores, combined the same noisy-OR way the rest of
  // this file combines independent evidence (1 - (1-a)(1-b), not a plain
  // sum - see computeMergedScores' own doc comment for why):
  // - Restaurant Type tier: ctx.businessTypeProfiles maps businessTypeId to
  //   primary(1.0)/secondary(0.55)/lowPriority(0.05, never 0 - "do not
  //   remove products, only change priority")/unmatched(0.0) category-ID
  //   tiers.
  // - Cuisine affinity: ctx.cuisineCategoryAffinity - a flat 0.7 if ANY of
  //   the vendor's cuisineIds is known to favor this product's categoryID,
  //   0.0 otherwise.
  //
  // Cloud Kitchen: deliberately has NO entry in businessTypeProfiles at
  // all - not an empty profile, no entry (the Admin Panel simply never
  // gets a Categories section to fill in for it - see the Admin Panel
  // changes in this revision's final report). A business type with no
  // config entry is indistinguishable here from any other not-yet-
  // configured type: typeScore is honestly 0.0 (no evidence, not a
  // penalty), and businessContextScore reduces to exactly cuisineScore -
  // Cloud Kitchen "simply inherits from Cuisine, Product Category [via the
  // existing preference source, untouched] and Popularity", with no
  // special-case code anywhere for it.
  //
  // Backward compatibility: a vendor with no businessTypeId set (every
  // restaurant created before this field existed) or one with no entry in
  // businessTypeProfiles yet (every type, until an admin configures it via
  // the Business Types/Cuisines edit pages) contributes typeScore 0.0. A
  // vendor with no cuisineId entry in cuisineCategoryAffinity contributes
  // cuisineScore 0.0. Both together mean businessContextScore is honestly
  // 0.0 for every vendor until an admin explicitly configures categories
  // for their Restaurant Type/Cuisine - this feature activates gradually,
  // type by type and cuisine by cuisine, entirely from the Admin Panel,
  // never from an app release.

  static const double _businessContextPrimaryScore = 1.0;
  static const double _businessContextSecondaryScore = 0.55;
  static const double _businessContextLowPriorityScore = 0.05;
  static const double _businessContextCuisineMatchScore = 0.7;

  static double _restaurantTypeCategoryScore(
      ProductModel p, RestaurantRecommendationContext ctx) {
    final typeId = ctx.vendor.businessTypeId;
    if (typeId.isEmpty) return 0.0;
    final profile = ctx.businessTypeProfiles[typeId];
    if (profile == null) return 0.0;
    if (profile.primaryCategoryIds.contains(p.categoryID)) {
      return _businessContextPrimaryScore;
    }
    if (profile.secondaryCategoryIds.contains(p.categoryID)) {
      return _businessContextSecondaryScore;
    }
    if (profile.lowPriorityCategoryIds.contains(p.categoryID)) {
      return _businessContextLowPriorityScore;
    }
    return 0.0;
  }

  /// [cuisineIdsOverride] (2026-07-19, Pairs Well With only): when null
  /// (every existing caller - _sourceBusinessContext,
  /// _categoryOrderByBusinessType, _applyBusinessContextMultiplier - all
  /// call this with 2 positional args and no override), behavior is
  /// byte-for-byte identical to before this parameter existed: iterates
  /// ctx.vendor.cuisineIds, the restaurant's full cuisine list. Only
  /// pairingContextScore below ever supplies an override, and only with a
  /// narrower subset of that same list - never a different data source,
  /// never a cuisine the vendor doesn't actually have.
  static double _cuisineCategoryScore(
      ProductModel p, RestaurantRecommendationContext ctx,
      {Iterable<String>? cuisineIdsOverride}) {
    for (final cuisineId in cuisineIdsOverride ?? ctx.vendor.cuisineIds) {
      final affinity = ctx.cuisineCategoryAffinity[cuisineId];
      if (affinity != null && affinity.contains(p.categoryID)) {
        return _businessContextCuisineMatchScore;
      }
    }
    return 0.0;
  }

  /// The one combined Business Context score - Restaurant Type tier and
  /// Cuisine affinity merged noisy-OR style. 0..1, 0.0 meaning honestly "no
  /// business-context signal", never a penalty.
  ///
  /// [cuisineIdsOverride] exists solely so pairingContextScore (below) can
  /// narrow the cuisine half of this combine to just the cuisine(s) that
  /// match a PAIRING TRIGGER's own category, without duplicating this
  /// function's noisy-OR logic. Every other caller omits it and gets
  /// exactly today's "all the restaurant's cuisines" behavior - see
  /// _cuisineCategoryScore's own doc comment for the backward-compatibility
  /// guarantee this depends on.
  static double businessContextScore(
      ProductModel p, RestaurantRecommendationContext ctx,
      {Iterable<String>? cuisineIdsOverride}) {
    final typeScore = _restaurantTypeCategoryScore(p, ctx);
    final cuisineScore = _cuisineCategoryScore(p, ctx,
        cuisineIdsOverride: cuisineIdsOverride);
    return 1 - (1 - typeScore) * (1 - cuisineScore);
  }

  // ── Customer Cuisine Preference (2026-07-25) ────────────────────────────
  // Closes a specific, identified gap: cuisineInteractionCounts was being
  // collected (reliably) but never reached per-product/per-category
  // scoring on any customer-facing surface - only a source-WEIGHT blending
  // term (discoveryPreferenceScore) and a separate restaurant-LIST ranking
  // function (restaurantPreferenceScores, used by SearchScreen, not this
  // file's per-restaurant product scoring) ever read it. For a dining-first
  // platform where most visits are a walk-in/QR-scan/name-search rather
  // than a search-driven discovery flow, this meant a customer's real
  // cross-restaurant cuisine history (e.g. "orders Italian food often")
  // had zero influence on which of a BRAND-NEW restaurant's own products
  // got surfaced first - only Product Category (_tasteProfileScore's
  // categoryMatch) did that job, and only when the category IDs happened
  // to be shared across restaurants.
  //
  // Deliberately reuses the EXISTING admin-curated ctx.cuisineCategoryAffinity
  // map (Business Context's cuisine -> category lookup, already fetched,
  // zero new reads) rather than inventing a second affinity table - the
  // only new ingredient is PERSONALIZING that lookup with the customer's
  // own ctx.behaviorSummary.cuisineInteractionCounts, restricted to cuisines
  // this specific vendor actually serves (ctx.vendor.cuisineIds). This is
  // structurally distinct from businessContextScore/_cuisineCategoryScore
  // above, which apply the SAME affinity uniformly to every customer -
  // this one is honestly 0.0 for a customer with no cuisine history, or for
  // a customer whose preferred cuisines aren't served here, exactly like
  // every other behavior-based term in this file degrades gracefully.
  //
  // Per-PRODUCT score, used inside _tasteProfileScore (feeds
  // recommendForYou/"Based on Your Taste" via _sourcePreference).
  static double _customerCuisineMatchScore(
      ProductModel p, RestaurantRecommendationContext ctx) {
    final cuisineCounts = ctx.behaviorSummary.cuisineInteractionCounts;
    if (cuisineCounts.isEmpty) return 0.0;
    final maxCuisine = cuisineCounts.values.fold(0, max);
    if (maxCuisine <= 0) return 0.0;
    double best = 0.0;
    for (final cuisineId in ctx.vendor.cuisineIds) {
      final raw = cuisineCounts[cuisineId];
      if (raw == null || raw <= 0) continue;
      final affinity = ctx.cuisineCategoryAffinity[cuisineId];
      if (affinity == null || !affinity.contains(p.categoryID)) continue;
      final strength = _log1pScaled(raw, maxCuisine);
      if (strength > best) best = strength;
    }
    return best;
  }

  /// Per-CATEGORY counterpart of the above, feeding _categoryOrderByPreference
  /// as a bounded (&lt;1.0) tie-break nudge, never able to outrank a category
  /// with real, direct categoryInteractionCounts evidence (always integers
  /// &gt;=1) - only breaks ties among categories this customer has never
  /// directly touched at all (the common case for a brand-new restaurant).
  /// This is the "walks into a different North Indian restaurant, has never
  /// ordered a Main Course here before, but the platform knows they like
  /// North Indian food elsewhere" bridge from Cuisine -> Category ->
  /// (via _categoryRankIndex) Product ranking.
  static double _customerCuisineCategoryBonus(
      String categoryId, RestaurantRecommendationContext ctx) {
    final cuisineCounts = ctx.behaviorSummary.cuisineInteractionCounts;
    if (cuisineCounts.isEmpty) return 0.0;
    final maxCuisine = cuisineCounts.values.fold(0, max);
    if (maxCuisine <= 0) return 0.0;
    double best = 0.0;
    for (final cuisineId in ctx.vendor.cuisineIds) {
      final raw = cuisineCounts[cuisineId];
      if (raw == null || raw <= 0) continue;
      final affinity = ctx.cuisineCategoryAffinity[cuisineId];
      if (affinity == null || !affinity.contains(categoryId)) continue;
      final strength = _log1pScaled(raw, maxCuisine);
      if (strength > best) best = strength;
    }
    // Capped below 1.0 (any real direct category interaction) - a pure
    // tie-break/nudge among zero-history categories, never a override.
    return best * 0.9;
  }

  // ── Pairing Context: Pairs Well With ONLY (2026-07-19) ──────────────────
  //
  // A restaurant serving North Indian + Chinese + Fast Food shouldn't have
  // Chinese/Fast Food's cuisine affinity boost pairing candidates for a
  // North Indian trigger just because the restaurant ALSO serves those
  // cuisines - businessContextScore's default "all the restaurant's
  // cuisines" is right for Explore/Recommended For You/etc. (no single
  // anchor product exists there) but wrong for pairing, which is inherently
  // about "what goes with THIS specific item". This section is the ONLY
  // place in the file that ever supplies businessContextScore's
  // cuisineIdsOverride - strictly isolated to Pairs Well With, never
  // touched by any other section.
  //
  // Restaurant Type still participates in full and unnarrowed (via
  // businessContextScore's own typeScore term, untouched here) - only the
  // cuisine half is scoped to the trigger.

  /// The category ID(s) a product represents for cuisine-matching purposes -
  /// just its own categoryID for a normal product, or the UNION of its own
  /// category plus every resolvable CHILD product's category when it's a
  /// combo. A combo's own category is typically just "Combo" (see the Add
  /// Product combo architecture - a real, admin-managed category, never a
  /// cuisine signal by itself), so without this a combo spanning e.g. Main
  /// Course + Bread + Beverage would only ever narrow against "Combo"'s own
  /// (likely nonexistent) cuisine affinity, missing every cuisine its
  /// actual contents belong to. Resolved against ctx.allProducts (already
  /// loaded, zero new reads); a child id that no longer resolves (deleted/
  /// unpublished product) is silently skipped, same graceful-degrade
  /// pattern used everywhere else in this file - never an error, just one
  /// fewer category contributing to the union.
  static Set<String> _categoryIdsFor(
      ProductModel product, RestaurantRecommendationContext ctx) {
    final ids = <String>{product.categoryID};
    if (product.isCombo && product.comboProducts.isNotEmpty) {
      final byId = {for (final p in ctx.allProducts) p.id: p};
      for (final child in product.comboProducts) {
        final childProduct = byId[child.productId];
        if (childProduct != null) ids.add(childProduct.categoryID);
      }
    }
    return ids;
  }

  /// Which of the vendor's cuisines the TRIGGERING product's own category
  /// (or, for a combo trigger, ANY of its child categories - see
  /// _categoryIdsFor) actually matches - a Set-membership check, never a
  /// single "winner" pick: if a shared/generic category (e.g. "Main
  /// Course") legitimately matches more than one cuisine's affinity, all
  /// matching cuisines stay active rather than an arbitrary tie-break
  /// invented to pick just one - the same principle now extends across a
  /// combo's multiple category ids, not just one. Falls back to the
  /// vendor's full cuisineIds (== businessContextScore's default) when
  /// none of the trigger's category id(s) match any configured cuisine yet
  /// - never empty/broken, just less narrow, exactly as precise as the
  /// underlying category data allows.
  static Iterable<String> _triggeringCuisinesFor(
      ProductModel triggeringProduct, RestaurantRecommendationContext ctx) {
    final triggerCategoryIds = _categoryIdsFor(triggeringProduct, ctx);
    final matched = ctx.vendor.cuisineIds.where((cuisineId) {
      final affinity = ctx.cuisineCategoryAffinity[cuisineId];
      if (affinity == null) return false;
      return triggerCategoryIds.any(affinity.contains);
    }).toList();
    return matched.isNotEmpty ? matched : ctx.vendor.cuisineIds;
  }

  /// businessContextScore, narrowed to the triggering product's own
  /// cuisine(s) - the ONLY function in this file that ever passes
  /// businessContextScore a cuisineIdsOverride. Used exclusively by
  /// fillPairsWellWith's caller (see newVendorProductsScreen's
  /// _resolvedPairsWellWith) to rank FILLER candidates (never the vendor-
  /// curated branch - a human already chose those pairs deliberately, see
  /// fillPairsWellWith's own doc comment for why that stays untouched).
  static double pairingContextScore(ProductModel candidate,
      ProductModel triggeringProduct, RestaurantRecommendationContext ctx) {
    return businessContextScore(candidate, ctx,
        cuisineIdsOverride: _triggeringCuisinesFor(triggeringProduct, ctx));
  }

  static List<SourceCandidate> _sourceBusinessContext(
      RestaurantRecommendationContext ctx) {
    final out = <SourceCandidate>[];
    for (final p in ctx.allProducts) {
      final score = businessContextScore(p, ctx);
      if (score > 0) out.add(SourceCandidate(p.id, score));
    }
    return out;
  }

  // Max multiplicative boost at businessContextScore == 1.0 (a primary-
  // category match) - deliberately small. A product genuinely 3-4x more
  // popular than another can NEVER be pushed below it by this alone: the
  // boost only ever scales [raw] up by at most 25%, it can never invent
  // score a product doesn't otherwise have and never reduce one. This is
  // the literal mechanism behind "Business Context must remain a boost,
  // never a replacement" - a Cafe's Coffee (typeScore 1.0, small raw
  // sales) cannot outrank that same Cafe's Pizza (typeScore 0.0, dominant
  // real sales) once Pizza's raw popularity genuinely exceeds Coffee's by
  // more than this cap - the recommendation naturally follows real
  // customer behavior as it evolves, with zero vendor configuration.
  static const double _businessContextMaxBoost = 0.25;

  /// Applied to the handful of sections that intentionally read ONE named
  /// source's raw score instead of going through the cross-source merge
  /// (Restaurant Must Try/_sourceMustTry, Hidden Gems/
  /// _hiddenGemProductScore, Most Loved Here/mostLovedHere) - those sections
  /// would otherwise never see Business Context at all, since they bypass
  /// computeMergedScores (and therefore _sourceBusinessContext) by design.
  ///
  /// Boost-only, never a discount: returns [raw] completely UNCHANGED
  /// whenever businessContextScore is 0 (no Restaurant Type/Cuisine
  /// evidence at all - covers every vendor before this feature existed,
  /// every not-yet-configured Restaurant Type, AND Cloud Kitchen with no
  /// matching cuisine) - this is what guarantees Cloud Kitchen (and every
  /// unconfigured type) gets "no special penalty or bonus," not a
  /// coincidence of the tiers happening to be small. When there IS
  /// evidence, the multiplier only ever scales [raw] UP, by at most
  /// _businessContextMaxBoost - a real, honest popularity/trend/gem score
  /// is never suppressed on business-context grounds alone.
  static double _applyBusinessContextMultiplier(
      double raw, ProductModel p, RestaurantRecommendationContext ctx) {
    if (raw <= 0) return raw;
    final tier = businessContextScore(p, ctx);
    if (tier <= 0) return raw;
    return raw * (1 + _businessContextMaxBoost * tier);
  }

  // ── Search Confidence / Cross-Session Search Interest ───────────────────
  //
  // Escalating trust in a search term based on what the customer did
  // afterward (typed only=10% .. opened a matching restaurant=30% ..
  // viewed a matching product=60% .. added to cart=80% .. ordered=100%,
  // see BehaviorSummarySnapshot.searchConfidenceFor), now extended (2026-
  // 07-18) with long-term, cross-session interest - how many DISTINCT DAYS
  // a query keeps recurring over the full retained window, decayed by
  // recency (see BehaviorSummarySnapshot.crossSessionSearchInterestFor,
  // which already reuses searchConfidenceFor as one of its two ingredients
  // - this function just calls the richer, superseding one). This function
  // is the OTHER half of that signal: connecting a remembered query back
  // to a SPECIFIC candidate product/restaurant, using the same lightweight
  // normalized-contains text matching SearchScreen's own _runSearch
  // already does for its name/cuisine tiers - reused here, not
  // reimplemented differently.
  static double _searchConfidenceBoost(
      ProductModel product, RestaurantRecommendationContext ctx) {
    final keywords = ctx.behaviorSummary.topSearchKeywords.keys;
    if (keywords.isEmpty) return 0.0;
    final productName = product.name.toLowerCase();
    final vendorTitle = ctx.vendor.title.toLowerCase();
    final cuisineNames = ctx.vendor.cuisineNames.map((c) => c.toLowerCase());
    final businessType = ctx.vendor.businessTypeName.toLowerCase();
    double best = 0.0;
    for (final query in keywords) {
      if (query.isEmpty) continue;
      final matches = productName.contains(query) ||
          vendorTitle.contains(query) ||
          cuisineNames.any((c) => c.contains(query)) ||
          (businessType.isNotEmpty && businessType.contains(query));
      if (!matches) continue;
      final confidence = ctx.behaviorSummary.crossSessionSearchInterestFor(query);
      if (confidence > best) best = confidence;
    }
    return best;
  }

  // ── Candidate sources (each: RestaurantRecommendationContext -> 0..N candidates) ──

  /// Combo Category Intelligence (2026-07-25) - the category ID(s) [p]
  /// should be matched against for customer category-preference purposes.
  /// Normal products: their own single categoryID, byte-for-byte the same
  /// behavior as before this feature existed. Combo products: the vendor-
  /// selected comboCategoryIds ("this combo represents Biryani + Fast Food
  /// + Beverage") when set, or - since no vendor-facing UI to set that
  /// exists yet, so it's empty on every real combo today - derived from the
  /// combo's own child products' categories instead, via [productById]
  /// (built once per ctx from ctx.allProducts by callers, zero new
  /// Firestore reads). This dual path is what makes a brand-new,
  /// never-configured combo qualify through category preference
  /// immediately (Cold Start requirement), not just once a vendor
  /// eventually tags it. Deliberately NEVER the combo's own categoryID -
  /// see ProductModel.isCombo's doc comment: that field is a real, normal,
  /// admin-managed category exactly like any other product's, but not a
  /// category any customer actually "prefers" as a concept - a combo isn't
  /// competing to be someone's favorite "Combo" category, it's standing in
  /// for the real dishes inside it.
  static List<String> _effectiveCategoryIds(
      ProductModel p, Map<String, ProductModel> productById) {
    if (!p.isCombo) return [p.categoryID];
    if (p.comboCategoryIds.isNotEmpty) return p.comboCategoryIds;
    if (p.comboProducts.isEmpty) return const [];
    final childCategories = <String>{};
    for (final child in p.comboProducts) {
      final childCategoryId = productById[child.productId]?.categoryID;
      if (childCategoryId != null && childCategoryId.isNotEmpty) {
        childCategories.add(childCategoryId);
      }
    }
    return childCategories.toList();
  }

  /// Menu-wide raw (pre-normalization) counts behind _sourcePreference's
  /// behaviorAffinity/categoryMatch terms - pulled out so
  /// recommendationConfidenceScores (the confidence-bar's dominant-label
  /// selection, below) can reuse the EXACT same numbers instead of a second,
  /// potentially-drifting computation. Computed once per ctx, not per product.
  static _PreferenceRawMaps _preferenceRawMaps(RestaurantRecommendationContext ctx) {
    final visitCount = ctx.behaviorSummary.restaurantVisitCounts[ctx.vendor.id] ?? 0;
    final favoriteBonus =
        ctx.behaviorSummary.favoriteRestaurantIds.contains(ctx.vendor.id) ? 5 : 0;
    final behaviorRaw = <String, int>{};
    final categoryRaw = <String, int>{};
    final productById = {for (final p in ctx.allProducts) p.id: p};
    for (final p in ctx.allProducts) {
      behaviorRaw[p.id] = visitCount +
          favoriteBonus +
          (ctx.behaviorSummary.productViewCounts[p.id] ?? 0) +
          (ctx.behaviorSummary.productOrderQuantities[p.id] ?? 0);
      // Combo Category Intelligence (2026-07-25): the STRONGEST match among
      // a combo's represented categories (max, not sum) - "if this combo
      // contains ANY category the customer clearly favors, it should score
      // comparably to a normal product in that same category", not be
      // inflated just for spanning more categories than a single-category
      // product ever could. For a normal product this is exactly the old
      // single-category lookup (a one-element list has one value, so max
      // of it is that value) - fully backward compatible.
      categoryRaw[p.id] = _effectiveCategoryIds(p, productById).fold(
          0,
          (best, catId) =>
              max(best, ctx.behaviorSummary.categoryInteractionCounts[catId] ?? 0));
    }
    return _PreferenceRawMaps(
      behaviorRaw: behaviorRaw,
      maxBehavior: behaviorRaw.values.fold(0, max),
      categoryRaw: categoryRaw,
      maxCategory: categoryRaw.values.fold(0, max),
    );
  }

  static List<SourceCandidate> _sourcePreference(RestaurantRecommendationContext ctx) {
    if (ctx.behaviorSummary.isEmpty) return const []; // Stage 0: naturally contributes nothing
    final raw = _preferenceRawMaps(ctx);

    final out = <SourceCandidate>[];
    for (final p in ctx.allProducts) {
      final behaviorAffinity = _log1pScaled(raw.behaviorRaw[p.id] ?? 0, raw.maxBehavior);
      final tasteProfile =
          _tasteProfileScore(p, ctx, raw.categoryRaw[p.id] ?? 0, raw.maxCategory);
      final searchConfidence = _searchConfidenceBoost(p, ctx);
      final score = behaviorAffinity * 0.45 + tasteProfile * 0.30 + searchConfidence * 0.25;
      if (score > 0) out.add(SourceCandidate(p.id, score));
    }
    return out;
  }
  // "Frequently searched products" note (largely superseded 2026-07-18 by
  // Search Confidence above, which now DOES connect a specific query to a
  // specific product/restaurant via text matching): there is still no
  // per-product search-SELECTION event distinct from kEvtProductViewed -
  // dish search leads to the same view-tracking as any other product view.
  // What changed is that a search query's own escalating confidence now
  // reaches product scoring even without a dedicated selection event.

  static List<SourceCandidate> _sourceBestSeller(RestaurantRecommendationContext ctx) {
    if (!hasSufficientRestaurantConfidence(ctx)) return const [];
    final maxSales = ctx.rolling90DaySales.values.fold(0, max);
    final out = <SourceCandidate>[];
    for (final p in ctx.allProducts) {
      final s = _log1pScaled(ctx.rolling90DaySales[p.id] ?? 0, maxSales);
      if (s > 0) out.add(SourceCandidate(p.id, s));
    }
    return out;
  }

  /// Recent-trend boost for Restaurant Must Try: detects products whose
  /// last-7-days share of volume is disproportionately higher than their
  /// 90-day (3-month) baseline would predict, without being fooled by
  /// low-volume noise (a floor on the expected-7-day denominator, plus an
  /// absolute minimum of 5 units sold this week before any boost applies).
  /// (2026-07-20: denominator rescaled from 7/30 to 7/90 to match the
  /// window widening - rolling90DaySales is now a 90-day total, so
  /// projecting an "expected 7-day share" from it must divide by 90, not
  /// 30, or every trend score would come out 3x too low.)
  static double _mustTryTrend(ProductModel p, RestaurantRecommendationContext ctx) {
    final last7 = ctx.rolling7DaySales[p.id] ?? 0;
    if (last7 < 5) return 0.0;
    final last90 = ctx.rolling90DaySales[p.id] ?? 0;
    final expected7 = max(last90 * (7 / 90), 3.0);
    final ratio = last7 / expected7;
    return ((ratio - 1.0) / 2.0).clamp(0.0, 1.0); // bonus-only, never penalizes decline further
  }

  /// Restaurant Must Try, fully automatic: (a) rolling 90-day (3-month) sales as the
  /// strongest signal, (b) the recent-trend boost above. The restaurant-
  /// level rating boost (signal c in the design doc) is intentionally NOT
  /// applied here - it would be a no-op for relative ranking within one
  /// vendor's own menu (every candidate gets the same multiplier) - it's
  /// applied once, globally, in recommendForYou instead. Diversity (signal
  /// d) is likewise delegated to the single shared _selectDiverse pass,
  /// not duplicated here.
  static List<SourceCandidate> _sourceMustTry(RestaurantRecommendationContext ctx) {
    if (!hasSufficientRestaurantConfidence(ctx)) return const [];
    final max30 = ctx.rolling90DaySales.values.fold(0, max);
    final out = <SourceCandidate>[];
    for (final p in ctx.allProducts) {
      final sales = _log1pScaled(ctx.rolling90DaySales[p.id] ?? 0, max30);
      final trend = _mustTryTrend(p, ctx);
      if (sales <= 0 && trend <= 0) continue; // no signal at all -> contributes nothing
      final rawScore = (sales * 0.65 + trend * 0.35).clamp(0.0, 1.0);
      final score = _applyBusinessContextMultiplier(rawScore, p, ctx);
      if (score > 0) out.add(SourceCandidate(p.id, score));
    }
    return out;
  }

  /// Similar/Complementary Products - reuses crossSellFrequency (vendor-
  /// configured recommendedProductIds tallied across the menu), the same
  /// data "Pairs Well With" uses, read a second time for a different
  /// purpose. Zero new reads. This is the only viable "similar/
  /// complementary" signal available without new tracking - there is no
  /// per-order co-purchase data anywhere to build a real "customers who
  /// bought X also bought Y" correlation. Does NOT touch fillPairsWellWith/
  /// the pairs-well-with panel - that keeps reading crossSellFrequency
  /// directly, unchanged.
  static List<SourceCandidate> _sourceSimilar(RestaurantRecommendationContext ctx) {
    final maxCross = ctx.crossSellFrequency.values.fold(0, max);
    final out = <SourceCandidate>[];
    for (final p in ctx.allProducts) {
      final s = _linearScaled(ctx.crossSellFrequency[p.id] ?? 0, maxCross);
      if (s > 0) out.add(SourceCandidate(p.id, s));
    }
    return out;
  }

  /// "Products this customer has never interacted with, that the
  /// restaurant has real sales confidence in" - gated by
  /// hasSufficientRestaurantConfidence (sales volume is the magnitude here,
  /// so it needs the same confidence floor as Best Sellers/Must Try) and by
  /// real customer behavior existing at all (a Stage-0 customer has nothing
  /// to have "never interacted with" in a meaningful sense - everything is
  /// equally novel, which isn't a signal). Pulled into its own function so
  /// the confidence-bar's dominant-label selection (recommendationConfidenceScores)
  /// can reuse the exact same formula instead of a second, drifting copy.
  static double _neverInteractedRaw(ProductModel p, RestaurantRecommendationContext ctx) {
    if (ctx.behaviorSummary.isEmpty || !hasSufficientRestaurantConfidence(ctx)) return 0.0;
    final neverInteracted =
        (ctx.behaviorSummary.productViewCounts[p.id] ?? 0) == 0 &&
            (ctx.behaviorSummary.productOrderQuantities[p.id] ?? 0) == 0;
    if (!neverInteracted) return 0.0;
    final maxSales = ctx.rolling90DaySales.values.fold(0, max);
    return _log1pScaled(ctx.rolling90DaySales[p.id] ?? 0, maxSales) * 0.7;
  }

  /// Discovery: real candidate generation from two buildable sub-signals -
  /// "products this customer has never interacted with" (_neverInteractedRaw
  /// above) and "hidden gems" (Section below, reused directly so Discovery
  /// and the standalone hiddenGems() never define "gem" differently). Both
  /// sub-signals are gated by hasSufficientRestaurantConfidence (directly
  /// here, and internally inside _hiddenGemProductScore) - a restaurant
  /// with insufficient sales history has no real "worth trying"/"gem"
  /// signal to offer yet, so this source simply contributes nothing rather
  /// than falling back to randomness (removed 2026-07-18 - "must not
  /// generate fake recommendations" in a complete cold start means an empty
  /// Discovery source should mean "Discovery has nothing to say", not "show
  /// random products so the section never looks empty" - see
  /// RECOMMENDATION_SYSTEM_ARCHITECTURE.html for the full rationale).
  static List<SourceCandidate> _sourceDiscovery(RestaurantRecommendationContext ctx) {
    final out = <SourceCandidate>[];
    for (final p in ctx.allProducts) {
      final score = max(_neverInteractedRaw(p, ctx), _hiddenGemProductScore(p, ctx));
      if (score > 0) out.add(SourceCandidate(p.id, score));
    }
    return out;
  }
  // "Newly added products" is now built - see _sourceNewProduct below
  // (2026-07-18), consuming ProductModel.createdAt, which is optional and
  // never faked/backfilled (see that field's doc comment). "Seasonal
  // products" remains fully deferred - no seasonal-flag field exists
  // anywhere, and Season-Readiness (architecture doc Section 18) explicitly
  // keeps it that way until real historical data exists.

  static const Duration _newProductWindow = Duration(days: 14);
  // Small on purpose - "a very small temporary boost", must never let mere
  // recency outrank real popularity/personalization signals whose max is 1.0.
  static const double _newProductMaxBoost = 0.3;

  /// New-product freshness signal. Deliberately NOT gated by
  /// hasSufficientRestaurantConfidence - "this was added recently" is a
  /// factual observation, not a popularity claim, so a brand-new restaurant
  /// can still showcase its latest dishes even before it has enough sales
  /// history for the popularity-based sections to activate. Contributes
  /// nothing today for any product without a real createdAt (i.e. every
  /// product created before this field existed) - not an error, just no
  /// signal, exactly like every other gated source in this file.
  static List<SourceCandidate> _sourceNewProduct(RestaurantRecommendationContext ctx) {
    final now = DateTime.now();
    final out = <SourceCandidate>[];
    for (final p in ctx.allProducts) {
      final createdAt = p.createdAt?.toDate();
      if (createdAt == null) continue;
      final age = now.difference(createdAt);
      if (age.isNegative || age > _newProductWindow) continue;
      final freshness = 1.0 - (age.inHours / _newProductWindow.inHours);
      if (freshness > 0) out.add(SourceCandidate(p.id, freshness * _newProductMaxBoost));
    }
    return out;
  }

  // ── Explorer Score: dynamic source-weight adjustment (2026-07-17) ──────
  //
  // _baseSourceWeights is both the original static calibration AND, by
  // construction, exactly what a customer with discoveryPreferenceScore ==
  // 0.5 gets (see sourceWeightsFor below) - since a brand-new/signal-less
  // customer's score also defaults to exactly 0.5 (see
  // BehaviorSummarySnapshot.discoveryPreferenceScore's all-empty case),
  // this guarantees Stage 0 and "balanced" customers are unaffected by this
  // feature, matching every other "purely additive" guarantee in this engine.
  // 'businessContext' (2026-07-19, weight revised same day per product
  // review - was 0.95, now 0.55) is a MODERATE boost, deliberately placed
  // below every real-behavior/popularity source (preference, bestSeller,
  // mustTry, similar) - "Restaurant Type should guide recommendations, not
  // define them... User behaviour and actual restaurant performance should
  // remain the primary decision makers." Sitting just below 'discovery'
  // keeps it a genuine, felt contribution without ever becoming the
  // second-strongest signal. Deliberately absent from _explorerWeightDelta
  // below, same treatment as 'newProduct' - a fixed weight regardless of
  // Explorer Score, since Explorer Score is explicitly unchanged by this
  // feature.
  // Recommendation Configuration (2026-07-22): was a `static const Map`
  // with the literal values now shown as this getter's fallback-free
  // source - RecommendationConfig.current already defaults to these exact
  // numbers (see RecommendationConfig.defaults()), so this getter produces
  // byte-for-byte the same map as the old const one until an admin changes
  // a value in the Admin Panel. Every reader of _baseSourceWeights
  // (sourceWeightsFor, computeMergedScores' default) is unchanged - only
  // the values feeding it moved from hardcoded literals to cached config.
  static Map<String, double> get _baseSourceWeights {
    final c = RecommendationConfig.current;
    return {
      'preference': c.preferenceWeight / 100,
      'bestSeller': c.bestSellerWeight / 100,
      'mustTry': c.restaurantSpecialitiesWeight / 100,
      'similar': c.vendorRecommendationPreferenceWeight / 100,
      'discovery': c.discoveryWeight / 100,
      'businessContext': c.businessContextWeight / 100,
      'newProduct': c.newProductBoostWeight / 100,
    };
  }

  // How far each source's weight swings toward the EXPLORER extreme
  // (discoveryPreferenceScore == 1.0); the LOYAL extreme (score == 0.0)
  // swings the opposite direction by the same amount, then everything is
  // clamped to [0,1] (required for the noisy-OR merge's probability
  // interpretation above to stay valid - a weight > 1 could make
  // `effective` exceed 1, which breaks the (1-effective) survival-
  // probability math). Some sources are already at/near their base
  // ceiling/floor, so their swing room is asymmetric in practice - e.g.
  // preference is already at the max 1.00, so it can only decrease for
  // explorers, not increase further for loyal customers. That's expected,
  // not a bug: preference was already the single most-trusted source.
  static const Map<String, double> _explorerWeightDelta = {
    'preference': -0.25, // explorers: personal history matters somewhat less
    'bestSeller': -0.15, // explorers: "safe" best-sellers matter somewhat less
    'mustTry': 0.20, // explorers: Restaurant Must Try matters more
    'similar': -0.20, // loyal-favored per spec; decreases for explorers
    'discovery': 0.35, // the most literal match - biggest swing
  };

  /// Per-source reliability weights for one customer, derived from their
  /// Explorer Score. Loyal customers naturally lean toward
  /// preference/similar; explorers naturally lean toward mustTry/discovery
  /// - dynamically, via continuous weight adjustment, never a fixed
  /// percentage or reserved slot.
  static Map<String, double> sourceWeightsFor(double discoveryPreferenceScore) {
    final t = (discoveryPreferenceScore.clamp(0.0, 1.0) - 0.5) * 2; // -1(loyal)..0(balanced)..+1(explorer)
    return _baseSourceWeights.map((name, base) {
      final delta = (_explorerWeightDelta[name] ?? 0.0) * t;
      return MapEntry(name, (base + delta).clamp(0.0, 1.0));
    });
  }

  static final Map<String, CandidateSource> defaultSources = {
    'preference': _sourcePreference,
    'businessContext': _sourceBusinessContext,
    'bestSeller': _sourceBestSeller,
    'mustTry': _sourceMustTry,
    'similar': _sourceSimilar,
    'discovery': _sourceDiscovery,
    'newProduct': _sourceNewProduct,
  };

  // ── Merge: noisy-OR, weighted by source reliability ─────────────────────

  /// This is the entire dynamic-allocation mechanism: no source ever
  /// reserves a slot or percentage. Each source proposes 0..N candidates
  /// with its own 0..1 score; this function is the ONLY place scores from
  /// different sources combine, and it's how a product proposed by
  /// multiple sources ends up appearing exactly once with one combined
  /// score instead of being shown twice.
  ///
  /// effective_i = clamp(score_i,0,1) * weight(source_i)
  /// combined = 1 - Π(1 - effective_i)
  ///
  /// A single strong source reproduces its own score exactly. A second
  /// source touching the same product only ever increases the combined
  /// score (never decreases), saturating smoothly toward 1.0 - neither
  /// double-counting (plain sum, can exceed any sane bound) nor discarding
  /// weak-but-real corroboration (plain max).
  ///
  /// Source weights default to sourceWeightsFor(ctx's own Explorer Score) -
  /// this is the dynamic-allocation mechanism for the Explorer Score
  /// feature: a loyal customer's merge naturally leans on
  /// preference/similar, an explorer's naturally leans on mustTry/discovery,
  /// with zero special-casing anywhere else in this file (menu reorder and
  /// the pairs-well-with fill both call this function and inherit the
  /// adjustment automatically). [weights] lets a caller override for
  /// testing/tuning; omit it for normal use.
  static Map<String, double> computeMergedScores(RestaurantRecommendationContext ctx,
      {Map<String, CandidateSource>? sources, Map<String, double>? weights}) {
    final active = sources ?? defaultSources;
    final activeWeights =
        weights ?? sourceWeightsFor(ctx.behaviorSummary.discoveryPreferenceScore);
    final survival = <String, double>{};
    active.forEach((name, source) {
      final weight = activeWeights[name] ?? 1.0;
      for (final c in source(ctx)) {
        if (c.score <= 0) continue;
        final effective = c.score.clamp(0.0, 1.0) * weight;
        survival[c.productId] = (survival[c.productId] ?? 1.0) * (1 - effective);
      }
    });
    return survival.map((id, s) => MapEntry(id, 1 - s));
  }

  /// Raw per-source scores, for callers that need one specific source's own
  /// ranking untouched by the merge (Restaurant Must Try's own section,
  /// "Based On Your Taste", and fillPairsWellWith's preference/bestSeller
  /// tie-break inputs).
  static Map<String, double> scoreBySource(
      RestaurantRecommendationContext ctx, String sourceName) {
    final source = defaultSources[sourceName];
    if (source == null) return {};
    return {for (final c in source(ctx)) c.productId: c.score};
  }

  /// Top [n] products ranked by ONE source's own score alone (not the
  /// cross-source merge) - used for sections that represent a single,
  /// named signal (Restaurant Must Try, "Based On Your Taste") rather than
  /// the blended "Recommended For You" list. No diversity pass - these are
  /// already small, curated-by-construction lists (see _selectDiverse's
  /// doc comment for why diversifying a 5-item signature-dish list would
  /// be counterproductive).
  /// [categoryFirst] (2026-07-23, explicit product direction) - when true,
  /// category preference rank becomes the PRIMARY sort key and this
  /// source's own score becomes secondary, same technique as
  /// recommendForYou/hiddenGems below. Defaults to false so every existing
  /// caller (Restaurant Must Try, Hidden Gems' Specialities backfill on the
  /// Sparkle screen) keeps its exact current behavior unchanged - only
  /// Based on Your Taste's 'preference' call site opts in.
  /// [businessContextBoost] (2026-07-23, explicit product direction: "also
  /// use business context for based on your taste") - when true, applies
  /// the same boost-only, up-to-+25% multiplier (_applyBusinessContextMultiplier)
  /// every other single-source section already gets (Restaurant Must Try
  /// via _sourceMustTry, Hidden Gems, Most Loved Here) to this source's raw
  /// scores before ranking/allocation. Defaults to false so 'mustTry'
  /// callers are unaffected (that source already boosts itself internally -
  /// applying it twice would double-count) and any future caller of this
  /// function keeps today's behavior unless it opts in. Only Based on Your
  /// Taste's 'preference' call site passes true - _sourcePreference itself
  /// (also used as RFY's 'preference' merge source, which already has its
  /// own independent 'businessContext' merge source) stays untouched, so
  /// this never changes Recommended For You.
  static List<ProductModel> topBySource(
      RestaurantRecommendationContext ctx, String sourceName,
      {int n = defaultSectionLimit, bool categoryFirst = false, bool businessContextBoost = false}) {
    final rawScores = scoreBySource(ctx, sourceName);
    if (rawScores.isEmpty) return const [];
    Map<String, double> scores;
    if (businessContextBoost) {
      final byId = {for (final p in ctx.allProducts) p.id: p};
      scores = {
        for (final entry in rawScores.entries)
          if (byId[entry.key] != null)
            entry.key: _applyBusinessContextMultiplier(entry.value, byId[entry.key]!, ctx)
      };
    } else {
      scores = rawScores;
    }
    final indexed = ctx.allProducts
        .asMap()
        .entries
        .where((e) => (scores[e.value.id] ?? 0) > 0)
        .toList();
    if (!categoryFirst) {
      indexed.sort((a, b) {
        final sa = scores[a.value.id] ?? 0, sb = scores[b.value.id] ?? 0;
        final cmp = sb.compareTo(sa);
        return cmp != 0 ? cmp : a.key.compareTo(b.key);
      });
      return indexed.map((e) => e.value).take(n).toList();
    }

    // categoryFirst: dynamic per-category slot allocation (2026-07-23),
    // same mechanism as recommendForYou/hiddenGems - see
    // _categorySlotAllocation's own doc comment.
    final categoryRank = _categoryRankIndex(ctx);
    indexed.sort((a, b) {
      final catA = categoryRank[a.value.categoryID] ?? categoryRank.length;
      final catB = categoryRank[b.value.categoryID] ?? categoryRank.length;
      if (catA != catB) return catA.compareTo(catB);
      final sa = scores[a.value.id] ?? 0, sb = scores[b.value.id] ?? 0;
      final cmp = sb.compareTo(sa);
      return cmp != 0 ? cmp : a.key.compareTo(b.key);
    });
    final ranked = indexed.map((e) => e.value).toList();
    final slots = _categorySlotAllocation(ranked, ctx, n);
    return _selectByCategoryAllocation(ranked, slots);
  }

  // ── Diversity: near-duplicate detection, zero NLP ───────────────────────

  static const Set<String> _qualifierWords = {
    'family', 'mini', 'half', 'full', 'combo', 'special', 'large', 'small',
    'regular', 'medium', 'jumbo', 'xl', 'xs', 'single', 'double', 'triple',
    'pack', 'meal', 'box', 'plate', 'bowl', 'piece', 'pcs', 'pc', 'deluxe',
    'classic', 'value',
  };

  static Set<String> _coreTokens(String name) {
    final tokens = name.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((t) => t.isNotEmpty);
    return tokens
        .where((t) => !_qualifierWords.contains(t) && !RegExp(r'^\d+$').hasMatch(t))
        .toSet();
  }

  static double _nameSimilarity(String a, String b) {
    final ta = _coreTokens(a), tb = _coreTokens(b);
    if (ta.isEmpty || tb.isEmpty) return 0.0;
    return ta.intersection(tb).length / ta.union(tb).length; // Jaccard
  }

  static const double _duplicateSimilarityThreshold = 0.5;
  static const int _diversityMinMenuSize = 10;

  /// Union-find over pairwise name-similarity - menus are small (tens of
  /// items, not thousands), so O(n^2) pairwise comparison is cheap
  /// on-device. Groups e.g. "Chicken Biryani"/"Family Chicken Biryani"/
  /// "Mini Chicken Biryani"/"Chicken Biryani Combo" into one family (all
  /// strip to {chicken, biryani}), while correctly keeping "Veg Biryani"
  /// ({veg, biryani}) separate (similarity 0.33, below threshold).
  static Map<String, int> _computeDishFamilies(List<ProductModel> products) {
    final parent = <String, String>{for (final p in products) p.id: p.id};
    String find(String x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]!]!;
        x = parent[x]!;
      }
      return x;
    }
    void union(String a, String b) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }
    for (var i = 0; i < products.length; i++) {
      for (var j = i + 1; j < products.length; j++) {
        if (_nameSimilarity(products[i].name, products[j].name) >=
            _duplicateSimilarityThreshold) {
          union(products[i].id, products[j].id);
        }
      }
    }
    final groupIds = <String, int>{};
    final result = <String, int>{};
    for (final p in products) {
      final root = find(p.id);
      final gid = groupIds.putIfAbsent(root, () => groupIds.length);
      result[p.id] = gid;
    }
    return result;
  }

  /// [ranked] must already be sorted best-first. Picks at most one product
  /// per dish family, then backfills with the next-best remaining products
  /// if that leaves the list under [limit] - never under-fills just to
  /// enforce variety. Below _diversityMinMenuSize total menu items, the
  /// strict pass is skipped entirely (quality over artificial variety on a
  /// small menu, exactly as requested).
  ///
  /// Final re-sort (2026-07-19, audit fix): SELECTION (family computation,
  /// primary pass, backfill) is completely unchanged above - this only fixes
  /// PRESENTATION. Without it, a family member deferred to the backfill pass
  /// always lands at the very end of [chosen] regardless of its own score,
  /// which could show it below several lower-scored, different-family items
  /// - a real confidence-badge/display-order inconsistency (a later position
  /// showing a HIGHER badge than an earlier one), confirmed via the
  /// synthetic-dataset audit (RECOMMENDATION_ENGINE_AUDIT_REPORT.md). Once
  /// selection has decided the final SET of products (unaffected by this),
  /// re-sorting that set back into [ranked]'s own order restores strict
  /// score-descending display order for whatever was chosen - it can never
  /// add back an excluded family member, so the real diversity guarantee
  /// (at most one family member wins a slot when genuine choice exists,
  /// i.e. limit < distinct family count) is untouched. Adjacency between
  /// same-family items can still occur, but ONLY in the backfill-forced-full-
  /// inclusion case where every candidate was going to be shown anyway (no
  /// exclusion was actually happening) - deliberate: score ordering takes
  /// precedence over duplicate spacing once nothing is actually being
  /// excluded, per explicit product decision.
  /// Family-dedup ONLY (2026-07-23, extracted from the former
  /// _selectDiverse) - at most one product per dish family survives,
  /// [ranked]'s own relative order is otherwise preserved, no truncation to
  /// any limit and no backfill. Below _diversityMinMenuSize total menu
  /// items, the strict pass is skipped entirely (quality over artificial
  /// variety on a small menu), matching the original rule exactly.
  /// _categorySlotAllocation/_selectByCategoryAllocation below now own the
  /// job _selectDiverse's old truncate+backfill used to do - the dynamic
  /// per-category quota walk (see those functions) naturally cascades to
  /// the next-best remaining candidate once a category's quota won't
  /// stretch further, so a separate backfill pass is no longer needed.
  static List<ProductModel> _dedupFamilies(
      List<ProductModel> ranked, List<ProductModel> allProducts) {
    if (allProducts.length < _diversityMinMenuSize) {
      return List<ProductModel>.from(ranked);
    }
    final families = _computeDishFamilies(allProducts);
    final out = <ProductModel>[];
    final usedFamilies = <int>{};
    for (final p in ranked) {
      final fam = families[p.id];
      if (fam != null && usedFamilies.contains(fam)) continue;
      out.add(p);
      if (fam != null) usedFamilies.add(fam);
    }
    return out;
  }

  // ── Dynamic category slot allocation (2026-07-23) ───────────────────────
  //
  // Evolves the category-first sort (categoryRank as the primary sort key,
  // product score secondary) into genuine DYNAMIC ALLOCATION: instead of
  // just sorting by category then truncating to [limit] (which lets one
  // dominant category silently claim every slot whenever it has enough
  // eligible products), this decides HOW MANY of the final [limit] slots
  // each category should contribute, before picking which products fill
  // them.
  //
  // Inputs, exactly as specified:
  //   - customer category preference STRENGTH -> categoryInteractionCounts,
  //     log1p-normalized against the max among categories that actually
  //     have eligible candidates (a category with signal but zero real
  //     products here can't skew the comparison)
  //   - eligible-candidate COUNT per category -> caps how many slots a
  //     category can even use ("data availability")
  //   - the total [limit]
  //
  // Method: capacity-constrained largest-remainder apportionment (the same
  // family of algorithm political seat allocation uses) - proportional by
  // construction, so higher preference naturally receives more slots
  // without ever being forced to an equal split, and a category is never
  // allocated more than it has real candidates for.
  static Map<String, int> _categorySlotAllocation(List<ProductModel> dedupedRanked,
      RestaurantRecommendationContext ctx, int limit) {
    final eligibleByCategory = <String, List<ProductModel>>{};
    final categoryOrder = <String>[]; // first-appearance order = category-rank order already
    for (final p in dedupedRanked) {
      if (!eligibleByCategory.containsKey(p.categoryID)) categoryOrder.add(p.categoryID);
      eligibleByCategory.putIfAbsent(p.categoryID, () => []).add(p);
    }
    if (categoryOrder.isEmpty || limit <= 0) return const {};

    final rawWeights = <String, int>{
      for (final cat in categoryOrder)
        cat: ctx.behaviorSummary.categoryInteractionCounts[cat] ?? 0
    };
    final maxRaw = rawWeights.values.fold(0, max);
    // No differentiating signal anywhere (Stage 0, or genuinely no category
    // interaction on this menu yet) -> every category ties at equal weight.
    // This is an honest degrade, not a "forced" equal split - there is
    // simply no real preference to weight by yet, same philosophy as every
    // other cold-start fallback in this file.
    final weights = <String, double>{
      for (final cat in categoryOrder)
        cat: maxRaw > 0 ? _log1pScaled(rawWeights[cat]!, maxRaw) : 1.0
    };
    final totalWeight = weights.values.fold(0.0, (a, b) => a + b);

    final caps = {for (final cat in categoryOrder) cat: eligibleByCategory[cat]!.length};
    final idealQuota = <String, double>{
      for (final cat in categoryOrder)
        cat: totalWeight > 0
            ? (weights[cat]! / totalWeight) * limit
            : limit / categoryOrder.length
    };

    // Floor pass, capped at each category's own eligible count - "never
    // force impossible allocations."
    final slots = <String, int>{};
    var allocated = 0;
    for (final cat in categoryOrder) {
      final floorSlots = min(idealQuota[cat]!.floor(), caps[cat]!);
      slots[cat] = floorSlots;
      allocated += floorSlots;
    }

    // Largest-remainder leftover pass: hand out any slots the floor pass
    // left unassigned one at a time to whichever category still has room
    // (below its cap) and the largest remaining fractional need. A
    // category with genuinely zero preference weight has zero fractional
    // need and can never win a leftover slot over one with real - however
    // small - weight, which is what "guarantee category diversity" means
    // here: real secondary preference is never rounded away to zero purely
    // by floor() truncation, but a category with NO signal at all is never
    // fabricated a slot either.
    var remaining = limit - allocated;
    while (remaining > 0) {
      String? pick;
      // -infinity, not a small negative constant (bug fixed 2026-07-23): a
      // category that keeps absorbing leftover rounds has "need" =
      // idealQuota - slots that can fall arbitrarily far below any fixed
      // sentinel (idealQuota stays constant while slots keeps growing) - a
      // finite sentinel could out-rank every real, still-has-room
      // candidate and wrongly end the loop early, under-allocating even
      // though categories with real capacity remain.
      var bestNeed = double.negativeInfinity;
      for (final cat in categoryOrder) {
        if (slots[cat]! >= caps[cat]!) continue;
        final need = idealQuota[cat]! - slots[cat]!;
        if (need > bestNeed) {
          bestNeed = need;
          pick = cat;
        }
      }
      if (pick == null) break; // every category is capped out - can't allocate further
      slots[pick] = slots[pick]! + 1;
      remaining--;
    }
    return slots;
  }

  /// Walks [dedupedRanked] (already category-rank-primary, product-score-
  /// secondary ordered) once, taking a product only while its category
  /// still has quota left from [slotsByCategory] - so the result is exactly
  /// the top-scoring products from each category, up to that category's
  /// allocated slot count, still in the same category-then-score display
  /// order. Naturally returns fewer than the original [limit] if the total
  /// eligible pool is smaller than [limit] (same graceful shortfall
  /// behavior the old truncate+backfill selection had).
  static List<ProductModel> _selectByCategoryAllocation(
      List<ProductModel> dedupedRanked, Map<String, int> slotsByCategory) {
    final remaining = Map<String, int>.from(slotsByCategory);
    final chosen = <ProductModel>[];
    for (final p in dedupedRanked) {
      final left = remaining[p.categoryID] ?? 0;
      if (left <= 0) continue;
      chosen.add(p);
      remaining[p.categoryID] = left - 1;
    }
    return chosen;
  }

  // ── Final selection ──────────────────────────────────────────────────

  /// Applies the restaurant-quality boost and clamps back to 0..1 - the
  /// single normalization step every consumer-facing score (ranking AND
  /// the confidence bar) goes through last. This is a GUARANTEED invariant,
  /// not an incidental fact: computeMergedScores' noisy-OR construction
  /// combined with sourceWeightsFor's own 0..1 weight clamping already
  /// mathematically keeps [raw] in [0,1) before this ever runs, and this
  /// final clamp is what keeps the promise even if a future source/weight/
  /// boost formula's math doesn't - adding a 7th, 8th, ... candidate
  /// source can never push a displayed confidence value above 100% or
  /// below 0%, by construction, forever.
  static double _normalizeConfidence(double raw, double boostFactor) =>
      (raw * boostFactor).clamp(0.0, 1.0);

  /// The ONE final normalized score - computeMergedScores + the restaurant-
  /// quality boost + _normalizeConfidence's clamp, all in one place.
  /// Correction (2026-07-18): previously recommendForYou and
  /// recommendationConfidenceScores each inlined this same 3-step sequence
  /// separately, and fillPairsWellWith's caller passed the RAW (pre-boost)
  /// computeMergedScores output for ranking while the confidence badge on
  /// those same cards showed the POST-boost value - two different numbers
  /// that could disagree about which of two products should rank higher.
  /// Every caller that both ranks products AND may display a confidence
  /// value for them MUST use this function for both, never mix it with raw
  /// computeMergedScores - see fillPairsWellWith's call site
  /// (_resolvedPairsWellWith in newVendorProductsScreen.dart) for why this
  /// matters in practice.
  static Map<String, double> normalizedMergedScores(RestaurantRecommendationContext ctx,
      {Map<String, CandidateSource>? sources, Map<String, double>? weights}) {
    final merged = computeMergedScores(ctx, sources: sources, weights: weights);
    final boostFactor = 1 + restaurantQualityBoost(ctx.vendor);
    return merged.map((id, s) => MapEntry(id, _normalizeConfidence(s, boostFactor)));
  }

  /// The blended "Recommended For You" list: merges all 6 sources
  /// (computeMergedScores), applies the small uniform restaurant-quality
  /// boost once across the whole result, then diversifies. This is the
  /// ONLY section that uses the full cross-source merge - Restaurant Must
  /// Try/Most Loved Here/Discovery-page sections each read one source's
  /// own ranking via topBySource, keeping their identity as distinct,
  /// named signals rather than collapsing into one generic list.
  static List<ProductModel> recommendForYou(RestaurantRecommendationContext ctx,
      {int limit = defaultSectionLimit,
      Map<String, CandidateSource>? sources,
      Map<String, double>? weights}) {
    final boosted = normalizedMergedScores(ctx, sources: sources, weights: weights);
    if (boosted.isEmpty) return const [];

    final indexed = ctx.allProducts
        .asMap()
        .entries
        .where((e) => (boosted[e.value.id] ?? 0) > 0)
        // Combo Recommendation Rules, Section 2: never recommended by
        // default - a combo only competes for a slot here once real
        // per-customer evidence supports it (comboEligibilityScore), never
        // merely because its category/preference/best-seller score is
        // high. Individual products are entirely unaffected and simply
        // fill the list as they already did before this existed.
        .where((e) => !e.value.isCombo ||
            comboEligibilityScore(e.value, ctx) >= comboEligibilityThreshold)
        .toList();

    // Cap eligible combos to comboSlotAllocation (2026-07-25: dynamic,
    // customer-adaptive - see that function's own doc comment - replaces
    // the old flat maxComboRecommendationsPerSection here specifically)
    // BEFORE ranking/diversifying - keep only the highest-scoring ones if
    // more qualify, so _selectDiverse's backfill (which walks this same
    // list) can never reintroduce an excess combo either.
    final comboSlots = comboSlotAllocation(limit, ctx);
    final eligibleCombos = indexed.where((e) => e.value.isCombo).toList()
      ..sort((a, b) => (boosted[b.value.id] ?? 0).compareTo(boosted[a.value.id] ?? 0));
    if (eligibleCombos.length > comboSlots) {
      final dropIds = eligibleCombos
          .skip(comboSlots)
          .map((e) => e.value.id)
          .toSet();
      indexed.removeWhere((e) => dropIds.contains(e.value.id));
    }

    // Category-first, product-second (2026-07-23, explicit product
    // direction) - category preference is now the PRIMARY sort key, real
    // product score the SECONDARY one. Scoring itself (computeMergedScores/
    // normalizedMergedScores, all 7 sources, Explorer Score weighting) is
    // completely untouched - only the final ordering changes, same
    // technique as the combo partition immediately below it.
    final categoryRank = _categoryRankIndex(ctx);
    indexed.sort((a, b) {
      // Combo Recommendation Rules: individual products ALWAYS sort before
      // combos, regardless of score/category - a combo clearing the
      // eligibility bar only ever competes for a position among other
      // combos, never against individual dishes. Same dominant-partition
      // technique used in fillPairsWellWith's filler comparator.
      final comboA = a.value.isCombo ? 1 : 0;
      final comboB = b.value.isCombo ? 1 : 0;
      if (comboA != comboB) return comboA.compareTo(comboB);
      // PRIMARY: category preference rank (lower = more preferred).
      final catA = categoryRank[a.value.categoryID] ?? categoryRank.length;
      final catB = categoryRank[b.value.categoryID] ?? categoryRank.length;
      if (catA != catB) return catA.compareTo(catB);
      // SECONDARY: real product score, descending.
      final sa = boosted[a.value.id] ?? 0, sb = boosted[b.value.id] ?? 0;
      final cmp = sb.compareTo(sa);
      return cmp != 0 ? cmp : a.key.compareTo(b.key);
    });
    final ranked = indexed.map((e) => e.value).toList();
    // Dynamic category slot allocation (2026-07-23) replaces the old
    // truncate+backfill selection - family-dedup first (unchanged rule),
    // then decide how many slots each category earns (preference strength
    // + eligible count + limit), then fill those slots with each
    // category's own top-scoring products.
    //
    // Combos are deliberately kept OUT of the category quota math (fix,
    // same day): a combo often shares its category with individual dishes
    // (e.g. a Naan combo filed under "Main Course" alongside plain Naan),
    // and budgeting it against that category's cap could starve it of a
    // slot purely because its own category's individuals already used the
    // full quota - even though "individuals before combos, never first"
    // was always meant to guarantee combos a LOWER-priority slot once
    // eligible individuals are satisfied, not exclude them outright.
    // Combos stay the separate trailing bucket they were before this
    // feature existed - filling whatever room individuals didn't use, but
    // now ALSO capped at comboSlots (2026-07-25) even if individuals left
    // more room than that: a small/sparse-category menu where individual
    // slot allocation naturally falls short of [limit] must not let combos
    // silently absorb the whole shortfall and overshoot their intended
    // ratio - "never dominate a section" is about the ratio actually
    // shown, not just "whatever's left over".
    final deduped = _dedupFamilies(ranked, ctx.allProducts);
    final dedupedIndividuals = deduped.where((p) => !p.isCombo).toList();
    final dedupedCombos = deduped.where((p) => p.isCombo).toList();
    final slots = _categorySlotAllocation(dedupedIndividuals, ctx, limit);
    final chosenIndividuals = _selectByCategoryAllocation(dedupedIndividuals, slots);
    final remainingRoom = min(limit - chosenIndividuals.length, comboSlots);
    final chosenCombos =
        remainingRoom > 0 ? dedupedCombos.take(remainingRoom).toList() : const <ProductModel>[];
    return [...chosenIndividuals, ...chosenCombos];
  }

  // ── Recommendation-confidence bar (2026-07-18) ──────────────────────────

  // Below this, no bar shows AT ALL - not a faint/weak one. "The green bar
  // should only appear when the recommendation engine is genuinely
  // confident... do not display a weak recommendation indicator for every
  // product" (explicit product direction). Configurable in one place.
  static const double minimumRecommendationConfidence = 0.40;

  // "Based on Your Searches" requires more than a single typed keyword -
  // at least the Opened-restaurant tier (30%, see
  // BehaviorSummarySnapshot.searchConfidenceFor) before it's eligible to be
  // the DISPLAYED reason, even though a bare "Typed" (10%) query already
  // contributes to _sourcePreference's internal score.
  static const double _searchConfidenceLabelThreshold = 0.3;

  /// Per-product confidence score - via normalizedMergedScores, the SAME
  /// final score recommendForYou's ranking uses (and, since 2026-07-18,
  /// fillPairsWellWith's ordering too - see normalizedMergedScores' own
  /// doc comment), GUARANTEED to stay within 0..1 (0-100% on the UI bar)
  /// no matter how many candidate sources this engine grows to in the
  /// future - plus a single customer-facing label naming
  /// whichever real signal contributes the most for that product -
  /// "transparent... while keeping the UI simple" (explicit product
  /// direction). Computed once per restaurant-page visit, for every
  /// product on the menu (not just the curated top-5 sections), so callers
  /// should call this once and look products up by id rather than
  /// recomputing per card.
  ///
  /// Label mapping (7 total, deliberately small - "avoid introducing many
  /// similar labels"):
  /// - 🔥 mostOrdered  <- bestSeller source dominant
  /// - ❤️ matchesYourTaste <- EITHER behaviorAffinity (restaurant visits/
  ///   favorites/product views&orders) OR categoryMatch (cross-restaurant
  ///   cuisine affinity) dominant - both share ONE label on purpose:
  ///   "customers think about foods they enjoy, not restaurants or cuisines
  ///   by name" - the engine still computes/weighs these two signals
  ///   completely independently everywhere else (_sourcePreference,
  ///   sourceWeightsFor), only the DISPLAYED label is merged.
  /// - 🔍 basedOnSearches <- search confidence dominant, gated by
  ///   _searchConfidenceLabelThreshold
  /// - 💰 fitsYourBudget: no longer selectable as the displayed label at all
  ///   (2026-07-20, revised same day - was "computed/selected, only the UI
  ///   hides it," now excluded from the label vote itself so a real score
  ///   isn't wasted behind a hidden badge). Price compatibility still feeds
  ///   the actual SCORE via _tasteProfileScore, just never wins the label.
  /// - ✨ worthTrying <- "never interacted with, restaurant has real sales
  ///   confidence in it" dominant
  /// - 💎 hiddenGem <- hidden-gem score dominant
  /// - ⭐ popularChoice <- generic fallback, used whenever nothing above
  ///   qualifies as the dominant signal - this INCLUDES a mustTry-dominant
  ///   product (Restaurant Must Try is fully automatic, no human curator,
  ///   so it deliberately gets no dedicated label - see file header) and a
  ///   similar/newProduct-dominant product (neither has a dedicated label
  ///   either - both are honest, real signals, just not ones with their
  ///   own customer-facing story).
  ///
  /// Stage 0 (ctx.behaviorSummary.isEmpty): every personalized label above
  /// is skipped entirely (not just scored low) - only mostOrdered/
  /// popularChoice are reachable, matching "never display personalised
  /// labels" when there is no customer behavior at all yet.
  ///
  /// ── LAUNCH MODE override (2026-07-20) ───────────────────────────────
  /// Explicit product direction to ship fast: for now, the badge only ever
  /// shows Popular Choice or Most Ordered, decided by a dead-simple raw
  /// sales-count rule below, instead of the full noisy-OR + label-vote
  /// system above. Nothing else is removed or disabled - every source,
  /// every weight, every bit of data collection (dailyProductSales,
  /// behaviorSummary, search confidence, etc.) keeps running exactly as
  /// before, and ranking (recommendForYou/topBySource/hiddenGems/
  /// mostLovedHere - i.e. WHICH products appear in each carousel) is
  /// entirely untouched by this flag; it only affects what THIS function
  /// returns for the badge widget's label/fill.
  ///
  /// Superseded 2026-07-21 by the dynamic role-aware allocation below
  /// (_useDynamicRoleAwareBadgeLogic, checked first in
  /// recommendationConfidenceScores) - this flat-percentage version is
  /// kept fully intact and unreached rather than deleted, exactly like the
  /// full label-vote system it itself superseded. Flip
  /// _useDynamicRoleAwareBadgeLogic to false to fall back to this, or both
  /// flags to false to restore the original label-vote system.
  static bool _useSimpleLaunchBadgeLogic = true;
  static const int _launchPopularChoiceMinOrders = 20; // 90-day window
  static const int _launchMostOrderedMinOrders7Day = 50; // 7-day window

  /// ── DYNAMIC ROLE-AWARE BADGE ALLOCATION (2026-07-21) ────────────────
  /// Replaces the flat "20% of everything" rule above with a size-scaled,
  /// role-aware allocation, per explicit product direction. Supersedes
  /// _useSimpleLaunchBadgeLogic (kept intact above, just unreached).
  ///
  /// 1. Role split via the EXISTING Business Context architecture - no new
  ///    data. Main = primaryCategoryIds ∪ secondaryCategoryIds, Side =
  ///    lowPriorityCategoryIds, both read from
  ///    ctx.businessTypeProfiles[ctx.vendor.businessTypeId] - the exact
  ///    same admin-managed profile _restaurantTypeCategoryScore already
  ///    reads. No businessTypeId set, or no profile configured for this
  ///    vendor's type yet (e.g. Cloud Kitchen/Ice Cream Shop/Sweet Shop,
  ///    which deliberately have none - see _restaurantTypeCategoryScore's
  ///    doc comment) -> entire menu treated as one Main group, Side empty,
  ///    matching the "no Business Context yet" degradation used everywhere
  ///    else in this file. A product whose categoryID is primary,
  ///    secondary, OR unmatched by any tier is bucketed into Main by
  ///    construction (Main = "everything not explicitly Side") - never
  ///    silently dropped from ever earning a badge.
  /// 2. Per-group badge cap - dynamic percentage of that GROUP's own active
  ///    product count (1-10:40%, 11-20:35%, 21-40:30%, 41-75:25%,
  ///    76+:20%), percentage-of-count computed first, then rounded
  ///    (round-half-up), THEN clamped to [_dynamicCapMin, _dynamicCapMax]
  ///    and to the group's own size (a cap can never exceed how many
  ///    products actually exist in that group). The same per-group cap
  ///    number is the ceiling for that group's Most Ordered AND,
  ///    independently, its Popular Choice allocation ("how many products
  ///    are allowed to receive each badge") - the shared restaurant-wide
  ///    budget below is what actually limits the combined total shown.
  /// 3. Selection within a group - existing signals, unchanged. Most
  ///    Ordered ranks candidates by ctx.rolling7DaySales, Popular Choice by
  ///    ctx.rolling90DaySales - both restaurant-wide aggregate counts
  ///    FirebaseHelper already computes, nothing new fetched or stored.
  ///    Only products with a positive count are ever candidates; ties keep
  ///    original menu order (stable sort). A product already awarded Most
  ///    Ordered is removed from its group's Popular Choice candidate pool
  ///    - one label per product.
  /// 4. Shared restaurant-wide badge budget - 20 total, across the WHOLE
  ///    menu, both roles and both labels combined (never 20 Most Ordered +
  ///    20 Popular Choice on top of each other). Filled in priority order:
  ///    Most Ordered (Main) -> Most Ordered (Side) -> Popular Choice
  ///    (Main) -> Popular Choice (Side). Each bucket draws
  ///    min(its own per-group cap, its real candidate count, budget
  ///    remaining); once the running budget hits 0, later buckets in the
  ///    priority order get nothing further, even with qualifying
  ///    candidates left.
  /// 5. Same hasSufficientRestaurantConfidence(ctx) floor as every other
  ///    real-sales-based signal in this file - a restaurant without enough
  ///    total volume gets no badges at all, exactly as before.
  ///
  /// Zero Firestore changes: role split, ranking, and gating all read
  /// fields already on ctx (businessTypeProfiles, rolling7DaySales,
  /// rolling90DaySales), computed exactly as before this change.
  static bool _useDynamicRoleAwareBadgeLogic = true;
  static const int _dynamicCapMin = 1;
  static const int _dynamicCapMax = 20;
  static const int _sharedBadgeBudget = 20;

  static int _dynamicPercentFor(int activeCount) {
    if (activeCount <= 10) return 40;
    if (activeCount <= 20) return 35;
    if (activeCount <= 40) return 30;
    if (activeCount <= 75) return 25;
    return 20;
  }

  static int _dynamicCapFor(int activeCount) {
    if (activeCount <= 0) return 0;
    final percent = _dynamicPercentFor(activeCount);
    var cap = (activeCount * percent / 100).round(); // round-half-up
    if (cap < _dynamicCapMin) cap = _dynamicCapMin;
    if (cap > _dynamicCapMax) cap = _dynamicCapMax;
    if (cap > activeCount) cap = activeCount;
    return cap;
  }

  static Map<ProductBadgeRole, List<ProductModel>> _roleGroupsFor(
      RestaurantRecommendationContext ctx) {
    final typeId = ctx.vendor.businessTypeId;
    final profile = typeId.isEmpty ? null : ctx.businessTypeProfiles[typeId];
    if (profile == null) {
      return {
        ProductBadgeRole.main: ctx.allProducts,
        ProductBadgeRole.side: const [],
      };
    }
    final sideCategoryIds = profile.lowPriorityCategoryIds;
    final main = <ProductModel>[];
    final side = <ProductModel>[];
    for (final p in ctx.allProducts) {
      if (sideCategoryIds.contains(p.categoryID)) {
        side.add(p);
      } else {
        main.add(p);
      }
    }
    return {ProductBadgeRole.main: main, ProductBadgeRole.side: side};
  }

  // Descending rank by [counts], positive counts only, [exclude]d ids
  // skipped, ties keep original menu order (stable) - same convention as
  // every other ranking function in this file.
  static List<ProductModel> _rankByCount(List<ProductModel> group,
      Map<String, int> counts, Set<String> exclude) {
    final indexed = <MapEntry<int, ProductModel>>[];
    for (var i = 0; i < group.length; i++) {
      final p = group[i];
      if (exclude.contains(p.id)) continue;
      if ((counts[p.id] ?? 0) <= 0) continue;
      indexed.add(MapEntry(i, p));
    }
    indexed.sort((a, b) {
      final diff = (counts[b.value.id] ?? 0).compareTo(counts[a.value.id] ?? 0);
      return diff != 0 ? diff : a.key.compareTo(b.key);
    });
    return indexed.map((e) => e.value).toList();
  }

  static Map<String, ProductRecommendationConfidence> _dynamicRoleAwareBadges(
      RestaurantRecommendationContext ctx) {
    if (!hasSufficientRestaurantConfidence(ctx)) return {};

    final groups = _roleGroupsFor(ctx);
    final main = groups[ProductBadgeRole.main] ?? const [];
    final side = groups[ProductBadgeRole.side] ?? const [];
    final mainCap = _dynamicCapFor(main.length);
    final sideCap = _dynamicCapFor(side.length);

    final result = <String, ProductRecommendationConfidence>{};
    final awarded = <String>{};

    // Returns how many badges it actually awarded (<= budgetLeft), so the
    // caller manages its own budget counter(s) by simple subtraction -
    // shared by both allocation modes below rather than duplicating the
    // award loop for each.
    //
    // WINNER SELECTION vs. CONFIDENCE are deliberately two separate inputs
    // (2026-07-23, Trending/Popular Choice confidence rework):
    //   - rankingCounts decides WHICH products win a badge - unchanged,
    //     still rolling7DaySales for Most Ordered/Trending, rolling90DaySales
    //     for Popular Choice (quantity-based, exactly as before).
    //   - confidenceCounts/confidenceTotal decide the BAR'S FILL VALUE only,
    //     computed AFTER the winner is already chosen: this product's share
    //     of the restaurant's total DISTINCT ORDERS in that same window
    //     (productOrders7/totalOrders7 for Trending, productOrders90/
    //     totalOrders90 for Popular Choice) - independent denominators, no
    //     longer the shared hardcoded constant.
    int awardBadges(
        List<ProductModel> group,
        int groupCap,
        Map<String, int> rankingCounts,
        RecommendationLabel label,
        Map<String, int> confidenceCounts,
        int confidenceTotal,
        int budgetLeft) {
      if (budgetLeft <= 0 || groupCap <= 0) return 0;
      final ranked = _rankByCount(group, rankingCounts, awarded);
      final take = min(min(groupCap, ranked.length), budgetLeft);
      for (var i = 0; i < take; i++) {
        final p = ranked[i];
        final fill = confidenceTotal > 0
            ? ((confidenceCounts[p.id] ?? 0) / confidenceTotal).clamp(0.0, 1.0)
            : 0.0;
        result[p.id] = ProductRecommendationConfidence(fill, label);
        awarded.add(p.id);
      }
      return take;
    }

    // Large-menu budget reservation (2026-07-23) - on a big enough menu,
    // Most Ordered's own per-group caps could consume the ENTIRE shared
    // 20-badge budget before Popular Choice ever gets a turn (confirmed:
    // a 100+ product, no-Business-Context menu produced zero Popular
    // Choice badges under the plain shared-pool rule below). Once total
    // active products exceeds 40, reserve a fixed 60/40 split of the
    // shared budget instead - Most Ordered can take at most 12 of the 20,
    // Popular Choice keeps a guaranteed 8 that Most Ordered can never
    // encroach on. Whichever label doesn't use its full reserved share
    // (too few real candidates) just leaves those slots unused - a hard
    // partition, not a dynamic reallocation, so the split stays exactly
    // 60/40 of what's actually awarded, never less predictable than that.
    //
    // Menus <=40 keep TODAY'S EXACT original behavior below (one shared
    // pool, Most Ordered fills first, Popular Choice gets whatever's
    // left) - this only changes anything once the scenario it fixes can
    // actually occur.
    if (ctx.allProducts.length > 40) {
      var mostOrderedBudget = (_sharedBadgeBudget * 0.6).round(); // 12 of 20
      var popularChoiceBudget = _sharedBadgeBudget - mostOrderedBudget; // 8 of 20, guaranteed

      mostOrderedBudget -= awardBadges(main, mainCap, ctx.rolling7DaySales,
          RecommendationLabel.mostOrdered, ctx.productOrders7, ctx.totalOrders7, mostOrderedBudget);
      mostOrderedBudget -= awardBadges(side, sideCap, ctx.rolling7DaySales,
          RecommendationLabel.mostOrdered, ctx.productOrders7, ctx.totalOrders7, mostOrderedBudget);
      // Popular Choice (2026-07-23, explicit product direction): Main only.
      // Side items never carry this label, regardless of their own 90-day
      // sales. Any reserved Popular Choice budget Main doesn't use is left
      // unused, not handed to Side - Side stays untouched for this label.
      popularChoiceBudget -= awardBadges(main, mainCap, ctx.rolling90DaySales,
          RecommendationLabel.popularChoice, ctx.productOrders90, ctx.totalOrders90, popularChoiceBudget);
    } else {
      // Priority order: Most Ordered (Main) -> Most Ordered (Side) ->
      // Popular Choice (Main only - see 2026-07-23 note above; Side never
      // gets this label in either allocation mode).
      var remainingBudget = _sharedBadgeBudget;
      remainingBudget -= awardBadges(main, mainCap, ctx.rolling7DaySales,
          RecommendationLabel.mostOrdered, ctx.productOrders7, ctx.totalOrders7, remainingBudget);
      remainingBudget -= awardBadges(side, sideCap, ctx.rolling7DaySales,
          RecommendationLabel.mostOrdered, ctx.productOrders7, ctx.totalOrders7, remainingBudget);
      remainingBudget -= awardBadges(main, mainCap, ctx.rolling90DaySales,
          RecommendationLabel.popularChoice, ctx.productOrders90, ctx.totalOrders90, remainingBudget);
    }

    return result;
  }

  static Map<String, ProductRecommendationConfidence> recommendationConfidenceScores(
      RestaurantRecommendationContext ctx) {
    if (_useDynamicRoleAwareBadgeLogic) {
      return _dynamicRoleAwareBadges(ctx);
    }

    final normalized = normalizedMergedScores(ctx);
    if (normalized.isEmpty) return {};
    final bestSeller = scoreBySource(ctx, 'bestSeller');
    final stage0 = ctx.behaviorSummary.isEmpty;
    final prefRaw = stage0 ? null : _preferenceRawMaps(ctx);

    final result = <String, ProductRecommendationConfidence>{};
    for (final p in ctx.allProducts) {
      if (_useSimpleLaunchBadgeLogic) {
        // Pure raw-sales-count rule, restaurant-wide - deliberately
        // independent of hasSufficientRestaurantConfidence/normalized
        // score/label-vote above, so it's exactly as simple as asked:
        // more than 50 orders in the LAST 7 DAYS -> Most Ordered (checked
        // first - a fast-trending item wins even if its 90-day total is
        // still under the Popular Choice floor); otherwise 20+ orders in
        // the trailing 90 days -> Popular Choice; otherwise no badge.
        // Fill level scales each count 0..1 against the same Most Ordered
        // threshold so the bar and the label always agree visually.
        final sales7Day = ctx.rolling7DaySales[p.id] ?? 0;
        final sales90Day = ctx.rolling90DaySales[p.id] ?? 0;
        if (sales7Day > _launchMostOrderedMinOrders7Day) {
          final fillScore =
              (sales7Day / _launchMostOrderedMinOrders7Day).clamp(0.0, 1.0);
          result[p.id] = ProductRecommendationConfidence(
              fillScore, RecommendationLabel.mostOrdered);
        } else if (sales90Day >= _launchPopularChoiceMinOrders) {
          final fillScore =
              (sales90Day / _launchMostOrderedMinOrders7Day).clamp(0.0, 1.0);
          result[p.id] = ProductRecommendationConfidence(
              fillScore, RecommendationLabel.popularChoice);
        }
        continue;
      }

      final score = normalized[p.id] ?? 0;
      if (score <= 0) continue; // no signal at all -> no bar, never fake a confidence value
      if (score < minimumRecommendationConfidence) continue; // not confident enough to show at all

      var label = RecommendationLabel.popularChoice;
      var best = 0.0;
      void consider(double value, RecommendationLabel candidate, bool eligible) {
        if (eligible && value > best) {
          best = value;
          label = candidate;
        }
      }

      consider(bestSeller[p.id] ?? 0, RecommendationLabel.mostOrdered, true);

      if (!stage0 && prefRaw != null) {
        final searchConfidence = _searchConfidenceBoost(p, ctx);
        final behaviorAffinity = _log1pScaled(prefRaw.behaviorRaw[p.id] ?? 0, prefRaw.maxBehavior);
        final categoryMatch = _log1pScaled(prefRaw.categoryRaw[p.id] ?? 0, prefRaw.maxCategory);
        consider(behaviorAffinity, RecommendationLabel.matchesYourTaste, true);
        consider(categoryMatch, RecommendationLabel.matchesYourTaste, true);
        // fitsYourBudget (2026-07-20, revised same day): no longer eligible
        // to become the DISPLAYED label at all - on a narrow-priced menu it
        // was dominating almost every product, and simply hiding the badge
        // whenever it won (the widget's old SizedBox.shrink() branch) threw
        // away a perfectly real score just because its label happened to be
        // this one. Excluding it here instead lets the next-highest real
        // signal become the label, so the badge still shows. _priceCompatibility
        // itself is untouched and still contributes to the SCORE via
        // _tasteProfileScore - only its ability to WIN the label vote is gone.
        consider(searchConfidence, RecommendationLabel.basedOnSearches,
            searchConfidence >= _searchConfidenceLabelThreshold);
        consider(_neverInteractedRaw(p, ctx), RecommendationLabel.worthTrying, true);
        consider(_hiddenGemProductScore(p, ctx), RecommendationLabel.hiddenGem, true);
      }

      result[p.id] = ProductRecommendationConfidence(score, label);
    }
    return result;
  }

  /// Real, honest "how many times this product was ordered in the last 90
  /// days (3 months)" count per product (2026-07-20, explicit product
  /// request - shown ALONGSIDE recommendationConfidenceScores' badge, not
  /// replacing it; revised same day from a computed percentage to this
  /// plain count per explicit follow-up direction - simpler and even more
  /// literal; window itself widened from 30 to 90 days later the same day).
  /// Reads ctx.rolling90DaySales directly - already real, restaurant-wide
  /// aggregate quantity-sold data (see dailyProductSales' doc comment in
  /// FirebaseHelper.dart), not tied to the customer currently viewing the
  /// menu.
  ///
  /// Same hasSufficientRestaurantConfidence floor (>=15 total orders
  /// restaurant-wide in 90 days) as every other real-sales-based signal in
  /// this file (bestSeller, hiddenGem, worthTrying) - no count shown at all
  /// for a restaurant without enough volume to make one meaningful. A
  /// product with zero sales in the window is omitted entirely (never a
  /// fabricated/misleading "0 orders" badge cluttering every unsold dish).
  static Map<String, int> orderCounts(RestaurantRecommendationContext ctx) {
    if (!hasSufficientRestaurantConfidence(ctx)) return {};
    final result = <String, int>{};
    for (final p in ctx.allProducts) {
      final sales = ctx.rolling90DaySales[p.id] ?? 0;
      if (sales <= 0) continue;
      result[p.id] = sales;
    }
    return result;
  }

  /// Stable score-descending sort (ties keep original menu order) via
  /// index-decoration, since List.sort is not guaranteed stable in Dart.
  /// Cold-start rule: if every candidate in [categoryProducts] scores 0,
  /// the original (natural) order is returned unchanged - nothing visibly
  /// reorders for a signal-less user or a brand-new restaurant. [scores]
  /// is typically computeMergedScores(ctx) for the full-menu reorder use case.
  static List<ProductModel> reorderByScore(
      List<ProductModel> categoryProducts, Map<String, double> scores) {
    final hasSignal = categoryProducts.any((p) => (scores[p.id] ?? 0) > 0);
    if (!hasSignal) return List<ProductModel>.from(categoryProducts);

    final indexed = categoryProducts.asMap().entries.toList();
    indexed.sort((a, b) {
      final scoreA = scores[a.value.id] ?? 0;
      final scoreB = scores[b.value.id] ?? 0;
      final cmp = scoreB.compareTo(scoreA);
      return cmp != 0 ? cmp : a.key.compareTo(b.key);
    });
    return indexed.map((e) => e.value).toList();
  }

  /// A category with this many or more DISTINCT products already in the
  /// cart is "sufficiently represented" - fillPairsWellWith deprioritizes
  /// (never eliminates) further suggestions from it. Counted by distinct
  /// product, not quantity - three of the same Naan is still "1 bread
  /// product", not 3, matching "sufficiently represented" as a variety
  /// concept, not a quantity one.
  static const int _cartCategorySaturationThreshold = 2;

  /// The "pairs well with" panel: starts from the vendor's own configured
  /// list (reordered by the merged score, original vendor order as the
  /// tie-break), and if that's short of [maxItems], fills the remainder
  /// from [candidatePool] (which must already exclude the product being
  /// viewed) in the spec's fallback priority: cross-sell frequency ->
  /// customer preference -> restaurant best-sellers.
  ///
  /// Cart Awareness (2026-07-19): [cartProductIds]/[cartCategoryCounts] are
  /// SECONDARY context - the triggering product (via [vendorConfigured],
  /// still keyed to it alone) remains PRIMARY, unchanged. Two effects,
  /// both additive on top of the existing ranking, never a second scoring
  /// system:
  /// 1. Duplicate suppression: anything already in the cart is dropped
  ///    entirely from both [vendorConfigured] and [candidatePool] - a
  ///    product already added has nothing left to offer by being
  ///    suggested again.
  /// 2. Category saturation: a stable partition (same "reorder, never
  ///    remove" technique _categoryOrderByBusinessType uses for Explore
  ///    the Menu) pushes candidates whose category already meets
  ///    [_cartCategorySaturationThreshold] in the cart to the back of
  ///    their respective list - "Cart has 2 breads already" deprioritizes
  ///    a 3rd bread suggestion below every non-bread candidate, but still
  ///    shows it as backfill if there simply aren't enough alternatives to
  ///    fill [maxItems]. Both default to empty/no-op so every OTHER caller
  ///    of this function (there are none today, but the signature stays
  ///    backward compatible) keeps working unchanged.
  ///
  /// Both parameters are deliberately untouched: no new candidate-scoring
  /// system, no change to Recommended For You / Restaurant Must Try /
  /// Hidden Gems / Most Loved Here - the merge, the sources, and every
  /// other section's call path never reference cart state at all.
  ///
  /// Product Context (2026-07-19): [pairingContextScores] - typically
  /// pairingContextScore(candidate, triggeringProduct, ctx) precomputed per
  /// candidate by the caller - is a NEW sort key inserted only into the
  /// FILLER ranking, between saturation and cross-sell frequency. Never
  /// applied to [vendorConfigured]: a human already chose those pairs
  /// deliberately (still ranked by [mergedScores] alone, exactly as
  /// before) - re-ranking an explicit vendor choice by an inferred
  /// category heuristic would be presumptuous, not an improvement.
  /// Defaults to {} (every candidate scores 0, meaning "tied, fall through
  /// to cross-sell/preference/best-seller exactly as today") so this stays
  /// fully backward compatible for any caller that doesn't supply it.
  static List<ProductModel> fillPairsWellWith({
    required List<ProductModel> vendorConfigured,
    required List<ProductModel> candidatePool,
    required Map<String, double> mergedScores,
    required Map<String, double> preferenceScores,
    required Map<String, double> bestSellerScores,
    required Map<String, int> crossSellFrequency,
    Map<String, double> pairingContextScores = const {},
    Set<String> cartProductIds = const {},
    Map<String, int> cartCategoryCounts = const {},
    int maxItems = defaultSectionLimit,
  }) {
    bool isSaturated(ProductModel p) =>
        (cartCategoryCounts[p.categoryID] ?? 0) >= _cartCategorySaturationThreshold;

    final vendorFiltered =
        vendorConfigured.where((p) => !cartProductIds.contains(p.id)).toList();
    final vendorIndexed = vendorFiltered.asMap().entries.toList();
    vendorIndexed.sort((a, b) {
      final satA = isSaturated(a.value) ? 1 : 0;
      final satB = isSaturated(b.value) ? 1 : 0;
      if (satA != satB) return satA.compareTo(satB); // non-saturated first
      final scoreA = mergedScores[a.value.id] ?? 0;
      final scoreB = mergedScores[b.value.id] ?? 0;
      final cmp = scoreB.compareTo(scoreA);
      return cmp != 0 ? cmp : a.key.compareTo(b.key);
    });

    final result = vendorIndexed.map((e) => e.value).toList();
    if (result.length >= maxItems) return result.take(maxItems).toList();

    final chosenIds = result.map((p) => p.id).toSet();
    final fillers = candidatePool
        .where((p) => !chosenIds.contains(p.id) && !cartProductIds.contains(p.id))
        .toList();
    final fillerIndexed = fillers.asMap().entries.toList();
    fillerIndexed.sort((a, b) {
      final satA = isSaturated(a.value) ? 1 : 0;
      final satB = isSaturated(b.value) ? 1 : 0;
      if (satA != satB) return satA.compareTo(satB); // non-saturated first
      // Combo Recommendation Rules (2026-07-19): combo products always get
      // the LOWEST filler priority - individual dishes are preferred
      // regardless of how well a combo would otherwise score on Product
      // Context/cross-sell/preference/best-seller below, which is why this
      // check sits ABOVE all of those (a dominant partition, same "reorder,
      // never remove" technique saturation already uses) rather than a
      // low-priority tie-break. A combo still backfills in - never fully
      // excluded - once there simply aren't enough non-combo alternatives
      // left to fill maxItems. Vendor-curated pairs (above) are deliberately
      // untouched, same principle as Product Context: a human already chose
      // those pairs, including any combo among them, on purpose.
      final comboA = a.value.isCombo ? 1 : 0;
      final comboB = b.value.isCombo ? 1 : 0;
      if (comboA != comboB) return comboA.compareTo(comboB); // individual products first
      final ctxA = pairingContextScores[a.value.id] ?? 0;
      final ctxB = pairingContextScores[b.value.id] ?? 0;
      if (ctxA != ctxB) return ctxB.compareTo(ctxA); // meal-context-relevant first
      final crossA = crossSellFrequency[a.value.id] ?? 0;
      final crossB = crossSellFrequency[b.value.id] ?? 0;
      if (crossA != crossB) return crossB.compareTo(crossA);
      final prefA = preferenceScores[a.value.id] ?? 0;
      final prefB = preferenceScores[b.value.id] ?? 0;
      if (prefA != prefB) return prefB.compareTo(prefA);
      final bestA = bestSellerScores[a.value.id] ?? 0;
      final bestB = bestSellerScores[b.value.id] ?? 0;
      final cmp = bestB.compareTo(bestA);
      return cmp != 0 ? cmp : a.key.compareTo(b.key);
    });

    result.addAll(fillerIndexed.map((e) => e.value).take(maxItems - result.length));
    return result;
  }

  // ── Hidden Gems (also redesigned - was poisoned by the same fake-rating bug) ──

  static const double _hiddenGemsVendorRatingGate = 0.6; // roughly a confidence-weighted 4.0+ restaurant

  /// "Hidden gem" can no longer mean "this specific dish is secretly
  /// great" - no per-product quality signal exists anywhere. Redefined
  /// honestly as "this restaurant is trustworthy overall (rating-gated, at
  /// the RESTAURANT level) and this specific dish is under-ordered
  /// relative to its own menu." Reused directly by _sourceDiscovery so
  /// Discovery's "hidden gem" ingredient and this standalone function
  /// never define "gem" two different ways.
  static double _hiddenGemProductScore(
      ProductModel p, RestaurantRecommendationContext ctx) {
    if (!hasSufficientRestaurantConfidence(ctx)) return 0.0;
    if (_vendorRatingSignal(ctx.vendor) < _hiddenGemsVendorRatingGate) return 0.0;
    final maxSales = ctx.rolling90DaySales.values.fold(0, max);
    if (maxSales <= 0) return 0.0;
    final sales = ctx.rolling90DaySales[p.id] ?? 0;
    final band = maxSales * 0.3;
    if (sales <= 0 || sales > band) return 0.0; // >0 excludes never-sold items, not "gems"
    final raw = 1.0 - (sales / band);
    return _applyBusinessContextMultiplier(raw, p, ctx);
  }

  static List<ProductModel> hiddenGems(RestaurantRecommendationContext ctx,
      {int n = defaultSectionLimit}) {
    final scored = ctx.allProducts
        .map((p) => MapEntry(p, _hiddenGemProductScore(p, ctx)))
        .where((e) => e.value > 0)
        .toList();
    // Category-first, product-second, now with dynamic slot allocation
    // (2026-07-23) - _hiddenGemProductScore itself (confidence gate,
    // rating gate, sales-band position, Business Context boost) is
    // completely untouched; only the final ordering/selection changed.
    final categoryRank = _categoryRankIndex(ctx);
    final indexed = scored.asMap().entries.toList();
    indexed.sort((a, b) {
      final catA = categoryRank[a.value.key.categoryID] ?? categoryRank.length;
      final catB = categoryRank[b.value.key.categoryID] ?? categoryRank.length;
      if (catA != catB) return catA.compareTo(catB);
      final cmp = b.value.value.compareTo(a.value.value);
      return cmp != 0 ? cmp : a.key.compareTo(b.key);
    });
    final ranked = indexed.map((e) => e.value.key).toList();
    final slots = _categorySlotAllocation(ranked, ctx, n);
    return _selectByCategoryAllocation(ranked, slots);
  }

  // ── Most Loved Here (2026-07-19: consolidated + Business Context) ──────
  //
  // Previously duplicated independently in newVendorProductsScreen's
  // _mostLovedHereProducts and WhatShouldITryScreen's _mostLoved() - same
  // gates, same raw-sales sort, two copies that could silently drift.
  // Consolidated here as the single source of truth, and re-ranked with
  // _applyBusinessContextMultiplier so "the products people are actually
  // ordering" doesn't mean an incidental off-brand item (a Restaurant's
  // bottled water having one lucky week) can outrank real signature dishes
  // just because it's cheap and frequently added on - "Popularity must no
  // longer override business context." Still restricted to products with
  // real sales>0 this window - this section's identity as "what's actually
  // being ordered" is unchanged, only the ranking WITHIN that real-sales set
  // changes.
  /// Veg/Non-Veg preference filter for Most Loved Here (2026-07-25) - "most
  /// loved BY OTHER CUSTOMERS" (real sales popularity, per the section's
  /// own long-standing identity above), narrowed to the dish type THIS
  /// customer has shown an exclusive, repeated preference for -
  /// DietaryPreference.none (no confident signal yet, or a genuinely mixed
  /// history) returns [ranked] untouched, so an unproven/undetermined
  /// customer sees exactly what this section has always shown. A confident
  /// preference that would leave NOTHING to fill the section (a veg-only
  /// customer at an all-non-veg restaurant) also falls back to unfiltered
  /// - a worse, but non-empty, section beats an empty one, same "never
  /// fabricate confidence you don't have, but never show emptier than
  /// necessary either" rule this file already applies everywhere else
  /// (e.g. reorderByScore's cold-start guard).
  static List<ProductModel> _applyDietaryPreferenceFilter(
      List<ProductModel> ranked, RestaurantRecommendationContext ctx) {
    final preference = ctx.behaviorSummary.dietaryPreference;
    if (preference == DietaryPreference.none) return ranked;
    final filtered = ranked
        .where((p) => preference == DietaryPreference.vegOnly ? p.veg : p.nonveg)
        .toList();
    return filtered.isNotEmpty ? filtered : ranked;
  }

  static List<ProductModel> mostLovedHere(RestaurantRecommendationContext ctx,
      {int limit = defaultSectionLimit}) {
    if (!hasSufficientRestaurantConfidence(ctx)) return const [];
    final withSales =
        ctx.allProducts.where((p) => (ctx.rolling90DaySales[p.id] ?? 0) > 0).toList();
    if (withSales.isEmpty) return const [];
    final maxSales = ctx.rolling90DaySales.values.fold(0, max);
    double keyOf(ProductModel p) {
      final salesScore = _log1pScaled(ctx.rolling90DaySales[p.id] ?? 0, maxSales);
      return _applyBusinessContextMultiplier(salesScore, p, ctx);
    }
    final indexed = withSales.asMap().entries.toList();
    indexed.sort((a, b) {
      final cmp = keyOf(b.value).compareTo(keyOf(a.value));
      return cmp != 0 ? cmp : a.key.compareTo(b.key);
    });
    final ranked = _applyDietaryPreferenceFilter(
        indexed.map((e) => e.value).toList(), ctx);

    // Category-first, product-second (2026-07-25) - reuses hiddenGems'
    // exact allocation pattern (_categorySlotAllocation +
    // _selectByCategoryAllocation) rather than a flat take(limit), so a
    // veg/non-veg-filtered (or unfiltered) result is still spread across
    // the categories this customer actually prefers instead of being
    // dominated by whichever single category happens to sell the most.
    final slots = _categorySlotAllocation(ranked, ctx, limit);
    return _selectByCategoryAllocation(ranked, slots);
  }

  // ── SearchScreen restaurant-level personalization ───────────────────────

  /// Search Confidence / Cross-Session Search Interest's restaurant-ranking
  /// half - same text-matching approach as _searchConfidenceBoost above,
  /// applied to a restaurant's own title/cuisineNames instead of a single
  /// product's name.
  static double _restaurantSearchConfidenceBoost(
      VendorModel vendor, BehaviorSummarySnapshot summary) {
    final keywords = summary.topSearchKeywords.keys;
    if (keywords.isEmpty) return 0.0;
    final title = vendor.title.toLowerCase();
    final cuisineNames = vendor.cuisineNames.map((c) => c.toLowerCase());
    final businessType = vendor.businessTypeName.toLowerCase();
    double best = 0.0;
    for (final query in keywords) {
      if (query.isEmpty) continue;
      final matches = title.contains(query) ||
          cuisineNames.any((c) => c.contains(query)) ||
          (businessType.isNotEmpty && businessType.contains(query));
      if (!matches) continue;
      final confidence = summary.crossSessionSearchInterestFor(query);
      if (confidence > best) best = confidence;
    }
    return best;
  }

  /// A 0..1 personalization score per restaurant, derived from the
  /// customer's own restaurant-visit/cuisine-interaction history AND (2026-
  /// 07-18) Search Confidence - meant to be blended into a caller's own
  /// composite ranking formula (e.g. SearchScreen's rating/popularity/
  /// nearness score), not used to reorder [restaurants] directly, since
  /// callers generally need to mix this signal with others that this
  /// engine has no knowledge of.
  static Map<String, double> restaurantPreferenceScores(
      List<VendorModel> restaurants, BehaviorSummarySnapshot? summary) {
    if (summary == null || summary.isEmpty) return {};

    final config = RecommendationConfig.current;
    final raw = <String, double>{};
    for (final vendor in restaurants) {
      final visits = summary.restaurantVisitCounts[vendor.id] ?? 0;
      final favoriteBonus =
          summary.favoriteRestaurantIds.contains(vendor.id) ? 5 : 0;
      final cuisineAffinity = vendor.cuisineIds.fold<int>(
          0, (sum, c) => sum + (summary.cuisineInteractionCounts[c] ?? 0));
      // restaurantPreferenceWeight/cuisinePreferenceWeight (2026-07-22) -
      // were the literal `visits * 2` and implicit `cuisineAffinity * 1`
      // coefficients. Raw small multipliers, not 0-1 ratios (they scale a
      // COUNT before log1p compression below), so read directly - not
      // divided by 100 like the other config fields.
      raw[vendor.id] = visits * config.restaurantPreferenceWeight +
          favoriteBonus +
          cuisineAffinity * config.cuisinePreferenceWeight;
    }
    final maxRaw = raw.values.fold(0.0, max);

    final result = <String, double>{};
    for (final vendor in restaurants) {
      // Additive on top of the log1p-normalized base score, not folded into
      // the same raw-count scale - Search Confidence is already 0..1 by
      // construction and shouldn't be diluted by log1p's compression, but
      // it's capped to a modest (searchConfidenceWeight/100, default 0.3)
      // max contribution so it can nudge ranking, never dominate a
      // customer's real visit/favorite history.
      final base = maxRaw > 0 ? _log1pScaled((raw[vendor.id] ?? 0).round(), maxRaw.round()) : 0.0;
      final confidenceBoost = _restaurantSearchConfidenceBoost(vendor, summary) *
          (config.searchConfidenceWeight / 100);
      final score = (base + confidenceBoost).clamp(0.0, 1.0);
      if (score > 0) result[vendor.id] = score;
    }
    return result;
  }
}
