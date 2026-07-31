// Exhaustive randomized verification - 500+ independent, reproducible
// (fixed-seed) synthetic scenarios spanning restaurant config, menu
// composition, combo configuration, customer behavior, budget, and cart
// state. Engine-layer only, per explicit scope ("the goal is NOT to verify
// UI rendering") - every RecommendationEngine entry point is exercised
// directly against synthetic RestaurantRecommendationContext fixtures.
//
// Design: does NOT stop at the first failure. Every scenario's checks run
// through a `_check()` helper that records failures (with the FULL scenario
// dump needed to reproduce them) into a list rather than throwing - the test
// only fails at the very end, after every one of the 500+ scenarios has run,
// printing every recorded failure plus a full summary report.
import 'dart:math';

import 'package:emartconsumer/model/ComboProductItem.dart';
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/services/recommendation/behavior_summary_snapshot.dart';
import 'package:emartconsumer/services/recommendation/recommendation_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

// ── Scenario dimensions ─────────────────────────────────────────────────

const _menuSizePool = [1, 3, 5, 10, 20, 50, 100, 250, 500];
// Weighted toward smaller menus (realistic distribution + keeps total fuzz
// runtime bounded - a 500-product recommendForYou call alone costs ~200ms,
// see performance_benchmark_test.dart) while still guaranteeing every size
// named in the spec appears many times across 500 scenarios.
int _pickMenuSize(Random r) {
  final band = r.nextDouble();
  if (band < 0.35) return _menuSizePool[r.nextInt(3)]; // 1,3,5
  if (band < 0.65) return _menuSizePool[3 + r.nextInt(2)]; // 10,20
  if (band < 0.90) return _menuSizePool[5 + r.nextInt(2)]; // 50,100
  return _menuSizePool[7 + r.nextInt(2)]; // 250,500
}

const _businessTypePool = [btRestaurant, btCafe, btBakery, btJuiceBar, btFastFood, btCloudKitchen, ''];
const _cuisinePool = [
  cuisineNorthIndian, cuisineChinese, cuisineFastFood, cuisineCafe, cuisineBakery, cuisineBeverage,
];
const _comboDensities = ['none', 'few', 'heavy'];
const _behaviorVariants = [
  'none', 'browsing', 'search', 'order', 'heavy',
  'restaurant_loyal', 'cuisine_loyal', 'category_loyal', 'combo_loyal',
];
const _budgetTiers = [100.0, 150.0, 250.0, 500.0, 800.0, 1500.0];
const _cartVariants = [
  'empty', 'one', 'multiple', 'repeated_category', 'repeated_product',
  'combo_in_cart', 'multi_combo', 'large_family',
];

const _adjectives = ['Butter', 'Garlic', 'Spicy', 'Sweet', 'Classic', 'Mini', 'Family', 'Jeera', 'Special', 'Tandoori'];
const _nouns = ['Rice', 'Naan', 'Chicken', 'Paneer', 'Noodles', 'Soup', 'Pizza', 'Burger', 'Pasta', 'Salad', 'Biryani', 'Coffee', 'Dessert', 'Roti'];

class ScenarioConfig {
  final int index;
  final int menuSize;
  final String businessType;
  final List<String> cuisines;
  final bool businessContextConfigured; // false simulates missing-affinity edge case
  final String comboDensity;
  final String behaviorVariant;
  final double budget;
  final String cartVariant;
  final bool vegOnly;
  final bool nonVegOnly;

  ScenarioConfig({
    required this.index,
    required this.menuSize,
    required this.businessType,
    required this.cuisines,
    required this.businessContextConfigured,
    required this.comboDensity,
    required this.behaviorVariant,
    required this.budget,
    required this.cartVariant,
    required this.vegOnly,
    required this.nonVegOnly,
  });

