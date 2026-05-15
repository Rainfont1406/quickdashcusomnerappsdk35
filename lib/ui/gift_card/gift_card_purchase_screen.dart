import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/model/payment_model/mid_trans.dart';
import 'package:emartconsumer/model/payment_model/orange_money.dart';
import 'package:emartconsumer/model/payment_model/xendit.dart';
import 'package:emartconsumer/payment/midtrans_screen.dart';
import 'package:emartconsumer/payment/orangePayScreen.dart';
import 'package:emartconsumer/payment/xenditModel.dart';
import 'package:emartconsumer/payment/xenditScreen.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_paypal_native/flutter_paypal_native.dart';
import 'package:flutter_paypal_native/models/custom/currency_code.dart';
import 'package:flutter_paypal_native/models/custom/environment.dart';
import 'package:flutter_paypal_native/models/custom/order_callback.dart';
import 'package:flutter_paypal_native/models/custom/purchase_unit.dart';
import 'package:flutter_paypal_native/models/custom/user_action.dart';
import 'package:flutter_paypal_native/str_helper.dart';

import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/FlutterWaveSettingDataModel.dart';
import 'package:emartconsumer/model/MercadoPagoSettingsModel.dart';
import 'package:emartconsumer/model/PayFastSettingData.dart';
import 'package:emartconsumer/model/PayStackSettingsModel.dart';

import 'package:emartconsumer/model/createRazorPayOrderModel.dart';
import 'package:emartconsumer/model/getPaytmTxtToken.dart';
import 'package:emartconsumer/model/gift_cards_model.dart';
import 'package:emartconsumer/model/gift_cards_order_model.dart';
import 'package:emartconsumer/model/payStackURLModel.dart';
import 'package:emartconsumer/model/paypalSettingData.dart';
import 'package:emartconsumer/model/paytmSettingData.dart';
import 'package:emartconsumer/model/razorpayKeyModel.dart';
import 'package:emartconsumer/model/stripeSettingData.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/ui/wallet/MercadoPagoScreen.dart';
import 'package:emartconsumer/ui/wallet/payStackScreen.dart';
import 'package:http/http.dart' as http;
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/paystack_url_genrater.dart';
import 'package:emartconsumer/services/rozorpayConroller.dart';
import 'package:emartconsumer/ui/wallet/PayFastScreen.dart';
import 'package:emartconsumer/userPrefrence.dart';

import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:flutter_stripe/flutter_stripe.dart' as stripe1;
import 'package:uuid/uuid.dart';

class GiftCardPurchaseScreen extends StatefulWidget {
  final GiftCardsModel giftCardModel;
  final String price;
  final String msg;

  const GiftCardPurchaseScreen({super.key, required this.giftCardModel, required this.price, required this.msg});

  @override
  State<GiftCardPurchaseScreen> createState() => _GiftCardPurchaseScreenState();
}

class _GiftCardPurchaseScreenState extends State<GiftCardPurchaseScreen> {
  GiftCardsModel giftCardModel = GiftCardsModel();
  String gradTotal = "0";

  @override
  void initState() {
    giftCardModel = widget.giftCardModel;
    gradTotal = widget.price;
    getPaymentSettingData();
    super.initState();
  }

  Razorpay _razorPay = Razorpay();
  RazorPayModel? razorPayData;
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

