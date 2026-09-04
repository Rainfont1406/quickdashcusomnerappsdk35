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
import 'package:emartconsumer/services/behavior/behavior_event_types.dart';
import 'package:emartconsumer/services/behavior/behavior_tracker.dart';
import 'package:emartconsumer/services/device_session_service.dart';
import 'package:emartconsumer/services/firestore_instrumentation.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/services/notification_service.dart';
import 'package:emartconsumer/services/paystack_url_genrater.dart';
import 'package:emartconsumer/services/rozorpayConroller.dart';
import 'package:emartconsumer/services/app_dialog.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/services/upi_apps_service.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/theme/round_button_fill.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
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
import 'package:url_launcher/url_launcher.dart';

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
  // Phase 1 real-time seat availability - only set when orderType == 'Dining'
  // at a vendor that opted in (CartScreen only shows the picker then).
  final int? diningGuestCount;

  // Vendor-initiated Bill Pay accept flow: the customer paid through a
  // brand-new, completely normal order (see CartScreen's Bill Pay mode) —
  // this just links it back to the original request doc so a Cloud Function
  // can reconcile that document afterward. Also passed to the
  // createVerifiedOrderPayment/createVerifiedWalletOrder calls below so the
  // server recomputes the charge from the LIVE request doc instead of
  // whatever `products` this screen was built with.
  final String? billPayRequestId;
  // billPayExpiresAt.millisecondsSinceEpoch captured when CartScreen loaded
  // the bill — lets the server detect the vendor edited it since then (see
  // resolveBillPayAmount in paymentIntents.js) and reject with the fresh
  // total instead of charging a stale one.
  final int? expectedBillVersion;

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
      this.orderType,
      this.diningGuestCount,
      this.billPayRequestId,
      this.expectedBillVersion})
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

  // Phase 1 real-time seat availability - shown on THIS screen (right
  // before the customer commits to paying) rather than on the vendor
  // product/menu screen, so it's relevant at the moment it actually
  // matters instead of noise while just browsing. Only fetched at all for
  // a Dining order (widget.orderType == 'Dining') - other order types
  // never need this. Created once in initState, not inline in build(), so
  // the StreamBuilder keeps one stable Firestore listener for the whole
  // screen visit instead of reopening it on every rebuild. See
  // TABLE_BOOKING_CAPACITY_AND_DEPOSIT_PLAN.html.
  Stream<SeatAvailability?>? _seatAvailabilityStream;
  // Set alongside _seatAvailabilityStream in _loadSeatAvailability - needed
  // here (not just passed straight into the stream) so the guest-count
  // picker below can check seatCapacity/seatAvailabilityEnabled/seatingMode itself.
  VendorModel? _diningVendor;

  // Guest-count input for a Dining order (2026-08-25 - moved here from
  // CartScreen so it's asked right before the customer commits to paying,
  // same reasoning as the seat-availability banner itself living here).
  // Defaults from whatever CartScreen still passes in (back-compat), else 1.
  late int _diningGuestCount = widget.diningGuestCount ?? 1;

  // Set in _loadSeatAvailability if this customer already has an active
  // table booking at this vendor today (2026-08-28) - when non-null, the
  // picker below shows this count read-only instead of the interactive
  // stepper, since the customer already told us their party size at
  // booking time. Null means "no existing booking," not "zero guests" -
  // the normal picker applies in that case.
  int? _existingBookingGuestCount;

  // Guest-count sheet (2026-09-01, at the user's request) - the picker used
  // to be a small inline banner on the default payment page, easy to miss.
  // For a Dining order at a vendor with seat capacity configured, it's now
  // asked in its own blocking modal sheet BEFORE the payment methods render
  // at all - see _maybeShowGuestCountSheet, triggered once
  // _loadSeatAvailability resolves _diningVendor. _guestSheetHandled guards
  // against showing it more than once per screen visit; _guestCountConfirmed
  // gates _buildDefaultPaymentPage's payment-methods section until "Next" is
  // tapped. Both are irrelevant (treated as already-satisfied) whenever
  // _showDiningGuestPicker is false.
  bool _guestSheetHandled = false;
  bool _guestCountConfirmed = false;

  bool get _showDiningGuestPicker =>
      widget.orderType == 'Dining' &&
      _diningVendor?.effectiveSeatCapacity != null &&
      _diningVendor?.seatAvailabilityEnabled == true &&
      _diningVendor?.seatAvailabilityOn == true &&
      _diningVendor?.seatingMode != 'full_session';

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Real installed-UPI-app detection (2026-08-31) - null while still
  // loading, empty if none detected (or non-Android/detection failed, in
  // which case the default payment page falls back to a single generic
  // "Other UPI Apps" tile). See UpiAppsService/MainActivity.kt.
  List<InstalledUpiApp>? _installedUpiApps;

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
        .snapshotsLogged('getPaymentSettingData:USERS');

    // CartScreen already triggered this on the way in here, but that call
    // is fire-and-forget — awaiting the same memoized Future is what
    // guarantees UserPreference's cache below is actually populated by the
    // time we read it, whether CartScreen's call already finished or is
    // still in flight.
    await FireStoreUtils.ensurePaymentGatewaySettingsLoaded();

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

  showAlert(context,
      {required String response,
      required Color colors,
      Duration duration = const Duration(seconds: 4)}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(response),
        backgroundColor: colors,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
  }

  @override
  void initState() {
    getPaymentSettingData();
    futurecod = fireStoreUtils.getCod();
    _razorPay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorPay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWaller);
    _razorPay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    if (widget.orderType == 'Dining' && widget.products.isNotEmpty) {
      _loadSeatAvailability();
    }
    UpiAppsService.getInstalledApps().then((apps) {
      if (!mounted) return;
      setState(() => _installedUpiApps = apps);
    });
    super.initState();
  }

  Future<void> _loadSeatAvailability() async {
    try {
      final vendor = await FireStoreUtils().getVendorByVendorID(widget.products.first.vendorID);
      if (!mounted) return;
      setState(() {
        _diningVendor = vendor;
        // Club/lounge (full_session) venues don't get the rolling-
        // availability signal at all (2026-08-25) - a guest staying all
        // night doesn't map to "seats freeing up as people finish and
        // leave" the way a turnover venue does, so the listener isn't even
        // started for them. The guest-count picker's own render condition
        // below checks the same field.
        if (vendor.seatingMode != 'full_session') {
          _seatAvailabilityStream = FireStoreUtils.streamCurrentSeatAvailability(vendor);
        }
      });
      // Check for an existing table booking at this vendor today (2026-08-28)
      // - separate try/catch so a failure here never blocks the seat-
      // availability banner above, which already loaded fine.
      try {
        final existingGuests = await FireStoreUtils.getExistingBookingGuestCountToday(
          vendorId: vendor.id,
          customerId: MyAppState.currentUser!.userID,
        );
        if (!mounted) return;
        if (existingGuests != null) {
          setState(() {
            _existingBookingGuestCount = existingGuests;
            _diningGuestCount = existingGuests;
          });
        }
      } catch (_) {
        // Non-critical - falls back to the normal interactive picker.
      }
      _maybeShowGuestCountSheet();
    } catch (_) {
      // Non-critical - the footer just shows nothing if this fails.
    }
  }

  // Shows the blocking guest-count sheet once, as soon as _diningVendor has
  // resolved enough to know _showDiningGuestPicker is actually true. A
  // WidgetsBinding post-frame callback, not a direct call, because this runs
  // from inside a setState-triggered rebuild still in flight - showModalBottomSheet
  // needs a BuildContext whose widget tree has already finished building this frame.
  void _maybeShowGuestCountSheet() {
    if (_guestSheetHandled || !_showDiningGuestPicker) return;
    _guestSheetHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Wait for THIS screen's own push-in transition to finish before
      // showing a modal on top of it (2026-09-01 fix). Reported symptom:
      // opening a Dining order sometimes landed on a stuck "just the order
      // total" screen with no sheet at all - going back and re-entering
      // (a fresh screen instance, another chance to trigger) sometimes
      // fixed it. Root cause: when _loadSeatAvailability's Firestore round
      // trip happens to resolve fast (good/cached network), this callback
      // fires while the push transition animation is still running -
      // showModalBottomSheet called at that exact moment can silently fail
      // to appear. Waiting for the route's own animation to finish removes
      // the race entirely.
      final animation = ModalRoute.of(context)?.animation;
      if (animation != null && animation.status != AnimationStatus.completed) {
        final completer = Completer<void>();
        void listener(AnimationStatus status) {
          if (status == AnimationStatus.completed) {
            animation.removeStatusListener(listener);
            if (!completer.isCompleted) completer.complete();
          }
        }
        animation.addStatusListener(listener);
        // Safety timeout in case the animation never reaches "completed"
        // for some reason (route replaced/popped mid-transition, etc.) -
        // never block the sheet forever over this wait alone.
        await completer.future.timeout(const Duration(seconds: 2), onTimeout: () {
          animation.removeStatusListener(listener);
        });
      }
      if (!mounted) return;

      try {
        await _showGuestCountSheet();
      } catch (e) {
        // Fail-safe (2026-09-01): if showing the sheet itself throws for any
        // reason, don't leave the customer stuck on the "just the order
        // total" screen forever with no way forward - proceed with
        // whatever guest count is already set (defaults to
        // widget.diningGuestCount ?? 1) rather than block checkout entirely
        // over a non-critical UI step.
        debugPrint('[GuestCountSheet] failed to show: $e');
        if (mounted) setState(() => _guestCountConfirmed = true);
      }
    });
  }

  Future<void> _showGuestCountSheet() async {
    final dark = isDarkMode(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, sheetSetState) {
            // Reuses this screen's own +/-\ stepper state (_diningGuestCount)
            // via the outer widget's setState, so the stepper's changes are
            // immediately visible here too without duplicating that state.
            return PopScope(
              // canPop: false (2026-09-02 fix) - isDismissible/enableDrag
              // false above only block tap-outside and swipe; they do NOT
              // stop the Android hardware/gesture back button, which by
              // default still pops this modal route on its own. That silent
              // dismissal used to leave _guestCountConfirmed permanently
              // false with no way to re-summon this sheet (_guestSheetHandled
              // is already true) - stranding the customer on a payment page
              // showing only the order-total card forever, with no payment
              // methods and no visible way forward. Reported symptom exactly
              // matches this: "after the back button ... Guest count sheet
              // is coming" / stuck blank payment screen.
              //
              // Back here now means "cancel checkout, not just cancel the
              // sheet" - pops this sheet AND the whole PaymentScreen
              // underneath in one motion, returning to Cart, rather than
              // leaving a half-finished, unusable payment page behind.
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                Navigator.of(sheetContext, rootNavigator: true).pop();
                Navigator.of(context).maybePop();
              },
              child: SafeArea(
                // top: false - this is a bottom sheet, never reaches the status
                // bar. bottom: true is what actually matters here - keeps the
                // Next button clear of a phone's gesture bar / on-screen back
                // button, which is exactly what was overlapping before.
                top: false,
                child: Container(
                padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(sheetContext).padding.bottom + 16),
                decoration: BoxDecoration(
                  color: dark ? AppThemeData.surfaceDark : Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 18),
                        decoration: BoxDecoration(
                          color: dark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      'Table for how many?'.tr(),
                      style: TextStyle(
                        fontSize: 18,
                        fontFamily: AppThemeData.bold,
                        color: dark ? Colors.white : AppThemeData.neutral900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'This helps the restaurant seat you faster.'.tr(),
                      style: TextStyle(
                        fontSize: 13,
                        color: dark ? Colors.white54 : AppThemeData.neutral500,
                      ),
                    ),
                    const SizedBox(height: 18),
                    // onChanged forces THIS sheet's own StatefulBuilder to
                    // rebuild too - the +/- taps' own setState only rebuilds
                    // the page underneath, which this modal route doesn't
                    // automatically follow (see _diningGuestCountPicker's
                    // param doc). _diningGuestCountPicker already handles
                    // both the editable stepper and the read-only
                    // "already booked" display.
                    _diningGuestCountPicker(dark, onChanged: () => sheetSetState(() {})),
                    _seatAvailabilityFooterBanner(dark),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          setState(() => _guestCountConfirmed = true);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppThemeData.primary500,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(
                          'Next'.tr(),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ),
            );
          },
        );
      },
    );
  }

  // Low-availability warning threshold (2026-08-25) - max(20% of capacity,
  // 10), clamped down to capacity itself for a venue smaller than 10 seats
  // (a threshold can never exceed the venue's own capacity). Examples
  // confirmed with the user: capacity 30 -> 10 (20% of 30 is 6, floored up
  // to 10); capacity 120 -> 24 (20% already exceeds 10, used as-is);
  // capacity 6 -> 6 (10-floor would exceed capacity, clamped back down).
  int _lowSeatThreshold(int maxCapacity) {
    if (maxCapacity <= 0) return 0;
    final twentyPercent = (maxCapacity * 0.2).round();
    final withFloor = twentyPercent < 10 ? 10 : twentyPercent;
    return withFloor > maxCapacity ? maxCapacity : withFloor;
  }

  String? selectedRadioTile;

  // RazorPay is this deployment's only real gateway (2026-08-31) - when
  // it's enabled from the admin panel, skip the multi-gateway chooser
  // entirely and go straight to the default one-tap payment page (UPI apps
  // detected on this device / Cards / Wallet / COD, each firing immediately
  // on tap - see _buildDefaultPaymentPage). The old multi-gateway radio-tile
  // list only remains reachable as a fallback for a deployment that has
  // RazorPay OFF but some other gateway (Paytm, PayPal, etc.) on instead.
  @override
  Widget build(BuildContext context) {
    if (razorPayData?.isEnabled == true) {
      return _buildDefaultPaymentPage(context);
    }
    return _buildLegacyGatewayScaffold(context);
  }

  Widget _buildLegacyGatewayScaffold(BuildContext context) {
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
                // RazorPay has no tile here (2026-08-31) - this legacy list
                // only ever renders when razorPayData?.isEnabled != true
                // (see build()'s branch), so a RazorPay tile could never
                // actually be reachable inside it. See
                // _buildDefaultPaymentPage for where RazorPay lives instead.
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

  // ─── Default one-tap payment page (2026-08-31) ───────────────────────────
  // Replaces the multi-gateway radio-tile-then-Pay-Now flow with a single
  // scrollable page, Zomato/Swiggy-style: every row fires its own payment
  // immediately on tap, no separate confirm button. Reached directly from
  // CartScreen's "Place Order" whenever RazorPay is the enabled gateway.

  Widget _buildDefaultPaymentPage(BuildContext context) {
    final dark = isDarkMode(context);
    // Guest count is asked in its own blocking modal sheet now (see
    // _maybeShowGuestCountSheet/_showGuestCountSheet, triggered from
    // _loadSeatAvailability) instead of this small inline banner - until
    // it's confirmed there, the payment methods below stay hidden rather
    // than showing underneath/behind the sheet.
    final bool readyForPayment = !_showDiningGuestPicker || _guestCountConfirmed;

    return PopScope(
      canPop: !isProcessingOrder,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (!didPop && isProcessingOrder) {
          await _showBackDialog();
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: dark ? AppThemeData.surfaceDark : const Color(0xFFF2F4F8),
        appBar: _buildAppBar(dark),
        // top: false - _buildAppBar already accounts for the status bar.
        // bottom: true is the actual fix here - without it, the last
        // payment row could sit underneath a phone's gesture bar / on-
        // screen back button once there's no sticky footer to hold the
        // scroll content clear of it.
        body: SafeArea(
          top: false,
          bottom: true,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: !readyForPayment
                  ? _buildOrderSummaryCard(dark)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildOrderSummaryCard(dark),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _seatAvailabilityFooterBanner(dark),
                        ),
                        ..._buildUpiSections(dark),
                        _paymentSectionLabel('Cards'.tr(), dark),
                        _paymentRow(
                          dark: dark,
                          iconBg: const Color(0xFF4F46E5),
                          icon: Icons.credit_card_rounded,
                          title: 'Add credit / debit card'.tr(),
                          subtitle: 'Visa, Mastercard, RuPay & more'.tr(),
                          onTap: _handleCardSelected,
                        ),
                        if (UserPreference.getWalletData() ?? false) ...[
                          _paymentSectionLabel('Wallet'.tr(), dark),
                          _walletRow(dark),
                        ],
                        FutureBuilder<CodModel?>(
                          future: futurecod,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const SizedBox();
                            }
                            if (snapshot.hasData && snapshot.data!.cod == true) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _paymentSectionLabel('Cash on Delivery'.tr(), dark),
                                  _paymentRow(
                                    dark: dark,
                                    iconBg: const Color(0xFFD97706),
                                    icon: Icons.payments_rounded,
                                    title: 'Cash on Delivery'.tr(),
                                    subtitle: 'Pay when your order arrives'.tr(),
                                    onTap: () => _handleCodSelected(),
                                  ),
                                ],
                              );
                            }
                            return const SizedBox();
                          },
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  // RECOMMENDED (top 3 detected apps) + PAY BY ANY UPI APP (the rest), or a
  // single generic fallback tile while still loading / if detection came
  // back empty (non-Android, or genuinely no UPI app installed).
  List<Widget> _buildUpiSections(bool dark) {
    final apps = _installedUpiApps;
    if (apps == null || apps.isEmpty) {
      return [
        _paymentSectionLabel('Pay via UPI'.tr(), dark),
        _paymentRow(
          dark: dark,
          iconBg: const Color(0xFF4CAF50),
          icon: Icons.account_balance_rounded,
          title: 'Pay by UPI'.tr(),
          subtitle: 'Google Pay, PhonePe, Paytm & more'.tr(),
          onTap: () => _handleUpiSelected('upi'),
        ),
      ];
    }
    final recommended = apps.take(3).toList();
    final rest = apps.skip(3).toList();
    final widgets = <Widget>[
      _paymentSectionLabel('Recommended'.tr(), dark),
      for (final app in recommended) _upiAppRow(dark, app),
    ];
    if (rest.isNotEmpty) {
      widgets.add(_paymentSectionLabel('Pay by any UPI app'.tr(), dark));
      widgets.addAll(rest.map((app) => _upiAppRow(dark, app)));
    }
    return widgets;
  }

  Widget _upiAppRow(bool dark, InstalledUpiApp app) {
    return _paymentRow(
      dark: dark,
      iconBg: const Color(0xFF4CAF50),
      icon: Icons.account_balance_wallet_outlined,
      title: app.appName,
      subtitle: '${'Pay directly with'.tr()} ${app.appName}',
      leadingImage: app.icon,
      onTap: () => _handleUpiSelected(app.appName, packageName: app.packageName),
    );
  }

  Widget _walletRow(bool dark) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userQuery,
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return _paymentRow(
            dark: dark,
            iconBg: const Color(0xFF059669),
            icon: Icons.account_balance_wallet_rounded,
            title: 'Wallet'.tr(),
            subtitle: '',
            onTap: null,
          );
        }
        final userData = User.fromJson(snapshot.data!.data()!);
        final bool sufficient = userData.wallet_amount >= widget.total;
        walletBalanceError = sufficient;
        return _paymentRow(
          dark: dark,
          iconBg: const Color(0xFF059669),
          icon: Icons.account_balance_wallet_rounded,
          title: 'Wallet'.tr(),
          subtitle: sufficient
              ? '${'Balance'.tr()}: ${amountShow(amount: userData.wallet_amount.toString())}'
              : '${'Insufficient balance'.tr()} (${amountShow(amount: userData.wallet_amount.toString())})',
          subtitleColor: sufficient ? null : Colors.red.shade400,
          onTap: sufficient ? _handleWalletSelected : null,
        );
      },
    );
  }

  Widget _paymentSectionLabel(String text, bool dark) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontFamily: AppThemeData.semiBold,
            letterSpacing: 0.6,
            color: dark ? Colors.white38 : AppThemeData.neutral500,
          ),
        ),
      );

  Widget _paymentRow({
    required bool dark,
    required Color iconBg,
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Uint8List? leadingImage,
    Color? subtitleColor,
  }) {
    final bool disabled = onTap == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: disabled ? 0.45 : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: dark ? AppThemeData.darkBgSecondary : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral200),
              boxShadow: dark
                  ? []
                  : [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: leadingImage != null ? Colors.white : iconBg.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                    border: leadingImage != null ? Border.all(color: AppThemeData.neutral200) : null,
                  ),
                  child: leadingImage != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Image.memory(leadingImage, fit: BoxFit.contain),
                          ),
                        )
                      : Icon(icon, color: iconBg, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontFamily: AppThemeData.medium,
                          color: dark ? Colors.white : AppThemeData.neutral900,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: subtitleColor ?? (dark ? Colors.white54 : AppThemeData.neutral500),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 20, color: dark ? Colors.white30 : AppThemeData.neutral300),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── UI helpers ────────────────────────────────────────────────────────

  // Full-page loading screen shown after online payment is captured but before
  // the order is written to Firestore. Replaces the payment screen entirely so
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

  // Phase 1 real-time seat availability - non-blocking, advisory only. The
  // customer can still tap Pay Now regardless of what this shows; see
  // TABLE_BOOKING_CAPACITY_AND_DEPOSIT_PLAN.html for why this stays
  // advisory rather than gating checkout.
  //
  // Three tiers now (2026-08-25, was just full-vs-silent before):
  //   1. Full                                          -> red "full" banner
  //   2. Not full, but the chosen party size (
  //      _diningGuestCount) exceeds the seats actually
  //      remaining right now                           -> orange "delay" banner naming the exact remaining count
  //   3. Not full, party fits, but remaining seats have
  //      dropped under _lowSeatThreshold                -> amber "filling up" banner, same exact-count phrasing
  //   4. Otherwise                                       -> nothing
  // 2 takes priority over 3 - "your specific party won't comfortably fit"
  // is more actionable than a generic low-availability nudge.
  Widget _seatAvailabilityFooterBanner(bool dark) {
    if (_seatAvailabilityStream == null) return const SizedBox();
    return StreamBuilder<SeatAvailability?>(
      stream: _seatAvailabilityStream,
      builder: (context, snapshot) {
        final availability = snapshot.data;
        if (availability == null) return const SizedBox();

        if (availability.isFull) {
          return _seatBanner(
            dark: dark,
            color: Colors.red,
            icon: Icons.event_seat_outlined,
            message: 'This restaurant is full right now. You may get a seat with a little delay.'.tr(),
          );
        }

        final remaining = (availability.maxCapacity - availability.occupiedGuests).clamp(0, availability.maxCapacity);

        if (_diningGuestCount > remaining) {
          return _seatBanner(
            dark: dark,
            color: Colors.orange,
            icon: Icons.event_seat_outlined,
            message: 'You may get a delay in seating - only $remaining seat${remaining == 1 ? '' : 's'} vacant right now.'.tr(),
          );
        }

        final threshold = _lowSeatThreshold(availability.maxCapacity);
        if (remaining <= threshold) {
          return _seatBanner(
            dark: dark,
            color: Colors.amber,
            icon: Icons.event_seat_outlined,
            message: 'Seats are filling up - only $remaining seat${remaining == 1 ? '' : 's'} vacant right now.'.tr(),
          );
        }

        return const SizedBox();
      },
    );
  }

  Widget _seatBanner({required bool dark, required MaterialColor color, required IconData icon, required String message}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: dark ? color.shade900.withValues(alpha: 0.25) : color.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: dark ? color.shade700 : color.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: dark ? color.shade200 : color.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                fontFamily: AppThemeData.medium,
                color: dark ? color.shade100 : color.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Guest-count input for a Dining order (2026-08-25, moved here from
  // CartScreen.dart's _diningGuestCountPicker - identical look/behavior,
  // just relocated so it's asked right before the customer commits to
  // paying, when the seat-availability signal it feeds is actually visible
  // on the same screen). Only rendered when the caller already checked
  // widget.orderType == 'Dining' && _diningVendor?.seatCapacity != null &&
  // _diningVendor?.seatAvailabilityEnabled == true.
  // onChanged: called (in addition to this State's own setState, which
  // always runs first and is what actually mutates _diningGuestCount) after
  // every +/- tap. Needed when this picker is shown inside a separately
  // routed overlay (the guest-count modal sheet) - a plain setState on this
  // State does not, by itself, cause that overlay's own builder to re-run,
  // so the sheet passes its StatefulBuilder's setState here to force it to.
  // The two normal in-page call sites (the default payment page's inline
  // banner, the legacy footer) are part of this same widget tree already,
  // so they don't need it and leave it null.
  Widget _diningGuestCountPicker(bool dark, {VoidCallback? onChanged}) {
    // Already booked a table here today - show the count read-only instead
    // of re-asking (2026-08-28). No +/- stepper at all: this number came
    // from the booking, not from this screen, so it isn't editable here.
    if (_existingBookingGuestCount != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: dark ? AppThemeData.darkBgTertiary : Color(0xFFF7F7F9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: dark ? AppThemeData.darkBorderPrimary : Color(0xFFE5E5EA),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.event_seat_outlined, size: 18, color: dark ? Colors.white70 : Colors.grey.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'You already have a table booked here today for $_existingBookingGuestCount ${_existingBookingGuestCount == 1 ? 'guest' : 'guests'}.'
                    .tr(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppThemeData.semiBold,
                  color: dark ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgTertiary : Color(0xFFF7F7F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: dark ? AppThemeData.darkBorderPrimary : Color(0xFFE5E5EA),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.people_outline, size: 18, color: dark ? Colors.white70 : Colors.grey.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Guests'.tr(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily: AppThemeData.semiBold,
                color: dark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: dark ? AppThemeData.darkBorderPrimary : Color(0xFFE5E5EA)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () {
                    if (_diningGuestCount <= 1) return;
                    setState(() => _diningGuestCount--);
                    onChanged?.call();
                  },
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppThemeData.primary500,
                      borderRadius: const BorderRadius.only(topLeft: Radius.circular(6), bottomLeft: Radius.circular(6)),
                    ),
                    child: const Icon(Icons.remove, color: Colors.white, size: 14),
                  ),
                ),
                SizedBox(
                  width: 30,
                  child: Center(
                    child: Text(
                      '$_diningGuestCount',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: dark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  // Loose sanity cap, not a real venue limit - the server
                  // never trusts this number for anything beyond the
                  // informational seat-availability display.
                  onTap: () {
                    if (_diningGuestCount >= 30) return;
                    setState(() => _diningGuestCount++);
                    onChanged?.call();
                  },
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppThemeData.primary500,
                      borderRadius: const BorderRadius.only(topRight: Radius.circular(6), bottomRight: Radius.circular(6)),
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.orderType == 'Dining' &&
              _diningVendor?.effectiveSeatCapacity != null &&
              _diningVendor?.seatAvailabilityEnabled == true &&
              _diningVendor?.seatAvailabilityOn == true &&
              _diningVendor?.seatingMode != 'full_session')
            _diningGuestCountPicker(dark),
          _seatAvailabilityFooterBanner(dark),
          SizedBox(
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
        ],
      ),
    );
  }

  Future<void> _onProceed(BuildContext context) async {
    // TEMPORARY [ORDER-PERF] - timing instrumentation for the loading-speed
    // investigation. Remove once done.
    final proceedSw = Stopwatch()..start();
    debugPrint('[ORDER-PERF] _onProceed START — razorPay=$razorPay payFast=$payFast wallet=$wallet');
    // (2026-08-31) RazorPay no longer has a tile in this legacy gateway
    // list at all (see build()'s doc comment) - it's handled entirely by
    // _buildDefaultPaymentPage instead, which never calls _onProceed. This
    // dispatcher's razorPay branch was removed as dead code accordingly.
    if (payFast) {
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
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text('Payment Successful!!'.tr() + '\n'), backgroundColor: Colors.green.shade400, duration: const Duration(seconds: 6),
              behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
        } else {
          Navigator.pop(context);
          // showLoadingAlert() above set isProcessingOrder=true and it's
          // never touched again on this path — without resetting it here,
          // Pay Now stays permanently disabled after a failed/cancelled
          // PayFast payment, with no way to retry short of leaving the screen.
          if (mounted) setState(() => isProcessingOrder = false);
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text('Payment Unsuccessful!!'.tr() + '\n'), backgroundColor: AppThemeData.primary500, duration: const Duration(seconds: 6),
              behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
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
        final genIdSw = Stopwatch()..start();
        final orderId = await generateOrderId();
        debugPrint('[ORDER-PERF] generateOrderId — ${genIdSw.elapsedMilliseconds}ms');

        // Root-cause fix (2026-08-06) for "wallet deducted but order never
        // placed": the order this money is for is now built and staged as a
        // draft BEFORE the wallet is touched. createVerifiedWalletOrder
        // promotes that exact draft into the real vendor_orders/{orderId}
        // doc INSIDE the same Firestore transaction as the wallet deduction
        // (see paymentIntents.js), so the two can never happen one without
        // the other — by the time this call returns success, the order is
        // guaranteed to already exist server-side, regardless of anything
        // that happens on the client afterwards (crash, lost connectivity).
        // Because the order already exists, _finishAlreadyPlacedWalletOrder
        // below deliberately does NOT go through placeOrder()/
        // toCheckOutScreen's normal write path - a customer-side rewrite of
        // an already-created order is correctly rejected by vendor_orders'
        // security rules (2026-08-06 finding: this was actually happening,
        // silently downgrading every wallet order into a "failed, retry"
        // loop that then created a duplicate order on retry).
        final draftSw = Stopwatch()..start();
        final orderModel = await _buildOrderModel(orderId);
        final draftRef = FirebaseFirestore.instance.collection('order_drafts').doc(orderId);
        await draftRef.setLogged(orderModel.toJson(), '_onProceed:order_drafts');
        debugPrint('[ORDER-PERF] build+stage order draft — ${draftSw.elapsedMilliseconds}ms');

        // Server verifies price/coupon/special-discount/vendor-status,
        // claims device ownership, and atomically deducts the verified
        // total from the wallet (checking the real current balance in the
        // same transaction) — all in one trusted call. No client-side
        // wallet write of any kind happens on this path anymore.
        final verifySw = Stopwatch()..start();
        final result = await RazorPayController().createVerifiedWalletOrder(
          vendorID: widget.products.first.vendorID,
          products: widget.products,
          orderId: orderId,
          couponId: widget.couponId,
          sectionId: sectionConstantModel?.id,
          takeAway: widget.take_away ?? false,
          deliveryCharge: widget.deliveryCharge,
          tipValue: widget.tipValue,
          taxSetting: widget.taxModel,
          billPayRequestId: widget.billPayRequestId,
          expectedBillVersion: widget.expectedBillVersion,
          scheduleTimeMillis: widget.scheduleTime?.millisecondsSinceEpoch,
          clientOrderType: widget.orderType,
        );
        debugPrint('[ORDER-PERF] createVerifiedWalletOrder — ${verifySw.elapsedMilliseconds}ms '
            '(TOTAL so far ${proceedSw.elapsedMilliseconds}ms)');
        // Unconditional dismiss - the wallet has already been charged (or
        // not) server-side by this point regardless of whether this screen
        // is still on top; the dialog must never be able to outlive that.
        dismissLoadingAndClearProcessing();

        if (!result.success) {
          // Nothing was charged - the draft was never promoted. Clean it up
          // so order_drafts doesn't accumulate abandoned attempts.
          draftRef.deleteLogged('_onProceed:order_drafts').catchError((_) {});
          _handleVerifiedPaymentFailure(result);
          return;
        }

        if (!context.mounted) return;
        // dismissLoadingAndClearProcessing() above already cleared
        // isProcessingOrder (it has to — that's what also dismisses the
        // loading dialog), but the wallet is already debited at this point
        // and there's still real work left (stock decrement, then
        // navigating away) — re-set it so Pay Now stays disabled/spinning
        // instead of being tappable again while the success banner is up.
        setState(() { isOrderPlaced = true; isProcessingOrder = true; });
        // Best-effort only (2026-08-06): the live wallet-balance
        // StreamBuilder above can rebuild/detach _scaffoldKey's Element at
        // almost this exact instant when the balance it's watching changes
        // (which this very payment just caused) - a transient race that
        // must never be allowed to stop the order confirmation/stock
        // decrement below, which is what actually matters.
        try {
          showAlert(context, response: 'Payment Successful Via'.tr() + ' Wallet', colors: Colors.green, duration: const Duration(seconds: 2));
        } catch (e) {
          debugPrint('[ORDER-BUILD] showAlert (wallet success) failed, continuing anyway: $e');
        }
        await _finishAlreadyPlacedWalletOrder(context, orderModel);
      }
    } else if (codPay) {
      paymentType = 'cod';
      paymentOption = 'Pay Via Cash On delivery'.tr();
      showLoadingAlert();
      final genIdSw = Stopwatch()..start();
      final orderId = await generateOrderId();
      debugPrint('[ORDER-PERF] generateOrderId (COD) — ${genIdSw.elapsedMilliseconds}ms '
          '(TOTAL so far ${proceedSw.elapsedMilliseconds}ms)');

      // Server verifies price/coupon/special-discount/vendor-status and
      // claims device ownership before any order is created - see
      // createVerifiedCodOrder in paymentIntents.js. COD itself charges
      // nothing; this call blocks order creation the same way the
      // gateway/wallet paths already do, closing the gap where COD
      // previously never called any Cloud Function at all.
      final verifySw = Stopwatch()..start();
      final result = await RazorPayController().createVerifiedCodOrder(
        vendorID: widget.products.first.vendorID,
        products: widget.products,
        orderId: orderId,
        couponId: widget.couponId,
        sectionId: sectionConstantModel?.id,
        takeAway: widget.take_away ?? false,
        deliveryCharge: widget.deliveryCharge,
        tipValue: widget.tipValue,
        taxSetting: widget.taxModel,
        billPayRequestId: widget.billPayRequestId,
        expectedBillVersion: widget.expectedBillVersion,
      );
      debugPrint('[ORDER-PERF] createVerifiedCodOrder — ${verifySw.elapsedMilliseconds}ms '
          '(TOTAL so far ${proceedSw.elapsedMilliseconds}ms)');
      dismissLoadingAndClearProcessing();
      if (!context.mounted) return;

      if (!result.success) {
        _handleVerifiedPaymentFailure(result);
        return;
      }

      setState(() { isOrderPlaced = true; });
      if (widget.take_away!) {
        placeOrder(_scaffoldKey.currentContext!, oid: orderId);
      } else {
        toCheckOutScreen(false, context, oid: orderId);
      }
    } else if (Midtrans) {
      paymentType = 'midtrans';
      // Unlike the other gateway branches above, these three never called
      // showLoadingAlert()/isProcessingOrder=true before doing async work
      // (payment-link/invoice creation) ahead of opening their WebView — Pay
      // Now stayed tappable for that whole gap, letting a double-tap fire
      // off multiple concurrent payment attempts.
      setState(() => isProcessingOrder = true);
      midtransMakePayment(context: context, amount: widget.total.toString());
    } else if (orange) {
      paymentType = 'orangepay';
      setState(() => isProcessingOrder = true);
      orangeMakePayment(context: context, amount: widget.total.toString());
    } else if (xendit) {
      paymentType = 'xendit';
      setState(() => isProcessingOrder = true);
      xenditPayment(context, widget.total);
    } else if (phonePay) {
      paymentType = 'phonepe';
      _phonePayMakePayment(context: context, amount: widget.total);
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Select Payment Method'.tr(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
          backgroundColor: AppThemeData.primary500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      Navigator.of(_scaffoldKey.currentContext!, rootNavigator: true).pop();
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
  // Order ID generated before opening Razorpay checkout - embedded in the
  // Razorpay notes for support/reconciliation lookups. NOTE: there is no
  // webhook that reads this to recover the order server-side (verified
  // 2026-08-31 - no such Cloud Function is deployed); _buildAndPlaceOrder is
  // the only thing that ever creates the order for a RazorPay payment.
  String? _pendingOrderId;

  // ─────────────────────────────────────────────────────────────
  // QuickDash payment sheet (Zomato-style bottom sheet)
  // ─────────────────────────────────────────────────────────────

  String _formatPhone(String? phone) {
    if (phone == null || phone.isEmpty) return '';
    if (phone.startsWith('+')) return phone;
    if (phone.length == 10) return '+91$phone';
    return phone;
  }

  // All UPI tiles route through Razorpay's own checkout with UPI pre-selected.
  // Direct UPI Intent (upi:// scheme) is not supported for Razorpay's
  // rzp@rxaxis virtual VPAs — those VPAs are Razorpay-internal and can only
  // be resolved through Razorpay's own collect flow, not NPCI's public registry.
  // packageName, when given, is a real installed app detected by
  // UpiAppsService - _launchUpiIntentAndPoll uses it to open that exact app
  // directly instead of letting Android show its own chooser. appHint is
  // only a display/debug label at this point.
  void _handleUpiSelected(String appHint, {String? packageName}) async {
    paymentType = 'razorpay';
    showLoadingAlert();
    final appOrderId = await generateOrderId();
    _pendingOrderId = appOrderId;
    final draftOrderModel = await _buildOrderModel(appOrderId);
    final draftRef = FirebaseFirestore.instance.collection('order_drafts').doc(appOrderId);
    await draftRef.setLogged(draftOrderModel.toJson(), '_handleUpiSelected:order_drafts');

    // S2S UPI Intent (2026-08-31) - tried first so the customer leaves this
    // app's UI entirely and pays in their own UPI app, instead of inside
    // Razorpay's hosted Checkout screen (see upiIntentPayments.js's
    // top-of-file comment for the full picture). Falls back to the
    // pre-existing openCheckoutUpi flow below on ANY failure - including
    // S2S simply not being enabled for UPI on this Razorpay account yet -
    // so this can ship without waiting on that approval, and keeps working
    // exactly as before if Razorpay ever disables it.
    final phone = _formatPhone(MyAppState.currentUser!.phoneNumber);
    if (phone.isNotEmpty) {
      final s2sResult = await RazorPayController().createS2SUpiIntent(
        vendorID: widget.products.first.vendorID,
        products: widget.products,
        contact: phone,
        email: MyAppState.currentUser!.email,
        couponId: widget.couponId,
        sectionId: sectionConstantModel?.id,
        takeAway: widget.take_away ?? false,
        deliveryCharge: widget.deliveryCharge,
        tipValue: widget.tipValue,
        billPayRequestId: widget.billPayRequestId,
        expectedBillVersion: widget.expectedBillVersion,
        scheduleTimeMillis: widget.scheduleTime?.millisecondsSinceEpoch,
        clientOrderType: widget.orderType,
      );
      if (s2sResult.success && s2sResult.intentUrl != null) {
        dismissLoadingAndClearProcessing();
        if (!mounted) return;
        await _launchUpiIntentAndPoll(
          intentUrl: s2sResult.intentUrl!,
          razorpayOrderId: s2sResult.razorpayOrderId!,
          razorpayPaymentId: s2sResult.razorpayPaymentId!,
          appOrderId: appOrderId,
          draftRef: draftRef,
          packageName: packageName,
        );
        return;
      }
      // billUpdated/deviceSuperseded/vendor_closed are real, final answers
      // from server-side verification (not "S2S unavailable") - surface
      // those directly instead of silently falling back to a Checkout
      // payment for a bill/device state the customer already needs to
      // address first.
      if (s2sResult.billUpdated || s2sResult.deviceSuperseded) {
        dismissLoadingAndClearProcessing();
        if (!mounted) return;
        draftRef.deleteLogged('_handleUpiSelected:order_drafts').catchError((_) {});
        _handleVerifiedPaymentFailure(VerifiedPaymentOrderResult(
          errorMessage: s2sResult.errorMessage,
          deviceSuperseded: s2sResult.deviceSuperseded,
          billUpdated: s2sResult.billUpdated,
          updatedTotal: s2sResult.updatedTotal,
        ));
        return;
      }
      debugPrint('[S2S UPI] falling back to Checkout: ${s2sResult.errorMessage}');
    }

    final result = await RazorPayController().createVerifiedOrderPayment(
      vendorID: widget.products.first.vendorID,
      products: widget.products,
      couponId: widget.couponId,
      sectionId: sectionConstantModel?.id,
      takeAway: widget.take_away ?? false,
      deliveryCharge: widget.deliveryCharge,
      tipValue: widget.tipValue,
      taxSetting: widget.taxModel,
      billPayRequestId: widget.billPayRequestId,
      expectedBillVersion: widget.expectedBillVersion,
      scheduleTimeMillis: widget.scheduleTime?.millisecondsSinceEpoch,
      clientOrderType: widget.orderType,
    );
    dismissLoadingAndClearProcessing();
    if (!mounted) return;
    if (result.success) {
      openCheckoutUpi(amount: result.amount, orderId: result.razorpayOrderId!, appOrderId: appOrderId);
    } else {
      draftRef.deleteLogged('_handleUpiSelected:order_drafts').catchError((_) {});
      _handleVerifiedPaymentFailure(result);
    }
  }

  // Launches the S2S UPI intent link (hands off to whichever UPI app the
  // customer picks) and polls verifyPayment until Razorpay reports the
  // payment as captured, failed, or this simply times out. There's no SDK
  // success callback the way Checkout provides one - polling is the only
  // signal available on this path (see upiIntentPayments.js's comment on
  // the still-missing webhook for the "app killed mid-payment" edge case
  // this doesn't cover, same gap the existing Checkout flow already has).
  Future<void> _launchUpiIntentAndPoll({
    required String intentUrl,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String appOrderId,
    required DocumentReference draftRef,
    // A specific installed app's package name (from UpiAppsService) - when
    // given, opens that exact app directly (native Intent.setPackage, no
    // chooser). Falls back to the generic launchUrl below if that package
    // can no longer handle the intent, or if none was given at all (the
    // "Other UPI Apps" tile), in which case Android shows its own chooser.
    String? packageName,
  }) async {
    bool launched = false;
    if (packageName != null) {
      launched = await UpiAppsService.launchForPackage(intentUrl, packageName);
    }
    if (!launched) {
      final uri = Uri.parse(intentUrl);
      try {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        launched = false;
      }
    }
    if (!launched) {
      if (!mounted) return;
      draftRef.deleteLogged('_launchUpiIntentAndPoll:order_drafts').catchError((_) {});
      AppDialog.showWarning(
        _scaffoldKey.currentContext!,
        title: 'No UPI App Found'.tr(),
        message: 'Could not find an app to handle UPI payments on this device.'.tr(),
      );
      return;
    }
    if (!mounted) return;

    // 'success' / 'failed' / 'timeout' / 'cancelled' - decided inside the
    // poll loop, the timeout timer, or the Cancel button, read back once the
    // dialog itself has closed so navigation never happens while it's still
    // on-screen.
    String outcome = 'cancelled';
    String? failureMessage;

    // Guards against a real, observed failure mode (2026-08-31): the poll's
    // HTTP call can still be in flight when the 3-minute timeout fires and
    // pops the dialog. Without this guard, that in-flight call completes
    // moments later and ALSO calls Navigator.pop() - but by then showDialog
    // has already returned and the caller has moved on (e.g. already pushed
    // PlaceOrderScreen for a genuinely successful payment). That second,
    // unguarded pop() doesn't error - it just pops whatever real route is on
    // top at that moment, which can be PlaceOrderScreen itself, yanking the
    // customer back to this PaymentScreen mid-order-creation while the order
    // write proceeds/completes independently. That leaves them stuck staring
    // at a frozen "Pay Now" spinner (isProcessingOrder was already set true
    // for the push and nothing here ever resets it) despite the payment
    // having actually succeeded and the order having actually been placed -
    // exactly the symptom reported 2026-08-31. Only the FIRST of {poll
    // result, timeout, manual cancel} may now act; every later arrival is a
    // no-op.
    bool decided = false;

    final pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final verifyResult = await RazorPayController().verifyPayment(
        razorpayOrderId: razorpayOrderId,
        razorpayPaymentId: razorpayPaymentId,
        purpose: 'order',
      );
      if (decided) return; // dialog already resolved (timeout/cancel) while this call was in flight
      if (verifyResult.pending) return; // customer hasn't finished paying yet - keep polling
      decided = true;
      timer.cancel();
      outcome = verifyResult.success ? 'success' : 'failed';
      failureMessage = verifyResult.errorMessage;
      if (_scaffoldKey.currentContext != null && Navigator.of(_scaffoldKey.currentContext!, rootNavigator: true).canPop()) {
        Navigator.of(_scaffoldKey.currentContext!, rootNavigator: true).pop();
      }
    });
    // 3 minutes - generous for switching to a UPI app, entering a PIN, and
    // coming back, without leaving the customer stuck on this dialog
    // forever if they abandon the payment instead of tapping Cancel.
    final timeoutTimer = Timer(const Duration(minutes: 3), () {
      if (decided) return;
      decided = true;
      if (outcome == 'cancelled') outcome = 'timeout';
      if (_scaffoldKey.currentContext != null && Navigator.of(_scaffoldKey.currentContext!, rootNavigator: true).canPop()) {
        Navigator.of(_scaffoldKey.currentContext!, rootNavigator: true).pop();
      }
    });

    // ignore: use_build_context_synchronously
    await showDialog<void>(
      context: _scaffoldKey.currentContext!,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (dialogCtx) {
        final dark = isDarkMode(dialogCtx);
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
                    'Waiting for Payment'.tr(),
                    style: TextStyle(
                      fontSize: 18,
                      fontFamily: AppThemeData.semiBold,
                      color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Complete the payment in your UPI app, then come back here.'.tr(),
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: AppThemeData.regular,
                      color: dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral500,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () {
                      if (decided) return;
                      decided = true;
                      outcome = 'cancelled';
                      Navigator.of(dialogCtx, rootNavigator: true).pop();
                    },
                    child: Text('Cancel'.tr(), style: TextStyle(color: AppThemeData.primary500, fontFamily: AppThemeData.medium)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    pollTimer.cancel();
    timeoutTimer.cancel();

    // A 'timeout' means our 3-minute poll window closed before we saw a
    // final state - NOT that the payment failed. Before showing "still
    // waiting" and stranding the customer, ask Razorpay directly one more
    // time: if the payment actually did capture (a slow bank confirmation,
    // the app having been backgrounded and throttled while polling, etc.),
    // treat it exactly like a normal success and take the customer straight
    // to their order instead of a dead-end warning for a payment that
    // genuinely went through.
    if (outcome == 'timeout' && mounted) {
      final finalCheck = await RazorPayController().verifyPayment(
        razorpayOrderId: razorpayOrderId,
        razorpayPaymentId: razorpayPaymentId,
        purpose: 'order',
      );
      if (finalCheck.success) {
        outcome = 'success';
      } else if (!finalCheck.pending) {
        // A definite, non-pending failure now (not just "still don't know")
        // - treat like any other confirmed failure below.
        outcome = 'failed';
        failureMessage = finalCheck.errorMessage;
      }
      // else: still genuinely pending - outcome stays 'timeout', and the
      // draft is kept (not deleted) below so it isn't lost either way.
    }

    if (outcome == 'success') {
      _pendingS2SRazorpayOrderId = razorpayOrderId;
      _pendingOrderId = appOrderId;
      if (!mounted) return;
      setState(() {
        isOrderPlaced = true;
        isProcessingOrder = true;
        _paymentCollected = true;
      });
      push(_scaffoldKey.currentContext!, PlaceOrderScreen(
        orderFactory: () => _buildAndPlaceOrder(appOrderId),
        isPaymentVerified: true,
      ));
      return;
    }

    // cancelled / failed: verifyPayment only reaches 'success' on a
    // genuinely captured payment, so a real 'failed' means nothing was
    // charged and the draft is safe to discard. 'cancelled' (the customer
    // tapped Cancel) is the same - Razorpay never captured anything for an
    // intent the customer's own UPI app never completed.
    //
    // 'timeout' is NOT the same as 'failed' - it means "we don't know",
    // not "nothing was charged". Deleting the draft here used to happen
    // unconditionally, and the message below still promises an automatic
    // refund if money was deducted - but there is no Cloud Function that
    // performs that (checked functions/index.js: no razorpayWebhook, no
    // reconciliation job for order_drafts at all, unlike the wallet path's
    // healMissingWalletCredits). If the payment actually did capture just
    // slightly after the 3-minute window, deleting the draft here would
    // destroy the only record that could ever recover it, with the promised
    // refund never actually happening. Keep the draft on timeout so a
    // reconciliation job can be built to act on it; only delete for the two
    // outcomes that are genuinely final.
    if (outcome != 'timeout') {
      draftRef.deleteLogged('_launchUpiIntentAndPoll:order_drafts').catchError((_) {});
    }
    if (!mounted) return;
    if (outcome == 'timeout') {
      AppDialog.showWarning(
        _scaffoldKey.currentContext!,
        title: 'Still Waiting?'.tr(),
        message: 'We couldn\'t confirm your payment yet. Please do not pay again - check your Orders screen in a few minutes before retrying.'.tr(),
      );
    } else if (outcome == 'failed') {
      AppDialog.showWarning(
        _scaffoldKey.currentContext!,
        title: 'Payment Failed'.tr(),
        message: failureMessage ?? 'Your UPI payment could not be completed. Please try again.'.tr(),
      );
    }
    // 'cancelled': the customer tapped Cancel themselves - no extra dialog needed.
  }

  void _handleCardSelected() async {
    paymentType = 'razorpay';
    showLoadingAlert();
    final appOrderId = await generateOrderId();
    _pendingOrderId = appOrderId;
    final draftOrderModel = await _buildOrderModel(appOrderId);
    final draftRef = FirebaseFirestore.instance.collection('order_drafts').doc(appOrderId);
    await draftRef.setLogged(draftOrderModel.toJson(), '_handleCardSelected:order_drafts');
    final result = await RazorPayController().createVerifiedOrderPayment(
      vendorID: widget.products.first.vendorID,
      products: widget.products,
      couponId: widget.couponId,
      sectionId: sectionConstantModel?.id,
      takeAway: widget.take_away ?? false,
      deliveryCharge: widget.deliveryCharge,
      tipValue: widget.tipValue,
      taxSetting: widget.taxModel,
      billPayRequestId: widget.billPayRequestId,
      expectedBillVersion: widget.expectedBillVersion,
      scheduleTimeMillis: widget.scheduleTime?.millisecondsSinceEpoch,
      clientOrderType: widget.orderType,
    );
    dismissLoadingAndClearProcessing();
    if (!mounted) return;
    if (result.success) {
      openCheckoutCard(amount: result.amount, orderId: result.razorpayOrderId!, appOrderId: appOrderId);
    } else {
      draftRef.deleteLogged('_handleCardSelected:order_drafts').catchError((_) {});
      _handleVerifiedPaymentFailure(result);
    }
  }

  // Shared by all three createVerifiedOrderPayment call sites (button,
  // UPI tile, Card tile). A device_superseded denial means the server has
  // just told this device it's no longer the account's active one — that
  // must be treated the same as any other "not active" signal (sign out,
  // redirect to login), not left as an inline error toast on a screen the
  // user is no longer actually authorized to be transacting from.
  void _handleVerifiedPaymentFailure(VerifiedPaymentOrderResult result) {
    // (2026-08-08) Every call site above already pops the "Processing
    // Payment" dialog before reaching here, but none of them reset the flag
    // that dialog set (isProcessingOrder/_isLoadingDialogShowing) - so a
    // single rejected wallet/gateway attempt (insufficient balance, vendor
    // closed, bill updated, anything) permanently disabled the Pay Now
    // button for the rest of this screen's lifetime, since its onPressed is
    // gated on isProcessingOrder. Reset here, once, for every failure path
    // that funnels through this shared handler, instead of relying on each
    // call site to remember it individually.
    if (mounted) {
      setState(() {
        isProcessingOrder = false;
        _isLoadingDialogShowing = false;
      });
    }
    if (result.deviceSuperseded) {
      DeviceSessionService.handleSessionInvalidated(
        _scaffoldKey.currentContext,
        message: result.errorMessage,
      );
      return;
    }
    if (result.billUpdated) {
      _showBillUpdatedDialog(result.updatedTotal);
      return;
    }
    showAlert(_scaffoldKey.currentContext!,
        response: result.errorMessage?.tr() ?? 'Something went wrong, please contact admin.'.tr(),
        colors: AppThemeData.primary500);
  }

  // The vendor edited this Bill Pay bill after the customer opened it here —
  // the server already refused to charge anything (see resolveBillPayAmount
  // in paymentIntents.js). Send the customer back to BillPayRequestScreen,
  // which live-listens to the request doc and will already be showing the
  // current total by the time they land on it.
  void _showBillUpdatedDialog(double? updatedTotal) {
    final ctx = _scaffoldKey.currentContext;
    if (ctx == null) return;
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('Bill Updated'.tr()),
        content: Text(
          '${'The restaurant has updated your bill.'.tr()}\n\n'
          '${'Previous Total'.tr()}: ${amountShow(amount: widget.total.toString())}\n'
          '${'Updated Total'.tr()}: ${amountShow(amount: (updatedTotal ?? 0).toString())}\n\n'
          '${'Please review the updated bill before making payment.'.tr()}',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              // PaymentScreen -> CartScreen -> back to BillPayRequestScreen.
              Navigator.of(ctx).pop();
              Navigator.of(ctx).pop();
            },
            child: Text('Review Updated Bill'.tr()),
          ),
        ],
      ),
    );
  }

  void _handleWalletSelected() async {
    paymentType = 'wallet';
    final confirmOrder = await AppDialog.showConfirm(
      _scaffoldKey.currentContext!,
      title: 'Confirm Order',
      message: 'Do you want to confirm and place this order via Wallet?',
      confirmLabel: 'Yes, Place Order',
      cancelLabel: 'Cancel',
    );
    if (!confirmOrder) return;
    showLoadingAlert();
    final orderId = await generateOrderId();

    // Same server-verified, atomic path as the other wallet handler (see
    // _onProceed) — no client-side wallet write on this path either. Same
    // order-draft staging too (see the comment at the other call site) so
    // this entry point closes the same "wallet charged, order never
    // created" gap.
    final orderModel = await _buildOrderModel(orderId);
    final draftRef = FirebaseFirestore.instance.collection('order_drafts').doc(orderId);
    await draftRef.setLogged(orderModel.toJson(), '_handleWalletSelected:order_drafts');

    final result = await RazorPayController().createVerifiedWalletOrder(
      vendorID: widget.products.first.vendorID,
      products: widget.products,
      orderId: orderId,
      couponId: widget.couponId,
      sectionId: sectionConstantModel?.id,
      takeAway: widget.take_away ?? false,
      deliveryCharge: widget.deliveryCharge,
      tipValue: widget.tipValue,
      taxSetting: widget.taxModel,
      billPayRequestId: widget.billPayRequestId,
      expectedBillVersion: widget.expectedBillVersion,
      clientOrderType: widget.orderType,
    );
    dismissLoadingAndClearProcessing();
    if (!mounted) return;

    if (!result.success) {
      draftRef.deleteLogged('_handleWalletSelected:order_drafts').catchError((_) {});
      _handleVerifiedPaymentFailure(result);
      return;
    }

    if (!mounted) return;
    // See the identical comment at the other wallet call site (_onProceed)
    // — re-set isProcessingOrder so Pay Now stays disabled/spinning through
    // the success banner and stock-decrement/navigation, instead of being
    // tappable again right after the wallet's already been charged.
    setState(() { isOrderPlaced = true; isProcessingOrder = true; });
    // Best-effort only - see the identical comment at the other wallet
    // call site (_onProceed) for why this must never block the
    // confirmation/stock-decrement step below.
    try {
      showAlert(context, response: 'Payment Successful Via'.tr() + ' Wallet', colors: Colors.green, duration: const Duration(seconds: 2));
    } catch (e) {
      debugPrint('[ORDER-BUILD] showAlert (wallet success) failed, continuing anyway: $e');
    }
    await _finishAlreadyPlacedWalletOrder(context, orderModel);
  }

  void _handleCodSelected() async {
    paymentType = 'cod';
    paymentOption = 'Pay Via Cash On delivery'.tr();
    showLoadingAlert();
    final orderId = await generateOrderId();

    // See the identical comment at the other createVerifiedCodOrder call
    // site above (the codPay branch) - same server-side verification and
    // device-ownership claim, required before any order is created.
    final result = await RazorPayController().createVerifiedCodOrder(
      vendorID: widget.products.first.vendorID,
      products: widget.products,
      orderId: orderId,
      couponId: widget.couponId,
      sectionId: sectionConstantModel?.id,
      takeAway: widget.take_away ?? false,
      deliveryCharge: widget.deliveryCharge,
      tipValue: widget.tipValue,
      taxSetting: widget.taxModel,
      billPayRequestId: widget.billPayRequestId,
      expectedBillVersion: widget.expectedBillVersion,
    );
    dismissLoadingAndClearProcessing();
    if (!mounted) return;

    if (!result.success) {
      _handleVerifiedPaymentFailure(result);
      return;
    }

    setState(() { isOrderPlaced = true; });
    if (widget.take_away!) {
      placeOrder(_scaffoldKey.currentContext!, oid: orderId);
    } else {
      toCheckOutScreen(false, _scaffoldKey.currentContext!, oid: orderId);
    }
  }

  // Opens Razorpay pre-selecting UPI — skips method-selection step
  void openCheckoutUpi({required double amount, required String orderId, required String appOrderId}) {
    final options = {
      'key': razorPayData!.razorpayKey,
      'amount': (amount * 100).toInt(),
      'name': 'Quickdash',
      'order_id': orderId,
      'currency': currencyData?.code ?? 'INR',
      'description': 'Order Payment',
      'retry': {'enabled': false},
      'send_sms_hash': true,
      'prefill': {
        'contact': _formatPhone(MyAppState.currentUser!.phoneNumber),
        'email': MyAppState.currentUser!.email ?? '',
        'method': 'upi',
      },
      'notes': {
        'orderId': appOrderId,
        'vendorId': widget.products.first.vendorID,
        'userId': MyAppState.currentUser!.userID,
      },
      'theme': {'color': '#7C3AED'},
    };
    paymentInProgressNotifier.value = true;
    try {
      _razorPay.open(options);
    } catch (e) {
      paymentInProgressNotifier.value = false;
      debugPrint('[RazorPay UPI] $e');
    }
  }

  // Opens Razorpay pre-selecting card — skips method-selection step
  void openCheckoutCard({required double amount, required String orderId, required String appOrderId}) {
    final options = {
      'key': razorPayData!.razorpayKey,
      'amount': (amount * 100).toInt(),
      'name': 'Quickdash',
      'order_id': orderId,
      'currency': currencyData?.code ?? 'INR',
      'description': 'Order Payment',
      'retry': {'enabled': false},
      'send_sms_hash': true,
      'prefill': {
        'contact': _formatPhone(MyAppState.currentUser!.phoneNumber),
        'email': MyAppState.currentUser!.email ?? '',
        'method': 'card',
      },
      'notes': {
        'orderId': appOrderId,
        'vendorId': widget.products.first.vendorID,
        'userId': MyAppState.currentUser!.userID,
      },
      'theme': {'color': '#7C3AED'},
    };
    paymentInProgressNotifier.value = true;
    try {
      _razorPay.open(options);
    } catch (e) {
      paymentInProgressNotifier.value = false;
      debugPrint('[RazorPay Card] $e');
    }
  }

  void openCheckout({required amount, required orderId, required String appOrderId}) {
    final options = {
      'key': razorPayData!.razorpayKey,
      'amount': (amount * 100).toInt(),
      'name': 'Quickdash',
      'order_id': orderId,
      'currency': currencyData?.code,
      'description': 'Order Payment',
      'retry': {'enabled': true, 'max_count': 1},
      'send_sms_hash': true,
      'prefill': {
        'contact': _formatPhone(MyAppState.currentUser!.phoneNumber),
        'email': MyAppState.currentUser!.email ?? '',
      },
      'notes': {
        'orderId': appOrderId,
        'vendorId': widget.products.first.vendorID,
        'userId': MyAppState.currentUser!.userID,
      },
    };
    paymentInProgressNotifier.value = true;
    try {
      _razorPay.open(options);
    } catch (e) {
      paymentInProgressNotifier.value = false;
      debugPrint('[RazorPay] $e');
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    paymentInProgressNotifier.value = false;
    if (_isLoadingDialogShowing) {
      setState(() => _isLoadingDialogShowing = false);
      Navigator.of(_scaffoldKey.currentContext!, rootNavigator: true).pop();
    }

    // Use the order ID that was pre-generated before checkout opened.
    //
    // NOTE (2026-08-31 correction): the comment this used to carry claimed
    // "the webhook can recover the order if the app dies before
    // _buildAndPlaceOrder completes" - there is NO such webhook deployed
    // (checked functions/index.js's full export list: no razorpayWebhook,
    // no payment.captured handler anywhere). _buildAndPlaceOrder below is
    // the ONLY thing that ever creates the order for a RazorPay payment -
    // if this method returns without reaching it, the customer is charged
    // with nothing to show for it, permanently.
    final orderId = _pendingOrderId;
    _pendingOrderId = null;

    // razorpay_flutter is known to sometimes deliver EVENT_PAYMENT_SUCCESS
    // twice for one payment. The FIRST call already consumed _pendingOrderId
    // (set to null above) and pushed PlaceOrderScreen - a second call must
    // not try to push it again (double order), but it must also NOT just
    // silently bail: the isProcessingOrder=true set below would otherwise be
    // set with nothing ever resetting it, permanently freezing the Pay Now
    // button on this screen even though the order already placed correctly
    // via the first call. Bailing BEFORE touching isProcessingOrder is what
    // makes that safe.
    if (orderId == null) return;
    if (!mounted) return;

    // Money is now debited — lock back navigation.
    setState(() {
      isOrderPlaced = true;
      isProcessingOrder = true;
      _paymentCollected = true;
    });

    // Carried into _buildAndPlaceOrder so it can verify the Razorpay
    // signature server-side (and stamp razorpayOrderId onto the order)
    // before the order doc is written.
    _pendingRazorpayResponse = response;

    push(_scaffoldKey.currentContext!, PlaceOrderScreen(
      orderFactory: () => _buildAndPlaceOrder(orderId),
      isPaymentVerified: true,
    ));
  }

  PaymentSuccessResponse? _pendingRazorpayResponse;
  // S2S UPI Intent's equivalent of _pendingRazorpayResponse - see
  // _buildOrderModel's matching branch and _handleUpiIntentSelected below.
  String? _pendingS2SRazorpayOrderId;

  void _handleExternalWaller(ExternalWalletResponse response) {
    paymentInProgressNotifier.value = false;
    Navigator.of(_scaffoldKey.currentContext!, rootNavigator: true).pop();
    ScaffoldMessenger.of(_scaffoldKey.currentContext!)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          "Payment Processing!! via".tr() + "\n" + response.walletName!,
        ),
        backgroundColor: Colors.blue.shade400,
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    paymentInProgressNotifier.value = false;
    dismissLoadingAndClearProcessing();
    String description = 'Payment failed. Please try again.'.tr();
    try {
      final msg = response.message?.toString();
      if (msg != null && msg.isNotEmpty && msg != 'undefined') {
        final lom = RazorPayFailedModel.fromJson(jsonDecode(msg));
        description = lom.error.description;
      }
    } catch (_) {}
    ScaffoldMessenger.of(_scaffoldKey.currentContext!)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text("Payment Failed!!".tr() + "\n" + description),
        backgroundColor: AppThemeData.primary500,
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text("Payment Successful!!".tr()),
            duration: const Duration(seconds: 8),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ));
        paymentIntentData = null;
      }).onError((error, stackTrace) {
        Navigator.of(_scaffoldKey.currentContext!, rootNavigator: true).pop();
        var lo1 = jsonEncode(error);
        var lo2 = jsonDecode(lo1);
        AppDialog.showError(context, message: 'Payment failed. Please try again.');
      });
    } on stripe1.StripeException catch (e) {
      Navigator.of(_scaffoldKey.currentContext!, rootNavigator: true).pop();
      var lo1 = jsonEncode(e);
      var lo2 = jsonDecode(lo1);
      AppDialog.showError(context, message: 'Payment failed. Please try again.');
    } catch (e) {
      Navigator.of(_scaffoldKey.currentContext!, rootNavigator: true).pop();
      ScaffoldMessenger.of(_scaffoldKey.currentContext!)
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
  //             Navigator.of(_scaffoldKey.currentContext!, rootNavigator: true).pop();
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
  //           Navigator.of(_scaffoldKey.currentContext!, rootNavigator: true).pop();
  //           ScaffoldMessenger.of(_scaffoldKey.currentContext!)
  //               .showSnackBar(SnackBar(
  //             content: Text("Status :".tr() + " ${settleResult.data.message}"),
  //             duration: const Duration(seconds: 8),
  //             backgroundColor: AppThemeData.primary500,
  //           ));
  //         }
  //       });
  //     } else {
  //       Navigator.of(_scaffoldKey.currentContext!, rootNavigator: true).pop();
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
          Navigator.of(_scaffoldKey.currentContext!, rootNavigator: true).pop();

          result = onError.message.toString() + " \n  " + onError.code.toString();
          showAlert(_scaffoldKey.currentContext!, response: onError.message.toString(), colors: AppThemeData.primary500);
        } else {

          result = onError.toString();
          Navigator.of(_scaffoldKey.currentContext!, rootNavigator: true).pop();
          showAlert(_scaffoldKey.currentContext!, response: result, colors: AppThemeData.primary500);
        }
      });
    } catch (err) {
      result = err.toString();
      Navigator.of(_scaffoldKey.currentContext!, rootNavigator: true).pop();
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
      Navigator.of(_scaffoldKey.currentContext!, rootNavigator: true).pop();
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
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text("Payment Successful!!".tr() + "\n"),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ));
        } else {
          Navigator.of(_scaffoldKey.currentContext!, rootNavigator: true).pop();
          ScaffoldMessenger.of(_scaffoldKey.currentContext!)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text("Payment UnSuccessful!!".tr() + "\n"),
              backgroundColor: AppThemeData.primary500,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ));
        }
      } else {
        Navigator.of(_scaffoldKey.currentContext!, rootNavigator: true).pop();
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
          if (mounted) setState(() => isProcessingOrder = false);
          ShowToastDialog.showToast("Payment Unsuccessful!!");
        }
      } else {
        if (mounted) setState(() => isProcessingOrder = false);
        ShowToastDialog.showToast("Something went wrong, please contact admin.");
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
        if (mounted) setState(() => isProcessingOrder = false);
        ShowToastDialog.showToast("Payment Unsuccessful!!");
      }
    } else {
      if (mounted) setState(() => isProcessingOrder = false);
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
          if (mounted) setState(() => isProcessingOrder = false);
          ShowToastDialog.showToast("Payment Unsuccessful!!");
        }
      } else {
        if (mounted) setState(() => isProcessingOrder = false);
        ShowToastDialog.showToast("Something went wrong, please contact admin.");
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

      Navigator.of(_scaffoldKey.currentContext!, rootNavigator: true).pop(); // dismiss loading

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
          Navigator.of(_scaffoldKey.currentContext!, rootNavigator: true).pop();
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
        Navigator.of(_scaffoldKey.currentContext!, rootNavigator: true).pop();
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

  /// Core Firestore write — builds and saves the order, updates stock counts.
  /// Used by both [placeOrder] (COD/wallet) and [_handlePaymentSuccess] (Razorpay).
  // Pure construction, no Firestore write - split out of _buildAndPlaceOrder
  // (2026-08-06) so the wallet payment flow can build the exact same
  // OrderModel it would eventually write and stage it as a draft BEFORE the
  // wallet is charged (see the wallet branch of onTapPaymentOption for why).
  Future<OrderModel> _buildOrderModel(String oid) async {
    // TEMPORARY [ORDER-PERF] - step-level instrumentation (2026-08-06) to
    // pin down exactly which step throws/stalls in the intermittent
    // "order failed after payment succeeded" reports. Remove once root
    // cause is confirmed and fixed.
    final buildSw = Stopwatch()..start();
    debugPrint('[ORDER-BUILD] _buildOrderModel($oid) START');
    // For Razorpay orders, confirm the payment signature server-side before
    // ever writing the order doc — a spoofed/absent signature must not
    // result in an order (verifyOrderOnCreate would later flag it as fraud,
    // but blocking it here is a much better UX for the vast majority of
    // cases where this only fails due to a genuine payment problem).
    String? razorpayOrderId;
    final pendingResponse = _pendingRazorpayResponse;
    _pendingRazorpayResponse = null;
    if (pendingResponse != null) {
      debugPrint('[ORDER-BUILD] verifyPayment (razorpay) START — +${buildSw.elapsedMilliseconds}ms');
      final verifyResult = await RazorPayController().verifyPayment(
        razorpayOrderId: pendingResponse.orderId ?? '',
        razorpayPaymentId: pendingResponse.paymentId ?? '',
        razorpaySignature: pendingResponse.signature ?? '',
        purpose: 'order',
      );
      debugPrint('[ORDER-BUILD] verifyPayment (razorpay) END — +${buildSw.elapsedMilliseconds}ms success=${verifyResult.success}');
      if (!verifyResult.success) {
        throw Exception(verifyResult.errorMessage ?? 'Payment verification failed. Please contact support.');
      }
      razorpayOrderId = pendingResponse.orderId;
    } else if (_pendingS2SRazorpayOrderId != null) {
      // S2S UPI Intent (2026-08-31) - already confirmed 'captured' by the
      // polling loop in _handleUpiIntentSelected before this was ever
      // called, so there's nothing left to verify here - just stamp the id.
      razorpayOrderId = _pendingS2SRazorpayOrderId;
      _pendingS2SRazorpayOrderId = null;
    }

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

    debugPrint('[ORDER-BUILD] getVendorByVendorID START — +${buildSw.elapsedMilliseconds}ms');
    VendorModel vendorModel = await FireStoreUtils()
        .getVendorByVendorID(widget.products.first.vendorID)
        .whenComplete(() => setPrefData());
    debugPrint('[ORDER-BUILD] getVendorByVendorID END — +${buildSw.elapsedMilliseconds}ms');

    // Combo Purchase Learning (2026-07-24) - see CheckoutScreen.dart's
    // identical block for the full rationale (zero-extra-read cache
    // lookup, empty list for the common no-combo-items case).
    final comboLineItems = tempProduc
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

    // Purchase-analytics snapshot (2026-07-22) - written ONCE, here, at
    // order creation, and never touched again - the order document stays
    // fully immutable after creation. Purchase-derived preference (as
    // opposed to browsing/interest signals, which stay exactly as they
    // were) no longer fires from checkout at all - PurchaseCompletionListener
    // reads this snapshot once the order actually reaches
    // ORDER_STATUS_COMPLETED, so a failed/cancelled/rejected order never
    // contributes. Exactly-once processing is guaranteed by a deterministic
    // marker doc that listener creates elsewhere, not by anything stored
    // here - see that class' own doc comment for the full rationale.
    final analyticsSnapshot = <String, dynamic>{
      'categoryIds': tempProduc.map((item) => item.category_id ?? '').where((c) => c.isNotEmpty).toSet().toList(),
      'cuisineIds': vendorModel.cuisineIds,
      'restaurantId': widget.products.first.vendorID,
      'businessTypeId': vendorModel.businessTypeId,
      'productIds': tempProduc.map((item) => item.id.split('~').first).toSet().toList(),
      'totalAmount': widget.total,
      'orderMode': widget.orderType ?? (widget.take_away == true ? 'Takeaway' : 'Delivery'),
      'paymentMethod': paymentType,
      'couponCode': widget.couponCode ?? '',
      'hasSpecialDiscount': widget.specialDiscountMap != null,
      // Captured NOW, while still fresh - see
      // BehaviorTracker.recentSearchQueryFor's own doc comment for why
      // this can't be re-derived later, at completion time.
      'reachedViaSearchQuery': BehaviorTracker.recentSearchQueryFor(widget.products.first.vendorID) ?? '',
      // Restaurant Engagement / Banner Analytics linkage (Phase 2,
      // 2026-07-24, collection-only) - see CheckoutScreen.dart's identical
      // fields for the full rationale.
      'restaurantSessionId': BehaviorTracker
              .recentRestaurantSessionFor(widget.products.first.vendorID)
              ?.sessionId ??
          '',
      // Search-conversion funnel (collection-only, additive field) - see
      // CheckoutScreen.dart's identical field for the full rationale.
      'entrySource': BehaviorTracker
              .recentRestaurantSessionFor(widget.products.first.vendorID)
              ?.entrySource ??
          '',
      'reachedViaBannerId': BehaviorTracker.recentBannerClickId() ?? '',
      'comboLineItems': comboLineItems,
    };

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
      // Reads the local, on-screen picker's current value now (2026-08-25),
      // not the constructor default CartScreen used to pass in.
      diningGuestCount: widget.orderType == 'Dining' ? _diningGuestCount : widget.diningGuestCount,
      billPayRequestId: widget.billPayRequestId,
      razorpayOrderId: razorpayOrderId,
      analyticsSnapshot: analyticsSnapshot,
    );

    debugPrint('[ORDER-BUILD] _buildOrderModel($oid) END — +${buildSw.elapsedMilliseconds}ms TOTAL');
    return orderModel;
  }

  Future<OrderModel> _buildAndPlaceOrder(String oid) async {
    final placeSw = Stopwatch()..start();
    debugPrint('[ORDER-BUILD] _buildAndPlaceOrder($oid) START');
    final orderModel = await _buildOrderModel(oid);
    debugPrint('[ORDER-BUILD] placeOrderWithTakeAWay START — +${placeSw.elapsedMilliseconds}ms');
    final placedOrder = await FireStoreUtils().placeOrderWithTakeAWay(orderModel);
    debugPrint('[ORDER-BUILD] placeOrderWithTakeAWay END — +${placeSw.elapsedMilliseconds}ms');
    // Order now durably exists in vendor_orders - the pre-checkout draft
    // (staged in the razorpay branch of onTapPaymentOption/_handleUpiSelected/
    // _handleCardSelected) has served its purpose. Best-effort: if this
    // delete fails, razorpayWebhook's own existence-check against
    // vendor_orders/{oid} still makes a leftover draft harmless (it just
    // never gets read).
    FirebaseFirestore.instance.collection('order_drafts').doc(oid).deleteLogged('_buildAndPlaceOrder:order_drafts').catchError((_) {});

    // NOTE (2026-07-22): purchase-preference tracking (kEvtOrderCompleted/
    // kEvtProductOrdered) deliberately does NOT fire here anymore - a
    // placed order is not yet a successful purchase (payment could still
    // fail to settle, the vendor could reject it, etc.). See
    // PurchaseCompletionListener, which fires these once this order's
    // status actually reaches ORDER_STATUS_COMPLETED, reading
    // analyticsSnapshot above with zero additional Firestore reads.
    // Browsing/interest events (restaurant opened, product viewed,
    // searched, cart add/remove) are untouched and still fire immediately,
    // same as always.

    // Combo Purchase Learning is temporarily deferred (2026-07-22) - see
    // PurchaseCompletionListener's doc comment for what's deferred and the
    // planned follow-up.
    //
    // Stock decrement - atomic per-product transaction
    // (FirebaseHelper.decrementProductStock) instead of a plain
    // read-then-overwrite - see that method's doc comment for why the old
    // pattern could silently lose a decrement under concurrent orders.
    debugPrint('[ORDER-BUILD] decrementProductStock (${orderModel.products.length} items) START — +${placeSw.elapsedMilliseconds}ms');
    await Future.wait(
      orderModel.products.map((item) => FireStoreUtils.decrementProductStock(
            productId: item.id.split('~').first,
            quantity: item.quantity,
            variantId: item.variant_info != null ? item.id.split('~').last : null,
          )),
    );
    debugPrint('[ORDER-BUILD] decrementProductStock END — +${placeSw.elapsedMilliseconds}ms');

    debugPrint('[ORDER-BUILD] _buildAndPlaceOrder($oid) END — +${placeSw.elapsedMilliseconds}ms TOTAL');
    return placedOrder;
  }

  placeOrder(BuildContext buildContext, {required String oid}) async {
    if (_isPlacingOrder) return;
    if (paymentType.isEmpty) {
      AppDialog.showWarning(buildContext, title: 'Missing Payment Method', message: 'Please select a payment method to continue.');
      return;
    }

    setState(() {
      _isPlacingOrder = true;
      isProcessingOrder = true;
    });

    OrderModel? placedOrder;

    try {
      showProgress('Placing Order...'.tr(), false);
      // TEMPORARY [ORDER-PERF] - timing instrumentation for the
      // loading-speed investigation. Remove once done.
      final buildPlaceSw = Stopwatch()..start();
      placedOrder = await _buildAndPlaceOrder(oid);
      debugPrint('[ORDER-PERF] _buildAndPlaceOrder — ${buildPlaceSw.elapsedMilliseconds}ms');
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
    } catch (e, s) {
      // TEMPORARY [ORDER-PERF] - the actual exception was never logged
      // before (only e.toString() reached the failure dialog, filtered
      // into a generic bucket) - this is the one line that will tell us
      // exactly what's throwing here. Remove once root cause is confirmed.
      debugPrint('[ORDER-BUILD] placeOrder($oid) EXCEPTION: $e\n$s');
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

  // Wallet payments only (2026-08-06): the order was already created
  // atomically server-side, in the SAME transaction as the wallet
  // deduction (see createVerifiedWalletOrder). Do the remaining
  // side-effect (stock decrement) and go straight to the confirmation UI,
  // using the order data already built for the draft - do NOT go through
  // placeOrder()/_buildAndPlaceOrder or toCheckOutScreen's default write
  // path, since the order document already exists and a customer-side
  // rewrite of it is correctly rejected by vendor_orders' security rules
  // (only status/billPayRespondedAt may be changed after creation).
  Future<void> _finishAlreadyPlacedWalletOrder(BuildContext context, OrderModel orderModel) async {
    await Future.wait(orderModel.products.map((item) => FireStoreUtils.decrementProductStock(
          productId: item.id.split('~').first,
          quantity: item.quantity,
          variantId: item.variant_info != null ? item.id.split('~').last : null,
        )));
    if (!context.mounted) return;
    if (widget.take_away ?? false) {
      push(context, PlaceOrderScreen(orderModel: orderModel, isPaymentVerified: true));
    } else {
      toCheckOutScreen(true, context, oid: orderModel.id, alreadyPlacedOrder: orderModel);
    }
  }

  toCheckOutScreen(bool val, BuildContext context, {required String oid, OrderModel? alreadyPlacedOrder}) {
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
        billPayRequestId: widget.billPayRequestId,
        alreadyPlacedOrder: alreadyPlacedOrder,
      ),
    );
  }

  @override
  void dispose() {
    // Defense-in-depth: every concrete trigger for the stuck-dialog bug is
    // already fixed at each call site above (dismissLoadingAndClearProcessing
    // pops unconditionally once its await resolves). This only guards the
    // narrow residual case where the screen itself gets disposed while a
    // verification call is still in flight, so the dialog never gets a
    // chance to be dismissed by any of those call sites at all.
    if (_isLoadingDialogShowing) {
      try {
        final dialogContext = _scaffoldKey.currentContext;
        if (dialogContext != null) {
          Navigator.of(dialogContext, rootNavigator: true).pop();
        }
      } catch (_) {}
    }
    _razorPay.clear();
    super.dispose();
  }
}