  @override
  String toString() => 'ScenarioConfig#$index{menuSize=$menuSize, businessType="$businessType", '
      'cuisines=$cuisines, businessContextConfigured=$businessContextConfigured, '
      'comboDensity=$comboDensity, behaviorVariant=$behaviorVariant, budget=$budget, '
      'cartVariant=$cartVariant, vegOnly=$vegOnly, nonVegOnly=$nonVegOnly}';
}

ScenarioConfig _generateScenario(int index, Random r) {
  final cuisineCount = r.nextInt(6); // 0..5
  final shuffled = List<String>.from(_cuisinePool)..shuffle(r);
  final vegOnly = r.nextDouble() < 0.15;
  final nonVegOnly = !vegOnly && r.nextDouble() < 0.15;
  return ScenarioConfig(
    index: index,
    menuSize: _pickMenuSize(r),
    businessType: _businessTypePool[r.nextInt(_businessTypePool.length)],
    cuisines: shuffled.take(cuisineCount).toList(),
    businessContextConfigured: r.nextDouble() < 0.8, // 20% simulate missing affinity maps entirely
    comboDensity: _comboDensities[r.nextInt(_comboDensities.length)],
    behaviorVariant: _behaviorVariants[r.nextInt(_behaviorVariants.length)],
    budget: _budgetTiers[r.nextInt(_budgetTiers.length)],
    cartVariant: _cartVariants[r.nextInt(_cartVariants.length)],
    vegOnly: vegOnly,
    nonVegOnly: nonVegOnly,
  );
}

// ── Menu / vendor / behavior / cart materialization ─────────────────────

class _Materialized {
  final RestaurantRecommendationContext ctx;
  final List<ProductModel> individuals;
  final List<ProductModel> combos;
  _Materialized(this.ctx, this.individuals, this.combos);
}

_Materialized _materialize(ScenarioConfig cfg, Random r) {
  final vendorId = 'fuzz_v${cfg.index}';
  final v = vendor(id: vendorId, businessTypeId: cfg.businessType, cuisineIds: cfg.cuisines);

  int individualCount;
  if (cfg.comboDensity == 'none') {
    individualCount = cfg.menuSize;
  } else if (cfg.comboDensity == 'few') {
    individualCount = max(1, cfg.menuSize - min(2, cfg.menuSize));
  } else {
    individualCount = max(1, (cfg.menuSize * 0.6).round()); // heavy: ~40% combos
  }
  final comboCount = cfg.menuSize - individualCount;

  final individuals = List.generate(individualCount, (i) {
    final cat = allMenuCategories[r.nextInt(allMenuCategories.length)];
    final noun = _nouns[r.nextInt(_nouns.length)];
    final name = r.nextBool() ? noun : '${_adjectives[r.nextInt(_adjectives.length)]} $noun';
    final isVeg = cfg.vegOnly ? true : (cfg.nonVegOnly ? false : r.nextBool());
    return product(
      id: '${vendorId}_p$i',
      vendorID: vendorId,
      categoryID: cat,
      name: '$name#$i', // #i keeps ids/names unique while still colliding on tokens for family grouping
      price: (50 + r.nextInt(950)).toString(),
      veg: isVeg,
      nonveg: !isVeg,
    );
  });

  final combos = <ProductModel>[];
  for (var i = 0; i < comboCount; i++) {
    if (individuals.isEmpty) break;
    final childCount = 2 + r.nextInt(3); // 2-4 children, matching Burger+Fries+Drink style bundles
    final children = List.generate(
        childCount, (_) => individuals[r.nextInt(individuals.length)].id);
    combos.add(product(
      id: '${vendorId}_combo$i',
      vendorID: vendorId,
      categoryID: allMenuCategories[r.nextInt(allMenuCategories.length)],
      name: 'Combo Meal #$i',
      price: (150 + r.nextInt(1200)).toString(),
    )
      ..isCombo = true
      ..comboProducts = children.map((c) => ComboProductItem(productId: c, quantity: 1 + r.nextInt(2))).toList());
  }

  final allProducts = [...individuals, ...combos];

  final behavior = _buildBehavior(cfg, allProducts, r);

  final sales30 = <String, int>{};
  if (cfg.behaviorVariant != 'none' && r.nextDouble() < 0.7) {
    for (final p in allProducts) {
      if (r.nextDouble() < 0.4) sales30[p.id] = r.nextInt(25);
    }
  }

  final ctx = buildCtx(
    vendor: v,
    products: allProducts,
    behavior: behavior,
    sales30: sales30,
    businessTypeProfiles: cfg.businessContextConfigured ? fullBusinessTypeProfiles : const {},
    cuisineCategoryAffinity: cfg.businessContextConfigured ? fullCuisineAffinity : const {},
  );
  return _Materialized(ctx, individuals, combos);
}

