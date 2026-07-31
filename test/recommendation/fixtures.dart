// Synthetic test-data builders for the recommendation-engine audit
// (RECOMMENDATION_ENGINE_AUDIT.md). Nothing here touches Firestore/Flutter -
// RecommendationEngine itself is documented as pure Dart, so every fixture
// is a plain in-memory ProductModel/VendorModel/RestaurantRecommendationContext,
// matching exactly the shape FireStoreUtils.loadRecommendationContext hands
// the engine in production.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/recommendation/behavior_summary_snapshot.dart';
import 'package:emartconsumer/services/recommendation/recommendation_engine.dart';

// ── Category IDs (shared "menu" vocabulary across every fixture) ──────────
const catMain = 'cat_main_curry'; // Butter Chicken, Dal Makhani, Paneer Butter Masala
const catBread = 'cat_bread'; // Butter Naan, Garlic Naan
const catRice = 'cat_rice'; // Rice, Jeera Rice
const catSides = 'cat_sides'; // Raita
const catSalad = 'cat_salad'; // Salad
const catBiryani = 'cat_biryani'; // Biryani
const catHotBev = 'cat_hot_beverage'; // Coffee, Tea
const catColdBev = 'cat_cold_beverage'; // Juice, Milkshake
const catPizza = 'cat_pizza';
const catBurger = 'cat_burger';
const catPasta = 'cat_pasta';
const catNoodles = 'cat_noodles';
const catSoup = 'cat_soup';
const catDessert = 'cat_dessert';
const catDosa = 'cat_dosa'; // South Indian - dosa/idli/vada/sambar, unique to that cuisine

const allMenuCategories = [
  catMain, catBread, catRice, catSides, catSalad, catBiryani, catHotBev,
  catColdBev, catPizza, catBurger, catPasta, catNoodles, catSoup, catDessert,
  catDosa,
];

// ── Cuisine IDs + admin-configured affinity (business_context_cuisine_affinity) ──
const cuisineNorthIndian = 'cuisine_north_indian';
const cuisineChinese = 'cuisine_chinese';
const cuisineFastFood = 'cuisine_fast_food';
const cuisineCafe = 'cuisine_cafe';
const cuisineBakery = 'cuisine_bakery';
const cuisineBeverage = 'cuisine_beverage';
const cuisineSouthIndian = 'cuisine_south_indian';

final fullCuisineAffinity = <String, Set<String>>{
  cuisineNorthIndian: {catMain, catBread, catRice, catSides, catSalad, catBiryani},
  cuisineChinese: {catNoodles, catSoup},
  cuisineFastFood: {catPizza, catBurger},
  cuisineCafe: {catHotBev, catDessert, catPasta},
  cuisineBakery: {catDessert, catBread}, // deliberate overlap with North Indian's bread
  cuisineBeverage: {catHotBev, catColdBev},
  cuisineSouthIndian: {catDosa, catRice, catSides},
};

// ── Business Type IDs + admin-configured profiles (business_context_type_profiles) ──
const btRestaurant = 'bt_restaurant';
const btCafe = 'bt_cafe';
const btBakery = 'bt_bakery';
const btJuiceBar = 'bt_juice_bar';
const btFastFood = 'bt_fast_food';
const btCloudKitchen = 'bt_cloud_kitchen'; // deliberately NO entry below
const btIceCreamShop = 'bt_ice_cream_shop'; // deliberately NO entry below - archetype + degradation coverage in one
const btSweetShop = 'bt_sweet_shop'; // deliberately NO entry below
const btBeverageShop = 'bt_beverage_shop';

final fullBusinessTypeProfiles = <String, RestaurantTypeCategoryProfile>{
  btRestaurant: const RestaurantTypeCategoryProfile(
    primaryCategoryIds: {catMain, catBread, catRice},
    secondaryCategoryIds: {catSides, catSalad, catBiryani},
    lowPriorityCategoryIds: {catHotBev, catColdBev},
  ),
  btCafe: const RestaurantTypeCategoryProfile(
    primaryCategoryIds: {catHotBev, catDessert},
    secondaryCategoryIds: {catColdBev, catPasta},
    lowPriorityCategoryIds: {catMain},
  ),
  btBakery: const RestaurantTypeCategoryProfile(
    primaryCategoryIds: {catDessert, catBread},
  ),
  btJuiceBar: const RestaurantTypeCategoryProfile(
    primaryCategoryIds: {catColdBev},
    secondaryCategoryIds: {catHotBev},
  ),
  btFastFood: const RestaurantTypeCategoryProfile(
    primaryCategoryIds: {catPizza, catBurger},
    secondaryCategoryIds: {catColdBev},
  ),
  btBeverageShop: const RestaurantTypeCategoryProfile(
    primaryCategoryIds: {catHotBev, catColdBev},
  ),
  // btCloudKitchen/btIceCreamShop/btSweetShop: intentionally absent - "no
  // entry" is the real-world shape for a not-yet-configured Business Type,
  // reused here to cover both an archetype AND graceful-degradation in one.
};

