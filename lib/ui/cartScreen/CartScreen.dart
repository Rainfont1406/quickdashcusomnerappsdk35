import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/AddressModel.dart';
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/model/TaxModel.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/model/offer_model.dart';
import 'package:emartconsumer/model/variant_info.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/deliveryAddressScreen/DeliveryAddressScreen.dart';

import 'package:emartconsumer/ui/productDetailsScreen/ProductDetailsScreen.dart';
import 'package:emartconsumer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/typography.dart';
import '../../model/DeliveryChargeModel.dart';
import '../payment/PaymentScreen.dart';
import 'package:emartconsumer/model/ItemAttributes.dart';

class CartScreen extends StatefulWidget {
  final bool fromStoreSelection;

  const CartScreen({Key? key, this.fromStoreSelection = false})
      : super(key: key);

  @override
  _CartScreenState createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  late Future<List<CartProduct>> cartFuture;
  late List<CartProduct> cartProducts = [];
  TextEditingController noteController = TextEditingController(text: '');

  double subTotal = 0.0;
  late CartDatabase cartDatabase;
  double grandtotal = 0.0;
  var per = 0.0;
  late Future<List<OfferModel>> coupon;
  TextEditingController txt = TextEditingController(text: '');
  final FireStoreUtils _fireStoreUtils = FireStoreUtils();
  var percentage, type = 0.0;
  var amount = 0.00;
  late String couponId = '';
  String vendorID = "";
  late List<AddAddonsDemo> lstExtras = [];
  late List<String> commaSepratedAddOns = [];
  String? commaSepratedAddOnsString = "";
  bool? deliverExec = false;
  var deliveryCharges = "0.0";
  VendorModel? vendorModel;
  String? selctedOrderTypeValue = "Delivery".tr();
  bool isDeliverFound = false;
  var tipValue = 0.0;

  // Dineaway section variables
  String? selectedDineawayType; // "Takeaway" or "Dining"
  bool isDineawaySelected = false;
  bool isTipSelected = false,
      isTipSelected1 = false,
      isTipSelected2 = false,
      isTipSelected3 = false;
  final TextEditingController _textFieldController = TextEditingController();

  double specialDiscount = 0.0;
  double specialDiscountAmount = 0.0;
  String specialType = "";

  Timestamp? scheduleTime;
  bool specialDiscountEnable = false;
  bool _isBillExpanded = false;
  AddressModel addressModel = AddressModel();

  List<TaxModel>? taxList = []; // Initialize as empty list

  // Stable stream reference — must not change between rebuilds to prevent scroll resets
  Stream<List<CartProduct>>? _cartStream;

  // Performance optimization: Cache product models
  final Map<String, ProductModel> _productCache = {};

  // Cart validation state
  bool _isValidating = false;
  bool _canCheckout = true;
  Map<String, String> _itemIssues = {};
  Map<String, bool> _itemBlocking = {};
  String? _cartGlobalWarning;

  OverlayEntry? _notificationOverlay;

  @override
  void initState() {
    super.initState();
    addressModel = MyAppState.selectedPosotion;

    coupon = _fireStoreUtils.getAllCoupons();
    getFoodType();
    getTaxData(); // Add this line

    // Initialize Dineaway state
    selectedDineawayType = null;
    isDineawaySelected = false;
  }

  @override
  void dispose() {
    _notificationOverlay?.remove();
    _notificationOverlay = null;
    super.dispose();
  }

