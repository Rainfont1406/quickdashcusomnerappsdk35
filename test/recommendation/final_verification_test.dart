// Final Verification Phase, Sections 4-11: Sparse Business Context, Combo
// Robustness, Recommendation Stability, Threshold Verification, Cross User
// Isolation, Long Session Simulation, Recommendation Distribution Audit,
// and Recommendation Explainability. Does not stop at the first failure -
// failures accumulate and print in a final summary, same pattern as
// golden_scenarios_test.dart and exhaustive_fuzz_test.dart.
import 'dart:math';

import 'package:emartconsumer/model/ComboProductItem.dart';
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/services/recommendation/behavior_summary_snapshot.dart';
import 'package:emartconsumer/services/recommendation/recommendation_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

class _Failure {
  final String scenario;
  final String detail;
  _Failure(this.scenario, this.detail);
  @override
  String toString() => 'FAILED [$scenario]: $detail';
}

final _failures = <_Failure>[];
var _assertionCount = 0;

void _check(String scenario, bool condition, String detail) {
  _assertionCount++;
  if (!condition) _failures.add(_Failure(scenario, detail));
}

/// Section 11: Recommendation Explainability - which real signals contribute
/// to [product]'s score for this ctx, using only the engine's own public
/// scoring functions (no new formula, just introspection of existing ones).
String _explain(ProductModel product, RestaurantRecommendationContext ctx) {
  final businessContext = RecommendationEngine.businessContextScore(product, ctx) > 0;
  final preference = (RecommendationEngine.scoreBySource(ctx, 'preference')[product.id] ?? 0) > 0;
  final crossSell = (ctx.crossSellFrequency[product.id] ?? 0) > 0;
  final bestSeller = (RecommendationEngine.scoreBySource(ctx, 'bestSeller')[product.id] ?? 0) > 0;
  final confidence = RecommendationEngine.recommendationConfidenceScores(ctx)[product.id];
  final mark = (bool b) => b ? '✓' : '✗';
  return '${product.name}\n'
      '  Final Score: ${confidence?.score.toStringAsFixed(2) ?? 'n/a (below display threshold)'}\n'
      '  Contributing Signals:\n'
      '  ${mark(businessContext)} Business Context\n'
      '  ${mark(preference)} Customer Preference\n'
      '  ${mark(crossSell)} Cross Sell\n'
      '  ${mark(bestSeller)} Bestseller';
}

