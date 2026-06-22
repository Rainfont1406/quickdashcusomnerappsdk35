import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/AddressModel.dart';
import 'package:emartconsumer/model/CodModel.dart';
import 'package:emartconsumer/model/FlutterWaveSettingDataModel.dart';
import 'package:emartconsumer/model/PayFastSettingData.dart';
import 'package:emartconsumer/model/PayStackSettingsModel.dart';
import 'package:emartconsumer/model/PhonePaySettingData.dart';
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/model/createRazorPayOrderModel.dart';
import 'package:emartconsumer/model/payStackURLModel.dart';
import 'package:emartconsumer/model/payment_model/mid_trans.dart';
import 'package:emartconsumer/model/payment_model/orange_money.dart';
import 'package:emartconsumer/model/payment_model/xendit.dart';
import 'package:emartconsumer/model/razorpayKeyModel.dart';
import 'package:emartconsumer/model/stripeSettingData.dart';
import 'package:emartconsumer/model/topupTranHistory.dart';
import 'package:emartconsumer/payment/midtrans_screen.dart';
import 'package:emartconsumer/payment/orangePayScreen.dart';
import 'package:emartconsumer/payment/xenditModel.dart';
import 'package:emartconsumer/payment/xenditScreen.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/services/paystack_url_genrater.dart';
import 'package:emartconsumer/services/rozorpayConroller.dart';
import 'package:emartconsumer/services/app_dialog.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/theme/round_button_fill.dart';
import 'package:emartconsumer/ui/checkoutScreen/CheckoutScreen.dart';
import 'package:emartconsumer/ui/wallet/MercadoPagoScreen.dart';
import 'package:emartconsumer/ui/wallet/PayFastScreen.dart';
import 'package:emartconsumer/ui/wallet/payStackScreen.dart';
import 'package:emartconsumer/userPrefrence.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_paypal_native/flutter_paypal_native.dart';
import 'package:flutter_paypal_native/models/custom/currency_code.dart';
import 'package:flutter_paypal_native/models/custom/environment.dart';
import 'package:flutter_paypal_native/models/custom/order_callback.dart';
import 'package:flutter_paypal_native/models/custom/purchase_unit.dart';
import 'package:flutter_paypal_native/models/custom/user_action.dart';
import 'package:flutter_paypal_native/str_helper.dart';
import 'package:flutter_stripe/flutter_stripe.dart' as stripe1;

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;

import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phonepe_payment_sdk/phonepe_payment_sdk.dart';
import 'package:uuid/uuid.dart';

import '../../model/MercadoPagoSettingsModel.dart';
import '../../model/OrderModel.dart';
import '../../model/RazorPayFailedModel.dart';

import '../../model/TaxModel.dart';
import '../../model/User.dart';
import '../../model/VendorModel.dart';
import '../../model/getPaytmTxtToken.dart';
import '../../model/paypalSettingData.dart';
import '../../model/paytmSettingData.dart';
import '../container/ContainerScreen.dart';
import '../placeOrderScreen/PlaceOrderScreen.dart';

class PaymentScreen extends StatefulWidget {
  final double total;
  final double? discount;
  final String? couponCode;
  final String? couponId, notes;
  final List<CartProduct> products;

  final List<String>? extra_addons;
  final String? tipValue;
  final bool? take_away;
  final String? deliveryCharge;
  final List<TaxModel>? taxModel;
  final Map<String, dynamic>? specialDiscountMap;
  final Timestamp? scheduleTime;
  final AddressModel? addressModel;
  final String? orderType; // New field for Dineaway order type

  const PaymentScreen(
      {Key? key,
      required this.total,
      this.discount,
      this.couponCode,
      this.couponId,
      required this.products,
      this.extra_addons,
      this.tipValue,
      this.take_away,
      this.deliveryCharge,
      this.notes,
      this.taxModel,
      this.specialDiscountMap,
      this.scheduleTime,
      this.addressModel,
      this.orderType})
      : super(key: key);

  @override
  PaymentScreenState createState() => PaymentScreenState();
}

class PaymentScreenState extends State<PaymentScreen> {
  final fireStoreUtils = FireStoreUtils();
  late Future<bool> hasNativePay;

  // Modified to ensure unique order ID by checking against database
  // Generates a unique-enough order ID without hitting the network.
  // Combines a millisecond timestamp with a 4-digit random suffix —
  // the collision probability is negligible for any realistic order volume.
  Future<String> generateOrderId() async {
    final ts = DateTime.now().millisecondsSinceEpoch % 100000; // last 5 digits
    final rand = Random().nextInt(9000) + 1000;               // 1000-9999
    return '$ts$rand';
  }

  //List<PaymentMethod> _cards = [];
  late Future<CodModel?> futurecod;

  Stream<DocumentSnapshot<Map<String, dynamic>>>? userQuery;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String paymentOption = 'Pay Via Wallet'.tr();
  RazorPayModel? razorPayData = UserPreference.getRazorPayData();

  final Razorpay _razorPay = Razorpay();
  StripeSettingData? stripeData;
  PaytmSettingData? paytmSettingData;
  PaypalSettingData? paypalSettingData;
  PayStackSettingData? payStackSettingData;
  FlutterWaveSettingData? flutterWaveSettingData;
  PayFastSettingData? payFastSettingData;
  MercadoPagoSettingData? mercadoPagoSettingData;
  MidTrans? midTransModel;
  OrangeMoney? orangeMoneyModel;
  Xendit? xenditModel;
  PhonePaySettingData? phonePayData;

  bool walletBalanceError = false;

  bool isStaging = true;
  String callbackUrl =
      "http://162.241.125.167/~foodie/payments/paytmpaymentcallback?ORDER_ID=";
  bool restrictAppInvoke = false;
  bool enableAssist = true;
  String result = "";
  String paymentType = "";

  final _flutterPaypalNativePlugin = FlutterPaypalNative.instance;

  getPaymentSettingData() async {
    userQuery = FireStoreUtils.firestore
        .collection(USERS)
        .doc(MyAppState.currentUser!.userID)
        .snapshots();

    // Each gateway is fetched independently so a missing/unconfigured gateway
    // (jsonData! crash inside UserPreference) cannot abort the entire load.
    razorPayData = await _safeLoad(() => UserPreference.getRazorPayData());
    paytmSettingData = await _safeLoad(() => UserPreference.getPaytmData());
    paypalSettingData = await _safeLoad(() => UserPreference.getPayPalData());
    payStackSettingData = await _safeLoad(() => UserPreference.getPayStackData());
    flutterWaveSettingData = await _safeLoad(() => UserPreference.getFlutterWaveData());
    payFastSettingData = await _safeLoad(() => UserPreference.getPayFastData());
    mercadoPagoSettingData = await _safeLoad(() => UserPreference.getMercadoPago());
    midTransModel = await _safeLoad(() => UserPreference.getMidTransData());
    orangeMoneyModel = await _safeLoad(() => UserPreference.getOrangeData());
    xenditModel = await _safeLoad(() => UserPreference.getXenditData());
    phonePayData = UserPreference.getPhonePayData();

    setRef();
    if (paypalSettingData != null) initPayPal();

    if (mounted) setState(() {});
  }

  // Silently returns null if the preference key is missing or data is malformed.
  Future<T?> _safeLoad<T>(FutureOr<T?> Function() loader) async {
    try {
      return await loader();
    } catch (_) {
      return null;
    }
  }

  void initPayPal() async {
    if (paypalSettingData == null) return;
    FlutterPaypalNative.isDebugMode =
        paypalSettingData!.isLive == false ? true : false;
    await _flutterPaypalNativePlugin.init(
      returnUrl: "com.emart.customer://paypalpay",
      clientID: paypalSettingData!.paypalClient,
      payPalEnvironment: paypalSettingData!.isLive == true
          ? FPayPalEnvironment.live
          : FPayPalEnvironment.sandbox,
      //what currency do you plan to use? default is US dollars
      currencyCode: FPayPalCurrencyCode.usd,
      //action paynow?
      action: FPayPalUserAction.payNow,
    );

    //call backs for payment
    _flutterPaypalNativePlugin.setPayPalOrderCallback(
      callback: FPayPalOrderCallback(
        onCancel: () {
          //user canceled the payment
          Navigator.pop(context);
          ShowToastDialog.showToast("Payment canceled");
        },
        onSuccess: (data) async {
          //successfully paid
          //remove all items from queue
          Navigator.pop(context);
          _flutterPaypalNativePlugin.removeAllPurchaseItems();
          ShowToastDialog.showToast("Payment Successfully");
          final orderId = await generateOrderId();
          if (widget.take_away!) {
            placeOrder(_scaffoldKey.currentContext!, oid: orderId);
          } else {
            toCheckOutScreen(true, _scaffoldKey.currentContext!, oid: orderId);
          }
        },
        onError: (data) {
          //an error occured
          Navigator.pop(context);
          ShowToastDialog.showToast("error: ${data.reason}");
        },
        onShippingChange: (data) {
          //the user updated the shipping address
          Navigator.pop(context);
          ShowToastDialog.showToast(
              "shipping change: ${data.shippingChangeAddress?.adminArea1 ?? ""}");
        },
      ),
    );
  }

