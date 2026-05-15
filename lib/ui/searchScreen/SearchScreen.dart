import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';

import 'package:emartconsumer/model/User.dart';

import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/productDetailsScreen/ProductDetailsScreen.dart';
// import 'package:emartconsumer/ui/vendorProductsScreen/NewVendorProductsScreen.dart';
import 'package:flutter/material.dart';

import 'package:geolocator/geolocator.dart';
import '../vendorProductsScreen/newVendorProductsScreen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  SearchScreenState createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {

  User? customer;

  late List<VendorModel> vendorList = [];
  late List<VendorModel> vendorSearchList = [];

  late List<ProductModel> productList = [];
  late List<ProductModel> productSearchList = [];

  final FireStoreUtils fireStoreUtils = FireStoreUtils();

  // Performance optimization: Cache lowercase strings
  late List<String> _vendorLowerCaseCache = [];
  late List<String> _productLowerCaseCache = [];

  @override
  void initState() {
    super.initState();

    _loadCurrentCustomer();

    // fireStoreUtils.getVendors().then((value) {
    //   if (mounted) {
    //     setState(() {
    //       vendorList = value;
    //       // Build lowercase cache once
    //       _vendorLowerCaseCache = value.map((v) => v.title.toLowerCase()).toList();
    //     });
    //   }
    // });
    // fireStoreUtils.getAllProducts().then((value) {
    //   if (mounted) {
    //     setState(() {
    //       productList = value;
    //       // Build lowercase cache once
    //       _productLowerCaseCache = value.map((p) => p.name.toLowerCase()).toList();
    //     });
    //   }
    // });

 /// By Ak
    if (mounted) {
      setState(() {

        /// already filtered by
        /// selected address + admin radius
        vendorList = allstoreList;

        _vendorLowerCaseCache =
            vendorList
                .map(
                  (v) =>
                  v.title.toLowerCase(),
            )
                .toList();
      });
    }


  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: isDarkMode(context)
            ? AppThemeData.surfaceDark
            : AppThemeData.surface,
        appBar: AppBar(
          leading: InkWell(
              onTap: () {
                Navigator.pop(context);
              },
              child: const Icon(Icons.arrow_back)),
          actions: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                    left: 50,
                    top: 10,
                    right: Directionality.of(context)
                            .toString()
                            .contains(TextDirection.RTL.value.toLowerCase())
                        ? 50
                        : 10,
                    bottom: 10),
                child: SizedBox(
                  width: MediaQuery.of(context).size.width,
                  child: TextFormField(
                    textInputAction: TextInputAction.next,
                    onChanged: (value) {
                      onSearchTextChanged(value);
                    },
                    decoration: InputDecoration(
                      hintText: 'Search...'.tr(),
                      contentPadding:
                          const EdgeInsets.only(left: 10, right: 10, top: 10),
                      hintStyle: const TextStyle(color: Color(0XFF8A8989)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10.0),
                          borderSide: BorderSide(
                              color: AppThemeData.primary500, width: 2.0)),
                      errorBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.error),
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.error),
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                    ),
                  ),
                ),
              ),
            )
          ],
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Visibility(
                  visible: vendorSearchList.isNotEmpty,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Store",
                        style: TextStyle(
                            color: Colors.black,
                            fontFamily: AppThemeData.medium,
                            fontSize: 16),
                      ),
                      const SizedBox(
                        height: 10,
                      ),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: vendorSearchList.length,
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: true,
                        itemBuilder: (context, index) {
                          return data(vendorSearchList[index]);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  height: 10,
                ),
                // Visibility(
                //   visible: productSearchList.isNotEmpty,
                //   child: Column(
                //     mainAxisAlignment: MainAxisAlignment.start,
                //     crossAxisAlignment: CrossAxisAlignment.start,
                //     children: [
                //       Text(
                //         "Item".tr(),
                //         style: const TextStyle(
                //             color: Colors.black,
                //             fontFamily: AppThemeData.medium,
                //             fontSize: 16),
                //       ),
                //       const SizedBox(
                //         height: 10,
                //       ),
                //       ListView.builder(
                //         shrinkWrap: true,
                //         physics: const NeverScrollableScrollPhysics(),
                //         itemCount: productSearchList.length,
                //         addAutomaticKeepAlives: false,
                //         addRepaintBoundaries: true,
                //         itemBuilder: (context, index) {
                //           return product(productSearchList[index]);
                //         },
                //       ),
                //     ],
                //   ),
                // )
              ],
            ),
          ),
        ));
  }

  onSearchTextChanged(String text) {
    if (text.isEmpty) {
      if (mounted) {
        setState(() {
          vendorSearchList.clear();
          productSearchList.clear();
        });
      }
      return;
    }

    // Performance optimization: Convert search text to lowercase once
    final lowerText = text.toLowerCase();

    if (mounted) {
      setState(() {
        // Use cached lowercase strings for faster comparison
        vendorSearchList = [];
        for (int i = 0; i < vendorList.length; i++) {
          if (_vendorLowerCaseCache.length > i &&
              _vendorLowerCaseCache[i].contains(lowerText)) {
            vendorSearchList.add(vendorList[i]);
          }
        }

 /// by AK
        // productSearchList = [];
        // for (int i = 0; i < productList.length; i++) {
        //   if (_productLowerCaseCache.length > i &&
        //       _productLowerCaseCache[i].contains(lowerText)) {
        //     productSearchList.add(productList[i]);
        //   }
        // }


        // Sort vendorSearchList to show open shops first
        // vendorSearchList.sort((a, b) {
        //   if (a.isOpen() && !b.isOpen()) {
        //     return -1;
        //   } else if (!a.isOpen() && b.isOpen()) {
        //     return 1;
        //   } else {
        //     return 0;
        //   }
        // });

        vendorSearchList.sort((a, b) {

          /// Open first
          if (a.isOpen() && !b.isOpen()) {
            return -1;
          }

          if (!a.isOpen() && b.isOpen()) {
            return 1;
          }

          /// Higher rating first
          final aRating =
          a.reviewsCount > 0
              ? a.reviewsSum / a.reviewsCount
              : 0.0;

          final bRating =
          b.reviewsCount > 0
              ? b.reviewsSum / b.reviewsCount
              : 0.0;

          if (aRating != bRating) {
            return bRating.compareTo(aRating);
          }

          /// Nearest first
          final aDistance =
          _distanceFromUser(a);

          final bDistance =
          _distanceFromUser(b);

          return aDistance.compareTo(
            bDistance,
          );
        });

      });
    }
  }


  // double _distanceFromUser(
  //     VendorModel vendor) {
  //
  //   final userLat =
  //       userCurrent!.location.latitude;
  //
  //   final userLng =
  //       userCurrent!.location.longitude;
  //
  //   final latDiff =
  //       userLat - vendor.latitude;
  //
  //   final lngDiff =
  //       userLng - vendor.longitude;
  //
  //   return (latDiff * latDiff) +
  //       (lngDiff * lngDiff);
  // }


  Future<void> _loadCurrentCustomer() async {
    customer = await FireStoreUtils.getCurrentUser(
      FireStoreUtils.getCurrentUid(),
    );
  }

  double _distanceFromUser(VendorModel vendor) {

    if (customer == null ||
        customer!.shippingAddress == null ||
        customer!.shippingAddress!.isEmpty) {
      return 999999;
    }

    final selectedAddress =
    customer!.shippingAddress!.firstWhere(
          (e) => e.isDefault == true,
    );

    final userLat =
        selectedAddress.location!.latitude;

    final userLng =
        selectedAddress.location!.longitude;

    return Geolocator.distanceBetween(
      userLat,
      userLng,
      vendor.latitude,
      vendor.longitude,
    ) /
        1000;
  }



  @override

  void dispose() {
    vendorSearchList.clear();
    productSearchList.clear();
    super.dispose();
  }

  data(VendorModel vendorModel) {
    final isOpen = vendorModel.isOpen();
    debugPrint(
        'Vendorss ${vendorModel.title} is ${isOpen ? 'open' : 'closed'}');
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => push(
          context,
          NewVendorProductsScreen(
            vendorModel: vendorModel,
          )),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 4,
        ),
        child: Row(
          // crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                  isOpen ? Colors.transparent : Colors.grey,
                  BlendMode.saturation),
              child: CachedNetworkImage(
                  height: MediaQuery.of(context).size.height * 0.075,
                  width: MediaQuery.of(context).size.width * 0.16,
                  imageUrl: getImageVAlidUrl(vendorModel.photo),
                  imageBuilder: (context, imageProvider) => Container(
                        // width: 100,
                        // height: 100,
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(5),
                            image: DecorationImage(
                              image: imageProvider,
                              fit: BoxFit.cover,
                            )),
                      ),
                  errorWidget: (context, url, error) => ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.network(
                        placeholderImage,
                        fit: BoxFit.cover,
                      ))),
            ),
            const SizedBox(
              width: 10,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(vendorModel.title,
                          style: TextStyle(
                            fontSize: 16,
                            color:
                                isOpen ? const Color(0XFF555353) : Colors.grey,
                            // Color(0xff272727)
                          )),
                      const SizedBox(height: 3),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.location_on_sharp,
                            color:
                                isOpen ? const Color(0XFF555353) : Colors.grey,
                            size: 16,
                          ),
                          const SizedBox(width: 3),
                          Container(
                            constraints: const BoxConstraints(
                                maxWidth: 200, maxHeight: 50),
                            child: Text(
                              vendorModel.location,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 14,
                                color: isOpen
                                    ? const Color(0XFF555353)
                                    : Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  product(ProductModel productModel) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () async {
        VendorModel? vendorModel =
            await FireStoreUtils.getVendor(productModel.vendorID);
        if (vendorModel != null) {
          push(
            context,
            ProductDetailsScreen(
              vendorModel: vendorModel,
              productModel: productModel,
            ),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 4,
        ),
        child: Row(
          // crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            CachedNetworkImage(
                height: MediaQuery.of(context).size.height * 0.075,
                width: MediaQuery.of(context).size.width * 0.16,
                imageUrl: getImageVAlidUrl(productModel.photo),
                imageBuilder: (context, imageProvider) => Container(
                      // width: 100,
                      // height: 100,
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          image: DecorationImage(
                            image: imageProvider,
                            fit: BoxFit.cover,
                          )),
                    ),
                errorWidget: (context, url, error) => ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Image.network(
                      placeholderImage,
                      fit: BoxFit.cover,
                    ))),
            const SizedBox(
              width: 10,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(productModel.name,
                          style: TextStyle(
                            fontSize: 16,
                            color: isDarkMode(context)
                                ? const Color(0xffFFFFFF)
                                : const Color(0xff272727),
                            // Color(0xff272727)
                          )),
                      const SizedBox(height: 3),
                      productModel.disPrice == "" ||
                              productModel.disPrice == "0"
                          ? Text(
                              amountShow(
                                  amount: productCommissionPrice(
                                      productModel.price)),
                              style: TextStyle(
                                  fontSize: 16,
                                  letterSpacing: 0.5,
                                  color: AppThemeData.primary500),
                            )
                          : Row(
                              children: [
                                Text(
                                  "${amountShow(amount: productCommissionPrice(productModel.disPrice.toString()))}",
                                  // "$symbol${double.parse(productModel.disPrice.toString()).toStringAsFixed(decimal)}",
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
                                  amountShow(
                                      amount: productCommissionPrice(
                                          productModel.price)),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey,
                                      decoration: TextDecoration.lineThrough),
                                ),
                              ],
                            ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
