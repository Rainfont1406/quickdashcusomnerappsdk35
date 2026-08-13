import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/src/public_ext.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/FavouriteModel.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/behavior/behavior_tracker.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../constants.dart';
import '../../utils/network_image_widget.dart';
import '../../widget/coming_soon_view.dart';
import '../vendorProductsScreen/newVendorProductsScreen.dart';

class FavouriteStoreScreen extends StatefulWidget {
  const FavouriteStoreScreen({Key? key}) : super(key: key);

  @override
  _FavouriteStoreScreenState createState() => _FavouriteStoreScreenState();
}

class _FavouriteStoreScreenState extends State<FavouriteStoreScreen> with SingleTickerProviderStateMixin {
  late Future<List<VendorModel>> vendorFuture;
  final fireStoreUtils = FireStoreUtils();
  List<VendorModel> storeAllLst = [];
  List<FavouriteModel> lstFavourite = [];
  var position = const LatLng(23.12, 70.22);
  bool showLoader = true;
  VendorModel? vendorModel;

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
    return ValueListenableBuilder<bool>(
      valueListenable: isDeliveryActiveNotifier,
      builder: (context, deliveryActive, _) {
        if (currentOrderTypeGlobal == 'Delivery'.tr() && !deliveryActive) {
          return ComingSoonScreen(message: deliveryOffMessageNotifier.value);
        }
        return _buildScreen(context);
      },
    );
  }

  Widget _buildScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: isDarkMode(context) ? AppThemeData.surfaceDark : AppThemeData.surface,
      body: showLoader
          ? _buildShimmerList()
          : lstFavourite.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  shrinkWrap: true,
                  scrollDirection: Axis.vertical,
                  physics: const BouncingScrollPhysics(),
                  itemCount: lstFavourite.length,
                  itemBuilder: (context, index) {
                    if (storeAllLst.isNotEmpty) {
                      for (int a = 0; a < storeAllLst.length; a++) {
                        if (storeAllLst[a].id == lstFavourite[index].store_id) {
                          vendorModel = storeAllLst[a];
                        }
                      }
                    }
                    return vendorModel == null ? const SizedBox.shrink() : buildAllStoreData(vendorModel!, index);
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
          Icon(Icons.store_outlined, size: 72, color: AppThemeData.primary500.withValues(alpha: 0.35)),
          const SizedBox(height: 16),
          Text(
            'No Favourite Stores',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppThemeData.grey600),
          ).tr(),
          const SizedBox(height: 6),
          Text(
            'Stores you love will appear here',
            style: TextStyle(fontSize: 13, color: AppThemeData.grey400),
          ).tr(),
        ],
      ),
    );
  }

  Widget buildAllStoreData(VendorModel vendorModel, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      child: GestureDetector(
        onTap: () {
          BehaviorTracker.setNextEntrySource('Favourites');
          precacheVendorHeroImage(context, vendorModel);
          push(
            context,
            NewVendorProductsScreen(vendorModel: vendorModel),
          );
        },
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
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: getImageVAlidUrl(vendorModel.photo),
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
                    borderRadius: BorderRadius.circular(20),
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
                            vendorModel.title,
                            style: const TextStyle(fontSize: 18),
                            maxLines: 1,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              FavouriteModel favouriteModel = FavouriteModel(
                                  store_id: vendorModel.id, user_id: MyAppState.currentUser!.userID);
                              lstFavourite.removeWhere((item) => item == vendorModel.id);
                              FireStoreUtils.removeFavouriteStore(favouriteModel);
                              lstFavourite.removeAt(index);
                            });
                          },
                          child: Icon(Icons.favorite, color: AppThemeData.primary500),
                        )
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      vendorModel.location,
                      maxLines: 1,
                      style: const TextStyle(fontSize: 16, color: Color(0xff9091A4)),
                    ),
                    const SizedBox(height: 10),
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
                              vendorModel.reviewsCount != 0
                                  ? (vendorModel.reviewsSum / vendorModel.reviewsCount).toStringAsFixed(1)
                                  : '0',
                              style: const TextStyle(letterSpacing: 0.5, fontSize: 12, color: Colors.white),
                            ),
                            const SizedBox(width: 3),
                            const Icon(Icons.star, size: 16, color: Colors.white),
                          ],
                        ),
                      ),
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

  void getData() {
    FireStoreUtils.getFavouriteStore(MyAppState.currentUser!.userID).then((value) {
      setState(() {
        lstFavourite.clear();
        lstFavourite.addAll(value);
      });
    });
    vendorFuture = fireStoreUtils.getVendors();

    vendorFuture.then((value) {
      setState(() {
        storeAllLst.clear();
        storeAllLst.addAll(value);
        showLoader = false;
      });
    });
  }
}
