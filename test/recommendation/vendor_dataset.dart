// The "20-30 restaurants" synthetic dataset required by the audit brief.
// Each entry is a self-contained (vendor, products, businessTypeProfiles,
// cuisineAffinity) tuple; sales/behavior are layered on per-test since those
// vary independently of restaurant identity.
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/model/VendorModel.dart';

import 'fixtures.dart';

class VendorFixture {
  final String label;
  final VendorModel vendor;
  final List<ProductModel> products;
  const VendorFixture(this.label, this.vendor, this.products);
}

List<VendorFixture> buildVendorDataset() {
  final out = <VendorFixture>[];

  VendorModel v(String id, String title, {String bt = '', List<String> cuisines = const []}) =>
      vendor(id: id, title: title, businessTypeId: bt, cuisineIds: cuisines);

  // 1-6: single-cuisine archetypes named in the brief.
  out.add(VendorFixture('Pure North Indian', v('v01', 'Punjab Da Dhaba', bt: btRestaurant, cuisines: [cuisineNorthIndian]), fullDishMenu('v01')));
  out.add(VendorFixture('Pure Chinese', v('v02', 'Golden Dragon', bt: btRestaurant, cuisines: [cuisineChinese]), fullDishMenu('v02')));
  out.add(VendorFixture('Cafe', v('v03', 'Brew & Bean', bt: btCafe, cuisines: [cuisineCafe]), fullDishMenu('v03')));
  out.add(VendorFixture('Bakery', v('v04', 'Sweet Crumbs', bt: btBakery, cuisines: [cuisineBakery]), fullDishMenu('v04')));
  out.add(VendorFixture('Juice Bar', v('v05', 'Fresh Squeeze', bt: btJuiceBar, cuisines: [cuisineBeverage]), fullDishMenu('v05')));
  out.add(VendorFixture('Fast Food', v('v06', 'Quick Bite', bt: btFastFood, cuisines: [cuisineFastFood]), fullDishMenu('v06')));

  // 7-12: multi-cuisine combinations named in the brief.
  out.add(VendorFixture('North Indian + Chinese', v('v07', 'Spice Fusion', bt: btRestaurant, cuisines: [cuisineNorthIndian, cuisineChinese]), fullDishMenu('v07')));
  out.add(VendorFixture('North Indian + Fast Food', v('v08', 'Curry & Crust', bt: btRestaurant, cuisines: [cuisineNorthIndian, cuisineFastFood]), fullDishMenu('v08')));
  out.add(VendorFixture('Chinese + Cafe', v('v09', 'Wok & Brew', bt: btCafe, cuisines: [cuisineChinese, cuisineCafe]), fullDishMenu('v09')));
  out.add(VendorFixture('Cafe + Bakery', v('v10', 'Crumb & Cup', bt: btCafe, cuisines: [cuisineCafe, cuisineBakery]), fullDishMenu('v10')));
  out.add(VendorFixture('North Indian + Chinese + Fast Food', v('v11', 'Triple Kitchen', bt: btRestaurant, cuisines: [cuisineNorthIndian, cuisineChinese, cuisineFastFood]), fullDishMenu('v11')));
  out.add(VendorFixture('North Indian + Chinese + Beverage', v('v12', 'Curry Noodle Cafe', bt: btRestaurant, cuisines: [cuisineNorthIndian, cuisineChinese, cuisineBeverage]), fullDishMenu('v12')));

  // 13: Cloud Kitchen - businessTypeId set, but NO entry in businessTypeProfiles anywhere.
  out.add(VendorFixture('Cloud Kitchen (no Business Type profile)', v('v13', 'Ghost Kitchen Co', bt: btCloudKitchen, cuisines: [cuisineNorthIndian]), fullDishMenu('v13')));

  // 14-18: Business Context configuration matrix.
  out.add(VendorFixture('No cuisine configured', v('v14', 'Mystery Menu', bt: btRestaurant, cuisines: []), fullDishMenu('v14')));
  out.add(VendorFixture('No Business Type configured', v('v15', 'Unlabeled Eats', bt: '', cuisines: [cuisineNorthIndian]), fullDishMenu('v15')));
  out.add(VendorFixture('Only Business Type configured', v('v16', 'Type Only Diner', bt: btRestaurant, cuisines: []), fullDishMenu('v16')));
  out.add(VendorFixture('Both Business Type and Cuisine configured', v('v17', 'Fully Configured Eats', bt: btRestaurant, cuisines: [cuisineNorthIndian]), fullDishMenu('v17')));
  out.add(VendorFixture('Neither configured', v('v18', 'Blank Slate Bistro', bt: '', cuisines: []), fullDishMenu('v18')));

  // 19-23: menu-size bands (Explore Menu verification + dynamic-limit bands).
  out.add(VendorFixture('Tiny menu (5 products)', v('v19', 'Tiny Table', bt: btRestaurant, cuisines: [cuisineNorthIndian]), fullDishMenu('v19').take(5).toList()));
  out.add(VendorFixture('Small menu (15 products)', v('v20', 'Small Spread', bt: btRestaurant, cuisines: [cuisineNorthIndian]), fullDishMenu('v20').take(15).toList()));
  out.add(VendorFixture('Medium menu (40 products)', v('v21', 'Mid Menu Manor', bt: btRestaurant, cuisines: [cuisineNorthIndian, cuisineChinese]), [...fullDishMenu('v21'), ...paddingProducts('v21', 40 - fullDishMenu('v21').length)].take(40).toList()));
  out.add(VendorFixture('Large menu (150 products)', v('v22', 'Big Buffet Barn', bt: btRestaurant, cuisines: [cuisineNorthIndian, cuisineChinese, cuisineFastFood]), [...fullDishMenu('v22'), ...paddingProducts('v22', 150 - fullDishMenu('v22').length)].take(150).toList()));
  out.add(VendorFixture('Huge menu (500 products, performance)', v('v23', 'Mega Mall Food Court', bt: btRestaurant, cuisines: [cuisineNorthIndian, cuisineChinese, cuisineFastFood]), [...fullDishMenu('v23'), ...paddingProducts('v23', 500 - fullDishMenu('v23').length)].take(500).toList()));

  // 24-25: cold-start / high-volume veteran bookends.
  out.add(VendorFixture('Zero-sales cold start (10 products)', v('v24', 'Brand New Bistro', bt: btRestaurant, cuisines: [cuisineNorthIndian]), fullDishMenu('v24').take(10).toList()));
  out.add(VendorFixture('High-sales veteran (50 products)', v('v25', 'Established Eatery', bt: btRestaurant, cuisines: [cuisineNorthIndian, cuisineChinese]), [...fullDishMenu('v25'), ...paddingProducts('v25', 50 - fullDishMenu('v25').length)].take(50).toList()));

  // 26: single-product edge case.
  out.add(VendorFixture('Single product menu', v('v26', 'One Dish Only', bt: btRestaurant, cuisines: [cuisineNorthIndian]), fullDishMenu('v26').take(1).toList()));

  return out;
}
