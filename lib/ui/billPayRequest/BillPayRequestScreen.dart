import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/OrderModel.dart';
import 'package:emartconsumer/send_notification.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/app_dialog.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/cartScreen/CartScreen.dart';
import 'package:emartconsumer/widget/savings_banner.dart';
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

  // Deliberately does NOT read order.pricing (2026-08-04 pricing-snapshot
  // rollout), unlike OrderDetailsScreen/OrdersScreen. This screen shows the
  // VENDOR'S ORIGINAL PENDING REQUEST document (see OrderModel's doc comment
  // on initiatedBy/billPayExpiresAt/billPayRespondedAt), and that document
  // can be edited in place by the vendor after creation (isVendorEditingBillPay
  // in firestore.rules lets a vendor rewrite products/discount/taxSetting on
  // the SAME doc, refreshing billPayExpiresAt). verifyOrderOnCreate is an
  // onDocumentCreated trigger — it runs exactly once, at the request's
  // original creation, before any such edit — so any order.pricing snapshot
  // on this doc would reflect the ORIGINAL submitted bill, not a later
  // vendor edit, and could show the customer a stale total to approve.
  // The brand-new order Accept & Pay creates (a separate document, linked
  // via billPayRequestId) gets its own fresh, trustworthy pricing snapshot
  // and is displayed via OrderDetailsScreen/OrdersScreen instead — not here.
  // Recomputing live from this doc's current raw fields (as below) is
  // therefore the correct behavior for this screen, not a fallback.
  //
  // Returns every line that goes into the total (subtotal, discounts, each
  // tax, tip) rather than just the final number — the items list alone
  // doesn't add up to the total shown (discount/tax/tip make up the gap),
  // and showing the total with no explanation reads as the platform quietly
  // charging something extra. The full breakdown is what CartScreen already
  // shows before payment; Bill Pay approval should show the same.
  //
  // Steps mirror CartScreen._modernSummarySection's exact order (subtotal ->
  // +delivery/tip base -> -discount -> -special discount -> +tax computed on
  // the discounted base), just reading from the vendor's locked doc fields
  // instead of live cart/coupon state — see the class doc-comment above for
  // why this screen deliberately doesn't re-derive discounts live the way
  // the cart does. There's no combined-discount-cap step here: that cap only
  // exists to referee a customer's live coupon pick against a stacked
  // special discount, and there's no coupon on this locked, vendor-set bill.
  _BillBreakdown _computeBreakdown(OrderModel order) {
    // 1. Subtotal — sum of item price (+ extras) * quantity.
    double subtotal = 0.0;
    for (final item in order.products) {
      try {
        if (item.extras_price != null &&
            item.extras_price!.isNotEmpty &&
            double.parse(item.extras_price!) != 0.0) {
          subtotal += item.quantity * double.parse(item.extras_price!);
        }
        subtotal += item.quantity * double.parse(item.price);
      } catch (_) {}
    }

    final double tipValue = (order.tipValue == null || order.tipValue!.isEmpty)
        ? 0.0
        : double.parse(order.tipValue!);
    final double deliveryCharge =
        (order.deliveryCharge == null || order.deliveryCharge!.isEmpty)
            ? 0.0
            : double.parse(order.deliveryCharge!);

    // 2. Base total before any discount or tax — items + delivery + tip.
    double runningTotal = subtotal + deliveryCharge + tipValue;

    // 3. Discount (the vendor's equivalent of a coupon on this bill).
    final double discount = (order.discount ?? 0.0).toDouble();
    runningTotal -= discount;

    // 4. Special discount — already evaluated and fixed on the doc by the
    // vendor, not re-run against a live day/timeslot schedule here.
    double specialDiscountAmount = 0.0;
    if (order.specialDiscount != null && order.specialDiscount!.isNotEmpty) {
      try {
        specialDiscountAmount = double.parse(
            order.specialDiscount!['special_discount'].toString());
      } catch (_) {}
    }
    runningTotal -= specialDiscountAmount;

    // 5. Tax, computed on the discounted subtotal (clamped so a discount
    // larger than the subtotal never produces negative tax), then added on
    // top — same as CartScreen's taxBase/totalTaxAmount step.
    final double taxBase =
        (subtotal - discount - specialDiscountAmount).clamp(0.0, double.infinity);
    final taxes = <BillTaxLine>[];
    if (order.taxModel != null) {
      // Bill Pay is a Dineaway flow (no delivery address) — only taxes
      // tagged isTakeaway == true apply, same as Takeaway/Dining elsewhere.
      // taxModel stores the FULL tax config; delivery-only charges (e.g.
      // "cart charge") must be filtered out here, not at write time.
      for (final tax in order.taxModel!.where((t) => t.isTakeaway == true)) {
        final amount = getTaxValue(amount: taxBase.toString(), taxModel: tax);
        if (amount > 0) {
          taxes.add(BillTaxLine(title: tax.title ?? 'Tax'.tr(), amount: amount));
        }
      }
    }
    final double totalTaxAmount = taxes.fold(0.0, (sum, t) => sum + t.amount);
    runningTotal += totalTaxAmount;

    return _BillBreakdown(
      subtotal: subtotal,
      discount: discount,
      specialDiscount: specialDiscountAmount,
      taxes: taxes,
      tipValue: tipValue,
      total: runningTotal.clamp(0.0, double.infinity),
    );
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
  // (2026-08-11) No standalone device-session check here anymore — it was a
  // full extra HTTP round trip re-checking the exact same thing
  // createVerifiedOrderPayment/createVerifiedWalletOrder already re-verify
  // server-side one step later, inside PaymentScreen (see their
  // 'device_superseded' handling in _handleVerifiedPaymentFailure). That
  // server-side check is the actual binding gate — it runs immediately
  // before the Razorpay order is created / wallet is debited, so a
  // superseded device can never get a charge created regardless of whether
  // this tap re-checked first. Same removal already applied to the regular
  // Delivery/Takeaway place-order flow on 2026-08-03 (see
  // CheckoutScreen._placeOrder's identical comment) — this was the one
  // remaining flow still doing it twice.
  Future<void> _acceptAndPay(OrderModel order) async {
    setState(() => _isResponding = true);
    try {
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

  Widget _billBreakdownRow(String label, double amount, bool dark,
      {Color? valueColor}) {
    final negative = amount < 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: AppThemeData.regular,
              fontSize: 13,
              color: dark ? AppThemeData.neutral400 : AppThemeData.neutral500,
            ),
          ),
          Text(
            '${negative ? '-' : ''}${amountShow(amount: amount.abs().toStringAsFixed(2))}',
            style: TextStyle(
              fontFamily: AppThemeData.medium,
              fontSize: 13,
              color: valueColor ??
                  (dark ? Colors.white : const Color(0xFF1A1A2E)),
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
        // Explicit iconTheme — Styles.dart's global light-mode AppBarTheme
        // hardcodes iconTheme to Colors.white (every other screen uses a
        // colored primary app bar, where that's correct). Flutter resolves
        // AppBar.iconTheme from the WIDGET first, then the THEME, so without
        // this the global white theme silently wins, rendering the back
        // button white-on-white on this screen's white app bar.
        iconTheme: IconThemeData(color: dark ? Colors.white : const Color(0xFF1A1A2E)),
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
                            // Bill breakdown — the items above sum to
                            // `subtotal`, not `total`; without these rows the
                            // customer sees a Total that doesn't match what
                            // the items add up to, with no explanation.
                            Builder(builder: (context) {
                              final b = _computeBreakdown(order);
                              return Column(
                                children: [
                                  _billBreakdownRow('Subtotal'.tr(),
                                      b.subtotal, dark),
                                  if (b.discount > 0)
                                    _billBreakdownRow('Discount'.tr(),
                                        -b.discount, dark,
                                        valueColor: AppThemeData.primary500),
                                  if (b.specialDiscount > 0)
                                    _billBreakdownRow('Special Discount'.tr(),
                                        -b.specialDiscount, dark,
                                        valueColor: AppThemeData.primary500),
                                  for (final tax in b.taxes)
                                    _billBreakdownRow(
                                        tax.title, tax.amount, dark),
                                  if (b.tipValue > 0)
                                    _billBreakdownRow('Tip amount'.tr(),
                                        b.tipValue, dark,
                                        valueColor: const Color(0xFFF59E0B)),
                                  const Divider(height: 20),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Total'.tr(),
                                        style: TextStyle(
                                          fontFamily: AppThemeData.semiBold,
                                          fontSize: 15,
                                          color: dark
                                              ? Colors.white
                                              : const Color(0xFF1A1A2E),
                                        ),
                                      ),
                                      Text(
                                        b.total.toStringAsFixed(2),
                                        style: TextStyle(
                                          fontFamily: AppThemeData.semiBold,
                                          fontSize: 16,
                                          color: AppThemeData.primary500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  // Same combined discount + special-discount
                                  // savings banner CartScreen shows before
                                  // payment — Bill Pay should read the same
                                  // way, not like a stripped-down screen.
                                  if (b.discount + b.specialDiscount > 0) ...[
                                    const Divider(height: 20),
                                    SavingsBanner(
                                      totalSavings:
                                          b.discount + b.specialDiscount,
                                      dark: dark,
                                    ),
                                  ],
                                ],
                              );
                            }),
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
                      // There's no coupon field on this review screen — it's
                      // read-only. Special discount (if any) is already
                      // computed into the breakdown above, same as it would
                      // auto-apply in the cart; a coupon, unlike special
                      // discount, is a manual pick and only offered one step
                      // later on the locked CartScreen Accept & Pay hands off
                      // to (see _isBillPayMode there) — say so here instead
                      // of leaving the customer wondering where to enter one.
                      if (canRespond) ...[
                        const SizedBox(height: 12),
                        _offerInfoNote(dark),
                      ],
                      // The bill is usually just a couple of items, leaving a
                      // lot of empty space above the Decline/Accept buttons —
                      // a small pulsing illustration keeps that gap from
                      // reading as a blank/broken screen while they decide.
                      if (canRespond) _waitingIllustration(dark),
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

  Widget _offerInfoNote(bool dark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: dark
            ? AppThemeData.primary500.withValues(alpha: 0.12)
            : AppThemeData.primary500.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppThemeData.primary500.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.local_offer_outlined, size: 16, color: AppThemeData.primary500),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Accept & Pay to apply a coupon and get your discounts.'.tr(),
              style: TextStyle(
                fontFamily: AppThemeData.regular,
                fontSize: 12,
                height: 1.4,
                color: dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _waitingIllustration(bool dark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const _PulsingWaitIcon(),
          const SizedBox(height: 16),
          Text(
            'Take your time to review before you decide'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppThemeData.regular,
              fontSize: 12,
              color: AppThemeData.neutral400,
            ),
          ),
        ],
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

class BillTaxLine {
  final String title;
  final double amount;

  const BillTaxLine({required this.title, required this.amount});
}

class _BillBreakdown {
  final double subtotal;
  final double discount;
  final double specialDiscount;
  final List<BillTaxLine> taxes;
  final double tipValue;
  final double total;

  const _BillBreakdown({
    required this.subtotal,
    required this.discount,
    required this.specialDiscount,
    required this.taxes,
    required this.tipValue,
    required this.total,
  });
}

// A receipt icon with a soft ring pinging outward and fading, on a loop —
// purely decorative, fills the vacant space while the customer is deciding.
class _PulsingWaitIcon extends StatefulWidget {
  const _PulsingWaitIcon();

  @override
  State<_PulsingWaitIcon> createState() => _PulsingWaitIconState();
}

class _PulsingWaitIconState extends State<_PulsingWaitIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      height: 88,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          final t = _controller.value;
          final ringScale = 0.55 + 0.45 * t;
          final ringOpacity = (1 - t).clamp(0.0, 1.0);
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: ringScale,
                child: Opacity(
                  opacity: ringOpacity * 0.35,
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppThemeData.primary500,
                    ),
                  ),
                ),
              ),
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppThemeData.primary500.withValues(alpha: 0.10),
                ),
                child: Icon(Icons.receipt_long_rounded,
                    color: AppThemeData.primary500, size: 28),
              ),
            ],
          );
        },
      ),
    );
  }
}