  getPaymentSettingData() async {
    await UserPreference.getStripeData().then((value) async {
      stripeData = value;
      stripe1.Stripe.publishableKey = stripeData!.clientpublishableKey;
      stripe1.Stripe.merchantIdentifier = 'Foodie';
      await stripe1.Stripe.instance.applySettings();
    });

    _razorPay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorPay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWaller);
    _razorPay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);

    razorPayData = await UserPreference.getRazorPayData();
    paytmSettingData = await UserPreference.getPaytmData();
    paypalSettingData = await UserPreference.getPayPalData();
    payStackSettingData = await UserPreference.getPayStackData();
    flutterWaveSettingData = await UserPreference.getFlutterWaveData();
    payFastSettingData = await UserPreference.getPayFastData();
    mercadoPagoSettingData = await UserPreference.getMercadoPago();
    midTransModel = await UserPreference.getMidTransData();
    orangeMoneyModel = await UserPreference.getOrangeData();
    xenditModel = await UserPreference.getXenditData();
    setRef();
    initPayPal();
  }

  final _flutterPaypalNativePlugin = FlutterPaypalNative.instance;

  void initPayPal() async {
    //set debugMode for error logging
    FlutterPaypalNative.isDebugMode = paypalSettingData!.isLive == false ? true : false;
    //initiate payPal plugin
    await _flutterPaypalNativePlugin.init(
      //your app id !!! No Underscore!!! see readme.md for help
      returnUrl: "com.emart.customer://paypalpay",
      //client id from developer dashboard
      clientID: paypalSettingData!.paypalClient,
      //sandbox, staging, live etc
      payPalEnvironment: paypalSettingData!.isLive == true ? FPayPalEnvironment.live : FPayPalEnvironment.sandbox,
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
          ScaffoldMessenger.of(_scaffoldKey.currentContext!).showSnackBar(SnackBar(
            content: Text("Payment canceled".tr() + "\n"),
            backgroundColor: AppThemeData.primary500,
          ));
        },
        onSuccess: (data) {
          Navigator.pop(context);
          _flutterPaypalNativePlugin.removeAllPurchaseItems();
          String visitor = data.cart?.shippingAddress?.firstName ?? 'Visitor';
          String address = data.cart?.shippingAddress?.line1 ?? 'Unknown Address';

          ScaffoldMessenger.of(_scaffoldKey.currentContext!).showSnackBar(SnackBar(
            content: Text("Payment Successfully".tr() + "\n"),
            backgroundColor: AppThemeData.primary500,
          ));
          paymentCompleted(paymentMethod: "Paypal");
        },
        onError: (data) {
          Navigator.pop(context);
          ScaffoldMessenger.of(_scaffoldKey.currentContext!).showSnackBar(SnackBar(
            content: Text("error".tr() + "\n"),
            backgroundColor: AppThemeData.primary500,
          ));
        },
        onShippingChange: (data) {
          //the user updated the shipping address
          Navigator.pop(context);
          ScaffoldMessenger.of(_scaffoldKey.currentContext!).showSnackBar(SnackBar(
            content: Text("shipping change: ${data.shippingChangeAddress?.adminArea1 ?? ""}"),
            backgroundColor: AppThemeData.primary500,
          ));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: isDarkMode(context) ? AppThemeData.surfaceDark : AppThemeData.surface,
      appBar: AppBar(
        title: Text("Complete purchase", style: TextStyle(color: AppThemeData.primary500, fontSize: 18, fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                  height: 200,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.white, width: 5),
                      image: DecorationImage(
                        fit: BoxFit.cover,
                        image: NetworkImage(
                          giftCardModel.image.toString(),
                        ),
                      ),
                    ),
                  )),
              SizedBox(
                height: 10,
              ),
              Container(
                decoration: BoxDecoration(
                  color: AppThemeData.primary500.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: Text("Complete payment and share this e-gift card with loved ones using any app."),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Text("BILL SUMMARY".toUpperCase(),
                          style: TextStyle(fontSize: 16, color: isDarkMode(context) ? Colors.grey.shade700 : Colors.grey.shade700, fontWeight: FontWeight.w600)),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 13),
                clipBehavior: Clip.antiAlias,
                decoration: ShapeDecoration(
                  color: isDarkMode(context) ? AppThemeData.grey900 : AppThemeData.grey50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  shadows: [
                    BoxShadow(
                      color: Color(0x0A000000),
                      blurRadius: 32,
                      offset: Offset(0, 0),
                      spreadRadius: 0,
                    )
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Subtotal".tr(),
                              style: TextStyle(fontFamily: "Poppinsm"),
                            ),
                            Text(
                              amountShow(amount: widget.price),
                              style: TextStyle(fontFamily: AppThemeData.regular, color: isDarkMode(context) ? const Color(0xffFFFFFF) : const Color(0xff333333)),
                            ),
                          ],
                        )),
                    const Divider(
                      thickness: 1,
                    ),
                    Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Grand Total".tr(),
                              style: TextStyle(fontFamily: "Poppinsm"),
                            ),
                            Text(
                              amountShow(amount: widget.price),
                              style: TextStyle(fontFamily: AppThemeData.regular, color: AppThemeData.primary500),
                            ),
                          ],
                        )),
                  ],
                ),
              ),
              Text(
                "Gift Card expire  ${giftCardModel.expiryDay} days after purchase ",
                style: TextStyle(color: Colors.grey),
              )
            ],
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(right: 40.0, left: 40.0, top: 10, bottom: 10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: double.infinity),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppThemeData.primary500,
              padding: EdgeInsets.only(top: 12, bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25.0),
                side: BorderSide(
                  color: AppThemeData.primary500,
                ),
              ),
            ),
            child: Text(
              'Continue'.tr(),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDarkMode(context) ? Colors.black : Colors.white,
              ),
            ),
            onPressed: () {
              topUpBalance();
            },
          ),
        ),
      ),
    );
  }

  paymentCompleted({required String paymentMethod}) async {
    GiftCardsOrderModel giftCardsOrderModel = GiftCardsOrderModel();
    giftCardsOrderModel.id = Uuid().v4();
    giftCardsOrderModel.giftId = giftCardModel.id.toString();
    giftCardsOrderModel.giftTitle = giftCardModel.title.toString();
    giftCardsOrderModel.price = gradTotal.toString();
    giftCardsOrderModel.redeem = false;
    giftCardsOrderModel.message = widget.msg;
    giftCardsOrderModel.giftPin = generateGiftPin();
    giftCardsOrderModel.giftCode = generateGiftCode();
    giftCardsOrderModel.paymentType = paymentMethod;
    giftCardsOrderModel.createdDate = Timestamp.now();
    DateTime dateTime = DateTime.now().add(Duration(days: int.parse(giftCardModel.expiryDay.toString())));
    giftCardsOrderModel.expireDate = Timestamp.fromDate(dateTime);
    giftCardsOrderModel.userid = MyAppState.currentUser!.userID;

    await FireStoreUtils().placeGiftCardOrder(giftCardsOrderModel).then((value) {
      Navigator.pop(context);
    });
  }

  String generateGiftCode() {
    var rng = Random();
    String generatedNumber = '';
    for (int i = 0; i < 16; i++) {
      generatedNumber += (rng.nextInt(9) + 1).toString();
    }
    return generatedNumber;
  }

  String generateGiftPin() {
    var rng = Random();
    String generatedNumber = '';
    for (int i = 0; i < 6; i++) {
      generatedNumber += (rng.nextInt(9) + 1).toString();
    }
    return generatedNumber;
  }

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool stripe = true;

  bool razorPay = false;
  bool payTm = false;
  bool paypal = false;
  bool payStack = false;
  bool flutterWave = false;
  bool payFast = false;
  bool mercadoPago = false;
  bool xendit = false;
  bool orange = false;
  bool Midtrans = false;

  String? selectedRadioTile;

  topUpBalance() {
    final size = MediaQuery.of(context).size;
    return showModalBottomSheet(
        elevation: 5,
        enableDrag: true,
        useRootNavigator: true,
        isScrollControlled: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15))),
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) => Container(
              width: size.width,
              height: size.height * 0.85,
              child: SingleChildScrollView(
                physics: BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 5),
                          child: RichText(
                            text: TextSpan(
                              text: "Select Payment Option".tr(),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isDarkMode(context) ? Colors.white : Colors.black,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Visibility(
                      visible: stripeData!.isEnabled,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 20),
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: stripe ? 0 : 2,
                          child: RadioListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: stripe ? AppThemeData.primary500 : Colors.transparent)),
                            controlAffinity: ListTileControlAffinity.trailing,
                            value: "Stripe",
                            groupValue: selectedRadioTile,
                            onChanged: (String? value) {
                              setState(() {
                                flutterWave = false;
                                stripe = true;
                                mercadoPago = false;
                                payFast = false;
                                payStack = false;
                                razorPay = false;
                                payTm = false;
                                paypal = false;
                                orange = false;
                                Midtrans = false;
                                xendit = false;
                                selectedRadioTile = value!;
                              });
                            },
                            selected: stripe,
                            //selectedRadioTile == "strip" ? true : false,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 6,
                            ),
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Container(
                                    decoration: BoxDecoration(
                                      color: Colors.blueGrey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 10),
                                      child: SizedBox(
                                        width: 80,
                                        height: 35,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                                          child: Image.asset(
                                            "assets/images/stripe.png",
                                          ),
                                        ),
                                      ),
                                    )),
                                SizedBox(
                                  width: 20,
                                ),
                                Text("Stripe"),
                              ],
                            ),
                            //toggleable: true,
                          ),
                        ),
                      ),
                    ),
                    Visibility(
                      visible: payStackSettingData!.isEnabled,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 20),
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: payStack ? 0 : 2,
                          child: RadioListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: payStack ? AppThemeData.primary500 : Colors.transparent)),
                            controlAffinity: ListTileControlAffinity.trailing,
                            value: "PayStack",
                            groupValue: selectedRadioTile,
                            onChanged: (String? value) {
                              setState(() {
                                flutterWave = false;
                                payStack = true;
                                mercadoPago = false;
                                stripe = false;
                                payFast = false;
                                razorPay = false;
                                payTm = false;
                                paypal = false;
                                orange = false;
                                Midtrans = false;
                                xendit = false;
                                selectedRadioTile = value!;
                              });
                            },
                            selected: payStack,
                            //selectedRadioTile == "strip" ? true : false,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 6,
                            ),
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Container(
                                    decoration: BoxDecoration(
                                      color: Colors.blueGrey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 10),
                                      child: SizedBox(
                                        width: 80,
                                        height: 35,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                                          child: Image.asset(
                                            "assets/images/paystack.png",
                                          ),
                                        ),
                                      ),
                                    )),
                                SizedBox(
                                  width: 20,
                                ),
                                Text("PayStack"),
                              ],
                            ),
                            //toggleable: true,
                          ),
                        ),
                      ),
                    ),
                    Visibility(
                      visible: flutterWaveSettingData != null && flutterWaveSettingData!.isEnable,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 20),
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: flutterWave ? 0 : 2,
                          child: RadioListTile(
                            shape:
                                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: flutterWave ? AppThemeData.primary500 : Colors.transparent)),
                            controlAffinity: ListTileControlAffinity.trailing,
                            value: "FlutterWave",
                            groupValue: selectedRadioTile,
                            onChanged: (String? value) {
                              setState(() {
                                flutterWave = true;
                                payStack = false;
                                mercadoPago = false;
                                payFast = false;
                                stripe = false;
                                razorPay = false;
                                payTm = false;
                                paypal = false;
                                orange = false;
                                Midtrans = false;
                                xendit = false;
                                selectedRadioTile = value!;
                              });
                            },
                            selected: flutterWave,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 6,
                            ),
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Container(
                                    decoration: BoxDecoration(
                                      color: Colors.blueGrey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 10),
                                      child: SizedBox(
                                        width: 80,
                                        height: 35,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                                          child: Image.asset(
                                            "assets/images/flutterwave.png",
                                          ),
                                        ),
                                      ),
                                    )),
                                SizedBox(
                                  width: 20,
                                ),
                                Text("FlutterWave"),
                              ],
                            ),
                            //toggleable: true,
                          ),
                        ),
                      ),
                    ),
                    Visibility(
                      visible: razorPayData!.isEnabled,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 20),
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: razorPay ? 0 : 2,
                          child: RadioListTile(
                            //toggleable: true,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: razorPay ? AppThemeData.primary500 : Colors.transparent)),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 6,
                            ),
                            controlAffinity: ListTileControlAffinity.trailing,
                            value: "RazorPay",
                            groupValue: selectedRadioTile,
                            onChanged: (String? value) {
                              setState(() {
                                mercadoPago = false;
                                flutterWave = false;
                                stripe = false;
                                razorPay = true;
                                payTm = false;
                                payFast = false;
                                paypal = false;
                                payStack = false;
                                orange = false;
                                Midtrans = false;
                                xendit = false;
                                selectedRadioTile = value!;
                              });
                            },
                            selected: razorPay,
                            //selectedRadioTile == "strip" ? true : false,
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Container(
                                    decoration: BoxDecoration(
                                      color: Colors.blueGrey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 10),
                                      child: SizedBox(width: 80, height: 35, child: Image.asset("assets/images/razorpay_@3x.png")),
                                    )),
                                SizedBox(
                                  width: 20,
                                ),
                                Text("RazorPay"),
                              ],
                            ),
                            //toggleable: true,
                          ),
                        ),
                      ),
                    ),
                    Visibility(
                      visible: payFastSettingData != null && payFastSettingData!.isEnable,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 20),
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: payFast ? 0 : 2,
                          child: RadioListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: payFast ? AppThemeData.primary500 : Colors.transparent)),
                            controlAffinity: ListTileControlAffinity.trailing,
                            value: "payFast",
                            groupValue: selectedRadioTile,
                            onChanged: (String? value) {
                              setState(() {
                                payFast = true;
                                stripe = false;
                                mercadoPago = false;
                                razorPay = false;
                                payStack = false;
                                flutterWave = false;
                                payTm = false;
                                paypal = false;
                                orange = false;
                                Midtrans = false;
                                xendit = false;
                                selectedRadioTile = value!;
                              });
                            },
                            selected: payFast,
                            //selectedRadioTile == "strip" ? true : false,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 6,
                            ),
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Container(
                                    decoration: BoxDecoration(
                                      color: Colors.blueGrey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 10),
                                      child: SizedBox(
                                        width: 80,
                                        height: 35,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                                          child: Image.asset(
                                            "assets/images/payfast.png",
                                          ),
                                        ),
                                      ),
                                    )),
                                SizedBox(
                                  width: 20,
                                ),
                                Text("Pay Fast"),
                              ],
                            ),
                            //toggleable: true,
                          ),
                        ),
                      ),
                    ),
                    Visibility(
                      visible: paytmSettingData!.isEnabled,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 20),
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: payTm ? 0 : 2,
                          child: RadioListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: payTm ? AppThemeData.primary500 : Colors.transparent)),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 6,
                            ),
                            controlAffinity: ListTileControlAffinity.trailing,
                            value: "PayTm",
                            groupValue: selectedRadioTile,
                            onChanged: (String? value) {
                              setState(() {
                                stripe = false;
                                flutterWave = false;
                                payTm = true;
                                mercadoPago = false;
                                razorPay = false;
                                paypal = false;
                                payFast = false;
                                payStack = false;
                                orange = false;
                                Midtrans = false;
                                xendit = false;
                                selectedRadioTile = value!;
                              });
                            },
                            selected: payTm,
                            //selectedRadioTile == "strip" ? true : false,
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Container(
                                    decoration: BoxDecoration(
                                      color: Colors.blueGrey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 10),
                                      child: SizedBox(
                                          width: 80,
                                          height: 35,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 3.0),
                                            child: Image.asset(
                                              "assets/images/paytm_@3x.png",
                                            ),
                                          )),
                                    )),
                                SizedBox(
                                  width: 20,
                                ),
                                Text("Paytm"),
                              ],
                            ),
                            //toggleable: true,
                          ),
                        ),
                      ),
                    ),
                    Visibility(
                      visible: mercadoPagoSettingData != null && mercadoPagoSettingData!.isEnabled,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 20),
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: mercadoPago ? 0 : 2,
                          child: RadioListTile(
                            shape:
                                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: mercadoPago ? AppThemeData.primary500 : Colors.transparent)),
                            controlAffinity: ListTileControlAffinity.trailing,
                            value: "MercadoPago",
                            groupValue: selectedRadioTile,
                            onChanged: (String? value) {
                              setState(() {
                                mercadoPago = true;
                                payFast = false;
                                stripe = false;
                                razorPay = false;
                                payStack = false;
                                flutterWave = false;
                                payTm = false;
                                paypal = false;
                                selectedRadioTile = value!;
                              });
                            },
                            selected: mercadoPago,
                            //selectedRadioTile == "strip" ? true : false,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 6,
                            ),
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Container(
                                    decoration: BoxDecoration(
                                      color: Colors.blueGrey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 10),
                                      child: SizedBox(
                                        width: 80,
                                        height: 35,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                                          child: Image.asset(
                                            "assets/images/mercadopago.png",
                                          ),
                                        ),
                                      ),
                                    )),
                                SizedBox(
                                  width: 20,
                                ),
                                Text("Mercado Pago"),
                              ],
                            ),
                            //toggleable: true,
                          ),
                        ),
                      ),
                    ),
                    Visibility(
                      visible: paypalSettingData != null && paypalSettingData!.isEnabled,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 20),
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: paypal ? 0 : 2,
                          child: RadioListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: paypal ? AppThemeData.primary500 : Colors.transparent)),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 6,
                            ),
                            controlAffinity: ListTileControlAffinity.trailing,
                            value: "PayPal",
                            groupValue: selectedRadioTile,
                            onChanged: (String? value) {
                              setState(() {
                                stripe = false;
                                payTm = false;
                                mercadoPago = false;
                                flutterWave = false;
                                razorPay = false;
                                paypal = true;
                                payFast = false;
                                payStack = false;
                                orange = false;
                                Midtrans = false;
                                xendit = false;
                                selectedRadioTile = value!;
                              });
                            },
                            selected: paypal,
                            //selectedRadioTile == "strip" ? true : false,
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Container(
                                    decoration: BoxDecoration(
                                      color: Colors.blueGrey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 10),
                                      child: SizedBox(
                                          width: 80,
                                          height: 35,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 3.0),
                                            child: Image.asset("assets/images/paypal_@3x.png"),
                                          )),
                                    )),
                                SizedBox(
                                  width: 20,
                                ),
                                Text("PayPal"),
                              ],
                            ),
                            //toggleable: true,
                          ),
                        ),
                      ),
                    ),
                    Visibility(
                      visible: xenditModel!.enable ?? false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 20),
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: xendit ? 0 : 2,
                          child: RadioListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: xendit ? AppThemeData.primary500 : Colors.transparent)),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                            ),
                            controlAffinity: ListTileControlAffinity.trailing,
                            value: "Xendit",
                            groupValue: selectedRadioTile,
                            onChanged: (String? value) {
                              print(value);
                              setState(() {
                                stripe = false;
                                payTm = false;
                                mercadoPago = false;
                                flutterWave = false;
                                razorPay = false;
                                paypal = false;
                                payFast = false;
                                payStack = false;
                                orange = false;
                                Midtrans = false;
                                xendit = true;
                                selectedRadioTile = value!;
                              });
                            },
                            selected: xendit,
                            //selectedRadioTile == "strip" ? true : false,
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Container(
                                    decoration: BoxDecoration(
                                      color: Colors.blueGrey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 10),
                                      child: SizedBox(
                                          width: 80,
                                          height: 35,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 3.0),
                                            child: Image.asset("assets/images/xendit.png",),
                                          )),
                                    )),
                                const SizedBox(
                                  width: 20,
                                ),
                                const Text("Xendit").tr(),
                              ],
                            ),
                            //toggleable: true,
                          ),
                        ),
                      ),
                    ),
                    Visibility(
                      visible: orangeMoneyModel!.enable ?? false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 20),
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: orange ? 0 : 2,
                          child: RadioListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: orange ? AppThemeData.primary500 : Colors.transparent)),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                            ),
                            controlAffinity: ListTileControlAffinity.trailing,
                            value: "OrangeMoney",
                            groupValue: selectedRadioTile,
                            onChanged: (String? value) {
                              print(value);
                              setState(() {
                                stripe = false;
                                payTm = false;
                                mercadoPago = false;
                                flutterWave = false;
                                razorPay = false;
                                paypal = false;
                                payFast = false;
                                payStack = false;
                                orange = true;
                                Midtrans = false;
                                xendit = false;
                                selectedRadioTile = value!;
                              });
                            },
                            selected: orange,
                            //selectedRadioTile == "strip" ? true : false,
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Container(
                                    decoration: BoxDecoration(
                                      color: Colors.blueGrey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 10),
                                      child: SizedBox(
                                          width: 80,
                                          height: 35,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 3.0),
                                            child: Image.asset("assets/images/orange_money.png"),
                                          )),
                                    )),
                                const SizedBox(
                                  width: 20,
                                ),
                                const Text("OrangeMoney").tr(),
                              ],
                            ),
                            //toggleable: true,
                          ),
                        ),
                      ),
                    ),
                    Visibility(
                      visible: midTransModel!.enable ?? false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 20),
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: Midtrans ? 0 : 2,
                          child: RadioListTile(
                            shape:
                                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Midtrans ? AppThemeData.primary500 : Colors.transparent)),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                            ),
                            controlAffinity: ListTileControlAffinity.trailing,
                            value: "Midtrans",
                            groupValue: selectedRadioTile,
                            onChanged: (String? value) {
                              print(value);
                              setState(() {
                                stripe = false;
                                payTm = false;
                                mercadoPago = false;
                                flutterWave = false;
                                razorPay = false;
                                paypal = false;
                                payFast = false;
                                payStack = false;
                                orange = false;
                                Midtrans = true;
                                xendit = false;
                                selectedRadioTile = value!;
                              });
                            },
                            selected: Midtrans,
                            //selectedRadioTile == "strip" ? true : false,
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Container(
                                    decoration: BoxDecoration(
                                      color: Colors.blueGrey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 10),
                                      child: SizedBox(
                                          width: 80,
                                          height: 35,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 3.0),
                                            child: Image.asset("assets/images/midtrans.png"),
                                          )),
                                    )),
                                const SizedBox(
                                  width: 20,
                                ),
                                const Text("Midtrans").tr(),
                              ],
                            ),
                            //toggleable: true,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 22),
                      child: GestureDetector(
                        onTap: () async {
                          if (selectedRadioTile == "Stripe" && stripeData?.isEnabled == true) {
                            Navigator.pop(context);
                            showLoadingAlert();
                            stripeMakePayment(amount: gradTotal);
                          } else if (selectedRadioTile == "MercadoPago") {
                            Navigator.pop(context);
                            showLoadingAlert();
                            mercadoPagoMakePayment();
                          } else if (selectedRadioTile == "payFast") {
                            showLoadingAlert();
                            PayStackURLGen.getPayHTML(payFastSettingData: payFastSettingData!, amount: gradTotal).then((value) async {
                              bool isDone = await Navigator.of(context).push(MaterialPageRoute(
                                  builder: (context) => PayFastScreen(
                                        htmlData: value,
                                        payFastSettingData: payFastSettingData!,
                                      )));
                              print(isDone);
                              if (isDone) {
                                Navigator.pop(context);
                                Navigator.pop(context);
                                await paymentCompleted(paymentMethod: "PayFast");
                              } else {
                                Navigator.pop(context);
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(
                                    "Payment Unsuccessful!!".tr() + "\n",
                                  ),
                                  backgroundColor: AppThemeData.primary500,
                                  duration: const Duration(seconds: 6),
                                ));
                              }
                            });
                          } else if (selectedRadioTile == "RazorPay") {
                            showLoadingAlert();
                            RazorPayController().createOrderRazorPay(isTopup: true, amount: double.parse(gradTotal)).then((result) {
                              Navigator.pop(context);
                              if (result.isSuccess) {
                                openCheckout(
                                  amount: double.parse(gradTotal),
                                  orderId: result.order!.id,
                                );
                              } else {
                                showAlert(_scaffoldKey.currentContext!, response: result.errorMessage?.tr() ?? "Something went wrong, please contact admin.".tr(), colors: AppThemeData.primary500);
                              }
                            });
                          }  else if (selectedRadioTile == "PayPal") {
                            showLoadingAlert();
                            paypalPaymentSheet();
                          } else if (selectedRadioTile == "PayStack") {
                            showLoadingAlert();
                            payStackPayment();
                          } else if (selectedRadioTile == "FlutterWave") {
                            _flutterWaveInitiatePayment(context);
                          } else if (selectedRadioTile == "Midtrans") {
                            midtransMakePayment(context: context, amount: gradTotal);
                          } else if (selectedRadioTile == "OrangeMoney") {
                            orangeMakePayment(context: context, amount: gradTotal);
                          } else if (selectedRadioTile == "Xendit") {
                            xenditPayment(context, gradTotal);
                          }
                        },
                        child: Container(
                          height: 45,
                          decoration: BoxDecoration(
                            color: AppThemeData.primary500,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                              child: Text(
                            "CONTINUE".tr(),
                            style: TextStyle(color: Colors.white),
                          )),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
  }

  showLoadingAlert() {
    return showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return CupertinoAlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const CircularProgressIndicator(),
              const Text('Please wait!!').tr(),
            ],
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                const SizedBox(
                  height: 15,
                ),
                Text(
                  'Please wait!! while completing Transaction'.tr(),
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(
                  height: 15,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  showAlert(context, {required String response, required Color colors}) {
    return ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(response),
      backgroundColor: colors,
      duration: Duration(seconds: 8),
    ));
  }

  Map<String, dynamic>? paymentIntentData;

  /// RazorPay Payment Gateway
  void openCheckout({required amount, required orderId}) async {
    var options = {
      'key': razorPayData!.razorpayKey,
      'amount': (amount * 100).toInt(),
      'name': 'Quickdash',
      'order_id': orderId,
      "currency": currencyData?.code,
      'description': 'wallet Topup',
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
      debugPrint('error'.tr() + ': $e');
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    paymentCompleted(paymentMethod: "RazorPay");
  }

  void _handleExternalWaller(ExternalWalletResponse response) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        "Payment Processing Via".tr() + "\n" + response.walletName!,
      ),
      backgroundColor: Colors.blue.shade400,
      duration: Duration(seconds: 8),
    ));
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        "Payment Failed!!".tr() + "\n" + jsonDecode(response.message!)['error']['description'],
      ),
      backgroundColor: AppThemeData.primary500,
      duration: Duration(seconds: 8),
    ));
  }

  /// Paytm Payment Gateway
  bool isStaging = true;
  String callbackUrl = "http://162.241.125.167/~foodie/payments/paytmpaymentcallback?ORDER_ID=";
  bool restrictAppInvoke = false;
  bool enableAssist = true;
  String result = "";

  getPaytmCheckSum(
    context, {
    required double amount,
  }) async {
    final String orderId = UserPreference.getPaymentId();
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

    await verifyCheckSum(checkSum: data["code"], amount: amount, orderId: orderId).then((value) {
      initiatePayment(context, amount: amount, orderId: orderId).then((value) {
        GetPaymentTxtTokenModel result = value;
        String callback = "";
        if (paytmSettingData!.isSandboxEnabled) {
          callback = callback + "https://securegw-stage.paytm.in/theia/paytmCallback?ORDER_ID=$orderId";
        } else {
          callback = callback + "https://securegw.paytm.in/theia/paytmCallback?ORDER_ID=$orderId";
        }

        _startTransaction(
          context,
          txnTokenBy: result.body.txnToken,
          orderId: orderId,
          amount: amount,
        );
      });
    });
  }

  Future verifyCheckSum({required String checkSum, required double amount, required orderId}) async {
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

  Future<GetPaymentTxtTokenModel> initiatePayment(BuildContext context, {required double amount, required orderId}) async {
    String initiateURL = "${GlobalURL}payments/initiatepaytmpayment";
    String callback = "";
    if (paytmSettingData!.isSandboxEnabled) {
      callback = callback + "https://securegw-stage.paytm.in/theia/paytmCallback?ORDER_ID=$orderId";
    } else {
      callback = callback + "https://securegw.paytm.in/theia/paytmCallback?ORDER_ID=$orderId";
    }
    final response = await http.post(
        Uri.parse(
          initiateURL,
        ),
        headers: {},
        body: {
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
    if (data["body"]["txnToken"] == null || data["body"]["txnToken"].toString().isEmpty) {
      Navigator.pop(_scaffoldKey.currentContext!);
      showAlert(_scaffoldKey.currentContext!, response: "something went wrong, please contact admin.".tr(), colors: AppThemeData.primary500);
    }
    return GetPaymentTxtTokenModel.fromJson(data);
  }

  Future<void> _startTransaction(
    context, {
    required String txnTokenBy,
    required orderId,
    required double amount,
  }) async {
    // try {
    //   var response = AllInOneSdk.startTransaction(
    //     paytmSettingData!.PaytmMID,
    //     orderId,
    //     amount.toString(),
    //     txnTokenBy,
    //     "https://securegw-stage.paytm.in/theia/paytmCallback?ORDER_ID=$orderId",
    //     isStaging,
    //     true,
    //     enableAssist,
    //   );
    //
    //   response.then((value) {
    //     if (value!["RESPMSG"] == "Txn Success") {
    //       Navigator.pop(context);
    //       paymentCompleted(paymentMethod: "Paytm");
    //     }
    //   }).catchError((onError) {
    //     if (onError is PlatformException) {
    //       Navigator.pop(_scaffoldKey.currentContext!);
    //
    //       result = onError.message.toString() + " \n  " + onError.code.toString();
    //       showAlert(_scaffoldKey.currentContext!, response: onError.message.toString(), colors: AppThemeData.primary500);
    //     } else {
    //       result = onError.toString();
    //       Navigator.pop(_scaffoldKey.currentContext!);
    //       showAlert(_scaffoldKey.currentContext!, response: result, colors: AppThemeData.primary500);
    //     }
    //   });
    // } catch (err) {
    //   result = err.toString();
    //   Navigator.pop(_scaffoldKey.currentContext!);
    //   showAlert(_scaffoldKey.currentContext!, response: result, colors: AppThemeData.primary500);
    // }
  }

  /// Stripe Payment Gateway
  Future<void> stripeMakePayment({required String amount}) async {
    try {
      paymentIntentData = await createStripeIntent(
        amount,
      );
      if (paymentIntentData!.containsKey("error")) {
        Navigator.pop(context);
        showAlert(_scaffoldKey.currentContext, response: "Something went wrong, please contact admin.".tr(), colors: AppThemeData.primary500);
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
              appearance: stripe1.PaymentSheetAppearance(
                colors: stripe1.PaymentSheetAppearanceColors(
                  primary: AppThemeData.primary500,
                ),
              ),
              merchantDisplayName: 'QuickDash',
            ))
            .then((value) {});
        setState(() {});
        displayStripePaymentSheet();
      }
    } catch (e, s) {
      print('exception:$e$s');
    }
  }

  displayStripePaymentSheet() async {
    try {
      await stripe1.Stripe.instance.presentPaymentSheet().then((value) async {
        Navigator.pop(context);
        paymentCompleted(paymentMethod: "Stripe");
        paymentIntentData = null;
      });
    } on stripe1.StripeException catch (e) {
      Navigator.pop(context);
      var lo1 = jsonEncode(e);
      var lo2 = jsonDecode(lo1);
      showDialog(context: context, builder: (_) => AlertDialog(content: Text("Payment Failed")));
    } catch (e) {
      print('$e');
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("$e"),
        duration: Duration(seconds: 8),
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
      print(body);
      var response = await http.post(Uri.parse('https://api.stripe.com/v1/payment_intents'),
          body: body, headers: {'Authorization': 'Bearer ${stripeData?.stripeSecret}', 'Content-Type': 'application/x-www-form-urlencoded'});
      print('Create Intent response ===> ${response.body.toString()}');
      return jsonDecode(response.body);
    } catch (err) {
      print('error charging user: ${err.toString()}');
    }
  }

  calculateAmount(String amount) {
    final a = (int.parse(amount)) * 100;
    return a.toString();
  }

  /// PayPal Payment Gateway
  /// PayPal Payment Gateway
  paypalPaymentSheet() {
    //add 1 item to cart. Max is 4!
    if (_flutterPaypalNativePlugin.canAddMorePurchaseUnit) {
      _flutterPaypalNativePlugin.addPurchaseUnit(
        FPayPalPurchaseUnit(
          // random prices
          amount: double.parse(gradTotal),

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
      "auto_return": "approved" // Automatically return after payment is approved
    });

    final response = await http.post(
      Uri.parse("https://api.mercadopago.com/checkout/preferences"),
      headers: headers,
      body: body,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      final bool isDone = await Navigator.push(context, MaterialPageRoute(builder: (context) => MercadoPagoScreen(initialURl: data['init_point'])));

      if (isDone) {
        ShowToastDialog.showToast("Payment Successful!!");
        paymentCompleted(paymentMethod: "Mercoado");
      } else {
        ShowToastDialog.showToast("Payment UnSuccessful!!");
      }
    } else {
      print('Error creating preference: ${response.body}');
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
        "phonenumber": MyAppState.currentUser!.phoneNumber, // Add a real phone number
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
      final bool isDone = await Navigator.push(context, MaterialPageRoute(builder: (context) => MercadoPagoScreen(initialURl: data['data']['link'])));

      if (isDone) {
        ShowToastDialog.showToast("Payment Successful!!");
        paymentCompleted(paymentMethod: "FlutterWave");
      } else {
        ShowToastDialog.showToast("Payment UnSuccessful!!");
      }
    } else {
      print('Payment initialization failed: ${response.body}');
      return null;
    }
  }

  Future<void> showLoading({required String message, Color txtColor = Colors.black}) {
    return showDialog(
      context: this.context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Container(
            margin: EdgeInsets.fromLTRB(30, 20, 30, 20),
            width: double.infinity,
            height: 30,
            child: Text(
              message,
              style: TextStyle(color: txtColor),
            ),
          ),
        );
      },
    );
  }

  ///PayStack Payment Method
  payStackPayment() async {
    await PayStackURLGen.payStackURLGen(
      amount: (double.parse(gradTotal) * 100).toString(),
      currency: "ZAR",
      secretKey: payStackSettingData!.secretKey,
    ).then((value) async {
      if (value != null) {
        PayStackUrlModel _payStackModel = value;
        bool isDone = await Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => PayStackScreen(
                  secretKey: payStackSettingData!.secretKey,
                  callBackUrl: payStackSettingData!.callbackURL,
                  initialURl: _payStackModel.data.authorizationUrl,
                  amount: gradTotal,
                  reference: _payStackModel.data.reference,
                )));
        Navigator.pop(_scaffoldKey.currentContext!);

        if (isDone) {
          Navigator.pop(context);
          paymentCompleted(paymentMethod: "PayStack");
        } else {
          Navigator.pop(context);
          ScaffoldMessenger.of(_scaffoldKey.currentContext!).showSnackBar(SnackBar(
            content: Text("Payment UnSuccessful!!".tr() + "\n"),
            backgroundColor: AppThemeData.primary500,
          ));
        }
      } else {
        Navigator.pop(context);
        ScaffoldMessenger.of(_scaffoldKey.currentContext!).showSnackBar(SnackBar(
          content: Text("Error while transaction!".tr() + "\n"),
          backgroundColor: AppThemeData.primary500,
        ));
      }
    });
  }

  //Midtrans payment
  midtransMakePayment({required String amount, required BuildContext context}) async {
    await createPaymentLink(amount: amount).then((url) async {
      ShowToastDialog.closeLoader();
      if (url != '') {
        final bool isDone = await Navigator.push(context, MaterialPageRoute(builder: (context) => MidtransScreen(initialURl: url)));
        if (isDone) {
          ShowToastDialog.showToast("Payment Successful!!");
          paymentCompleted(paymentMethod: "Midtrans");
        } else {
          ShowToastDialog.showToast("Payment Unsuccessful!!");
        }
      }
    });
  }

  Future<String> createPaymentLink({required var amount}) async {
    var ordersId = const Uuid().v1();
    final url = Uri.parse(midTransModel!.isSandbox! ? 'https://api.sandbox.midtrans.com/v1/payment-links' : 'https://api.midtrans.com/v1/payment-links');

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
        "callbacks": {"finish": "https://www.google.com?merchant_order_id=$ordersId"},
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

  orangeMakePayment({required String amount, required BuildContext context}) async {
    reset();
    var id = const Uuid().v4();
    var paymentURL = await fetchToken(context: context, orderId: id, amount: amount, currency: 'USD');
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
        paymentCompleted(paymentMethod: "OrangeMoney");
      } else {
        ShowToastDialog.showToast("Payment Unsuccessful!!");
      }
    } else {
      ShowToastDialog.showToast("Payment Unsuccessful!!");
    }
  }

  Future fetchToken({required String orderId, required String currency, required BuildContext context, required String amount}) async {
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
      return await webpayment(context: context, amountData: amount, currency: currency, orderIdData: orderId);
    } else {
      ShowToastDialog.showToast("Something went wrong, please contact admin.");
      return '';
    }
  }

  Future webpayment({required String orderIdData, required BuildContext context, required String currency, required String amountData}) async {
    orderId = orderIdData;
    amount = amountData;
    String apiUrl =
        orangeMoneyModel!.isSandbox! == true ? 'https://api.orange.com/orange-money-webpay/dev/v1/webpayment' : 'https://api.orange.com/orange-money-webpay/cm/v1/webpayment';
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
      headers: <String, String>{'Authorization': 'Bearer $accessToken', 'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: json.encode(requestBody),
    );
    print(response.statusCode);
    print(response.body);

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
          paymentCompleted(paymentMethod: "Xendit");
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
      // 'Cookie': '__cf_bm=yERkrx3xDITyFGiou0bbKY1bi7xEwovHNwxV1vCNbVc-1724155511-1.0.1.1-jekyYQmPCwY6vIJ524K0V6_CEw6O.dAwOmQnHtwmaXO_MfTrdnmZMka0KZvjukQgXu5B.K_6FJm47SGOPeWviQ',
    };

    final body = jsonEncode({
      'external_id': const Uuid().v1(),
      'amount': amount,
      'payer_email': 'customer@domain.com',
      'description': 'Test - VA Successful invoice payment',
      'currency': 'IDR', //IDR, PHP, THB, VND, MYR
    });

    try {
      final response = await http.post(Uri.parse(url), headers: headers, body: body);

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

  @override
  void dispose() {
    _razorPay.clear(); // Remove all Razorpay event listeners
    super.dispose();
  }
}
