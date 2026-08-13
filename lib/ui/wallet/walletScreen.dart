import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:http/http.dart' as http;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/model/FlutterWaveSettingDataModel.dart';
import 'package:emartconsumer/model/MercadoPagoSettingsModel.dart';
import 'package:emartconsumer/model/PayFastSettingData.dart';
import 'package:emartconsumer/model/PayStackSettingsModel.dart';

import 'package:emartconsumer/model/payStackURLModel.dart';
import 'package:emartconsumer/model/payment_model/mid_trans.dart';
import 'package:emartconsumer/model/payment_model/orange_money.dart';
import 'package:emartconsumer/model/payment_model/xendit.dart';
import 'package:emartconsumer/model/paypalSettingData.dart';
import 'package:emartconsumer/model/paytmSettingData.dart';
import 'package:emartconsumer/model/razorpayKeyModel.dart';
import 'package:emartconsumer/model/stripeSettingData.dart';
import 'package:emartconsumer/model/topupTranHistory.dart';
import 'package:emartconsumer/payment/midtrans_screen.dart';
import 'package:emartconsumer/payment/orangePayScreen.dart';
import 'package:emartconsumer/payment/xenditModel.dart';
import 'package:emartconsumer/payment/xenditScreen.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/device_session_service.dart';
import 'package:emartconsumer/services/paystack_url_genrater.dart';
import 'package:emartconsumer/services/rozorpayConroller.dart';
import 'package:emartconsumer/services/app_dialog.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/wallet/MercadoPagoScreen.dart';
import 'package:emartconsumer/ui/wallet/PayFastScreen.dart';
import 'package:emartconsumer/ui/wallet/payStackScreen.dart';
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
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../constants.dart';
import '../../main.dart';
import '../../model/OrderModel.dart';
import '../../model/User.dart';
import '../../model/getPaytmTxtToken.dart';
import '../../services/helper.dart';
import '../../userPrefrence.dart';
import '../orderDetailsScreen/OrderDetailsScreen.dart';
import '../../constants/colors.dart';
import '../../constants/typography.dart';
import '../../constants/spacing.dart';
import '../../constants/border_radius.dart';

class WalletScreen extends StatefulWidget {
  /// Set to true when pushed as a standalone route (e.g. from Table Booking).
  /// Renders a proper AppBar with back button so the screen is self-contained.
  /// Keep false (default) when embedded inside ContainerScreen.
  final bool showAppBar;

  const WalletScreen({Key? key, this.showAppBar = false}) : super(key: key);

  @override
  WalletScreenState createState() => WalletScreenState();
}

class WalletScreenState extends State<WalletScreen> {
  Stream<QuerySnapshot>? topupHistoryQuery;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? userQuery;

  String? selectedRadioTile;

  final GlobalKey<FormState> _globalKey = GlobalKey();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final Razorpay _razorPay = Razorpay();
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

  final TextEditingController _amountController =
      TextEditingController(text: 50.toString());

  Map<String, dynamic>? paymentIntentData;

  final _flutterPaypalNativePlugin = FlutterPaypalNative.instance;

  showAlert(context, {required String response, required Color colors}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(response),
        backgroundColor: colors,
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
  }

  final userId = MyAppState.currentUser!.userID;

  // Wallet balance + top-up history need to be live the moment this screen
  // opens — unrelated to payment gateways, so this stays in initState.
  void _attachWalletListeners() {
    topupHistoryQuery = FireStoreUtils.firestore
        .collection(Wallet)
        .where('user_id', isEqualTo: userId)
        .orderBy('date', descending: true)
        .limit(20)
        .snapshots();
    userQuery = FireStoreUtils.firestore
        .collection(USERS)
        .doc(MyAppState.currentUser!.userID)
        .snapshots();
  }

  bool _gatewaySettingsLoadedForTopup = false;

  // Deliberately NOT called from initState — this screen is reached just by
  // opening the wallet, which many users never turn into a top-up. Gateway
  // settings are only actually consumed by the payment-method tiles inside
  // topUpBalance()'s modal, so this is called from there instead, right
  // before that modal opens. Guarded so re-tapping "Add Money" in the same
  // session doesn't re-run the UserPreference reads (ensurePaymentGatewaySettingsLoaded
  // is already memoized, but the field assignments/Stripe init below aren't).
  // Each gateway is fetched independently so a missing/unconfigured gateway
  // (jsonData! crash inside UserPreference — several of these getters throw
  // rather than return null when their SharedPreferences key was never
  // populated, e.g. every non-Razorpay gateway now that only Razorpay is
  // fetched) cannot abort the entire load. Mirrors PaymentScreen's own
  // _safeLoad helper.
  Future<T?> _safeLoad<T>(FutureOr<T?> Function() loader) async {
    try {
      return await loader();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadPaymentGatewaySettingsForTopup() async {
    if (_gatewaySettingsLoadedForTopup) return;
    _gatewaySettingsLoadedForTopup = true;

    await FireStoreUtils.ensurePaymentGatewaySettingsLoaded();

    stripeData = await _safeLoad(() => UserPreference.getStripeData());
    if (stripeData != null &&
        stripeData!.clientpublishableKey.isNotEmpty &&
        stripeData!.clientpublishableKey != 'null') {
      try {
        stripe1.Stripe.publishableKey = stripeData!.clientpublishableKey;
        stripe1.Stripe.merchantIdentifier = 'QuickDash';
        await stripe1.Stripe.instance.applySettings();
      } catch (e) {
        // Stripe initialization failed, but continue with other payment methods
      }
    }

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

    // Guarded — paypalSettingData is null whenever Paypal isn't fetched
    // (i.e. always, right now), and initPayPal() force-unwraps it.
    if (paypalSettingData != null) initPayPal();
  }

  @override
  void initState() {
    setRef();
    _attachWalletListeners();
    // Was "Stripe" - wrong now that only Razorpay is enabled in production;
    // Stripe's tile is hidden (stripeData is never fetched), so leaving the
    // old default meant tapping Pay without first manually re-selecting
    // Razorpay matched neither branch in the dispatch below and silently
    // did nothing.
    selectedRadioTile = "RazorPay";

    _razorPay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorPay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWaller);
    _razorPay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);


    // TODO: implement initState
    super.initState();
  }

