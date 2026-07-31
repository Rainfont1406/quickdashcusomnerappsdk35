// ─────────────────────────────────────────────────────────────────────────
// Recommendation Configuration (2026-07-22) - admin-tunable weights for the
// recommendation engine, replacing what used to be hardcoded constants in
// recommendation_engine.dart/SearchScreen.dart.
//
// Deliberately Firebase-free, same invariant recommendation_engine.dart's
// own header documents for itself ("pure Dart, synchronous, WITHOUT any
// Firebase import... swappable"). This file is ONLY the plain data model
// and the in-memory cache slot; the actual Firestore fetch lives in
// FirebaseHelper.loadRecommendationConfig() (same file/pattern as the
// Business Context listeners), so recommendation_engine.dart can import
// this file and stay Firebase-import-free itself.
//
// CACHING CONTRACT (the whole point of this file):
// - RecommendationConfig.current is a static field, always non-null,
//   initialized synchronously at class-load time to RecommendationConfig
//   .defaults() - the EXACT current hardcoded values this feature replaces.
//   This means every recommendation computed before the real config has
//   loaded (or if it never loads - offline, permission error, etc.) is
//   byte-for-byte identical to today's behavior. There is no nullable
//   "not loaded yet" state anywhere downstream.
// - FirebaseHelper.loadRecommendationConfig() fetches the single config
//   document ONCE per app run and overwrites `current` when it resolves.
//   Called once, eagerly, from main.dart at startup.
// - Every recommendation computation after that reads the already-cached
//   `current` field directly - zero additional Firestore reads while
//   opening restaurants, building sections, pairing products, or searching.
// - Never auto-refreshes mid-session. A fresh value only takes effect on
//   the next app start, matching the brief's explicit requirement.
//
// Every field here has a real, verified runtime effect the moment an admin
// changes it - no reserved/placeholder fields. A field for a signal not yet
// consumed by any algorithm (Seasonal Preference, Explorer Score on
// restaurant ranking, etc.) does not get added here until that signal is
// actually wired into scoring - see the implementation report for why
// Explorer Score was removed from this model for exactly this reason.
class RecommendationConfig {
  // ── Recommended For You (7 merge-source weights) ────────────────────
  // Mirrors RecommendationEngine's _baseSourceWeights map (preference/
  // businessContext/bestSeller/mustTry/similar/discovery/newProduct). All
  // stored 0-100 (the admin-facing slider scale) and divided by 100 - see
  // recommendation_engine.dart's own comments at each read site for the
  // exact original constant each field replaces.
  //
  // preferenceWeight (2026-07-22, simplified) - controls the WHOLE
  // Preference source's contribution to the merge. The engine still
  // internally computes Preference = Product + Category + Budget exactly
  // as before (_sourcePreference/_tasteProfileScore, untouched) - only the
  // single combined result is configurable here. The Product/Category/
  // Budget internal ratio (0.45/0.30*0.6/0.30*0.4) is an implementation
  // detail, not exposed, per explicit product decision - keeps this page
  // to one slider for Preference instead of three.
  final double preferenceWeight; // was _baseSourceWeights['preference'] = 1.00
  final double restaurantSpecialitiesWeight; // was _baseSourceWeights['mustTry'] = 0.85
  final double businessContextWeight; // was _baseSourceWeights['businessContext'] = 0.55
  final double bestSellerWeight; // was _baseSourceWeights['bestSeller'] = 0.90
  final double vendorRecommendationPreferenceWeight; // was _baseSourceWeights['similar'] = 0.75
  final double discoveryWeight; // was _baseSourceWeights['discovery'] = 0.60
  final double newProductBoostWeight; // was _baseSourceWeights['newProduct'] = 0.50

  // ── Explore the Menu ─────────────────────────────────────────────────
  // (2026-07-22, revised) True inheritance, not duplicated defaults:
  // exploreOverrideEnabled false (default) means exploreMenuSelection uses
  // whatever weights Recommended For You itself would compute for this
  // session - live, not a frozen copy - so tuning RFY automatically
  // carries through to Explore with zero admin action. Only when an admin
  // flips this on do the 4 stored override fields below take effect,
  // substituted in place of businessContext/newProduct/bestSeller/
  // discovery (preference/mustTry/similar are never independently
  // configurable for Explore, override or not).
  final bool exploreOverrideEnabled;
  final double exploreBusinessContextWeight;
  final double exploreNewProductBoostWeight;
  final double explorePopularProductsWeight; // was _baseSourceWeights['bestSeller'] at this call site
  final double exploreDiscoveryWeight;

