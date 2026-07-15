import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/OrderModel.dart';
import 'package:emartconsumer/send_notification.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/app_dialog.dart';
import 'package:emartconsumer/services/device_session_service.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/services/notification_service.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/ui/cartScreen/CartScreen.dart';
import 'package:flutter/material.dart';

/// Read-only approval screen for a Bill Pay request the VENDOR built and
/// sent to this customer. The customer can only Accept & Pay or Decline —
/// items are locked from the moment the vendor sent the request.
class BillPayRequestScreen extends StatefulWidget {
  final String orderId;

  const BillPayRequestScreen({Key? key, required this.orderId})
      : super(key: key);

  @override
  State<BillPayRequestScreen> createState() => _BillPayRequestScreenState();
}

class _BillPayRequestScreenState extends State<BillPayRequestScreen> {
  final FireStoreUtils _fireStoreUtils = FireStoreUtils();
  Timer? _tickTimer;
  bool _expiryWriteAttempted = false;
  bool _isResponding = false;

  @override
  void initState() {
    super.initState();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  int _computeRemaining(OrderModel order) {
    if (order.billPayExpiresAt == null) return 0;
    final diff =
        order.billPayExpiresAt!.toDate().difference(DateTime.now()).inSeconds;
    return diff.clamp(0, 1 << 30);
  }

  double _calculateTotal(OrderModel order) {
    double total = 0.0;
    for (final item in order.products) {
      try {
        if (item.extras_price != null &&
            item.extras_price!.isNotEmpty &&
            double.parse(item.extras_price!) != 0.0) {
          total += item.quantity * double.parse(item.extras_price!);
        }
        total += item.quantity * double.parse(item.price);
      } catch (_) {}
    }

    final num discount = order.discount ?? 0.0;
    double specialDiscountAmount = 0.0;
    if (order.specialDiscount != null && order.specialDiscount!.isNotEmpty) {
      try {
        specialDiscountAmount = double.parse(
            order.specialDiscount!['special_discount'].toString());
      } catch (_) {}
    }

    double totalTaxAmount = 0.0;
    if (order.taxModel != null) {
      // Bill Pay is a Dineaway flow (no delivery address) — only taxes
      // tagged isTakeaway == true apply, same as Takeaway/Dining elsewhere.
      // taxModel stores the FULL tax config; delivery-only charges (e.g.
      // "cart charge") must be filtered out here, not at write time.
      for (final tax in order.taxModel!.where((t) => t.isTakeaway == true)) {
        totalTaxAmount += getTaxValue(
          amount: (total - discount - specialDiscountAmount).toString(),
          taxModel: tax,
        );
      }
    }

    final double tipValue = (order.tipValue == null || order.tipValue!.isEmpty)
        ? 0.0
        : double.parse(order.tipValue!);
    final double deliveryCharge =
        (order.deliveryCharge == null || order.deliveryCharge!.isEmpty)
            ? 0.0
            : double.parse(order.deliveryCharge!);

    return deliveryCharge +
        total +
        totalTaxAmount +
        tipValue -
        discount -
        specialDiscountAmount;
  }

  Future<void> _notifyVendorOfDecline(OrderModel order) async {
    try {
      final vendorId = order.vendor.id;
      if (vendorId.isEmpty) return;
      final doc =
          await FireStoreUtils.firestore.collection(VENDORS).doc(vendorId).get();
      final liveToken = (doc.data()?['fcmToken'] as String?) ?? '';
      if (liveToken.isEmpty) return;
      final payload = <String, dynamic>{
        'type': 'customer_bill_pay_response',
        'orderId': order.id,
        'action': 'declined',
      };
      await SendNotification.sendFcmMessage(
        billPayRequestDeclined,
        liveToken,
        payload,
      );
    } catch (_) {}
  }

  Future<void> _decline(OrderModel order) async {
    final confirmed = await AppDialog.showConfirm(
      context,
      title: 'Decline this bill?'.tr(),
      message:
          'The vendor will be notified that you declined this request.'.tr(),
      confirmLabel: 'Decline'.tr(),
      cancelLabel: 'Cancel'.tr(),
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isResponding = true);
    try {
      await _fireStoreUtils.declineBillPayRequest(order.id);
      await _notifyVendorOfDecline(order);
      if (mounted) {
        ShowToastDialog.showToast('Request declined.'.tr());
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ShowToastDialog.showToast('Something went wrong. Please try again.'.tr());
      }
    } finally {
      if (mounted) setState(() => _isResponding = false);
    }
  }

  // Accept & Pay no longer writes the vendor's original request doc at all —
  // it hands the exact bill to a locked CartScreen, which pays through the
  // app's completely normal order-creation flow (see CartScreen's Bill Pay
  // mode). A Cloud Function reconciles this original request afterward.
  //
  // This tap is the trusted-verification moment for Bill Pay: it claims
  // device ownership (see DeviceSessionService.claim) rather than just
  // passively checking it, so this device becomes the account's active one
  // and any other device gets force-logged-out — but only once the user has
  // actually committed to paying, not just from opening this screen.
  Future<void> _acceptAndPay(OrderModel order) async {
    setState(() => _isResponding = true);
    try {
      final fcmToken = await NotificationService.getToken();
      final result = await DeviceSessionService.claim(fcmToken: fcmToken);
      if (!result.allowed) {
        if (mounted) {
          ShowToastDialog.showToast(result.message!);
          pushAndRemoveUntil(context, const LoginScreen());
        }
        return;
      }
      if (!mounted) return;
      push(
        context,
        CartScreen(billPayRequestModel: order),
      );
    } catch (_) {
      if (mounted) {
        ShowToastDialog.showToast('Something went wrong. Please try again.'.tr());
      }
    } finally {
      if (mounted) setState(() => _isResponding = false);
    }
  }

  Widget _buildItemRow(CartProduct item, bool dark) {
    // Numeric comparison, not string — discountPrice here is a Dart
    // double.toString() (e.g. "0.0"), which never equals the literal
    // string '0'. A string check treats every item as having an active
    // ₹0 discount and hides the real price entirely.
    final double? parsedDis = double.tryParse(item.discountPrice ?? '');
    final hasDiscount = parsedDis != null &&
        parsedDis > 0 &&
        item.discountPrice != item.price;
    // Line price shown here must include the add-on total and quantity —
    // previously showed just the base unit price, so a product with an
    // add-on (or qty > 1) displayed a lower number here than what the
    // Total at the bottom actually charges for it.
    final double unitBase = hasDiscount ? parsedDis! : (double.tryParse(item.price) ?? 0.0);
    final double unitExtras = double.tryParse(item.extras_price ?? '') ?? 0.0;
    final double lineTotal = (unitBase + unitExtras) * item.quantity;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppThemeData.primary500.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${item.quantity}x',
              style: TextStyle(
                fontFamily: AppThemeData.semiBold,
                fontSize: 11,
                color: AppThemeData.primary500,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    fontFamily: AppThemeData.medium,
                    fontSize: 14,
                    color: dark ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
                if (item.variant_info?.variant_options != null &&
                    item.variant_info!.variant_options!.isNotEmpty)
                  Text(
                    item.variant_info!.variant_options!.values.join(', '),
                    style: TextStyle(
                      fontFamily: AppThemeData.regular,
                      fontSize: 12,
                      color: AppThemeData.neutral400,
                    ),
                  ),
                if (item.extras != null && (item.extras as List).isNotEmpty)
                  Text(
                    '+ ${(item.extras as List).join(', ')}',
                    style: TextStyle(
                      fontFamily: AppThemeData.regular,
                      fontSize: 12,
                      color: AppThemeData.neutral400,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            lineTotal.toStringAsFixed(2),
            style: TextStyle(
              fontFamily: AppThemeData.semiBold,
              fontSize: 14,
              color: dark ? Colors.white : const Color(0xFF1A1A2E),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    return Scaffold(
      backgroundColor: dark ? AppThemeData.darkBgSecondary : const Color(0xFFF2F3F8),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: dark ? AppThemeData.darkBgPrimary : Colors.white,
        title: Text(
          'Bill Pay Request'.tr(),
          style: TextStyle(
            fontFamily: AppThemeData.semiBold,
            fontSize: 18,
            color: dark ? Colors.white : const Color(0xFF1A1A2E),
          ),
        ),
      ),
      body: StreamBuilder<OrderModel?>(
        stream: _fireStoreUtils.getOrderByID(widget.orderId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          final order = snapshot.data!;
          final remaining = _computeRemaining(order);
          final bool isPending = order.status == BILLPAY_STATUS_PENDING_APPROVAL;
          final bool isExpiredByTime = isPending && remaining <= 0;

          if (isExpiredByTime && !_expiryWriteAttempted) {
            _expiryWriteAttempted = true;
            _fireStoreUtils
                .expireBillPayRequestIfPending(order.id)
                .catchError((_) {});
          }

          final bool canRespond = isPending && !isExpiredByTime;
          final mm = (remaining ~/ 60).toString().padLeft(2, '0');
          final ss = (remaining % 60).toString().padLeft(2, '0');

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Vendor card
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundImage: order.vendor.photo.isNotEmpty
                                ? NetworkImage(order.vendor.photo)
                                : null,
                            child: order.vendor.photo.isEmpty
                                ? const Icon(Icons.storefront_rounded)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  order.vendor.title,
                                  style: TextStyle(
                                    fontFamily: AppThemeData.semiBold,
                                    fontSize: 16,
                                    color: dark ? Colors.white : const Color(0xFF1A1A2E),
                                  ),
                                ),
                                Text(
                                  'sent you a bill to review'.tr(),
                                  style: TextStyle(
                                    fontFamily: AppThemeData.regular,
                                    fontSize: 12,
                                    color: AppThemeData.neutral400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Status / countdown banner
                      if (canRespond)
                        _banner(
                          icon: Icons.timer_rounded,
                          color: AppThemeData.warning500,
                          text: '${'Respond within'.tr()}  $mm:$ss',
                        )
                      else if (order.status == BILLPAY_STATUS_EXPIRED || isExpiredByTime)
                        _banner(
                          icon: Icons.hourglass_disabled_rounded,
                          color: AppThemeData.error500,
                          text: 'This request has expired.'.tr(),
                        )
                      else if (order.status == BILLPAY_STATUS_DECLINED)
                        _banner(
                          icon: Icons.cancel_rounded,
                          color: AppThemeData.error500,
                          text: 'You declined this request.'.tr(),
                        )
                      else if (order.status == BILLPAY_STATUS_CANCELLED)
                        _banner(
                          icon: Icons.block_rounded,
                          color: AppThemeData.error500,
                          text: 'The vendor cancelled this request.'.tr(),
                        )
                      else if (order.status == ORDER_STATUS_COMPLETED)
                        _banner(
                          icon: Icons.check_circle_rounded,
                          color: AppThemeData.success500,
                          text: 'Paid successfully.'.tr(),
                        ),

                      const SizedBox(height: 16),

                      // Items — read only, no edit affordances
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: dark ? AppThemeData.neutral900 : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Items'.tr(),
                              style: TextStyle(
                                fontFamily: AppThemeData.semiBold,
                                fontSize: 14,
                                color: dark ? Colors.white : const Color(0xFF1A1A2E),
                              ),
                            ),
                            const Divider(height: 20),
                            ...order.products.map((p) => _buildItemRow(p, dark)),
                            const Divider(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total'.tr(),
                                  style: TextStyle(
                                    fontFamily: AppThemeData.semiBold,
                                    fontSize: 15,
                                    color: dark ? Colors.white : const Color(0xFF1A1A2E),
                                  ),
                                ),
                                Text(
                                  _calculateTotal(order).toStringAsFixed(2),
                                  style: TextStyle(
                                    fontFamily: AppThemeData.semiBold,
                                    fontSize: 16,
                                    color: AppThemeData.primary500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (order.notes != null && order.notes!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          '${'Note'.tr()}: ${order.notes}',
                          style: TextStyle(
                            fontFamily: AppThemeData.regular,
                            fontSize: 12,
                            color: AppThemeData.neutral400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (canRespond)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isResponding ? null : () => _decline(order),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: AppThemeData.error500),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Decline'.tr(),
                              style: TextStyle(
                                color: AppThemeData.error500,
                                fontFamily: AppThemeData.semiBold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: _isResponding ? null : () => _acceptAndPay(order),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppThemeData.primary500,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Accept & Pay'.tr(),
                              style: TextStyle(
                                color: Colors.white,
                                fontFamily: AppThemeData.semiBold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _banner({required IconData icon, required Color color, required String text}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: AppThemeData.semiBold,
                fontSize: 13,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
