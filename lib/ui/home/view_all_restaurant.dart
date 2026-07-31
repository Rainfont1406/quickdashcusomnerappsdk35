import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/FavouriteModel.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/model/offer_model.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/behavior/behavior_event_types.dart';
import 'package:emartconsumer/services/behavior/behavior_tracker.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/widget/shimmer_box.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../vendorProductsScreen/newVendorProductsScreen.dart';

class ViewAllRestaurant extends StatefulWidget {
  const ViewAllRestaurant({Key? key}) : super(key: key);

  @override
  State<ViewAllRestaurant> createState() => _ViewAllRestaurantState();
}

class _ViewAllRestaurantState extends State<ViewAllRestaurant>
    with SingleTickerProviderStateMixin {
  List<VendorModel> vendors = [];
  List<String> lstFav = [];
  List<OfferModel> offerList = [];
  bool isLoading = true;

  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _loadData();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (MyAppState.currentUser != null) {
      final favs =
          await FireStoreUtils.getFavouriteStore(MyAppState.currentUser!.userID);
      lstFav = favs.map((f) => f.store_id ?? '').toList();
    }

    final offers = await FireStoreUtils().getPublicCoupons();

    final sorted = List<VendorModel>.from(allstoreList);
    _sortVendors(sorted);

    if (mounted) {
      setState(() {
        vendors = sorted;
        offerList = offers;
        isLoading = false;
      });
    }
  }

  void _sortVendors(List<VendorModel> list) {
    if (MyAppState.selectedPosotion.location == null) return;
    final double userLat = MyAppState.selectedPosotion.location!.latitude;
    final double userLng = MyAppState.selectedPosotion.location!.longitude;
    list.sort((a, b) {
      final bool aOpen = a.isAcceptingOrders;
      final bool bOpen = b.isAcceptingOrders;
      if (aOpen != bOpen) return aOpen ? -1 : 1;
      final double aRating =
          a.reviewsCount > 0 ? a.reviewsSum / a.reviewsCount : 0.0;
      final double bRating =
          b.reviewsCount > 0 ? b.reviewsSum / b.reviewsCount : 0.0;
      if (aRating != bRating) return bRating.compareTo(aRating);
      final double aDist = Geolocator.distanceBetween(
          userLat, userLng, a.latitude, a.longitude);
      final double bDist = Geolocator.distanceBetween(
          userLat, userLng, b.latitude, b.longitude);
      return aDist.compareTo(bDist);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? AppThemeData.surfaceDark : AppThemeData.surface,
      body: Column(
        children: [
          _buildGradientHeader(),
          Expanded(
            child: isLoading
                ? _buildShimmerList()
                : vendors.isEmpty
                    ? _buildEmptyState()
                    : _buildList(),
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
                  'All Stores'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (vendors.isNotEmpty)
                Text(
                  '${vendors.length}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
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
      itemCount: 6,
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
            Icons.store_outlined,
            size: 72,
            color: AppThemeData.primary500.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 16),
          Text(
            'No Nearby Restaurants',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppThemeData.grey600,
            ),
          ).tr(),
          const SizedBox(height: 6),
          Text(
            'Try changing your delivery address',
            style: TextStyle(fontSize: 13, color: AppThemeData.grey400),
          ).tr(),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      physics: const BouncingScrollPhysics(),
      itemCount: vendors.length,
      itemBuilder: (context, index) => _buildVendorCard(vendors[index]),
    );
  }

  /// Same "Closed" pill used on the home screen restaurant card, scaled
  /// down to fit this screen's smaller thumbnail.
  Widget _closedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEEEE),
        borderRadius: BorderRadius.circular(50),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFDC2626).withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: Color(0xFFDC2626),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 3),
          const Text(
            'Closed',
            style: TextStyle(
              color: Color(0xFFDC2626),
              fontSize: 9,
              height: 1.2,
              fontFamily: AppThemeData.semiBold,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVendorCard(VendorModel vendorModel) {
    final isDark = isDarkMode(context);

    final tempList = offerList
        .where((e) =>
            vendorModel.id == e.storeId &&
            (e.expireOfferDate?.toDate().isAfter(DateTime.now()) ?? false))
        .toList();
    final discounts = tempList
        .map((e) => double.tryParse(e.discountOffer.toString()) ?? 0.0)
        .toList();

    return GestureDetector(
      onTap: () {
        BehaviorTracker.setNextEntrySource('Home');
        push(context, NewVendorProductsScreen(vendorModel: vendorModel));
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
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _LazyVendorThumb(
                        cacheKey: vendorModel.id,
                        imageUrl: getImageVAlidUrl(vendorModel.photo),
                        size: 100,
                      ),
                    ),
                    if (discounts.isNotEmpty)
                      Positioned(
                        bottom: -6,
                        left: -1,
                        child: Container(
                          decoration: const BoxDecoration(
                            image: DecorationImage(
                              image:
                                  AssetImage('assets/images/offer_badge.png'),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              '${discounts.reduce(min).toStringAsFixed(currencyData?.decimal ?? 2)}% off',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (!vendorModel.isAcceptingOrders)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: _closedBadge(),
                      ),
                  ],
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
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              if (MyAppState.currentUser == null) {
                                push(context, const LoginScreen());
                              } else {
                                setState(() {
                                  if (lstFav.contains(vendorModel.id)) {
                                    lstFav.removeWhere(
                                        (item) => item == vendorModel.id);
                                    FireStoreUtils.removeFavouriteStore(
                                      FavouriteModel(
                                        section_id:
                                            sectionConstantModel?.id ?? '',
                                        store_id: vendorModel.id,
                                        user_id:
                                            MyAppState.currentUser!.userID,
                                      ),
                                    );
                                    BehaviorTracker.track(kEvtRestaurantUnfavorited,
                                        {'vendorId': vendorModel.id});
                                  } else {
                                    lstFav.add(vendorModel.id);
                                    FireStoreUtils.setFavouriteStore(
                                      FavouriteModel(
                                        section_id:
                                            sectionConstantModel?.id ?? '',
                                        store_id: vendorModel.id,
                                        user_id:
                                            MyAppState.currentUser!.userID,
                                      ),
                                    );
                                    BehaviorTracker.track(kEvtRestaurantFavorited,
                                        {'vendorId': vendorModel.id});
                                  }
                                });
                              }
                            },
                            child: Icon(
                              lstFav.contains(vendorModel.id)
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: lstFav.contains(vendorModel.id)
                                  ? AppThemeData.primary500
                                  : (isDark ? Colors.white38 : Colors.black38),
                            ),
                          ),
                        ],
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

// Viewport-gated (2026-07-20, explicit product request to verify this
// screen): this screen's outer ListView.builder is already a real,
// unbounded, non-shrinkWrap list (unlike AllStore/NewArrival on Home), so
// Flutter's own virtualization already limits how many cards build ahead of
// scroll - but the default cache extent still pre-builds a couple of cards
// beyond the visible screen, firing their image request immediately. Same
// VisibilityDetector-gated pattern as _RestaurantCardImage/_LazyDishImage
// elsewhere in the app, so only thumbnails actually scrolled into view ever
// fire a network request here too.
class _LazyVendorThumb extends StatefulWidget {
  final String cacheKey;
  final String imageUrl;
  final double size;

  const _LazyVendorThumb({
    required this.cacheKey,
    required this.imageUrl,
    required this.size,
  });

  @override
  State<_LazyVendorThumb> createState() => _LazyVendorThumbState();
}

class _LazyVendorThumbState extends State<_LazyVendorThumb> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    if (!_visible) {
      return VisibilityDetector(
        key: ValueKey('vendorThumb_${widget.cacheKey}'),
        onVisibilityChanged: (info) {
          if (!_visible && info.visibleFraction > 0 && mounted) {
            setState(() => _visible = true);
          }
        },
        child: ShimmerBox(
          width: widget.size,
          height: widget.size,
          borderRadius: 0, // outer ClipRRect at the call site already clips this
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: widget.imageUrl,
      height: widget.size,
      width: widget.size,
      fit: BoxFit.cover,
      imageBuilder: (context, imageProvider) => Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
        ),
      ),
      errorWidget: (context, url, error) => Image.network(
        placeholderImage,
        fit: BoxFit.cover,
        cacheHeight: widget.size.toInt(),
        cacheWidth: widget.size.toInt(),
      ),
    );
  }
}
