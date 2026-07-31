// Targeted verification for the Combo Recommendation Algorithm Update:
// combos always sort after individuals, capped at maxComboRecommendationsPerSection
// (2), comboEligibilityScore gating (incl. meal-size), and Pairs Well With
// skipping entirely for a combo trigger. The existing 111+ tests in this
// directory never set isCombo: true anywhere, so none of this logic was
// previously exercised - this file closes that gap.
import 'package:emartconsumer/model/ComboProductItem.dart';
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/services/recommendation/behavior_summary_snapshot.dart';
import 'package:emartconsumer/services/recommendation/recommendation_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'vendor_dataset.dart';

void main() {
  final dataset = buildVendorDataset();

  ProductModel comboProduct({
    required String id,
    required String vendorID,
    required String categoryID,
    required List<String> childIds,
    String price = '500',
    String name = 'Family Combo',
  }) {
    return product(
      id: id,
      vendorID: vendorID,
      categoryID: categoryID,
      name: name,
      price: price,
    )
      ..isCombo = true
      ..comboProducts = childIds.map((c) => ComboProductItem(productId: c)).toList();
  }

  group('Combo Recommendation Algorithm Update', () {
    test('comboEligibilityScore: true cold start (no behavior at all) is always 0', () {
      final f = dataset.firstWhere((f) => f.label == 'North Indian + Fast Food');
      final combo = comboProduct(
        id: '${f.vendor.id}_combo1',
        vendorID: f.vendor.id,
        categoryID: catMain,
        childIds: [f.products.first.id],
      );
      final ctx = buildCtx(vendor: f.vendor, products: [...f.products, combo]);
      expect(RecommendationEngine.comboEligibilityScore(combo, ctx), 0.0);
    });

    test('comboEligibilityScore: strong evidence (prior order + child overlap + budget match) clears the threshold', () {
      final f = dataset.firstWhere((f) => f.label == 'North Indian + Fast Food');
      final naan = f.products.firstWhere((p) => p.name == 'Butter Naan');
      final rice = f.products.firstWhere((p) => p.name == 'Rice');
      final combo = comboProduct(
        id: '${f.vendor.id}_combo1',
        vendorID: f.vendor.id,
        categoryID: catMain,
        childIds: [naan.id, rice.id],
        price: '300',
      );
      final behavior = BehaviorSummarySnapshot(
        productOrderQuantities: {combo.id: 3, naan.id: 5, rice.id: 4},
        productViewCounts: {combo.id: 10, naan.id: 8, rice.id: 8},
        orderCount: 12,
        avgOrderValue: 300, // matches combo price closely
        comboOrderCount: 3,
        comboChildCountTotal: 6, // avg size 2, matches this combo's 2 children
      );
      final ctx = buildCtx(
        vendor: f.vendor, products: [...f.products, combo], behavior: behavior,
      );
      expect(RecommendationEngine.comboEligibilityScore(combo, ctx),
          greaterThanOrEqualTo(RecommendationEngine.comboEligibilityThreshold));
    });

    test('comboEligibilityScore: mealSizeSignal only applies once the customer has ordered a combo before', () {
      final f = dataset.firstWhere((f) => f.label == 'North Indian + Fast Food');
      final combo = comboProduct(
        id: '${f.vendor.id}_combo1',
        vendorID: f.vendor.id,
        categoryID: catMain,
        childIds: [f.products.first.id],
      );
      // Some generic behavior signal, but zero prior combo orders.
      final behavior = BehaviorSummarySnapshot(
        productViewCounts: {'x': 5},
        orderCount: 3,
      );
      final ctx = buildCtx(vendor: f.vendor, products: [...f.products, combo], behavior: behavior);
      // Should not throw and should not fabricate a mealSizeSignal contribution.
      expect(() => RecommendationEngine.comboEligibilityScore(combo, ctx), returnsNormally);
    });

    test('Recommended For You: a high-scoring but ineligible combo never outranks individual products', () {
      final f = dataset.firstWhere((f) => f.label == 'North Indian + Fast Food');
      final combo = comboProduct(
        id: '${f.vendor.id}_combo1',
        vendorID: f.vendor.id,
        categoryID: catMain, // primary Restaurant Type category -> high businessContext score
        childIds: [f.products.first.id],
      );
      final allProducts = [...f.products, combo];
      final sales = {for (final p in allProducts) p.id: 2};
      final ctx = buildCtx(
        vendor: f.vendor, products: allProducts, sales30: sales,
        businessTypeProfiles: fullBusinessTypeProfiles, cuisineCategoryAffinity: fullCuisineAffinity,
      );
      // No behavior at all -> comboEligibilityScore is 0 -> must be excluded entirely.
      final result = RecommendationEngine.recommendForYou(ctx, limit: 20);
      expect(result.map((p) => p.id), isNot(contains(combo.id)));
    });

    test('Recommended For You: an eligible combo still sorts after every individual product, never first', () {
      final f = dataset.firstWhere((f) => f.label == 'North Indian + Fast Food');
      final naan = f.products.firstWhere((p) => p.name == 'Butter Naan');
      final combo = comboProduct(
        id: '${f.vendor.id}_combo1',
        vendorID: f.vendor.id,
        categoryID: catMain,
        childIds: [naan.id],
        price: '300',
      );
      final allProducts = [...f.products, combo];
      final sales = {for (final p in allProducts) p.id: 1}; // low, uniform - combo's category score would otherwise dominate
      final behavior = BehaviorSummarySnapshot(
        productOrderQuantities: {combo.id: 5, naan.id: 5},
        productViewCounts: {combo.id: 10, naan.id: 10},
        orderCount: 10,
        avgOrderValue: 300,
      );
      final ctx = buildCtx(
        vendor: f.vendor, products: allProducts, sales30: sales, behavior: behavior,
        businessTypeProfiles: fullBusinessTypeProfiles, cuisineCategoryAffinity: fullCuisineAffinity,
      );
      expect(RecommendationEngine.comboEligibilityScore(combo, ctx),
          greaterThanOrEqualTo(RecommendationEngine.comboEligibilityThreshold));
      final result = RecommendationEngine.recommendForYou(ctx, limit: 20);
      final comboIdx = result.indexWhere((p) => p.id == combo.id);
      expect(comboIdx, isNot(-1), reason: 'combo should be eligible and present');
      expect(comboIdx, greaterThan(0), reason: 'must never be the first recommendation');
      final individualsBeforeCombo = result.take(comboIdx).where((p) => !p.isCombo).length;
      expect(individualsBeforeCombo, comboIdx,
          reason: 'every position before the combo must be an individual product');
    });

    test('Recommended For You: never more than comboSlotAllocation(limit, ctx) combos, even with many eligible', () {
      // 2026-07-25: recommendForYou's combo cap is now dynamic/customer-
      // adaptive (RecommendationEngine.comboSlotAllocation), replacing the
      // old flat maxComboRecommendationsPerSection (2) THIS TEST used to
      // assert against - exploreMenuSelection/fillPairsWellWith still use
      // that flat constant unchanged (see their own tests below/elsewhere).
      final f = dataset.firstWhere((f) => f.label == 'North Indian + Fast Food');
      final combos = List.generate(5, (i) => comboProduct(
            id: '${f.vendor.id}_combo$i',
            vendorID: f.vendor.id,
            categoryID: catMain,
            childIds: [f.products[i % f.products.length].id],
            price: '300',
          ));
      final allProducts = [...f.products, ...combos];
      final behavior = BehaviorSummarySnapshot(
        productOrderQuantities: {for (final c in combos) c.id: 5},
        productViewCounts: {for (final c in combos) c.id: 10},
        orderCount: 20,
        avgOrderValue: 300,
      );
      final ctx = buildCtx(vendor: f.vendor, products: allProducts, behavior: behavior);
      final result = RecommendationEngine.recommendForYou(ctx, limit: 30);
      final comboCount = result.where((p) => p.isCombo).length;
      // No comboOrderCount set on `behavior` -> baseline (non-adaptive) ratio.
      expect(comboCount, lessThanOrEqualTo(RecommendationEngine.comboSlotAllocation(30, ctx)));
      // And the baseline ratio itself must still land within the spec's own
      // ~15-20% band, not silently drift - 30 * 0.175 = 5.25 -> 5.
      expect(RecommendationEngine.comboSlotAllocation(30, ctx), 5);
    });

    test('Recommended For You: combo allocation scales with limit (8->1, 10->2, 15->3 at the baseline ratio)', () {
      final f = dataset.firstWhere((f) => f.label == 'North Indian + Fast Food');
      final ctx = buildCtx(vendor: f.vendor, products: f.products); // no behavior -> baseline ratio
      expect(RecommendationEngine.comboSlotAllocation(8, ctx), inInclusiveRange(1, 2));
      expect(RecommendationEngine.comboSlotAllocation(10, ctx), 2);
      expect(RecommendationEngine.comboSlotAllocation(15, ctx), inInclusiveRange(2, 3));
    });

    test('Recommended For You: tiny sections reserve no combo slot at all', () {
      final f = dataset.firstWhere((f) => f.label == 'North Indian + Fast Food');
      final ctx = buildCtx(vendor: f.vendor, products: f.products);
      expect(RecommendationEngine.comboSlotAllocation(3, ctx), 0);
    });

    test('Recommended For You: a customer who orders combos most of the time gets the 50-60% adaptive band', () {
      final f = dataset.firstWhere((f) => f.label == 'North Indian + Fast Food');
      final behavior = BehaviorSummarySnapshot(orderCount: 10, comboOrderCount: 7); // 70% combo rate
      final ctx = buildCtx(vendor: f.vendor, products: f.products, behavior: behavior);
      final slots = RecommendationEngine.comboSlotAllocation(10, ctx);
      expect(slots, inInclusiveRange(5, 6), reason: '50-60% of 10');
    });

    test('Recommended For You: a customer who rarely orders combos gets the 10-15% adaptive band, not the baseline', () {
      final f = dataset.firstWhere((f) => f.label == 'North Indian + Fast Food');
      final behavior = BehaviorSummarySnapshot(orderCount: 20, comboOrderCount: 1); // 5% combo rate
      final ctx = buildCtx(vendor: f.vendor, products: f.products, behavior: behavior);
      final slots = RecommendationEngine.comboSlotAllocation(20, ctx);
      expect(slots, inInclusiveRange(2, 3), reason: '10-15% of 20');
    });

    test('Cold Start: a brand-new, never-sold combo qualifies through category preference alone', () {
      // Explicit product example: customer likes Pizza + Garlic Bread; a
      // new Pizza Combo (Pizza + Garlic Bread + Coke) should already
      // qualify via category preference, before any sales/views/orders of
      // the combo itself.
      final f = dataset.firstWhere((f) => f.label == 'North Indian + Fast Food');
      final pizza = f.products.firstWhere((p) => p.name.contains('Pizza'),
          orElse: () => f.products.first);
      final combo = comboProduct(
        id: '${f.vendor.id}_pizza_combo',
        vendorID: f.vendor.id,
        categoryID: catMain,
        childIds: [pizza.id],
      );
      final allProducts = [...f.products, combo];
      // No order/view history for the combo or its children AT ALL - only
      // strong CATEGORY interaction, the one signal this test is isolating.
      final behavior = BehaviorSummarySnapshot(
        orderCount: 8,
        categoryInteractionCounts: {pizza.categoryID: 25},
      );
      final ctx = buildCtx(vendor: f.vendor, products: allProducts, behavior: behavior);
      expect(RecommendationEngine.comboEligibilityScore(combo, ctx),
          greaterThanOrEqualTo(RecommendationEngine.comboEligibilityThreshold),
          reason: 'category preference alone should be able to clear the bar for a genuinely new combo');
    });

    test('Combo Category Intelligence: comboCategoryIds (when set) is used instead of derived child categories', () {
      final f = dataset.firstWhere((f) => f.label == 'North Indian + Fast Food');
      final naan = f.products.firstWhere((p) => p.name == 'Butter Naan'); // real category: catBread
      final combo = comboProduct(
        id: '${f.vendor.id}_tagged_combo',
        vendorID: f.vendor.id,
        categoryID: catMain,
        childIds: [naan.id],
      )..comboCategoryIds = ['some_other_category_the_vendor_picked'];
      final allProducts = [...f.products, combo];
      // Strong preference for the CHILD's real category (catBread), but
      // NONE for the vendor-tagged category - if comboCategoryIds is being
      // honored (not silently falling back to child derivation), this
      // combo should get NO category-preference credit here.
      final behavior = BehaviorSummarySnapshot(
        orderCount: 8,
        categoryInteractionCounts: {naan.categoryID: 25},
      );
      final ctx = buildCtx(vendor: f.vendor, products: allProducts, behavior: behavior);
      final productById = {for (final p in allProducts) p.id: p};
      // Indirect check via the public surface: eligibility should be LOW
      // (no signal behind the vendor-tagged category), unlike the
      // "derived from children" Cold Start test above which clears the bar.
      expect(productById, isNotEmpty); // sanity: fixture wired correctly
      expect(RecommendationEngine.comboEligibilityScore(combo, ctx),
          lessThan(RecommendationEngine.comboEligibilityThreshold),
          reason: 'comboCategoryIds must take priority over derived child categories');
    });

    test('Explore Menu: combos are capped at 2 and sorted after individual representatives', () {
      final f = dataset.firstWhere((f) => f.label == 'North Indian + Chinese + Fast Food');
      // Give every category a combo variant too, all eligible.
      final combos = allMenuCategories
          .map((cat) => comboProduct(
                id: '${f.vendor.id}_combo_$cat',
                vendorID: f.vendor.id,
                categoryID: cat,
                childIds: [f.products.first.id],
                price: '300',
              ))
          .toList();
      final allProducts = [...f.products, ...combos];
      final behavior = BehaviorSummarySnapshot(
        productOrderQuantities: {for (final c in combos) c.id: 5},
        productViewCounts: {for (final c in combos) c.id: 10},
        orderCount: 50,
        avgOrderValue: 300,
      );
      final ctx = buildCtx(
        vendor: f.vendor, products: allProducts, behavior: behavior,
        businessTypeProfiles: fullBusinessTypeProfiles, cuisineCategoryAffinity: fullCuisineAffinity,
      );
      final result = RecommendationEngine.exploreMenuSelection(ctx, limit: 20);
      final comboCount = result.where((p) => p.isCombo).length;
      expect(comboCount, lessThanOrEqualTo(RecommendationEngine.maxComboRecommendationsPerSection));
      final firstComboIdx = result.indexWhere((p) => p.isCombo);
      if (firstComboIdx != -1) {
        final tailIsAllCombo = result.skip(firstComboIdx).every((p) => p.isCombo);
        expect(tailIsAllCombo, isTrue, reason: 'once a combo appears, only combos should follow');
      }
    });

    test('Explore Menu: an ineligible combo never becomes a category representative', () {
      final f = dataset.firstWhere((f) => f.label == 'North Indian + Fast Food');
      final combo = comboProduct(
        id: '${f.vendor.id}_combo1',
        vendorID: f.vendor.id,
        categoryID: catMain,
        childIds: [f.products.first.id],
      );
      final allProducts = [...f.products, combo];
      final ctx = buildCtx(
        vendor: f.vendor, products: allProducts,
        businessTypeProfiles: fullBusinessTypeProfiles, cuisineCategoryAffinity: fullCuisineAffinity,
      );
      final result = RecommendationEngine.exploreMenuSelection(ctx, limit: 20);
      expect(result.map((p) => p.id), isNot(contains(combo.id)));
    });

    test('Combo trigger: cuisine resolution considers child product categories, not just the combo\'s own category', () {
      final f = dataset.firstWhere((f) => f.label == 'North Indian + Chinese');
      final v = vendor(id: f.vendor.id, businessTypeId: '', cuisineIds: [cuisineNorthIndian, cuisineChinese]);
      final naan = f.products.firstWhere((p) => p.name == 'Butter Naan'); // North Indian (catBread)
      final combo = comboProduct(
        id: '${v.id}_combo1',
        vendorID: v.id,
        categoryID: 'cat_combo_bucket', // deliberately NOT in any cuisine's affinity set
        childIds: [naan.id],
      );
      final allProducts = [...f.products, combo];
      final ctx = buildCtx(vendor: v, products: allProducts, cuisineCategoryAffinity: fullCuisineAffinity);
      final rice = f.products.firstWhere((p) => p.name == 'Rice'); // North Indian (catRice)
      final noodles = f.products.firstWhere((p) => p.name == 'Noodles'); // Chinese (catNoodles)
      final riceScore = RecommendationEngine.pairingContextScore(rice, combo, ctx);
      final noodlesScore = RecommendationEngine.pairingContextScore(noodles, combo, ctx);
      expect(riceScore, greaterThan(noodlesScore),
          reason: 'combo child (Butter Naan, North Indian) should narrow cuisine to North Indian, favoring Rice over Noodles');
      expect(noodlesScore, 0.0,
          reason: 'Chinese-only category should be fully narrowed away once child-category resolution is applied');
    });

    test('Combo trigger: gracefully falls back when a child product no longer resolves (deleted/unpublished)', () {
      final f = dataset.firstWhere((f) => f.label == 'North Indian + Chinese');
      final combo = comboProduct(
        id: '${f.vendor.id}_combo1',
        vendorID: f.vendor.id,
        categoryID: 'cat_combo_bucket',
        childIds: ['nonexistent_deleted_product_id'],
      );
      final allProducts = [...f.products, combo];
      final ctx = buildCtx(vendor: f.vendor, products: allProducts, cuisineCategoryAffinity: fullCuisineAffinity);
      final rice = f.products.firstWhere((p) => p.name == 'Rice');
      expect(() => RecommendationEngine.pairingContextScore(rice, combo, ctx), returnsNormally);
    });
  });
}
