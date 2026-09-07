import 'dart:developer';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/services/behavior/behavior_tracker.dart';
import 'package:emartconsumer/model/AddressModel.dart';
import 'package:emartconsumer/model/OrderModel.dart';
import 'package:emartconsumer/model/TaxModel.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/placeOrderScreen/PlaceOrderScreen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CheckoutScreen extends StatefulWidget {
  final String paymentOption, paymentType, id;
  final double total;
  final double? discount;
  final String? couponCode;
  final String? couponId, notes;
  final List<CartProduct> products;
  final List<String>? extra_addons;
  final String? extra_size;
  final String? tipValue;
  final bool? take_away;
  final String? deliveryCharge;
  final String? size;
  final bool isPaymentDone;
  final List<TaxModel>? taxModel;
  final Map<String, dynamic>? specialDiscountMap;
  final Timestamp? scheduleTime;
  final AddressModel? address;
  final String? orderType; // "Takeaway" | "Dining" | "Bill Pay" — null for delivery
  // Links a Bill Pay accept order back to the original vendor request doc
  // for Cloud Function reconciliation — see PaymentScreen.billPayRequestId.
  final String? billPayRequestId;
  // Set only by the wallet payment flow (2026-08-06): the order was already
  // created atomically, server-side, in the SAME Firestore transaction as
  // the wallet deduction (see createVerifiedWalletOrder in
  // paymentIntents.js) - it already exists by the time this screen opens.
  // When set, _placeOrder() must NOT attempt to write the order document
  // again: vendor_orders' security rules only allow a customer to change
  // `status`/`billPayRespondedAt` on an existing order, so a full rewrite
  // is correctly rejected as permission-denied. Only the remaining client
  // side-effects (stock decrement, confirmation UI) still need to run.
  final OrderModel? alreadyPlacedOrder;

  const CheckoutScreen({
    Key? key,
    required this.id,
    required this.isPaymentDone,
    required this.paymentOption,
    required this.paymentType,
    required this.total,
    this.discount,
    this.couponCode,
    this.couponId,
    this.notes,
    required this.products,
    this.extra_addons,
    this.extra_size,
    this.tipValue,
    this.take_away,
    this.deliveryCharge,
    this.taxModel,
    this.specialDiscountMap,
    this.size,
    this.scheduleTime,
    this.address,
    this.orderType,
    this.billPayRequestId,
    this.alreadyPlacedOrder,
  }) : super(key: key);

  @override
  _CheckoutScreenState createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _fireStoreUtils = FireStoreUtils();
  bool _isPlacingOrder = false;

  // ── Derived values ──────────────────────────────────────────────────────────

  double _itemLineTotal(CartProduct p) {
    final base = double.tryParse(p.price) ?? 0.0;
    final extras = double.tryParse(p.extras_price ?? '0') ?? 0.0;
    return (base + extras) * p.quantity;
  }

  double get _subTotal =>
      widget.products.fold(0.0, (sum, p) => sum + _itemLineTotal(p));

  double get _deliveryCharge =>
      double.tryParse(widget.deliveryCharge ?? '0') ?? 0.0;

  double get _tip => double.tryParse(widget.tipValue ?? '0') ?? 0.0;

  double get _discount => widget.discount ?? 0.0;

  double get _totalTax {
    if (widget.taxModel == null) return 0.0;
    return widget.taxModel!.fold(0.0, (sum, t) {
      if (t.type == 'percentage') {
        return sum + (_subTotal * (double.tryParse(t.tax ?? '0') ?? 0.0) / 100);
      }
      return sum + (double.tryParse(t.tax ?? '0') ?? 0.0);
    });
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    if (widget.isPaymentDone) {
      // Payment already collected — validate address then place order
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // 2026-09-07 fix: was `widget.take_away ?? false`, which is only
        // true for genuine Takeaway pickup - false for both Delivery AND
        // Dining, so this required a delivery address for Dining orders
        // too. widget.orderType is null only for genuine Delivery (see
        // ORDER_TYPE_NAMING_AUDIT_2026-09-07.html).
        final bool isDeliveryOrder = widget.orderType == null;
        if (isDeliveryOrder && widget.address == null) {
          if (mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
              content: Text('Delivery address is missing. Cannot place order.'.tr()),
              backgroundColor: AppThemeData.error500,
              behavior: SnackBarBehavior.floating,
            ));
          }
          return;
        }
        if (mounted) setState(() => _isPlacingOrder = true);
        await _placeOrder();
      });
    }
  }

  // ── UI helpers ──────────────────────────────────────────────────────────────

  // Order-type pill helpers — aware of Dining / Bill Pay sub-types.
  //
  // 2026-09-07 fix: these took a bool param that every call site filled
  // with `widget.take_away ?? false` (narrow: true only for genuine
  // Takeaway, false for both Delivery AND Dining) and gated on `if
  // (!isTakeaway) return <delivery thing>` BEFORE the switch below ever
  // ran - so the "aware of Dining / Bill Pay" switch was unreachable dead
  // code for those two cases, and every Dine-In checkout showed a
  // "Delivery Order" pill. No parameter needed at all: widget.orderType
  // alone (null only for genuine Delivery) is the correct, complete signal
  // - see ORDER_TYPE_NAMING_AUDIT_2026-09-07.html.
  Color _pillColor() {
    if (widget.orderType == null) return AppThemeData.primary500; // delivery
    switch (widget.orderType) {
      case 'Dining':
        return Colors.purple;
      case 'Bill Pay':
        return Colors.orange;
      default:
        return AppThemeData.info500; // Takeaway
    }
  }

  IconData _pillIcon() {
    if (widget.orderType == null) return Icons.delivery_dining_rounded;
    switch (widget.orderType) {
      case 'Dining':
        return Icons.restaurant_rounded;
      case 'Bill Pay':
        return Icons.receipt_long_rounded;
      default:
        return Icons.shopping_bag_outlined; // Takeaway
    }
  }

  String _pillLabel() {
    if (widget.orderType == null) return 'Delivery Order'.tr();
    switch (widget.orderType) {
      case 'Dining':
        return 'Dine-In Order'.tr();
      case 'Bill Pay':
        return 'Bill Pay'.tr();
      default:
        return 'Takeaway Order'.tr();
    }
  }

  IconData _paymentIcon(String type) {
    switch (type.toLowerCase()) {
      case 'wallet':
        return Icons.account_balance_wallet_rounded;
      case 'cod':
        return Icons.money_rounded;
      case 'stripe':
        return Icons.credit_card_rounded;
      case 'razorpay':
      case 'paystack':
      case 'paypal':
      case 'flutterwave':
      case 'payfast':
      case 'mercadopago':
      case 'xendit':
      case 'midtrans':
      case 'orangepay':
        return Icons.payment_rounded;
      default:
        return Icons.payments_rounded;
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool dark = isDarkMode(context);
    // 2026-09-07 fix: was `widget.take_away ?? false` (narrow: true only
    // for genuine Takeaway, false for both Delivery AND Dining), used below
    // to decide whether to show the "Delivering to [address]" card - which
    // meant a Dine-In checkout would show it too whenever widget.address
    // happened to be non-null (e.g. a returning customer's saved address
    // riding along regardless of order type). orderType == null is the
    // correct, complete "is this genuinely a Delivery order" signal - see
    // ORDER_TYPE_NAMING_AUDIT_2026-09-07.html.
    final bool isDeliveryOrder = widget.orderType == null;

    return Scaffold(
      backgroundColor: dark ? AppThemeData.surfaceDark : AppThemeData.grey100,
      appBar: AppBar(
        backgroundColor: dark ? AppThemeData.darkBgPrimary : Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: dark ? Colors.white : Colors.black,
          ),
        ),
        title: Text(
          'Order Summary'.tr(),
          style: TextStyle(
            fontSize: 17,
            fontFamily: AppThemeData.semiBold,
            color: dark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              children: [
                // ── Payment verified banner (online payments only) ───────────
                if (widget.paymentType != 'cod') ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.verified_rounded,
                              color: Colors.green.shade700, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Payment Successful'.tr(),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontFamily: AppThemeData.semiBold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Your payment is verified. Review your order and place it.'
                                    .tr(),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green.shade600,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // ── Order type pill ──────────────────────────────────────────
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: _pillColor().withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                        _pillIcon(),
                        size: 14,
                        color: _pillColor(),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _pillLabel(),
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: AppThemeData.semiBold,
                          color: _pillColor(),
                        ),
                      ),
                    ]),
                  ),
                ),

                // ── Items ────────────────────────────────────────────────────
                _SectionCard(
                  dark: dark,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionHeader(
                        label: 'Items'.tr(),
                        icon: Icons.restaurant_menu_rounded,
                        dark: dark,
                      ),
                      ...widget.products.map((p) => _ItemRow(
                            product: p,
                            dark: dark,
                            lineTotal: _itemLineTotal(p),
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── Delivery address ─────────────────────────────────────────
                if (isDeliveryOrder && widget.address != null)
                  _SectionCard(
                    dark: dark,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppThemeData.primary500.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.location_on_rounded,
                                color: AppThemeData.primary500, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Delivering to'.tr(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontFamily: AppThemeData.semiBold,
                                    color: dark
                                        ? AppThemeData.grey400
                                        : AppThemeData.grey500,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.address!.getFullAddress(),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color:
                                        dark ? Colors.white : Colors.black87,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (isDeliveryOrder && widget.address != null)
                  const SizedBox(height: 12),

                // ── Schedule ─────────────────────────────────────────────────
                if (widget.scheduleTime != null)
                  _SectionCard(
                    dark: dark,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppThemeData.warning400.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.schedule_rounded,
                              color: AppThemeData.warning400, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Scheduled for'.tr(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: AppThemeData.semiBold,
                                  color: dark
                                      ? AppThemeData.grey400
                                      : AppThemeData.grey500,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat("EEE, d MMM 'at' hh:mm a")
                                    .format(widget.scheduleTime!.toDate()),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: dark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
                if (widget.scheduleTime != null) const SizedBox(height: 12),

                // ── Price breakdown ──────────────────────────────────────────
                _SectionCard(
                  dark: dark,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      _SectionHeader(
                        label: 'Price Breakdown'.tr(),
                        icon: Icons.receipt_long_rounded,
                        dark: dark,
                      ),
                      const SizedBox(height: 4),
                      _PriceRow(
                        label: 'Subtotal'.tr(),
                        value: amountShow(amount: _subTotal.toStringAsFixed(2)),
                        dark: dark,
                      ),
                      if (_deliveryCharge > 0)
                        _PriceRow(
                          label: 'Delivery'.tr(),
                          value: amountShow(
                              amount: _deliveryCharge.toStringAsFixed(2)),
                          dark: dark,
                        ),
                      if (_tip > 0)
                        _PriceRow(
                          label: 'Tip'.tr(),
                          value:
                              amountShow(amount: _tip.toStringAsFixed(2)),
                          dark: dark,
                        ),
                      if (_totalTax > 0)
                        _PriceRow(
                          label: 'Tax'.tr(),
                          value: amountShow(
                              amount: _totalTax.toStringAsFixed(2)),
                          dark: dark,
                        ),
                      if (_discount > 0)
                        _PriceRow(
                          label: (widget.couponCode != null &&
                                  widget.couponCode!.isNotEmpty)
                              ? 'Coupon (${widget.couponCode})'.tr()
                              : 'Discount'.tr(),
                          value:
                              '- ${amountShow(amount: _discount.toStringAsFixed(2))}',
                          valueColor: AppThemeData.accent500,
                          dark: dark,
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Divider(
                          color: dark
                              ? AppThemeData.darkBorderPrimary
                              : AppThemeData.grey200,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total'.tr(),
                            style: TextStyle(
                              fontSize: 16,
                              fontFamily: AppThemeData.semiBold,
                              color: dark ? Colors.white : Colors.black,
                            ),
                          ),
                          Text(
                            amountShow(amount: widget.total.toStringAsFixed(2)),
                            style: TextStyle(
                              fontSize: 18,
                              fontFamily: AppThemeData.semiBold,
                              color: AppThemeData.primary500,
                            ),
                          ),
                        ],
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Payment method ───────────────────────────────────────────
                _SectionCard(
                  dark: dark,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppThemeData.primary500.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _paymentIcon(widget.paymentType),
                          color: AppThemeData.primary500,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Payment Method'.tr(),
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: AppThemeData.semiBold,
                                color: dark
                                    ? AppThemeData.grey400
                                    : AppThemeData.grey500,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.paymentOption,
                              style: TextStyle(
                                fontSize: 14,
                                fontFamily: AppThemeData.medium,
                                color: dark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.isPaymentDone)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.check_circle_outline_rounded,
                                size: 12, color: Color(0xFF2E7D32)),
                            const SizedBox(width: 4),
                            Text(
                              'Paid'.tr(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontFamily: AppThemeData.semiBold,
                                color: Color(0xFF2E7D32),
                              ),
                            ),
                          ]),
                        ),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Notes ────────────────────────────────────────────────────
                if (widget.notes != null && widget.notes!.trim().isNotEmpty)
                  _SectionCard(
                    dark: dark,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.note_outlined,
                              color: AppThemeData.grey400, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Order Notes'.tr(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontFamily: AppThemeData.semiBold,
                                    color: dark
                                        ? AppThemeData.grey400
                                        : AppThemeData.grey500,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.notes!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: dark
                                        ? Colors.white70
                                        : Colors.black87,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 16),
              ],
            ),
          ),

          // ── CTA ─────────────────────────────────────────────────────────────
          _buildCTA(dark),
        ],
      ),
    );
  }

  // Returns true if the order can proceed, false if it should be blocked.
  Future<bool> _validateAndConfirmDelivery() async {
    // 2026-09-07 fix: was `widget.take_away ?? false`, which is only true
    // for genuine Takeaway - false for both Delivery AND Dining, so this
    // function would fall through and require a delivery address for
    // Dining orders too (blocking checkout with "Please add a delivery
    // address to continue." for any dine-in customer with no address on
    // file). orderType == null is the correct "is this genuinely a
    // Delivery order" signal - see ORDER_TYPE_NAMING_AUDIT_2026-09-07.html.
    final bool isDeliveryOrder = widget.orderType == null;
    if (!isDeliveryOrder) return true; // Dineaway (Dining/Takeaway/Bill Pay) needs no delivery address

    // ── Case 1: address is null ──────────────────────────────────────────────
    if (widget.address == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
          content: Text('Please add a delivery address to continue.'.tr()),
          backgroundColor: AppThemeData.error500,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return false;
    }

    // ── Case 2: confirm the location with the user ───────────────────────────
    final bool dark = isDarkMode(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: dark ? AppThemeData.darkBgSecondary : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.location_on_rounded,
                color: AppThemeData.primary500, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Confirm Delivery Location'.tr(),
                style: TextStyle(
                  fontSize: 16,
                  fontFamily: AppThemeData.semiBold,
                  color: dark ? Colors.white : Colors.black,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your order will be delivered to:'.tr(),
              style: TextStyle(
                fontSize: 13,
                color: dark ? AppThemeData.grey400 : AppThemeData.grey500,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: dark
                    ? AppThemeData.darkBgTertiary
                    : AppThemeData.grey100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: dark
                      ? AppThemeData.darkBorderPrimary
                      : AppThemeData.grey200,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.pin_drop_rounded,
                      size: 16, color: AppThemeData.primary500),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.address!.getFullAddress(),
                      style: TextStyle(
                        fontSize: 14,
                        color: dark ? Colors.white : Colors.black87,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Is this the correct delivery address?'.tr(),
              style: TextStyle(
                fontSize: 13,
                color: dark ? AppThemeData.grey400 : AppThemeData.grey600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Change Address'.tr(),
              style: TextStyle(
                color: dark ? AppThemeData.grey400 : AppThemeData.grey600,
                fontFamily: AppThemeData.medium,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppThemeData.primary500,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: Text(
              'Confirm'.tr(),
              style: const TextStyle(
                color: Colors.white,
                fontFamily: AppThemeData.semiBold,
              ),
            ),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Widget _buildCTA(bool dark) {
    final bool canPress = !_isPlacingOrder;

    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgPrimary : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(dark ? 0.3 : 0.07),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: canPress
              ? () async {
                  if (!await _validateAndConfirmDelivery()) return;
                  setState(() => _isPlacingOrder = true);
                  await _placeOrder();
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppThemeData.primary500,
            disabledBackgroundColor: AppThemeData.grey300,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: _isPlacingOrder
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Placing Order...'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontFamily: AppThemeData.semiBold,
                      ),
                    ),
                  ],
                )
              : Text(
                  widget.paymentType == 'cod'
                      ? 'Confirm & Place Order'.tr()
                      : 'Place Order'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontFamily: AppThemeData.semiBold,
                    letterSpacing: 0.2,
                  ),
                ),
        ),
      ),
    );
  }

  // ── Business logic ───────────────────────────────────────────────────────────

  Future<void> _setPrefData() async {
    final sp = await SharedPreferences.getInstance();
    sp.setString('musics_key', '');
    sp.setString('addsize', '');
  }

  Future<void> _placeOrder() async {
    if (widget.products.isEmpty) return;

    // Wallet path (2026-08-06): the order already exists, created
    // atomically with the wallet deduction - see alreadyPlacedOrder's own
    // doc comment. Only the remaining side-effect (stock decrement) and
    // the confirmation UI still need to happen; skip everything else
    // (vendor re-fetch, service gates, and above all the Firestore write,
    // which would now be rejected as permission-denied).
    final alreadyPlaced = widget.alreadyPlacedOrder;
    if (alreadyPlaced != null) {
      await showProgress('Please wait...'.tr(), false);
      await Future.wait(alreadyPlaced.products.map((cartProduct) =>
          FireStoreUtils.decrementProductStock(
            productId: cartProduct.id.split('~').first,
            quantity: cartProduct.quantity,
            variantId: cartProduct.variant_info != null
                ? cartProduct.id.split('~').last
                : null,
          )));
      await hideProgress();
      if (!mounted) return;
      showModalBottomSheet(
        isScrollControlled: true,
        isDismissible: false,
        context: context,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (context) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: PlaceOrderScreen(
            orderModel: alreadyPlaced,
            isPaymentVerified: true,
          ),
        ),
      );
      return;
    }

    // TEMPORARY [ORDER-PERF] - timing instrumentation for the loading-speed
    // investigation. Remove once done.
    final placeOrderSw = Stopwatch()..start();
    debugPrint('[ORDER-PERF] CheckoutScreen._placeOrder START');
    // (2026-08-03) No standalone enforceActive() call here anymore - it was
    // a full extra HTTP round trip checking the exact same thing that
    // createVerifiedOrderPayment/createVerifiedWalletOrder/
    // createVerifiedCodOrder already re-verify server-side, one step later
    // in this same flow (see their 'device_superseded' handling in
    // rozorpayConroller.dart / _handleVerifiedPaymentFailure). Removing the
    // duplicate shortens the critical path instead of lengthening it, since
    // the two calls ran sequentially, never in parallel.

    final List<CartProduct> tempProducts = List.from(widget.products);

    await showProgress('Please wait...'.tr(), false);

    try {
      final VendorModel vendorModel = await _fireStoreUtils
          .getVendorByVendorID(tempProducts.first.vendorID)
          .whenComplete(() => _setPrefData());

      // ── Live service-type gate ───────────────────────────────────────────
      final bool _isTakeawayOrder = widget.take_away ?? false;
      String? _serviceBlockReason;

      if (!_isTakeawayOrder) {
        // Layer 0 — section-wide admin gate (the Delivery on/off toggle).
        // isDeliveryActiveNotifier is kept live by ContainerScreen's
        // Firestore listener for the whole session, so this reflects the
        // current state even if the toggle changed after this screen
        // was already open — this is the backstop catching any browsing
        // path that reached checkout despite the view-level gates.
        if (!isDeliveryActiveNotifier.value) {
          _serviceBlockReason = deliveryOffMessageNotifier.value.trim().isNotEmpty
              ? deliveryOffMessageNotifier.value
              : "We're not delivering right now. Please check back soon!".tr();
        // Layer 1 — admin gate
        } else if (!vendorModel.deliveryEnabled) {
          _serviceBlockReason = 'Delivery is not available at this restaurant.'.tr();
        // Layer 2 — vendor pause
        } else if (!vendorModel.vendorDeliveryOpen) {
          _serviceBlockReason = 'This restaurant has temporarily paused delivery orders.'.tr();
        }
      } else {
        // Layer 1 — admin gate (top-level dineaway)
        if (!vendorModel.dineAwayEnabled) {
          _serviceBlockReason = 'Dine-away service is not available at this restaurant.'.tr();
        // Layer 1 — admin gate (sub-type)
        } else if (widget.orderType == 'Takeaway' && !vendorModel.takeawayEnabled) {
          _serviceBlockReason = 'Takeaway service is not available at this restaurant.'.tr();
        } else if (widget.orderType == 'Dining' && !vendorModel.diningEnabled) {
          _serviceBlockReason = 'Dining service is not available at this restaurant.'.tr();
        // Layer 2 — vendor pause
        } else if (!vendorModel.vendorDineawayOpen) {
          _serviceBlockReason = 'This restaurant has temporarily paused dine-away orders.'.tr();
        }
      }

      if (_serviceBlockReason != null) {
        await hideProgress();
        if (mounted) {
          setState(() => _isPlacingOrder = false);
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
            content: Text(_serviceBlockReason!),
            backgroundColor: AppThemeData.error500,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 4),
          ));
        }
        return;
      }
      // ────────────────────────────────────────────────────────────────────

      // Combo Purchase Learning (2026-07-24) - only non-null for line
      // items whose catalog product was flagged isCombo at add-to-cart
      // time (see BehaviorTracker.rememberComboMetadata). Zero extra reads:
      // this is a lookup into an in-memory/persisted cache, never a
      // catalog re-fetch. Empty list for an order with no combo items -
      // the common case.
      final comboLineItems = tempProducts
          .map((item) {
            final combo =
                BehaviorTracker.comboMetadataFor(item.id.split('~').first);
            if (combo == null) return null;
            return <String, dynamic>{
              'productId': item.id.split('~').first,
              'quantity': item.quantity,
              'price': combo.price,
              'comboProductIds': combo.comboProductIds,
              'comboCategoryIds': combo.comboCategoryIds,
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList();

      // Purchase-analytics snapshot (2026-07-22) - identical shape/purpose
      // to PaymentScreen's own copy; see that file's doc comment.
      // Deliberately duplicated rather than shared via a helper on the
      // OrderModel/screen boundary - both screens build this from
      // different local state (tempProducts vs tempProduc, widget.total
      // vs widget.total, etc.), and PurchaseCompletionListener is the
      // actual single source of truth for what happens with it, which is
      // what "avoid duplicating analytics logic" was about, not the
      // handful of fields feeding into the snapshot itself.
      final analyticsSnapshot = <String, dynamic>{
        'categoryIds': tempProducts.map((item) => item.category_id ?? '').where((c) => c.isNotEmpty).toSet().toList(),
        'cuisineIds': vendorModel.cuisineIds,
        'restaurantId': tempProducts.first.vendorID,
        'businessTypeId': vendorModel.businessTypeId,
        'productIds': tempProducts.map((item) => item.id.split('~').first).toSet().toList(),
        'totalAmount': widget.total,
        'orderMode': widget.orderType ?? (widget.take_away == true ? 'Takeaway' : 'Delivery'),
        'paymentMethod': widget.paymentType,
        'couponCode': widget.couponCode ?? '',
        'hasSpecialDiscount': widget.specialDiscountMap != null,
        // Captured NOW, while still fresh - see
        // BehaviorTracker.recentSearchQueryFor's own doc comment for why
        // this can't be re-derived later, at completion time.
        'reachedViaSearchQuery': BehaviorTracker.recentSearchQueryFor(tempProducts.first.vendorID) ?? '',
        // Restaurant Engagement / Banner Analytics linkage (Phase 2,
        // 2026-07-24, collection-only) - same "capture now, read later"
        // reasoning as reachedViaSearchQuery above: restaurantSessionId
        // lets PurchaseCompletionListener attribute order COMPLETION back
        // to the exact browsing session that led here (order PLACEMENT
        // attribution already happens synchronously via
        // FirebaseHelper.placeOrder); reachedViaBannerId lets it credit a
        // banner's ordersGenerated/revenueGenerated the same way
        // reachedViaSearchQuery credits a search.
        'restaurantSessionId': BehaviorTracker
                .recentRestaurantSessionFor(tempProducts.first.vendorID)
                ?.sessionId ??
            '',
        // Search-conversion funnel (collection-only, additive field) -
        // carried through to PurchaseCompletionListener's order_completed
        // payload, read by _computeSummaryUpdates to bump
        // behavior_summary.searchConversion.ordered when this order
        // originated from a Search/Cuisine-attributed restaurant visit.
        'entrySource': BehaviorTracker
                .recentRestaurantSessionFor(tempProducts.first.vendorID)
                ?.entrySource ??
            '',
        'reachedViaBannerId': BehaviorTracker.recentBannerClickId() ?? '',
        'comboLineItems': comboLineItems,
      };

      final OrderModel orderModel = OrderModel(
        id: widget.id,
        address: widget.address,
        author: MyAppState.currentUser,
        authorID: MyAppState.currentUser?.userID ?? '',
        createdAt: Timestamp.now(),
        products: tempProducts,
        status: widget.orderType == 'Bill Pay'
            ? ORDER_STATUS_COMPLETED
            : ORDER_STATUS_PLACED,
        vendor: vendorModel,
        vendorID: tempProducts.first.vendorID,
        discount: widget.discount,
        couponCode: widget.couponCode,
        couponId: widget.couponId,
        notes: widget.notes,
        payment_method: widget.paymentType,
        tipValue: widget.tipValue,
        sectionId: sectionConstantModel?.id ?? '',
        adminCommission: (widget.take_away ?? false)
            ? (sectionConstantModel?.adminCommision?.takeawayCommission ?? 0).toString()
            : (sectionConstantModel?.adminCommision?.commission ?? 0).toString(),
        adminCommissionType: sectionConstantModel?.adminCommision?.type,
        taxModel: widget.taxModel,
        takeAway: widget.take_away,
        orderType: widget.orderType,
        deliveryCharge: widget.deliveryCharge,
        specialDiscount: widget.specialDiscountMap,
        scheduleTime: widget.scheduleTime,
        billPayRequestId: widget.billPayRequestId,
        analyticsSnapshot: analyticsSnapshot,
      );

      final writeOrderSw = Stopwatch()..start();
      final OrderModel placedOrder =
          await _fireStoreUtils.placeOrder(orderModel);
      debugPrint('[ORDER-PERF] FireStoreUtils.placeOrder (Firestore write) — '
          '${writeOrderSw.elapsedMilliseconds}ms (TOTAL so far ${placeOrderSw.elapsedMilliseconds}ms)');

      // Decrement product stock — best-effort, never fails the order.
      // Atomic per-product transaction (FirebaseHelper.decrementProductStock)
      // instead of a plain read-then-overwrite - see that method's doc
      // comment for why the old pattern could silently lose a decrement
      // under concurrent orders.
      await Future.wait(tempProducts.map((cartProduct) =>
          FireStoreUtils.decrementProductStock(
            productId: cartProduct.id.split('~').first,
            quantity: cartProduct.quantity,
            variantId: cartProduct.variant_info != null
                ? cartProduct.id.split('~').last
                : null,
          )));

      await hideProgress();

      if (!mounted) return;

      showModalBottomSheet(
        isScrollControlled: true,
        isDismissible: false,
        context: context,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (context) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: PlaceOrderScreen(
            orderModel: placedOrder,
            isPaymentVerified: widget.paymentType != 'cod',
          ),
        ),
      );
    } catch (e, s) {
      await hideProgress();
      if (mounted) {
        setState(() => _isPlacingOrder = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
          content: Text('Failed to place order. Please try again.'.tr()),
          backgroundColor: AppThemeData.error500,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 4),
        ));
      }
      // TEMPORARY [ORDER-PERF] - stack trace added (2026-08-06) while
      // investigating the same intermittent post-payment failure on the
      // takeaway path (see PaymentScreen.dart's placeOrder()). Remove once
      // root cause is confirmed.
      debugPrint('[ORDER-BUILD] CheckoutScreen._placeOrder error: $e\n$s');
    }
  }
}