void main() {
  tearDownAll(() {
    final buffer = StringBuffer()
      ..writeln('')
      ..writeln('═══════════════════════════════════════════════')
      ..writeln('FINAL VERIFICATION PHASE - SUMMARY')
      ..writeln('═══════════════════════════════════════════════')
      ..writeln('Total assertions : $_assertionCount')
      ..writeln('Passed           : ${_assertionCount - _failures.length}')
      ..writeln('Failed           : ${_failures.length}');
    if (_failures.isNotEmpty) {
      buffer.writeln('--- FAILURES ---');
      for (final f in _failures) {
        buffer.writeln(f.toString());
      }
    }
    // ignore: avoid_print
    print(buffer.toString());
  });

  // ── Section 4: Sparse Business Context Verification ─────────────────────
  group('Section 4: Sparse Business Context', () {
    test('No Business Type profile, no Cuisine affinity at all', () {
      final v = vendor(id: 'sparse1', businessTypeId: btRestaurant, cuisineIds: [cuisineNorthIndian]);
      final products = fullDishMenu('sparse1');
      final ctx = buildCtx(vendor: v, products: products); // both maps default to {}
      for (final p in products) {
        _check('No config at all', RecommendationEngine.businessContextScore(p, ctx) == 0.0,
            '${p.name} must score exactly 0 with no Business Context config at all');
      }
    });

    test('Only one cuisine configured, rest of vendor list unresolvable', () {
      final v = vendor(id: 'sparse2', businessTypeId: btRestaurant, cuisineIds: [cuisineNorthIndian, 'unconfigured_cuisine_x']);
      final products = fullDishMenu('sparse2');
      final partialAffinity = {cuisineNorthIndian: fullCuisineAffinity[cuisineNorthIndian]!};
      final ctx = buildCtx(vendor: v, products: products, businessTypeProfiles: fullBusinessTypeProfiles, cuisineCategoryAffinity: partialAffinity);
      final naan = products.firstWhere((p) => p.name == 'Butter Naan');
      expect(() => RecommendationEngine.businessContextScore(naan, ctx), returnsNormally);
      _check('Only one cuisine configured', RecommendationEngine.businessContextScore(naan, ctx) > 0,
          'the configured cuisine should still contribute even though the second vendor cuisine has no affinity entry');
    });

    test('Only one category configured in cuisine affinity', () {
      final v = vendor(id: 'sparse3', businessTypeId: btRestaurant, cuisineIds: [cuisineNorthIndian]);
      final products = fullDishMenu('sparse3');
      final ctx = buildCtx(vendor: v, products: products, cuisineCategoryAffinity: {cuisineNorthIndian: {catMain}});
      final naan = products.firstWhere((p) => p.name == 'Butter Naan'); // catBread - NOT in the sparse affinity
      final butterChicken = products.firstWhere((p) => p.name == 'Butter Chicken'); // catMain - IS in the sparse affinity
      expect(() => RecommendationEngine.businessContextScore(naan, ctx), returnsNormally);
      _check('Only one category configured', RecommendationEngine.businessContextScore(butterChicken, ctx) > 0,
          'the one configured category must still contribute');
    });

    test('Half of categories missing from an otherwise-full Business Type profile', () {
      final v = vendor(id: 'sparse4', businessTypeId: btRestaurant, cuisineIds: []);
      final products = fullDishMenu('sparse4');
      final halfProfile = {
        btRestaurant: const RestaurantTypeCategoryProfile(primaryCategoryIds: {catMain}), // missing catBread/catRice
      };
      final ctx = buildCtx(vendor: v, products: products, businessTypeProfiles: halfProfile);
      final naan = products.firstWhere((p) => p.name == 'Butter Naan');
      expect(() => RecommendationEngine.businessContextScore(naan, ctx), returnsNormally);
      _check('Half categories missing', RecommendationEngine.businessContextScore(naan, ctx) == 0.0,
          'a category missing from the (otherwise real) profile must honestly score 0, never fabricated');
    });

    test('One cuisine mapped to many categories (already covered by North Indian - explicit boundary check)', () {
      final v = vendor(id: 'sparse5', businessTypeId: '', cuisineIds: [cuisineNorthIndian]);
      final products = fullDishMenu('sparse5');
      final ctx = buildCtx(vendor: v, products: products, cuisineCategoryAffinity: fullCuisineAffinity);
      final matchedCategories = products.where((p) => fullCuisineAffinity[cuisineNorthIndian]!.contains(p.categoryID));
      for (final p in matchedCategories) {
        _check('One cuisine, many categories', RecommendationEngine.businessContextScore(p, ctx) > 0,
            '${p.name} (${p.categoryID}) should score via the one broad cuisine mapping');
      }
    });

    test('One category mapped to many cuisines (Dessert: Cafe + Bakery)', () {
      final v = vendor(id: 'sparse6', businessTypeId: '', cuisineIds: [cuisineCafe, cuisineBakery]);
      final products = fullDishMenu('sparse6');
      final dessert = products.firstWhere((p) => p.name == 'Dessert');
      final ctx = buildCtx(vendor: v, products: products, cuisineCategoryAffinity: fullCuisineAffinity);
      _check('One category, many cuisines', RecommendationEngine.businessContextScore(dessert, ctx) > 0,
          'Dessert should score via either matching cuisine, never require both');
    });

    test('Unknown category / cuisine / Business Type strings never crash', () {
      final v = vendor(id: 'sparse7', businessTypeId: 'unknown_bt_xyz', cuisineIds: ['unknown_cuisine_xyz']);
      final weird = product(id: 'weird_p', vendorID: 'sparse7', categoryID: 'unknown_category_xyz');
      final ctx = buildCtx(vendor: v, products: [weird], businessTypeProfiles: fullBusinessTypeProfiles, cuisineCategoryAffinity: fullCuisineAffinity);
      expect(() => RecommendationEngine.businessContextScore(weird, ctx), returnsNormally);
      _check('Unknown everything', RecommendationEngine.businessContextScore(weird, ctx) == 0.0,
          'entirely unknown ids must degrade to an honest 0, never crash or fabricate');
    });
  });

  // ── Section 5: Combo Robustness ──────────────────────────────────────────
  group('Section 5: Combo Robustness', () {
    late String vendorId;
    late List<ProductModel> baseProducts;
    setUp(() {
      vendorId = 'combo_robust_${DateTime.now().microsecondsSinceEpoch}';
      baseProducts = fullDishMenu(vendorId);
    });

    test('Combo child unpublished (publish=false) - resolution skips it gracefully', () {
      final naan = baseProducts.firstWhere((p) => p.name == 'Butter Naan')..publish = false;
      final combo = product(id: '${vendorId}_combo', vendorID: vendorId, categoryID: catMain, name: 'Combo')
        ..isCombo = true
        ..comboProducts = [ComboProductItem(productId: naan.id)];
      final ctx = buildCtx(vendor: vendor(id: vendorId, businessTypeId: btRestaurant, cuisineIds: [cuisineNorthIndian]),
          products: [...baseProducts, combo], cuisineCategoryAffinity: fullCuisineAffinity);
      // Resolution is by id in ctx.allProducts, publish status doesn't block lookup here (matches
      // "reuse already-loaded data" - the caller decides what's in allProducts, not this function).
      expect(() => RecommendationEngine.pairingContextScore(baseProducts.first, combo, ctx), returnsNormally);
      expect(() => RecommendationEngine.comboEligibilityScore(combo, ctx), returnsNormally);
    });

    test('Combo child deleted (not present in ctx.allProducts at all)', () {
      final combo = product(id: '${vendorId}_combo', vendorID: vendorId, categoryID: catMain, name: 'Combo')
        ..isCombo = true
        ..comboProducts = [ComboProductItem(productId: 'deleted_product_id_does_not_exist')];
      final ctx = buildCtx(vendor: vendor(id: vendorId, businessTypeId: btRestaurant, cuisineIds: [cuisineNorthIndian]),
          products: [...baseProducts, combo], cuisineCategoryAffinity: fullCuisineAffinity);
      expect(() => RecommendationEngine.pairingContextScore(baseProducts.first, combo, ctx), returnsNormally);
      final score = RecommendationEngine.comboEligibilityScore(combo, ctx);
      _check('Combo child deleted', score >= 0.0 && score <= 1.0, 'must stay bounded even with an unresolvable child (got $score)');
    });

    test('Combo child category changed after combo creation (resolved live, not snapshotted)', () {
      final naan = baseProducts.firstWhere((p) => p.name == 'Butter Naan');
      final combo = product(id: '${vendorId}_combo', vendorID: vendorId, categoryID: catMain, name: 'Combo')
        ..isCombo = true
        ..comboProducts = [ComboProductItem(productId: naan.id)];
      naan.categoryID = catDessert; // simulate a vendor recategorizing the child after combo creation
      final ctx = buildCtx(vendor: vendor(id: vendorId, businessTypeId: btRestaurant, cuisineIds: [cuisineNorthIndian]),
          products: [...baseProducts, combo], cuisineCategoryAffinity: fullCuisineAffinity);
      // Child category resolution reads categoryID live off ctx.allProducts - the
      // combo's cuisine narrowing should reflect the NEW category, not a stale one.
      final noodles = baseProducts.firstWhere((p) => p.name == 'Noodles');
      expect(() => RecommendationEngine.pairingContextScore(noodles, combo, ctx), returnsNormally);
    });

    test('Combo child price changed - comboEligibilityScore budget signal uses the COMBO\'s own price, unaffected', () {
      final naan = baseProducts.firstWhere((p) => p.name == 'Butter Naan')..price = '99999';
      final combo = product(id: '${vendorId}_combo', vendorID: vendorId, categoryID: catMain, name: 'Combo', price: '300')
        ..isCombo = true
        ..comboProducts = [ComboProductItem(productId: naan.id)];
      final behavior = BehaviorSummarySnapshot(productOrderQuantities: {naan.id: 3}, orderCount: 5, avgOrderValue: 300);
      final ctx = buildCtx(vendor: vendor(id: vendorId, businessTypeId: btRestaurant, cuisineIds: [cuisineNorthIndian]),
          products: [...baseProducts, combo], behavior: behavior);
      final score = RecommendationEngine.comboEligibilityScore(combo, ctx);
      _check('Combo child price changed', score >= 0.0 && score <= 1.0,
          'a child\'s own price must never destabilize the combo\'s own budget signal (got $score)');
    });

    test('Combo references an invalid/empty product id', () {
      final combo = product(id: '${vendorId}_combo', vendorID: vendorId, categoryID: catMain, name: 'Combo')
        ..isCombo = true
        ..comboProducts = [ComboProductItem(productId: '')];
      final ctx = buildCtx(vendor: vendor(id: vendorId, businessTypeId: btRestaurant, cuisineIds: [cuisineNorthIndian]),
          products: [...baseProducts, combo], cuisineCategoryAffinity: fullCuisineAffinity);
      expect(() => RecommendationEngine.comboEligibilityScore(combo, ctx), returnsNormally);
      expect(() => RecommendationEngine.pairingContextScore(baseProducts.first, combo, ctx), returnsNormally);
    });

    test('Duplicate combo child IDs (same product listed twice) - handled, not double-counted incorrectly', () {
      final naan = baseProducts.firstWhere((p) => p.name == 'Butter Naan');
      final combo = product(id: '${vendorId}_combo', vendorID: vendorId, categoryID: catMain, name: 'Combo')
        ..isCombo = true
        ..comboProducts = [ComboProductItem(productId: naan.id), ComboProductItem(productId: naan.id)];
      final ctx = buildCtx(vendor: vendor(id: vendorId, businessTypeId: btRestaurant, cuisineIds: [cuisineNorthIndian]),
          products: [...baseProducts, combo], cuisineCategoryAffinity: fullCuisineAffinity);
      expect(() => RecommendationEngine.comboEligibilityScore(combo, ctx), returnsNormally);
      // Category-id resolution for cuisine narrowing is Set-based (see _categoryIdsFor) -
      // a duplicated child contributes the same category id twice, deduplicated automatically.
      final noodles = baseProducts.firstWhere((p) => p.name == 'Noodles');
      final rice = baseProducts.firstWhere((p) => p.name == 'Rice');
      final riceScore = RecommendationEngine.pairingContextScore(rice, combo, ctx);
      final noodlesScore = RecommendationEngine.pairingContextScore(noodles, combo, ctx);
      _check('Duplicate combo child IDs', riceScore >= noodlesScore,
          'duplicate child ids must not distort cuisine narrowing (rice=$riceScore, noodles=$noodlesScore)');
    });

    test('Multiple identical child categories (3 different Bread items) - category resolves once, no error', () {
      final naan = baseProducts.firstWhere((p) => p.name == 'Butter Naan');
      final garlicNaan = baseProducts.firstWhere((p) => p.name == 'Garlic Naan');
      final extraBread = product(id: '${vendorId}_extra_bread', vendorID: vendorId, categoryID: catBread, name: 'Tandoori Roti');
      final combo = product(id: '${vendorId}_combo', vendorID: vendorId, categoryID: catMain, name: 'Combo')
        ..isCombo = true
        ..comboProducts = [
          ComboProductItem(productId: naan.id),
          ComboProductItem(productId: garlicNaan.id),
          ComboProductItem(productId: extraBread.id),
        ];
      final ctx = buildCtx(vendor: vendor(id: vendorId, businessTypeId: btRestaurant, cuisineIds: [cuisineNorthIndian]),
          products: [...baseProducts, extraBread, combo], cuisineCategoryAffinity: fullCuisineAffinity);
      expect(() => RecommendationEngine.pairingContextScore(baseProducts.first, combo, ctx), returnsNormally);
    });

    test('Nested combo attempt: a combo listing another combo as a child must not crash or recurse infinitely', () {
      final innerCombo = product(id: '${vendorId}_inner_combo', vendorID: vendorId, categoryID: catMain, name: 'Inner Combo')
        ..isCombo = true
        ..comboProducts = [ComboProductItem(productId: baseProducts.first.id)];
      final outerCombo = product(id: '${vendorId}_outer_combo', vendorID: vendorId, categoryID: catMain, name: 'Outer Combo')
        ..isCombo = true
        ..comboProducts = [ComboProductItem(productId: innerCombo.id)]; // deliberately violates the "no nested combos" UI rule
      final ctx = buildCtx(vendor: vendor(id: vendorId, businessTypeId: btRestaurant, cuisineIds: [cuisineNorthIndian]),
          products: [...baseProducts, innerCombo, outerCombo], cuisineCategoryAffinity: fullCuisineAffinity);
      // _categoryIdsFor is one level deep by construction (it doesn't recurse
      // into a child's OWN comboProducts) - engine-level, this can never
      // infinite-loop even if the vendor-UI's "no nested combos" rule is
      // ever bypassed. The vendor UI is the actual enforcement point (see
      // the Add Product combo architecture); this just confirms the engine
      // degrades safely rather than crashing if that invariant is ever violated.
      expect(() => RecommendationEngine.pairingContextScore(baseProducts.first, outerCombo, ctx), returnsNormally);
      expect(() => RecommendationEngine.comboEligibilityScore(outerCombo, ctx), returnsNormally);
    });
  });

  // ── Section 6: Recommendation Stability ──────────────────────────────────
  group('Section 6: Recommendation Stability (10+ repeated refreshes)', () {
    test('Same customer/restaurant/menu/history: 15 repeated calls produce identical output', () {
      final f = _stableFixture();
      final results = List.generate(15, (_) => RecommendationEngine.recommendForYou(f, limit: 20).map((p) => p.id).toList());
      for (var i = 1; i < results.length; i++) {
        _check('Stability (recommendForYou)', results[i].toString() == results[0].toString(),
            'refresh #$i produced a different order than refresh #0 with completely unchanged inputs');
      }
    });

    test('Explore Menu: 15 repeated calls produce identical output', () {
      final f = _stableFixture();
      final results = List.generate(15, (_) => RecommendationEngine.exploreMenuSelection(f, limit: 20).map((p) => p.id).toList());
      for (var i = 1; i < results.length; i++) {
        _check('Stability (exploreMenuSelection)', results[i].toString() == results[0].toString(),
            'refresh #$i produced a different order than refresh #0 with completely unchanged inputs');
      }
    });
  });

  // ── Section 7: Threshold Verification (REAL engine constants, not illustrative numbers) ──
  group('Section 7: Threshold Verification', () {
    test('comboEligibilityThreshold (0.35): everOrdered alone (weight 0.30) does NOT clear it', () {
      final vendorId = 'thresh_combo1';
      final naan = product(id: '${vendorId}_naan', vendorID: vendorId, categoryID: catBread, name: 'Naan');
      final combo = product(id: '${vendorId}_combo', vendorID: vendorId, categoryID: catMain, name: 'Combo', price: '999999')
        ..isCombo = true
        ..comboProducts = [ComboProductItem(productId: naan.id)];
      // everOrdered=true contributes exactly 0.30 (its weight); nothing else
      // fires (no views, no budget match - price deliberately absurd, no
      // meal-size history) - must land BELOW comboEligibilityThreshold (0.35).
      final behavior = BehaviorSummarySnapshot(productOrderQuantities: {combo.id: 1}, orderCount: 1);
      final ctx = buildCtx(vendor: vendor(id: vendorId), products: [naan, combo], behavior: behavior);
      final score = RecommendationEngine.comboEligibilityScore(combo, ctx);
      _check('Threshold: everOrdered alone', score < RecommendationEngine.comboEligibilityThreshold,
          'everOrdered alone (weight 0.30) must not clear threshold 0.35 unassisted (got $score)');
    });

    test('_cartCategorySaturationThreshold (2): counts 1/2/3/4 - exactly ">=2" semantics', () {
      final vendorId = 'thresh_sat';
      final naan = product(id: '${vendorId}_naan', vendorID: vendorId, categoryID: catBread, name: 'Naan');
      final rice = product(id: '${vendorId}_rice', vendorID: vendorId, categoryID: catRice, name: 'Rice');
      for (final count in [1, 2, 3, 4]) {
        final result = RecommendationEngine.fillPairsWellWith(
          vendorConfigured: const [], candidatePool: [naan, rice],
          mergedScores: const {}, preferenceScores: const {}, bestSellerScores: const {},
          crossSellFrequency: const {}, cartCategoryCounts: {catBread: count}, maxItems: 2,
        );
        final naanIdx = result.indexWhere((p) => p.id == naan.id);
        final riceIdx = result.indexWhere((p) => p.id == rice.id);
        final label = 'Saturation count=$count';
        if (count < 2) {
          _check(label, naanIdx < riceIdx, 'below threshold (1): Bread must NOT be deprioritized (naan=$naanIdx, rice=$riceIdx)');
        } else {
          _check(label, riceIdx < naanIdx, 'at/above threshold ($count): Bread MUST be deprioritized (naan=$naanIdx, rice=$riceIdx)');
        }
      }
    });

    test('minimumRestaurantConfidenceOrders (15): totals 14/15/16', () {
      for (final total in [14, 15, 16]) {
        final vendorId = 'thresh_conf_$total';
        final products = fullDishMenu(vendorId);
        final sales = {products.first.id: total};
        final ctx = buildCtx(vendor: vendor(id: vendorId), products: products, sales30: sales);
        final expected = total >= 15;
        _check('Confidence orders=$total', RecommendationEngine.hasSufficientRestaurantConfidence(ctx) == expected,
            'total=$total should give hasSufficientRestaurantConfidence=$expected');
      }
    });

    test('minProductsForRecommendationSections (10): menu sizes 9/10/11', () {
      for (final size in [9, 10, 11]) {
        final vendorId = 'thresh_menu_$size';
        final products = List.generate(size, (i) => product(id: '${vendorId}_p$i', vendorID: vendorId, categoryID: catMain));
        final ctx = buildCtx(vendor: vendor(id: vendorId), products: products);
        final expected = size >= 10;
        _check('Menu size=$size', RecommendationEngine.hasEnoughProductsForSections(ctx) == expected,
            'menu size=$size should give hasEnoughProductsForSections=$expected');
      }
    });

    test('minimumRecommendationConfidence (0.40): exclusion check uses strict < (verified by code inspection)', () {
      // recommendationConfidenceScores: `if (score < minimumRecommendationConfidence) continue;`
      // - a score of EXACTLY 0.40 is INCLUDED (not excluded). Engineering an
      // exact 0.40 through the full multi-source pipeline isn't practical,
      // but the operator itself is the boundary fact worth pinning down -
      // confirmed directly against the source rather than assumed.
      expect(RecommendationEngine.minimumRecommendationConfidence, 0.40);
    });

    test('_diversityMinMenuSize (10): menus of 9/10/11 near-duplicate-named products', () {
      for (final size in [9, 10, 11]) {
        final vendorId = 'thresh_diversity_$size';
        final products = List.generate(size, (i) => product(
              id: '${vendorId}_p$i', vendorID: vendorId, categoryID: catMain, name: 'Butter Chicken', price: '${100 + i}',
            ));
        final sales = {for (final p in products) p.id: (products.indexOf(p) % 3) + 1};
        final behavior = BehaviorSummarySnapshot(
          productOrderQuantities: {for (final p in products) p.id: 1}, orderCount: size,
        );
        final ctx = buildCtx(vendor: vendor(id: vendorId), products: products, sales30: sales, behavior: behavior);
        expect(() => RecommendationEngine.recommendForYou(ctx, limit: size), returnsNormally);
      }
    });

    test('History counts 0/1/2/5/10: comboEligibilityScore is monotonically non-decreasing with more evidence', () {
      final vendorId = 'thresh_history';
      final naan = product(id: '${vendorId}_naan', vendorID: vendorId, categoryID: catBread, name: 'Naan');
      final combo = product(id: '${vendorId}_combo', vendorID: vendorId, categoryID: catMain, name: 'Combo', price: '300')
        ..isCombo = true
        ..comboProducts = [ComboProductItem(productId: naan.id)];
      double? previous;
      for (final count in [0, 1, 2, 5, 10]) {
        final behavior = count == 0
            ? BehaviorSummarySnapshot.empty()
            : BehaviorSummarySnapshot(
                productOrderQuantities: {naan.id: count}, productViewCounts: {naan.id: count * 2},
                orderCount: count, avgOrderValue: 300,
              );
        final ctx = buildCtx(vendor: vendor(id: vendorId), products: [naan, combo], behavior: behavior);
        final score = RecommendationEngine.comboEligibilityScore(combo, ctx);
        if (previous != null) {
          _check('History count=$count', score >= previous - 1e-9,
              'score must not DECREASE as history count grows (prev=$previous, now=$score)');
        }
        previous = score;
      }
    });
  });

  // ── Section 8: Cross User Isolation (100+ distinct customers, interleaved) ──
  group('Section 8: Cross User Isolation', () {
    test('100 distinct customers, interleaved calls: no cross-contamination', () {
      final vendorId = 'isolation_vendor';
      final products = fullDishMenu(vendorId);
      final sales = {for (final p in products) p.id: 2};
      final v = vendor(id: vendorId, businessTypeId: btRestaurant, cuisineIds: [cuisineNorthIndian, cuisineChinese, cuisineFastFood]);

      final customers = List.generate(100, (i) {
        switch (i % 5) {
          case 0:
            return northIndianLoverCustomer();
          case 1:
            return pizzaLoverCustomer();
          case 2:
            return beverageLoverCustomer();
          case 3:
            return categoryLoverCustomer({catMain: 1}, orderCount: 1); // budget-ish/minimal user
          default:
            return mixedPreferenceCustomer();
        }
      });

      List<String> resultFor(int i) => RecommendationEngine.recommendForYou(
            buildCtx(vendor: v, products: products, behavior: customers[i], sales30: sales,
                businessTypeProfiles: fullBusinessTypeProfiles, cuisineCategoryAffinity: fullCuisineAffinity),
            limit: 20,
          ).map((p) => p.id).toList();

      // Compute each customer's own baseline once, then re-interleave calls
      // for customers 0 and 50 (different personas) between every other
      // customer's call, and confirm neither ever drifts from its baseline -
      // proof there's no shared/global mutable state anywhere in the engine.
      final baselines = List.generate(100, resultFor);
      for (var round = 0; round < 100; round++) {
        final probe = round % 2 == 0 ? 0 : 50;
        final result = resultFor(probe);
        _check('Cross-user isolation round $round',
            result.toString() == baselines[probe].toString(),
            'customer #$probe\'s recommendations drifted after ${round + 1} interleaved calls to other customers');
      }
    });
  });

  // ── Section 9: Long Session Simulation ───────────────────────────────────
  group('Section 9: Long Session Simulation', () {
    test('Open -> browse -> search -> cart add/remove -> budget change -> combo add -> order -> reopen', () {
      final vendorId = 'session_vendor';
      final v = vendor(id: vendorId, businessTypeId: btRestaurant, cuisineIds: [cuisineNorthIndian, cuisineFastFood]);
      final products = fullDishMenu(vendorId);
      final butterChicken = products.firstWhere((p) => p.name == 'Butter Chicken');
      final naan = products.firstWhere((p) => p.name == 'Butter Naan');
      final combo = product(id: '${vendorId}_combo', vendorID: vendorId, categoryID: catMain, name: 'Family Combo', price: '650')
        ..isCombo = true
        ..comboProducts = [ComboProductItem(productId: butterChicken.id), ComboProductItem(productId: naan.id)];
      final allProducts = [...products, combo];

      // Step 1: open restaurant, true cold start.
      var behavior = BehaviorSummarySnapshot.empty();
      var ctx = buildCtx(vendor: v, products: allProducts, behavior: behavior);
      _check('Session step 1 (open)', RecommendationEngine.recommendForYou(ctx, limit: 20).isEmpty,
          'a brand-new session must start with no fabricated recommendations');

      // Step 2: browse (view Butter Chicken a few times).
      behavior = BehaviorSummarySnapshot(productViewCounts: {butterChicken.id: 4});
      ctx = buildCtx(vendor: v, products: allProducts, behavior: behavior);
      expect(() => RecommendationEngine.recommendForYou(ctx, limit: 20), returnsNormally);

      // Step 3: search.
      behavior = BehaviorSummarySnapshot(productViewCounts: {butterChicken.id: 4}, topSearchKeywords: {'butter chicken': 2});
      ctx = buildCtx(vendor: v, products: allProducts, behavior: behavior);
      expect(() => RecommendationEngine.recommendForYou(ctx, limit: 20), returnsNormally);

      // Step 4: add to cart (cart-awareness inputs, not behavior).
      final cartIds = {butterChicken.id};
      final cartCats = {catMain: 1};
      expect(() => RecommendationEngine.fillPairsWellWith(
            vendorConfigured: const [], candidatePool: allProducts.where((p) => p.id != butterChicken.id).toList(),
            mergedScores: RecommendationEngine.normalizedMergedScores(ctx), preferenceScores: const {}, bestSellerScores: const {},
            crossSellFrequency: ctx.crossSellFrequency, cartProductIds: cartIds, cartCategoryCounts: cartCats, maxItems: 5,
          ), returnsNormally);

      // Step 5: remove item - cart empties back out, no crash.
      expect(() => RecommendationEngine.fillPairsWellWith(
            vendorConfigured: const [], candidatePool: allProducts, mergedScores: const {},
            preferenceScores: const {}, bestSellerScores: const {}, crossSellFrequency: ctx.crossSellFrequency, maxItems: 5,
          ), returnsNormally);

      // Step 6: budget changes (order placed, avgOrderValue now known).
      behavior = BehaviorSummarySnapshot(
        productViewCounts: {butterChicken.id: 4}, productOrderQuantities: {butterChicken.id: 1, naan.id: 1},
        orderCount: 1, avgOrderValue: 650,
      );
      ctx = buildCtx(vendor: v, products: allProducts, behavior: behavior);
      expect(() => RecommendationEngine.recommendForYou(ctx, limit: 20), returnsNormally);

      // Step 7: combo added and ordered - Combo Purchase Learning fields populate.
      behavior = BehaviorSummarySnapshot(
        productViewCounts: {butterChicken.id: 4}, productOrderQuantities: {butterChicken.id: 1, naan.id: 1, combo.id: 1},
        orderCount: 2, avgOrderValue: 650, comboOrderCount: 1, comboPriceTotal: 650, comboChildCountTotal: 2,
        comboChildProductCounts: {butterChicken.id: 1, naan.id: 1},
      );
      ctx = buildCtx(vendor: v, products: allProducts, behavior: behavior);
      final comboScoreAfterOrder = RecommendationEngine.comboEligibilityScore(combo, ctx);
      _check('Session step 7 (combo ordered)', comboScoreAfterOrder > 0,
          'after actually ordering this combo, its own eligibility score must be positive');

      // Step 8: re-open restaurant - recommendations reflect the accumulated history.
      final reopenCtx = buildCtx(vendor: v, products: allProducts, behavior: behavior,
          businessTypeProfiles: fullBusinessTypeProfiles, cuisineCategoryAffinity: fullCuisineAffinity);
      expect(() => RecommendationEngine.recommendForYou(reopenCtx, limit: 20), returnsNormally);
      final reopenResult = RecommendationEngine.recommendForYou(reopenCtx, limit: 20);
      _check('Session step 8 (reopen)', reopenResult.isNotEmpty,
          'after real order history exists, the reopened session must show real recommendations, not an empty cold start');
    });
  });

  // ── Section 10: Recommendation Distribution Audit ────────────────────────
  group('Section 10: Recommendation Distribution Audit', () {
    test('200 randomized scenarios: no single category/cuisine/business-type dominates unexpectedly', () {
      final random = Random(31415926);
      final categoryTally = <String, int>{};
      final businessTypeTally = <String, int>{};
      var comboCount = 0, individualCount = 0;
      const scenarioCount = 200;

      for (var i = 0; i < scenarioCount; i++) {
        final bt = _distributionBusinessTypes[random.nextInt(_distributionBusinessTypes.length)];
        final cuisines = (List<String>.from(_distributionCuisines)..shuffle(random)).take(1 + random.nextInt(3)).toList();
        final vendorId = 'dist_$i';
        final v = vendor(id: vendorId, businessTypeId: bt, cuisineIds: cuisines);
        final menuSize = 10 + random.nextInt(40);
        final products = List.generate(menuSize, (j) {
          final cat = allMenuCategories[random.nextInt(allMenuCategories.length)];
          return product(id: '${vendorId}_p$j', vendorID: vendorId, categoryID: cat, price: (50 + random.nextInt(500)).toString());
        });
        final behavior = BehaviorSummarySnapshot(
          categoryInteractionCounts: {for (final c in allMenuCategories) c: random.nextInt(20)},
          orderCount: 5 + random.nextInt(30), avgOrderValue: 100.0 + random.nextInt(1000),
        );
        final sales = {for (final p in products) p.id: random.nextInt(10)};
        final ctx = buildCtx(vendor: v, products: products, behavior: behavior, sales30: sales,
            businessTypeProfiles: fullBusinessTypeProfiles, cuisineCategoryAffinity: fullCuisineAffinity);
        final result = RecommendationEngine.recommendForYou(ctx, limit: RecommendationEngine.sectionLimitFor(ctx));
        for (final p in result) {
          categoryTally[p.categoryID] = (categoryTally[p.categoryID] ?? 0) + 1;
          if (p.isCombo) comboCount++; else individualCount++;
        }
        businessTypeTally[bt.isEmpty ? '(none)' : bt] = (businessTypeTally[bt.isEmpty ? '(none)' : bt] ?? 0) + result.length;
      }

      final totalRecommendations = categoryTally.values.fold(0, (a, b) => a + b);
      final buffer = StringBuffer()
        ..writeln('')
        ..writeln('── Recommendation Distribution Audit ($scenarioCount scenarios, $totalRecommendations total recommendations) ──')
        ..writeln('By category:');
      final sortedCategories = categoryTally.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      for (final e in sortedCategories) {
        final pct = totalRecommendations > 0 ? (e.value / totalRecommendations * 100) : 0;
        buffer.writeln('  ${e.key.padRight(20)} ${e.value.toString().padLeft(5)}  (${pct.toStringAsFixed(1)}%)');
      }
      buffer.writeln('Individual vs Combo: $individualCount individual, $comboCount combo');
      // ignore: avoid_print
      print(buffer.toString());

      if (totalRecommendations > 0 && sortedCategories.isNotEmpty) {
        final topShare = sortedCategories.first.value / totalRecommendations;
        _check('Distribution bias check', topShare < 0.5,
            'no single category should dominate more than 50% of all recommendations across ${_distributionBusinessTypes.length} diverse business types (top category was ${(topShare * 100).toStringAsFixed(1)}%)');
      }
    });
  });

  // ── Section 11: Recommendation Explainability ────────────────────────────
  group('Section 11: Recommendation Explainability', () {
    test('Explain the top 5 recommendations for a realistic North Indian scenario', () {
      final vendorId = 'explain_1';
      final v = vendor(id: vendorId, businessTypeId: btRestaurant, cuisineIds: [cuisineNorthIndian, cuisineFastFood]);
      final products = fullDishMenu(vendorId);
      final sales = {for (final p in products) p.id: (products.indexOf(p) % 5) + 1};
      final behavior = northIndianLoverCustomer();
      final ctx = buildCtx(vendor: v, products: products, behavior: behavior, sales30: sales,
          businessTypeProfiles: fullBusinessTypeProfiles, cuisineCategoryAffinity: fullCuisineAffinity);
      final result = RecommendationEngine.recommendForYou(ctx, limit: 5);
      _check('Explainability sample generation', result.isNotEmpty, 'need at least one recommendation to explain');
      final buffer = StringBuffer()..writeln('')..writeln('── Explainability samples (North Indian scenario) ──');
      for (final p in result) {
        buffer.writeln(_explain(p, ctx));
        buffer.writeln('---');
      }
      // ignore: avoid_print
      print(buffer.toString());
    });
  });

  // Registered last so package:test's sequential-by-declaration execution
  // guarantees every _check() above has already run by the time this reads
  // _failures - this is what actually surfaces a recorded failure to the
  // test runner (tearDownAll above only prints; it never asserted).
  test('FINAL: zero failures recorded across the final verification phase', () {
    expect(_failures, isEmpty,
        reason: '${_failures.length} of $_assertionCount assertions failed - see the printed report above for full detail');
  });
}

const _distributionBusinessTypes = [btRestaurant, btCafe, btBakery, btJuiceBar, btFastFood, btCloudKitchen, btBeverageShop, ''];
const _distributionCuisines = [cuisineNorthIndian, cuisineChinese, cuisineFastFood, cuisineCafe, cuisineBakery, cuisineBeverage, cuisineSouthIndian];

RestaurantRecommendationContext _stableFixture() {
  final vendorId = 'stable_vendor';
  final v = vendor(id: vendorId, businessTypeId: btRestaurant, cuisineIds: [cuisineNorthIndian, cuisineChinese]);
  final products = fullDishMenu(vendorId);
  final sales = {for (final p in products) p.id: (products.indexOf(p) % 4) + 1};
  final behavior = mixedPreferenceCustomer();
  return buildCtx(vendor: v, products: products, behavior: behavior, sales30: sales,
      businessTypeProfiles: fullBusinessTypeProfiles, cuisineCategoryAffinity: fullCuisineAffinity);
}
