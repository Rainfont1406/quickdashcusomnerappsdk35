import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/src/public_ext.dart';
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../AppGlobal.dart';
import '../../constants.dart';
import '../vendorProductsScreen/newVendorProductsScreen.dart';
// import '../vendorProductsScreen/NewVendorProductsScreen.dart';

class ViewAllPopularFoodNearByScreen extends StatefulWidget {
  const ViewAllPopularFoodNearByScreen({Key? key}) : super(key: key);

  @override
  _ViewAllPopularFoodNearByScreenState createState() => _ViewAllPopularFoodNearByScreenState();
}

class _ViewAllPopularFoodNearByScreenState extends State<ViewAllPopularFoodNearByScreen> {
  late Stream<List<VendorModel>> vendorsFuture;
  final fireStoreUtils = FireStoreUtils();
  Stream<List<VendorModel>>? lstAllStore;
  late Future<List<ProductModel>> productsFuture;
  List<ProductModel> lstNearByFood = [];
  List<VendorModel> vendors = [];
  bool showLoader = true;
  String? selctedOrderTypeValue = "Delivery".tr();
  VendorModel? popularNearFoodVendorModel;
  Stream<List<VendorModel>>? lstVendor;
  int totItem = 0;

  @override
  void initState() {
    super.initState();
    getFoodType();
    lstAllStore = fireStoreUtils.getAllStores().asBroadcastStream();
    lstAllStore!.listen((event) {
      vendors.clear();
      vendors.addAll(event);
      _filterProducts();
    });
    lstVendor = fireStoreUtils.getVendors1().asBroadcastStream();
    lstVendor!.listen((event) {
      setState(() {
        vendors.clear();
        vendors.addAll(event);
        _filterProducts();
      });
    });

    if (selctedOrderTypeValue == "Delivery") {
      productsFuture = fireStoreUtils.getAllDelevryProducts();
    } else {
      productsFuture = fireStoreUtils.getAllTakeAWayProducts();
    }

    productsFuture.then((value) {
      allProducts = value;
      _filterProducts();
    });
  }

  List<ProductModel> allProducts = [];

  void _filterProducts() {
    if (allProducts.isEmpty || vendors.isEmpty) return;

    print("======================Filtering products. Total products: ${allProducts.length}, Total vendors: ${vendors.length}");

    lstNearByFood.clear();

    // Filter products to only include those from online vendors
    for (var product in allProducts) {
      // Find the vendor for this product
      VendorModel? productVendor;
      for (var vendor in vendors) {
        if (vendor.id == product.vendorID) {
          productVendor = vendor;
          break;
        }
      }

      // Only add products from online vendors (reststatus = true OR within working hours)
      if (productVendor != null && (productVendor.reststatus || productVendor.isOpen())) {
        lstNearByFood.add(product);
        print("✅ Added product: ${product.name} from online vendor: ${productVendor.title} (reststatus: ${productVendor.reststatus}, isOpen: ${productVendor.isOpen()})");
      } else if (productVendor != null) {
        print("❌ Skipped product: ${product.name} - Vendor ${productVendor.title} is offline (reststatus: ${productVendor.reststatus}, isOpen: ${productVendor.isOpen()})");
      }
    }

    print("======================Filtered products from online vendors only. Total: ${lstNearByFood.length}");
    setState(() {
      showLoader = false;
    });
  }

