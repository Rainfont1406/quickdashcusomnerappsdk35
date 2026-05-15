// ignore_for_file: must_be_immutable

import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/OrderModel.dart';
import 'package:emartconsumer/model/variant_info.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/cartScreen/CartScreen.dart';
import 'package:emartconsumer/ui/orderDetailsScreen/OrderDetailsScreen.dart';
import 'package:emartconsumer/ui/orderRatingScreen/OrderRatingScreen.dart';
import 'package:emartconsumer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/typography.dart';
import '../../constants/spacing.dart';

class OrdersScreen extends StatefulWidget {
  bool? isAnimation = true;

  OrdersScreen({super.key, this.isAnimation});

  @override
  _OrdersScreenState createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late Stream<List<OrderModel>> ordersFuture;
  final FireStoreUtils _fireStoreUtils = FireStoreUtils();
  List<OrderModel> ordersList = [];
  late CartDatabase cartDatabase;

  @override
  void initState() {
    super.initState();
    ordersFuture = _fireStoreUtils.getOrders(MyAppState.currentUser!.userID);
    print(MyAppState.currentUser!.userID);

    Future.delayed(const Duration(seconds: 7), () {
      setState(() {
        widget.isAnimation = false;
      });
    });
  }

  @override
  void didChangeDependencies() {
    cartDatabase = Provider.of<CartDatabase>(context, listen: false);
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    FireStoreUtils().closeOrdersStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeData.neutral50,
      body: widget.isAnimation == true
          ? Center(
              child: Image.asset(
                'assets/order_place_gif.gif',
              ),
            )
          : StreamBuilder<List<OrderModel>>(
              stream: ordersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator.adaptive(
                      valueColor: AlwaysStoppedAnimation(AppThemeData.primary500),
                    ),
                  );
                }
                if (!snapshot.hasData || (snapshot.data?.isEmpty ?? true)) {
                  return Center(
                    child: showEmptyState('No Previous Orders'.tr(), context),
                  );
                } else {
                  return ListView.builder(
                    itemCount: snapshot.data!.length,
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.spacing4,
                      vertical: AppSpacing.spacing4,
                    ),
                    itemBuilder: (context, index) =>
                        buildOrderItem(snapshot.data![index]),
                  );
                }
              }),
    );
  }

  Future<void> _handleReOrder(OrderModel orderModel) async {
    final products = await cartDatabase.allCartProducts;

    if (products.isNotEmpty) {
      final hasDifferentVendor =
          products.any((p) => p.vendorID != orderModel.vendorID);
      if (hasDifferentVendor) {
        final clear = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Text(
              'Replace Cart?'.tr(),
              style: AppTypography.h6.copyWith(
                  fontWeight: FontWeight.w700),
            ),
            content: Text(
              'Your cart has items from another restaurant. Re-ordering will clear your current cart.'
                  .tr(),
              style: AppTypography.bodyMedium,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel'.tr()),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'Clear & Re-Order'.tr(),
                  style: TextStyle(color: AppThemeData.primary500),
                ),
              ),
            ],
          ),
        );
        if (clear != true) return;
        await cartDatabase.deleteAllProducts();
      }
    }

    for (final product in orderModel.products) {
      await cartDatabase.reAddProduct(product);
    }

    if (!mounted) return;
    push(context, const CartScreen());
  }

  Future<void> _handleRate(OrderModel orderModel) async {
    push(context, OrderRatingScreen(orderModel: orderModel));
  }

  double _calculateOrderTotal(OrderModel orderModel) {
    double total = 0.0;
    for (var element in orderModel.products) {
      try {
        if (element.extras_price != null &&
            element.extras_price!.isNotEmpty &&
            double.parse(element.extras_price!) != 0.0) {
          total += element.quantity * double.parse(element.extras_price!);
        }
        total += element.quantity * double.parse(element.price);
      } catch (_) {}
    }

    num discount = orderModel.discount ?? 0.0;
    double tipValue =
        orderModel.tipValue == null || orderModel.tipValue!.isEmpty
            ? 0.0
            : double.parse(orderModel.tipValue!);
    double specialDiscountAmount = 0.0;
    if (orderModel.specialDiscount != null &&
        orderModel.specialDiscount!.isNotEmpty) {
      specialDiscountAmount = double.parse(
          orderModel.specialDiscount!['special_discount'].toString());
    }

    double totalTaxAmount = 0.0;
    if (orderModel.taxModel != null) {
      for (var element in orderModel.taxModel!) {
        bool shouldApplyTax = (orderModel.takeAway == false &&
                (element.isTakeaway == false || element.isTakeaway == null)) ||
            (orderModel.takeAway == true && element.isTakeaway == true);
        if (shouldApplyTax) {
          double taxAmount = getTaxValue(
            amount: (total - discount - specialDiscountAmount).toString(),
            taxModel: element,
          );
          totalTaxAmount += taxAmount;
        }
      }
    }

    double deliveryCharge =
        orderModel.deliveryCharge == null || orderModel.deliveryCharge!.isEmpty
            ? 0.0
            : double.parse(orderModel.deliveryCharge!);

    return deliveryCharge +
        total +
        totalTaxAmount +
        tipValue -
        discount -
        specialDiscountAmount;
  }

  Color _statusColor(String status) {
    if (status == ORDER_STATUS_COMPLETED) return AppThemeData.success500;
    if (status == ORDER_STATUS_CANCELLED ||
        status == ORDER_STATUS_REJECTED) return AppThemeData.error500;
    if (status == ORDER_STATUS_PLACED ||
        status == ORDER_STATUS_ACCEPTED ||
        status == ORDER_STATUS_DRIVER_PENDING ||
        status == ORDER_STATUS_DRIVER_ACCEPTED ||
        status == ORDER_STATUS_SHIPPED ||
        status == ORDER_STATUS_IN_TRANSIT ||
        status == ORDER_STATUS_ONGOING ||
        status == ORDER_STATUS_ASSIGNED) return AppThemeData.warning500;
    return AppThemeData.primary500;
  }

  Color _statusBgColor(String status) {
    if (status == ORDER_STATUS_COMPLETED)
      return AppThemeData.success500.withValues(alpha: 0.10);
    if (status == ORDER_STATUS_CANCELLED || status == ORDER_STATUS_REJECTED)
      return AppThemeData.error500.withValues(alpha: 0.10);
    if (status == ORDER_STATUS_PLACED ||
        status == ORDER_STATUS_ACCEPTED ||
        status == ORDER_STATUS_DRIVER_PENDING ||
        status == ORDER_STATUS_DRIVER_ACCEPTED ||
        status == ORDER_STATUS_SHIPPED ||
        status == ORDER_STATUS_IN_TRANSIT ||
        status == ORDER_STATUS_ONGOING ||
        status == ORDER_STATUS_ASSIGNED)
      return AppThemeData.warning500.withValues(alpha: 0.10);
    return AppThemeData.primary500.withValues(alpha: 0.10);
  }

  bool _isCompleted(String status) {
    return status == ORDER_STATUS_COMPLETED;
  }

  Widget buildOrderItem(OrderModel orderModel) {
    final double orderTotal = _calculateOrderTotal(orderModel);
    final statusColor = _statusColor(orderModel.status);
    final statusBg = _statusBgColor(orderModel.status);
    final bool completed = _isCompleted(orderModel.status);
    final String restaurantName = orderModel.vendor.title;
    final String restaurantPhoto =
        orderModel.vendor.photo.isNotEmpty ? orderModel.vendor.photo : placeholderImage;
    final String locationText = orderModel.address?.address?.toString() ?? '';
    final String dateTime = DateFormat('dd MMM yyyy · hh:mm a').format(
        DateTime.fromMillisecondsSinceEpoch(
            orderModel.createdAt.millisecondsSinceEpoch));

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.spacing4),
      decoration: BoxDecoration(
        color: isDarkMode(context) ? AppThemeData.neutral900 : AppThemeData.neutral0,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Tappable zone → Order Details ──────────────────────────────
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => push(context, OrderDetailsScreen(orderModel: orderModel)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top: info left, image right
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Status badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusBg,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: statusColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    orderModel.status.tr(),
                                    style: AppTypography.labelSmall.copyWith(
                                      color: statusColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              restaurantName,
                              style: AppTypography.h6.copyWith(
                                color: isDarkMode(context)
                                    ? AppThemeData.neutral50
                                    : AppThemeData.neutral900,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (locationText.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.location_on_rounded,
                                      size: 13, color: AppThemeData.neutral500),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: Text(
                                      locationText,
                                      style: AppTypography.bodySmall.copyWith(
                                          color: AppThemeData.neutral500),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Restaurant image (right)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          restaurantPhoto,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 80,
                            height: 80,
                            color: AppThemeData.neutral100,
                            child: Icon(Icons.store_rounded,
                                color: AppThemeData.neutral400, size: 32),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Divider
                Divider(
                  height: 1,
                  thickness: 1,
                  color: isDarkMode(context)
                      ? AppThemeData.neutral800
                      : AppThemeData.neutral100,
                ),

                // Order items with add-ons
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: orderModel.products.map((product) {
                      // Parse add-ons
                      List<String> addonList = [];
                      final dynamic rawExtras = product.extras;
                      if (rawExtras is List) {
                        addonList = rawExtras
                            .map((e) => e.toString().replaceAll('"', '').trim())
                            .where((s) => s.isNotEmpty && s != 'null' && s != '[]')
                            .toList();
                      } else if (rawExtras is String &&
                          rawExtras.isNotEmpty &&
                          rawExtras != '[]') {
                        final cleaned = rawExtras
                            .replaceAll('[', '')
                            .replaceAll(']', '')
                            .replaceAll('"', '');
                        addonList = cleaned
                            .split(',')
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .toList();
                      }

                      // Parse variant info
                      VariantInfo? variantInfo;
                      final dynamic rawVariant = product.variant_info;
                      if (rawVariant is VariantInfo) {
                        variantInfo = rawVariant;
                      } else if (rawVariant is Map<String, dynamic>) {
                        variantInfo = VariantInfo.fromJson(rawVariant);
                      } else if (rawVariant is String &&
                          rawVariant.isNotEmpty &&
                          rawVariant != 'null') {
                        try {
                          variantInfo =
                              VariantInfo.fromJson(jsonDecode(rawVariant));
                        } catch (_) {}
                      }
                      final List<MapEntry<String, dynamic>> variantEntries =
                          (variantInfo?.variant_options?.isNotEmpty ?? false)
                              ? variantInfo!.variant_options!.entries.toList()
                              : [];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: AppThemeData.primary500
                                        .withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${product.quantity}',
                                      style: AppTypography.labelSmall.copyWith(
                                        color: AppThemeData.primary500,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('×',
                                    style: AppTypography.bodySmall.copyWith(
                                        color: AppThemeData.neutral400)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    product.name,
                                    style: AppTypography.bodyMedium.copyWith(
                                      color: isDarkMode(context)
                                          ? AppThemeData.neutral100
                                          : AppThemeData.neutral800,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            // Customization — variants + add-ons in one line
                            Builder(builder: (context) {
                              final List<String> customParts = [
                                ...variantEntries.map((e) => '${e.key}: ${e.value}'),
                                ...addonList,
                              ];
                              if (customParts.isEmpty) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 3, left: 38),
                                child: Text(
                                  customParts.join(' · '),
                                  style: AppTypography.caption.copyWith(
                                    color: AppThemeData.neutral500,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // Date & Total row
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded,
                              size: 13, color: AppThemeData.neutral500),
                          const SizedBox(width: 4),
                          Text(
                            dateTime,
                            style: AppTypography.caption
                                .copyWith(color: AppThemeData.neutral500),
                          ),
                        ],
                      ),
                      Text(
                        amountShow(amount: orderTotal.toString()),
                        style: AppTypography.labelLarge.copyWith(
                          color: AppThemeData.primary500,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Action buttons (isolated from card tap) ─────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                // Re-Order
                Expanded(
                  child: _ActionButton(
                    label: 'Re-Order'.tr(),
                    icon: Icons.replay_rounded,
                    color: AppThemeData.primary500,
                    filled: true,
                    onTap: () => _handleReOrder(orderModel),
                  ),
                ),
                // Rate — only visible once Completed / Delivered
                if (completed) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionButton(
                      label: 'Rate'.tr(),
                      icon: Icons.star_rounded,
                      color: AppThemeData.warning500,
                      filled: false,
                      onTap: () => _handleRate(orderModel),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                // View Menu
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => push(
                    context,
                    NewVendorProductsScreen(vendorModel: orderModel.vendor),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'View Menu'.tr(),
                        style: AppTypography.labelSmall.copyWith(
                          color: AppThemeData.primary500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.arrow_forward_ios_rounded,
                          size: 11, color: AppThemeData.primary500),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? getPrice(OrderModel product, CartProduct cartProduct) {
    double subTotal;
    var price = cartProduct.extras_price == "" ||
            cartProduct.extras_price == null ||
            cartProduct.extras_price == "0.0"
        ? 0.0
        : cartProduct.extras_price;
    var tipValue = product.tipValue.toString() == "" || product.tipValue == null
        ? 0.0
        : product.tipValue.toString();
    var dCharge = product.deliveryCharge == null ||
            product.deliveryCharge.toString().isEmpty
        ? 0.0
        : double.parse(product.deliveryCharge.toString());
    var dis = product.discount.toString() == "" || product.discount == null
        ? 0.0
        : product.discount.toString();

    subTotal = double.parse(price.toString()) +
        double.parse(tipValue.toString()) +
        double.parse(dCharge.toString()) -
        double.parse(dis.toString());

    return subTotal.toString();
  }

  String? getPriceTotal(String price, int quantity) {
    double ans = double.parse(price) * double.parse(quantity.toString());
    return ans.toString();
  }

  getPriceTotalText(CartProduct s) {
    double total = 0.0;

    if (s.extras_price != null &&
        s.extras_price!.isNotEmpty &&
        double.parse(s.extras_price!) != 0.0) {
      total += s.quantity * double.parse(s.extras_price!);
    }
    total += s.quantity * double.parse(s.price);

    return Text(
      amountShow(amount: total.toString()),
      style: AppTypography.h6.copyWith(
        color: AppThemeData.primary500,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool filled;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.filled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool disabled = onTap == null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 38,
        decoration: BoxDecoration(
          color: filled
              ? (disabled ? AppThemeData.neutral200 : color)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: filled
              ? null
              : Border.all(
                  color: disabled ? AppThemeData.neutral300 : color,
                  width: 1.5,
                ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: filled
                  ? Colors.white
                  : (disabled ? AppThemeData.neutral400 : color),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: filled
                    ? Colors.white
                    : (disabled ? AppThemeData.neutral400 : color),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