  void initPayPal() async {
    //set debugMode for error logging
    FlutterPaypalNative.isDebugMode =
        paypalSettingData!.isLive == false ? true : false;
    //initiate payPal plugin
    await _flutterPaypalNativePlugin.init(
      //your app id !!! No Underscore!!! see readme.md for help
      returnUrl: "com.emart.customer://paypalpay",
      //client id from developer dashboard
      clientID: paypalSettingData!.paypalClient,
      //sandbox, staging, live etc
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
        onSuccess: (data) {
          Navigator.pop(context);
          _flutterPaypalNativePlugin.removeAllPurchaseItems();
          ShowToastDialog.showToast("Payment Successfully");
          paymentCompleted(paymentMethod: "Paypal");
        },
        onError: (data) {
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

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    final bg = dark ? const Color(0xFF0C0C0E) : const Color(0xFFF4F6FA);
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: bg,
      // AppBar is shown only in standalone mode (e.g. pushed from Table Booking).
      // When embedded inside ContainerScreen the outer scaffold provides the AppBar.
      appBar: widget.showAppBar
          ? AppBar(
              elevation: 0,
              scrolledUnderElevation: 0,
              centerTitle: true,
              backgroundColor:
                  dark ? AppThemeData.primary600 : AppThemeData.primary500,
              systemOverlayStyle: SystemUiOverlayStyle.light,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 18, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Text(
                'Wallet'.tr(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.normal,
                ),
              ),
            )
          : null,
      body: Column(
        children: [
          // ── Premium Wallet Card ────────────────────────────────────────
          _WalletCard(
            userQuery: userQuery,
            onAddMoney: topUpBalance,
            dark: dark,
          ),

          // ── Transactions header ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Transaction History".tr(),
                  style: TextStyle(
                    fontSize: 16,
                    fontFamily: AppThemeData.semiBold,
                    color: dark ? Colors.white : const Color(0xFF111111),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: dark
                        ? const Color(0xFF1C1C1E)
                        : const Color(0xFFEEF0F5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.filter_list_rounded,
                          size: 14,
                          color: dark
                              ? const Color(0xFF888888)
                              : const Color(0xFF666666)),
                      const SizedBox(width: 4),
                      Text(
                        "All".tr(),
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: AppThemeData.medium,
                          color: dark
                              ? const Color(0xFF888888)
                              : const Color(0xFF666666),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Expanded(child: showTopupHistory(context)),
        ],
      ),
    );
  }

  Widget _pmCardW({
    required bool dark,
    required bool isSelected,
    required Widget logo,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
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
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppThemeData.neutral200, width: 0.8),
              ),
              child: logo,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label, style: TextStyle(
                fontSize: 15,
                fontFamily: AppThemeData.medium,
                color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
              )),
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

  Widget buildTopUpButton() {
    return ElevatedButton(
      onPressed: () {
        topUpBalance();
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.neutral0,
        foregroundColor: AppColors.primary500,
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing6, vertical: AppSpacing.spacing3),
        textStyle: AppTypography.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: AppBorderRadius.full,
        ),
        shadowColor: Colors.transparent,
        elevation: 0,
      ),
      child: Text("TOPUP WALLET".tr()),
    );
  }