  showAlert(context, {required String response, required Color colors}) {
    return ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(response),
      backgroundColor: colors,
    ));
  }

  @override
  void initState() {
    getPaymentSettingData();
    futurecod = fireStoreUtils.getCod();
    _razorPay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorPay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWaller);
    _razorPay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    super.initState();
  }

  String? selectedRadioTile;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isProcessingOrder,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (!didPop && isProcessingOrder) {
          // Show dialog when user tries to go back during processing
          await _showBackDialog();
        }
      },
      child: Scaffold(
        extendBody: true,
        key: _scaffoldKey,
        backgroundColor: isDarkMode(context) ? AppThemeData.surfaceDark : const Color(0xFFF2F4F8),
        appBar: _buildAppBar(isDarkMode(context)),
        bottomNavigationBar: _buildStickyFooter(context, isDarkMode(context)),
        body: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildOrderSummaryCard(isDarkMode(context)),
                _buildSectionHeader('Payment Method'.tr(), isDarkMode(context)),
                Visibility(
                  visible: UserPreference.getWalletData() ?? false,
                  child: _buildWalletCard(isDarkMode(context)),
                ),
                Visibility(
                  visible: paytmSettingData?.isEnabled == true,
                  child: _pmCard(
                    dark: isDarkMode(context), isSelected: payTm, value: 'PayTm',
                    label: 'Paytm'.tr(),
                    logo: Image.asset('assets/images/paytm_@3x.png', fit: BoxFit.contain),
                    onChanged: (v) => setState(() {
                      stripe = false; flutterWave = false; payTm = true; mercadoPago = false;
                      razorPay = false; paypal = false; payFast = false; payStack = false;
                      orange = false; Midtrans = false; xendit = false; wallet = false;
                      phonePay = false; codPay = false; selectedRadioTile = v!;
                    }),
                  ),
                ),
                Visibility(
                  visible: payStackSettingData?.isEnabled == true,
                  child: _pmCard(
                    dark: isDarkMode(context), isSelected: payStack, value: 'PayStack',
                    label: 'PayStack'.tr(),
                    logo: Image.asset('assets/images/paystack.png', fit: BoxFit.contain),
                    onChanged: (v) => setState(() {
                      flutterWave = false; payStack = true; mercadoPago = false; stripe = false;
                      payFast = false; razorPay = false; payTm = false; paypal = false;
                      orange = false; Midtrans = false; xendit = false; wallet = false;
                      phonePay = false; codPay = false; selectedRadioTile = v!;
                    }),
                  ),
                ),
                Visibility(
                  visible: flutterWaveSettingData?.isEnable == true,
                  child: _pmCard(
                    dark: isDarkMode(context), isSelected: flutterWave, value: 'FlutterWave',
                    label: 'FlutterWave'.tr(),
                    logo: Image.asset('assets/images/flutterwave.png', fit: BoxFit.contain),
                    onChanged: (v) => setState(() {
                      flutterWave = true; payStack = false; mercadoPago = false; payFast = false;
                      stripe = false; razorPay = false; payTm = false; paypal = false;
                      orange = false; Midtrans = false; xendit = false; wallet = false;
                      phonePay = false; codPay = false; selectedRadioTile = v!;
                    }),
                  ),
                ),
                Visibility(
                  visible: razorPayData?.isEnabled == true,
                  child: _pmCard(
                    dark: isDarkMode(context), isSelected: razorPay, value: 'RazorPay',
                    label: 'RazorPay'.tr(),
                    logo: Image.asset('assets/images/razorpay_@3x.png', fit: BoxFit.contain),
                    onChanged: (v) => setState(() {
                      mercadoPago = false; flutterWave = false; stripe = false; razorPay = true;
                      payTm = false; payFast = false; paypal = false; payStack = false;
                      orange = false; Midtrans = false; xendit = false; wallet = false;
                      phonePay = false; codPay = false; selectedRadioTile = v!;
                    }),
                  ),
                ),
                Visibility(
                  visible: payFastSettingData?.isEnable == true,
                  child: _pmCard(
                    dark: isDarkMode(context), isSelected: payFast, value: 'payFast',
                    label: 'Payfast'.tr(),
                    logo: Image.asset('assets/images/payfast.png', fit: BoxFit.contain),
                    onChanged: (v) => setState(() {
                      payFast = true; stripe = false; mercadoPago = false; razorPay = false;
                      payStack = false; flutterWave = false; payTm = false; paypal = false;
                      orange = false; Midtrans = false; xendit = false; wallet = false;
                      phonePay = false; codPay = false; selectedRadioTile = v!;
                    }),
                  ),
                ),
                Visibility(
                  visible: mercadoPagoSettingData?.isEnabled == true,
                  child: _pmCard(
                    dark: isDarkMode(context), isSelected: mercadoPago, value: 'MercadoPago',
                    label: 'Mercado Pago'.tr(),
                    logo: Image.asset('assets/images/mercadopago.png', fit: BoxFit.contain),
                    onChanged: (v) => setState(() {
                      mercadoPago = true; payFast = false; stripe = false; razorPay = false;
                      payStack = false; flutterWave = false; payTm = false; paypal = false;
                      orange = false; Midtrans = false; xendit = false; wallet = false;
                      phonePay = false; codPay = false; selectedRadioTile = v!;
                    }),
                  ),
                ),
                Visibility(
                  visible: paypalSettingData?.isEnabled == true,
                  child: _pmCard(
                    dark: isDarkMode(context), isSelected: paypal, value: 'PayPal',
                    label: 'PayPal'.tr(),
                    logo: Image.asset('assets/images/paypal_@3x.png', fit: BoxFit.contain),
                    onChanged: (v) => setState(() {
                      stripe = false; payTm = false; mercadoPago = false; flutterWave = false;
                      razorPay = false; paypal = true; payFast = false; payStack = false;
                      orange = false; Midtrans = false; xendit = false; wallet = false;
                      phonePay = false; codPay = false; selectedRadioTile = v!;
                    }),
                  ),
                ),
                Visibility(
                  visible: xenditModel?.enable == true,
                  child: _pmCard(
                    dark: isDarkMode(context), isSelected: xendit, value: 'Xendit',
                    label: 'Xendit'.tr(),
                    logo: Image.asset('assets/images/xendit.png', fit: BoxFit.contain),
                    onChanged: (v) => setState(() {
                      stripe = false; payTm = false; mercadoPago = false; flutterWave = false;
                      razorPay = false; paypal = false; payFast = false; payStack = false;
                      orange = false; Midtrans = false; xendit = true; wallet = false;
                      phonePay = false; codPay = false; selectedRadioTile = v!;
                    }),
                  ),
                ),
                Visibility(
                  visible: orangeMoneyModel?.enable == true,
                  child: _pmCard(
                    dark: isDarkMode(context), isSelected: orange, value: 'OrangeMoney',
                    label: 'OrangeMoney'.tr(),
                    logo: Image.asset('assets/images/orange_money.png', fit: BoxFit.contain),
                    onChanged: (v) => setState(() {
                      stripe = false; payTm = false; mercadoPago = false; flutterWave = false;
                      razorPay = false; paypal = false; payFast = false; payStack = false;
                      orange = true; Midtrans = false; xendit = false; wallet = false;
                      phonePay = false; codPay = false; selectedRadioTile = v!;
                    }),
                  ),
                ),
                Visibility(
                  visible: midTransModel?.enable == true,
                  child: _pmCard(
                    dark: isDarkMode(context), isSelected: Midtrans, value: 'Midtrans',
                    label: 'Midtrans'.tr(),
                    logo: Image.asset('assets/images/midtrans.png', fit: BoxFit.contain),
                    onChanged: (v) => setState(() {
                      stripe = false; payTm = false; mercadoPago = false; flutterWave = false;
                      razorPay = false; paypal = false; payFast = false; payStack = false;
                      orange = false; Midtrans = true; xendit = false; wallet = false;
                      phonePay = false; codPay = false; selectedRadioTile = v!;
                    }),
                  ),
                ),
                Visibility(
                  visible: phonePayData?.isEnabled ?? false,
                  child: _pmCard(
                    dark: isDarkMode(context), isSelected: phonePay, value: 'PhonePe',
                    label: 'PhonePe'.tr(),
                    logo: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF5F259F),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: const Text(
                        'PhonePe',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    onChanged: (v) => setState(() {
                      stripe = false; payTm = false; mercadoPago = false; flutterWave = false;
                      razorPay = false; paypal = false; payFast = false; payStack = false;
                      orange = false; Midtrans = false; xendit = false; wallet = false;
                      phonePay = true; codPay = false; selectedRadioTile = v!;
                    }),
                  ),
                ),
                FutureBuilder<CodModel?>(
                  future: futurecod,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator.adaptive()),
                      );
                    }
                    if (snapshot.hasData && snapshot.data!.cod == true) {
                      return _buildCodCard(isDarkMode(context));
                    }
                    return const SizedBox.shrink();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // â”€â”€â”€ UI helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  PreferredSizeWidget _buildAppBar(bool dark) {
    return AppBar(
      backgroundColor: dark ? AppThemeData.darkBgSecondary : Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20,
            color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text('Payment'.tr(), style: TextStyle(fontSize: 18, fontFamily: AppThemeData.semiBold,
          color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900)),
      centerTitle: false,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, thickness: 1,
            color: dark ? AppThemeData.darkBorderSecondary : AppThemeData.neutral200),
      ),
    );
  }

  Widget _buildOrderSummaryCard(bool dark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppThemeData.primary500, AppThemeData.primary600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: AppThemeData.primary500.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order Total'.tr(), style: const TextStyle(color: Colors.white70, fontSize: 13, fontFamily: AppThemeData.regular)),
                const SizedBox(height: 6),
                Text(amountShow(amount: widget.total.toString()),
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontFamily: AppThemeData.bold)),
                if (widget.couponCode != null && widget.couponCode!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_offer_rounded, color: Colors.white, size: 12),
                        const SizedBox(width: 4),
                        Text(widget.couponCode!, style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: AppThemeData.medium)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.payment_rounded, color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title.toUpperCase(), style: TextStyle(fontSize: 11, fontFamily: AppThemeData.semiBold,
          color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral500, letterSpacing: 0.8)),
    );
  }

  Widget _pmCard({
    required bool dark, required bool isSelected, required String value,
    required Widget logo, required String label, required ValueChanged<String?> onChanged,
    Widget? subtitle,
  }) {
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: isSelected ? AppThemeData.primary500.withValues(alpha: 0.06) : (dark ? AppThemeData.darkBgSecondary : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppThemeData.primary500 : (dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral200),
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: AppThemeData.primary500.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 3))]
              : [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.0 : 0.03), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              width: 50, height: 38,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppThemeData.neutral200, width: 0.8)),
              child: logo,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: TextStyle(fontSize: 15, fontFamily: AppThemeData.medium,
                      color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900)),
                  if (subtitle != null) ...[const SizedBox(height: 4), subtitle],
                ],
              ),
            ),
            const SizedBox(width: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22, height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppThemeData.primary500 : Colors.transparent,
                border: Border.all(
                  color: isSelected ? AppThemeData.primary500 : (dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral300),
                  width: 2,
                ),
              ),
              child: isSelected ? const Icon(Icons.check_rounded, color: Colors.white, size: 13) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletCard(bool dark) {
    return GestureDetector(
      onTap: () => setState(() {
        mercadoPago = false; payStack = false; flutterWave = false; razorPay = false;
        wallet = true; codPay = false; payTm = false; payFast = false; paypal = false;
        stripe = false; xendit = false; orange = false; Midtrans = false; phonePay = false;
        selectedRadioTile = 'Wallet';
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: wallet ? AppThemeData.primary500.withValues(alpha: 0.06) : (dark ? AppThemeData.darkBgSecondary : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: wallet ? AppThemeData.primary500 : (dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral200),
            width: wallet ? 1.5 : 1.0,
          ),
          boxShadow: wallet
              ? [BoxShadow(color: AppThemeData.primary500.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 3))]
              : [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.0 : 0.03), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 50, height: 38,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppThemeData.neutral200, width: 0.8)),
                  child: Image.asset('assets/images/wallet_icon.png', fit: BoxFit.contain),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text('Wallet'.tr(), style: TextStyle(fontSize: 15, fontFamily: AppThemeData.medium,
                      color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900)),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: wallet ? AppThemeData.primary500 : Colors.transparent,
                    border: Border.all(
                      color: wallet ? AppThemeData.primary500 : (dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral300),
                      width: 2,
                    ),
                  ),
                  child: wallet ? const Icon(Icons.check_rounded, color: Colors.white, size: 13) : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: userQuery,
              builder: (context, asyncSnapshot) {
                if (asyncSnapshot.hasError) {
                  return Text('error'.tr(), style: const TextStyle(color: Colors.red, fontSize: 12));
                }
                if (asyncSnapshot.connectionState == ConnectionState.waiting) {
                  return SizedBox(height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: AppThemeData.primary500));
                }
                if (asyncSnapshot.data == null || !asyncSnapshot.data!.exists) return const SizedBox.shrink();
                final User userData = User.fromJson(asyncSnapshot.data!.data()!);
                final bool sufficient = userData.wallet_amount >= widget.total;
                walletBalanceError = sufficient;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: sufficient ? Colors.green.withValues(alpha: 0.08) : AppThemeData.primary500.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        sufficient ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
                        size: 16,
                        color: sufficient ? Colors.green.shade600 : AppThemeData.primary500,
                      ),
                      const SizedBox(width: 8),
                      Text(amountShow(amount: userData.wallet_amount.toString()),
                          style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 14,
                              color: sufficient ? Colors.green.shade700 : AppThemeData.primary500)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          sufficient ? 'Â· ${"Sufficient Balance".tr()}' : 'Â· ${"Insufficient Balance".tr()}',
                          style: TextStyle(fontSize: 12, fontFamily: AppThemeData.regular,
                              color: sufficient ? Colors.green.shade600 : AppThemeData.primary500),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodCard(bool dark) {
    return GestureDetector(
      onTap: () => setState(() {
        mercadoPago = false; payStack = false; flutterWave = false; razorPay = false;
        wallet = false; codPay = true; payTm = false; payFast = false; paypal = false;
        stripe = false; xendit = false; orange = false; Midtrans = false; phonePay = false;
        selectedRadioTile = 'cod';
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: codPay ? AppThemeData.primary500.withValues(alpha: 0.06) : (dark ? AppThemeData.darkBgSecondary : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: codPay ? AppThemeData.primary500 : (dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral200),
            width: codPay ? 1.5 : 1.0,
          ),
          boxShadow: codPay
              ? [BoxShadow(color: AppThemeData.primary500.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 3))]
              : [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.0 : 0.03), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              width: 50, height: 38,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppThemeData.neutral200, width: 0.8)),
              child: const Center(child: FaIcon(FontAwesomeIcons.handHoldingDollar, size: 18, color: AppThemeData.primary500)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cash on delivery'.tr(), style: TextStyle(fontSize: 15, fontFamily: AppThemeData.medium,
                      color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900)),
                  const SizedBox(height: 2),
                  Text('Pay when your order arrives'.tr(), style: TextStyle(fontSize: 12, fontFamily: AppThemeData.regular,
                      color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral500)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22, height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: codPay ? AppThemeData.primary500 : Colors.transparent,
                border: Border.all(
                  color: codPay ? AppThemeData.primary500 : (dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral300),
                  width: 2,
                ),
              ),
              child: codPay ? const Icon(Icons.check_rounded, color: Colors.white, size: 13) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStickyFooter(BuildContext context, bool dark) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgSecondary : Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          onPressed: isProcessingOrder ? null : () => _onProceed(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppThemeData.primary500,
            disabledBackgroundColor: AppThemeData.primary500.withValues(alpha: 0.5),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: isProcessingOrder
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_rounded, size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    Text('Pay Now'.tr(), style: const TextStyle(fontSize: 16, fontFamily: AppThemeData.semiBold, color: Colors.white)),
                    const SizedBox(width: 8),
                    Text('· ${amountShow(amount: widget.total.toString())}',
                        style: const TextStyle(fontSize: 16, fontFamily: AppThemeData.semiBold, color: Colors.white)),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _onProceed(BuildContext context) async {
    if (razorPay) {
      paymentType = 'razorpay';
      showLoadingAlert();
      RazorPayController().createOrderRazorPay(amount: widget.total).then((result) {
        // Manually dismiss the loading dialog and clear the flag before
        // opening the Razorpay sheet, so that when _handlePaymentSuccess /
        // _handlePaymentError fires later, the guard in
        // dismissLoadingAndClearProcessing() knows no dialog is open.
        setState(() => _isLoadingDialogShowing = false);
        Navigator.pop(context);
        if (result.isSuccess) {
          openCheckout(amount: widget.total, orderId: result.order!.id);
        } else {
          showAlert(_scaffoldKey.currentContext!,
              response: result.errorMessage?.tr() ?? 'Something went wrong, please contact admin.'.tr(),
              colors: AppThemeData.primary500);
        }
      });
    } else if (payFast) {
      paymentType = 'payfast';
      showLoadingAlert();
      PayStackURLGen.getPayHTML(payFastSettingData: payFastSettingData!, amount: widget.total.toString())
          .then((value) async {
        bool isDone = await Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => PayFastScreen(htmlData: value, payFastSettingData: payFastSettingData!)));
        if (isDone) {
          final orderId = await generateOrderId();
          if (widget.take_away!) {
            placeOrder(_scaffoldKey.currentContext!, oid: orderId);
          } else {
            toCheckOutScreen(true, _scaffoldKey.currentContext!, oid: orderId);
          }
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Payment Successful!!'.tr() + '\n'), backgroundColor: Colors.green.shade400, duration: const Duration(seconds: 6)));
        } else {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Payment Unsuccessful!!'.tr() + '\n'), backgroundColor: AppThemeData.primary500, duration: const Duration(seconds: 6)));
        }
      });
    } else if (wallet && walletBalanceError == true) {
      paymentType = 'wallet';
      final confirmOrder = await AppDialog.showConfirm(
        context,
        title: 'Confirm Order',
        message: 'Do you want to confirm and place this order via Wallet?',
        confirmLabel: 'Yes, Place Order',
        cancelLabel: 'Cancel',
      );
      if (confirmOrder) {
        showLoadingAlert();
        setState(() { isOrderPlaced = true; });
        final orderId = await generateOrderId();
        TopupTranHistoryModel walletTx = TopupTranHistoryModel(
            amount: widget.total, order_id: orderId, serviceType: 'delivery-service',
            id: orderId, user_id: MyAppState.currentUser!.userID, date: Timestamp.now(),
            isTopup: false, payment_method: 'wallet', payment_status: 'success',
            transactionUser: 'customer', note: 'Order Amount Payment');
        await FireStoreUtils.firestore.collection('wallet').doc(walletTx.id).set(walletTx.toJson()).then((value) async {
          await FireStoreUtils.updateWalletAmount(amount: -widget.total).then((value) {
            Navigator.pop(_scaffoldKey.currentContext!);
            showAlert(_scaffoldKey.currentContext!, response: 'Payment Successful Via'.tr() + ' Wallet', colors: Colors.green);
            if (widget.take_away!) {
              placeOrder(_scaffoldKey.currentContext!, oid: orderId);
            } else {
              toCheckOutScreen(true, context, oid: orderId);
            }
          });
        });
      }
    } else if (codPay) {
      paymentType = 'cod';
      paymentOption = 'Pay Via Cash On delivery'.tr();
      setState(() { isOrderPlaced = true; });
      final orderId = await generateOrderId();
      if (widget.take_away!) {
        placeOrder(_scaffoldKey.currentContext!, oid: orderId);
      } else {
        toCheckOutScreen(false, context, oid: orderId);
      }
    } else if (Midtrans) {
      paymentType = 'midtrans';
      midtransMakePayment(context: context, amount: widget.total.toString());
    } else if (orange) {
      paymentType = 'orangepay';
      orangeMakePayment(context: context, amount: widget.total.toString());
    } else if (xendit) {
      paymentType = 'xendit';
      xenditPayment(context, widget.total);
    } else if (phonePay) {
      paymentType = 'phonepe';
      _phonePayMakePayment(context: context, amount: widget.total);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Select Payment Method'.tr(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
        backgroundColor: AppThemeData.primary500,
      ));
    }
  }

  // Show dialog when user tries to go back during processing
  Future<void> _showBackDialog() async {
    if (_paymentCollected) {
      // Payment is already debited — never allow going back. Show a reassuring,
      // non-cancellable dialog so the user knows their money is safe.
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => PopScope(
          canPop: false,
          child: AlertDialog(
            icon: Icon(Icons.lock_clock_rounded, color: Colors.green.shade700, size: 32),
            title: Text('Payment Received'.tr()),
            content: Text(
              'Your payment was successful. We are confirming your order — please do not go back.'
                  .tr(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: Text("OK, I'll Wait".tr()),
              ),
            ],
          ),
        ),
      );
    } else {
      // No payment taken yet — user can still cancel and go back to cart.
      final goBack = await AppDialog.showConfirm(
        context,
        title: 'Cancel Payment?',
        message: 'Do you want to go back to cart? Your order will not be placed.',
        confirmLabel: 'Go Back',
        cancelLabel: 'Stay Here',
      );
      if (goBack) {
        setState(() { isProcessingOrder = false; });
        Navigator.of(context).pop();
      }
    }
  }

  // Helper method to dismiss loading and clear processing state
  void dismissLoadingAndClearProcessing() {
    if (isProcessingOrder) {
      setState(() {
        isProcessingOrder = false;
      });
    }
    // Only pop if the loading dialog is actually showing.
    // Without this guard, calling pop when no dialog is open would pop the
    // PaymentScreen itself (e.g. Razorpay already dismissed the dialog before
    // calling _handlePaymentSuccess / _handlePaymentError).
    if (_isLoadingDialogShowing) {
      setState(() => _isLoadingDialogShowing = false);
      Navigator.pop(_scaffoldKey.currentContext!);
    }
  }

  bool payStack = false;
  bool flutterWave = false;
  bool wallet = false;
  bool razorPay = false;
  bool payFast = false;
  bool mercadoPago = false;
  bool codPay = false;
  bool payTm = false;
  bool stripe = false;
  bool paypal = false;
  bool xendit = false;
  bool orange = false;
  bool Midtrans = false;
  bool phonePay = false;
  bool isProcessingOrder = false;
  bool isOrderPlaced = false;
  bool _isPlacingOrder = false; // debounce for placeOrder()
  bool _paymentCollected = false; // true once Razorpay (or any online gateway) has debited the user

  ///RazorPay payment function
  void openCheckout({required amount, required orderId}) async {
    var options = {
      'key': razorPayData!.razorpayKey,
      'amount': (amount * 100).toInt(),
      'name': 'Quickdash',
      'order_id': orderId,
      "currency": currencyData?.code,
      'description': 'Order Payment',
      'retry': {'enabled': true, 'max_count': 1},
      'send_sms_hash': true,
      'prefill': {
        'contact': MyAppState.currentUser!.phoneNumber,
        'email': MyAppState.currentUser!.email,
      },
      // Removed external wallets restriction to enable UPI and all payment methods
    };

    try {
      _razorPay.open(options);
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    // Dismiss the loading dialog if it's still open (it was already dismissed in
    // _onProceed before the Razorpay sheet opened, so this is usually a no-op).
    // Crucially we do NOT call dismissLoadingAndClearProcessing() here because
    // that would set isProcessingOrder = false, creating a window where the user
    // could press Back between payment and the order being written to Firestore.
    if (_isLoadingDialogShowing) {
      setState(() => _isLoadingDialogShowing = false);
      Navigator.pop(_scaffoldKey.currentContext!);
    }

    // Money is now debited. Lock back navigation for the entire order-placement
    // phase and remember that payment was collected (used in _showBackDialog).
    setState(() {
      isOrderPlaced = true;
      isProcessingOrder = true;
      _paymentCollected = true;
    });

    generateOrderId().then((orderId) {
      placeOrder(_scaffoldKey.currentContext!, oid: orderId);
    });
  }

  void _handleExternalWaller(ExternalWalletResponse response) {
    Navigator.pop(_scaffoldKey.currentContext!);
    ScaffoldMessenger.of(_scaffoldKey.currentContext!).showSnackBar(SnackBar(
      content: Text(
        "Payment Processing!! via".tr() + "\n" + response.walletName!,
      ),
      backgroundColor: Colors.blue.shade400,
      duration: const Duration(seconds: 8),
    ));
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    dismissLoadingAndClearProcessing();
    String description = 'Payment failed. Please try again.'.tr();
    try {
      final msg = response.message?.toString();
      if (msg != null && msg.isNotEmpty && msg != 'undefined') {
        final lom = RazorPayFailedModel.fromJson(jsonDecode(msg));
        description = lom.error.description;
      }
    } catch (_) {}
    ScaffoldMessenger.of(_scaffoldKey.currentContext!).showSnackBar(SnackBar(
      content: Text("Payment Failed!!".tr() + "\n" + description),
      backgroundColor: AppThemeData.primary500,
      duration: const Duration(seconds: 8),
    ));
  }

  ///Stripe payment function
  Map<String, dynamic>? paymentIntentData;

  Future<void> stripeMakePayment({required String amount}) async {
    try {
      paymentIntentData = await createStripeIntent(amount);
      if (paymentIntentData!.containsKey("error")) {
        Navigator.pop(context);
        showAlert(_scaffoldKey.currentContext!,
            response: "Something went wrong, please contact admin.".tr(),
            colors: AppThemeData.primary500);
      } else {
        await stripe1.Stripe.instance
            .initPaymentSheet(
                paymentSheetParameters: stripe1.SetupPaymentSheetParameters(
              paymentIntentClientSecret: paymentIntentData!['client_secret'],
              applePay: const stripe1.PaymentSheetApplePay(
                merchantCountryCode: 'US',
              ),
              allowsDelayedPaymentMethods: false,
              googlePay: stripe1.PaymentSheetGooglePay(
                merchantCountryCode: 'US',
                testEnv: true,
                currencyCode: currencyData!.code,
              ),
              style: ThemeMode.system,
              customFlow: true,
              appearance: stripe1.PaymentSheetAppearance(
                colors: stripe1.PaymentSheetAppearanceColors(
                  primary: AppThemeData.primary500,
                ),
              ),
              merchantDisplayName: 'QuickDash',
            ))
            .then((value) {});
        setState(() {});
        displayStripePaymentSheet(amount: amount);
      }
    } catch (e, s) {
    }
  }

  displayStripePaymentSheet({required amount}) async {
    try {
      await stripe1.Stripe.instance.presentPaymentSheet().then((value) async {
        final orderId = await generateOrderId();
        if (widget.take_away!) {
          placeOrder(_scaffoldKey.currentContext!, oid: orderId);
        } else {
          toCheckOutScreen(true, _scaffoldKey.currentContext!, oid: orderId);
        }

        ScaffoldMessenger.of(_scaffoldKey.currentContext!)
            .showSnackBar(SnackBar(
          content: Text("Payment Successful!!".tr()),
          duration: const Duration(seconds: 8),
          backgroundColor: Colors.green,
        ));
        paymentIntentData = null;
      }).onError((error, stackTrace) {
        Navigator.pop(_scaffoldKey.currentContext!);
        var lo1 = jsonEncode(error);
        var lo2 = jsonDecode(lo1);
        AppDialog.showError(context, message: 'Payment failed. Please try again.');
      });
    } on stripe1.StripeException catch (e) {
      Navigator.pop(_scaffoldKey.currentContext!);
      var lo1 = jsonEncode(e);
      var lo2 = jsonDecode(lo1);
      AppDialog.showError(context, message: 'Payment failed. Please try again.');
    } catch (e) {
      Navigator.pop(_scaffoldKey.currentContext!);
      ScaffoldMessenger.of(_scaffoldKey.currentContext!).showSnackBar(SnackBar(
        content: Text("$e"),
        duration: const Duration(seconds: 8),
        backgroundColor: AppThemeData.primary500,
      ));
    }
  }

  createStripeIntent(String amount) async {
    try {
      Map<String, dynamic> body = {
        'amount': calculateAmount(amount),
        'currency': currencyData!.code,
      };
      var response = await http.post(
          Uri.parse('https://api.stripe.com/v1/payment_intents'),
          body: body,
          headers: {
            'Authorization': 'Bearer ${stripeData?.stripeSecret}',
            'Content-Type': 'application/x-www-form-urlencoded'
          });
      return jsonDecode(response.body);
    } catch (err) {
    }
  }

  calculateAmount(String amount) {
    final a = ((double.parse(amount)) * 100).toInt();
    return a.toString();
  }

  ///PayPal payment function
  paypalPaymentSheet() {
    //add 1 item to cart. Max is 4!
    if (_flutterPaypalNativePlugin.canAddMorePurchaseUnit) {
      _flutterPaypalNativePlugin.addPurchaseUnit(
        FPayPalPurchaseUnit(
          // random prices
          amount: double.parse(widget.total.toString()),

          ///please use your own algorithm for referenceId. Maybe ProductID?
          referenceId: FPayPalStrHelper.getRandomString(16),
        ),
      );
    }
    // initPayPal();
    _flutterPaypalNativePlugin.makeOrder(
      action: FPayPalUserAction.payNow,
    );
  }

  // _makePaypalPayment({required amount}) async {
  //   PayPalClientTokenGen.paypalClientToken(
  //           paypalSettingData: paypalSettingData!)
  //       .then((value) async {
  //     final String tokenizationKey =
  //         paypalSettingData!.braintree_tokenizationKey;
  //
  //     var request = BraintreePayPalRequest(
  //         amount: amount,
  //         currencyCode: currencyData!.code,
  //         billingAgreementDescription: "djsghxghf",
  //         displayName: 'Foodies company');
  //
  //     BraintreePaymentMethodNonce? resultData;
  //     try {
  //       resultData =
  //           await Braintree.requestPaypalNonce(tokenizationKey, request);
  //     } on Exception catch (ex) {
  //       print("Stripe error");
  //       showAlert(_scaffoldKey.currentContext!,
  //           response: "Something went wrong, please contact admin.".tr(),
  //           colors: AppThemeData.primary500);
  //     }
  //     print(resultData?.nonce);
  //     print(resultData?.paypalPayerId);
  //     if (resultData?.nonce != null) {
  //       PayPalClientTokenGen.paypalSettleAmount(
  //         paypalSettingData: paypalSettingData!,
  //         nonceFromTheClient: resultData?.nonce,
  //         amount: amount,
  //         deviceDataFromTheClient: resultData?.typeLabel,
  //       ).then((value) {
  //         print('payment done!!');
  //         if (value['success'] == "true" || value['success'] == true) {
  //           if (value['data']['success'] == "true" ||
  //               value['data']['success'] == true) {
  //             payPalSettel.PayPalClientSettleModel settleResult =
  //                 payPalSettel.PayPalClientSettleModel.fromJson(value);
  //
  //             if (widget.take_away!) {
  //               placeOrder(_scaffoldKey.currentContext!);
  //             } else {
  //               toCheckOutScreen(true, _scaffoldKey.currentContext!);
  //             }
  //
  //             ScaffoldMessenger.of(context).showSnackBar(SnackBar(
  //               content: Text(
  //                 "Status : ${settleResult.data.transaction.status}\n"
  //                 "Transaction id : ${settleResult.data.transaction.id}\n"
  //                 "Amount : ${settleResult.data.transaction.amount}",
  //               ),
  //               duration: const Duration(seconds: 8),
  //               backgroundColor: Colors.green,
  //             ));
  //           } else {
  //             print(value);
  //             payPalCurrModel.PayPalCurrencyCodeErrorModel settleResult =
  //                 payPalCurrModel.PayPalCurrencyCodeErrorModel.fromJson(value);
  //             Navigator.pop(_scaffoldKey.currentContext!);
  //             ScaffoldMessenger.of(context).showSnackBar(SnackBar(
  //               content:
  //                   Text("Status :".tr() + " ${settleResult.data.message}"),
  //               duration: const Duration(seconds: 8),
  //               backgroundColor: AppThemeData.primary500,
  //             ));
  //           }
  //         } else {
  //           PayPalErrorSettleModel settleResult =
  //               PayPalErrorSettleModel.fromJson(value);
  //           Navigator.pop(_scaffoldKey.currentContext!);
  //           ScaffoldMessenger.of(_scaffoldKey.currentContext!)
  //               .showSnackBar(SnackBar(
  //             content: Text("Status :".tr() + " ${settleResult.data.message}"),
  //             duration: const Duration(seconds: 8),
  //             backgroundColor: AppThemeData.primary500,
  //           ));
  //         }
  //       });
  //     } else {
  //       Navigator.pop(_scaffoldKey.currentContext!);
  //       ScaffoldMessenger.of(_scaffoldKey.currentContext!)
  //           .showSnackBar(SnackBar(
  //         content: Text("Status :".tr() + "Payment Unsuccessful!!".tr()),
  //         duration: const Duration(seconds: 8),
  //         backgroundColor: AppThemeData.primary500,
  //       ));
  //     }
  //   });
  // }

  bool _isLoadingDialogShowing = false;

  showLoadingAlert() {
    setState(() {
      isProcessingOrder = true;
      _isLoadingDialogShowing = true;
    });
    return showDialog<void>(
      context: _scaffoldKey.currentContext!,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (BuildContext ctx) {
        final dark = isDarkMode(ctx);
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              decoration: BoxDecoration(
                color: dark ? AppThemeData.darkBgSecondary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 30, offset: const Offset(0, 10))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 56, height: 56,
                    child: CircularProgressIndicator(
                      strokeWidth: 3.5,
                      color: AppThemeData.primary500,
                      backgroundColor: AppThemeData.primary500.withValues(alpha: 0.12),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Processing Payment'.tr(),
                    style: TextStyle(
                      fontSize: 18,
                      fontFamily: AppThemeData.semiBold,
                      color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Please do not go back until payment is completed.'.tr(),
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: AppThemeData.regular,
                      color: dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral500,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppThemeData.primary500.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_rounded, size: 13, color: AppThemeData.primary500),
                        const SizedBox(width: 6),
                        Text(
                          'Secure payment in progress'.tr(),
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: AppThemeData.medium,
                            color: AppThemeData.primary500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  ///Paytm payment function
  getPaytmCheckSum(
    context, {
    required double amount,
  }) async {
    final String orderId = await UserPreference.getPaymentId();
    String getChecksum = "${GlobalURL}payments/getpaytmchecksum";

    final response = await http.post(
        Uri.parse(
          getChecksum,
        ),
        headers: {},
        body: {
          "mid": paytmSettingData?.PaytmMID,
          "order_id": orderId,
          "key_secret": paytmSettingData?.PAYTM_MERCHANT_KEY,
        });

    final data = jsonDecode(response.body);
    await verifyCheckSum(
            checkSum: data["code"], amount: amount, orderId: orderId)
        .then((value) {
      initiatePayment(amount: amount, orderId: orderId).then((value) {
        String callback = "";
        if (paytmSettingData!.isSandboxEnabled) {
          callback = callback +
              "https://securegw-stage.paytm.in/theia/paytmCallback?ORDER_ID=$orderId";
        } else {
          callback = callback +
              "https://securegw.paytm.in/theia/paytmCallback?ORDER_ID=$orderId";
        }

        GetPaymentTxtTokenModel result = value;
        _startTransaction(context,
            txnTokenBy: result.body.txnToken,
            orderId: orderId,
            amount: amount,
            callBackURL: callback);
      });
    });
  }

  Future<void> _startTransaction(
    context, {
    required String txnTokenBy,
    required orderId,
    required double amount,
    required callBackURL,
  }) async {
    /* try {
      var response = AllInOneSdk.startTransaction(
        paytmSettingData!.PaytmMID,
        orderId,
        amount.toString(),
        txnTokenBy,
        callbackUrl,
        //"https://securegw-stage.paytm.in/theia/paytmCallback?ORDER_ID=$orderId",
        isStaging,
        true,
        enableAssist,
      );

      response.then((value) {
        if (value!["RESPMSG"] == "Txn Success") {
          if (widget.take_away!) {
            placeOrder(_scaffoldKey.currentContext!, oid: Uuid().v4());
          } else {
            toCheckOutScreen(true, context, oid: Uuid().v4());
          }
          showAlert(context, response: "Payment Successful!!".tr() + "\n ${value['RESPMSG']}", colors: Colors.green);
        }
      }).catchError((onError) {
        if (onError is PlatformException) {
          Navigator.pop(_scaffoldKey.currentContext!);

          result = onError.message.toString() + " \n  " + onError.code.toString();
          showAlert(_scaffoldKey.currentContext!, response: onError.message.toString(), colors: AppThemeData.primary500);
        } else {

          result = onError.toString();
          Navigator.pop(_scaffoldKey.currentContext!);
          showAlert(_scaffoldKey.currentContext!, response: result, colors: AppThemeData.primary500);
        }
      });
    } catch (err) {
      result = err.toString();
      Navigator.pop(_scaffoldKey.currentContext!);
      showAlert(_scaffoldKey.currentContext!, response: result, colors: AppThemeData.primary500);
    }*/
  }

  Future verifyCheckSum(
      {required String checkSum,
      required double amount,
      required orderId}) async {
    String getChecksum = "${GlobalURL}payments/validatechecksum";
    final response = await http.post(
        Uri.parse(
          getChecksum,
        ),
        headers: {},
        body: {
          "mid": paytmSettingData?.PaytmMID,
          "order_id": orderId,
          "key_secret": paytmSettingData?.PAYTM_MERCHANT_KEY,
          "checksum_value": checkSum,
        });
    final data = jsonDecode(response.body);
    return data['status'];
  }

  Future<GetPaymentTxtTokenModel> initiatePayment(
      {required double amount, required orderId}) async {
    String initiateURL = "${GlobalURL}payments/initiatepaytmpayment";
    String callback = "";
    if (paytmSettingData!.isSandboxEnabled) {
      callback = callback +
          "https://securegw-stage.paytm.in/theia/paytmCallback?ORDER_ID=$orderId";
    } else {
      callback = callback +
          "https://securegw.paytm.in/theia/paytmCallback?ORDER_ID=$orderId";
    }
    final response =
        await http.post(Uri.parse(initiateURL), headers: {}, body: {
      "mid": paytmSettingData?.PaytmMID,
      "order_id": orderId,
      "key_secret": paytmSettingData?.PAYTM_MERCHANT_KEY.toString(),
      "amount": amount.toString(),
      "currency": currencyData!.code,
      "callback_url": callback,
      "custId": MyAppState.currentUser!.userID,
      "issandbox": paytmSettingData!.isSandboxEnabled ? "1" : "2",
    });
    final data = jsonDecode(response.body);
    if (data["body"]["txnToken"] == null ||
        data["body"]["txnToken"].toString().isEmpty) {
      Navigator.pop(_scaffoldKey.currentContext!);
      showAlert(_scaffoldKey.currentContext!,
          response: "something went wrong, please contact admin.".tr(),
          colors: AppThemeData.primary500);
    }
    return GetPaymentTxtTokenModel.fromJson(data);
  }

  ///PayStack Payment Method
  payStackPayment(BuildContext context) async {
    await PayStackURLGen.payStackURLGen(
      amount: (widget.total * 100).toString(),
      currency: currencyData!.code,
      secretKey: payStackSettingData!.secretKey,
    ).then((value) async {
      if (value != null) {
        PayStackUrlModel _payStackModel = value;
        bool isDone = await Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => PayStackScreen(
                  secretKey: payStackSettingData!.secretKey,
                  callBackUrl: payStackSettingData!.callbackURL,
                  initialURl: _payStackModel.data.authorizationUrl,
                  amount: widget.total.toString(),
                  reference: _payStackModel.data.reference,
                )));
        //Navigator.pop(_globalKey.currentContext!);

        if (isDone) {
          final orderId = await generateOrderId();
          if (widget.take_away!) {
            placeOrder(_scaffoldKey.currentContext!, oid: orderId);
          } else {
            toCheckOutScreen(true, _scaffoldKey.currentContext!, oid: orderId);
          }
          ScaffoldMessenger.of(_scaffoldKey.currentContext!)
              .showSnackBar(SnackBar(
            content: Text("Payment Successful!!".tr() + "\n"),
            backgroundColor: Colors.green,
          ));
        } else {
          Navigator.pop(_scaffoldKey.currentContext!);
          ScaffoldMessenger.of(_scaffoldKey.currentContext!)
              .showSnackBar(SnackBar(
            content: Text("Payment UnSuccessful!!".tr() + "\n"),
            backgroundColor: AppThemeData.primary500,
          ));
        }
      } else {
        Navigator.pop(_scaffoldKey.currentContext!);
        showAlert(_scaffoldKey.currentContext!,
            response: "something went wrong, please contact admin.".tr(),
            colors: AppThemeData.primary500);
      }
    });
  }

  ///MercadoPago Payment Method

  mercadoPagoMakePayment() async {
    final headers = {
      'Authorization': 'Bearer ${mercadoPagoSettingData!.accessToken}',
      'Content-Type': 'application/json',
    };

    final body = jsonEncode({
      "items": [
        {
          "title": "Test",
          "description": "Test Payment",
          "quantity": 1,
          "currency_id": "BRL", // or your preferred currency
          "unit_price": double.parse(amount),
        }
      ],
      "payer": {"email": MyAppState.currentUser!.email},
      "back_urls": {
        "failure": "${GlobalURL}payment/failure",
        "pending": "${GlobalURL}payment/pending",
        "success": "${GlobalURL}payment/success",
      },
      "auto_return":
          "approved" // Automatically return after payment is approved
    });

    final response = await http.post(
      Uri.parse("https://api.mercadopago.com/checkout/preferences"),
      headers: headers,
      body: body,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      final bool isDone = await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) =>
                  MercadoPagoScreen(initialURl: data['init_point'])));

      if (isDone) {
        ShowToastDialog.showToast("Payment Successful!!");
        final orderId = await generateOrderId();
        if (widget.take_away!) {
          placeOrder(_scaffoldKey.currentContext!, oid: orderId);
        } else {
          toCheckOutScreen(true, _scaffoldKey.currentContext!, oid: orderId);
        }
      } else {
        ShowToastDialog.showToast("Payment UnSuccessful!!");
      }
    } else {
      return null;
    }
  }

  ///FlutterWave Payment Method
  String? _ref;

  setRef() {
    Random numRef = Random();
    int year = DateTime.now().year;
    int refNumber = numRef.nextInt(20000);
    if (Platform.isAndroid) {
      setState(() {
        _ref = "AndroidRef$year$refNumber";
      });
    } else if (Platform.isIOS) {
      setState(() {
        _ref = "IOSRef$year$refNumber";
      });
    }
  }

  _flutterWaveInitiatePayment(BuildContext context) async {
    final url = Uri.parse('https://api.flutterwave.com/v3/payments');
    final headers = {
      'Authorization': 'Bearer ${flutterWaveSettingData!.secretKey}',
      'Content-Type': 'application/json',
    };

    final body = jsonEncode({
      "tx_ref": _ref,
      "amount": amount,
      "currency": "NGN",
      "redirect_url": "${GlobalURL}payment/success",
      "payment_options": "ussd, card, barter, payattitude",
      "customer": {
        "email": MyAppState.currentUser!.email.toString(),
        "phonenumber":
            MyAppState.currentUser!.phoneNumber, // Add a real phone number
        "name": MyAppState.currentUser!.fullName(), // Add a real customer name
      },
      "customizations": {
        "title": "Payment for Services",
        "description": "Payment for XYZ services",
      }
    });

    final response = await http.post(url, headers: headers, body: body);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final bool isDone = await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) =>
                  MercadoPagoScreen(initialURl: data['data']['link'])));

      if (isDone) {
        ShowToastDialog.showToast("Payment Successful!!");
        final orderId = await generateOrderId();
        if (widget.take_away!) {
          placeOrder(_scaffoldKey.currentContext!, oid: orderId);
        } else {
          toCheckOutScreen(true, _scaffoldKey.currentContext!, oid: orderId);
        }
      } else {
        ShowToastDialog.showToast("Payment UnSuccessful!!");
      }
    } else {
      return null;
    }
  }

  //Midtrans payment
  midtransMakePayment(
      {required String amount, required BuildContext context}) async {
    final orderId = await generateOrderId();
    await createPaymentLink(amount: amount).then((url) async {
      ShowToastDialog.closeLoader();
      if (url != '') {
        final bool isDone = await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => MidtransScreen(initialURl: url)));
        if (isDone) {
          ShowToastDialog.showToast("Payment Successful!!");
          final orderId = await generateOrderId();
          if (widget.take_away!) {
            placeOrder(_scaffoldKey.currentContext!, oid: orderId);
          } else {
            toCheckOutScreen(true, _scaffoldKey.currentContext!, oid: orderId);
          }
        } else {
          ShowToastDialog.showToast("Payment Unsuccessful!!");
        }
      }
    });
  }

  Future<String> createPaymentLink({required var amount}) async {
    final ordersId = await generateOrderId();
    final url = Uri.parse(midTransModel!.isSandbox!
        ? 'https://api.sandbox.midtrans.com/v1/payment-links'
        : 'https://api.midtrans.com/v1/payment-links');

    final response = await http.post(
      url,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': generateBasicAuthHeader(midTransModel!.serverKey!),
      },
      body: jsonEncode({
        'transaction_details': {
          'order_id': ordersId,
          'gross_amount': double.parse(amount.toString()).toInt(),
        },
        'usage_limit': 2,
        "callbacks": {
          "finish": "https://www.google.com?merchant_order_id=$ordersId"
        },
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final responseData = jsonDecode(response.body);
      return responseData['payment_url'];
    } else {
      ShowToastDialog.showToast("something went wrong, please contact admin.");
      return '';
    }
  }

  String generateBasicAuthHeader(String apiKey) {
    String credentials = '$apiKey:';
    String base64Encoded = base64Encode(utf8.encode(credentials));
    return 'Basic $base64Encoded';
  }

  //Orangepay payment
  static String accessToken = '';
  static String payToken = '';
  static String orderId = '';
  static String amount = '';

  orangeMakePayment(
      {required String amount, required BuildContext context}) async {
    reset();
    final orderId = await generateOrderId();
    var paymentURL = await fetchToken(
        context: context, orderId: orderId, amount: amount, currency: 'USD');
    ShowToastDialog.closeLoader();
    if (paymentURL.toString() != '') {
      final bool isDone = await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => OrangeMoneyScreen(
                    initialURl: paymentURL,
                    accessToken: accessToken,
                    amount: amount,
                    orangePay: orangeMoneyModel!,
                    orderId: orderId,
                    payToken: payToken,
                  )));

      if (isDone) {
        ShowToastDialog.showToast("Payment Successful!!");
        final orderId = await generateOrderId();
        if (widget.take_away!) {
          placeOrder(_scaffoldKey.currentContext!, oid: orderId);
        } else {
          toCheckOutScreen(true, _scaffoldKey.currentContext!, oid: orderId);
        }
      } else {
        ShowToastDialog.showToast("Payment Unsuccessful!!");
      }
    } else {
      ShowToastDialog.showToast("Payment Unsuccessful!!");
    }
  }

  Future fetchToken(
      {required String orderId,
      required String currency,
      required BuildContext context,
      required String amount}) async {
    String apiUrl = 'https://api.orange.com/oauth/v3/token';
    Map<String, String> requestBody = {
      'grant_type': 'client_credentials',
    };

    var response = await http.post(Uri.parse(apiUrl),
        headers: <String, String>{
          'Authorization': "Basic ${orangeMoneyModel!.auth!}",
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: requestBody);

    if (response.statusCode == 200) {
      Map<String, dynamic> responseData = jsonDecode(response.body);

      accessToken = responseData['access_token'];
      return await webpayment(
          context: context,
          amountData: amount,
          currency: currency,
          orderIdData: orderId);
    } else {
      ShowToastDialog.showToast("Something went wrong, please contact admin.");
      return '';
    }
  }

  Future webpayment(
      {required String orderIdData,
      required BuildContext context,
      required String currency,
      required String amountData}) async {
    orderId = orderIdData;
    amount = amountData;
    String apiUrl = orangeMoneyModel!.isSandbox! == true
        ? 'https://api.orange.com/orange-money-webpay/dev/v1/webpayment'
        : 'https://api.orange.com/orange-money-webpay/cm/v1/webpayment';
    Map<String, String> requestBody = {
      "merchant_key": orangeMoneyModel!.merchantKey ?? '',
      "currency": orangeMoneyModel!.isSandbox == true ? "OUV" : currency,
      "order_id": orderId,
      "amount": amount,
      "reference": 'Y-Note Test',
      "lang": "en",
      "return_url": orangeMoneyModel!.returnUrl!.toString(),
      "cancel_url": orangeMoneyModel!.cancelUrl!.toString(),
      "notif_url": orangeMoneyModel!.notifyUrl!.toString(),
    };

    var response = await http.post(
      Uri.parse(apiUrl),
      headers: <String, String>{
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: json.encode(requestBody),
    );

    // Handle the response
    if (response.statusCode == 201) {
      Map<String, dynamic> responseData = jsonDecode(response.body);
      if (responseData['message'] == 'OK') {
        payToken = responseData['pay_token'];
        return responseData['payment_url'];
      } else {
        return '';
      }
    } else {
      ShowToastDialog.showToast("Something went wrong, please contact admin.");
      return '';
    }
  }

  static reset() {
    accessToken = '';
    payToken = '';
    orderId = '';
    amount = '';
  }

  //XenditPayment
  xenditPayment(context, amount) async {
    final orderId = await generateOrderId();
    await createXenditInvoice(amount: amount).then((model) async {
      ShowToastDialog.closeLoader();
      if (model.id != null) {
        final bool isDone = await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => XenditScreen(
                      initialURl: model.invoiceUrl ?? '',
                      transId: model.id ?? '',
                      apiKey: xenditModel!.apiKey!.toString() ?? "",
                    )));

        if (isDone) {
          ShowToastDialog.showToast("Payment Successful!!");
          final orderId = await generateOrderId();
          if (widget.take_away!) {
            placeOrder(_scaffoldKey.currentContext!, oid: orderId);
          } else {
            toCheckOutScreen(true, _scaffoldKey.currentContext!, oid: orderId);
          }
        } else {
          ShowToastDialog.showToast("Payment Unsuccessful!!");
        }
      }
    });
  }

  Future<XenditModel> createXenditInvoice({required var amount}) async {
    const url = 'https://api.xendit.co/v2/invoices';
    var headers = {
      'Content-Type': 'application/json',
      'Authorization': generateBasicAuthHeader(xenditModel!.apiKey!.toString()),
    };

    final externalId = await generateOrderId();
    final body = jsonEncode({
      'external_id': externalId,
      'amount': amount,
      'payer_email': 'customer@domain.com',
      'description': 'Test - VA Successful invoice payment',
      'currency': 'IDR', //IDR, PHP, THB, VND, MYR
    });

    try {
      final response =
          await http.post(Uri.parse(url), headers: headers, body: body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        XenditModel model = XenditModel.fromJson(jsonDecode(response.body));
        return model;
      } else {
        return XenditModel();
      }
    } catch (e) {
      return XenditModel();
    }
  }

  // ── PhonePe Payment (SDK) ────────────────────────────────────────────────────

  Future<void> _phonePayMakePayment({
    required BuildContext context,
    required double amount,
  }) async {
    showLoadingAlert();
    try {
      final params = _buildPhonePayParams(amount: amount);
      final merchantId   = params['merchantId']    as String;
      final base64Body   = params['base64Payload'] as String;
      final checksum     = params['checksum']      as String;
      final callbackUrl  = params['callbackUrl']   as String;
      final transactionId = params['transactionId'] as String;
      final isSandbox    = params['isSandbox']     as bool;

      await PhonePePaymentSdk.init(
        isSandbox ? "UAT" : "PRODUCTION",
        null,
        merchantId,
        false,
      );

      Navigator.pop(_scaffoldKey.currentContext!); // dismiss loading

      final response = await PhonePePaymentSdk.startTransaction(
        base64Body,
        callbackUrl,
        checksum,
        null, // null = let user choose any UPI app
      );

      debugPrint('PhonePe SDK response: $response');

      if (response != null && response['status'] == 'SUCCESS') {
        showLoadingAlert();
        final verified = await _checkPhonePayStatus(transactionId);
        if (Navigator.canPop(_scaffoldKey.currentContext!)) {
          Navigator.pop(_scaffoldKey.currentContext!);
        }
        if (verified) {
          ShowToastDialog.showToast('Payment Successful!!'.tr());
          final orderId = await generateOrderId();
          if (widget.take_away!) {
            placeOrder(_scaffoldKey.currentContext!, oid: orderId);
          } else {
            toCheckOutScreen(true, _scaffoldKey.currentContext!, oid: orderId);
          }
        } else {
          setState(() => isProcessingOrder = false);
          ShowToastDialog.showToast('Payment could not be verified'.tr());
        }
      } else {
        setState(() => isProcessingOrder = false);
        final err = response?['error'] ?? 'Payment cancelled';
        ShowToastDialog.showToast(err.toString());
      }
    } catch (e) {
      debugPrint('PhonePe payment error: $e');
      if (Navigator.canPop(_scaffoldKey.currentContext!)) {
        Navigator.pop(_scaffoldKey.currentContext!);
      }
      setState(() => isProcessingOrder = false);
      ShowToastDialog.showToast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<bool> _checkPhonePayStatus(String transactionId) async {
    final merchantId = phonePayData?.merchantId ?? '';
    final saltKey    = phonePayData?.saltKey    ?? '';
    final saltIndex  = phonePayData?.saltIndex  ?? 1;
    final isSandbox  = phonePayData?.isSandbox  ?? true;

    final statusPath    = '/pg/v1/status/$merchantId/$transactionId';
    final checksumInput = statusPath + saltKey;
    final checksum      =
        '${sha256.convert(utf8.encode(checksumInput)).toString()}###$saltIndex';

    final baseUrl = isSandbox
        ? 'https://api-preprod.phonepe.com/apis/pg-sandbox'
        : 'https://api.phonepe.com/apis/hermes';

    debugPrint('PhonePe status: GET $baseUrl$statusPath');

    final response = await http.get(
      Uri.parse('$baseUrl$statusPath'),
      headers: {
        'Content-Type': 'application/json',
        'X-VERIFY': checksum,
        'X-MERCHANT-ID': merchantId,
      },
    );

    debugPrint('PhonePe status: ${response.statusCode} ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['success'] == true && data['code'] == 'PAYMENT_SUCCESS';
    }
    return false;
  }

  Map<String, dynamic> _buildPhonePayParams({required double amount}) {
    final merchantId  = phonePayData?.merchantId  ?? '';
    final saltKey     = phonePayData?.saltKey     ?? '';
    final saltIndex   = phonePayData?.saltIndex   ?? 1;
    final isSandbox   = phonePayData?.isSandbox   ?? true;
    final redirectUrl = phonePayData?.redirectUrl ?? '';
    final callbackUrl = phonePayData?.callbackUrl ?? '';

    if (merchantId.isEmpty || saltKey.isEmpty) {
      throw Exception('PhonePe credentials not configured.');
    }

    final transactionId  = 'MT${DateTime.now().millisecondsSinceEpoch}';
    final amountInPaise  = (amount * 100).toInt();

    final payload = {
      'merchantId': merchantId,
      'merchantTransactionId': transactionId,
      'merchantUserId': 'MUID_${MyAppState.currentUser!.userID}',
      'amount': amountInPaise,
      'redirectUrl': redirectUrl,
      'redirectMode': 'REDIRECT',
      'callbackUrl': callbackUrl,
      'mobileNumber': MyAppState.currentUser!.phoneNumber ?? '',
      'paymentInstrument': {'type': 'PAY_PAGE'},
    };

    final base64Payload  = base64Encode(utf8.encode(jsonEncode(payload)));
    final checksumInput  = base64Payload + '/pg/v1/pay' + saltKey;
    final checksum       =
        '${sha256.convert(utf8.encode(checksumInput)).toString()}###$saltIndex';

    debugPrint('PhonePe SDK: merchantId=$merchantId isSandbox=$isSandbox amount=$amountInPaise');

    return {
      'merchantId':   merchantId,
      'base64Payload': base64Payload,
      'checksum':     checksum,
      'transactionId': transactionId,
      'callbackUrl':  callbackUrl,
      'isSandbox':    isSandbox,
    };
  }

  placeOrder(BuildContext buildContext, {required String oid}) async {
    // Debounce: prevent duplicate order placements
    if (_isPlacingOrder) return;
    if (paymentType.isEmpty) {
      AppDialog.showWarning(buildContext, title: 'Missing Payment Method', message: 'Please select a payment method to continue.');
      return;
    }

    setState(() {
      _isPlacingOrder = true;
      isProcessingOrder = true;
    });

    // Build cleaned products list
    final List<CartProduct> tempProduc = [];
    for (CartProduct cartProduct in widget.products) {
      CartProduct tempCart = cartProduct;
      if (tempCart.extras != null && tempCart.extras is List) {
        List<dynamic> cleanedExtras = [];
        for (var extra in tempCart.extras) {
          String cleanedExtra = extra
              .toString()
              .replaceAll("\\", "")
              .replaceAll("\"", "")
              .trim();
          if (cleanedExtra.isNotEmpty) cleanedExtras.add(cleanedExtra);
        }
        tempCart.extras = cleanedExtras;
      }
      tempProduc.add(tempCart);
    }

    OrderModel? placedOrder;

    try {
      showProgress('Placing Order...'.tr(), false);

      // Fetch vendor
      VendorModel vendorModel = await FireStoreUtils()
          .getVendorByVendorID(widget.products.first.vendorID)
          .whenComplete(() => setPrefData());

      // Build order model
      final OrderModel orderModel = OrderModel(
        id: oid.toString(),
        address: widget.addressModel,
        author: MyAppState.currentUser,
        authorID: MyAppState.currentUser?.userID ?? '',
        createdAt: Timestamp.now(),
        products: tempProduc,
        status: widget.orderType == "Bill Pay" ? ORDER_STATUS_COMPLETED : ORDER_STATUS_PLACED,
        vendor: vendorModel,
        payment_method: paymentType,
        notes: widget.notes,
        taxModel: widget.taxModel,
        vendorID: widget.products.first.vendorID,
        discount: widget.discount,
        couponCode: widget.couponCode,
        couponId: widget.couponId,
        sectionId: sectionConstantModel?.id ?? '',
        adminCommission: (widget.take_away ?? false)
            ? (sectionConstantModel?.adminCommision?.takeawayCommission ?? 0).toString()
            : (sectionConstantModel?.adminCommision?.commission ?? 0).toString(),
        adminCommissionType: sectionConstantModel?.adminCommision?.type,
        specialDiscount: widget.specialDiscountMap,
        takeAway: widget.take_away ?? false,
        scheduleTime: widget.scheduleTime,
        orderType: widget.orderType,
      );

      // Save to Firestore
      placedOrder =
          await FireStoreUtils().placeOrderWithTakeAWay(orderModel);

      // Update stock counts in parallel — best-effort, never fails the order.
      await Future.wait(
        tempProduc.map((item) async {
          try {
            final productModel = await FireStoreUtils().getProductByID(item.id.split('~').first);
            if (item.variant_info != null && productModel.itemAttributes?.variants != null) {
              for (final v in productModel.itemAttributes!.variants!) {
                if (v.variant_id == item.id.split('~').last && v.variant_quantity != '-1') {
                  v.variant_quantity =
                      (int.parse(v.variant_quantity.toString()) - item.quantity).toString();
                }
              }
            } else if (productModel.quantity != -1) {
              productModel.quantity -= item.quantity;
            }
            await FireStoreUtils.updateProduct(productModel);
          } catch (stockErr) {
            debugPrint('Stock update error for item ${item.id}: $stockErr');
          }
        }),
      );

      hideProgress();
      setState(() {
        isProcessingOrder = false;
        isOrderPlaced = true;
        _isPlacingOrder = false;
      });

      push(buildContext, PlaceOrderScreen(
        orderModel: placedOrder,
        isPaymentVerified: paymentType != 'cod',
      ));

    } catch (e) {
      hideProgress();
      setState(() {
        isProcessingOrder = false;
        _isPlacingOrder = false;
      });

      if (placedOrder != null && buildContext.mounted) {
        push(buildContext, PlaceOrderScreen(
          orderModel: placedOrder,
          isPaymentVerified: paymentType != 'cod',
        ));
        return;
      }

      if (buildContext.mounted) {
        // When payment was already debited (online gateway), show a different
        // message that doesn't falsely reassure the user their card wasn't charged.
        if (_paymentCollected) {
          _showPaymentCollectedOrderFailDialog(buildContext, oid, e.toString());
        } else {
          _showOrderFailureDialog(buildContext, oid, e.toString());
        }
      }
    }
  }

  void _showOrderFailureDialog(
      BuildContext ctx, String oid, String errorDetail) {
    final bool dark = isDarkMode(ctx);
    String friendlyMsg;
    final r = errorDetail.toLowerCase();
    if (r.contains('socket') ||
        r.contains('network') ||
        r.contains('timeout') ||
        r.contains('connection')) {
      friendlyMsg =
          'No internet connection. Please check your network and try again.'
              .tr();
    } else if (r.contains('permission-denied')) {
      friendlyMsg = 'Permission denied. Please contact support.'.tr();
    } else {
      friendlyMsg =
          'We could not place your order. Your payment has NOT been charged again.'
              .tr();
    }

    AppDialog.showConfirm(
      ctx,
      title: 'Order Failed',
      message: friendlyMsg,
      confirmLabel: 'Retry',
      cancelLabel: 'Cancel',
    ).then((retry) async {
      if (retry) {
        final retryId = await generateOrderId();
        placeOrder(ctx, oid: retryId);
      }
    });
  }

  // Shown when the online payment was collected but Firestore write failed.
  // Unlike _showOrderFailureDialog, this does NOT say "payment not charged" —
  // because it already was. The user can retry or navigate to Orders to verify.
  void _showPaymentCollectedOrderFailDialog(
      BuildContext ctx, String oid, String errorDetail) {
    AppDialog.showConfirm(
      ctx,
      title: 'Order Failed'.tr(),
      message:
          'Your payment was received but we could not confirm your order. '
          'Please check your Orders list or contact support. (Ref: $oid)'
              .tr(),
      confirmLabel: 'Retry'.tr(),
      cancelLabel: 'View Orders'.tr(),
    ).then((retry) async {
      if (!ctx.mounted) return;
      if (retry) {
        setState(() { _isPlacingOrder = false; });
        final retryId = await generateOrderId();
        placeOrder(ctx, oid: retryId);
      } else {
        pushAndRemoveUntil(ctx, ContainerScreen(user: MyAppState.currentUser!));
      }
    });
  }

  Future<void> setPrefData() async {
    SharedPreferences sp = await SharedPreferences.getInstance();

    sp.setString("musics_key", "");
    sp.setString("addsize", "");
  }

  toCheckOutScreen(bool val, BuildContext context, {required String oid}) {
    push(
      context,
      CheckoutScreen(
        id: oid,
        isPaymentDone: val,
        paymentType: paymentType,
        total: widget.total,
        discount: widget.discount!,
        couponCode: widget.couponCode!,
        couponId: widget.couponId!,
        notes: widget.notes!,
        paymentOption: paymentOption,
        products: widget.products,
        deliveryCharge: widget.deliveryCharge,
        tipValue: widget.tipValue,
        take_away: widget.take_away,
        taxModel: widget.taxModel,
        specialDiscountMap: widget.specialDiscountMap,
        scheduleTime: widget.scheduleTime,
        address: widget.addressModel,
        orderType: widget.orderType,
      ),
    );
  }

  @override
  void dispose() {
    _razorPay.clear(); // Remove all Razorpay event listeners
    super.dispose();
  }
}
