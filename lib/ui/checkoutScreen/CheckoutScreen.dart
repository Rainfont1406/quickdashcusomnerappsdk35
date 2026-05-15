import 'dart:developer';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/AddressModel.dart';
import 'package:emartconsumer/model/OrderModel.dart';
import 'package:emartconsumer/model/ProductModel.dart';
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
      // Payment already collected — place order immediately
      setState(() => _isPlacingOrder = true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _placeOrder());
    }
  }

  // ── UI helpers ──────────────────────────────────────────────────────────────

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
    final bool isTakeaway = widget.take_away ?? false;

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
                // ── Order type pill ──────────────────────────────────────────
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isTakeaway
                          ? AppThemeData.info500.withOpacity(0.1)
                          : AppThemeData.primary500.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                        isTakeaway
                            ? Icons.shopping_bag_outlined
                            : Icons.delivery_dining_rounded,
                        size: 14,
                        color: isTakeaway
                            ? AppThemeData.info500
                            : AppThemeData.primary500,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isTakeaway ? 'Takeaway Order'.tr() : 'Delivery Order'.tr(),
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: AppThemeData.semiBold,
                          color: isTakeaway
                              ? AppThemeData.info500
                              : AppThemeData.primary500,
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
                if (!isTakeaway && widget.address != null)
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
                if (!isTakeaway && widget.address != null)
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
                                DateFormat("EEEE, MMM d 'at' hh:mm a")
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
                          valueColor: const Color(0xFF2E7D32),
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

  Widget _buildCTA(bool dark) {
    final bool canPress = !widget.isPaymentDone && !_isPlacingOrder;

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
                  widget.isPaymentDone
                      ? 'Confirming Order...'.tr()
                      : 'Confirm & Place Order'.tr(),
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

    final List<CartProduct> tempProducts = List.from(widget.products);

    await showProgress('Please wait...'.tr(), false);

    final VendorModel vendorModel = await _fireStoreUtils
        .getVendorByVendorID(tempProducts.first.vendorID)
        .whenComplete(() => _setPrefData());

    final OrderModel orderModel = OrderModel(
      id: widget.id,
      address: widget.address,
      author: MyAppState.currentUser,
      authorID: MyAppState.currentUser!.userID,
      createdAt: Timestamp.now(),
      products: tempProducts,
      status: ORDER_STATUS_PLACED,
      vendor: vendorModel,
      vendorID: tempProducts.first.vendorID,
      discount: widget.discount,
      couponCode: widget.couponCode,
      couponId: widget.couponId,
      notes: widget.notes,
      payment_method: widget.paymentType,
      tipValue: widget.tipValue,
      sectionId: sectionConstantModel!.id,
      adminCommission: (widget.take_away ?? false)
          ? sectionConstantModel!.adminCommision!.takeawayCommission.toString()
          : sectionConstantModel!.adminCommision!.commission.toString(),
      adminCommissionType: sectionConstantModel!.adminCommision!.type,
      taxModel: widget.taxModel,
      takeAway: widget.take_away,
      deliveryCharge: widget.deliveryCharge,
      specialDiscount: widget.specialDiscountMap,
      scheduleTime: widget.scheduleTime,
    );

    final OrderModel placedOrder =
        await _fireStoreUtils.placeOrder(orderModel);

    // Decrement product stock
    for (final cartProduct in tempProducts) {
      await FireStoreUtils()
          .getProductByID(cartProduct.id.split('~').first)
          .then((value) async {
        final ProductModel productModel = value;
        if (cartProduct.variant_info != null) {
          for (int j = 0;
              j < (productModel.itemAttributes?.variants?.length ?? 0);
              j++) {
            if (productModel.itemAttributes!.variants![j].variant_id ==
                cartProduct.id.split('~').last) {
              if (productModel.itemAttributes!.variants![j].variant_quantity !=
                  '-1') {
                productModel.itemAttributes!.variants![j].variant_quantity =
                    (int.parse(productModel
                                .itemAttributes!
                                .variants![j]
                                .variant_quantity
                                .toString()) -
                            cartProduct.quantity)
                        .toString();
              }
            }
          }
        } else {
          if (productModel.quantity != -1) {
            productModel.quantity =
                productModel.quantity - cartProduct.quantity;
          }
        }
        await FireStoreUtils.updateProduct(productModel);
      });
    }

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
        child: PlaceOrderScreen(orderModel: placedOrder),
      ),
    );
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