  Widget _buildTransactionSkeleton(bool dark) {
    final baseColor = dark ? AppThemeData.darkBgTertiary : AppThemeData.neutral200;
    final highlightColor = dark ? AppThemeData.darkBgSecondary : AppThemeData.neutral100;
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing4, vertical: AppSpacing.spacing2),
      itemCount: 5,
      itemBuilder: (_, i) {
        return Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.spacing1),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.4, end: 1.0),
            duration: Duration(milliseconds: 900 + i * 120),
            curve: Curves.easeInOut,
            builder: (context, value, _) {
              return Opacity(
                opacity: value,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing4, vertical: AppSpacing.spacing4),
                  decoration: BoxDecoration(
                    color: dark ? AppThemeData.darkBgSecondary : Colors.white,
                    borderRadius: AppBorderRadius.lg,
                    border: Border.all(color: dark ? AppThemeData.darkBorderSecondary : AppThemeData.neutral200, width: 0.8),
                  ),
                  child: Row(
                    children: [
                      Container(width: 46, height: 46, decoration: BoxDecoration(shape: BoxShape.circle, color: baseColor)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(height: 13, width: 160, decoration: BoxDecoration(color: baseColor, borderRadius: BorderRadius.circular(6))),
                            const SizedBox(height: 8),
                            Container(height: 10, width: 110, decoration: BoxDecoration(color: highlightColor, borderRadius: BorderRadius.circular(6))),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(height: 14, width: 60, decoration: BoxDecoration(color: baseColor, borderRadius: BorderRadius.circular(6))),
                          const SizedBox(height: 8),
                          Container(height: 18, width: 50, decoration: BoxDecoration(color: highlightColor, borderRadius: BorderRadius.circular(8))),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildHistoryEmptyState(bool dark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppThemeData.primary500.withValues(alpha: 0.08),
              ),
              child: Icon(Icons.receipt_long_rounded, size: 42, color: AppThemeData.primary500.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 20),
            Text(
              'No Transactions Yet'.tr(),
              style: TextStyle(fontSize: 17, fontFamily: AppThemeData.semiBold, color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Your wallet top-up history will appear here once you add money.'.tr(),
              style: TextStyle(fontSize: 13, fontFamily: AppThemeData.regular, color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral500, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryErrorState(bool dark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppThemeData.error500.withValues(alpha: 0.08)),
              child: Icon(Icons.wifi_off_rounded, size: 38, color: AppThemeData.error500.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 20),
            Text(
              'Could Not Load Transactions'.tr(),
              style: TextStyle(fontSize: 17, fontFamily: AppThemeData.semiBold, color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Check your connection and try again.'.tr(),
              style: TextStyle(fontSize: 13, fontFamily: AppThemeData.regular, color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral500, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.white),
              label: Text('Retry'.tr(), style: const TextStyle(fontSize: 15, fontFamily: AppThemeData.medium, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppThemeData.primary500,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget showTopupHistory(BuildContext context) {
    final dark = isDarkMode(context);
    return StreamBuilder<QuerySnapshot>(
      stream: topupHistoryQuery,
      builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (snapshot.hasError) {
          return _buildHistoryErrorState(dark);
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildTransactionSkeleton(dark);
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildHistoryEmptyState(dark);
        } else {
          // Sort newest-first client-side (avoids requiring a Firestore composite index)
          final sortedDocs = List<DocumentSnapshot>.from(docs)
            ..sort((a, b) {
              final aTs = (a.data() as Map<String, dynamic>)['date'];
              final bTs = (b.data() as Map<String, dynamic>)['date'];
              if (aTs is Timestamp && bTs is Timestamp) {
                return bTs.compareTo(aTs);
              }
              return 0;
            });
          final cards = <Widget>[];
          for (final document in sortedDocs) {
            try {
              final topUpData = TopupTranHistoryModel.fromJson(
                  document.data() as Map<String, dynamic>);
              cards.add(buildTransactionCard(
                topupTranHistory: topUpData,
                date: topUpData.date.toDate(),
              ));
            } catch (e) {
              // One malformed row must never take down the whole list.
              debugPrint('Skipping malformed wallet transaction ${document.id}: $e');
            }
          }
          if (cards.isEmpty) return _buildHistoryEmptyState(dark);
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing4, vertical: AppSpacing.spacing2),
            children: cards,
          );
        }
      },
    );
  }

  Widget buildTransactionCard({
    required TopupTranHistoryModel topupTranHistory,
    required DateTime date,
  }) {
    final dark = isDarkMode(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing1, vertical: AppSpacing.spacing1),
      child: GestureDetector(
        onTap: () => showTransactionDetails(topupTranHistory: topupTranHistory),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: AppBorderRadius.lg),
          shadowColor: Colors.transparent,
          color: dark ? AppThemeData.darkBgSecondary : AppColors.neutral0,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing2, vertical: AppSpacing.spacing4),
            child: Row(
              children: [
                ClipOval(
                  child: Container(
                    color: AppColors.primary500.withValues(alpha: 0.06),
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.spacing3),
                      child: Icon(
                        Icons.account_balance_wallet_rounded,
                        size: 28,
                        color: AppColors.primary500,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: AppSpacing.spacing4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        topupTranHistory.note.toString(),
                        style: AppTypography.bodyMedium.copyWith(
                          color: dark ? AppThemeData.darkTextPrimary : AppColors.neutral900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: AppSpacing.spacing1),
                      Text(
                        DateFormat('hh:mm a, dd MMM yyyy')
                            .format(topupTranHistory.date.toDate()),
                        style: AppTypography.caption.copyWith(
                          color: dark ? AppThemeData.darkTextTertiary : AppColors.neutral600,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      topupTranHistory.isTopup
                          ? "+ ${amountShow(amount: topupTranHistory.amount.toString())}"
                          : "- ${amountShow(amount: topupTranHistory.amount.toString())}",
                      style: AppTypography.h6.copyWith(
                        color: topupTranHistory.isTopup
                            ? AppColors.success500
                            : AppColors.error500,
                      ),
                    ),
                    SizedBox(height: AppSpacing.spacing2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: dark ? AppThemeData.darkTextTertiary : AppColors.neutral400,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  paymentCompleted({required String paymentMethod}) async {
    TopupTranHistoryModel wallet = TopupTranHistoryModel(
        amount: _amountController.text,
        order_id: '',
        serviceType: '',
        id: Uuid().v4(),
        user_id: MyAppState.currentUser!.userID,
        date: Timestamp.now(),
        isTopup: true,
        payment_method: paymentMethod,
        payment_status: "success",
        transactionUser: "customer",
        note: 'Wallet Top-up.');

    await FireStoreUtils.firestore
        .collection("wallet")
        .doc(wallet.id)
        .set(wallet.toJson())
        .then((value) async {
      await FireStoreUtils.updateWalletAmount(amount: _amountController.text)
          .then((value) async {
        await FireStoreUtils.sendTopUpMail(
            paymentMethod: paymentMethod,
            amount: _amountController.text,
            tractionId: wallet.id);
      }).whenComplete(() {
        if (_scaffoldKey.currentContext != null) {
          ScaffoldMessenger.of(_scaffoldKey.currentContext!)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text('Wallet topped up via $paymentMethod'.tr()),
              backgroundColor: Colors.green.shade600,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 4),
            ));
        }
      });
    });
  }

  showLoadingAlert() {
    return showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.6),
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
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 30, offset: const Offset(0, 10))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 52, height: 52,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppThemeData.primary500,
                      backgroundColor: AppThemeData.primary500.withValues(alpha: 0.12),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Processing Payment'.tr(),
                    style: TextStyle(
                      fontSize: 17,
                      fontFamily: AppThemeData.semiBold,
                      color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please wait while we complete your transaction.'.tr(),
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: AppThemeData.regular,
                      color: dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  showTransactionDetails({required TopupTranHistoryModel topupTranHistory}) {
    final size = MediaQuery.of(context).size;
    final dark = isDarkMode(context);
    return showModalBottomSheet(
      elevation: 0,
      backgroundColor: dark ? AppThemeData.darkBgSecondary : AppColors.neutral0,
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.xl,
      ),
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return Container(
            constraints: BoxConstraints(
              maxHeight: size.height * 0.8,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: dark ? AppThemeData.darkBorderPrimary : AppColors.neutral300,
                      borderRadius: AppBorderRadius.full,
                    ),
                  ),

                  // Header
                  Padding(
                    padding: EdgeInsets.all(AppSpacing.spacing4),
                    child: Text(
                      "Transaction Details".tr(),
                      style: AppTypography.h4.copyWith(
                        color: dark ? AppThemeData.darkTextPrimary : AppColors.neutral900,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  // Transaction ID Card
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing4, vertical: AppSpacing.spacing2),
                    child: Card(
                      elevation: 0,
                      color: dark ? AppThemeData.darkBgTertiary : AppColors.neutral50,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppBorderRadius.lg,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.spacing4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Transaction ID".tr(),
                              style: AppTypography.labelMedium.copyWith(
                                color: dark ? AppThemeData.darkTextTertiary : AppColors.neutral700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: AppSpacing.spacing2),
                            Text(
                              topupTranHistory.id,
                              style: AppTypography.bodyMedium.copyWith(
                                color: dark ? AppThemeData.darkTextPrimary : AppColors.neutral900,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Transaction Info Card
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing4, vertical: AppSpacing.spacing2),
                    child: Card(
                      elevation: 0,
                      color: dark ? AppThemeData.darkBgTertiary : AppColors.neutral50,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppBorderRadius.lg,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.spacing4),
                        child: Row(
                          children: [
                            ClipOval(
                              child: Container(
                                color: AppColors.primary500.withValues(alpha: 0.1),
                                child: Padding(
                                  padding: EdgeInsets.all(AppSpacing.spacing3),
                                  child: Icon(
                                    Icons.account_balance_wallet_rounded,
                                    size: 24,
                                    color: AppColors.primary500,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: AppSpacing.spacing4),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    DateFormat('MMM dd, yyyy • hh:mm a').format(topupTranHistory.date.toDate()),
                                    style: AppTypography.bodyMedium.copyWith(
                                      color: dark ? AppThemeData.darkTextPrimary : AppColors.neutral900,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SizedBox(height: AppSpacing.spacing1),
                                  Text(
                                    topupTranHistory.note.toString(),
                                    style: AppTypography.bodySmall.copyWith(
                                      color: dark ? AppThemeData.darkTextSecondary : AppColors.neutral600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  topupTranHistory.isTopup
                                      ? "+${amountShow(amount: topupTranHistory.amount.toString())}"
                                      : "-${amountShow(amount: topupTranHistory.amount.toString())}",
                                  style: AppTypography.h6.copyWith(
                                    color: topupTranHistory.isTopup
                                        ? AppColors.success500
                                        : AppColors.error500,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Payment Details Card
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing4, vertical: AppSpacing.spacing2),
                    child: Card(
                      elevation: 0,
                      color: dark ? AppThemeData.darkBgTertiary : AppColors.neutral50,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppBorderRadius.lg,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.spacing4),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Payment Details".tr(),
                                        style: AppTypography.labelLarge.copyWith(
                                          color: dark ? AppThemeData.darkTextPrimary : AppColors.neutral900,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      SizedBox(height: AppSpacing.spacing2),
                                      Row(
                                        children: [
                                          Text(
                                            "Pay Via".tr(),
                                            style: AppTypography.bodyMedium.copyWith(
                                              color: dark ? AppThemeData.darkTextSecondary : AppColors.neutral600,
                                            ),
                                          ),
                                          if (!topupTranHistory.isTopup) ...[
                                            SizedBox(width: AppSpacing.spacing2),
                                            Text(
                                              topupTranHistory.payment_method.toUpperCase(),
                                              style: AppTypography.bodyMedium.copyWith(
                                                color: AppColors.primary500,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (!topupTranHistory.isTopup)
                                  ElevatedButton(
                                    onPressed: () async {
                                      FireStoreUtils.firestore
                                          .collection(ORDERS)
                                          .doc(topupTranHistory.order_id)
                                          .get()
                                          .then((value) {
                                        if (!value.exists || value.data() == null) return;
                                        OrderModel orderModel = OrderModel.fromJson(value.data()!);
                                        push(context, OrderDetailsScreen(orderModel: orderModel));
                                      });
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary500,
                                      foregroundColor: AppColors.neutral0,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: AppSpacing.spacing4,
                                        vertical: AppSpacing.spacing2,
                                      ),
                                      textStyle: AppTypography.labelMedium,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: AppBorderRadius.md,
                                      ),
                                      elevation: 0,
                                    ),
                                    child: Text("View Order".tr()),
                                  )
                                else
                                  Text(
                                    topupTranHistory.payment_method.toUpperCase(),
                                    style: AppTypography.labelLarge.copyWith(
                                      color: AppColors.primary500,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),

                            SizedBox(height: AppSpacing.spacing4),

                            Container(
                              height: 1,
                              color: dark ? AppThemeData.darkBorderSecondary : AppColors.neutral200,
                            ),

                            SizedBox(height: AppSpacing.spacing4),

                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Date".tr(),
                                        style: AppTypography.labelMedium.copyWith(
                                          color: dark ? AppThemeData.darkTextTertiary : AppColors.neutral700,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      SizedBox(height: AppSpacing.spacing2),
                                      Text(
                                        DateFormat('MMM dd, yyyy  HH:mm').format(topupTranHistory.date.toDate()),
                                        style: AppTypography.bodyMedium.copyWith(
                                          color: dark ? AppThemeData.darkTextPrimary : AppColors.neutral900,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: AppSpacing.spacing4),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Future<void> topUpBalance() async {
    // (2026-08-11) Pure activity update, non-blocking — same treatment as
    // Order/Wallet-paid-order/Bill Pay/Table Booking (see paymentIntents.js'
    // checkDeviceSession() call sites). Ownership can only change/be
    // enforced at login; a superseded-device result here must never
    // prevent or cancel the top-up. checkActive() still refreshes
    // last_active_at server-side (DeviceSessionController::checkSession)
    // when this happens to still be the active device — its boolean
    // result is deliberately discarded, never passed to
    // handleSessionInvalidated the way enforceActive() used to.
    // ignore: unawaited_futures
    DeviceSessionService.checkActive();
    // Loaded here, immediately before the payment-method modal opens, not
    // in initState — see _loadPaymentGatewaySettingsForTopup's doc comment.
    await _loadPaymentGatewaySettingsForTopup();
    final size = MediaQuery.of(context).size;
    bool isProcessingTopup = false;
    return showModalBottomSheet(
        elevation: 0,
        enableDrag: true,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: isDarkMode(context) ? AppThemeData.darkBgSecondary : Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20), topRight: Radius.circular(20))),
        context: context,
        builder: (context) {
          return FractionallySizedBox(
            heightFactor: 0.94,
            child: StatefulBuilder(
              builder: (context, setModalState) => SizedBox(
                width: size.width,
                child: Form(
                  key: _globalKey,
                  autovalidateMode: AutovalidateMode.always,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Drag handle
                        Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isDarkMode(context) ? AppThemeData.darkBorderPrimary : AppThemeData.neutral300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing4, vertical: AppSpacing.spacing1),
                          child: Row(
                            children: [
                              Text(
                                "Add Money".tr(),
                                style: AppTypography.h3.copyWith(
                                  color: isDarkMode(context) ? AppColors.darkTextPrimary : AppColors.neutral900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing6, vertical: AppSpacing.spacing2),
                          child: Text(
                            "Add Topup Amount".tr(),
                            style: AppTypography.labelMedium.copyWith(
                              color: isDarkMode(context) ? AppColors.darkTextPrimary : AppColors.neutral700,
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing6, vertical: AppSpacing.spacing0),
                          child: TextFormField(
                            controller: _amountController,
                            style: AppTypography.bodyMedium.copyWith(color: AppColors.neutral800),
                            maxLines: 1,
                            validator: (value) {
                              if (value!.isEmpty) {
                                return "*required Field".tr();
                              } else {
                                return null;
                              }
                            },
                            keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                            textInputAction: TextInputAction.done,
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9]'))],
                            decoration: InputDecoration(
                              prefix: currencyData != null ? Padding(
                                padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing4, vertical: AppSpacing.spacing0),
                                child: Text(
                                  currencyData!.symbol.toString(),
                                  style: AppTypography.bodyMedium.copyWith(color: AppColors.neutral800),
                                ),
                              ) : null,
                              border: OutlineInputBorder(
                                borderRadius: AppBorderRadius.lg,
                                borderSide: BorderSide(color: AppColors.neutral300, width: 1),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: AppBorderRadius.lg,
                                borderSide: BorderSide(color: AppColors.neutral300, width: 1),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: AppBorderRadius.lg,
                                borderSide: BorderSide(color: AppColors.primary500, width: 2),
                              ),
                              contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing4, vertical: AppSpacing.spacing3),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing6, vertical: AppSpacing.spacing1),
                              child: Text(
                                "Select Payment Option".tr(),
                                style: AppTypography.bodyMedium.copyWith(
                                  color: isDarkMode(context) ? AppColors.darkTextPrimary : AppColors.neutral900,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (stripeData?.isEnabled ?? false) _pmCardW(
                          dark: isDarkMode(context),
                          isSelected: stripe,
                          logo: Image.asset('assets/images/stripe.png', fit: BoxFit.contain),
                          label: 'Stripe'.tr(),
                          onTap: () => setModalState(() {
                            stripe = true; razorPay = false; payTm = false; paypal = false;
                            payStack = false; flutterWave = false; payFast = false; mercadoPago = false;
                            orange = false; Midtrans = false; xendit = false;
                            selectedRadioTile = 'Stripe';
                          }),
                        ),
                        if (payStackSettingData?.isEnabled ?? false) _pmCardW(
                          dark: isDarkMode(context),
                          isSelected: payStack,
                          logo: Image.asset('assets/images/paystack.png', fit: BoxFit.contain),
                          label: 'PayStack'.tr(),
                          onTap: () => setModalState(() {
                            payStack = true; stripe = false; razorPay = false; payTm = false;
                            paypal = false; flutterWave = false; payFast = false; mercadoPago = false;
                            orange = false; Midtrans = false; xendit = false;
                            selectedRadioTile = 'PayStack';
                          }),
                        ),
                        Visibility(
                          visible: flutterWaveSettingData?.isEnable ?? false,
                          child: _pmCardW(
                            dark: isDarkMode(context),
                            isSelected: flutterWave,
                            logo: Image.asset('assets/images/flutterwave.png', fit: BoxFit.contain),
                            label: 'FlutterWave'.tr(),
                            onTap: () => setModalState(() {
                              flutterWave = true; stripe = false; razorPay = false; payTm = false;
                              paypal = false; payStack = false; payFast = false; mercadoPago = false;
                              orange = false; Midtrans = false; xendit = false;
                              selectedRadioTile = 'FlutterWave';
                            }),
                          ),
                        ),
                        if (razorPayData?.isEnabled ?? false) _pmCardW(
                          dark: isDarkMode(context),
                          isSelected: razorPay,
                          logo: Image.asset('assets/images/razorpay_@3x.png', fit: BoxFit.contain),
                          label: 'RazorPay'.tr(),
                          onTap: () => setModalState(() {
                            razorPay = true; stripe = false; payTm = false; paypal = false;
                            payStack = false; flutterWave = false; payFast = false; mercadoPago = false;
                            orange = false; Midtrans = false; xendit = false;
                            selectedRadioTile = 'RazorPay';
                          }),
                        ),
                        if (payFastSettingData?.isEnable ?? false) _pmCardW(
                          dark: isDarkMode(context),
                          isSelected: payFast,
                          logo: Image.asset('assets/images/payfast.png', fit: BoxFit.contain),
                          label: 'Payfast'.tr(),
                          onTap: () => setModalState(() {
                            payFast = true; stripe = false; razorPay = false; payTm = false;
                            paypal = false; payStack = false; flutterWave = false; mercadoPago = false;
                            orange = false; Midtrans = false; xendit = false;
                            selectedRadioTile = 'payFast';
                          }),
                        ),
                        if (paytmSettingData?.isEnabled ?? false) _pmCardW(
                          dark: isDarkMode(context),
                          isSelected: payTm,
                          logo: Image.asset('assets/images/paytm_@3x.png', fit: BoxFit.contain),
                          label: 'Paytm'.tr(),
                          onTap: () => setModalState(() {
                            payTm = true; stripe = false; razorPay = false; paypal = false;
                            payStack = false; flutterWave = false; payFast = false; mercadoPago = false;
                            orange = false; Midtrans = false; xendit = false;
                            selectedRadioTile = 'PayTm';
                          }),
                        ),
                        if (mercadoPagoSettingData?.isEnabled ?? false) _pmCardW(
                          dark: isDarkMode(context),
                          isSelected: mercadoPago,
                          logo: Image.asset('assets/images/mercadopago.png', fit: BoxFit.contain),
                          label: 'Mercado Pago'.tr(),
                          onTap: () => setModalState(() {
                            mercadoPago = true; stripe = false; razorPay = false; payTm = false;
                            paypal = false; payStack = false; flutterWave = false; payFast = false;
                            orange = false; Midtrans = false; xendit = false;
                            selectedRadioTile = 'MercadoPago';
                          }),
                        ),
                        if (paypalSettingData?.isEnabled ?? false) _pmCardW(
                          dark: isDarkMode(context),
                          isSelected: paypal,
                          logo: Image.asset('assets/images/paypal_@3x.png', fit: BoxFit.contain),
                          label: 'PayPal'.tr(),
                          onTap: () => setModalState(() {
                            paypal = true; stripe = false; razorPay = false; payTm = false;
                            payStack = false; flutterWave = false; payFast = false; mercadoPago = false;
                            orange = false; Midtrans = false; xendit = false;
                            selectedRadioTile = 'PayPal';
                          }),
                        ),
                        if (xenditModel?.enable ?? false) _pmCardW(
                          dark: isDarkMode(context),
                          isSelected: xendit,
                          logo: Image.asset('assets/images/xendit.png', fit: BoxFit.contain),
                          label: 'Xendit'.tr(),
                          onTap: () => setModalState(() {
                            xendit = true; stripe = false; razorPay = false; payTm = false;
                            paypal = false; payStack = false; flutterWave = false; mercadoPago = false;
                            orange = false; Midtrans = false; payFast = false;
                            selectedRadioTile = 'Xendit';
                          }),
                        ),
                        if (orangeMoneyModel?.enable ?? false) _pmCardW(
                          dark: isDarkMode(context),
                          isSelected: orange,
                          logo: Image.asset('assets/images/orange_money.png', fit: BoxFit.contain),
                          label: 'OrangeMoney'.tr(),
                          onTap: () => setModalState(() {
                            orange = true; stripe = false; razorPay = false; payTm = false;
                            paypal = false; payStack = false; flutterWave = false; mercadoPago = false;
                            Midtrans = false; xendit = false; payFast = false;
                            selectedRadioTile = 'OrangeMoney';
                          }),
                        ),
                        if (midTransModel?.enable ?? false) _pmCardW(
                          dark: isDarkMode(context),
                          isSelected: Midtrans,
                          logo: Image.asset('assets/images/midtrans.png', fit: BoxFit.contain),
                          label: 'Midtrans'.tr(),
                          onTap: () => setModalState(() {
                            Midtrans = true; stripe = false; razorPay = false; payTm = false;
                            paypal = false; payStack = false; flutterWave = false; mercadoPago = false;
                            orange = false; xendit = false; payFast = false;
                            selectedRadioTile = 'Midtrans';
                          }),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: AppSpacing.spacing5, horizontal: AppSpacing.spacing6),
                          child: SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                            onPressed: isProcessingTopup ? null : () async {
                              if (!(_globalKey.currentState?.validate() ?? false)) return;
                              final amtStr = _amountController.text.trim();
                              if (amtStr.isEmpty || (double.tryParse(amtStr) ?? 0) <= 0) {
                                showAlert(context, response: 'Please enter a valid amount'.tr(), colors: AppColors.error500);
                                return;
                              }
                              setModalState(() => isProcessingTopup = true);
                              if (selectedRadioTile == "Stripe" && (stripeData?.isEnabled ?? false)) {
                                Navigator.pop(context);
                                showLoadingAlert();
                                stripeMakePayment(amount: _amountController.text);
                              } else if (selectedRadioTile == "MercadoPago" && (mercadoPagoSettingData?.isEnabled ?? false)) {
                                Navigator.pop(context);
                                showLoadingAlert();
                                mercadoPagoMakePayment();
                              } else if (selectedRadioTile == "payFast" && (payFastSettingData?.isEnable ?? false)) {
                                Navigator.pop(context);
                                showLoadingAlert();
                                try {
                                  final html = await PayStackURLGen.getPayHTML(
                                    payFastSettingData: payFastSettingData!,
                                    amount: _amountController.text,
                                  );
                                  if (!mounted) return;
                                  final bool isDone = await Navigator.of(this.context).push(MaterialPageRoute(
                                    builder: (ctx) => PayFastScreen(
                                      htmlData: html,
                                      payFastSettingData: payFastSettingData!,
                                    ),
                                  ));
                                  if (!mounted) return;
                                  Navigator.pop(this.context);
                                  if (isDone) {
                                    await paymentCompleted(paymentMethod: "PayFast");
                                  } else {
                                    ScaffoldMessenger.of(_scaffoldKey.currentContext!)
                                      ..hideCurrentSnackBar()
                                      ..showSnackBar(SnackBar(
                                        content: Text("Payment Cancelled or Unsuccessful.".tr()),
                                        backgroundColor: AppColors.error500,
                                        duration: const Duration(seconds: 4),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ));
                                  }
                                } catch (e) {
                                  if (mounted) Navigator.pop(this.context);
                                  ShowToastDialog.showToast("Payment failed. Please try again.");
                                }
                              } else if (selectedRadioTile == "RazorPay" && (razorPayData?.isEnabled ?? false)) {
                                Navigator.pop(context);
                                showLoadingAlert();
                                RazorPayController().createWalletTopupOrder(
                                  amount: double.parse(_amountController.text),
                                ).then((result) {
                                  // Use this.context (wallet state) — the bottom-sheet context captured
                                  // in the closure is deactivated by this point.
                                  if (mounted) Navigator.of(this.context, rootNavigator: true).pop();
                                  if (result.success) {
                                    openCheckout(amount: result.amount.toInt(), orderId: result.razorpayOrderId!);
                                  } else {
                                    if (mounted) showAlert(this.context,
                                      response: result.errorMessage?.tr() ?? "Something went wrong, please contact admin.".tr(),
                                      colors: AppColors.error500,
                                    );
                                  }
                                });
                              } else if (selectedRadioTile == "PayPal" && (paypalSettingData?.isEnabled ?? false)) {
                                Navigator.pop(context);
                                showLoadingAlert();
                                paypalPaymentSheet();
                              } else if (selectedRadioTile == "PayStack" && (payStackSettingData?.isEnabled ?? false)) {
                                Navigator.pop(context);
                                showLoadingAlert();
                                payStackPayment();
                              } else if (selectedRadioTile == "FlutterWave" && (flutterWaveSettingData?.isEnable ?? false)) {
                                Navigator.pop(context);
                                showLoadingAlert();
                                _flutterWaveInitiatePayment();
                              } else if (selectedRadioTile == "Midtrans" && (midTransModel?.enable ?? false)) {
                                Navigator.pop(context);
                                showLoadingAlert();
                                midtransMakePayment(amount: _amountController.text);
                              } else if (selectedRadioTile == "OrangeMoney" && (orangeMoneyModel?.enable ?? false)) {
                                Navigator.pop(context);
                                showLoadingAlert();
                                orangeMakePayment(amount: _amountController.text);
                              } else if (selectedRadioTile == "Xendit" && (xenditModel?.enable ?? false)) {
                                Navigator.pop(context);
                                showLoadingAlert();
                                xenditPayment(_amountController.text);
                              } else {
                                setModalState(() => isProcessingTopup = false);
                                showAlert(context,
                                  response: 'Please select a payment method'.tr(),
                                  colors: AppColors.error500,
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppThemeData.primary500,
                              disabledBackgroundColor: AppThemeData.primary500.withValues(alpha: 0.5),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                            child: isProcessingTopup
                                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                : Text('Continue'.tr(), style: const TextStyle(fontSize: 16, fontFamily: AppThemeData.semiBold, color: Colors.white)),
                          ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        });
  }

  // Was stripe=true/razorPay=false, matching the old selectedRadioTile
  // default - flipped to match the new one now that only Razorpay is
  // enabled, so the visible tile's card is actually shown pre-highlighted
  // instead of looking unselected despite being the dispatch default.
  bool stripe = false;

  bool razorPay = true;
  bool payTm = false;
  bool paypal = false;
  bool payStack = false;
  bool flutterWave = false;
  bool payFast = false;
  bool mercadoPago = false;
  bool xendit = false;
  bool orange = false;
  bool Midtrans = false;

  ///
  ///
  ///

  /// RazorPay Payment Gateway
  void openCheckout({required int amount, required String orderId}) async {
    var options = {
      'key': razorPayData!.razorpayKey,
      'amount': amount * 100,
      'name': 'QuickDash',
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
      debugPrint('RazorPay open error: $e');
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    // The wallet is credited server-side, inside verifyPayment, only once
    // the Razorpay signature checks out — unlike paymentCompleted() (used by
    // the other gateways above), this never trusts _amountController.text.
    final result = await RazorPayController().verifyPayment(
      razorpayOrderId: response.orderId ?? '',
      razorpayPaymentId: response.paymentId ?? '',
      razorpaySignature: response.signature ?? '',
      purpose: 'wallet_topup',
    );
    if (!mounted) return;
    if (result.success) {
      ScaffoldMessenger.of(_scaffoldKey.currentContext!)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Wallet topped up via RazorPay'.tr()),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 4),
        ));
    } else {
      showAlert(context,
          response: result.errorMessage?.tr() ?? 'Payment verification failed. Please contact support.'.tr(),
          colors: AppColors.error500);
    }
  }

  void _handleExternalWaller(ExternalWalletResponse response) {
    // Loading dialog is already dismissed before openCheckout() is called — do not pop here.
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          "Payment Processing Via".tr() + "\n" + response.walletName!,
        ),
        backgroundColor: Colors.blue.shade400,
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    // Loading dialog is already dismissed before openCheckout() is called — do not pop here.
    if (!mounted) return;
    String description = 'Payment failed. Please try again.'.tr();
    try {
      final msg = response.message;
      if (msg != null && msg.isNotEmpty && msg != 'undefined') {
        final decoded = jsonDecode(msg);
        description = decoded['error']?['description']?.toString() ?? description;
      }
    } catch (_) {}
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text("Payment Failed!!".tr() + "\n" + description),
        backgroundColor: AppThemeData.primary500,
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
  }

  /// PayPal Payment Gateway
  paypalPaymentSheet() {
    //add 1 item to cart. Max is 4!
    if (_flutterPaypalNativePlugin.canAddMorePurchaseUnit) {
      _flutterPaypalNativePlugin.addPurchaseUnit(
        FPayPalPurchaseUnit(
          // random prices
          amount: double.parse(_amountController.text),

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

  /// Stripe Payment Gateway
  Future<void> stripeMakePayment({required String amount}) async {
    try {
      paymentIntentData = await createStripeIntent(
        amount,
      );
      if (paymentIntentData!.containsKey("error")) {
        Navigator.pop(context);
        showAlert(_scaffoldKey.currentContext,
            response: "Something went wrong, please contact admin.".tr(),
            colors: AppThemeData.primary500);
      } else {
        print(
            '----->paymentIntentData :${paymentIntentData!['client_secret']}');
        await stripe1.Stripe.instance
            .initPaymentSheet(
                paymentSheetParameters: stripe1.SetupPaymentSheetParameters(
              paymentIntentClientSecret: paymentIntentData!['client_secret'],
              customerEphemeralKeySecret: paymentIntentData!['ephemeralKey'],
              customerId: paymentIntentData!['customer'],
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
                  primary: AppColors.primary500,
                ),
              ),
              merchantDisplayName: 'QuickDash',
            ))
            .then((value) {});
        setState(() {});
        displayStripePaymentSheet();
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ShowToastDialog.showToast("Payment failed. Please try again.");
    }
  }

  displayStripePaymentSheet() async {
    try {
      await stripe1.Stripe.instance.presentPaymentSheet().then((value) async {
        Navigator.pop(context);
        paymentCompleted(paymentMethod: "Stripe");
        paymentIntentData = null;
      });
    } on stripe1.StripeException catch (_) {
      Navigator.pop(context);
      AppDialog.showError(context, message: 'Payment failed. Please try again.');
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
        content: Text("$e"),
        duration: const Duration(seconds: 8),
        backgroundColor: AppThemeData.primary500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
    final a = (int.parse(amount)) * 100;
    return a.toString();
  }

  /// Paytm Payment Gateway
  bool isStaging = true;
  String callbackUrl =
      "http://162.241.125.167/~foodie/payments/paytmpaymentcallback?ORDER_ID=";
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

    await verifyCheckSum(
            checkSum: data["code"], amount: amount, orderId: orderId)
        .then((value) {
      initiatePayment(context, amount: amount, orderId: orderId).then((value) {
        GetPaymentTxtTokenModel result = value;
        String callback = "";
        if (paytmSettingData!.isSandboxEnabled) {
          callback = callback +
              "https://securegw-stage.paytm.in/theia/paytmCallback?ORDER_ID=$orderId";
        } else {
          callback = callback +
              "https://securegw.paytm.in/theia/paytmCallback?ORDER_ID=$orderId";
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

  Future<GetPaymentTxtTokenModel> initiatePayment(BuildContext context,
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
    if (data["body"]["txnToken"] == null ||
        data["body"]["txnToken"].toString().isEmpty) {
      Navigator.pop(_scaffoldKey.currentContext!);
      showAlert(_scaffoldKey.currentContext!,
          response: "something went wrong, please contact admin.".tr(),
          colors: AppThemeData.primary500);
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

  ///PayStack Payment Method
  payStackPayment() async {
    try {
      final value = await PayStackURLGen.payStackURLGen(
        amount: (double.parse(_amountController.text) * 100).toString(),
        currency: currencyData!.code,
        secretKey: payStackSettingData!.secretKey,
      );

      if (!mounted) return;

      if (value != null) {
        final PayStackUrlModel payStackModel = value;
        final bool isDone = await Navigator.of(context).push(MaterialPageRoute(
            builder: (ctx) => PayStackScreen(
                  secretKey: payStackSettingData!.secretKey,
                  callBackUrl: payStackSettingData!.callbackURL,
                  initialURl: payStackModel.data.authorizationUrl,
                  amount: _amountController.text,
                  reference: payStackModel.data.reference,
                )));

        if (!mounted) return;
        Navigator.pop(context);  // Dismiss loading dialog

        if (isDone) {
          paymentCompleted(paymentMethod: "PayStack");
        } else {
          ScaffoldMessenger.of(_scaffoldKey.currentContext!)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
            content: Text("Payment Cancelled or Unsuccessful.".tr()),
            backgroundColor: AppThemeData.primary500,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ));
        }
      } else {
        Navigator.pop(context);  // Dismiss loading dialog on URL generation failure
        ScaffoldMessenger.of(_scaffoldKey.currentContext!)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
          content: Text("Error while setting up payment. Please try again.".tr()),
          backgroundColor: AppThemeData.primary500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ShowToastDialog.showToast("Payment failed. Please try again.");
    }
  }

  ///MercadoPago Payment Method

  mercadoPagoMakePayment() async {
    try {
      final headers = {
        'Authorization': 'Bearer ${mercadoPagoSettingData!.accessToken}',
        'Content-Type': 'application/json',
      };

      final body = jsonEncode({
        "items": [
          {
            "title": "Wallet Top-up",
            "description": "Wallet Top-up",
            "quantity": 1,
            "currency_id": currencyData?.code ?? "BRL",
            "unit_price": double.parse(_amountController.text),
          }
        ],
        "payer": {"email": MyAppState.currentUser!.email},
        "back_urls": {
          "failure": "${GlobalURL}payment/failure",
          "pending": "${GlobalURL}payment/pending",
          "success": "${GlobalURL}payment/success",
        },
        "auto_return": "approved"
      });

      final response = await http.post(
        Uri.parse("https://api.mercadopago.com/checkout/preferences"),
        headers: headers,
        body: body,
      );

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final bool isDone = await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (ctx) =>
                    MercadoPagoScreen(initialURl: data['init_point'])));

        if (!mounted) return;
        // Dismiss the loading dialog that was shown before this method was called
        Navigator.pop(context);

        if (isDone) {
          ShowToastDialog.showToast("Payment Successful!!");
          paymentCompleted(paymentMethod: "MercadoPago");
        } else {
          ShowToastDialog.showToast("Payment Cancelled or Unsuccessful.");
        }
      } else {
        Navigator.pop(context);
        ShowToastDialog.showToast("Payment setup failed. Please try again.");
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ShowToastDialog.showToast("Payment failed. Please try again.");
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

  _flutterWaveInitiatePayment() async {
    try {
      final url = Uri.parse('https://api.flutterwave.com/v3/payments');
      final headers = {
        'Authorization': 'Bearer ${flutterWaveSettingData!.secretKey}',
        'Content-Type': 'application/json',
      };

      final body = jsonEncode({
        "tx_ref": _ref,
        "amount": _amountController.text,
        "currency": currencyData?.code ?? "NGN",
        "redirect_url": "${GlobalURL}payment/success",
        "payment_options": "ussd, card, barter, payattitude",
        "customer": {
          "email": MyAppState.currentUser!.email.toString(),
          "phonenumber": MyAppState.currentUser!.phoneNumber,
          "name": MyAppState.currentUser!.fullName(),
        },
        "customizations": {
          "title": "Wallet Top-up",
          "description": "Wallet Top-up via FlutterWave",
        }
      });

      final response = await http.post(url, headers: headers, body: body);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final bool isDone = await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (ctx) =>
                    MercadoPagoScreen(initialURl: data['data']['link'])));

        if (!mounted) return;
        Navigator.pop(context);

        if (isDone) {
          ShowToastDialog.showToast("Payment Successful!!");
          paymentCompleted(paymentMethod: "FlutterWave");
        } else {
          ShowToastDialog.showToast("Payment Cancelled or Unsuccessful.");
        }
      } else {
        Navigator.pop(context);
        ShowToastDialog.showToast("Payment setup failed. Please try again.");
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ShowToastDialog.showToast("Payment failed. Please try again.");
    }
  }

  //Midtrans payment
  midtransMakePayment({required String amount}) async {
    try {
      final url = await createPaymentLink(amount: amount);
      if (!mounted) return;
      if (url.isNotEmpty) {
        final bool isDone = await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (ctx) => MidtransScreen(initialURl: url)));
        if (!mounted) return;
        Navigator.pop(context);
        if (isDone) {
          ShowToastDialog.showToast("Payment Successful!!");
          paymentCompleted(paymentMethod: "Midtrans");
        } else {
          ShowToastDialog.showToast("Payment Cancelled or Unsuccessful.");
        }
      } else {
        Navigator.pop(context);
        ShowToastDialog.showToast("Payment setup failed. Please try again.");
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ShowToastDialog.showToast("Payment failed. Please try again.");
    }
  }

  Future<String> createPaymentLink({required var amount}) async {
    var ordersId = const Uuid().v1();
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

  orangeMakePayment({required String amount}) async {
    try {
      reset();
      var id = const Uuid().v4();
      var paymentURL = await fetchToken(
          context: context, orderId: id, amount: amount, currency: 'USD');
      if (!mounted) return;
      if (paymentURL.toString().isNotEmpty) {
        final bool isDone = await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (ctx) => OrangeMoneyScreen(
                      initialURl: paymentURL,
                      accessToken: accessToken,
                      amount: amount,
                      orangePay: orangeMoneyModel!,
                      orderId: orderId,
                      payToken: payToken,
                    )));
        if (!mounted) return;
        Navigator.pop(context);
        if (isDone) {
          ShowToastDialog.showToast("Payment Successful!!");
          paymentCompleted(paymentMethod: "OrangeMoney");
        } else {
          ShowToastDialog.showToast("Payment Cancelled or Unsuccessful.");
        }
      } else {
        Navigator.pop(context);
        ShowToastDialog.showToast("Payment setup failed. Please try again.");
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ShowToastDialog.showToast("Payment failed. Please try again.");
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
  xenditPayment(amount) async {
    try {
      final model = await createXenditInvoice(amount: amount);
      if (!mounted) return;
      if (model.id != null) {
        final bool isDone = await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (ctx) => XenditScreen(
                      initialURl: model.invoiceUrl ?? '',
                      transId: model.id ?? '',
                      apiKey: xenditModel!.apiKey!.toString(),
                    )));
        if (!mounted) return;
        Navigator.pop(context);
        if (isDone) {
          ShowToastDialog.showToast("Payment Successful!!");
          paymentCompleted(paymentMethod: "Xendit");
        } else {
          ShowToastDialog.showToast("Payment Cancelled or Unsuccessful.");
        }
      } else {
        Navigator.pop(context);
        ShowToastDialog.showToast("Payment setup failed. Please try again.");
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ShowToastDialog.showToast("Payment failed. Please try again.");
    }
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

  Future<void> showLoading(
      {required String message, Color txtColor = Colors.black}) {
    return AppDialog.showInfo(context, message: message);
  }

  @override
  void dispose() {
    _razorPay.clear(); // Remove all Razorpay event listeners
    super.dispose();
  }
}

enum PaymentOptionString {
  RazorPay,
  Stripe,
  PayTm,
  PayPal,
  PayStack,
  FlutterWave
}

class _WalletCard extends StatelessWidget {
  final Stream<DocumentSnapshot<Map<String, dynamic>>>? userQuery;
  final VoidCallback onAddMoney;
  final bool dark;

  const _WalletCard({
    required this.userQuery,
    required this.onAddMoney,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userQuery,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSkeleton(dark);
        }
        double balance = 0;
        if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
          try {
            final user = User.fromJson(snapshot.data!.data()!);
            balance = user.wallet_amount.toDouble();
          } catch (_) {}
        }
        return _buildCard(context, balance, dark);
      },
    );
  }

  Widget _buildSkeleton(bool dark) {
    final baseColor = dark ? const Color(0xFF1A0A2E) : AppColors.primary500;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      height: 168,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [baseColor, baseColor.withValues(alpha: 0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Center(
        child: SizedBox(
          width: 32, height: 32,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white54),
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, double balance, bool dark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary600, AppColors.primary400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: AppColors.primary500.withValues(alpha: 0.38), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18, top: -18,
            child: Container(
              width: 120, height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            right: 40, bottom: -30,
            child: Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Text('My Wallet'.tr(), style: const TextStyle(
                      color: Colors.white70, fontSize: 14,
                      fontFamily: AppThemeData.medium,
                    )),
                  ],
                ),
                const SizedBox(height: 16),
                Text(amountShow(amount: balance.toStringAsFixed(2)),
                  style: const TextStyle(
                    color: Colors.white, fontSize: 32,
                    fontFamily: AppThemeData.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text('Available Balance'.tr(), style: const TextStyle(
                  color: Colors.white60, fontSize: 12, fontFamily: AppThemeData.regular,
                )),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton.icon(
                    onPressed: onAddMoney,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppThemeData.primary500,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text('Add Money'.tr(), style: const TextStyle(
                      fontSize: 14, fontFamily: AppThemeData.semiBold,
                    )),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