// ── Private subwidgets ─────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final Widget child;
  final bool dark;

  const _SectionCard({required this.child, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgSecondary : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: dark
            ? [
                BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ]
            : [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 3))
              ],
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool dark;

  const _SectionHeader(
      {required this.label, required this.icon, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(children: [
        Icon(icon, size: 16, color: AppThemeData.primary500),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontFamily: AppThemeData.semiBold,
            color: dark ? AppThemeData.grey400 : AppThemeData.grey500,
            letterSpacing: 0.4,
          ),
        ),
      ]),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final CartProduct product;
  final bool dark;
  final double lineTotal;

  const _ItemRow(
      {required this.product, required this.dark, required this.lineTotal});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: getImageVAlidUrl(product.photo),
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                color: dark ? AppThemeData.darkBgTertiary : AppThemeData.grey100,
              ),
              errorWidget: (_, __, ___) => Container(
                color: dark ? AppThemeData.darkBgTertiary : AppThemeData.grey100,
                child: Icon(Icons.fastfood_rounded,
                    size: 20, color: AppThemeData.grey400),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: AppThemeData.medium,
                    color: dark ? Colors.white : Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if ((product.extras ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      product.extras!,
                      style: TextStyle(
                        fontSize: 11,
                        color: dark ? AppThemeData.grey400 : AppThemeData.grey500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'x${product.quantity}',
                style: TextStyle(
                  fontSize: 12,
                  color: dark ? AppThemeData.grey400 : AppThemeData.grey500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                amountShow(amount: lineTotal.toStringAsFixed(2)),
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: AppThemeData.semiBold,
                  color: dark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final String value;
  final bool dark;
  final Color? valueColor;

  const _PriceRow({
    required this.label,
    required this.value,
    required this.dark,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: dark ? AppThemeData.grey300 : AppThemeData.grey600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontFamily: AppThemeData.medium,
              color: valueColor ??
                  (dark ? Colors.white70 : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