  void _showTopNotification({
    required String message,
    required Color color,
    required IconData icon,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!mounted) return;
    _notificationOverlay?.remove();
    _notificationOverlay = null;

    final entry = OverlayEntry(
      builder: (_) => Positioned(
        top: MediaQuery.of(context).padding.top + 14,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: AppTypography.labelSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    _notificationOverlay = entry;
    Overlay.of(context).insert(entry);

    Future.delayed(duration, () {
      _notificationOverlay?.remove();
      _notificationOverlay = null;
    });
  }

  // Add this method to fetch tax data
  Future<void> getTaxData() async {
    try {
      print('Fetching tax data...');
      // Try to get taxes from the tax collection
      await FireStoreUtils.firestore
          .collection('tax')
          .where('enable', isEqualTo: true)
          .get()
          .then((value) {
        if (value.docs.isNotEmpty) {
          List<TaxModel> taxes = [];
          for (var doc in value.docs) {
            taxes.add(TaxModel.fromJson(doc.data()));
          }
          print('Tax data fetched: ${taxes.length} taxes found');
          for (var tax in taxes) {
            print('Tax: ${tax.title}, Type: ${tax.type}, Value: ${tax.tax}');
          }
          taxList = taxes;
          setState(() {});
        } else {
          print('No tax data found from tax collection');
        }
      });
    } catch (e) {
      print('Error fetching tax data: $e');
      taxList = [];
    }
  }

  getFoodType() async {
    SharedPreferences sp = await SharedPreferences.getInstance();
    setState(() {
      selctedOrderTypeValue =
          sp.getString("foodType") == "" || sp.getString("foodType") == null
              ? "Delivery"
              : sp.getString("foodType");
    });
    await FireStoreUtils.firestore
        .collection(Setting)
        .doc('specialDiscountOffer')
        .get()
        .then((value) {
      specialDiscountEnable = value.data()!['isEnable'];
    });
  }

  Future<void> getDeliveyData() async {
    isDeliverFound = true;
    await _fireStoreUtils
        .getVendorByVendorID(cartProducts.first.vendorID)
        .then((value) {
      vendorModel = value;
      vendorID = cartProducts.first.vendorID; // Set vendorID here
    });

    // Get tax data for this vendor/section
    await getTaxData();

    if (selctedOrderTypeValue == "Delivery") {
      num km = num.parse(getKm(
          addressModel.location!,
          UserLocation(
              latitude: vendorModel!.latitude,
              longitude: vendorModel!.longitude)));

      getDeliveryCharges(km);
    }

    _validateCart();
  }

  Future<void> _validateCart() async {
    if (!mounted || cartProducts.isEmpty) return;
    setState(() {
      _isValidating = true;
      _itemIssues = {};
      _itemBlocking = {};
      _cartGlobalWarning = null;
      _canCheckout = true;
    });

    // Check restaurant open/closed
    if (vendorModel != null && !vendorModel!.reststatus) {
      setState(() {
        _cartGlobalWarning = "Restaurant is currently closed. You cannot place orders right now.".tr();
        _canCheckout = false;
      });
    }

    final List<String> idsToRemove = [];
    final List<Map<String, String>> priceChanges = [];
    for (final cartProduct in List<CartProduct>.from(cartProducts)) {
      final pid = cartProduct.id.split('~').first;
      try {
        final product = await _fireStoreUtils.getProductByID(pid);

        if (!product.publish) {
          idsToRemove.add(cartProduct.id);
          continue;
        }

        // Out of stock (quantity 0; -1 = unlimited)
        if (product.quantity == 0) {
          setState(() {
            _itemIssues[cartProduct.id] = "Out of stock — remove to proceed".tr();
            _itemBlocking[cartProduct.id] = true;
            _canCheckout = false;
          });
          continue;
        }

        // Price change — auto-update cart
        final freshPrice = productCommissionPrice(
          product.disPrice != null &&
                  product.disPrice!.isNotEmpty &&
                  double.parse(product.disPrice!) != 0
              ? product.disPrice!
              : product.price,
        );
        if (freshPrice != cartProduct.price) {
          priceChanges.add({
            'name': cartProduct.name,
            'old': cartProduct.price,
            'new': freshPrice,
          });
          await cartDatabase.updateProduct(CartProduct(
            id: cartProduct.id,
            category_id: cartProduct.category_id,
            name: cartProduct.name,
            photo: cartProduct.photo,
            price: freshPrice,
            vendorID: cartProduct.vendorID,
            quantity: cartProduct.quantity,
            extras: cartProduct.extras,
            extras_price: cartProduct.extras_price,
            variant_info: cartProduct.variant_info,
            discountPrice: cartProduct.discountPrice,
          ));
        }

        // Variant removed check
        if (cartProduct.variant_info != null &&
            product.itemAttributes != null &&
            product.itemAttributes!.variants != null) {
          VariantInfo? variantInfo;
          try {
            final decoded = jsonDecode(cartProduct.variant_info.toString());
            if (decoded is Map<String, dynamic>) {
              variantInfo = VariantInfo.fromJson(decoded);
            }
          } catch (_) {}
          if (variantInfo != null) {
            final variantExists = product.itemAttributes!.variants!.any(
              (v) => v.variant_sku == variantInfo!.variant_sku,
            );
            if (!variantExists) {
              setState(() {
                _itemIssues[cartProduct.id] =
                    "Selected variant no longer available".tr();
                _itemBlocking[cartProduct.id] = true;
                _canCheckout = false;
              });
            }
          }
        }

      } catch (_) {
        // LateInitializationError (product deleted) or any parse error
        idsToRemove.add(cartProduct.id);
      }
    }

    for (final id in idsToRemove) {
      await cartDatabase.removeProduct(id);
    }

    if (idsToRemove.isNotEmpty && mounted) {
      _showTopNotification(
        message: "Some items were removed — no longer available.".tr(),
        color: AppThemeData.error500,
        icon: Icons.remove_shopping_cart_outlined,
      );
    }

    if (priceChanges.isNotEmpty && mounted) {
      final String message = priceChanges.length == 1
          ? "${'Price updated from'.tr()} ${amountShow(amount: priceChanges.first['old']!)} ${'to'.tr()} ${amountShow(amount: priceChanges.first['new']!)}"
          : "${priceChanges.length} ${'items price updated to latest'.tr()}";
      _showTopNotification(
        message: message,
        color: AppThemeData.warning500,
        icon: Icons.price_change_outlined,
      );
    }

    if (mounted) setState(() => _isValidating = false);
  }

  getDeliveryCharges(num km) async {
    deliverExec = true;
    String newDeliveryCharges = "0.0";

    if (sectionConstantModel!.serviceTypeFlag == "ecommerce-service") {
      newDeliveryCharges = sectionConstantModel!.delivery_charge!;
    } else {
      DeliveryChargeModel? deliveryChargeModel =
          await _fireStoreUtils.getDeliveryCharges();

      if (deliveryChargeModel != null) {
        if (!deliveryChargeModel.vendorCanModify) {
          if (km > deliveryChargeModel.minimumDeliveryChargesWithinKm) {
            newDeliveryCharges = (km * deliveryChargeModel.deliveryChargesPerKm)
                .toDouble()
                .toStringAsFixed(
                    (currencyData != null) ? currencyData!.decimal : 2);
          } else {
            newDeliveryCharges = deliveryChargeModel.minimumDeliveryCharges
                .toDouble()
                .toStringAsFixed(
                    (currencyData != null) ? currencyData!.decimal : 2);
          }
        } else {
          if (vendorModel != null && vendorModel!.deliveryCharge != null) {
            if (km >
                vendorModel!.deliveryCharge!.minimumDeliveryChargesWithinKm) {
              newDeliveryCharges =
                  (km * vendorModel!.deliveryCharge!.deliveryChargesPerKm)
                      .toDouble()
                      .toStringAsFixed(
                          (currencyData != null) ? currencyData!.decimal : 2);
            } else {
              newDeliveryCharges = vendorModel!
                  .deliveryCharge!.minimumDeliveryCharges
                  .toDouble()
                  .toStringAsFixed(
                      (currencyData != null) ? currencyData!.decimal : 2);
            }
          } else {
            if (km > deliveryChargeModel.minimumDeliveryChargesWithinKm) {
              newDeliveryCharges = (km * deliveryChargeModel.deliveryChargesPerKm)
                  .toDouble()
                  .toStringAsFixed(
                      (currencyData != null) ? currencyData!.decimal : 2);
            } else {
              newDeliveryCharges = deliveryChargeModel.minimumDeliveryCharges
                  .toDouble()
                  .toStringAsFixed(
                      (currencyData != null) ? currencyData!.decimal : 2);
            }
          }
        }
      }
    }

    // Single setState call instead of multiple
    if (mounted) {
      setState(() {
        deliveryCharges = newDeliveryCharges;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    cartDatabase = Provider.of<CartDatabase>(context, listen: true);
    // Create the stream once — reusing the same instance prevents StreamBuilder
    // from resetting (and the scroll position from jumping) on every setState.
    _cartStream ??= cartDatabase.watchProducts;
    cartFuture = cartDatabase.allCartProducts;
    getPrefData();
    //setPrefData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? AppThemeData.surfaceDark : AppThemeData.surface,
      body: SafeArea(
        child: StreamBuilder<List<CartProduct>>(
          stream: _cartStream ?? cartDatabase.watchProducts,
          initialData: const [],
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(
                child: CircularProgressIndicator.adaptive(
                  valueColor: AlwaysStoppedAnimation(AppThemeData.primary500),
                ),
              );
            }

            if (!snapshot.hasData || (snapshot.data?.isEmpty ?? true)) {
              // Cart was just cleared (e.g. section switch) — reset all billing state
              if (cartProducts.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      couponId = '';
                      percentage = 0.0;
                      type = 0.0;
                      txt.clear();
                      specialDiscount = 0.0;
                      specialDiscountAmount = 0.0;
                      specialType = '';
                      tipValue = 0.0;
                      deliveryCharges = '0.0';
                      isDeliverFound = false;
                      vendorID = '';
                      vendorModel = null;
                      selectedDineawayType = null;
                      isDineawaySelected = false;
                    });
                  }
                });
              }
              return SizedBox(
                width: MediaQuery.of(context).size.width * 1,
                child: Center(
                  child: showEmptyState('Empty Cart'.tr(), context),
                ),
              );
            } else {
              cartProducts = snapshot.data!;
              if (!isDeliverFound) {
                getDeliveyData();
              }
              return Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 0),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Cart validation status (always first) ──
                            if (_isValidating) ...[
                              _buildValidatingBanner(),
                              const SizedBox(height: 12),
                            ] else if (_cartGlobalWarning != null ||
                                _itemIssues.isNotEmpty) ...[
                              _buildIssuesSummaryCard(),
                              const SizedBox(height: 12),
                            ],

                            // ── Global items container ──
                            _buildItemsContainer(),
                            const SizedBox(height: 14),

                            // ── Coupon ──
                            _sectionCard(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                child: Row(
                                  children: [
                                    _iconBadge(Icons.local_offer_rounded),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            couponId.isNotEmpty
                                                ? txt.text
                                                : "View Coupons".tr(),
                                            style: AppTypography.labelLarge
                                                .copyWith(
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -0.1,
                                              color: isDarkMode(context)
                                                  ? AppThemeData.darkTextPrimary
                                                  : AppThemeData.neutral900,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            couponId.isNotEmpty
                                                ? "Coupon applied!".tr()
                                                : "Tap to view & apply coupons"
                                                    .tr(),
                                            style: AppTypography.labelSmall
                                                .copyWith(
                                              fontWeight: FontWeight.w500,
                                              color: couponId.isNotEmpty
                                                  ? AppThemeData.success400
                                                  : (isDarkMode(context)
                                                      ? AppThemeData
                                                          .darkTextTertiary
                                                      : AppThemeData
                                                          .neutral500),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (couponId.isNotEmpty) ...[
                                      GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            couponId = '';
                                            percentage = 0.0;
                                            type = 0.0;
                                            txt.clear();
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: AppThemeData.error500
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            "Remove".tr(),
                                            style: AppTypography.labelSmall
                                                .copyWith(
                                              color: AppThemeData.error500,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    GestureDetector(
                                      onTap: () {
                                        showModalBottomSheet(
                                          isScrollControlled: true,
                                          isDismissible: true,
                                          context: context,
                                          backgroundColor: Colors.transparent,
                                          enableDrag: true,
                                          builder: (BuildContext ctx) =>
                                              sheet(),
                                        );
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: couponId.isNotEmpty
                                              ? AppThemeData.success500
                                              : AppThemeData.primary500,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        padding: const EdgeInsets.all(8),
                                        child: Icon(
                                          couponId.isNotEmpty
                                              ? Icons.check
                                              : Icons.add,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // ── Address ──
                            if (selctedOrderTypeValue == "Delivery") ...[
                              _modernAddressSection(),
                              const SizedBox(height: 12),
                            ],

                            // ── Schedule ──
                            if (sectionConstantModel!.serviceTypeFlag !=
                                "ecommerce-service") ...[
                              _modernScheduleSection(),
                              const SizedBox(height: 12),
                            ],

                            // ── Dineaway ──
                            if (selctedOrderTypeValue == "Dineaway") ...[
                              _modernDineawaySection(),
                              const SizedBox(height: 12),
                            ],

                            // ── Bill Details ──
                            _modernSummarySection(
                                snapshot.data!, lstExtras, vendorID),
                            const SizedBox(height: 12),

                            // ── Tip ──
                            if (selctedOrderTypeValue == "Delivery") ...[
                              _modernTipSection(),
                              const SizedBox(height: 8),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Place Order Bar
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _isValidating || !_canCheckout
                            ? [AppThemeData.neutral400, AppThemeData.neutral500]
                            : [
                                AppThemeData.primary500,
                                AppThemeData.primary600,
                              ],
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(28),
                        topRight: Radius.circular(28),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppThemeData.primary500.withValues(alpha: 0.40),
                          blurRadius: 24,
                          offset: const Offset(0, -8),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: GestureDetector(
                        onTap: () {
                          if (_isValidating) {
                            _showTopNotification(
                              message: "Validating cart, please wait...".tr(),
                              color: AppThemeData.primary500,
                              icon: Icons.hourglass_top_rounded,
                              duration: const Duration(seconds: 2),
                            );
                            return;
                          }
                          if (!_canCheckout) {
                            _showTopNotification(
                              message: _cartGlobalWarning ??
                                  "Please resolve cart issues before placing order.".tr(),
                              color: AppThemeData.error500,
                              icon: Icons.warning_amber_rounded,
                            );
                            return;
                          }
                          if (selctedOrderTypeValue == "Dineaway" &&
                              (!isDineawaySelected || selectedDineawayType == null)) {
                            _showTopNotification(
                              message: "Please select order type.".tr(),
                              color: AppThemeData.primary500,
                              icon: Icons.info_outline_rounded,
                              duration: const Duration(seconds: 3),
                            );
                            return;
                          }

                          if (couponId.isEmpty) {
                            txt.text = "";
                          }
                          final specialDiscountMap = {
                            'special_discount': specialDiscountAmount,
                            'special_discount_label': specialDiscount,
                            'specialType': specialType
                          };
                          final isDelivery = selctedOrderTypeValue == "Delivery";
                          final isTakeaway = selctedOrderTypeValue == "Dineaway";
                          final String? orderTypeToStore =
                              selctedOrderTypeValue == "Dineaway"
                                  ? selectedDineawayType
                                  : null;

                          push(
                            context,
                            PaymentScreen(
                              total: grandtotal,
                              products: cartProducts,
                              discount: per == 0.0 ? type : per,
                              couponCode: txt.text,
                              couponId: couponId,
                              notes: noteController.text,
                              extra_addons: commaSepratedAddOns,
                              tipValue: isDelivery ? tipValue.toString() : "0",
                              take_away: isTakeaway,
                              deliveryCharge: isDelivery ? deliveryCharges : "0",
                              taxModel: taxList,
                              specialDiscountMap: specialDiscountMap,
                              scheduleTime: scheduleTime,
                              addressModel: addressModel,
                              orderType: orderTypeToStore,
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    cartProducts.length == 1
                                        ? "1 item".tr()
                                        : "${cartProducts.length} ${"items".tr()}",
                                    style: AppTypography.caption.copyWith(
                                      color: Colors.white.withValues(alpha: 0.70),
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    amountShow(amount: grandtotal.toString()),
                                    style: AppTypography.h5.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 22, vertical: 13),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.28),
                                    width: 1,
                                  ),
                                ),
                                child: _isValidating
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor:
                                              AlwaysStoppedAnimation(Colors.white),
                                        ),
                                      )
                                    : Row(
                                        children: [
                                          Text(
                                            !_canCheckout
                                                ? "Issues Found".tr()
                                                : "Place Order".tr(),
                                            style:
                                                AppTypography.labelLarge.copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.1,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(
                                            !_canCheckout
                                                ? Icons.warning_amber_rounded
                                                : Icons.arrow_forward_rounded,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }
          },
        ),
      ),
    );
  }

  // Shared card wrapper used by all sections
  Widget _sectionCard({required Widget child}) {
    final dark = isDarkMode(context);
    return Container(
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgSecondary : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: dark
              ? AppThemeData.darkBorderSecondary
              : AppThemeData.neutral100,
          width: dark ? 1.0 : 0.8,
        ),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 24,
                  offset: const Offset(0, 2),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: child,
    );
  }

  // Shared icon badge for section leading icons
  Widget _iconBadge(IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: AppThemeData.primary500.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(9),
      child: Icon(icon, color: AppThemeData.primary500, size: 22),
    );
  }

  // Modern Address Section
  Widget _modernAddressSection() {
    return _sectionCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: _iconBadge(Icons.location_on_rounded),
        title: Text(
          "Delivery Address".tr(),
          style: AppTypography.labelLarge.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
            color: isDarkMode(context)
                ? AppThemeData.darkTextPrimary
                : AppThemeData.neutral900,
          ),
        ),
        subtitle: GestureDetector(
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (context) => Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Delivery Address".tr(),
                      style: AppTypography.h5.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      addressModel.getFullAddress(),
                      style: AppTypography.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppThemeData.primary500,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: Text("Close".tr(), style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                addressModel.getFullAddress().length > 45
                    ? "${addressModel.getFullAddress().substring(0, 45)}..."
                    : addressModel.getFullAddress(),
                style: AppTypography.bodySmall.copyWith(
                  color: isDarkMode(context)
                      ? AppThemeData.darkTextSecondary
                      : AppThemeData.neutral600,
                ),
              ),
              Text(
                "Tap to view full address".tr(),
                style: AppTypography.labelSmall.copyWith(
                  color: AppThemeData.primary500,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        trailing: GestureDetector(
          onTap: () async {
            await Navigator.of(context)
                .push(MaterialPageRoute(
                    builder: (context) => DeliveryAddressScreen()))
                .then((value) {
              addressModel = value;
              getDeliveyData();
              setState(() {});
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppThemeData.primary500.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              "Change".tr(),
              style: AppTypography.labelSmall.copyWith(
                fontWeight: FontWeight.bold,
                color: AppThemeData.primary500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Modern Schedule Section
  Widget _modernScheduleSection() {
    return _sectionCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: _iconBadge(Icons.schedule_rounded),
        title: Text(
          "Schedule Order".tr(),
          style: AppTypography.labelLarge.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
            color: isDarkMode(context)
                ? AppThemeData.darkTextPrimary
                : AppThemeData.neutral900,
          ),
        ),
        subtitle: Text(
          scheduleTime == null
              ? "Deliver as soon as possible".tr()
              : DateFormat("EEE dd MMM, hh:mm a").format(scheduleTime!.toDate()),
          style: AppTypography.bodySmall.copyWith(
            color: isDarkMode(context)
                ? AppThemeData.darkTextSecondary
                : AppThemeData.neutral600,
          ),
        ),
        trailing: GestureDetector(
          onTap: () {
            if (vendorModel != null && !vendorModel!.reststatus) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    "This restaurant is currently closed. Scheduled booking is not available right now."
                        .tr(),
                  ),
                  backgroundColor: AppThemeData.error500,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              );
              return;
            }
            _showSchedulePicker();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppThemeData.primary500.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              scheduleTime == null ? "Select".tr() : "Change".tr(),
              style: AppTypography.labelSmall.copyWith(
                fontWeight: FontWeight.bold,
                color: AppThemeData.primary500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Generates 30-minute time slots for the given day offset (0=today, 1=tomorrow).
  // For today, slots at least 30 min in the future are included.
  List<DateTime> _generateTimeSlots(int dateIndex) {
    final now = DateTime.now();
    final base =
        dateIndex == 0 ? now : now.add(const Duration(days: 1));
    final date = DateTime(base.year, base.month, base.day);

    const int startHour = 8;
    const int endHour = 23;
    final List<DateTime> slots = [];
    for (int h = startHour; h <= endHour; h++) {
      slots.add(date.add(Duration(hours: h)));
      if (h < endHour) slots.add(date.add(Duration(hours: h, minutes: 30)));
    }

    if (dateIndex == 0) {
      final cutoff = now.add(const Duration(minutes: 30));
      return slots.where((s) => s.isAfter(cutoff)).toList();
    }
    return slots;
  }

  void _showSchedulePicker() {
    int selectedDateIndex = 0;
    if (scheduleTime != null) {
      final today = DateTime.now();
      final s = scheduleTime!.toDate();
      if (s.year == today.year &&
          s.month == today.month &&
          s.day == today.day) {
        selectedDateIndex = 0;
      } else {
        selectedDateIndex = 1;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final dark = isDarkMode(context);
            final slots = _generateTimeSlots(selectedDateIndex);

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.78,
              ),
              decoration: BoxDecoration(
                color: dark ? AppThemeData.darkBgSecondary : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: dark
                              ? AppThemeData.darkBorderPrimary
                              : AppThemeData.neutral300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Schedule Order".tr(),
                            style: AppTypography.h5.copyWith(
                              fontWeight: FontWeight.w700,
                              color: dark
                                  ? AppThemeData.darkTextPrimary
                                  : AppThemeData.neutral900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Choose a delivery date and time".tr(),
                            style: AppTypography.bodySmall.copyWith(
                              color: dark
                                  ? AppThemeData.darkTextSecondary
                                  : AppThemeData.neutral500,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // ── Date selection ──
                          Text(
                            "Select Date".tr(),
                            style: AppTypography.labelMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: dark
                                  ? AppThemeData.darkTextPrimary
                                  : AppThemeData.neutral800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _schedDatePill(
                                label: "Today".tr(),
                                date: DateFormat("d MMM").format(DateTime.now()),
                                isSelected: selectedDateIndex == 0,
                                dark: dark,
                                onTap: () =>
                                    setSheetState(() => selectedDateIndex = 0),
                              ),
                              const SizedBox(width: 12),
                              _schedDatePill(
                                label: "Tomorrow".tr(),
                                date: DateFormat("d MMM").format(
                                    DateTime.now()
                                        .add(const Duration(days: 1))),
                                isSelected: selectedDateIndex == 1,
                                dark: dark,
                                onTap: () =>
                                    setSheetState(() => selectedDateIndex = 1),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // ── Time slot selection ──
                          Text(
                            "Select Time".tr(),
                            style: AppTypography.labelMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: dark
                                  ? AppThemeData.darkTextPrimary
                                  : AppThemeData.neutral800,
                            ),
                          ),
                          const SizedBox(height: 10),

                          if (slots.isEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text(
                                  "No available slots for today.\nTry selecting Tomorrow."
                                      .tr(),
                                  textAlign: TextAlign.center,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: dark
                                        ? AppThemeData.darkTextSecondary
                                        : AppThemeData.neutral500,
                                  ),
                                ),
                              ),
                            )
                          else
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: slots.map((slot) {
                                final bool sel = scheduleTime != null &&
                                    scheduleTime!.toDate().year == slot.year &&
                                    scheduleTime!.toDate().month ==
                                        slot.month &&
                                    scheduleTime!.toDate().day == slot.day &&
                                    scheduleTime!.toDate().hour == slot.hour &&
                                    scheduleTime!.toDate().minute ==
                                        slot.minute;
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      scheduleTime = Timestamp.fromDate(slot);
                                    });
                                    setSheetState(() {});
                                  },
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 180),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: sel
                                          ? AppThemeData.primary500
                                          : (dark
                                              ? AppThemeData.darkBgTertiary
                                              : AppThemeData.neutral100),
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      border: Border.all(
                                        color: sel
                                            ? AppThemeData.primary500
                                            : (dark
                                                ? AppThemeData
                                                    .darkBorderSecondary
                                                : AppThemeData.neutral200),
                                      ),
                                    ),
                                    child: Text(
                                      DateFormat("hh:mm a").format(slot),
                                      style:
                                          AppTypography.labelSmall.copyWith(
                                        color: sel
                                            ? Colors.white
                                            : (dark
                                                ? AppThemeData
                                                    .darkTextSecondary
                                                : AppThemeData.neutral700),
                                        fontWeight: sel
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),

                  // ── Action buttons ──
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        20,
                        8,
                        20,
                        MediaQuery.of(context).viewInsets.bottom + 20),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppThemeData.primary500,
                              disabledBackgroundColor:
                                  AppThemeData.neutral300,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: scheduleTime == null
                                ? null
                                : () => Navigator.pop(ctx),
                            child: Text(
                              "Confirm Schedule".tr(),
                              style: AppTypography.labelLarge.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() => scheduleTime = null);
                            Navigator.pop(ctx);
                          },
                          child: Text(
                            "Clear & Deliver ASAP".tr(),
                            style: AppTypography.labelMedium.copyWith(
                              color: dark
                                  ? AppThemeData.darkTextSecondary
                                  : AppThemeData.neutral500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _schedDatePill({
    required String label,
    required String date,
    required bool isSelected,
    required VoidCallback onTap,
    required bool dark,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? AppThemeData.primary500
                : (dark ? AppThemeData.darkBgTertiary : AppThemeData.neutral50),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? AppThemeData.primary500
                  : (dark
                      ? AppThemeData.darkBorderPrimary
                      : AppThemeData.neutral200),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: AppTypography.labelMedium.copyWith(
                  color: isSelected
                      ? Colors.white
                      : (dark
                          ? AppThemeData.darkTextSecondary
                          : AppThemeData.neutral700),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                date,
                style: AppTypography.caption.copyWith(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.80)
                      : (dark
                          ? AppThemeData.darkTextTertiary
                          : AppThemeData.neutral400),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Modern Summary Section
  Widget _modernSummarySection(
      List<CartProduct> data, List<AddAddonsDemo> lstExtras, String vendorID) {
    // Use the logic from buildTotalRow, but with a modern card UI, icons, and color highlights
    var _font = 16.00;
    subTotal = 0.00;
    grandtotal = 0;
    double discountVal = 0;

    for (int a = 0; a < data.length; a++) {
      CartProduct e = data[a];
      bool isAddOnApplied = false;
      double AddOnVal = 0;
      for (int i = 0; i < lstExtras.length; i++) {
        AddAddonsDemo addAddonsDemo = lstExtras[i];
        if (addAddonsDemo.categoryID == e.id) {
          isAddOnApplied = true;
          AddOnVal = AddOnVal + double.parse(addAddonsDemo.price!);
        }
      }
      if (e.extras_price != null &&
          e.extras_price != "" &&
          double.parse(e.extras_price!) != 0.0) {
        subTotal += double.parse(e.extras_price!) * e.quantity;
      }
      subTotal += double.parse(e.price) * e.quantity;
      grandtotal = subTotal + double.parse(deliveryCharges) + tipValue;
    }

    if (percentage != null) {
      amount = 0;
      amount = subTotal * percentage / 100;
      discountVal = subTotal * percentage / 100;
      grandtotal = grandtotal - amount;
      per = amount.toDouble();
    }
    amount = grandtotal - type;
    grandtotal = amount;
    if (type != 0) {
      discountVal = type;
    }

    if (vendorModel != null && specialDiscountEnable) {
      if (vendorModel!.specialDiscountEnable) {
        // Reset special discount amount at the beginning
        specialDiscountAmount = 0.0;
        final now = new DateTime.now();
        var day = DateFormat('EEEE', 'en_US').format(now);
        var date = DateFormat('dd-MM-yyyy').format(now);
        
        print('🔍 Special Discount Evaluation Started');
        print('📅 Current day: $day, Date: $date');
        print('🛒 Cart subtotal: ₹$subTotal, Order type: $selctedOrderTypeValue');
        
        // Collect all eligible discounts for maximum selection
        List<Map<String, dynamic>> eligibleDiscounts = [];
        
        vendorModel!.specialDiscount.forEach((dayDiscount) {
          if (day == dayDiscount.day.toString()) {
            print('✅ Found discount rules for $day');
            
            if (dayDiscount.timeslot!.isNotEmpty) {
              dayDiscount.timeslot!.forEach((timeSlot) {
                if (timeSlot.discount_type == "delivery") {
                  var start = DateFormat("dd-MM-yyyy HH:mm")
                      .parse(date + " " + timeSlot.from.toString());
                  var end = DateFormat("dd-MM-yyyy HH:mm")
                      .parse(date + " " + timeSlot.to.toString());
                  
                  print('⏰ Checking timeslot: ${timeSlot.from} - ${timeSlot.to}');
                  
                  if (isCurrentDateInRange(start, end)) {
                    print('✅ Time condition met');
                    
                    // Check if subtotal meets the applicable amount condition
                    bool subtotalCondition = true;
                    if (timeSlot.applicableAmount != null && timeSlot.applicableAmount!.isNotEmpty) {
                      double applicableAmount = double.parse(timeSlot.applicableAmount!);
                      subtotalCondition = subTotal >= applicableAmount;
                      print('💰 Min amount: ₹$applicableAmount, Condition: ${subtotalCondition ? "✅ Met" : "❌ Not met"}');
                    }
                    
                    // Check if order type matches
                    bool orderTypeCondition = true;
                    if (timeSlot.orderType != null && timeSlot.orderType!.isNotEmpty) {
                      String currentOrderType = selctedOrderTypeValue == "Delivery" ? "Delivery" : "Takeaway";
                      orderTypeCondition = timeSlot.orderType == currentOrderType;
                      print('🚚 Order type: ${timeSlot.orderType}, Condition: ${orderTypeCondition ? "✅ Met" : "❌ Not met"}');
                    }
                    
                    // Add to eligible list if both conditions are met
                    if (subtotalCondition && orderTypeCondition) {
                      double discountValue = double.parse(timeSlot.discount.toString());
                      String discountType = timeSlot.type.toString();
                      
                      // Calculate actual discount amount for comparison
                      double actualDiscountAmount;
                      if (discountType == "percentage") {
                        actualDiscountAmount = subTotal * discountValue / 100;
                      } else {
                        actualDiscountAmount = discountValue;
                      }
                      
                      eligibleDiscounts.add({
                        'discountValue': discountValue,
                        'discountType': discountType,
                        'actualAmount': actualDiscountAmount,
                        'description': discountType == "percentage" 
                            ? '${discountValue.toStringAsFixed(0)}% off (₹${actualDiscountAmount.toStringAsFixed(2)})'
                            : 'Flat ₹${discountValue.toStringAsFixed(2)} off'
                      });
                      
                      print('✅ Eligible discount found: ${eligibleDiscounts.last['description']}');
                    } else {
                      print('❌ Discount not eligible - conditions not met');
                    }
                  } else {
                    print('❌ Time condition not met');
                  }
                }
              });
            }
          }
        });
        
        // Select the maximum discount from eligible discounts
        if (eligibleDiscounts.isNotEmpty) {
          print('\n🏆 Selecting maximum discount from ${eligibleDiscounts.length} eligible discount(s):');
          
          // Find the discount with maximum actual amount
          var maxDiscount = eligibleDiscounts.reduce((current, next) => 
            current['actualAmount'] > next['actualAmount'] ? current : next);
          
          specialDiscount = maxDiscount['discountValue'];
          specialType = maxDiscount['discountType'];
          specialDiscountAmount = maxDiscount['actualAmount'];
          
          print('🎯 Selected: ${maxDiscount['description']} - Final amount: ₹${specialDiscountAmount.toStringAsFixed(2)}');
          
          // Apply the maximum discount to grand total
          grandtotal = grandtotal - specialDiscountAmount;
          
          print('💸 Grand total after discount: ₹${grandtotal.toStringAsFixed(2)}');
        } else {
          print('❌ No eligible discounts found');
          specialDiscount = 0.0;
          specialType = "amount";
          specialDiscountAmount = 0.0;
        }
        
        print('🔚 Special Discount Evaluation Complete\n');
        
      } else {
        specialDiscount = double.parse("0");
        specialType = "amount";
        specialDiscountAmount = 0.0;
      }
    } else {
      // Reset special discount when not enabled
      specialDiscountAmount = 0.0;
    }

    // Calculate all applicable taxes regardless of visibility
    double totalTaxAmount = 0.0;
    // Track taxes to display in the UI
    List<TaxModel> taxesToDisplay = [];
    
    if (taxList != null) {
      for (var element in taxList!) {
        // Check if the tax applies to the current order type
        bool shouldApplyTax = (selctedOrderTypeValue == "Delivery" &&
                (element.isTakeaway == false || element.isTakeaway == null)) ||
            (selctedOrderTypeValue == "Dineaway" && element.isTakeaway == true);

        print('Tax check - Tax: ${element.title}, shouldApplyTax: $shouldApplyTax, isTakeaway: ${element.isTakeaway}, orderType: $selctedOrderTypeValue');

        if (shouldApplyTax) {
          double taxAmount = getTaxValue(
              amount:
                  (subTotal - discountVal - specialDiscountAmount).toString(),
              taxModel: element);
          totalTaxAmount += taxAmount;

          print('Tax applied - ${element.title}: $taxAmount');

          // Add this tax to the display list
          taxesToDisplay.add(element);
        }
      }
    }

    // Add the total tax amount to grand total
    grandtotal += totalTaxAmount;

    print('Summary: ${taxesToDisplay.length} taxes to display, totalTaxAmount: $totalTaxAmount, orderType: $selctedOrderTypeValue');

    final bool dark = isDarkMode(context);
    final Color labelColor =
        dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral600;
    final Color valueColor =
        dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral800;
    final Color dividerColor =
        dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral100;

    final String discountDisplay = percentage != 0.0
        ? percentage != null
            ? "(-${amountShow(amount: per.toDouble().toString())})"
            : "(-${amountShow(amount: '0.0')})"
        : type != null
            ? "(-${amountShow(amount: type.toDouble().toString())})"
            : "(-${amountShow(amount: '0.0')})";

    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Grand Total header (accordion trigger) ──
          InkWell(
            onTap: () => setState(() => _isBillExpanded = !_isBillExpanded),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Grand Total'.tr(),
                          style: AppTypography.labelMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: dark
                                ? AppThemeData.darkTextSecondary
                                : AppThemeData.neutral600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _isBillExpanded
                                  ? 'Hide bill details'.tr()
                                  : 'View bill details'.tr(),
                              style: AppTypography.caption.copyWith(
                                color: dark
                                    ? AppThemeData.darkTextTertiary
                                    : AppThemeData.neutral400,
                              ),
                            ),
                            const SizedBox(width: 3),
                            AnimatedRotation(
                              turns: _isBillExpanded ? 0.5 : 0.0,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                              child: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: dark
                                    ? AppThemeData.darkTextTertiary
                                    : AppThemeData.neutral400,
                                size: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Text(
                    amountShow(amount: grandtotal.toString()),
                    style: AppTypography.h5.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      letterSpacing: -0.5,
                      color: AppThemeData.primary500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Animated breakdown ──
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _isBillExpanded
                ? Column(
                    children: [
                      Divider(height: 1, color: dividerColor),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                        child: Column(
                          children: [
                            _billRow('Subtotal'.tr(),
                                amountShow(amount: subTotal.toString()),
                                labelColor, valueColor),
                            _billRow('Discount'.tr(), discountDisplay,
                                labelColor, AppThemeData.success500),
                            if (vendorModel != null &&
                                specialDiscountEnable &&
                                vendorModel!.specialDiscountEnable &&
                                specialDiscountAmount > 0.0)
                              _billRow(
                                  'Special Discount'.tr(),
                                  '(-${amountShow(amount: specialDiscountAmount.toString())})',
                                  labelColor,
                                  AppThemeData.success500),
                            if (selctedOrderTypeValue == 'Delivery')
                              _billRow(
                                  'Delivery Charges'.tr(),
                                  amountShow(amount: deliveryCharges.toString()),
                                  labelColor,
                                  valueColor),
                            ...taxesToDisplay.map((taxModel) => _billRow(
                                  taxModel.title.toString(),
                                  amountShow(
                                      amount: getTaxValue(
                                    amount: (double.parse(subTotal.toString()) -
                                            discountVal -
                                            specialDiscountAmount)
                                        .toString(),
                                    taxModel: taxModel,
                                  ).toString()),
                                  labelColor,
                                  valueColor,
                                )),
                            if (tipValue > 0)
                              _billRow('Tip amount'.tr(),
                                  amountShow(amount: tipValue.toString()),
                                  labelColor, AppThemeData.warning500),
                            const SizedBox(height: 10),
                            Divider(height: 1, color: dividerColor),
                            const SizedBox(height: 10),
                            _billRow(
                                'Grand Total'.tr(),
                                amountShow(amount: grandtotal.toString()),
                                AppThemeData.primary500,
                                AppThemeData.primary500,
                                isBold: true),
                          ],
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _billRow(String label, String value, Color labelColor, Color valueColor,
      {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: isBold
                  ? AppTypography.labelLarge.copyWith(
                      fontWeight: FontWeight.w700,
                      color: labelColor,
                    )
                  : AppTypography.bodyMedium.copyWith(color: labelColor),
            ),
          ),
          Text(
            value,
            style: isBold
                ? AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    color: valueColor,
                    fontSize: 17,
                  )
                : AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                    color: valueColor,
                  ),
          ),
        ],
      ),
    );
  }

  // Modern Dineaway Section
  Widget _modernDineawaySection() {
    return _sectionCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _iconBadge(Icons.restaurant_menu_rounded),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Dineaway".tr(),
                      style: AppTypography.labelLarge.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDarkMode(context)
                            ? AppThemeData.darkTextPrimary
                            : AppThemeData.neutral900,
                      ),
                    ),
                    Text(
                      "Select order type".tr(),
                      style: AppTypography.bodySmall.copyWith(
                        color: isDarkMode(context)
                            ? AppThemeData.darkTextSecondary
                            : AppThemeData.neutral600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _dineawayOption(
                    "Takeaway",
                    "Pack the food for takeout",
                    Icons.shopping_bag_rounded,
                    selectedDineawayType == "Takeaway",
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _dineawayOption(
                    "Dining",
                    "Eat inside the restaurant",
                    Icons.restaurant_rounded,
                    selectedDineawayType == "Dining",
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dineawayOption(String title, String subtitle, IconData icon, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedDineawayType = title;
          isDineawaySelected = true;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppThemeData.primary500.withValues(alpha: 0.10)
              : (isDarkMode(context)
                  ? AppThemeData.darkBgPrimary
                  : AppThemeData.neutral50),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? AppThemeData.primary500
                : (isDarkMode(context)
                    ? AppThemeData.darkBorderSecondary
                    : AppThemeData.neutral200),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? AppThemeData.primary500
                  : (isDarkMode(context)
                      ? AppThemeData.darkTextSecondary
                      : AppThemeData.neutral500),
              size: 26,
            ),
            const SizedBox(height: 8),
            Text(
              title.tr(),
              style: AppTypography.labelMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: isSelected
                    ? AppThemeData.primary500
                    : (isDarkMode(context)
                        ? AppThemeData.darkTextPrimary
                        : AppThemeData.neutral900),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: AppTypography.bodySmall.copyWith(
                color: isDarkMode(context)
                    ? AppThemeData.darkTextTertiary
                    : AppThemeData.neutral500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Premium Tip Section
  Widget _modernTipSection() {
    final dark = isDarkMode(context);
    return _sectionCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.volunteer_activism_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Tip Your Delivery Partner".tr(),
                        style: AppTypography.labelLarge.copyWith(
                          fontWeight: FontWeight.w700,
                          color: dark
                              ? AppThemeData.darkTextPrimary
                              : AppThemeData.neutral900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tipValue > 0
                            ? "${"Tip added".tr()} · ${"Thank you".tr()}! 🙏"
                            : "100% goes to your delivery partner".tr(),
                        style: AppTypography.bodySmall.copyWith(
                          color: tipValue > 0
                              ? AppThemeData.success500
                              : (dark
                                  ? AppThemeData.darkTextSecondary
                                  : AppThemeData.neutral500),
                        ),
                      ),
                    ],
                  ),
                ),
                if (tipValue > 0)
                  GestureDetector(
                    onTap: () => setState(() {
                      tipValue = 0;
                      isTipSelected = false;
                      isTipSelected1 = false;
                      isTipSelected2 = false;
                      isTipSelected3 = false;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppThemeData.error500.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "Clear".tr(),
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: AppThemeData.semiBold,
                          color: AppThemeData.error500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                    child: _tipCard(10, Icons.local_cafe_rounded, isTipSelected)),
                const SizedBox(width: 8),
                Expanded(
                    child: _tipCard(20, Icons.icecream_rounded, isTipSelected1)),
                const SizedBox(width: 8),
                Expanded(
                    child: _tipCard(30, Icons.fastfood_rounded, isTipSelected2,
                        label: "Popular")),
                const SizedBox(width: 8),
                Expanded(child: _tipCardCustom()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tipCard(int value, IconData icon, bool selected, {String? label}) {
    final dark = isDarkMode(context);
    return GestureDetector(
      onTap: () {
        setState(() {
          tipValue = selected ? 0 : value.toDouble();
          isTipSelected = value == 10 ? !isTipSelected : false;
          isTipSelected1 = value == 20 ? !isTipSelected1 : false;
          isTipSelected2 = value == 30 ? !isTipSelected2 : false;
          isTipSelected3 = false;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: selected
              ? AppThemeData.primary500.withValues(alpha: 0.08)
              : (dark ? AppThemeData.darkBgPrimary : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppThemeData.primary500
                : (dark
                    ? AppThemeData.darkBorderSecondary
                    : AppThemeData.neutral200),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: AppThemeData.primary500.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ]
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 1))
                ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: selected
                    ? AppThemeData.primary500.withValues(alpha: 0.15)
                    : (dark
                        ? AppThemeData.darkBorderPrimary
                        : AppThemeData.neutral100),
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  color: selected
                      ? AppThemeData.primary500
                      : (dark
                          ? AppThemeData.darkTextSecondary
                          : AppThemeData.neutral500),
                  size: 18),
            ),
            const SizedBox(height: 7),
            Text(
              amountShow(amount: value.toString()),
              style: TextStyle(
                fontSize: 13,
                fontFamily: AppThemeData.bold,
                color: selected
                    ? AppThemeData.primary500
                    : (dark
                        ? AppThemeData.darkTextPrimary
                        : AppThemeData.neutral900),
              ),
            ),
            const SizedBox(height: 5),
            label != null
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppThemeData.primary500
                          : AppThemeData.warning500,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontFamily: AppThemeData.semiBold),
                    ),
                  )
                : const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }

  Widget _tipCardCustom() {
    final dark = isDarkMode(context);
    return GestureDetector(
      onTap: () {
        if (isTipSelected3) {
          setState(() {
            isTipSelected3 = false;
            tipValue = 0;
            isTipSelected = false;
            isTipSelected1 = false;
            isTipSelected2 = false;
          });
        } else {
          _showCustomTipSheet(context);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: isTipSelected3
              ? AppThemeData.primary500.withValues(alpha: 0.08)
              : (dark ? AppThemeData.darkBgPrimary : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isTipSelected3
                ? AppThemeData.primary500
                : (dark
                    ? AppThemeData.darkBorderSecondary
                    : AppThemeData.neutral200),
            width: isTipSelected3 ? 1.5 : 1,
          ),
          boxShadow: isTipSelected3
              ? [
                  BoxShadow(
                      color: AppThemeData.primary500.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ]
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 1))
                ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isTipSelected3
                    ? AppThemeData.primary500.withValues(alpha: 0.15)
                    : (dark
                        ? AppThemeData.darkBorderPrimary
                        : AppThemeData.neutral100),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isTipSelected3
                    ? Icons.check_rounded
                    : Icons.edit_note_rounded,
                color: isTipSelected3
                    ? AppThemeData.primary500
                    : (dark
                        ? AppThemeData.darkTextSecondary
                        : AppThemeData.neutral500),
                size: 18,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              isTipSelected3
                  ? amountShow(amount: tipValue.toString())
                  : "Custom".tr(),
              style: TextStyle(
                fontSize: 13,
                fontFamily: AppThemeData.bold,
                color: isTipSelected3
                    ? AppThemeData.primary500
                    : (dark
                        ? AppThemeData.darkTextPrimary
                        : AppThemeData.neutral900),
              ),
            ),
            const SizedBox(height: 19),
          ],
        ),
      ),
    );
  }

  // Global container: all item cards + Add More Items + Note for Restaurant
  Widget _buildItemsContainer() {
    final dark = isDarkMode(context);
    final dividerColor =
        dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral100;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgSecondary : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border:
            dark ? Border.all(color: AppThemeData.darkBorderPrimary, width: 1) : null,
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Your Order".tr(),
                  style: AppTypography.h5.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: dark
                        ? AppThemeData.darkTextPrimary
                        : AppThemeData.neutral900,
                  ),
                ),
                if (vendorModel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    vendorModel!.title,
                    style: AppTypography.labelSmall.copyWith(
                      color: dark
                          ? AppThemeData.darkTextTertiary
                          : AppThemeData.neutral400,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Item rows with hairline dividers
          for (int i = 0; i < cartProducts.length; i++) ...[
            _modernCartItem(cartProducts[i], lstExtras),
            if (i != cartProducts.length - 1)
              Divider(height: 1, indent: 16, endIndent: 16, color: dividerColor),
          ],

          // ── Add More Items ──
          Divider(height: 1, indent: 16, endIndent: 16, color: dividerColor),
          InkWell(
            onTap: () {
              if (vendorModel != null) {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      NewVendorProductsScreen(vendorModel: vendorModel!),
                ));
              }
            },
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: AppThemeData.primary500.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.add,
                        color: AppThemeData.primary500, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Add More Items".tr(),
                    style: AppTypography.labelMedium.copyWith(
                      color: AppThemeData.primary500,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: AppThemeData.primary500,
                    size: 12,
                  ),
                ],
              ),
            ),
          ),

          // ── Note for Restaurant ──
          Divider(height: 1, color: dividerColor),
          _noteForRestaurantFlat(dark),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // Flat "Note for Restaurant" section (lives inside the global container)
  Widget _noteForRestaurantFlat(bool dark) {
    final hasNote = noteController.text.isNotEmpty;
    return InkWell(
      onTap: () => showModalBottomSheet(
        isScrollControlled: true,
        isDismissible: true,
        context: context,
        backgroundColor: Colors.transparent,
        enableDrag: true,
        builder: (_) => Notesheet(),
      ),
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(20),
        bottomRight: Radius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: dark
                    ? const Color(0xFF2A2218)
                    : const Color(0xFFFFF8EC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Icon(Icons.edit_note_rounded,
                    color: Color(0xFFE89B2F), size: 20),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Order Note".tr(),
                    style: AppTypography.labelMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: dark
                          ? AppThemeData.darkTextPrimary
                          : AppThemeData.neutral900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (hasNote)
                    Text(
                      noteController.text,
                      style: AppTypography.bodySmall.copyWith(
                        color: dark
                            ? AppThemeData.darkTextSecondary
                            : AppThemeData.neutral600,
                        height: 1.5,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    Text(
                      "Add special instructions for the restaurant".tr(),
                      style: AppTypography.bodySmall.copyWith(
                        color: dark
                            ? AppThemeData.darkTextTertiary
                            : AppThemeData.neutral400,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppThemeData.primary500.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                hasNote ? "Edit".tr() : "Add".tr(),
                style: AppTypography.labelSmall.copyWith(
                  color: AppThemeData.primary500,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Zomato/Swiggy-style veg · non-veg indicator
  Widget _foodTypeBadge(ProductModel? product) {
    const double size = 20;
    const double dotSize = 9;

    // Determine type
    final bool isVeg = product?.veg == true;
    final bool isNonVeg = product?.nonveg == true;

    final Color borderColor = isVeg
        ? const Color(0xFF2E7D32) // deep green
        : isNonVeg
            ? const Color(0xFF8B3A2A) // warm brown / maroon
            : AppThemeData.neutral300; // unknown – neutral grey

    final Color dotColor = isVeg
        ? const Color(0xFF2E7D32)
        : isNonVeg
            ? const Color(0xFF8B3A2A)
            : AppThemeData.neutral400;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor, width: 1.8),
        color: isDarkMode(context)
            ? borderColor.withValues(alpha: 0.08)
            : borderColor.withValues(alpha: 0.05),
      ),
      child: Center(
        child: Container(
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _modernCartItem(CartProduct cartProduct, List<AddAddonsDemo> addons) {
    List addOnVal = [];
    var quen = cartProduct.quantity;
    double priceTotalValue = 0.0;
    double AddOnVal = 0;
    for (int i = 0; i < lstExtras.length; i++) {
      AddAddonsDemo addAddonsDemo = lstExtras[i];
      if (addAddonsDemo.categoryID == cartProduct.id) {
        AddOnVal = AddOnVal + double.parse(addAddonsDemo.price!);
      }
    }

    // Performance optimization: Use cache to avoid N+1 queries
    ProductModel? productModel;
    final productId = cartProduct.id.split('~').first;
    if (_productCache.containsKey(productId)) {
      productModel = _productCache[productId];
    } else {
      // Only fetch if not in cache
      FireStoreUtils()
          .getProductByID(productId)
          .then((value) {
        if (value != null && mounted) {
          setState(() {
            _productCache[productId] = value;
          });
        }
      });
    }

    VariantInfo? variantInfo;
    if (cartProduct.variant_info != null) {
      try {
        final decoded = jsonDecode(cartProduct.variant_info.toString());
        if (decoded is Map<String, dynamic>) {
          variantInfo = VariantInfo.fromJson(decoded);
        }
      } catch (_) {}
    }
    if (cartProduct.extras == null) {
      addOnVal.clear();
    } else {
      if (cartProduct.extras is String) {
        if (cartProduct.extras == '[]') {
          addOnVal.clear();
        } else {
          String extraDecode = cartProduct.extras
              .toString()
              .replaceAll("[", "")
              .replaceAll("]", "")
              .replaceAll("\\", "");

          if (extraDecode.contains(",")) {
            addOnVal = extraDecode.split(",");
          } else {
            if (extraDecode.trim().isNotEmpty) {
              addOnVal = [extraDecode];
            }
          }
        }
      }

      if (cartProduct.extras is List) {
        addOnVal = List.from(cartProduct.extras);
      }
    }

    if (cartProduct.extras_price != null &&
        cartProduct.extras_price != "" &&
        double.parse(cartProduct.extras_price!) != 0.0) {
      priceTotalValue +=
          double.parse(cartProduct.extras_price!) * cartProduct.quantity;
    }
    priceTotalValue += double.parse(cartProduct.price) * cartProduct.quantity;

    final dark = isDarkMode(context);
    final hasVariants = variantInfo != null &&
        variantInfo.variant_options != null &&
        variantInfo.variant_options!.isNotEmpty;
    final hasAddons = addOnVal.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Left: veg badge + name + variants + add-ons ──
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: _foodTypeBadge(productModel),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Product name
                  Text(
                    cartProduct.name,
                    style: AppTypography.labelLarge.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: dark
                          ? AppThemeData.darkTextPrimary
                          : AppThemeData.neutral900,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Customization chips — variants + add-ons in one row
                  if (hasVariants || hasAddons) ...[
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        if (hasVariants)
                          ...variantInfo!.variant_options!.entries.map(
                            (e) => _buildChip(
                              '${e.key}: ${e.value}',
                              e.key.hashCode,
                              isDark: dark,
                            ),
                          ),
                        if (hasAddons)
                          ...addOnVal
                              .map((e) => e.toString().replaceAll('"', '').trim())
                              .where((e) => e.isNotEmpty)
                              .map((e) => _buildChip(e, e.hashCode, isDark: dark)),
                      ],
                    ),
                  ],
                  // ── Edit button (minimal whisper) ──
                  const SizedBox(height: 9),
                  GestureDetector(
                    onTap: () async {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => const Center(
                            child: CircularProgressIndicator.adaptive()),
                      );
                      final pid = cartProduct.id.split('~').first;
                      final pm =
                          await FireStoreUtils().getProductByID(pid);
                      VendorModel? vm;
                      if (pm != null) {
                        vm = await FireStoreUtils()
                            .getVendorByVendorID(pm.vendorID);
                      }
                      Navigator.of(context).pop();
                      if (pm != null && vm != null) {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ProductDetailsScreen(
                              productModel: pm, vendorModel: vm!),
                        ));
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.edit_rounded,
                          size: 12,
                          color: dark
                              ? AppThemeData.darkBorderPrimary
                              : AppThemeData.neutral300,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "Edit item".tr(),
                          style: AppTypography.caption.copyWith(
                            color: dark
                                ? AppThemeData.darkBorderPrimary
                                : AppThemeData.neutral400,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ── Validation issue banner ──
                  if (_itemIssues.containsKey(cartProduct.id)) ...[
                    const SizedBox(height: 8),
                    _buildItemIssueBanner(
                      message: _itemIssues[cartProduct.id]!,
                      isBlocking: _itemBlocking[cartProduct.id] ?? false,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            // ── Right: qty stepper (top) + price (bottom) ──
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Qty stepper — Swiggy-style pill
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: AppThemeData.primary500, width: 1.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Minus button
                      GestureDetector(
                        onTap: () {
                          if (quen <= 1) {
                            cartDatabase.removeProduct(cartProduct.id);
                          } else {
                            quen--;
                            removetocard(cartProduct, quen);
                          }
                        },
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: AppThemeData.primary500,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(6),
                              bottomLeft: Radius.circular(6),
                            ),
                          ),
                          child: const Icon(Icons.remove,
                              color: Colors.white, size: 14),
                        ),
                      ),
                      // Count
                      SizedBox(
                        width: 30,
                        child: Center(
                          child: Text(
                            '${cartProduct.quantity}',
                            style: AppTypography.labelMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              color: dark
                                  ? AppThemeData.darkTextPrimary
                                  : AppThemeData.neutral900,
                            ),
                          ),
                        ),
                      ),
                      // Plus button
                      GestureDetector(
                        onTap: () {
                          if (productModel == null) return;
                          if (productModel!.itemAttributes != null) {
                            final variantList =
                                productModel!.itemAttributes!.variants!;
                            Variants? matchingVariant;
                            try {
                              matchingVariant = variantList.firstWhere(
                                (v) =>
                                    v.variant_sku ==
                                    variantInfo?.variant_sku,
                              );
                            } catch (_) {
                              matchingVariant = null;
                            }
                            final maxQty = matchingVariant != null
                                ? int.parse(matchingVariant
                                    .variant_quantity
                                    .toString())
                                : productModel!.quantity;
                            if (maxQty > quen || maxQty == -1) {
                              quen++;
                              addtocard(cartProduct, quen);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        "Product is out of Stock".tr())),
                              );
                            }
                          } else {
                            if (productModel!.quantity > quen ||
                                productModel!.quantity == -1) {
                              quen++;
                              addtocard(cartProduct, quen);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        "Product is out of Stock".tr())),
                              );
                            }
                          }
                        },
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: AppThemeData.primary500,
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(6),
                              bottomRight: Radius.circular(6),
                            ),
                          ),
                          child: const Icon(Icons.add,
                              color: Colors.white, size: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                // Price — directly below qty
                const SizedBox(height: 8),
                Text(
                  amountShow(amount: priceTotalValue.toString()),
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: -0.1,
                    color: AppThemeData.primary500,
                  ),
                ),
              ],
            ),
          ],
        ),
    );
  }

  bool isCurrentDateInRange(DateTime startDate, DateTime endDate) {
    final currentDate = DateTime.now();
    return currentDate.isAfter(startDate) && currentDate.isBefore(endDate);
  }

  Widget _buildIssuesSummaryCard() {
    final dark = isDarkMode(context);
    final bool hasGlobal = _cartGlobalWarning != null;
    final blockingItems = _itemIssues.entries
        .where((e) => _itemBlocking[e.key] == true)
        .toList();
    final infoItems = _itemIssues.entries
        .where((e) => _itemBlocking[e.key] != true)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: dark
            ? AppThemeData.error500.withValues(alpha: 0.12)
            : AppThemeData.error500.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppThemeData.error500.withValues(alpha: 0.30),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.error_outline_rounded,
                  color: AppThemeData.error500, size: 18),
              const SizedBox(width: 8),
              Text(
                "Cart Issues".tr(),
                style: AppTypography.labelMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppThemeData.error500,
                ),
              ),
              const Spacer(),
              Text(
                "${_itemIssues.length + (hasGlobal ? 1 : 0)} ${'issue(s) found'.tr()}",
                style: AppTypography.caption.copyWith(
                  color: AppThemeData.error500,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          if (hasGlobal) ...[
            const SizedBox(height: 10),
            _issueLine(
              icon: Icons.storefront_outlined,
              message: _cartGlobalWarning!,
              blocking: true,
              dark: dark,
            ),
          ],

          if (blockingItems.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...blockingItems.map((e) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _issueLine(
                    icon: Icons.remove_circle_outline_rounded,
                    message: e.value,
                    blocking: true,
                    dark: dark,
                  ),
                )),
          ],

          if (infoItems.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...infoItems.map((e) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _issueLine(
                    icon: Icons.info_outline_rounded,
                    message: e.value,
                    blocking: false,
                    dark: dark,
                  ),
                )),
          ],

          const SizedBox(height: 10),
          Text(
            "Resolve the issues above to place your order.".tr(),
            style: AppTypography.caption.copyWith(
              color: dark
                  ? AppThemeData.darkTextTertiary
                  : AppThemeData.neutral500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _issueLine({
    required IconData icon,
    required String message,
    required bool blocking,
    required bool dark,
  }) {
    final color =
        blocking ? AppThemeData.error500 : AppThemeData.warning500;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: AppTypography.caption.copyWith(
              color: dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral700,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildValidatingBanner() {
    final dark = isDarkMode(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: dark
            ? AppThemeData.primary500.withValues(alpha: 0.15)
            : AppThemeData.primary500.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppThemeData.primary500.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            "Checking item availability...".tr(),
            style: AppTypography.labelSmall.copyWith(
              color: AppThemeData.primary500,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemIssueBanner(
      {required String message, required bool isBlocking}) {
    final dark = isDarkMode(context);
    final color =
        isBlocking ? AppThemeData.error500 : AppThemeData.warning500;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: dark
            ? color.withValues(alpha: 0.15)
            : color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(
            isBlocking
                ? Icons.remove_circle_outline_rounded
                : Icons.info_outline_rounded,
            color: color,
            size: 14,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: AppTypography.caption.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> addtocard(CartProduct cartProduct, int qun) async {
    try {
      await cartDatabase.updateProduct(CartProduct(
        id: cartProduct.id,
        category_id: cartProduct.category_id,
        name: cartProduct.name,
        photo: cartProduct.photo,
        price: cartProduct.price,
        vendorID: cartProduct.vendorID,
        quantity: qun,
        // nullable fields omitted → Moor's nullToAbsent keeps DB values intact
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Failed to update quantity".tr()),
          backgroundColor: AppThemeData.error500,
        ));
      }
    }
  }

  Future<void> removetocard(CartProduct cartProduct, int qun) async {
    try {
      if (qun >= 1) {
        await cartDatabase.updateProduct(CartProduct(
          id: cartProduct.id,
          category_id: cartProduct.category_id,
          name: cartProduct.name,
          photo: cartProduct.photo,
          price: cartProduct.price,
          vendorID: cartProduct.vendorID,
          quantity: qun,
        ));
      } else {
        await cartDatabase.removeProduct(cartProduct.id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Failed to update quantity".tr()),
          backgroundColor: AppThemeData.error500,
        ));
      }
    }
  }

  List<Map<String, dynamic>> _getActiveSpecialDiscounts() {
    if (vendorModel == null ||
        !specialDiscountEnable ||
        !vendorModel!.specialDiscountEnable) {
      return [];
    }

    final now = DateTime.now();
    final currentDay = DateFormat('EEEE', 'en_US').format(now);
    final dateStr = DateFormat('dd-MM-yyyy').format(now);
    final List<Map<String, dynamic>> active = [];

    for (final dayDiscount in vendorModel!.specialDiscount) {
      if (dayDiscount.day != currentDay) continue;
      if (dayDiscount.timeslot == null || dayDiscount.timeslot!.isEmpty) continue;

      for (final slot in dayDiscount.timeslot!) {
        if (slot.discount_type != "delivery") continue;

        try {
          final start = DateFormat("dd-MM-yyyy HH:mm")
              .parse('$dateStr ${slot.from}');
          final end = DateFormat("dd-MM-yyyy HH:mm")
              .parse('$dateStr ${slot.to}');
          if (!isCurrentDateInRange(start, end)) continue;
        } catch (_) {
          continue;
        }

        if (slot.orderType != null && slot.orderType!.isNotEmpty) {
          final currentOrderType =
              selctedOrderTypeValue == "Delivery" ? "Delivery" : "Takeaway";
          if (slot.orderType != currentOrderType) continue;
        }

        final discountValue = double.tryParse(slot.discount ?? '0') ?? 0;
        final isPercentage = slot.type == "percentage";
        final applicableAmount =
            double.tryParse(slot.applicableAmount ?? '0') ?? 0;
        final actualAmount =
            isPercentage ? (subTotal * discountValue / 100) : discountValue;

        String validTill = slot.to ?? '';
        try {
          final parsedTime = DateFormat("HH:mm").parse(validTill);
          validTill = DateFormat("hh:mm a").format(parsedTime);
        } catch (_) {}

        active.add({
          'discountValue': discountValue,
          'isPercentage': isPercentage,
          'applicableAmount': applicableAmount,
          'actualAmount': actualAmount,
          'validTill': validTill,
        });
      }
    }

    active.sort((a, b) =>
        (b['actualAmount'] as double).compareTo(a['actualAmount'] as double));
    return active;
  }

  sheet() {
    final dark = isDarkMode(context);
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgSecondary : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: FutureBuilder<List<OfferModel>>(
        future: coupon,
        initialData: const [],
        builder: (ctx, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator.adaptive()),
            );
          }

          if (vendorID.isEmpty && cartProducts.isNotEmpty) {
            vendorID = cartProducts.first.vendorID;
          }

          final allCoupons = (snapshot.data ?? [])
              .where((c) =>
                  vendorID == c.storeId ||
                  c.storeId == null ||
                  (c.storeId?.isEmpty ?? true))
              .toList();

          final applicableCoupons = allCoupons.where((c) {
            final minAmt = double.tryParse(c.applicableAmount ?? '0') ?? 0;
            return subTotal >= minAmt;
          }).toList();

          final otherCoupons = allCoupons.where((c) {
            final minAmt = double.tryParse(c.applicableAmount ?? '0') ?? 0;
            return subTotal < minAmt;
          }).toList();

          final activeSpecialDiscounts = _getActiveSpecialDiscounts();

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: dark
                          ? AppThemeData.darkBorderPrimary
                          : AppThemeData.neutral300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Coupons".tr(),
                            style: AppTypography.h5.copyWith(
                              fontWeight: FontWeight.w700,
                              color: dark
                                  ? AppThemeData.darkTextPrimary
                                  : AppThemeData.neutral900,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: dark
                                    ? AppThemeData.darkBgTertiary
                                    : AppThemeData.neutral100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.close,
                                size: 18,
                                color: dark
                                    ? AppThemeData.darkTextSecondary
                                    : AppThemeData.neutral600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Manual entry ──
                      Text(
                        "Enter Coupon Code".tr(),
                        style: AppTypography.labelMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: dark
                              ? AppThemeData.darkTextPrimary
                              : AppThemeData.neutral800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: txt,
                              textCapitalization: TextCapitalization.characters,
                              style: AppTypography.labelMedium.copyWith(
                                color: dark
                                    ? AppThemeData.darkTextPrimary
                                    : AppThemeData.neutral900,
                                letterSpacing: 1.5,
                              ),
                              decoration: InputDecoration(
                                hintText: "e.g. GET30",
                                hintStyle: AppTypography.labelMedium.copyWith(
                                  color: dark
                                      ? AppThemeData.darkTextTertiary
                                      : AppThemeData.neutral400,
                                  letterSpacing: 0,
                                ),
                                filled: true,
                                fillColor: dark
                                    ? AppThemeData.darkBgTertiary
                                    : AppThemeData.neutral50,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: dark
                                        ? AppThemeData.darkBorderSecondary
                                        : AppThemeData.neutral200,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: AppThemeData.primary500,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppThemeData.primary500,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                            ),
                            onPressed: () => _applyManualCoupon(
                                snapshot.data ?? [], ctx),
                            child: Text(
                              "Apply".tr(),
                              style: AppTypography.labelMedium.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      Container(
                          height: 1,
                          color: dark
                              ? AppThemeData.darkBorderSecondary
                              : AppThemeData.neutral100),
                      const SizedBox(height: 20),

                      // ── Applicable coupons ──
                      if (applicableCoupons.isNotEmpty) ...[
                        Row(
                          children: [
                            Container(
                              width: 4,
                              height: 16,
                              decoration: BoxDecoration(
                                color: AppThemeData.success400,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Applicable Coupons".tr(),
                              style: AppTypography.labelMedium.copyWith(
                                fontWeight: FontWeight.w700,
                                color: dark
                                    ? AppThemeData.darkTextPrimary
                                    : AppThemeData.neutral800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...applicableCoupons.map(
                          (c) => _couponCard(c,
                              applicable: true, sheetCtx: ctx),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── Other coupons ──
                      if (otherCoupons.isNotEmpty) ...[
                        Row(
                          children: [
                            Container(
                              width: 4,
                              height: 16,
                              decoration: BoxDecoration(
                                color: dark
                                    ? AppThemeData.darkBorderPrimary
                                    : AppThemeData.neutral300,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Other Available Coupons".tr(),
                              style: AppTypography.labelMedium.copyWith(
                                fontWeight: FontWeight.w700,
                                color: dark
                                    ? AppThemeData.darkTextSecondary
                                    : AppThemeData.neutral500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...otherCoupons.map(
                          (c) => _couponCard(c,
                              applicable: false, sheetCtx: ctx),
                        ),
                      ],

                      // ── Special Discounts ──
                      if (activeSpecialDiscounts.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Container(
                            height: 1,
                            color: dark
                                ? AppThemeData.darkBorderSecondary
                                : AppThemeData.neutral100),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Container(
                              width: 4,
                              height: 16,
                              decoration: BoxDecoration(
                                color: AppThemeData.warning400,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Special Discounts".tr(),
                              style: AppTypography.labelMedium.copyWith(
                                fontWeight: FontWeight.w700,
                                color: dark
                                    ? AppThemeData.darkTextPrimary
                                    : AppThemeData.neutral800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: AppThemeData.success400
                                .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppThemeData.success400
                                  .withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.auto_awesome_rounded,
                                size: 14,
                                color: AppThemeData.success400,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  "Automatically Added Best Offer".tr(),
                                  style: AppTypography.caption.copyWith(
                                    color: AppThemeData.success400,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...activeSpecialDiscounts.asMap().entries.map(
                              (e) => _specialDiscountCard(
                                e.value,
                                isBest: e.key == 0,
                              ),
                            ),
                      ],

                      // Empty state
                      if (allCoupons.isEmpty && activeSpecialDiscounts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.local_offer_outlined,
                                  size: 48,
                                  color: dark
                                      ? AppThemeData.darkTextTertiary
                                      : AppThemeData.neutral300,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  "No coupons available".tr(),
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: dark
                                        ? AppThemeData.darkTextSecondary
                                        : AppThemeData.neutral500,
                                  ),
                                ),
                              ],
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

  Widget _couponCard(OfferModel offer,
      {required bool applicable, required BuildContext sheetCtx}) {
    final dark = isDarkMode(context);
    final isApplied = couponId == offer.offerId;
    final isPercentage = offer.discountTypeOffer == 'Percentage' ||
        offer.discountTypeOffer == 'Percent';
    final discountLabel = isPercentage
        ? "${offer.discountOffer}% OFF"
        : "${amountShow(amount: offer.discountOffer ?? '0')} OFF";
    final minAmt = double.tryParse(offer.applicableAmount ?? '0') ?? 0;
    final hasMinAmt = minAmt > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgTertiary : AppThemeData.neutral50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isApplied
              ? AppThemeData.success400
              : (applicable
                  ? AppThemeData.primary200
                  : (dark
                      ? AppThemeData.darkBorderSecondary
                      : AppThemeData.neutral200)),
          width: isApplied ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Code chip
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: applicable
                          ? AppThemeData.primary500.withValues(alpha: 0.10)
                          : (dark
                              ? AppThemeData.darkBgSecondary
                              : AppThemeData.neutral100),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: applicable
                            ? AppThemeData.primary200
                            : (dark
                                ? AppThemeData.darkBorderSecondary
                                : AppThemeData.neutral300),
                      ),
                    ),
                    child: Text(
                      offer.offerCode ?? '',
                      style: AppTypography.labelSmall.copyWith(
                        fontWeight: FontWeight.w800,
                        color: applicable
                            ? AppThemeData.primary500
                            : (dark
                                ? AppThemeData.darkTextTertiary
                                : AppThemeData.neutral500),
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Discount description
                  Text(
                    hasMinAmt
                        ? "Get $discountLabel on orders above ${amountShow(amount: offer.applicableAmount!)}"
                        : "Get $discountLabel on your order",
                    style: AppTypography.bodySmall.copyWith(
                      color: dark
                          ? AppThemeData.darkTextPrimary
                          : AppThemeData.neutral800,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (offer.descriptionOffer != null &&
                      offer.descriptionOffer!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      offer.descriptionOffer!,
                      style: AppTypography.caption.copyWith(
                        color: dark
                            ? AppThemeData.darkTextSecondary
                            : AppThemeData.neutral500,
                      ),
                    ),
                  ],
                  // Unlock hint for non-applicable coupons
                  if (!applicable && hasMinAmt) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.lock_outline_rounded,
                            size: 12, color: AppThemeData.warning400),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            "Add ${amountShow(amount: (minAmt - subTotal).toStringAsFixed(2))} more to unlock",
                            style: AppTypography.caption.copyWith(
                                color: AppThemeData.warning400),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (applicable) ...[
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => _applyListCoupon(offer, sheetCtx),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isApplied
                        ? AppThemeData.success400
                        : AppThemeData.primary500,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isApplied ? "Applied".tr() : "Apply".tr(),
                    style: AppTypography.labelSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _specialDiscountCard(Map<String, dynamic> discount,
      {required bool isBest}) {
    final dark = isDarkMode(context);
    final isPercentage = discount['isPercentage'] as bool;
    final discountValue = discount['discountValue'] as double;
    final applicableAmount = discount['applicableAmount'] as double;
    final validTill = discount['validTill'] as String;

    final discountLabel = isPercentage
        ? "Get ${discountValue.toStringAsFixed(0)}% OFF"
        : "Flat ${amountShow(amount: discountValue.toStringAsFixed(2))} OFF";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgTertiary : AppThemeData.warning50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isBest
              ? AppThemeData.warning300
              : (dark
                  ? AppThemeData.darkBorderPrimary
                  : AppThemeData.warning200),
          width: isBest ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppThemeData.warning400.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  isBest ? "🏆" : "🔥",
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isBest) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: BoxDecoration(
                        color: AppThemeData.warning400.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        "Best Offer",
                        style: AppTypography.caption.copyWith(
                          color: AppThemeData.warning400,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  Text(
                    discountLabel,
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: dark
                          ? AppThemeData.darkTextPrimary
                          : AppThemeData.neutral900,
                    ),
                  ),
                  if (applicableAmount > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      "On orders above ${amountShow(amount: applicableAmount.toStringAsFixed(2))}",
                      style: AppTypography.caption.copyWith(
                        color: dark
                            ? AppThemeData.darkTextSecondary
                            : AppThemeData.neutral600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 12,
                        color: dark
                            ? AppThemeData.darkTextTertiary
                            : AppThemeData.neutral500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "Valid till $validTill",
                        style: AppTypography.caption.copyWith(
                          color: dark
                              ? AppThemeData.darkTextTertiary
                              : AppThemeData.neutral500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppThemeData.success400.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "Auto",
                style: AppTypography.caption.copyWith(
                  color: AppThemeData.success400,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _applyListCoupon(OfferModel offer, BuildContext sheetCtx) {
    if (couponId.isNotEmpty && couponId != offer.offerId) {
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            "Replace Coupon?".tr(),
            style: AppTypography.h6.copyWith(fontWeight: FontWeight.w700),
          ),
          content: Text(
            "Only one coupon can be used at a time. Replace the current coupon?"
                .tr(),
            style: AppTypography.bodySmall,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(
                "Cancel".tr(),
                style: AppTypography.labelMedium
                    .copyWith(color: AppThemeData.neutral500),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppThemeData.primary500,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(dialogCtx);
                _doApplyCoupon(offer, sheetCtx);
              },
              child: Text("Replace".tr(),
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } else {
      _doApplyCoupon(offer, sheetCtx);
    }
  }

  void _applyManualCoupon(List<OfferModel> coupons, BuildContext sheetCtx) {
    if (txt.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Please enter a coupon code".tr()),
        backgroundColor: AppThemeData.primary500,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    if (vendorID.isEmpty && cartProducts.isNotEmpty) {
      vendorID = cartProducts.first.vendorID;
    }

    OfferModel? found;
    for (final c in coupons) {
      if (vendorID == c.storeId ||
          c.storeId == null ||
          (c.storeId?.isEmpty ?? true)) {
        if (txt.text.trim().toUpperCase() ==
            (c.offerCode ?? '').toUpperCase()) {
          found = c;
          break;
        }
      }
    }

    if (found == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            "Invalid coupon code or not applicable for this store".tr()),
        backgroundColor: AppThemeData.primary500,
        behavior: SnackBarBehavior.floating,
      ));
      txt.clear();
      return;
    }

    final minAmt = double.tryParse(found.applicableAmount ?? '0') ?? 0;
    if (subTotal < minAmt) {
      Navigator.pop(sheetCtx);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            "Subtotal must be at least ${amountShow(amount: found.applicableAmount!)}"),
        backgroundColor: AppThemeData.primary500,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    if (couponId.isNotEmpty && couponId != found.offerId) {
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            "Replace Coupon?".tr(),
            style: AppTypography.h6.copyWith(fontWeight: FontWeight.w700),
          ),
          content: Text(
            "Only one coupon can be used at a time. Replace the current coupon?"
                .tr(),
            style: AppTypography.bodySmall,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(
                "Cancel".tr(),
                style: AppTypography.labelMedium
                    .copyWith(color: AppThemeData.neutral500),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppThemeData.primary500,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(dialogCtx);
                _doApplyCoupon(found!, sheetCtx);
              },
              child: Text("Replace".tr(),
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } else {
      _doApplyCoupon(found, sheetCtx);
    }
  }

  void _doApplyCoupon(OfferModel offer, BuildContext sheetCtx) {
    setState(() {
      final isPercentage = offer.discountTypeOffer == 'Percentage' ||
          offer.discountTypeOffer == 'Percent';
      if (isPercentage) {
        percentage = double.parse(offer.discountOffer!);
        type = 0.0;
      } else {
        type = double.parse(offer.discountOffer!);
        percentage = 0.0;
      }
      couponId = offer.offerId!;
      txt.text = offer.offerCode ?? '';
    });
    Navigator.pop(sheetCtx);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("Coupon applied successfully!".tr()),
      backgroundColor: Colors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Notesheet() {
    final dark = isDarkMode(context);
    return Container(
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgSecondary : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: dark
                      ? AppThemeData.darkBorderPrimary
                      : AppThemeData.neutral300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: dark
                            ? const Color(0xFF2A2218)
                            : const Color(0xFFFFF8EC),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.edit_note_rounded,
                          color: Color(0xFFE89B2F), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Order Note".tr(),
                          style: AppTypography.h6.copyWith(
                            fontWeight: FontWeight.w700,
                            color: dark
                                ? AppThemeData.darkTextPrimary
                                : AppThemeData.neutral900,
                          ),
                        ),
                        Text(
                          "Visible only to the restaurant".tr(),
                          style: AppTypography.caption.copyWith(
                            color: dark
                                ? AppThemeData.darkTextTertiary
                                : AppThemeData.neutral400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Text field
                Container(
                  decoration: BoxDecoration(
                    color: dark
                        ? AppThemeData.darkBgPrimary
                        : AppThemeData.neutral50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: dark
                          ? AppThemeData.darkBorderSecondary
                          : AppThemeData.neutral200,
                    ),
                  ),
                  child: TextField(
                    controller: noteController,
                    maxLines: 4,
                    maxLength: 200,
                    style: AppTypography.bodyMedium.copyWith(
                      color: dark ? Colors.white : AppThemeData.neutral900,
                      height: 1.6,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          "e.g. No onions, extra spicy, ring the bell...".tr(),
                      hintStyle: AppTypography.bodyMedium.copyWith(
                        color: dark
                            ? AppThemeData.darkTextTertiary
                            : AppThemeData.neutral400,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                      counterStyle: AppTypography.caption.copyWith(
                        color: dark
                            ? AppThemeData.darkTextTertiary
                            : AppThemeData.neutral400,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {});
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppThemeData.primary500,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      elevation: 0,
                    ),
                    child: Text(
                      "Save Note".tr(),
                      style: AppTypography.labelLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCustomTipSheet(BuildContext ctx) {
    final dark = isDarkMode(ctx);
    _textFieldController.clear();
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 32),
          decoration: BoxDecoration(
            color: dark ? AppThemeData.darkBgSecondary : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, -4))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: dark
                        ? AppThemeData.darkBorderPrimary
                        : AppThemeData.neutral300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.volunteer_activism_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Custom Tip Amount".tr(),
                          style: TextStyle(
                            fontSize: 17,
                            fontFamily: AppThemeData.bold,
                            color: dark
                                ? AppThemeData.darkTextPrimary
                                : AppThemeData.neutral900,
                          ),
                        ),
                        Text(
                          "Enter any amount you'd like to tip".tr(),
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: AppThemeData.regular,
                            color: dark
                                ? AppThemeData.darkTextSecondary
                                : AppThemeData.neutral500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _textFieldController,
                autofocus: true,
                textInputAction: TextInputAction.done,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(
                  fontSize: 32,
                  fontFamily: AppThemeData.bold,
                  color: dark
                      ? AppThemeData.darkTextPrimary
                      : AppThemeData.neutral900,
                ),
                decoration: InputDecoration(
                  hintText: "0.00",
                  hintStyle: TextStyle(
                    color: dark
                        ? AppThemeData.darkTextTertiary
                        : AppThemeData.neutral400,
                    fontSize: 32,
                    fontFamily: AppThemeData.bold,
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                        color: dark
                            ? AppThemeData.darkBorderSecondary
                            : AppThemeData.neutral300,
                        width: 1.5),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide:
                        BorderSide(color: AppThemeData.primary500, width: 2.5),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(_),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: dark
                            ? AppThemeData.darkTextSecondary
                            : AppThemeData.neutral600,
                        side: BorderSide(
                            color: dark
                                ? AppThemeData.darkBorderPrimary
                                : AppThemeData.neutral300),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text("Cancel".tr(),
                          style: const TextStyle(
                              fontFamily: AppThemeData.semiBold, fontSize: 15)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        final val = _textFieldController.text.trim();
                        setState(() {
                          if (val.isEmpty) {
                            isTipSelected3 = false;
                            tipValue = 0;
                          } else {
                            isTipSelected3 = true;
                            tipValue = double.tryParse(val) ?? 0;
                            isTipSelected = false;
                            isTipSelected1 = false;
                            isTipSelected2 = false;
                          }
                        });
                        Navigator.pop(_);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppThemeData.primary500,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: Text("Apply Tip".tr(),
                          style: const TextStyle(
                              fontSize: 15,
                              fontFamily: AppThemeData.semiBold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> getPrefData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey("musics_key")) {
      final String musicsString = prefs.getString('musics_key')!;
      if (musicsString.isNotEmpty) {
        lstExtras = AddAddonsDemo.decode(musicsString);
        for (var element in lstExtras) {
          commaSepratedAddOns.add(element.name!);
        }
        commaSepratedAddOnsString = commaSepratedAddOns.join(", ");
      }
    }

    // Simplified tax fetching - just use the global tax data we already fetched
    print('Using global tax data from getTaxData()');
  }

  Future<void> setPrefData() async {
    SharedPreferences sp = await SharedPreferences.getInstance();

    sp.setString("musics_key", "");
    sp.setString("addsize", "");
  }
}

Widget _buildChip(String label, int attributesOptionIndex,
    {bool isDark = false}) {
  return Container(
    decoration: BoxDecoration(
      color: isDark ? AppThemeData.darkBgTertiary : AppThemeData.neutral100,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: isDark ? AppThemeData.darkBorderSecondary : AppThemeData.neutral200,
        width: 0.6,
      ),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: isDark ? AppThemeData.darkTextSecondary : AppThemeData.neutral600,
      ),
    ),
  );
}

Widget dashedSeparator([BuildContext? context]) {
  return DottedBorder(
    dashPattern: [5, 4],
    color: context != null && isDarkMode(context)
        ? AppThemeData.darkTextTertiary
        : AppThemeData.neutral400,
    strokeWidth: 1,
    borderType: BorderType.RRect,
    radius: Radius.circular(0),
    padding: EdgeInsets.zero,
    child: SizedBox(
      width: double.infinity,
      height: 0,
    ),
  );
}
   
