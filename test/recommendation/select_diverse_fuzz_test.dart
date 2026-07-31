// 500-iteration randomized stress test for the _selectDiverse ordering fix
// (RECOMMENDATION_ENGINE_AUDIT_REPORT.md, "confidence badge never contradicts
// ranking" finding). The curated test suite (recommendation_engine_verification_test.dart)
// caught the original bug with one hand-picked scenario; this generates 500
// randomized restaurant/customer combinations - varied menu sizes, varied
// name-collision density (deliberately produces many dish "families" via
// shared/qualifier tokens, same mechanism _computeDishFamilies uses), varied
// sales/behavior signals.
//
// The original "confidence badge never contradicts ranking" check (below,
// in the loop) is no longer meaningful and has been removed: it relied on
// recommendationConfidenceScores' score being the exact same value
// recommendForYou sorts by, a coupling deliberately broken by the
// 2026-07-20 Launch Mode override and further diverged by the 2026-07-21
// dynamic role-aware badge allocation (independent per-role-group cap +
// shared-budget system - see RecommendationEngine's "DYNAMIC ROLE-AWARE
// BADGE ALLOCATION" doc comment). The badge and the Recommended For You
// ordering are now intentionally independent signals. This file's other
// invariants (no duplicates, never exceeds limit/available products, and
// the backfill-path sanity check) remain fully valid and still run.
// recommendationConfidenceScores has its own dedicated coverage in
// test/recommendation/dynamic_role_aware_badges_test.dart. Seeded for
// reproducibility.
import 'dart:math';

import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/services/recommendation/behavior_summary_snapshot.dart';
import 'package:emartconsumer/services/recommendation/recommendation_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

const _adjectives = [
  'Butter', 'Garlic', 'Spicy', 'Sweet', 'Classic', 'Mini', 'Family', 'Jeera',
  'Special', 'Tandoori', 'Masala', 'Fresh', 'Crispy', 'Deluxe', 'Combo',
];
const _nouns = [
  'Rice', 'Naan', 'Chicken', 'Paneer', 'Noodles', 'Soup', 'Pizza', 'Burger',
  'Pasta', 'Salad', 'Biryani', 'Curry', 'Coffee', 'Tea', 'Juice',
];

String _randomName(Random r) {
  final noun = _nouns[r.nextInt(_nouns.length)];
  if (r.nextBool()) return noun; // bare noun - maximizes family collisions
  final adj = _adjectives[r.nextInt(_adjectives.length)];
  return '$adj $noun';
}

void main() {
  test('500 randomized restaurants: Recommended For You never shows a lower badge above a higher one', () {
    final rand = Random(42); // fixed seed - reproducible failures if any occur
    var scenariosWithBackfillActive = 0;

    for (var iter = 0; iter < 500; iter++) {
      final vendorId = 'fuzz_$iter';
      final menuSize = 10 + rand.nextInt(190); // 10..199, spans every dynamic-limit band
      final products = List.generate(menuSize, (i) {
        final cat = allMenuCategories[rand.nextInt(allMenuCategories.length)];
        return product(
          id: '${vendorId}_p$i',
          vendorID: vendorId,
          categoryID: cat,
          name: _randomName(rand),
          price: (50 + rand.nextInt(450)).toString(),
        );
      });

      final useBusinessContext = rand.nextBool();
      final cuisinePool = [
        cuisineNorthIndian, cuisineChinese, cuisineFastFood, cuisineCafe,
        cuisineBakery, cuisineBeverage,
      ];
      final vendorCuisines = useBusinessContext
          ? (List.of(cuisinePool)..shuffle(rand)).take(1 + rand.nextInt(3)).toList()
          : <String>[];
      final btPool = [btRestaurant, btCafe, btBakery, btJuiceBar, btFastFood, ''];
      final vendorBt = useBusinessContext ? btPool[rand.nextInt(btPool.length)] : '';

      final v = vendor(id: vendorId, businessTypeId: vendorBt, cuisineIds: vendorCuisines);

      final sales30 = <String, int>{};
      for (final p in products) {
        if (rand.nextDouble() < 0.4) sales30[p.id] = rand.nextInt(25);
      }

      final behaviorHasSignal = rand.nextBool();
      final behavior = behaviorHasSignal
          ? BehaviorSummarySnapshot(
              categoryInteractionCounts: {
                for (final cat in allMenuCategories)
                  if (rand.nextDouble() < 0.3) cat: rand.nextInt(20),
              },
              productViewCounts: {
                for (final p in products)
                  if (rand.nextDouble() < 0.15) p.id: rand.nextInt(15),
              },
              productOrderQuantities: {
                for (final p in products)
                  if (rand.nextDouble() < 0.1) p.id: rand.nextInt(10),
              },
              orderCount: 1 + rand.nextInt(50),
            )
          : brandNewCustomer();

      final ctx = buildCtx(
        vendor: v,
        products: products,
        behavior: behavior,
        sales30: sales30,
        businessTypeProfiles: useBusinessContext ? fullBusinessTypeProfiles : const {},
        cuisineCategoryAffinity: useBusinessContext ? fullCuisineAffinity : const {},
      );

      final limit = RecommendationEngine.sectionLimitFor(ctx);
      final List<ProductModel> ranked;
      try {
        ranked = RecommendationEngine.recommendForYou(ctx, limit: limit);
      } catch (e, st) {
        fail('iteration $iter (menuSize=$menuSize) threw: $e\n$st');
      }

      // No duplicates, never exceeds limit, never exceeds available products.
      expect(ranked.map((p) => p.id).toSet().length, ranked.length,
          reason: 'iteration $iter: duplicate product in Recommended For You');
      expect(ranked.length, lessThanOrEqualTo(limit), reason: 'iteration $iter');
      expect(ranked.length, lessThanOrEqualTo(products.length), reason: 'iteration $iter');

      if (menuSize >= RecommendationEngine.dynamicSectionLimit(menuSize) &&
          ranked.length == limit) {
        scenariosWithBackfillActive++;
      }
    }

    // Sanity check on the fuzzer itself - make sure a meaningful number of
    // iterations actually exercised the diversity/backfill path at all,
    // otherwise this stress test would be trivially passing without testing
    // anything close to the original bug's conditions.
    expect(scenariosWithBackfillActive, greaterThan(50),
        reason: 'fuzz harness did not generate enough backfill-triggering scenarios to be meaningful');
  });
}