// ── Product builder ─────────────────────────────────────────────────────
ProductModel product({
  required String id,
  required String vendorID,
  required String categoryID,
  String name = '',
  String price = '100',
  String? disPrice,
  bool publish = true,
  String productStatus = 'approved',
  List<String> recommendedProductIds = const [],
  Timestamp? createdAt,
  bool veg = true,
  bool nonveg = false,
}) {
  return ProductModel(
    id: id,
    vendorID: vendorID,
    categoryID: categoryID,
    name: name.isEmpty ? id : name,
    price: price,
    disPrice: disPrice,
    publish: publish,
    productStatus: productStatus,
    recommendedProductIds: recommendedProductIds,
    createdAt: createdAt,
    veg: veg,
    nonveg: nonveg,
    deliveryOption: true,
  );
}

/// The full 19-dish menu named explicitly in the audit brief, tagged to the
/// category vocabulary above. Every fixture vendor draws from (a subset of)
/// this same list, so cross-vendor comparisons stay meaningful.
List<ProductModel> fullDishMenu(String vendorId) => [
      product(id: '${vendorId}_butter_chicken', vendorID: vendorId, categoryID: catMain, name: 'Butter Chicken', nonveg: true, veg: false),
      product(id: '${vendorId}_dal_makhani', vendorID: vendorId, categoryID: catMain, name: 'Dal Makhani'),
      product(id: '${vendorId}_paneer_butter_masala', vendorID: vendorId, categoryID: catMain, name: 'Paneer Butter Masala'),
      product(id: '${vendorId}_butter_naan', vendorID: vendorId, categoryID: catBread, name: 'Butter Naan'),
      product(id: '${vendorId}_garlic_naan', vendorID: vendorId, categoryID: catBread, name: 'Garlic Naan'),
      product(id: '${vendorId}_rice', vendorID: vendorId, categoryID: catRice, name: 'Rice'),
      product(id: '${vendorId}_jeera_rice', vendorID: vendorId, categoryID: catRice, name: 'Jeera Rice'),
      product(id: '${vendorId}_raita', vendorID: vendorId, categoryID: catSides, name: 'Raita'),
      product(id: '${vendorId}_salad', vendorID: vendorId, categoryID: catSalad, name: 'Salad'),
      product(id: '${vendorId}_biryani', vendorID: vendorId, categoryID: catBiryani, name: 'Biryani', nonveg: true, veg: false),
      product(id: '${vendorId}_coffee', vendorID: vendorId, categoryID: catHotBev, name: 'Coffee'),
      product(id: '${vendorId}_tea', vendorID: vendorId, categoryID: catHotBev, name: 'Tea'),
      product(id: '${vendorId}_juice', vendorID: vendorId, categoryID: catColdBev, name: 'Juice'),
      product(id: '${vendorId}_milkshake', vendorID: vendorId, categoryID: catColdBev, name: 'Milkshake'),
      product(id: '${vendorId}_pizza', vendorID: vendorId, categoryID: catPizza, name: 'Pizza'),
      product(id: '${vendorId}_burger', vendorID: vendorId, categoryID: catBurger, name: 'Burger', nonveg: true, veg: false),
      product(id: '${vendorId}_pasta', vendorID: vendorId, categoryID: catPasta, name: 'Pasta'),
      product(id: '${vendorId}_noodles', vendorID: vendorId, categoryID: catNoodles, name: 'Noodles'),
      product(id: '${vendorId}_soup', vendorID: vendorId, categoryID: catSoup, name: 'Soup'),
      product(id: '${vendorId}_dessert', vendorID: vendorId, categoryID: catDessert, name: 'Dessert'),
    ];

