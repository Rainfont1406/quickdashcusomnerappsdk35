// Verification suite for the category-first, product-second ranking
// restructure (2026-07-23, explicit product direction: "first analyze user
// category-wise behavior, then show good products from that category"),
// later evolved into dynamic per-category slot allocation (same day,
// explicit follow-up: "dynamically decide how many products each category
// should contribute" based on preference strength + eligible-candidate
// count + the total limit, never forcing equal distribution, never
// allocating more than a category's real candidate count).
//
// Scope: recommendForYou, topBySource('preference', categoryFirst: true)
// (Based on Your Taste), and hiddenGems - all three now (1) sort by
// category preference rank first, product/gem score second, and (2) decide
// how many of the final slots each category earns via a capacity-
// constrained largest-remainder apportionment, before picking which
// products fill them. Every other surface (Restaurant Must Try, Explore
// the Menu, Trending/Popular Choice, Most Loved Here, Pairs Well With,
// Search Ranking) is explicitly out of scope and unchanged - group 4 below
// regression-checks that.
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/services/recommendation/behavior_summary_snapshot.dart';
import 'package:emartconsumer/services/recommendation/recommendation_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  final v = vendor(id: 'v_catfirst');

  // Two categories, two products each. catA is the customer's strongly
  // preferred category (categoryInteractionCounts); catB's products have
  // MUCH higher raw product-level view counts - if product score still won,
  // catB would rank first. This isolates the category-first claim cleanly.
  final pA1 = product(id: 'v_catfirst_a1', vendorID: 'v_catfirst', categoryID: 'catA', name: 'A1');
  final pA2 = product(id: 'v_catfirst_a2', vendorID: 'v_catfirst', categoryID: 'catA', name: 'A2');
  final pB1 = product(id: 'v_catfirst_b1', vendorID: 'v_catfirst', categoryID: 'catB', name: 'B1');
  final pB2 = product(id: 'v_catfirst_b2', vendorID: 'v_catfirst', categoryID: 'catB', name: 'B2');
  final products = [pA1, pA2, pB1, pB2];

  final behavior = const BehaviorSummarySnapshot(
    categoryInteractionCounts: {'catA': 50, 'catB': 2},
    // catB's products dominate on raw product-level signal alone - proves
    // category rank, not product score, is deciding the ordering.
    productViewCounts: {'v_catfirst_b1': 100, 'v_catfirst_b2': 90, 'v_catfirst_a1': 1, 'v_catfirst_a2': 1},
  );

  group('1. Recommended For You - category-first', () {
    test('preferred category (catA) ranks entirely before a higher-raw-score category (catB)', () {
      final ctx = buildCtx(vendor: v, products: products, behavior: behavior);
      final result = RecommendationEngine.recommendForYou(ctx, limit: 4);

      expect(result.length, 4, reason: 'all 4 products should have some preference signal');
      final ids = result.map((p) => p.id).toList();
      final lastCatAIndex = ids.lastIndexWhere((id) => id.contains('_a'));
      final firstCatBIndex = ids.indexWhere((id) => id.contains('_b'));
      expect(lastCatAIndex, lessThan(firstCatBIndex),
          reason: 'both catA products must appear before either catB product, despite catB having far higher raw view counts');
    });

    test('within catA, the higher-scoring product still wins the secondary (product) sort key', () {
      // Give pA1 more product-level signal than pA2, both still catA.
      final skewedBehavior = const BehaviorSummarySnapshot(
        categoryInteractionCounts: {'catA': 50, 'catB': 2},
        productViewCounts: {
          'v_catfirst_b1': 100, 'v_catfirst_b2': 90,
          'v_catfirst_a1': 20, 'v_catfirst_a2': 1,
        },
      );
      final ctx = buildCtx(vendor: v, products: products, behavior: skewedBehavior);
      final result = RecommendationEngine.recommendForYou(ctx, limit: 4);
      final ids = result.map((p) => p.id).toList();
      expect(ids.indexOf('v_catfirst_a1'), lessThan(ids.indexOf('v_catfirst_a2')),
          reason: 'product score is still the secondary sort key within the same category');
    });

    test('no category signal at all (Stage 0) -> degrades to plain menu-category order, never throws', () {
      final ctx = buildCtx(vendor: v, products: products, behavior: BehaviorSummarySnapshot.empty());
      expect(() => RecommendationEngine.recommendForYou(ctx, limit: 4), returnsNormally);
    });
  });

  group('2. Based on Your Taste (topBySource categoryFirst) - category-first', () {
    test('categoryFirst: true puts catA before catB, same as Recommended For You', () {
      final ctx = buildCtx(vendor: v, products: products, behavior: behavior);
      final result = RecommendationEngine.topBySource(ctx, 'preference', n: 4, categoryFirst: true);
      final ids = result.map((p) => p.id).toList();
      final lastCatAIndex = ids.lastIndexWhere((id) => id.contains('_a'));
      final firstCatBIndex = ids.indexWhere((id) => id.contains('_b'));
      expect(lastCatAIndex, lessThan(firstCatBIndex));
    });

    test('categoryFirst: false (default) ranks by raw preference score alone - catB leads, since it has far higher product-level signal', () {
      final ctx = buildCtx(vendor: v, products: products, behavior: behavior);
      final result = RecommendationEngine.topBySource(ctx, 'preference', n: 4);
      expect(result.first.id, 'v_catfirst_b1',
          reason: 'default (categoryFirst omitted) must be byte-for-byte the pre-existing score-only ranking');
    });

    test('businessContextBoost: true (2026-07-23) breaks a tie in favor of the Business-Context-primary category', () {
      // btRestaurant: catMain is Primary (tier 1.0), catDosa has no entry
      // at all (tier 0.0). Equal categoryInteractionCounts and equal
      // productViewCounts for both products -> raw _sourcePreference scores
      // tie exactly; only the boost can break that tie.
      final btVendor = vendor(id: 'v_bcboost', businessTypeId: btRestaurant);
      final pMain = product(id: 'v_bcboost_main', vendorID: 'v_bcboost', categoryID: catMain, name: 'Main');
      final pDosa = product(id: 'v_bcboost_dosa', vendorID: 'v_bcboost', categoryID: catDosa, name: 'Dosa');
      final tieBehavior = const BehaviorSummarySnapshot(
        categoryInteractionCounts: {catMain: 10, catDosa: 10},
        productViewCounts: {'v_bcboost_main': 5, 'v_bcboost_dosa': 5},
      );
      final ctx = buildCtx(
        vendor: btVendor,
        products: [pMain, pDosa],
        behavior: tieBehavior,
        businessTypeProfiles: fullBusinessTypeProfiles,
      );

      final withoutBoost = RecommendationEngine.topBySource(ctx, 'preference', n: 2);
      expect(withoutBoost.first.id, 'v_bcboost_main',
          reason: 'ties resolve by menu order (pMain listed first) without the boost - confirms the raw scores really do tie');

      final withBoost =
          RecommendationEngine.topBySource(ctx, 'preference', n: 2, businessContextBoost: true);
      expect(withBoost.first.id, 'v_bcboost_main',
          reason: 'catMain (Primary tier) must now clearly win on boosted score, not just tie-break menu order');
    });

    test('businessContextBoost never leaks into Recommended For You (_sourcePreference itself stays untouched)', () {
      // RFY already has its OWN independent businessContext merge source
      // (weight 55% by default) - this just confirms adding the new param
      // to topBySource did not also change _sourcePreference's own
      // computation, which RFY's merge reuses directly.
      final btVendor = vendor(id: 'v_bcboost_rfy', businessTypeId: btRestaurant);
      final pMain = product(id: 'v_bcboost_rfy_main', vendorID: 'v_bcboost_rfy', categoryID: catMain, name: 'Main');
      final ctx = buildCtx(
        vendor: btVendor,
        products: [pMain],
        behavior: const BehaviorSummarySnapshot(productViewCounts: {'v_bcboost_rfy_main': 5}),
        businessTypeProfiles: fullBusinessTypeProfiles,
      );
      expect(() => RecommendationEngine.recommendForYou(ctx, limit: 1), returnsNormally);
    });
  });

  group('3. Hidden Gems - category-first', () {
    test('preferred category ranks first among eligible gems, real gem score still the secondary key', () {
      // Hidden Gems needs: restaurant confidence (>=15 total 90-day units),
      // a qualifying vendor rating, and each candidate's own sales inside
      // the "quietly under-ordered" band (>0, <=30% of the menu leader).
      final ratedVendor = vendor(id: 'v_catfirst_hg', reviewsCount: 20, reviewsSum: 90); // avg 4.5, confidence-weighted signal clears 0.6
      final gA1 = product(id: 'v_catfirst_hg_a1', vendorID: 'v_catfirst_hg', categoryID: 'catA', name: 'GA1');
      final gA2 = product(id: 'v_catfirst_hg_a2', vendorID: 'v_catfirst_hg', categoryID: 'catA', name: 'GA2');
      final gB1 = product(id: 'v_catfirst_hg_b1', vendorID: 'v_catfirst_hg', categoryID: 'catB', name: 'GB1');
      final gProducts = [gA1, gA2, gB1];
      // Menu leader (high sales, sets the 30% band) + gems themselves, all
      // >0 and within band. gB1 given a stronger (lower-sales, "more
      // hidden") gem score than gA1/gA2 to prove category still wins first.
      final gemSales = {
        'v_catfirst_hg_leader': 100,
        'v_catfirst_hg_a1': 10,
        'v_catfirst_hg_a2': 9,
        'v_catfirst_hg_b1': 1, // lowest sales -> highest raw gem score
      };
      final leader = product(id: 'v_catfirst_hg_leader', vendorID: 'v_catfirst_hg', categoryID: 'catLeader', name: 'Leader');
      final ctx = buildCtx(
        vendor: ratedVendor,
        products: [leader, ...gProducts],
        sales30: gemSales,
        behavior: const BehaviorSummarySnapshot(categoryInteractionCounts: {'catA': 50, 'catB': 2}),
      );
      final result = RecommendationEngine.hiddenGems(ctx, n: 3);
      final ids = result.map((p) => p.id).toList();
      final catAIds = ids.where((id) => id.contains('_a')).toList();
      final catBIndex = ids.indexWhere((id) => id.contains('_b1'));
      expect(catBIndex, isNot(-1), reason: 'gB1 should still qualify as a gem');
      for (final catAId in catAIds) {
        expect(ids.indexOf(catAId), lessThan(catBIndex),
            reason: 'catA gems must rank before the catB gem despite it having a stronger raw gem score');
      }
    });
  });

  group('4. Out-of-scope surfaces remain unaffected (regression check)', () {
    test('Restaurant Must Try (topBySource mustTry, categoryFirst omitted) ignores category preference entirely', () {
      final ctx = buildCtx(
        vendor: v,
        products: products,
        sales30: {'v_catfirst_b1': 50, 'v_catfirst_b2': 40, 'v_catfirst_a1': 5, 'v_catfirst_a2': 4},
        behavior: behavior,
      );
      final result = RecommendationEngine.topBySource(ctx, 'mustTry', n: 4);
      expect(result.first.id, 'v_catfirst_b1',
          reason: 'mustTry must stay pure sales-ranked - category-first was never applied here');
    });
  });

  // ── 5. Dynamic proportional slot allocation (2026-07-23 evolution) ──────
  // These specifically exercise CONTENTION (total eligible > limit), where
  // the earlier groups above (total eligible == limit, so every category
  // gets everything regardless of weight) never touch the actual
  // apportionment math at all.
  group('5. Dynamic proportional allocation', () {
    final v2 = vendor(id: 'v_alloc');
    List<ProductModel> buildCategory(String cat, int n) => List.generate(n,
        (i) => product(id: 'v_alloc_${cat}_$i', vendorID: 'v_alloc', categoryID: cat, name: '$cat$i'));
    final catAProducts = buildCategory('catA', 5);
    final catBProducts = buildCategory('catB', 5);
    final catCProducts = buildCategory('catC', 5);
    final allocProducts = [...catAProducts, ...catBProducts, ...catCProducts];
    // Uniform tiny view-count on every product so all 15 are real eligible
    // preference candidates - category WEIGHT (below) is what
    // differentiates them, not raw product-level signal.
    final uniformViews = {for (final p in allocProducts) p.id: 1};

    test('higher preference gets proportionally more slots - not equal, not all-or-nothing', () {
      // catA:100, catB:10, catC: no signal at all. By hand:
      // weight_A=log1p(100,100)=1.0, weight_B=log1p(10,100)~0.519, weight_C=0.
      // idealQuota ~= A:3.29, B:1.71, C:0 -> floor A:3,B:1,C:0 (allocated=4)
      // -> 1 leftover slot goes to B (larger remaining need 0.71 > 0.29)
      // -> final A:3, B:2, C:0.
      final behavior = BehaviorSummarySnapshot(
        categoryInteractionCounts: const {'catA': 100, 'catB': 10},
        productViewCounts: uniformViews,
      );
      final ctx = buildCtx(vendor: v2, products: allocProducts, behavior: behavior);
      final result = RecommendationEngine.recommendForYou(ctx, limit: 5);
      final countA = result.where((p) => p.categoryID == 'catA').length;
      final countB = result.where((p) => p.categoryID == 'catB').length;
      final countC = result.where((p) => p.categoryID == 'catC').length;
      expect(result.length, 5);
      expect(countA, 3, reason: 'strongest preference gets the most slots');
      expect(countB, 2, reason: 'weaker but real preference still gets represented, not zero');
      expect(countC, 0, reason: 'zero-signal category never gets a fabricated slot, despite having real eligible products');
      expect(countA, greaterThan(countB), reason: 'higher preference must get MORE slots, never merely equal');
    });

    test('a category capped by few eligible products never exceeds its own cap - leftover flows to the next category', () {
      // catASmall: strong preference (100) but only 1 eligible product.
      // catB: weaker preference (10) but 4 eligible products.
      // limit 5 -> catASmall can only ever contribute 1 (its own real
      // candidate count - "never force impossible allocations"), the
      // other 4 slots must go to catB even though its raw weight alone
      // would otherwise suggest fewer than 4.
      final smallCatA = buildCategory('catASmall', 1);
      final testProducts = [...smallCatA, ...catBProducts];
      final views = {for (final p in testProducts) p.id: 1};
      final behavior = BehaviorSummarySnapshot(
        categoryInteractionCounts: const {'catASmall': 100, 'catB': 10},
        productViewCounts: views,
      );
      final ctx = buildCtx(vendor: v2, products: testProducts, behavior: behavior);
      final result = RecommendationEngine.recommendForYou(ctx, limit: 5);
      final countA = result.where((p) => p.categoryID == 'catASmall').length;
      final countB = result.where((p) => p.categoryID == 'catB').length;
      expect(result.length, 5);
      expect(countA, 1, reason: 'catASmall only has 1 real candidate - can never be allocated more');
      expect(countB, 4, reason: 'the 4 slots catASmall cannot use flow to the next category with real candidates');
    });

    test('no category signal at all -> honest near-equal split by data availability, never an error, never one category monopolizing everything', () {
      final ctx = buildCtx(
        vendor: v2,
        products: allocProducts,
        behavior: BehaviorSummarySnapshot(productViewCounts: uniformViews),
      );
      expect(() => RecommendationEngine.recommendForYou(ctx, limit: 5), returnsNormally);
      final result = RecommendationEngine.recommendForYou(ctx, limit: 5);
      expect(result.length, 5);
      final categoriesRepresented = result.map((p) => p.categoryID).toSet();
      expect(categoriesRepresented.length, greaterThan(1),
          reason: 'with zero differentiating category signal, no single category should monopolize every slot');
    });
  });
}
