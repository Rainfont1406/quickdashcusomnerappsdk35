import 'dart:convert';

import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/CurrencyModel.dart';
import 'package:emartconsumer/model/TaxModel.dart';
import 'package:emartconsumer/model/createRazorPayOrderModel.dart';
import 'package:emartconsumer/model/razorpayKeyModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/device_session_service.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/services/notification_service.dart';
import 'package:emartconsumer/userPrefrence.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

enum RazorPayErrorType {
  none,
  missingCredentials,
  missingCurrency,
  networkError,
  apiError,
  invalidResponse,
  timeout,
}

class RazorPayResult {
  final CreateRazorPayOrderModel? order;
  final RazorPayErrorType errorType;
  final String? errorMessage;

  RazorPayResult({
    this.order,
    this.errorType = RazorPayErrorType.none,
    this.errorMessage,
  });

  bool get isSuccess => order != null && errorType == RazorPayErrorType.none;
}

// Result of createVerifiedOrderPayment / createWalletTopupOrder: the amount
// (and, for orders, the discount breakdown) is whatever the Cloud Function
// computed server-side from Firestore, NOT anything this client sent.
class VerifiedPaymentOrderResult {
  final bool success;
  final String? errorMessage;
  final String? razorpayOrderId;
  final String? razorpayKey;
  final double amount;
  final double verifiedDiscount;
  final double verifiedSpecialDiscount;
  // True when the server denied this specifically because another device is
  // the account's active one within its 2h cooldown (device_superseded) —
  // distinct from every other failure reason. The caller must treat this
  // like any other "not the active device" signal: sign out and redirect to
  // login, not just show an inline error and leave the user on this screen.
  final bool deviceSuperseded;
  // True when a wallet payment was denied because the server's own read of
  // the real, current wallet_amount (inside the same transaction as the
  // deduction) was insufficient for the verified total — distinct from a
  // generic error since the UI should point the user at topping up.
  final bool insufficientBalance;
  // True when this was a Bill Pay Accept & Pay and the server rejected it
  // because the vendor edited the bill after this device last saw it
  // (billPayExpiresAt no longer matches what was passed as
  // expectedBillVersion). The server never charged anything — updatedTotal
  // is the CURRENT, real total the caller must show before retrying.
  final bool billUpdated;
  final double? updatedTotal;

  VerifiedPaymentOrderResult({
    this.success = false,
    this.errorMessage,
    this.razorpayOrderId,
    this.razorpayKey,
    this.amount = 0,
    this.verifiedDiscount = 0,
    this.verifiedSpecialDiscount = 0,
    this.deviceSuperseded = false,
    this.insufficientBalance = false,
    this.billUpdated = false,
    this.updatedTotal,
  });
}

class VerifyPaymentResult {
  final bool success;
  final String? errorMessage;

  VerifyPaymentResult({this.success = false, this.errorMessage});
}

class RazorPayController {
  Future<String?> _idToken() async => auth.FirebaseAuth.instance.currentUser?.getIdToken();

