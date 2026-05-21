import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/src/public_ext.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/FavouriteItemModel.dart';
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/productDetailsScreen/ProductDetailsScreen.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../constants.dart';

class FavouriteItemScreen extends StatefulWidget {
  const FavouriteItemScreen({Key? key}) : super(key: key);

  @override
  _FavouriteItemScreenState createState() => _FavouriteItemScreenState();
}

class _FavouriteItemScreenState extends State<FavouriteItemScreen> with SingleTickerProviderStateMixin {
  final fireStoreUtils = FireStoreUtils();
  List<FavouriteItemModel> lstFavourite = [];
  List<ProductModel> favProductList = [];
  var position = const LatLng(23.12, 70.22);
  bool showLoader = true;

  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    getData();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDarkMode(context) ? AppThemeData.surfaceDark : AppThemeData.surface,
      body: showLoader
          ? _buildShimmerList()
          : favProductList.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  shrinkWrap: true,
                  scrollDirection: Axis.vertical,
                  physics: const BouncingScrollPhysics(),
                  itemCount: favProductList.length,
                  itemBuilder: (context, index) {
                    return buildAllStoreData(favProductList[index], index);
                  },
                ),
    );
  }

  Widget _buildShimmerList() {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 5,
      itemBuilder: (_, __) => _buildShimmerCard(),
    );
  }

  Widget _buildShimmerCard() {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, _) {
        final isDark = isDarkMode(context);
        final color = Color.lerp(
          isDark ? AppThemeData.grey900 : AppThemeData.grey100,
          isDark ? AppThemeData.grey700 : AppThemeData.grey300,
          _shimmerController.value,
        )!;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Container(
            height: 116,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: color,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.favorite_border_rounded, size: 72, color: AppThemeData.primary500.withValues(alpha: 0.35)),
          const SizedBox(height: 16),
          Text(
            'No Favourite Items',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppThemeData.grey600),
          ).tr(),
          const SizedBox(height: 6),
          Text(
            'Items you love will appear here',
            style: TextStyle(fontSize: 13, color: AppThemeData.grey400),
          ).tr(),
        ],
      ),
    );
  }

  Widget buildAllStoreData(ProductModel productModel, int index) {
    return GestureDetector(
      onTap: () async {
        VendorModel? vendorModel = await FireStoreUtils.getVendor(productModel.vendorID);
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
        padding: const EdgeInsets.all(8.0),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: ShapeDecoration(
            color: isDarkMode(context) ? AppThemeData.grey900 : AppThemeData.grey50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            shadows: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 32,
                offset: Offset(0, 0),
                spreadRadius: 0,
              )
            ],
          ),
          width: MediaQuery.of(context).size.width * 0.8,
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: productModel.photo,
                  height: 100,
                  width: 100,
                  imageBuilder: (context, imageProvider) => Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
                    ),
                  ),
                  placeholder: (context, url) => AnimatedBuilder(
                    animation: _shimmerController,
                    builder: (_, __) => Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: Color.lerp(
                          AppThemeData.grey100,
                          AppThemeData.grey300,
                          _shimmerController.value,
                        ),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Image.network(
                      placeholderImage,
                      fit: BoxFit.cover,
                      width: 100,
                      height: 100,
                    ),
                  ),
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            productModel.name,
                            style: const TextStyle(fontSize: 18),
                            maxLines: 1,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              FavouriteItemModel favouriteModel = FavouriteItemModel(
                                  product_id: productModel.id,
                                  section_id: sectionConstantModel!.id,
                                  store_id: productModel.vendorID,
                                  user_id: MyAppState.currentUser!.userID);
                              lstFavourite.removeWhere((item) => item.product_id == productModel.id);
                              favProductList.removeAt(index);
                              FireStoreUtils.removeFavouriteItem(favouriteModel);
                            });
                          },
                          child: Icon(Icons.favorite, color: AppThemeData.primary500),
                        )
                      ],
                    ),
                    const SizedBox(height: 5),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              productModel.reviewsCount != 0
                                  ? (productModel.reviewsSum / productModel.reviewsCount).toStringAsFixed(1)
                                  : '0',
                              style: const TextStyle(letterSpacing: 0.5, fontSize: 12, color: Colors.white),
                            ),
                            const SizedBox(width: 3),
                            const Icon(Icons.star, size: 16, color: Colors.white),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    productModel.disPrice == "" || productModel.disPrice == "0"
                        ? Text(
                            amountShow(amount: productCommissionPrice(productModel.price)),
                            style: TextStyle(fontSize: 16, letterSpacing: 0.5, color: AppThemeData.primary500),
                          )
                        : Row(
                            children: [
                              Text(
                                amountShow(amount: productCommissionPrice(productModel.disPrice.toString())),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppThemeData.primary500,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                amountShow(amount: productCommissionPrice(productModel.price)),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            ],
                          ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Future<void> getData() async {
    await fireStoreUtils.getFavouritesProductList(MyAppState.currentUser!.userID).then((value) {
      setState(() {
        lstFavourite.clear();
        lstFavourite.addAll(value);
      });
    });

    await fireStoreUtils.getAllProducts().then((value) {
      setState(() {
        lstFavourite.forEach((element) {
          final bool productIsInList = value.any((product) => product.id == element.product_id);
          if (productIsInList) {
            ProductModel productModel = value.firstWhere((product) => product.id == element.product_id);
            favProductList.add(productModel);
          }
        });
        showLoader = false;
      });
    });
  }
}