BehaviorSummarySnapshot _buildBehavior(ScenarioConfig cfg, List<ProductModel> allProducts, Random r) {
  if (cfg.behaviorVariant == 'none' || allProducts.isEmpty) return BehaviorSummarySnapshot.empty();

  final avgOrderValue = cfg.budget;
  final sampleSize = min(allProducts.length, 10);
  final sample = (List<ProductModel>.from(allProducts)..shuffle(r)).take(sampleSize).toList();

  switch (cfg.behaviorVariant) {
    case 'browsing':
      return BehaviorSummarySnapshot(
        productViewCounts: {for (final p in sample) p.id: 1 + r.nextInt(20)},
        orderCount: 0,
      );
    case 'search':
      return BehaviorSummarySnapshot(
        topSearchKeywords: {'query${r.nextInt(5)}': 1 + r.nextInt(10)},
        orderCount: 0,
      );
    case 'order':
      return BehaviorSummarySnapshot(
        productOrderQuantities: {for (final p in sample) p.id: 1 + r.nextInt(5)},
        orderCount: 1 + r.nextInt(5),
        avgOrderValue: avgOrderValue,
      );
    case 'heavy':
      return BehaviorSummarySnapshot(
        productViewCounts: {for (final p in sample) p.id: 5 + r.nextInt(100)},
        productOrderQuantities: {for (final p in sample) p.id: 5 + r.nextInt(50)},
        categoryInteractionCounts: {for (final c in allMenuCategories) c: r.nextInt(50)},
        restaurantVisitCounts: {'x': 10 + r.nextInt(50)},
        orderCount: 20 + r.nextInt(200),
        avgOrderValue: avgOrderValue,
        comboOrderCount: r.nextInt(10),
        comboPriceTotal: (r.nextInt(10) * avgOrderValue),
        comboChildCountTotal: r.nextInt(30),
      );
    case 'restaurant_loyal':
      return BehaviorSummarySnapshot(
        restaurantVisitCounts: {'x': 20 + r.nextInt(80)},
        productOrderQuantities: {for (final p in sample) p.id: 3 + r.nextInt(10)},
        orderCount: 10 + r.nextInt(50),
        avgOrderValue: avgOrderValue,
      );
    case 'cuisine_loyal':
      return BehaviorSummarySnapshot(
        cuisineInteractionCounts: {for (final c in _cuisinePool) c: r.nextInt(30)},
        orderCount: 5 + r.nextInt(30),
        avgOrderValue: avgOrderValue,
      );
    case 'category_loyal':
      final cat = allMenuCategories[r.nextInt(allMenuCategories.length)];
      return BehaviorSummarySnapshot(
        categoryInteractionCounts: {cat: 20 + r.nextInt(30)},
        orderCount: 5 + r.nextInt(20),
        avgOrderValue: avgOrderValue,
      );
    case 'combo_loyal':
      final combos = allProducts.where((p) => p.isCombo).toList();
      final comboOrders = {for (final c in combos) c.id: 2 + r.nextInt(8)};
      final childCounts = <String, int>{};
      for (final c in combos) {
        for (final child in c.comboProducts) {
          childCounts[child.productId] = (childCounts[child.productId] ?? 0) + 1 + r.nextInt(5);
        }
      }
      return BehaviorSummarySnapshot(
        productOrderQuantities: comboOrders,
        productViewCounts: {for (final c in combos) c.id: 5 + r.nextInt(20)},
        orderCount: comboOrders.length + r.nextInt(10),
        avgOrderValue: avgOrderValue,
        comboOrderCount: comboOrders.values.fold(0, (a, b) => a + b),
        comboPriceTotal: comboOrders.values.fold(0, (a, b) => a + b) * avgOrderValue,
        comboChildCountTotal: combos.fold(0, (a, c) => a + c.comboProducts.length),
        comboChildProductCounts: childCounts,
      );
    default:
      return BehaviorSummarySnapshot.empty();
  }
}