  // Pre-payment verification for a cart checkout: the server recomputes
  // subtotal/coupon/special-discount from Firestore and only creates a real
  // Razorpay order for that verified total — the client can no longer choose
  // what gets charged (Razorpay rejects a checkout payment that doesn't
  // match the order's amount).
  Future<VerifiedPaymentOrderResult> createVerifiedOrderPayment({
    required String vendorID,
    required List<CartProduct> products,
    String? couponId,
    String? sectionId,
    bool takeAway = false,
    String? deliveryCharge,
    String? tipValue,
    List<TaxModel>? taxSetting,
    String currency = 'INR',
    // Bill Pay Accept & Pay only: links this payment to the vendor's live
    // request doc so the server recomputes the charge from it directly
    // (ignoring `products` above entirely) and rejects a stale bill instead
    // of ever charging it. See resolveBillPayAmount in paymentIntents.js.
    String? billPayRequestId,
    int? expectedBillVersion,
    // Epoch millis of the customer's chosen future delivery/pickup time, or
    // null for an immediate order. Lets the server judge vendor-open status
    // against when the order will actually be fulfilled, not the moment of
    // checkout - see CartScreen's _discountEvalTime for the client-side half
    // of this fix (2026-08-23). NOTE: special-discount eligibility no longer
    // uses this (2026-08-30 reversal) - see clientOrderType below instead.
    int? scheduleTimeMillis,
    // The real order type ('Dining' / 'Takeaway' / 'Delivery' / null),
    // distinct from the `takeAway` bool above which collapses Dining into
    // Takeaway for special-discount tier-matching (existing, unchanged
    // design). This is a separate signal used only to decide whether to
    // attempt the table-booking discount lock below - 'Dining' is the only
    // value that triggers it (2026-08-30, §11.21). Sourced from
    // PaymentScreen's own widget.orderType.
    String? clientOrderType,
  }) async {
    final idToken = await _idToken();
    if (idToken == null) {
      return VerifiedPaymentOrderResult(errorMessage: 'Not signed in.');
    }
    try {
      final deviceId = await DeviceSessionService.getDeviceId();
      final fcmToken = await NotificationService.getToken();

      final resp = await http
          .post(
            Uri.parse('$CloudFunctionsBaseURL/createVerifiedOrderPayment'),
            headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'},
            body: jsonEncode({
              'vendorID': vendorID,
              'products': products.map((p) => p.toJson()).toList(),
              'couponId': couponId,
              'sectionId': sectionId,
              'takeAway': takeAway,
              'deliveryCharge': deliveryCharge,
              'tipValue': tipValue,
              'taxSetting': taxSetting?.map((t) => t.toJson()).toList(),
              'currency': currency,
              'deviceId': deviceId,
              'fcmToken': fcmToken,
              'billPayRequestId': billPayRequestId,
              'expectedBillVersion': expectedBillVersion,
              'scheduleTimeMillis': scheduleTimeMillis,
              'clientOrderType': clientOrderType,
            }),
          )
          .timeout(const Duration(seconds: 30));

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200) {
        return VerifiedPaymentOrderResult(
          success: true,
          razorpayOrderId: data['razorpayOrderId']?.toString(),
          razorpayKey: data['razorpayKey']?.toString(),
          amount: (data['verifiedTotal'] as num?)?.toDouble() ?? 0,
          verifiedDiscount: (data['verifiedDiscount'] as num?)?.toDouble() ?? 0,
          verifiedSpecialDiscount: (data['verifiedSpecialDiscount'] as num?)?.toDouble() ?? 0,
        );
      }
      if (data['error'] == 'bill_updated') {
        return VerifiedPaymentOrderResult(
          billUpdated: true,
          updatedTotal: (data['updatedTotal'] as num?)?.toDouble(),
          errorMessage: 'The restaurant updated this bill. Please review it before paying.',
        );
      }
      if (data['error'] == 'vendor_closed') {
        return VerifiedPaymentOrderResult(errorMessage: 'This restaurant is currently closed.');
      }
      if (data['error'] == 'device_superseded') {
        final retryAtRaw = data['retry_at'] as String?;
        final retryAt = retryAtRaw != null ? DateTime.tryParse(retryAtRaw) : null;
        final baseMessage = (data['message'] as String?) ??
            'This account is active on another device. You can switch devices after 2 hours.';
        return VerifiedPaymentOrderResult(
          deviceSuperseded: true,
          errorMessage: DeviceSessionService.withRetryTime(baseMessage, retryAt),
        );
      }
      return VerifiedPaymentOrderResult(
          errorMessage: data['error']?.toString() ?? 'Unable to initialize payment. Please try again later.');
    } catch (e) {
      debugPrint('[createVerifiedOrderPayment] $e');
      return VerifiedPaymentOrderResult(errorMessage: 'Unable to initialize payment. Please try again later.');
    }
  }

  // Pre-payment verification AND atomic deduction for a WALLET-paid order —
  // the server recomputes subtotal/coupon/special-discount/vendor-open
  // status exactly like createVerifiedOrderPayment, then (since there's no
  // external gateway to enforce the charged amount the way Razorpay does)
  // performs the wallet deduction itself, atomically, checking the real
  // current balance in the same transaction. The client can no longer
  // choose what leaves its own wallet, and a stale locally-cached balance
  // can't race into an overdraft.
  //
  // `orderId` must be the same id the caller is about to write the
  // vendor_orders document under (same generateOrderId() call already used
  // for every order type) — it's what lets verifyOrder.js recognise this
  // order's deduction already happened correctly server-side.
  Future<VerifiedPaymentOrderResult> createVerifiedWalletOrder({
    required String vendorID,
    required List<CartProduct> products,
    required String orderId,
    String? couponId,
    String? sectionId,
    bool takeAway = false,
    String? deliveryCharge,
    String? tipValue,
    List<TaxModel>? taxSetting,
    // Bill Pay Accept & Pay only — see createVerifiedOrderPayment above.
    String? billPayRequestId,
    int? expectedBillVersion,
    // See createVerifiedOrderPayment's doc comment - same 2026-08-23 fix
    // (vendor-open status only, not special-discount as of the 2026-08-30
    // reversal).
    int? scheduleTimeMillis,
    // See createVerifiedOrderPayment's doc comment - same §11.21 addition.
    String? clientOrderType,
  }) async {
    final idToken = await _idToken();
    if (idToken == null) {
      return VerifiedPaymentOrderResult(errorMessage: 'Not signed in.');
    }
    try {
      final deviceId = await DeviceSessionService.getDeviceId();
      final fcmToken = await NotificationService.getToken();

      final resp = await http
          .post(
            Uri.parse('$CloudFunctionsBaseURL/createVerifiedWalletOrder'),
            headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'},
            body: jsonEncode({
              'vendorID': vendorID,
              'products': products.map((p) => p.toJson()).toList(),
              'orderId': orderId,
              'couponId': couponId,
              'sectionId': sectionId,
              'takeAway': takeAway,
              'deliveryCharge': deliveryCharge,
              'tipValue': tipValue,
              'taxSetting': taxSetting?.map((t) => t.toJson()).toList(),
              'deviceId': deviceId,
              'fcmToken': fcmToken,
              'billPayRequestId': billPayRequestId,
              'expectedBillVersion': expectedBillVersion,
              'scheduleTimeMillis': scheduleTimeMillis,
              'clientOrderType': clientOrderType,
            }),
          )
          .timeout(const Duration(seconds: 30));

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200) {
        return VerifiedPaymentOrderResult(
          success: true,
          amount: (data['verifiedTotal'] as num?)?.toDouble() ?? 0,
          verifiedDiscount: (data['verifiedDiscount'] as num?)?.toDouble() ?? 0,
          verifiedSpecialDiscount: (data['verifiedSpecialDiscount'] as num?)?.toDouble() ?? 0,
        );
      }
      if (data['error'] == 'bill_updated') {
        return VerifiedPaymentOrderResult(
          billUpdated: true,
          updatedTotal: (data['updatedTotal'] as num?)?.toDouble(),
          errorMessage: 'The restaurant updated this bill. Please review it before paying.',
        );
      }
      if (data['error'] == 'vendor_closed') {
        return VerifiedPaymentOrderResult(errorMessage: 'This restaurant is currently closed.');
      }
      if (data['error'] == 'insufficient_balance') {
        return VerifiedPaymentOrderResult(
          insufficientBalance: true,
          errorMessage: 'Insufficient wallet balance. Please top up your wallet or choose another payment method.',
        );
      }
      if (data['error'] == 'already_paid') {
        // Same orderId already paid for (retry/double-tap) — treat as
        // success from the caller's perspective, nothing left to charge.
        return VerifiedPaymentOrderResult(success: true);
      }
      if (data['error'] == 'device_superseded') {
        final retryAtRaw = data['retry_at'] as String?;
        final retryAt = retryAtRaw != null ? DateTime.tryParse(retryAtRaw) : null;
        final baseMessage = (data['message'] as String?) ??
            'This account is active on another device. You can switch devices after 2 hours.';
        return VerifiedPaymentOrderResult(
          deviceSuperseded: true,
          errorMessage: DeviceSessionService.withRetryTime(baseMessage, retryAt),
        );
      }
      if (data['error'] == 'order_draft_missing') {
        // Should not happen from a current app build - the order is always
        // staged right before this call. Safe to just retry from scratch.
        return VerifiedPaymentOrderResult(
            errorMessage: 'Could not prepare your order. Please try again.');
      }
      return VerifiedPaymentOrderResult(
          errorMessage: data['error']?.toString() ?? 'Unable to complete wallet payment. Please try again later.');
    } catch (e) {
      debugPrint('[createVerifiedWalletOrder] $e');
      return VerifiedPaymentOrderResult(errorMessage: 'Unable to complete wallet payment. Please try again later.');
    }
  }

  // Pre-order verification for a COD (Cash on Delivery) order — the server
  // recomputes subtotal/coupon/special-discount/vendor-open status exactly
  // like createVerifiedOrderPayment/createVerifiedWalletOrder and claims
  // device ownership, but charges nothing (COD collects cash at delivery/
  // pickup). Previously COD order creation never called any Cloud Function
  // at all, so a modified client could skip the client-side
  // DeviceSessionService.enforceActive() check entirely and still create a
  // real order on a superseded device — this closes that gap the same way
  // the gateway/wallet paths already were.
  //
  // `orderId` must be the same id the caller is about to write the
  // vendor_orders document under (same generateOrderId() call already used
  // for every order type) — it's what lets a retried/double-tapped call be
  // recognised as already-verified instead of claiming device ownership twice.
  Future<VerifiedPaymentOrderResult> createVerifiedCodOrder({
    required String vendorID,
    required List<CartProduct> products,
    required String orderId,
    String? couponId,
    String? sectionId,
    bool takeAway = false,
    String? deliveryCharge,
    String? tipValue,
    List<TaxModel>? taxSetting,
    // Bill Pay Accept & Pay only — see createVerifiedOrderPayment above.
    String? billPayRequestId,
    int? expectedBillVersion,
  }) async {
    final idToken = await _idToken();
    if (idToken == null) {
      return VerifiedPaymentOrderResult(errorMessage: 'Not signed in.');
    }
    try {
      final deviceId = await DeviceSessionService.getDeviceId();
      final fcmToken = await NotificationService.getToken();

      final resp = await http
          .post(
            // Pinned to its own us-central1-only URL, not CloudFunctionsBaseURL -
            // see CodOrderFunctionURL's doc comment in constants.dart.
            Uri.parse(CodOrderFunctionURL),
            headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'},
            body: jsonEncode({
              'vendorID': vendorID,
              'products': products.map((p) => p.toJson()).toList(),
              'orderId': orderId,
              'couponId': couponId,
              'sectionId': sectionId,
              'takeAway': takeAway,
              'deliveryCharge': deliveryCharge,
              'tipValue': tipValue,
              'taxSetting': taxSetting?.map((t) => t.toJson()).toList(),
              'deviceId': deviceId,
              'fcmToken': fcmToken,
              'billPayRequestId': billPayRequestId,
              'expectedBillVersion': expectedBillVersion,
            }),
          )
          .timeout(const Duration(seconds: 30));

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200) {
        return VerifiedPaymentOrderResult(
          success: true,
          amount: (data['verifiedTotal'] as num?)?.toDouble() ?? 0,
          verifiedDiscount: (data['verifiedDiscount'] as num?)?.toDouble() ?? 0,
          verifiedSpecialDiscount: (data['verifiedSpecialDiscount'] as num?)?.toDouble() ?? 0,
        );
      }
      if (data['error'] == 'bill_updated') {
        return VerifiedPaymentOrderResult(
          billUpdated: true,
          updatedTotal: (data['updatedTotal'] as num?)?.toDouble(),
          errorMessage: 'The restaurant updated this bill. Please review it before paying.',
        );
      }
      if (data['error'] == 'vendor_closed') {
        return VerifiedPaymentOrderResult(errorMessage: 'This restaurant is currently closed.');
      }
      if (data['error'] == 'device_superseded') {
        final retryAtRaw = data['retry_at'] as String?;
        final retryAt = retryAtRaw != null ? DateTime.tryParse(retryAtRaw) : null;
        final baseMessage = (data['message'] as String?) ??
            'This account is active on another device. You can switch devices after 2 hours.';
        return VerifiedPaymentOrderResult(
          deviceSuperseded: true,
          errorMessage: DeviceSessionService.withRetryTime(baseMessage, retryAt),
        );
      }
      return VerifiedPaymentOrderResult(
          errorMessage: data['error']?.toString() ?? 'Unable to verify order. Please try again later.');
    } catch (e) {
      debugPrint('[createVerifiedCodOrder] $e');
      return VerifiedPaymentOrderResult(errorMessage: 'Unable to verify order. Please try again later.');
    }
  }

  // Verified, atomic wallet payment for a Dine-In table booking deposit —
  // same shape as createVerifiedWalletOrder, but the server recomputes the
  // charge from the vendor's own bookingPricingModel/bookingCharge config
  // instead of a cart. `bookingId` must be the same id the caller is about
  // to write the booked_table document under (see FirebaseHelper.bookTable).
  Future<VerifiedPaymentOrderResult> createVerifiedTableBookingPayment({
    required String vendorID,
    required int guestCount,
    required String bookingId,
  }) async {
    final idToken = await _idToken();
    if (idToken == null) {
      return VerifiedPaymentOrderResult(errorMessage: 'Not signed in.');
    }
    try {
      final deviceId = await DeviceSessionService.getDeviceId();
      final fcmToken = await NotificationService.getToken();

      final resp = await http
          .post(
            Uri.parse('$CloudFunctionsBaseURL/createVerifiedTableBookingPayment'),
            headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'},
            body: jsonEncode({
              'vendorID': vendorID,
              'guestCount': guestCount,
              'bookingId': bookingId,
              'deviceId': deviceId,
              'fcmToken': fcmToken,
            }),
          )
          .timeout(const Duration(seconds: 30));

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200) {
        return VerifiedPaymentOrderResult(
          success: true,
          amount: (data['verifiedCharge'] as num?)?.toDouble() ?? 0,
        );
      }
      if (data['error'] == 'insufficient_balance') {
        return VerifiedPaymentOrderResult(
          insufficientBalance: true,
          errorMessage: 'Insufficient wallet balance. Please top up your wallet or choose another payment method.',
        );
      }
      if (data['error'] == 'already_paid') {
        return VerifiedPaymentOrderResult(success: true);
      }
      if (data['error'] == 'device_superseded') {
        final retryAtRaw = data['retry_at'] as String?;
        final retryAt = retryAtRaw != null ? DateTime.tryParse(retryAtRaw) : null;
        final baseMessage = (data['message'] as String?) ??
            'This account is active on another device. You can switch devices after 2 hours.';
        return VerifiedPaymentOrderResult(
          deviceSuperseded: true,
          errorMessage: DeviceSessionService.withRetryTime(baseMessage, retryAt),
        );
      }
      return VerifiedPaymentOrderResult(
          errorMessage: data['error']?.toString() ?? 'Unable to complete booking payment. Please try again later.');
    } catch (e) {
      debugPrint('[createVerifiedTableBookingPayment] $e');
      return VerifiedPaymentOrderResult(errorMessage: 'Unable to complete booking payment. Please try again later.');
    }
  }

  // Wallet top-up has no "true" server-known amount — the fix is guaranteeing
  // the credited amount is exactly what Razorpay actually confirms was paid.
  //
  // Moved off Cloud Functions onto the Laravel server (2026-08-23) - same
  // WalletTopupController already live for Vendor Web, confirmed working
  // with a real payment there before this switch. Only this method and its
  // 'wallet_topup' branch in verifyPayment() below moved - 'order' and
  // 'gift_card' verifyPayment calls are unaffected, WalletTopupController
  // doesn't implement those.
  Future<VerifiedPaymentOrderResult> createWalletTopupOrder({required double amount}) async {
    final idToken = await _idToken();
    if (idToken == null) {
      return VerifiedPaymentOrderResult(errorMessage: 'Not signed in.');
    }
    try {
      final resp = await http
          .post(
            Uri.parse('${GlobalURL}api/wallet/topup/create'),
            headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'},
            body: jsonEncode({'amount': amount}),
          )
          .timeout(const Duration(seconds: 30));

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200) {
        return VerifiedPaymentOrderResult(
          success: true,
          razorpayOrderId: data['razorpayOrderId']?.toString(),
          razorpayKey: data['razorpayKey']?.toString(),
          amount: (data['amount'] as num?)?.toDouble() ?? amount,
        );
      }
      return VerifiedPaymentOrderResult(
          errorMessage: data['error']?.toString() ?? 'Unable to initialize payment. Please try again later.');
    } catch (e) {
      debugPrint('[createWalletTopupOrder] $e');
      return VerifiedPaymentOrderResult(errorMessage: 'Unable to initialize payment. Please try again later.');
    }
  }

  // A gift card has no fixed catalog price - same bounded-amount pattern as
  // createWalletTopupOrder. The gift_purchases record itself (code/pin/
  // expiry) is created server-side too, inside verifyPayment's own
  // transaction, once the payment is verified - not by this app afterward.
  Future<VerifiedPaymentOrderResult> createGiftCardPaymentOrder({
    required double amount,
    required String giftId,
    String? message,
  }) async {
    final idToken = await _idToken();
    if (idToken == null) {
      return VerifiedPaymentOrderResult(errorMessage: 'Not signed in.');
    }
    try {
      final resp = await http
          .post(
            Uri.parse('$CloudFunctionsBaseURL/createGiftCardPaymentOrder'),
            headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'},
            body: jsonEncode({'amount': amount, 'giftId': giftId, 'message': message}),
          )
          .timeout(const Duration(seconds: 30));

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200) {
        return VerifiedPaymentOrderResult(
          success: true,
          razorpayOrderId: data['razorpayOrderId']?.toString(),
          razorpayKey: data['razorpayKey']?.toString(),
          amount: (data['amount'] as num?)?.toDouble() ?? amount,
        );
      }
      return VerifiedPaymentOrderResult(
          errorMessage: data['error']?.toString() ?? 'Unable to initialize payment. Please try again later.');
    } catch (e) {
      debugPrint('[createGiftCardPaymentOrder] $e');
      return VerifiedPaymentOrderResult(errorMessage: 'Unable to initialize payment. Please try again later.');
    }
  }

  // Verifies the Razorpay payment signature server-side before the app is
  // allowed to treat the payment as legitimate. purpose is 'order',
  // 'gift_card', or 'wallet_topup'; for 'wallet_topup' this is also what
  // actually credits the wallet (server-side, once — replay-guarded by the
  // intent's `consumed` flag).
  //
  // 'wallet_topup' moved to the Laravel WalletTopupController (2026-08-23,
  // same as createWalletTopupOrder above) - 'order'/'gift_card' stay on
  // Cloud Functions' verifyRazorpayPayment, which is the only place that
  // implements those two branches.
  Future<VerifyPaymentResult> verifyPayment({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
    required String purpose,
  }) async {
    final idToken = await _idToken();
    if (idToken == null) {
      return VerifyPaymentResult(errorMessage: 'Not signed in.');
    }
    final url = purpose == 'wallet_topup'
        ? '${GlobalURL}api/wallet/topup/verify'
        : '$CloudFunctionsBaseURL/verifyRazorpayPayment';
    try {
      final resp = await http
          .post(
            Uri.parse(url),
            headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'},
            body: jsonEncode({
              'razorpayOrderId': razorpayOrderId,
              'razorpayPaymentId': razorpayPaymentId,
              'razorpaySignature': razorpaySignature,
              'purpose': purpose,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200) {
        return VerifyPaymentResult(success: true);
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return VerifyPaymentResult(
          errorMessage: data['error']?.toString() ?? 'Payment verification failed. Please contact support.');
    } catch (e) {
      debugPrint('[verifyPayment] $e');
      return VerifyPaymentResult(errorMessage: 'Payment verification failed. Please contact support.');
    }
  }

  Future<RazorPayResult> createOrderRazorPay(
      {required double amount, bool isTopup = false}) async {
    final RazorPayModel? razorPayData = UserPreference.getRazorPayData();

    if (razorPayData == null ||
        razorPayData.razorpayKey.isEmpty ||
        razorPayData.razorpaySecret.isEmpty) {
      return RazorPayResult(
        errorType: RazorPayErrorType.missingCredentials,
        errorMessage: 'Invalid payment credentials configured.',
      );
    }

    // Ensure currency is available before calling the API.
    if (currencyData == null || currencyData!.code.isEmpty) {
      try {
        final fetched = await FireStoreUtils().getCurrency();
        if (fetched != null && fetched.code.isNotEmpty) {
          currencyData = fetched;
        } else {
          currencyData = _defaultCurrency();
        }
      } catch (_) {
        currencyData = _defaultCurrency();
      }
    }

    if (currencyData == null || currencyData!.code.isEmpty) {
      return RazorPayResult(
        errorType: RazorPayErrorType.missingCurrency,
        errorMessage: 'Payment configuration error. Please contact support.',
      );
    }

    const url = "${GlobalURL}payments/razorpay/createorder";

    // This endpoint now requires a signed-in caller (verify.firebase
    // middleware) — previously open/unauthenticated. Still used by gift-card
    // purchase and dine-in booking (order-payment and wallet-topup flows
    // moved to createVerifiedOrderPayment/createWalletTopupOrder above).
    final idToken = await _idToken();
    if (idToken == null) {
      return RazorPayResult(
        errorType: RazorPayErrorType.missingCredentials,
        errorMessage: 'Not signed in.',
      );
    }

    try {
      final requestBody = {
        "amount": ((amount * 100).toInt()).toString(),
        "receipt_id": const Uuid().v4(),
        "currency": currencyData!.code,
        "razorpaykey": razorPayData.razorpayKey,
        "razorPaySecret": razorPayData.razorpaySecret,
        "isSandBoxEnabled": razorPayData.isSandboxEnabled.toString(),
      };

      final response = await http
          .post(Uri.parse(url), headers: {'Authorization': 'Bearer $idToken'}, body: requestBody)
          .timeout(const Duration(seconds: 30), onTimeout: () {
        throw Exception('Request timeout');
      });

      debugPrint('[RazorPay] status=${response.statusCode} body=${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final raw = jsonDecode(response.body);

          // Unwrap common server envelopes: {"data": {...}} or {"order": {...}}
          Map<String, dynamic>? data;
          if (raw is Map<String, dynamic>) {
            if (raw.containsKey('data') && raw['data'] is Map<String, dynamic>) {
              data = raw['data'] as Map<String, dynamic>;
            } else if (raw.containsKey('order') && raw['order'] is Map<String, dynamic>) {
              data = raw['order'] as Map<String, dynamic>;
            } else {
              data = raw;
            }
          }

          if (data == null) {
            return RazorPayResult(
              errorType: RazorPayErrorType.invalidResponse,
              errorMessage: 'Payment service is temporarily unavailable. Please try again later.',
            );
          }

          // Surface any error returned by the server or Razorpay
          if (data.containsKey('error')) {
            final err = data['error'];
            String msg = 'Unable to initialize payment. Please try again later.';
            if (err is Map && err.containsKey('description')) {
              msg = err['description'].toString();
            } else if (err is String && err.isNotEmpty) {
              msg = err;
            }
            return RazorPayResult(errorType: RazorPayErrorType.apiError, errorMessage: msg);
          }

          // Also handle {status: false/error, message: "..."} style responses
          if (data.containsKey('message') && !data.containsKey('id')) {
            final msg = data['message']?.toString() ?? 'Unable to initialize payment.';
            return RazorPayResult(errorType: RazorPayErrorType.apiError, errorMessage: msg);
          }

          if (!data.containsKey('id')) {
            return RazorPayResult(
              errorType: RazorPayErrorType.invalidResponse,
              errorMessage: 'Payment service is temporarily unavailable. Please try again later.',
            );
          }

          return RazorPayResult(order: CreateRazorPayOrderModel.fromJson(data));
        } catch (parseErr) {
          debugPrint('[RazorPay] parse error: $parseErr');
          return RazorPayResult(
            errorType: RazorPayErrorType.invalidResponse,
            errorMessage: 'Unable to initialize payment. Please try again later.',
          );
        }
      } else {
        String errorMsg = 'Payment service is temporarily unavailable. (HTTP ${response.statusCode})';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map<String, dynamic>) {
            if (errorData.containsKey('error')) {
              final err = errorData['error'];
              errorMsg = err is Map
                  ? (err['description']?.toString() ?? errorMsg)
                  : err.toString();
            } else if (errorData.containsKey('message')) {
              errorMsg = errorData['message'].toString();
            }
          }
        } catch (_) {}
        debugPrint('[RazorPay] error response: $errorMsg');
        return RazorPayResult(errorType: RazorPayErrorType.apiError, errorMessage: errorMsg);
      }
    } catch (e) {
      debugPrint('[RazorPay] exception: $e');
      final isTimeout = e.toString().contains('timeout') ||
          e.toString().contains('TimeoutException');
      return RazorPayResult(
        errorType: isTimeout ? RazorPayErrorType.timeout : RazorPayErrorType.networkError,
        errorMessage: 'Unable to initialize payment. Please try again later.',
      );
    }
  }

  CurrencyModel _defaultCurrency() => CurrencyModel(
        id: '',
        code: 'INR',
        decimal: 2,
        isactive: true,
        name: 'Indian Rupee',
        symbol: '₹',
        symbolatright: false,
      );
}