/// N filler products cycling through the full category vocabulary, for
/// menu-size/performance fixtures where exact dish identity doesn't matter.
List<ProductModel> paddingProducts(String vendorId, int count, {int startAt = 0}) {
  return List.generate(count, (i) {
    final n = startAt + i;
    final cat = allMenuCategories[n % allMenuCategories.length];
    return product(
      id: '${vendorId}_pad_$n',
      vendorID: vendorId,
      categoryID: cat,
      name: 'Padding Item $n',
    );
  });
}

VendorModel vendor({
  required String id,
  String title = 'Test Restaurant',
  String businessTypeId = '',
  List<String> cuisineIds = const [],
  num reviewsCount = 0,
  num reviewsSum = 0,
}) {
  return VendorModel(
    id: id,
    title: title,
    businessTypeId: businessTypeId,
    cuisineIds: cuisineIds,
    reviewsCount: reviewsCount,
    reviewsSum: reviewsSum,
  );
}

RestaurantRecommendationContext buildCtx({
  required VendorModel vendor,
  required List<ProductModel> products,
  BehaviorSummarySnapshot? behavior,
  Map<String, int> sales30 = const {},
  Map<String, int> sales7 = const {},
  // Distinct-order counters (2026-07-23) - separate from sales30/sales7
  // (quantity, drives ranking). These drive ONLY the confidence bar's fill
  // value; default to {}/0 like production does for a vendor with no
  // order-count data yet (fill reads as 0.0).
  Map<String, int> productOrders90 = const {},
  Map<String, int> productOrders7 = const {},
  int totalOrders90 = 0,
  int totalOrders7 = 0,
  Map<String, RestaurantTypeCategoryProfile> businessTypeProfiles = const {},
  Map<String, Set<String>> cuisineCategoryAffinity = const {},
}) {
  return RestaurantRecommendationContext(
    vendor: vendor,
    allProducts: products,
    behaviorSummary: behavior ?? BehaviorSummarySnapshot.empty(),
    rolling90DaySales: sales30,
    rolling7DaySales: sales7,
    productOrders90: productOrders90,
    productOrders7: productOrders7,
    totalOrders90: totalOrders90,
    totalOrders7: totalOrders7,
    crossSellFrequency: RecommendationEngine.computeCrossSellFrequency(products),
    businessTypeProfiles: businessTypeProfiles,
    cuisineCategoryAffinity: cuisineCategoryAffinity,
  );
}

// ── Customer behavior-history fixtures ─────────────────────────────────
BehaviorSummarySnapshot brandNewCustomer() => BehaviorSummarySnapshot.empty();

/// isEmpty is false (productViewCounts non-empty) but orderCount is 0 - the
/// "looked around, never ordered" shape, distinct from brandNewCustomer.
BehaviorSummarySnapshot zeroOrderButBrowsingCustomer() => const BehaviorSummarySnapshot(
      productViewCounts: {'some_other_vendor_product': 3},
      orderCount: 0,
    );

BehaviorSummarySnapshot categoryLoverCustomer(Map<String, int> categoryWeights,
        {int orderCount = 12}) =>
    BehaviorSummarySnapshot(
      categoryInteractionCounts: categoryWeights,
      orderCount: orderCount,
      productOrderQuantities: {'x': orderCount},
    );

BehaviorSummarySnapshot northIndianLoverCustomer() =>
    categoryLoverCustomer({catMain: 20, catBread: 15, catRice: 10, catSides: 6, catSalad: 4});

BehaviorSummarySnapshot chineseLoverCustomer() =>
    categoryLoverCustomer({catNoodles: 20, catSoup: 15});

BehaviorSummarySnapshot pizzaLoverCustomer() => categoryLoverCustomer({catPizza: 22, catBurger: 8});

BehaviorSummarySnapshot beverageLoverCustomer() =>
    categoryLoverCustomer({catHotBev: 18, catColdBev: 16});

BehaviorSummarySnapshot dessertLoverCustomer() => categoryLoverCustomer({catDessert: 20});

BehaviorSummarySnapshot mixedPreferenceCustomer() => categoryLoverCustomer({
      catMain: 6, catBread: 5, catNoodles: 5, catPizza: 5, catHotBev: 5, catDessert: 4,
    });

/// Order-volume ladder for the "does confidence increase with orders" check
/// - same relative shape, increasing absolute volume.
BehaviorSummarySnapshot customerWithOrderVolume(int orders, {required String favoriteProductId}) {
  return BehaviorSummarySnapshot(
    restaurantVisitCounts: {'v': orders},
    productOrderQuantities: {favoriteProductId: orders},
    productViewCounts: {favoriteProductId: orders * 2},
    orderCount: orders,
  );
}
