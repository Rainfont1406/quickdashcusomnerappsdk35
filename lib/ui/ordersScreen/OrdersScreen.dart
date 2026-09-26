// ignore_for_file: must_be_immutable

import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/OrderModel.dart';
import 'package:emartconsumer/model/variant_info.dart';
import 'package:emartconsumer/services/app_dialog.dart';
import 'package:emartconsumer/services/behavior/behavior_tracker.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/services/order_extras_parsing.dart';
import 'package:emartconsumer/services/shared_orders_watcher.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/utils/network_image_widget.dart';
import 'package:emartconsumer/ui/orderDetailsScreen/OrderDetailsScreen.dart';
import 'package:emartconsumer/ui/billPayRequest/BillPayRequestScreen.dart';
import 'package:emartconsumer/ui/orderRatingScreen/OrderRatingScreen.dart';
import 'package:emartconsumer/ui/cartScreen/CartScreen.dart';
import 'package:emartconsumer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/typography.dart';
import '../../constants/spacing.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  _OrdersScreenState createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late Stream<List<OrderModel>> ordersFuture;
  List<OrderModel> ordersList = [];
  late CartDatabase cartDatabase;

  @override
  void initState() {
    super.initState();
    // 2026-09-06: routed through the shared, session-scoped watcher instead
    // of FireStoreUtils.getOrders() - see SharedOrdersWatcher's own doc
    // comment for why (ContainerScreen's drawer reuses this screen's
    // Element/State across visits with no key, so a per-screen listener
    // opened here only ever ran once per app session; a customer's Orders
    // list could stay frozen on whatever it last saw, straight through
    // real new orders, for days). Deliberately no dispose() override
    // anymore - this listener is NOT screen-owned, so closing it just
    // because this particular screen instance closed would defeat the
    // point; it's torn down on logout instead (see main.dart).
    ordersFuture = SharedOrdersWatcher.watch(MyAppState.currentUser!.userID);
  }

  @override
  void didChangeDependencies() {
    cartDatabase = Provider.of<CartDatabase>(context, listen: false);
    super.didChangeDependencies();
  }

  Future<void> _startReOrder(
      BuildContext context, OrderModel orderModel) async {
    final existing = await cartDatabase.allCartProducts;

    if (existing.isNotEmpty &&
        existing.any((p) => p.vendorID != orderModel.vendorID)) {
      if (!context.mounted) return;
      final confirmed = await AppDialog.showConfirm(
        context,
        title: 'Replace Cart?'.tr(),
        message:
            'Your cart has items from another restaurant. Adding these items will clear your current cart.'
                .tr(),
        confirmLabel: 'Clear & Add'.tr(),
        cancelLabel: 'Cancel'.tr(),
        destructive: true,
      );
      if (!confirmed) return;
      await cartDatabase.deleteAllProducts();
    } else if (existing.isNotEmpty) {
      // Same vendor — clear for a fresh re-order
      await cartDatabase.deleteAllProducts();
    }

    if (!context.mounted) return;
    push(context, CartScreen(reOrderModel: orderModel));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeData.neutral50,
      body: ValueListenableBuilder<bool>(
        valueListenable: isDeliveryActiveNotifier,
        builder: (context, deliveryActive, _) {
          return StreamBuilder<List<OrderModel>>(
            stream: ordersFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                  child: CircularProgressIndicator.adaptive(
                    valueColor: AlwaysStoppedAnimation(AppThemeData.primary500),
                  ),
                );
              }
              final allOrders = snapshot.data ?? [];

              // Delivery is off: hide only genuine Delivery-type orders from
              // history (Dineaway/Takeaway order history stays visible).
              //
              // 2026-09-07 fix: the old check (`takeAway == false ||
              // takeAway == null`) was wrong - orderType is only ever set
              // for the Dineaway feature ("Takeaway" or "Dining"), and a
              // genuine Dining order also has takeAway == false (that field
              // only distinguishes Takeaway pickup from Dining eat-in
              // WITHIN Dineaway, it says nothing about Delivery vs Dineaway
              // on its own). A real Delivery order never sets orderType at
              // all, so that's the correct, unambiguous signal. Confirmed
              // live: with delivery_active currently false in production,
              // this bug hid every one of a real customer's last 8 Dining
              // orders from their own Orders screen, leaving only much
              // older genuine Takeaway orders visible.
              final visibleOrders = allOrders.where((order) {
                final bool isDeliveryOrder = order.orderType == null;
                return !(isDeliveryOrder && !deliveryActive);
              }).where((order) {
                // A Bill Pay request the vendor sent (initiatedBy=='vendor')
                // that gets accepted is NOT updated in place — Accept & Pay
                // creates a brand-new order doc via the normal checkout flow
                // (with the customer's own coupon/discount applied) linked
                // back via billPayRequestId, and a Cloud Function reconciles
                // the original request doc afterward. Both docs land in this
                // same stream, so without this filter the customer sees the
                // same bill twice — once at the pre-discount amount from
                // when the vendor sent it, once at the final paid amount.
                // Hide the original request once its paid twin exists; it
                // stays visible on its own (Pending/Declined/Expired/
                // Cancelled) whenever no such twin was ever created.
                if (order.initiatedBy != 'vendor') return true;
                final hasSupersedingOrder =
                    allOrders.any((o) => o.billPayRequestId == order.id);
                return !hasSupersedingOrder;
              }).toList();

              if (visibleOrders.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      showEmptyState('No Previous Orders'.tr(), context),
                      _buildShowOlder(),
                    ],
                  ),
                );
              } else {
                // 2026-09-26: + 1 footer row for "Show older orders" - older
                // finished orders are loaded on demand (see
                // SharedOrdersWatcher.loadOlder), not up front.
                return ListView.builder(
                  itemCount: visibleOrders.length + 1,
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.spacing4,
                    vertical: AppSpacing.spacing4,
                  ),
                  itemBuilder: (context, index) => index == visibleOrders.length
                      ? _buildShowOlder()
                      : buildOrderItem(visibleOrders[index]),
                );
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildShowOlder() {
    return ValueListenableBuilder<bool>(
      valueListenable: SharedOrdersWatcher.hasOlder,
      builder: (context, hasOlder, _) {
        if (!hasOlder) return const SizedBox(height: 8);
        return ValueListenableBuilder<bool>(
          valueListenable: SharedOrdersWatcher.loadingOlder,
          builder: (context, loading, _) => Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.spacing4),
            child: Center(
              child: loading
                  ? CircularProgressIndicator.adaptive(
                      valueColor: AlwaysStoppedAnimation(AppThemeData.primary500),
                    )
                  : TextButton.icon(
                      onPressed: SharedOrdersWatcher.loadOlder,
                      icon: Icon(Icons.history_rounded, color: AppThemeData.primary500),
                      label: Text(
                        'Show older orders'.tr(),
                        style: TextStyle(color: AppThemeData.primary500, fontWeight: FontWeight.w600),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleRate(OrderModel orderModel) async {
    push(context, OrderRatingScreen(orderModel: orderModel));
  }

  double _calculateOrderTotal(OrderModel orderModel) {
    // ── Pricing-verified path (2026-08-04) ──────────────────────────────
    // order.pricing is the immutable, server-verified snapshot written by
    // verifyOrderOnCreate a few seconds after order creation. Use its total
    // directly when present so this row can never disagree with Order
    // Details for the same order. Absent on pre-existing orders and briefly
    // absent right after a brand-new order is created (before the trigger
    // has run) — fall through to the original recompute below, unchanged.
    final pricing = orderModel.pricing;
    if (pricing != null && pricing['total'] != null) {
      final dynamic totalVal = pricing['total'];
      return totalVal is num
          ? totalVal.toDouble()
          : double.tryParse(totalVal.toString()) ?? 0.0;
    }

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
      // isTakeaway on a tax entry means "applies to any Dineaway order" -
      // Dining, Takeaway, AND Bill Pay all collapse into this one bucket
      // (confirmed 2026-08-31 against BillPayRequestScreen.dart's own
      // untouched, original comment: "Bill Pay is a Dineaway flow... only
      // taxes tagged isTakeaway == true apply, same as Takeaway/Dining
      // elsewhere") - isTakeaway==false/absent is exclusively real Delivery.
      // A prior same-night fix here had this backwards (routed Dining into
      // the false/Delivery bucket) before that reference file was found -
      // takeAway alone can't detect Dining/Bill Pay (narrowed to mean only
      // genuine Takeaway by the 2026-08-26 fix, for an unrelated
      // Vendor-App-button-gating reason), so orderType is needed too.
      final bool isDineaway = (orderModel.takeAway ?? false) ||
          ((orderModel.orderType ?? '').isNotEmpty);
      for (var element in orderModel.taxModel!) {
        bool shouldApplyTax = isDineaway
            ? element.isTakeaway == true
            : (element.isTakeaway == false || element.isTakeaway == null);
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
    if (status == ORDER_STATUS_CANCELLED || status == ORDER_STATUS_REJECTED)
      return AppThemeData.error500;
    if (status == BILLPAY_STATUS_DECLINED ||
        status == BILLPAY_STATUS_EXPIRED ||
        status == BILLPAY_STATUS_CANCELLED) return AppThemeData.error500;
    if (status == BILLPAY_STATUS_PENDING_APPROVAL)
      return AppThemeData.warning500;
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
    if (status == BILLPAY_STATUS_DECLINED ||
        status == BILLPAY_STATUS_EXPIRED ||
        status == BILLPAY_STATUS_CANCELLED)
      return AppThemeData.error500.withValues(alpha: 0.10);
    if (status == BILLPAY_STATUS_PENDING_APPROVAL)
      return AppThemeData.warning500.withValues(alpha: 0.10);
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

  Widget _buildCustomChip(String label, {bool isVariant = false}) {
    final dark = isDarkMode(context);
    final bgColor = isVariant
        ? AppThemeData.primary500.withValues(alpha: dark ? 0.18 : 0.10)
        : (dark ? AppThemeData.neutral800 : AppThemeData.neutral100);
    final borderColor = isVariant
        ? AppThemeData.primary500.withValues(alpha: dark ? 0.40 : 0.30)
        : (dark ? AppThemeData.neutral700 : AppThemeData.neutral200);
    final textColor = isVariant
        ? AppThemeData.primary500
        : (dark ? AppThemeData.neutral300 : AppThemeData.neutral600);
    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 0.6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          color: textColor,
        ),
        // Rendering-level safety net (2026-09-09), independent of whatever
        // upstream parsing already filtered - a chip is never meant to hold
        // more than a short label, so this caps the blast radius of any
        // future data-quality surprise this specific screen hasn't been
        // taught to recognize yet.
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget buildOrderItem(OrderModel orderModel) {
    final double orderTotal = _calculateOrderTotal(orderModel);
    final statusColor = _statusColor(orderModel.status);
    final statusBg = _statusBgColor(orderModel.status);
    final bool completed = _isCompleted(orderModel.status);
    // A vendor-sent Bill Pay request that never actually got paid (still
    // Pending Approval, or Declined/Expired/Cancelled) has no real
    // transaction behind it - nothing was purchased, so "Re-Order"/"View
    // Menu" here would be misleading (found 2026-08-23: an Expired request
    // showed these same action buttons as a normal completed order). Once
    // a Bill Pay request is actually paid it becomes a real order with
    // status ORDER_STATUS_COMPLETED (same as `completed` above), so this
    // only suppresses the still-unresolved cases.
    final bool isUnpaidVendorBillPay =
        orderModel.initiatedBy == 'vendor' && !completed;
    final String restaurantName = orderModel.vendor.title;
    final String restaurantPhoto = orderModel.vendor.photo.isNotEmpty
        ? orderModel.vendor.photo
        : placeholderImage;
    final String locationText = orderModel.address?.address?.toString() ?? '';
    final String dateTime = DateFormat('dd MMM yyyy · hh:mm a').format(
        DateTime.fromMillisecondsSinceEpoch(
            orderModel.createdAt.millisecondsSinceEpoch));

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.spacing4),
      decoration: BoxDecoration(
        color: isDarkMode(context)
            ? AppThemeData.neutral900
            : AppThemeData.neutral0,
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
            onTap: () => (orderModel.initiatedBy == 'vendor' &&
                    orderModel.status == BILLPAY_STATUS_PENDING_APPROVAL)
                ? push(context, BillPayRequestScreen(orderId: orderModel.id))
                : push(context, OrderDetailsScreen(orderModel: orderModel)),
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
                      // Parse add-ons (shared, defensive parser - see
                      // order_extras_parsing.dart for why this used to be
                      // inline here without backslash-stripping, unlike its
                      // two siblings in OrderDetailsScreen.dart)
                      final List<String> addonList = parseOrderExtras(product.extras);

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
                            // Customization chips — variants + add-ons
                            if (variantEntries.isNotEmpty ||
                                addonList.isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 4, left: 38),
                                child: Wrap(
                                  spacing: 5,
                                  runSpacing: 4,
                                  children: [
                                    ...variantEntries
                                        .map((e) => _buildCustomChip(
                                              e.value.toString(),
                                              isVariant: true,
                                            )),
                                    ...addonList
                                        .map((e) => _buildCustomChip(e)),
                                  ],
                                ),
                              ),
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
          // Suppressed entirely for an unpaid vendor Bill Pay request - see
          // isUnpaidVendorBillPay above.
          if (!isUnpaidVendorBillPay)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  // Re-Order — premium gradient button
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _startReOrder(context, orderModel),
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              AppThemeData.primary500,
                              AppThemeData.primary600,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: AppThemeData.primary500
                                  .withValues(alpha: 0.32),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.replay_rounded,
                                color: Colors.white, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'Re-Order'.tr(),
                              style: const TextStyle(
                                fontFamily: AppThemeData.semiBold,
                                fontSize: 13,
                                color: Colors.white,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                    onTap: () {
                      BehaviorTracker.setNextEntrySource('Reorder');
                      precacheVendorHeroImage(context, orderModel.vendor);
                      push(
                        context,
                        NewVendorProductsScreen(vendorModel: orderModel.vendor),
                      );
                    },
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