  // ── Restaurant Ranking (shared by Search results AND restaurant-level
  // recommendation context - there is only one real algorithm today,
  // SearchScreen._score() + RecommendationEngine.restaurantPreferenceScores;
  // see the implementation report for why Search Ranking and Restaurant
  // Recommendation were unified into one section instead of two). ──
  final double ratingWeight; // was _score()'s `rating * 40`
  final double popularityWeight; // was _score()'s `popularity * 30` (review-count based)
  final double distanceWeight; // was _score()'s `nearness.clamp(0.0, 30.0)` cap
  final double personalizationWeight; // was _score()'s `personalization * 20`
  final double restaurantPreferenceWeight; // was restaurantPreferenceScores' `visits * 2`
  final double cuisinePreferenceWeight; // was restaurantPreferenceScores' implicit `cuisineAffinity * 1`
  final double searchConfidenceWeight; // was restaurantPreferenceScores' `confidenceBoost * 0.3`, stored *100

  const RecommendationConfig({
    this.preferenceWeight = 100,
    this.restaurantSpecialitiesWeight = 85,
    this.businessContextWeight = 55,
    this.bestSellerWeight = 90,
    this.vendorRecommendationPreferenceWeight = 75,
    this.discoveryWeight = 60,
    this.newProductBoostWeight = 50,
    this.exploreOverrideEnabled = false,
    this.exploreBusinessContextWeight = 55,
    this.exploreNewProductBoostWeight = 50,
    this.explorePopularProductsWeight = 90,
    this.exploreDiscoveryWeight = 60,
    this.ratingWeight = 40,
    this.popularityWeight = 30,
    this.distanceWeight = 30,
    this.personalizationWeight = 20,
    this.restaurantPreferenceWeight = 2,
    this.cuisinePreferenceWeight = 1,
    this.searchConfidenceWeight = 30,
  });

  /// The exact values recommendation_engine.dart/SearchScreen.dart had
  /// hardcoded before this feature existed - both the constructor defaults
  /// above AND this factory produce identical values; this named
  /// constructor exists only so call sites reading "restore to default" can
  /// say so explicitly.
  factory RecommendationConfig.defaults() => const RecommendationConfig();

  factory RecommendationConfig.fromJson(Map<String, dynamic> json) {
    final d = RecommendationConfig.defaults();
    double read(String key, double fallback) {
      final v = json[key];
      if (v is num) return v.toDouble();
      return fallback;
    }

    return RecommendationConfig(
      preferenceWeight: read('preferenceWeight', d.preferenceWeight),
      restaurantSpecialitiesWeight: read('restaurantSpecialitiesWeight', d.restaurantSpecialitiesWeight),
      businessContextWeight: read('businessContextWeight', d.businessContextWeight),
      bestSellerWeight: read('bestSellerWeight', d.bestSellerWeight),
      vendorRecommendationPreferenceWeight:
          read('vendorRecommendationPreferenceWeight', d.vendorRecommendationPreferenceWeight),
      discoveryWeight: read('discoveryWeight', d.discoveryWeight),
      newProductBoostWeight: read('newProductBoostWeight', d.newProductBoostWeight),
      exploreOverrideEnabled: json['exploreOverrideEnabled'] is bool
          ? json['exploreOverrideEnabled'] as bool
          : d.exploreOverrideEnabled,
      exploreBusinessContextWeight: read('exploreBusinessContextWeight', d.exploreBusinessContextWeight),
      exploreNewProductBoostWeight: read('exploreNewProductBoostWeight', d.exploreNewProductBoostWeight),
      explorePopularProductsWeight: read('explorePopularProductsWeight', d.explorePopularProductsWeight),
      exploreDiscoveryWeight: read('exploreDiscoveryWeight', d.exploreDiscoveryWeight),
      ratingWeight: read('ratingWeight', d.ratingWeight),
      popularityWeight: read('popularityWeight', d.popularityWeight),
      distanceWeight: read('distanceWeight', d.distanceWeight),
      personalizationWeight: read('personalizationWeight', d.personalizationWeight),
      restaurantPreferenceWeight: read('restaurantPreferenceWeight', d.restaurantPreferenceWeight),
      cuisinePreferenceWeight: read('cuisinePreferenceWeight', d.cuisinePreferenceWeight),
      searchConfidenceWeight: read('searchConfidenceWeight', d.searchConfidenceWeight),
    );
  }

  // ── In-memory cache ──────────────────────────────────────────────────
  // Set directly by FirebaseHelper.loadRecommendationConfig() once its
  // fetch resolves - this file never touches Firestore itself.
  static RecommendationConfig current = RecommendationConfig.defaults();
}