  getFoodType() async {
    SharedPreferences sp = await SharedPreferences.getInstance();
    setState(() {
      selctedOrderTypeValue = sp.getString("foodType") == "" || sp.getString("foodType") == null ? "Delivery".tr() : sp.getString("foodType");
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDarkMode(context) ? AppThemeData.surfaceDark : AppThemeData.surface,
      appBar: AppGlobal.buildAppBar(context, "Top Selling".tr()),
      body: Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        margin: const EdgeInsets.fromLTRB(10, 0, 0, 10),
        child: showLoader
            ? Center(
                child: CircularProgressIndicator.adaptive(
                  valueColor: AlwaysStoppedAnimation(AppThemeData.primary500),
                ),
              )
            : lstNearByFood.isEmpty
                ? showEmptyState('No top selling found'.tr(), context)
                : ListView.builder(
                    shrinkWrap: true,
                    scrollDirection: Axis.vertical,
                    physics: const BouncingScrollPhysics(),
                    itemCount: lstNearByFood.length,
                    itemBuilder: (context, index) {
                      if (vendors.isNotEmpty) {
                        print("item name ${lstNearByFood[index].name}");
                        print("Vendor ====${vendors.length}");
                        popularNearFoodVendorModel = null;
                        for (int a = 0; a < vendors.length; a++) {
                          print(vendors[a].id.toString() + "===<><><><==" + lstNearByFood[index].vendorID);
                          if (vendors[a].id == lstNearByFood[index].vendorID) {
                            popularNearFoodVendorModel = vendors[a];
                          }
                        }
                      }
                      return popularNearFoodVendorModel == null
                          ? (totItem == 0 && index == (lstNearByFood.length - 1))
                              ? showEmptyState('No top selling found'.tr(), context)
                              : Container()
                          : buildVendorItemData(context, index, popularNearFoodVendorModel!);
                    }),
      ),
    );
  }

  Widget buildVendorItemData(BuildContext context, int index, VendorModel popularNearFoodVendorModel) {
    totItem++;
    return GestureDetector(
      onTap: () {
        print(popularNearFoodVendorModel.id.toString() + " *** " + popularNearFoodVendorModel.title.toString());
        push(
          context,
          NewVendorProductsScreen(vendorModel: popularNearFoodVendorModel),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: isDarkMode(context) ? AppThemeData.grey900 : AppThemeData.grey50,
        ),
        width: MediaQuery.of(context).size.width * 0.8,
        margin: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        padding: const EdgeInsets.all(5),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: getImageVAlidUrl(lstNearByFood[index].photo),
                height: 100,
                width: 100,
                imageBuilder: (context, imageProvider) => Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
                  ),
                ),
                placeholder: (context, url) => Center(
                    child: CircularProgressIndicator.adaptive(
                  valueColor: AlwaysStoppedAnimation(AppThemeData.primary500),
                )),
                errorWidget: (context, url, error) => ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Image.network(
                      placeholderImage,
                      fit: BoxFit.cover,
                      width: MediaQuery.of(context).size.width,
                      height: MediaQuery.of(context).size.height,
                    )),
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(
              width: 10,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lstNearByFood[index].name,
                    style:  TextStyle(
                      fontSize: 18,
                      color: isDarkMode(context) ? AppThemeData.grey50 : AppThemeData.grey900,
                    ),
                    maxLines: 1,
                  ),
                  const SizedBox(
                    height: 5,
                  ),
                  Text(
                    lstNearByFood[index].description,
                    maxLines: 1,
                    style:  TextStyle(
                      fontSize: 16,
                      color: isDarkMode(context) ? AppThemeData.grey400 : AppThemeData.grey500,
                    ),
                  ),
                  const SizedBox(
                    height: 5,
                  ),
                  lstNearByFood[index].disPrice == "" || lstNearByFood[index].disPrice == "0"
                      ? Text(
                    amountShow(amount: productCommissionPrice(lstNearByFood[index].price)),
                    style: TextStyle(fontSize: 16, letterSpacing: 0.5, color: AppThemeData.primary500),
                  )
                      : Row(
                    children: [
                      Text(
                        "${amountShow(amount: productCommissionPrice(lstNearByFood[index].disPrice.toString()))}",
                        // "$symbol${double.parse(lstNearByFood[index].disPrice.toString()).toStringAsFixed(decimal)}",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppThemeData.primary500,
                        ),
                      ),
                      const SizedBox(
                        width: 10,
                      ),
                      Text(
                        amountShow(amount: productCommissionPrice(lstNearByFood[index].price)),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, decoration: TextDecoration.lineThrough),
                      ),
                    ],
                  ),


                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