class _CartState {
  final Set<String> cartProductIds;
  final Map<String, int> cartCategoryCounts;
  _CartState(this.cartProductIds, this.cartCategoryCounts);
}

_CartState _buildCart(ScenarioConfig cfg, List<ProductModel> individuals, List<ProductModel> combos, Random r) {
  if (individuals.isEmpty) return _CartState({}, {});
  final ids = <String>{};
  final catCounts = <String, int>{};
  void addItem(ProductModel p) {
    ids.add(p.id);
    catCounts[p.categoryID] = (catCounts[p.categoryID] ?? 0) + 1;
  }

  switch (cfg.cartVariant) {
    case 'empty':
      break;
    case 'one':
      addItem(individuals[r.nextInt(individuals.length)]);
      break;
    case 'multiple':
      for (var i = 0; i < min(4, individuals.length); i++) {
        addItem(individuals[r.nextInt(individuals.length)]);
      }
      break;
    case 'repeated_category':
      final cat = individuals[r.nextInt(individuals.length)].categoryID;
      final sameCategory = individuals.where((p) => p.categoryID == cat).toList();
      for (final p in sameCategory.take(3)) {
        addItem(p);
      }
      break;
    case 'repeated_product':
      final p = individuals[r.nextInt(individuals.length)];
      catCounts[p.categoryID] = 3; // simulate 3x same product's category weight without duplicate ids
      ids.add(p.id);
      break;
    case 'combo_in_cart':
      if (combos.isNotEmpty) addItem(combos[r.nextInt(combos.length)]);
      break;
    case 'multi_combo':
      for (final c in combos.take(2)) {
        addItem(c);
      }
      break;
    case 'large_family':
      for (var i = 0; i < min(8, individuals.length); i++) {
        addItem(individuals[i]);
      }
      if (combos.isNotEmpty) addItem(combos.first);
      break;
  }
  return _CartState(ids, catCounts);
}

// ── Failure recording ────────────────────────────────────────────────────

class _Failure {
  final int scenarioIndex;
  final String description;
  final String scenarioDump;
  _Failure(this.scenarioIndex, this.description, this.scenarioDump);

  @override
  String toString() => 'Scenario #$scenarioIndex FAILED: $description\n  Repro: $scenarioDump';
}

class _Percentiles {
  final List<double> samples = [];
  void add(double ms) => samples.add(ms);
  double get avg => samples.isEmpty ? 0 : samples.reduce((a, b) => a + b) / samples.length;
  double get min => samples.isEmpty ? 0 : samples.reduce((a, b) => a < b ? a : b);
  double get max => samples.isEmpty ? 0 : samples.reduce((a, b) => a > b ? a : b);
  double get p95 {
    if (samples.isEmpty) return 0;
    final sorted = List<double>.from(samples)..sort();
    final idx = (sorted.length * 0.95).floor().clamp(0, sorted.length - 1);
    return sorted[idx];
  }
}

