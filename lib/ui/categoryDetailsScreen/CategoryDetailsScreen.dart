import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/VendorCategoryModel.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/behavior/behavior_tracker.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/dineInScreen/dine_in_restaurant_details_screen.dart';
import 'package:emartconsumer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:emartconsumer/utils/network_image_widget.dart';
import 'package:emartconsumer/widget/coming_soon_view.dart';
import 'package:flutter/material.dart';

class CategoryDetailsScreen extends StatefulWidget {
  final VendorCategoryModel category;
  final bool isDineIn;

  const CategoryDetailsScreen(
      {Key? key, required this.category, required this.isDineIn})
      : super(key: key);

  @override
  _CategoryDetailsScreenState createState() => _CategoryDetailsScreenState();
}

class _CategoryDetailsScreenState extends State<CategoryDetailsScreen>
    with SingleTickerProviderStateMixin {
  Stream<List<VendorModel>>? categoriesFuture;
  final FireStoreUtils fireStoreUtils = FireStoreUtils();
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    final nearbyIds = allstoreList.map((v) => v.id).toSet();
    categoriesFuture = fireStoreUtils
        .getVendorsByCuisineID(widget.category.id.toString(),
            isDinein: widget.isDineIn)
        .map((vendors) => nearbyIds.isEmpty
            ? vendors
            : vendors.where((v) => nearbyIds.contains(v.id)).toList());
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
      backgroundColor:
          isDarkMode(context) ? AppThemeData.surfaceDark : AppThemeData.surface,
      body: Column(
        children: [
          _buildGradientHeader(),
          Expanded(
            child: StreamBuilder<List<VendorModel>>(
              stream: categoriesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildShimmerList();
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return _buildEmptyState();
                }
                return ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  physics: const BouncingScrollPhysics(),
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) =>
                      _buildVendorCard(snapshot.data![index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppThemeData.primary500, AppThemeData.primary400],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.category.title.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 5,
      itemBuilder: (_, __) => AnimatedBuilder(
        animation: _shimmerController,
        builder: (context, _) {
          final color = Color.lerp(
            isDarkMode(context) ? AppThemeData.grey900 : AppThemeData.grey100,
            isDarkMode(context) ? AppThemeData.grey700 : AppThemeData.grey300,
            _shimmerController.value,
          )!;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Container(
              height: 116,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: color,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.restaurant_outlined,
            size: 72,
            color: AppThemeData.primary500.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 16),
          Text(
            'No Restaurants Found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppThemeData.grey600,
            ),
          ).tr(),
          const SizedBox(height: 6),
          Text(
            'No nearby restaurants in this category',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppThemeData.grey400),
          ).tr(),
        ],
      ),
    );
  }

  Widget _buildVendorCard(VendorModel vendorModel) {
    final isDark = isDarkMode(context);
    return GestureDetector(
      onTap: () {
        BehaviorTracker.setNextEntrySource('Category');
        if (widget.isDineIn) {
          push(context,
              DineInRestaurantDetailsScreen(vendorModel: vendorModel));
        } else {
          precacheVendorHeroImage(context, vendorModel);
          push(context, NewVendorProductsScreen(vendorModel: vendorModel));
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: ShapeDecoration(
            color: isDark ? AppThemeData.grey900 : AppThemeData.grey50,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            shadows: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 32,
                offset: Offset(0, 0),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: getImageVAlidUrl(vendorModel.photo),
                    height: 100,
                    width: 100,
                    fit: BoxFit.cover,
                    imageBuilder: (context, imageProvider) => Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        image: DecorationImage(
                            image: imageProvider, fit: BoxFit.cover),
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
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        placeholderImage,
                        fit: BoxFit.cover,
                        width: 100,
                        height: 100,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vendorModel.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.location_pin,
                              size: 16, color: AppThemeData.primary500),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              vendorModel.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? Colors.white70
                                    : const Color(0xff9091A4),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.star_rounded,
                              size: 16, color: AppThemeData.primary500),
                          const SizedBox(width: 2),
                          Text(
                            vendorModel.reviewsCount != 0
                                ? (vendorModel.reviewsSum /
                                        vendorModel.reviewsCount)
                                    .toStringAsFixed(1)
                                : '0',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          if (vendorModel.reviewsCount > 0) ...[
                            const SizedBox(width: 2),
                            Text(
                              '(${vendorModel.reviewsCount.toStringAsFixed(0)})',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white60
                                    : const Color(0xff666666),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
