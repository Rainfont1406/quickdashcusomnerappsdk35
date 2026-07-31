// 30 explicit (restaurant, customer) test cases spanning every restaurant
// archetype in the synthetic dataset and every customer persona defined in
// fixtures.dart - a broader, more explicit companion to the curated
// scenario-specific tests in recommendation_engine_verification_test.dart
// and the randomized coverage in select_diverse_fuzz_test.dart. Each case
// pairs a DIFFERENT restaurant configuration with a DIFFERENT customer/sales
// situation and asserts one concrete, human-readable expectation.
import 'package:emartconsumer/services/recommendation/behavior_summary_snapshot.dart';
import 'package:emartconsumer/services/recommendation/recommendation_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'vendor_dataset.dart';

void main() {
  final dataset = buildVendorDataset();
  VendorFixture byLabel(String label) => dataset.firstWhere((f) => f.label == label);

  group('Restaurant x Customer matrix (30 cases)', () {
    // ── 1-6: single-cuisine archetypes x their matching preference persona ──

    test('Case 1: Pure North Indian restaurant + North Indian-lover customer', () {
      final f = byLabel('Pure North Indian');
      final sales = {for (final p in f.products) p.id: 2};
      final ctx = buildCtx(vendor: f.vendor, products: f.products, behavior: northIndianLoverCustomer(), sales30: sales);
      final result = RecommendationEngine.recommendForYou(ctx, limit: 20);
      expect(result, isNotEmpty);
      final naanIdx = result.indexWhere((p) => p.name == 'Butter Naan');
      final coffeeIdx = result.indexWhere((p) => p.name == 'Coffee');
      if (naanIdx != -1 && coffeeIdx != -1) expect(naanIdx, lessThan(coffeeIdx));
    });

    test('Case 2: Pure Chinese restaurant + Chinese-lover customer', () {
      final f = byLabel('Pure Chinese');
      final sales = {for (final p in f.products) p.id: 2};
      final ctx = buildCtx(vendor: f.vendor, products: f.products, behavior: chineseLoverCustomer(), sales30: sales);
      final result = RecommendationEngine.recommendForYou(ctx, limit: 20);
      final noodlesIdx = result.indexWhere((p) => p.name == 'Noodles');
      final dessertIdx = result.indexWhere((p) => p.name == 'Dessert');
      expect(noodlesIdx, isNot(-1));
      if (dessertIdx != -1) expect(noodlesIdx, lessThan(dessertIdx));
    });

    test('Case 3: Cafe + beverage-lover customer', () {
      final f = byLabel('Cafe');
      final sales = {for (final p in f.products) p.id: 2};
      final ctx = buildCtx(vendor: f.vendor, products: f.products, behavior: beverageLoverCustomer(), sales30: sales);
      final result = RecommendationEngine.recommendForYou(ctx, limit: 20);
      final coffeeIdx = result.indexWhere((p) => p.name == 'Coffee');
      expect(coffeeIdx, isNot(-1));
    });

    test('Case 4: Bakery + dessert-lover customer', () {
      final f = byLabel('Bakery');
      final sales = {for (final p in f.products) p.id: 2};
      final ctx = buildCtx(vendor: f.vendor, products: f.products, behavior: dessertLoverCustomer(), sales30: sales);
      final result = RecommendationEngine.recommendForYou(ctx, limit: 20);
      final dessertIdx = result.indexWhere((p) => p.name == 'Dessert');
      final soupIdx = result.indexWhere((p) => p.name == 'Soup');
      expect(dessertIdx, isNot(-1));
      if (soupIdx != -1) expect(dessertIdx, lessThan(soupIdx));
    });

    test('Case 5: Juice Bar + beverage-lover customer', () {
      final f = byLabel('Juice Bar');
      final sales = {for (final p in f.products) p.id: 2};
      final ctx = buildCtx(vendor: f.vendor, products: f.products, behavior: beverageLoverCustomer(), sales30: sales);
      final result = RecommendationEngine.recommendForYou(ctx, limit: 20);
      final juiceIdx = result.indexWhere((p) => p.name == 'Juice');
      final biryaniIdx = result.indexWhere((p) => p.name == 'Biryani');
      expect(juiceIdx, isNot(-1));
      if (biryaniIdx != -1) expect(juiceIdx, lessThan(biryaniIdx));
    });

    test('Case 6: Fast Food + Pizza-lover customer', () {
      final f = byLabel('Fast Food');
      final sales = {for (final p in f.products) p.id: 2};
      final ctx = buildCtx(vendor: f.vendor, products: f.products, behavior: pizzaLoverCustomer(), sales30: sales);
      final result = RecommendationEngine.recommendForYou(ctx, limit: 20);
      final pizzaIdx = result.indexWhere((p) => p.name == 'Pizza');
      final soupIdx = result.indexWhere((p) => p.name == 'Soup');
      expect(pizzaIdx, isNot(-1));
      if (soupIdx != -1) expect(pizzaIdx, lessThan(soupIdx));
    });

    // ── 7-12: multi-cuisine restaurants x mismatched/mixed personas ──

    test('Case 7: North Indian + Chinese restaurant + mixed-preference customer', () {
      final f = byLabel('North Indian + Chinese');
      final sales = {for (final p in f.products) p.id: 2};
      final ctx = buildCtx(vendor: f.vendor, products: f.products, behavior: mixedPreferenceCustomer(), sales30: sales);
      expect(() => RecommendationEngine.recommendForYou(ctx, limit: 20), returnsNormally);
      final result = RecommendationEngine.recommendForYou(ctx, limit: 20);
      final categories = result.map((p) => p.categoryID).toSet();
      expect(categories.length, greaterThan(1), reason: 'a mixed-preference customer should see variety, not one category');
    });

    test('Case 8: North Indian + Fast Food restaurant + brand-new customer (no sales) -> true cold start', () {
      final f = byLabel('North Indian + Fast Food');
      final v = vendor(id: f.vendor.id, businessTypeId: '', cuisineIds: []); // strip config for a genuine cold start
      final ctx = buildCtx(vendor: v, products: f.products, behavior: brandNewCustomer());
      expect(RecommendationEngine.recommendForYou(ctx), isEmpty);
    });

    test('Case 9: Chinese + Cafe restaurant + North Indian-lover customer (mismatched taste, must not crash)', () {
      final f = byLabel('Chinese + Cafe');
      final sales = {for (final p in f.products) p.id: 2};
      final ctx = buildCtx(vendor: f.vendor, products: f.products, behavior: northIndianLoverCustomer(), sales30: sales);
      expect(() => RecommendationEngine.recommendForYou(ctx, limit: 20), returnsNormally);
      expect(RecommendationEngine.recommendForYou(ctx, limit: 20), isNotEmpty);
    });

    test('Case 10: Cafe + Bakery restaurant + dessert-lover customer', () {
      final f = byLabel('Cafe + Bakery');
      final sales = {for (final p in f.products) p.id: 2};
      final ctx = buildCtx(vendor: f.vendor, products: f.products, behavior: dessertLoverCustomer(), sales30: sales);
      final result = RecommendationEngine.recommendForYou(ctx, limit: 20);
      expect(result.indexWhere((p) => p.name == 'Dessert'), isNot(-1));
    });

    test('Case 11: North Indian + Chinese + Fast Food restaurant + Pizza-lover customer', () {
      final f = byLabel('North Indian + Chinese + Fast Food');
      final sales = {for (final p in f.products) p.id: 2};
      final ctx = buildCtx(vendor: f.vendor, products: f.products, behavior: pizzaLoverCustomer(), sales30: sales);
      final result = RecommendationEngine.recommendForYou(ctx, limit: 20);
      final pizzaIdx = result.indexWhere((p) => p.name == 'Pizza');
      final soupIdx = result.indexWhere((p) => p.name == 'Soup');
      expect(pizzaIdx, isNot(-1));
      if (soupIdx != -1) expect(pizzaIdx, lessThan(soupIdx));
    });

    test('Case 12: North Indian + Chinese + Beverage restaurant + beverage-lover customer', () {
      final f = byLabel('North Indian + Chinese + Beverage');
      final sales = {for (final p in f.products) p.id: 2};
      final ctx = buildCtx(vendor: f.vendor, products: f.products, behavior: beverageLoverCustomer(), sales30: sales);
      final result = RecommendationEngine.recommendForYou(ctx, limit: 20);
      final coffeeIdx = result.indexWhere((p) => p.name == 'Coffee');
      final biryaniIdx = result.indexWhere((p) => p.name == 'Biryani');
      expect(coffeeIdx, isNot(-1));
      if (biryaniIdx != -1) expect(coffeeIdx, lessThan(biryaniIdx));
    });

    // ── 13-18: Business Context configuration matrix x varied customers ──

    test('Case 13: Cloud Kitchen (no Business Type profile) + North Indian-lover + high sales', () {
      final f = byLabel('Cloud Kitchen (no Business Type profile)');
      final sales = {for (final p in f.products) p.id: 3};
      final ctx = buildCtx(
        vendor: f.vendor,
        products: f.products,
        behavior: northIndianLoverCustomer(),
        sales30: sales,
        businessTypeProfiles: fullBusinessTypeProfiles, // has no entry for Cloud Kitchen's type - by design
        cuisineCategoryAffinity: fullCuisineAffinity,
      );
      expect(() => RecommendationEngine.recommendForYou(ctx, limit: 20), returnsNormally);
      final result = RecommendationEngine.recommendForYou(ctx, limit: 20);
      expect(result.indexWhere((p) => p.name == 'Butter Naan'), isNot(-1),
          reason: 'Cloud Kitchen should still inherit from Cuisine even with no Business Type profile');
    });

    test('Case 14: No cuisine configured restaurant + mixed-preference customer', () {
      final f = byLabel('No cuisine configured');
      final sales = {for (final p in f.products) p.id: 2};
      final ctx = buildCtx(
        vendor: f.vendor, products: f.products, behavior: mixedPreferenceCustomer(), sales30: sales,
        businessTypeProfiles: fullBusinessTypeProfiles, cuisineCategoryAffinity: fullCuisineAffinity,
      );
      expect(() => RecommendationEngine.recommendForYou(ctx, limit: 20), returnsNormally);
    });

    test('Case 15: No Business Type configured restaurant + North Indian-lover customer', () {
      final f = byLabel('No Business Type configured');
      final sales = {for (final p in f.products) p.id: 2};
      final ctx = buildCtx(
        vendor: f.vendor, products: f.products, behavior: northIndianLoverCustomer(), sales30: sales,
        businessTypeProfiles: fullBusinessTypeProfiles, cuisineCategoryAffinity: fullCuisineAffinity,
      );
      final result = RecommendationEngine.recommendForYou(ctx, limit: 20);
      expect(result.indexWhere((p) => p.name == 'Butter Naan'), isNot(-1));
    });

    test('Case 16: Only Business Type configured restaurant + brand-new customer', () {
      final f = byLabel('Only Business Type configured');
      final sales = {for (final p in f.products) p.id: 2};
      final ctx = buildCtx(
        vendor: f.vendor, products: f.products, behavior: brandNewCustomer(), sales30: sales,
        businessTypeProfiles: fullBusinessTypeProfiles, cuisineCategoryAffinity: fullCuisineAffinity,
      );
      expect(() => RecommendationEngine.recommendForYou(ctx, limit: 20), returnsNormally);
    });

    test('Case 17: Both configured restaurant + huge-history customer', () {
      final f = byLabel('Both Business Type and Cuisine configured');
      final sales = {for (final p in f.products) p.id: 2};
      final hugeMap = {for (var i = 0; i < 3000; i++) 'other_product_$i': i % 30};
      final huge = BehaviorSummarySnapshot(
        productViewCounts: hugeMap, productOrderQuantities: hugeMap, categoryInteractionCounts: hugeMap, orderCount: 3000,
      );
      final ctx = buildCtx(
        vendor: f.vendor, products: f.products, behavior: huge, sales30: sales,
        businessTypeProfiles: fullBusinessTypeProfiles, cuisineCategoryAffinity: fullCuisineAffinity,
      );
      expect(() => RecommendationEngine.recommendForYou(ctx, limit: 20), returnsNormally);
    });

    test('Case 18: Neither configured restaurant + zero-orders-but-browsed customer', () {
      final f = byLabel('Neither configured');
      final sales = {for (final p in f.products) p.id: 2};
      final ctx = buildCtx(vendor: f.vendor, products: f.products, behavior: zeroOrderButBrowsingCustomer(), sales30: sales);
      expect(() => RecommendationEngine.recommendForYou(ctx, limit: 20), returnsNormally);
    });

    // ── 19-23: menu-size bands x varied customers/sales ──

    test('Case 19: Tiny menu (5 products) + North Indian-lover customer -> sections hidden entirely', () {
      final f = byLabel('Tiny menu (5 products)');
      final ctx = buildCtx(vendor: f.vendor, products: f.products, behavior: northIndianLoverCustomer());
      expect(RecommendationEngine.hasEnoughProductsForSections(ctx), isFalse);
    });

    test('Case 20: Small menu (15 products) + zero sales -> Explore fallback, not Recommended For You', () {
      final f = byLabel('Small menu (15 products)');
      final ctx = buildCtx(
        vendor: f.vendor, products: f.products, behavior: mixedPreferenceCustomer(),
        businessTypeProfiles: fullBusinessTypeProfiles, cuisineCategoryAffinity: fullCuisineAffinity,
      );
      expect(RecommendationEngine.shouldShowExploreMenuFallback(ctx), isTrue);
      expect(RecommendationEngine.exploreMenuSelection(ctx, limit: RecommendationEngine.sectionLimitFor(ctx)), isNotEmpty);
    });

    test('Case 21: Medium menu (40 products) + sufficient sales + Chinese-lover customer', () {
      final f = byLabel('Medium menu (40 products)');
      final sales = {for (final p in f.products.take(6)) p.id: 3};
      final ctx = buildCtx(vendor: f.vendor, products: f.products, behavior: chineseLoverCustomer(), sales30: sales);
      expect(RecommendationEngine.hasSufficientRestaurantConfidence(ctx), isTrue);
      expect(RecommendationEngine.recommendForYou(ctx, limit: RecommendationEngine.sectionLimitFor(ctx)), isNotEmpty);
    });

    test('Case 22: Large menu (150 products) + North Indian-lover customer + high sales -> dynamic limit 15', () {
      final f = byLabel('Large menu (150 products)');
      final sales = {for (final p in f.products.take(8)) p.id: 3};
      final ctx = buildCtx(
        vendor: f.vendor, products: f.products, behavior: northIndianLoverCustomer(), sales30: sales,
        businessTypeProfiles: fullBusinessTypeProfiles, cuisineCategoryAffinity: fullCuisineAffinity,
      );
      expect(RecommendationEngine.sectionLimitFor(ctx), 15);
      final result = RecommendationEngine.recommendForYou(ctx, limit: RecommendationEngine.sectionLimitFor(ctx));
      expect(result.length, lessThanOrEqualTo(15));
    });

    test('Case 23: Huge menu (500 products) + mixed-preference customer -> no crash, capped at 20', () {
      final f = byLabel('Huge menu (500 products, performance)');
      final sales = {for (var i = 0; i < f.products.length; i += 5) f.products[i].id: (i % 15) + 1};
      final ctx = buildCtx(vendor: f.vendor, products: f.products, behavior: mixedPreferenceCustomer(), sales30: sales);
      expect(RecommendationEngine.sectionLimitFor(ctx), 20);
      expect(() => RecommendationEngine.recommendForYou(ctx, limit: 20), returnsNormally);
    });

    // ── 24-26: cold-start / veteran / edge-size bookends ──

    test('Case 24: Zero-sales cold start restaurant + brand-new customer -> fully empty, no fabricated data', () {
      final f = byLabel('Zero-sales cold start (10 products)');
      final v = vendor(id: f.vendor.id, businessTypeId: '', cuisineIds: []);
      final ctx = buildCtx(vendor: v, products: f.products, behavior: brandNewCustomer());
      expect(RecommendationEngine.recommendForYou(ctx), isEmpty);
      expect(RecommendationEngine.recommendationConfidenceScores(ctx), isEmpty);
    });

    test('Case 25: High-sales veteran restaurant + customer with 100 orders on one favorite dish', () {
      final f = byLabel('High-sales veteran (50 products)');
      final favorite = f.products.first;
      final sales = {for (final p in f.products.take(10)) p.id: 4};
      final behavior = customerWithOrderVolume(100, favoriteProductId: favorite.id);
      final ctx = buildCtx(vendor: f.vendor, products: f.products, behavior: behavior, sales30: sales);
      final result = RecommendationEngine.recommendForYou(ctx, limit: 20);
      expect(result.take(5).map((p) => p.id), contains(favorite.id),
          reason: '100 orders on one dish should place it near the top');
    });

    test('Case 26: Single-product restaurant + huge-history customer -> graceful, no crash', () {
      final f = byLabel('Single product menu');
      final hugeMap = {for (var i = 0; i < 1000; i++) 'other_$i': i % 20};
      final huge = BehaviorSummarySnapshot(productViewCounts: hugeMap, productOrderQuantities: hugeMap, orderCount: 1000);
      final ctx = buildCtx(vendor: f.vendor, products: f.products, behavior: huge);
      expect(() => RecommendationEngine.recommendForYou(ctx), returnsNormally);
    });

    // ── 27-28: Pairs Well With x distinct restaurant/cart situations ──

    test('Case 27: North Indian + Chinese + Fast Food restaurant, Butter Chicken trigger, empty cart', () {
      final f = byLabel('North Indian + Chinese + Fast Food');
      final ctx = buildCtx(
        vendor: f.vendor, products: f.products,
        businessTypeProfiles: fullBusinessTypeProfiles, cuisineCategoryAffinity: fullCuisineAffinity,
      );
      final trigger = f.products.firstWhere((p) => p.name == 'Butter Chicken');
      final pool = f.products.where((p) => p.id != trigger.id).toList();
      final pairingScores = {for (final p in pool) p.id: RecommendationEngine.pairingContextScore(p, trigger, ctx)};
      final result = RecommendationEngine.fillPairsWellWith(
        vendorConfigured: const [], candidatePool: pool, mergedScores: const {},
        preferenceScores: const {}, bestSellerScores: const {}, crossSellFrequency: ctx.crossSellFrequency,
        pairingContextScores: pairingScores, maxItems: RecommendationEngine.pairingSectionLimitFor(ctx),
      );
      expect(result, isNotEmpty);
      expect(result.length, lessThanOrEqualTo(8));
      expect(result.map((p) => p.name), isNot(contains('Coffee')),
          reason: 'with 8 slots and abundant North-Indian-relevant candidates, Coffee should not make the cut');
    });

    test('Case 28: Cafe + Bakery restaurant, Coffee trigger, cart already saturated with Dessert', () {
      final f = byLabel('Cafe + Bakery');
      final ctx = buildCtx(
        vendor: f.vendor, products: f.products,
        businessTypeProfiles: fullBusinessTypeProfiles, cuisineCategoryAffinity: fullCuisineAffinity,
      );
      final trigger = f.products.firstWhere((p) => p.name == 'Coffee');
      final pool = f.products.where((p) => p.id != trigger.id).toList();
      final pairingScores = {for (final p in pool) p.id: RecommendationEngine.pairingContextScore(p, trigger, ctx)};
      final result = RecommendationEngine.fillPairsWellWith(
        vendorConfigured: const [], candidatePool: pool, mergedScores: const {},
        preferenceScores: const {}, bestSellerScores: const {}, crossSellFrequency: ctx.crossSellFrequency,
        pairingContextScores: pairingScores,
        cartCategoryCounts: {catDessert: 2}, // 2 desserts already in cart - deprioritized, not removed
        maxItems: 3,
      );
      expect(result.any((p) => p.categoryID == catDessert), isFalse,
          reason: 'with abundant non-saturated alternatives (Pasta) and only 3 slots, saturated Dessert should not surface');
    });

    // ── 29-30: Restaurant Must Try / Most Loved Here x distinct data ──

    test('Case 29: High-sales veteran restaurant + huge-history customer -> Restaurant Must Try ordered correctly', () {
      final f = byLabel('High-sales veteran (50 products)');
      final sales = {for (final p in f.products) p.id: (f.products.indexOf(p) % 6) + 1};
      final sales7 = {for (final p in f.products) p.id: (f.products.indexOf(p) % 3)};
      final hugeMap = {for (var i = 0; i < 800; i++) 'other_$i': i % 25};
      final huge = BehaviorSummarySnapshot(productViewCounts: hugeMap, productOrderQuantities: hugeMap, orderCount: 800);
      final ctx = buildCtx(vendor: f.vendor, products: f.products, behavior: huge, sales30: sales, sales7: sales7);
      final mustTry = RecommendationEngine.topBySource(ctx, 'mustTry', n: 10);
      final scores = RecommendationEngine.scoreBySource(ctx, 'mustTry');
      for (var i = 0; i < mustTry.length - 1; i++) {
        expect(scores[mustTry[i].id]! + 1e-9, greaterThanOrEqualTo(scores[mustTry[i + 1].id]!));
      }
    });

    test('Case 30: Pure Fast Food restaurant + brand-new customer, real sales on only 3 dishes -> Most Loved Here restricted to those 3', () {
      final f = byLabel('Fast Food');
      final soldIds = f.products.take(3).map((p) => p.id).toSet();
      final sales = {for (final id in soldIds) id: 12};
      final ctx = buildCtx(vendor: f.vendor, products: f.products, behavior: brandNewCustomer(), sales30: sales);
      final result = RecommendationEngine.mostLovedHere(ctx, limit: 20);
      expect(result, isNotEmpty);
      for (final p in result) {
        expect(soldIds, contains(p.id), reason: '${p.name} has no real sales this window and should not appear');
      }
    });
  });
}