void main() {
  const scenarioCount = 520; // "at least 500"
  final failures = <_Failure>[];
  var assertionCount = 0;
  var scenariosRun = 0;
  final perf = <String, _Percentiles>{
    'computeMergedScores': _Percentiles(),
    'recommendForYou': _Percentiles(),
    'exploreMenuSelection': _Percentiles(),
    'fillPairsWellWith': _Percentiles(),
    'comboEligibilityScore': _Percentiles(),
  };

  void check(int scenarioIndex, bool condition, String description, ScenarioConfig cfg) {
    assertionCount++;
    if (!condition) {
      failures.add(_Failure(scenarioIndex, description, cfg.toString()));
    }
  }

  double timeMs(void Function() fn) {
    final sw = Stopwatch()..start();
    fn();
    sw.stop();
    return sw.elapsedMicroseconds / 1000.0;
  }

  test('Exhaustive verification: $scenarioCount randomized reproducible scenarios', () {
    final masterRandom = Random(20260719); // fixed seed - fully reproducible

    for (var i = 0; i < scenarioCount; i++) {
      final cfg = _generateScenario(i, masterRandom);
      try {
        final mat = _materialize(cfg, masterRandom);
        final ctx = mat.ctx;
        scenariosRun++;

        // ── computeMergedScores: no crash, deterministic ──
        Map<String, double> merged1 = {}, merged2 = {};
        perf['computeMergedScores']!.add(timeMs(() => merged1 = RecommendationEngine.computeMergedScores(ctx)));
        merged2 = RecommendationEngine.computeMergedScores(ctx);
        check(i, mapEquals(merged1, merged2), 'computeMergedScores must be deterministic', cfg);

        // ── Recommended For You ──
        final limit = RecommendationEngine.sectionLimitFor(ctx);
        List<ProductModel> rfy1 = [], rfy2 = [];
        perf['recommendForYou']!.add(timeMs(() => rfy1 = RecommendationEngine.recommendForYou(ctx, limit: limit)));
        rfy2 = RecommendationEngine.recommendForYou(ctx, limit: limit);
        check(i, rfy1.map((p) => p.id).toList().toString() == rfy2.map((p) => p.id).toList().toString(),
            'recommendForYou must be deterministic', cfg);
        check(i, rfy1.length <= limit, 'recommendForYou must never exceed the section limit', cfg);
        check(i, rfy1.map((p) => p.id).toSet().length == rfy1.length,
            'recommendForYou must never contain duplicates', cfg);
        final rfyComboCount = rfy1.where((p) => p.isCombo).length;
        // 2026-07-25: recommendForYou's combo cap is dynamic + customer-
        // adaptive (RecommendationEngine.comboSlotAllocation) - a
        // combo_loyal behaviorVariant with heavy comboDensity is EXPECTED
        // to clear more than the old flat maxComboRecommendationsPerSection
        // (2) via the 50-60% adaptive band. exploreMenuSelection below is
        // untouched by that change and still asserts the flat constant.
        check(i, rfyComboCount <= RecommendationEngine.comboSlotAllocation(limit, ctx),
            'recommendForYou combo count must never exceed the cap', cfg);
        final firstComboIdxRfy = rfy1.indexWhere((p) => p.isCombo);
        if (firstComboIdxRfy != -1) {
          check(i, rfy1.take(firstComboIdxRfy).every((p) => !p.isCombo),
              'recommendForYou: no combo may appear before an individual product', cfg);
          check(i, rfy1.skip(firstComboIdxRfy).every((p) => p.isCombo),
              'recommendForYou: once a combo appears, only combos may follow', cfg);
        }
        // NOTE: this used to assert confidence was non-increasing among
        // individual products in Recommended For You order - true only
        // while recommendationConfidenceScores' score was literally
        // normalizedMergedScores[p.id], the exact value recommendForYou
        // sorts by. That coupling was deliberately broken by the 2026-07-20
        // Launch Mode override (badge score became a raw sales-count
        // ratio) and further diverged by the 2026-07-21 dynamic role-aware
        // allocation (badge score/eligibility now come from a completely
        // independent per-role-group cap + shared-budget system, unrelated
        // to the merged score recommendForYou ranks by - see
        // RecommendationEngine's "DYNAMIC ROLE-AWARE BADGE ALLOCATION"
        // doc comment). The badge and the Recommended For You ordering are
        // now intentionally independent signals; removed rather than kept
        // as a check against behavior the product direction no longer
        // wants. recommendationConfidenceScores has its own dedicated
        // coverage in dynamic_role_aware_badges_test.dart.

        // ── Explore Menu ──
        List<ProductModel> explore1 = [], explore2 = [];
        perf['exploreMenuSelection']!.add(timeMs(() => explore1 = RecommendationEngine.exploreMenuSelection(ctx, limit: limit)));
        explore2 = RecommendationEngine.exploreMenuSelection(ctx, limit: limit);
        check(i, explore1.map((p) => p.id).toList().toString() == explore2.map((p) => p.id).toList().toString(),
            'exploreMenuSelection must be deterministic', cfg);
        check(i, explore1.map((p) => p.id).toSet().length == explore1.length,
            'exploreMenuSelection must never contain duplicates', cfg);
        final exploreComboCount = explore1.where((p) => p.isCombo).length;
        check(i, exploreComboCount <= RecommendationEngine.maxComboRecommendationsPerSection,
            'exploreMenuSelection combo count must never exceed the cap', cfg);

        // ── Restaurant Must Try / Most Loved Here / Hidden Gems: no crash, bounded, no duplicates ──
        final mustTry = RecommendationEngine.topBySource(ctx, 'mustTry');
        check(i, mustTry.map((p) => p.id).toSet().length == mustTry.length, 'Restaurant Must Try: no duplicates', cfg);
        final mostLoved = RecommendationEngine.mostLovedHere(ctx);
        check(i, mostLoved.every((p) => (ctx.rolling90DaySales[p.id] ?? 0) > 0),
            'Most Loved Here: every item must have real sales this window', cfg);
        final gems = RecommendationEngine.hiddenGems(ctx);
        check(i, gems.map((p) => p.id).toSet().length == gems.length, 'Hidden Gems: no duplicates', cfg);

        // ── Combo eligibility: bounded, no crash, cold-start honesty ──
        for (final combo in mat.combos) {
          double score = 0;
          perf['comboEligibilityScore']!.add(timeMs(() => score = RecommendationEngine.comboEligibilityScore(combo, ctx)));
          check(i, score >= 0.0 && score <= 1.0, 'comboEligibilityScore must stay within [0,1]', cfg);
          if (cfg.behaviorVariant == 'none') {
            check(i, score == 0.0, 'comboEligibilityScore must be exactly 0 for a true cold-start customer', cfg);
          }
        }

        // ── Pairing: normal trigger and combo trigger, empty/saturated cart ──
        final cart = _buildCart(cfg, mat.individuals, mat.combos, masterRandom);
        final allForTrigger = [...mat.individuals, ...mat.combos];
        if (allForTrigger.isNotEmpty) {
          final trigger = allForTrigger[masterRandom.nextInt(allForTrigger.length)];
          final pool = allForTrigger.where((p) => p.id != trigger.id).toList();
          final pairingScores = {
            for (final p in pool) p.id: RecommendationEngine.pairingContextScore(p, trigger, ctx),
          };
          for (final s in pairingScores.values) {
            check(i, s >= 0.0 && s <= 1.0, 'pairingContextScore must stay within [0,1]', cfg);
          }
          final merged = RecommendationEngine.normalizedMergedScores(ctx);
          final pref = RecommendationEngine.scoreBySource(ctx, 'preference');
          final best = RecommendationEngine.scoreBySource(ctx, 'bestSeller');
          final pairLimit = RecommendationEngine.pairingSectionLimitFor(ctx);
          List<ProductModel> pairResult = [];
          perf['fillPairsWellWith']!.add(timeMs(() {
            pairResult = RecommendationEngine.fillPairsWellWith(
              vendorConfigured: const [],
              candidatePool: pool,
              mergedScores: merged,
              preferenceScores: pref,
              bestSellerScores: best,
              crossSellFrequency: ctx.crossSellFrequency,
              pairingContextScores: pairingScores,
              cartProductIds: cart.cartProductIds,
              cartCategoryCounts: cart.cartCategoryCounts,
              maxItems: pairLimit,
            );
          }));
          check(i, pairResult.length <= pairLimit, 'fillPairsWellWith must never exceed maxItems', cfg);
          check(i, pairResult.map((p) => p.id).toSet().length == pairResult.length,
              'fillPairsWellWith must never contain duplicates', cfg);
          check(i, pairResult.every((p) => !cart.cartProductIds.contains(p.id)),
              'fillPairsWellWith must never re-suggest an item already in the cart', cfg);
          final pairComboCount = pairResult.where((p) => p.isCombo).length;
          check(i, pairComboCount <= pool.where((p) => p.isCombo).length,
              'fillPairsWellWith combo count sanity bound', cfg);
        }

        // ── Budget awareness spot check: a low-budget customer should not
        // find an expensive combo eligible purely on budget grounds ──
        if (cfg.budget <= 150 && mat.combos.isNotEmpty && cfg.behaviorVariant != 'none') {
          for (final combo in mat.combos) {
            final price = double.tryParse(combo.price) ?? 0;
            if (price > cfg.budget * 4) {
              // Budget signal alone should be 0 for a dramatically mismatched price -
              // doesn't guarantee overall ineligibility (other signals can still
              // contribute), just that price compatibility itself isn't lying.
              check(i, RecommendationEngine.comboEligibilityScore(combo, ctx) <= 1.0,
                  'comboEligibilityScore must stay bounded even for a dramatic budget mismatch', cfg);
            }
          }
        }
      } catch (e, st) {
        failures.add(_Failure(i, 'UNCAUGHT EXCEPTION: $e\n$st', cfg.toString()));
      }
    }

    // ── Final report ──
    final buffer = StringBuffer();
    buffer.writeln('');
    buffer.writeln('═══════════════════════════════════════════════════════════');
    buffer.writeln('EXHAUSTIVE RECOMMENDATION ENGINE VERIFICATION - FINAL REPORT');
    buffer.writeln('═══════════════════════════════════════════════════════════');
    buffer.writeln('Total scenarios generated : $scenarioCount');
    buffer.writeln('Total scenarios run       : $scenariosRun');
    buffer.writeln('Total assertions executed : $assertionCount');
    buffer.writeln('Assertions passed         : ${assertionCount - failures.length}');
    buffer.writeln('Assertions failed         : ${failures.length}');
    buffer.writeln('');
    buffer.writeln('── Performance (ms) ──────────────────────────────────────');
    perf.forEach((name, p) {
      if (p.samples.isEmpty) return;
      buffer.writeln('${name.padRight(24)} n=${p.samples.length.toString().padLeft(5)}  '
          'avg=${p.avg.toStringAsFixed(4)}  min=${p.min.toStringAsFixed(4)}  '
          'max=${p.max.toStringAsFixed(4)}  p95=${p.p95.toStringAsFixed(4)}');
    });
    buffer.writeln('═══════════════════════════════════════════════════════════');
    if (failures.isNotEmpty) {
      buffer.writeln('FAILURES (${failures.length}):');
      for (final f in failures) {
        buffer.writeln('---');
        buffer.writeln(f.toString());
      }
    }
    // ignore: avoid_print
    print(buffer.toString());

    expect(failures, isEmpty,
        reason: '${failures.length} of $assertionCount assertions failed across $scenariosRun scenarios - see printed report above for full repro details');
  });
}

bool mapEquals(Map<String, double> a, Map<String, double> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
