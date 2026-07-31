// Verification suite for the dynamic role-aware badge allocation
// (RecommendationEngine._dynamicRoleAwareBadges, exposed publicly via
// recommendationConfidenceScores while _useDynamicRoleAwareBadgeLogic is
// true - see that flag's doc comment in recommendation_engine.dart). Every
// case here is pure Dart against synthetic RestaurantRecommendationContext
// fixtures, no Firestore/widget dependency, matching the rest of
// test/recommendation/.
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/services/recommendation/recommendation_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

// N products, all in one category (so they land in one Business-Context
// role deterministically), with strictly descending, distinct sales counts
// (highest first) - product i has count (n - i) + offset. offset keeps
// rolling90DaySales' sum comfortably above the restaurant-confidence floor
// (15) even for very small n, without disturbing relative ranking.
List<ProductModel> _group(String vendorId, String categoryId, int n, {String prefix = 'g'}) {
  return List.generate(n,
      (i) => product(id: '${vendorId}_${prefix}_$i', vendorID: vendorId, categoryID: categoryId));
}

Map<String, int> _descendingCounts(List<ProductModel> products, {int offset = 20}) {
  final n = products.length;
  return {for (var i = 0; i < n; i++) products[i].id: (n - i) + offset};
}

void main() {
  final v = vendor(id: 'v1', businessTypeId: btRestaurant);

  // ── 1. Dynamic percentage table + rounding + min/max clamp ────────────
  group('1. Dynamic cap per group size (percentage -> round -> min/max clamp)', () {
    // (activeCount, expectedCap) - single-role (Main-only) menus, sales
    // supplied for every product on both windows so real candidates never
    // fall short of the theoretical cap. Expected caps derived by hand from
    // the spec's own table: 1-10:40%, 11-20:35%, 21-40:30%, 41-75:25%,
    // 76+:20%, rounded, clamped to [1,20] and to group size. Menus this
    // size (<=40 total) stay on the original shared-20-badge-pool path, so
    // the raw percentage-table cap is what's actually awarded.
    const cases = <int, int>{
      1: 1, // 0.4 -> rounds to 0 -> minimum clamp kicks in
      5: 2, // 2.0
      10: 4, // 4.0
      15: 5, // 5.25 -> 5
      20: 7, // 7.0
      30: 9, // 9.0
      40: 12, // 12.0
    };

    // Most Ordered and Popular Choice are verified in ISOLATION from each
    // other here (group 6 below separately covers how they interact
    // through the shared budget) - otherwise Most Ordered claiming its cap
    // first would eat into both Popular Choice's candidate pool AND the
    // shared budget, making the expected numbers a function of the
    // interaction rather than of the percentage table alone.
    cases.forEach((n, expectedCap) {
      test('$n active products -> Most Ordered cap $expectedCap', () {
        final products = _group('v_mo_$n', catMain, n);
        final ctx = buildCtx(
          vendor: v,
          products: products,
          sales7: _descendingCounts(products),
          sales30: _descendingCounts(products), // also clears the restaurant-confidence floor
          businessTypeProfiles: fullBusinessTypeProfiles,
        );
        final result = RecommendationEngine.recommendationConfidenceScores(ctx);
        final mostOrdered = result.values.where((c) => c.label == RecommendationLabel.mostOrdered).length;
        expect(mostOrdered, expectedCap);
      });

      test('$n active products -> Popular Choice cap $expectedCap', () {
        final products = _group('v_pc_$n', catMain, n);
        final ctx = buildCtx(
          vendor: v,
          products: products,
          sales7: const {}, // zero Most Ordered candidates -> full shared budget stays available
          sales30: _descendingCounts(products),
          businessTypeProfiles: fullBusinessTypeProfiles,
        );
        final result = RecommendationEngine.recommendationConfidenceScores(ctx);
        final popularChoice = result.values.where((c) => c.label == RecommendationLabel.popularChoice).length;
        expect(popularChoice, expectedCap);
      });
    });

    // >40 total products (2026-07-23 reserved-split fix): the raw
    // percentage-table cap no longer governs alone - it's additionally
    // ceilinged by the reserved 12 (Most Ordered) / 8 (Popular Choice)
    // shares of the shared 20-badge budget, whichever is smaller. Every n
    // below has a theoretical percentage-table cap of 15 or 20 (all >12
    // and >8), so the reserved-budget ceiling is what actually binds in
    // every one of these cases - the table itself (_dynamicCapFor) is
    // unchanged and still covered by the <=40 cases above.
    const largeMenuCases = [60, 100, 200, 500];
    for (final n in largeMenuCases) {
      test('$n active products (>40) -> Most Ordered ceilinged at the reserved 12, not the raw percentage cap', () {
        final products = _group('v_mo_large_$n', catMain, n);
        final ctx = buildCtx(
          vendor: v,
          products: products,
          sales7: _descendingCounts(products),
          sales30: _descendingCounts(products),
          businessTypeProfiles: fullBusinessTypeProfiles,
        );
        final result = RecommendationEngine.recommendationConfidenceScores(ctx);
        final mostOrdered = result.values.where((c) => c.label == RecommendationLabel.mostOrdered).length;
        expect(mostOrdered, 12);
      });

      test('$n active products (>40) -> Popular Choice ceilinged at the reserved 8, not the raw percentage cap', () {
        final products = _group('v_pc_large_$n', catMain, n);
        final ctx = buildCtx(
          vendor: v,
          products: products,
          sales7: const {},
          sales30: _descendingCounts(products),
          businessTypeProfiles: fullBusinessTypeProfiles,
        );
        final result = RecommendationEngine.recommendationConfidenceScores(ctx);
        final popularChoice = result.values.where((c) => c.label == RecommendationLabel.popularChoice).length;
        expect(popularChoice, 8);
      });
    }
  });

  // ── 2. Minimum limit ────────────────────────────────────────────────
  group('2. Minimum limit', () {
    test('1-3 active products never round down to a 0 badge budget', () {
      for (final n in [1, 2, 3]) {
        final products = _group('v_min_$n', catMain, n);
        final ctx = buildCtx(
          vendor: v,
          products: products,
          sales7: _descendingCounts(products),
          sales30: _descendingCounts(products),
          businessTypeProfiles: fullBusinessTypeProfiles,
        );
        final result = RecommendationEngine.recommendationConfidenceScores(ctx);
        final mostOrdered = result.values.where((c) => c.label == RecommendationLabel.mostOrdered).length;
        expect(mostOrdered, greaterThanOrEqualTo(1), reason: 'n=$n should still clear the minimum-limit floor');
      }
    });
  });

  // ── 3. Maximum limit (per group, before the shared budget even applies) ──
  group('3. Maximum limit', () {
    test('120 active products (brief\'s own example): 20% = 24, capped to the maximum of 20, then further ceilinged to 12 (>40 reserved split)', () {
      final products = _group('v_120', catMain, 120);
      final ctx = buildCtx(
        vendor: v,
        products: products,
        sales7: _descendingCounts(products),
        sales30: _descendingCounts(products), // clears the restaurant-confidence floor
        businessTypeProfiles: fullBusinessTypeProfiles,
      );
      final result = RecommendationEngine.recommendationConfidenceScores(ctx);
      final mostOrdered = result.values.where((c) => c.label == RecommendationLabel.mostOrdered).length;
      // 120 > 40 -> reserved-split budget (2026-07-23) ceilings Most
      // Ordered at 12 regardless of the 20% percentage-table headroom.
      expect(mostOrdered, 12);
    });
  });

  // ── 4. Business Context role split (Main vs Side, independent caps) ───
  group('4. Business Context role split', () {
    test('Main and Side are capped independently using each group\'s own size', () {
      // btRestaurant: primary {catMain,catBread,catRice}, secondary
      // {catSides,catSalad,catBiryani} -> Main; lowPriority {catHotBev,
      // catColdBev} -> Side.
      final mainProducts = _group('v_split', catMain, 8, prefix: 'main'); // 8 -> 40% -> 3.2 -> 3
      final sideProducts = _group('v_split', catHotBev, 6, prefix: 'side'); // 6 -> 40% -> 2.4 -> 2
      final all = [...mainProducts, ...sideProducts];
      final ctx = buildCtx(
        vendor: v,
        products: all,
        sales7: _descendingCounts(all),
        sales30: _descendingCounts(all),
        businessTypeProfiles: fullBusinessTypeProfiles,
      );
      final result = RecommendationEngine.recommendationConfidenceScores(ctx);

      final mostOrderedMain =
          mainProducts.where((p) => result[p.id]?.label == RecommendationLabel.mostOrdered).length;
      final mostOrderedSide =
          sideProducts.where((p) => result[p.id]?.label == RecommendationLabel.mostOrdered).length;
      final popularMain =
          mainProducts.where((p) => result[p.id]?.label == RecommendationLabel.popularChoice).length;
      final popularSide =
          sideProducts.where((p) => result[p.id]?.label == RecommendationLabel.popularChoice).length;

      expect(mostOrderedMain, 3, reason: '8 Main products -> cap 3');
      expect(mostOrderedSide, 2, reason: '6 Side products -> cap 2');
      expect(popularMain, 3, reason: 'budget (20) has plenty of room left');
      expect(popularSide, 0, reason: 'Popular Choice is Main-only (2026-07-23) - Side never gets this label');
      // 3+2+3+0 = 8, well under the shared budget of 20 - nothing dropped.
      expect(result.length, 8);
    });

    test('a product in an unmatched category is bucketed into Main, never dropped', () {
      // catDosa is not in btRestaurant's primary/secondary/lowPriority sets
      // at all.
      final unmatched = product(id: 'v_unmatched_p0', vendorID: 'v_unmatched', categoryID: catDosa);
      final filler = _group('v_unmatched', catMain, 14); // pushes total 90-day sales over the confidence floor
      final all = [unmatched, ...filler];
      final ctx = buildCtx(
        vendor: v,
        products: all,
        sales7: {unmatched.id: 999, ..._descendingCounts(filler, offset: 1)},
        sales30: {unmatched.id: 999, ..._descendingCounts(filler, offset: 1)},
        businessTypeProfiles: fullBusinessTypeProfiles,
      );
      final result = RecommendationEngine.recommendationConfidenceScores(ctx);
      // Highest count of the whole (now 15-product) Main group -> must win
      // a Most Ordered slot, proving it was counted as Main, not silently
      // excluded from every group.
      expect(result[unmatched.id]?.label, RecommendationLabel.mostOrdered);
    });
  });

  // ── 5. Fallback: no Business Context configured ────────────────────────
  group('5. Fallback when Business Context is unavailable', () {
    test('no businessTypeId set -> entire menu treated as one (Main) group', () {
      final noTypeVendor = vendor(id: 'v_notype', businessTypeId: '');
      final products = _group('v_notype', catHotBev, 12); // would be "Side" under btRestaurant, if it applied
      final ctx = buildCtx(
        vendor: noTypeVendor,
        products: products,
        sales7: _descendingCounts(products),
        sales30: _descendingCounts(products),
        businessTypeProfiles: fullBusinessTypeProfiles, // profiles exist, but this vendor has no typeId
      );
      final result = RecommendationEngine.recommendationConfidenceScores(ctx);
      final mostOrdered = result.values.where((c) => c.label == RecommendationLabel.mostOrdered).length;
      // 12 products, single group -> 35% -> 4.2 -> 4 (would be capped
      // differently, and split, if a Side group existed).
      expect(mostOrdered, 4);
    });

    test('businessTypeId set but no matching profile entry -> single group fallback', () {
      final cloudKitchenVendor = vendor(id: 'v_ck', businessTypeId: btCloudKitchen);
      final products = _group('v_ck', catHotBev, 12);
      final ctx = buildCtx(
        vendor: cloudKitchenVendor,
        products: products,
        sales7: _descendingCounts(products),
        sales30: _descendingCounts(products),
        businessTypeProfiles: fullBusinessTypeProfiles, // has no btCloudKitchen entry, by design
      );
      final result = RecommendationEngine.recommendationConfidenceScores(ctx);
      final mostOrdered = result.values.where((c) => c.label == RecommendationLabel.mostOrdered).length;
      expect(mostOrdered, 4);
    });
  });

  // ── 6. Shared restaurant-wide badge budget + priority ordering ────────
  group('6. Shared badge budget and priority ordering', () {
    test('combined total never exceeds 20 - >40-product menu uses the reserved 60/40 split', () {
      final mainProducts = _group('v_budget', catMain, 100, prefix: 'main'); // cap 20
      final sideProducts = _group('v_budget', catHotBev, 100, prefix: 'side'); // cap 20
      final all = [...mainProducts, ...sideProducts];
      final ctx = buildCtx(
        vendor: v,
        products: all,
        sales7: _descendingCounts(all),
        sales30: _descendingCounts(all),
        businessTypeProfiles: fullBusinessTypeProfiles,
      );
      final result = RecommendationEngine.recommendationConfidenceScores(ctx);

      expect(result.length, 20, reason: 'restaurant-wide badge count must never exceed the shared budget');

      final mostOrderedMain =
          mainProducts.where((p) => result[p.id]?.label == RecommendationLabel.mostOrdered).length;
      final mostOrderedSide =
          sideProducts.where((p) => result[p.id]?.label == RecommendationLabel.mostOrdered).length;
      final popularMain =
          mainProducts.where((p) => result[p.id]?.label == RecommendationLabel.popularChoice).length;
      final popularSide =
          sideProducts.where((p) => result[p.id]?.label == RecommendationLabel.popularChoice).length;

      // >40 total products (2026-07-23 reserved-split fix): the shared
      // 20-badge budget is a hard 12/8 partition, not "Most Ordered fills
      // first" - Most Ordered(Main) takes its full reserved 12, Side gets
      // none of that reserved share; Popular Choice is Main-only (separate
      // 2026-07-23 change), so its reserved 8 also goes entirely to Main.
      expect(mostOrderedMain, 12);
      expect(mostOrderedSide, 0);
      expect(popularMain, 8);
      expect(popularSide, 0, reason: 'Popular Choice is Main-only - Side never gets this label');
    });

    test('reserved-split hard partition: Most Ordered (Main) alone fills its 12-slot reserve, Side gets none', () {
      // Main cap forced to exactly 15 (60 products -> 25% -> 15).
      final mainProducts = _group('v_partial', catMain, 60, prefix: 'main'); // cap 15
      final sideProducts = _group('v_partial', catHotBev, 60, prefix: 'side'); // cap 15
      final all = [...mainProducts, ...sideProducts];
      final ctx = buildCtx(
        vendor: v,
        products: all,
        sales7: _descendingCounts(all),
        sales30: _descendingCounts(all),
        businessTypeProfiles: fullBusinessTypeProfiles,
      );
      final result = RecommendationEngine.recommendationConfidenceScores(ctx);

      expect(result.length, 20);
      final mostOrderedMain =
          mainProducts.where((p) => result[p.id]?.label == RecommendationLabel.mostOrdered).length;
      final mostOrderedSide =
          sideProducts.where((p) => result[p.id]?.label == RecommendationLabel.mostOrdered).length;
      final popularMain =
          mainProducts.where((p) => result[p.id]?.label == RecommendationLabel.popularChoice).length;

      // >40 total products -> reserved split (12 Most Ordered / 8 Popular
      // Choice), each capped further by the group's own cap (15 here, so
      // never the limiting factor). Main's cap (15) exceeds the entire
      // Most Ordered reserve (12), so Main alone consumes it - Side gets
      // zero, even though it has just as many real candidates as Main.
      expect(mostOrderedMain, 12, reason: 'Most Ordered reserve (12) is smaller than Main\'s own cap (15)');
      expect(mostOrderedSide, 0, reason: 'reserved split is a hard partition - unused Most Ordered slots never carry over, and none were unused here anyway');
      expect(popularMain, 8, reason: 'Popular Choice reserve (8), Main-only, fully awarded');
    });
  });

  // ── 7. Ranking correctness + tie-break + mutual exclusivity ───────────
  group('7. Selection ranking', () {
    test('highest-count products win their group\'s slots, by rolling7DaySales for Most Ordered', () {
      final products = _group('v_rank', catMain, 10); // cap 4
      final ctx = buildCtx(
        vendor: v,
        products: products,
        sales7: _descendingCounts(products), // product 0 highest, product 9 lowest
        sales30: _descendingCounts(products),
        businessTypeProfiles: fullBusinessTypeProfiles,
      );
      final result = RecommendationEngine.recommendationConfidenceScores(ctx);
      final mostOrderedIds =
          products.where((p) => result[p.id]?.label == RecommendationLabel.mostOrdered).map((p) => p.id).toSet();
      expect(mostOrderedIds, {products[0].id, products[1].id, products[2].id, products[3].id});
    });

    test('ties keep original menu order (stable sort)', () {
      final products = _group('v_tie', catMain, 6); // cap 2
      final tiedCounts = {for (final p in products) p.id: 25}; // every product identical
      final ctx = buildCtx(
        vendor: v,
        products: products,
        sales7: tiedCounts,
        sales30: tiedCounts,
        businessTypeProfiles: fullBusinessTypeProfiles,
      );
      final result = RecommendationEngine.recommendationConfidenceScores(ctx);
      final mostOrderedIds =
          products.where((p) => result[p.id]?.label == RecommendationLabel.mostOrdered).map((p) => p.id).toSet();
      // Cap is 2 (6 -> 40% -> 2.4 -> 2): the first two products in menu
      // order must win the tie, not an arbitrary subset.
      expect(mostOrderedIds, {products[0].id, products[1].id});
    });

    test('a product can never hold both labels at once', () {
      final products = _group('v_excl', catMain, 10);
      final ctx = buildCtx(
        vendor: v,
        products: products,
        sales7: _descendingCounts(products),
        sales30: _descendingCounts(products),
        businessTypeProfiles: fullBusinessTypeProfiles,
      );
      final result = RecommendationEngine.recommendationConfidenceScores(ctx);
      // Nothing to assert beyond "one label per id", which the Map<String,
      // ProductRecommendationConfidence> return shape already guarantees by
      // construction - documented here as an explicit regression check on
      // that shape rather than left implicit.
      expect(result.values.map((c) => c.label).length, result.length);
    });
  });

  // ── 8. Restaurant-confidence floor unchanged ───────────────────────────
  group('8. hasSufficientRestaurantConfidence floor', () {
    test('below the 15-order 90-day floor -> no badges at all, regardless of group sizes', () {
      final products = _group('v_low', catMain, 50);
      final ctx = buildCtx(
        vendor: v,
        products: products,
        sales7: _descendingCounts(products, offset: 0),
        sales30: {products.first.id: 10}, // total well under 15
        businessTypeProfiles: fullBusinessTypeProfiles,
      );
      final result = RecommendationEngine.recommendationConfidenceScores(ctx);
      expect(result, isEmpty);
    });
  });

  // ── 9. Trending/Popular Choice confidence (2026-07-23 rework) ──────────
  // Winner SELECTION still ranks by rolling7DaySales/rolling90DaySales
  // (quantity, unchanged - covered by group 7 above). This group covers
  // only the CONFIDENCE/fill value, which now comes from an independent
  // "this product's share of the restaurant's distinct orders in the same
  // window" formula, no longer a shared hardcoded denominator.
  group('9. Trending/Popular Choice independent confidence', () {
    test('confidence = productOrders / totalOrders, independent per label, not tied to ranking counts', () {
      final products = _group('v_conf', catMain, 5); // cap 2
      final ctx = buildCtx(
        vendor: v,
        products: products,
        // Ranking (quantity) - p0,p1 win Trending; p2,p3 win Popular Choice
        // (p4 never wins anything, cap is 2 per label).
        sales7: {products[0].id: 50, products[1].id: 40, products[2].id: 5, products[3].id: 4, products[4].id: 3},
        sales30: {products[0].id: 10, products[1].id: 9, products[2].id: 50, products[3].id: 40, products[4].id: 5},
        // Confidence (distinct orders) - deliberately NOT proportional to
        // the ranking counts above, to prove the two are independent.
        productOrders7: {products[0].id: 40, products[1].id: 5},
        totalOrders7: 50,
        productOrders90: {products[2].id: 100, products[3].id: 20},
        totalOrders90: 200,
        businessTypeProfiles: fullBusinessTypeProfiles,
      );
      final result = RecommendationEngine.recommendationConfidenceScores(ctx);

      expect(result[products[0].id]?.label, RecommendationLabel.mostOrdered);
      expect(result[products[0].id]?.score, closeTo(0.8, 1e-9), reason: '40/50 Trending share');
      expect(result[products[1].id]?.label, RecommendationLabel.mostOrdered);
      expect(result[products[1].id]?.score, closeTo(0.1, 1e-9), reason: '5/50 Trending share - lower than p0 despite both winning the same label');

      expect(result[products[2].id]?.label, RecommendationLabel.popularChoice);
      expect(result[products[2].id]?.score, closeTo(0.5, 1e-9), reason: '100/200 Popular Choice share');
      expect(result[products[3].id]?.label, RecommendationLabel.popularChoice);
      expect(result[products[3].id]?.score, closeTo(0.1, 1e-9), reason: '20/200 Popular Choice share');
    });

    test('confidence never crosses labels: a 90-day-heavy product winning Trending is scored on 7-day share only', () {
      final products = _group('v_cross', catMain, 3); // cap 1 (1-10 band -> 40% of 3 = 1.2 -> 1); product[0] has the highest sales7, so it alone wins
      final ctx = buildCtx(
        vendor: v,
        products: products,
        sales7: {products[0].id: 20, products[1].id: 1, products[2].id: 1},
        sales30: {products[0].id: 20, products[1].id: 1, products[2].id: 1},
        productOrders7: {products[0].id: 3},
        totalOrders7: 30, // low share despite dominating the ranking count
        productOrders90: {products[0].id: 27},
        totalOrders90: 30, // high share on the OTHER window - must not leak into Trending's score
        businessTypeProfiles: fullBusinessTypeProfiles,
      );
      final result = RecommendationEngine.recommendationConfidenceScores(ctx);
      expect(result[products[0].id]?.label, RecommendationLabel.mostOrdered);
      expect(result[products[0].id]?.score, closeTo(0.1, 1e-9),
          reason: 'must use productOrders7/totalOrders7 (3/30) only, never the 90-day figures even though this product also has a 90-day share');
    });

    test('no order-count data yet (totalOrders = 0) -> confidence is 0.0, never a divide-by-zero crash, label still assigned', () {
      final products = _group('v_nodata', catMain, 3);
      final ctx = buildCtx(
        vendor: v,
        products: products,
        sales7: {products[0].id: 20, products[1].id: 1, products[2].id: 1},
        sales30: {products[0].id: 20, products[1].id: 1, products[2].id: 1},
        // productOrders7/90 and totalOrders7/90 all left at their defaults
        // ({}/0) - simulates a vendor whose dailyProductSales buckets
        // predate the 2026-07-23 productOrders/totalOrders fields.
        businessTypeProfiles: fullBusinessTypeProfiles,
      );
      final result = RecommendationEngine.recommendationConfidenceScores(ctx);
      expect(result[products[0].id]?.label, RecommendationLabel.mostOrdered);
      expect(result[products[0].id]?.score, 0.0);
    });
  });
}
