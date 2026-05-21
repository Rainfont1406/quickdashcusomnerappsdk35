import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ViewAllPopularFoodNearByScreen extends StatefulWidget {
  const ViewAllPopularFoodNearByScreen({Key? key}) : super(key: key);

  @override
  _ViewAllPopularFoodNearByScreenState createState() =>
      _ViewAllPopularFoodNearByScreenState();
}

class _ViewAllPopularFoodNearByScreenState
    extends State<ViewAllPopularFoodNearByScreen>
    with SingleTickerProviderStateMixin {
  List<ProductModel> lstNearByFood = [];
  bool showLoader = true;
  String selectedOrderType = "Delivery";
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _loadProducts();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final sp = await SharedPreferences.getInstance();
    final saved = sp.getString("foodType");
    if (saved != null && saved.isNotEmpty) selectedOrderType = saved;

    final List<ProductModel> allProducts = selectedOrderType == "Delivery"
        ? await FireStoreUtils().getAllDelevryProducts()
        : await FireStoreUtils().getAllTakeAWayProducts();

    final filtered = <ProductModel>[];
    for (final product in allProducts) {
      final vendor = _vendorFor(product.vendorID);
      if (vendor != null && (vendor.reststatus || vendor.isOpen())) {
        filtered.add(product);
      }
    }
    if (mounted) {
      setState(() {
        lstNearByFood = filtered;
        showLoader = false;
      });
    }
  }

  VendorModel? _vendorFor(String id) {
    try {
      return allstoreList.firstWhere((v) => v.id == id);
    } catch (_) {
      return null;
    }
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
            child: showLoader
                ? _buildShimmerList()
                : lstNearByFood.isEmpty
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
              Text(
                'Top Selling'.tr(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
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
            Icons.local_fire_department_rounded,
            size: 72,
            color: AppThemeData.primary500.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 16),
          Text(
            'No Top Selling Items',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppThemeData.grey600,
            ),
          ).tr(),
          const SizedBox(height: 6),
          Text(
            'Popular items from nearby restaurants will appear here',
            textAlign: TextAlign.center,
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
      itemCount: lstNearByFood.length,
      itemBuilder: (context, index) {
        final product = lstNearByFood[index];
        final vendor = _vendorFor(product.vendorID);
        if (vendor == null) return const SizedBox.shrink();
        return _buildProductCard(product, vendor);
      },
    );
  }

  Widget _buildProductCard(ProductModel product, VendorModel vendor) {
    final isDark = isDarkMode(context);
    final isOpen = vendor.reststatus || vendor.isOpen();
    return GestureDetector(
      onTap: () => push(context, NewVendorProductsScreen(vendorModel: vendor)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isDark ? AppThemeData.grey900 : AppThemeData.grey50,
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 32,
                offset: Offset(0, 0),
              ),
            ],
          ),
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: getImageVAlidUrl(product.photo),
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppThemeData.grey50
                                  : AppThemeData.grey900,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isOpen
                                ? Colors.green.withValues(alpha: 0.1)
                                : AppThemeData.grey200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isOpen ? 'Open'.tr() : 'Closed'.tr(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: isOpen
                                  ? Colors.green
                                  : AppThemeData.grey400,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      vendor.title,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? AppThemeData.grey400
                            : AppThemeData.grey500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    product.disPrice == "" || product.disPrice == "0"
                        ? Text(
                            amountShow(
                                amount:
                                    productCommissionPrice(product.price)),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppThemeData.primary500,
                            ),
                          )
                        : Row(
                            children: [
                              Text(
                                amountShow(
                                    amount: productCommissionPrice(
                                        product.disPrice.toString())),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppThemeData.primary500,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                amountShow(
                                    amount: productCommissionPrice(
                                        product.price)),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            ],
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
