import 'dart:convert';

import 'package:emartconsumer/model/FlutterWaveSettingDataModel.dart';
import 'package:emartconsumer/model/MercadoPagoSettingsModel.dart';
import 'package:emartconsumer/model/PayFastSettingData.dart';
import 'package:emartconsumer/model/PayStackSettingsModel.dart';
import 'package:emartconsumer/model/payment_model/mid_trans.dart';
import 'package:emartconsumer/model/payment_model/orange_money.dart';
import 'package:emartconsumer/model/payment_model/xendit.dart';
import 'package:emartconsumer/model/paytmSettingData.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'model/paypalSettingData.dart';
import 'model/razorpayKeyModel.dart';
import 'model/stripeSettingData.dart';

class UserPreference {
  static late SharedPreferences preferences;

  static Future init() async {
    preferences = await SharedPreferences.getInstance();
  }

  static const razorPayDataKey = "razorPayData";
  static const _userId = "userId";

  static setUserId({required String userID}) {
    print(userID);
    preferences.setString(_userId, userID);
  }

  // static getUserId()async{
  //   final String? userID = _preferences.getString(_userId);
  //   print("User id");
  //   print(userID);
  //   return userID != null ? userID : "";
  // }

  static String walletKey = "walletKey";

  static setWalletData(bool isEnable) async {
    await preferences.setBool(walletKey, isEnable);
  }

  static getWalletData() {
    final bool? isEnable = preferences.getBool(walletKey);
    return isEnable;
  }

  static setRazorPayData(RazorPayModel razorPayModel) async {
    final jsonData = jsonEncode(razorPayModel);
    await preferences.setString(razorPayDataKey, jsonData);
  }

  static getRazorPayData() {
    final String? jsonData = preferences.getString(razorPayDataKey);
    if (jsonData != null) return RazorPayModel.fromJson(jsonDecode(jsonData));
  }

  static String payFast = "payFast";

  static setPayFastData(PayFastSettingData payFastSettingModel) async {
    final jsonData = jsonEncode(payFastSettingModel);
    await preferences.setString(payFast, jsonData);
  }

  static getPayFastData() {
    final String? jsonData = preferences.getString(payFast);
    if (jsonData != null) return PayFastSettingData.fromJson((jsonDecode(jsonData)));
  }

  static getMercadoPago() {
    final String? jsonData = preferences.getString(mercadoPago);
    if (jsonData != null) return MercadoPagoSettingData.fromJson((jsonDecode(jsonData)));
  }

  static String paypalKey = "paypalKey";

  static setPayPalData(PaypalSettingData payPalSettingModel) async {
    final jsonData = jsonEncode(payPalSettingModel);
    await preferences.setString(paypalKey, jsonData);
  }

  static getPayPalData() {
    final String? jsonData = preferences.getString(paypalKey);
    if (jsonData != null) return PaypalSettingData.fromJson((jsonDecode(jsonData)));
  }

  static String mercadoPago = "mercadoPago";

  static setMercadoPago(MercadoPagoSettingData mercadoPagoSettingData) async {
    final jsonData = jsonEncode(mercadoPagoSettingData);
    await preferences.setString(mercadoPago, jsonData);
  }

  static String stripeKey = "stripeKey";

  static setStripeData(StripeSettingData stripeSettingModel) async {
    final jsonData = jsonEncode(stripeSettingModel);
    await preferences.setString(stripeKey, jsonData);
  }

  static Future<StripeSettingData> getStripeData() async {
    final String? jsonData = preferences.getString(stripeKey);
    final stripeData = jsonDecode(jsonData!);
    return StripeSettingData.fromJson(stripeData);
  }

  static String flutterWaveStack = "flutterWaveStack";

  static setFlutterWaveData(FlutterWaveSettingData flutterWaveSettingData) async {
    final jsonData = jsonEncode(flutterWaveSettingData);
    await preferences.setString(flutterWaveStack, jsonData);
  }

  static Future<FlutterWaveSettingData> getFlutterWaveData() async {
    final String? jsonData = preferences.getString(flutterWaveStack);
    final flutterWaveData = jsonDecode(jsonData!);
    return FlutterWaveSettingData.fromJson(flutterWaveData);
  }

  static String payStack = "payStack";

  static setPayStackData(PayStackSettingData payStackSettingModel) async {
    final jsonData = jsonEncode(payStackSettingModel);
    await preferences.setString(payStack, jsonData);
  }

  static Future<PayStackSettingData> getPayStackData() async {
    final String? jsonData = preferences.getString(payStack);
    final payStackData = jsonDecode(jsonData!);
    return PayStackSettingData.fromJson(payStackData);
  }

  static const String _paytmKey = "paytmKey";

  static setPaytmData(PaytmSettingData paytmSettingModel) async {
    final jsonData = jsonEncode(paytmSettingModel);
    await preferences.setString(_paytmKey, jsonData);
  }

  static getPaytmData() async {
    final String? jsonData = preferences.getString(_paytmKey);
    final paytmData = jsonDecode(jsonData!);
    return PaytmSettingData.fromJson(paytmData);
  }



  static String orangeMoneySettings = "orangeMoneySettings";

  static setOrangeData(OrangeMoney orangeMoneyModel) async {
    final jsonData = jsonEncode(orangeMoneyModel);
    await preferences.setString(orangeMoneySettings, jsonData);
  }

  static Future<OrangeMoney> getOrangeData() async {
    final String? jsonData = preferences.getString(orangeMoneySettings);
    final stripeData = jsonDecode(jsonData!);
    return OrangeMoney.fromJson(stripeData);
  }


  static String xenditSettings = "xenditSettings";

  static setXenditData(Xendit xenditModel) async {
    final jsonData = jsonEncode(xenditModel);
    await preferences.setString(xenditSettings, jsonData);
  }

  static Future<Xendit> getXenditData() async {
    final String? jsonData = preferences.getString(xenditSettings);
    final stripeData = jsonDecode(jsonData!);
    return Xendit.fromJson(stripeData);
  }


  static String midTransSettings = "midTransSettings";

  static setMidTransData(MidTrans xenditModel) async {
    final jsonData = jsonEncode(xenditModel);
    await preferences.setString(midTransSettings, jsonData);
  }

  static Future<MidTrans> getMidTransData() async {
    final String? jsonData = preferences.getString(midTransSettings);
    final stripeData = jsonDecode(jsonData!);
    return MidTrans.fromJson(stripeData);
  }



  static const _paymentId = "paymentId";

  static setPaymentId({required String paymentId}) {
    preferences.setString(_paymentId, paymentId);
  }

  static getPaymentId() {
    final String? paymentId = preferences.getString(_paymentId);
    return paymentId ?? "";
  }
}
