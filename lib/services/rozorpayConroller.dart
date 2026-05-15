import 'dart:convert';

import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/CurrencyModel.dart';
import 'package:emartconsumer/model/createRazorPayOrderModel.dart';
import 'package:emartconsumer/model/razorpayKeyModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/userPrefrence.dart';
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

class RazorPayController {
  Future<RazorPayResult> createOrderRazorPay(
      {required double amount, bool isTopup = false}) async {
    final RazorPayModel razorPayData = UserPreference.getRazorPayData();

    if (razorPayData.razorpayKey.isEmpty ||
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
          .post(Uri.parse(url), body: requestBody)
          .timeout(const Duration(seconds: 30), onTimeout: () {
        throw Exception('Request timeout');
      });

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final data = jsonDecode(response.body);
          if (data is Map<String, dynamic>) {
            if (data.containsKey('error')) {
              String msg =
                  'Unable to initialize payment. Please try again later.';
              if (data['error'] is Map &&
                  data['error'].containsKey('description')) {
                msg = data['error']['description'].toString();
              }
              return RazorPayResult(
                  errorType: RazorPayErrorType.apiError, errorMessage: msg);
            }
            if (!data.containsKey('id')) {
              return RazorPayResult(
                errorType: RazorPayErrorType.invalidResponse,
                errorMessage:
                    'Payment service is temporarily unavailable. Please try again later.',
              );
            }
            return RazorPayResult(
                order: CreateRazorPayOrderModel.fromJson(data));
          }
          return RazorPayResult(
            errorType: RazorPayErrorType.invalidResponse,
            errorMessage:
                'Payment service is temporarily unavailable. Please try again later.',
          );
        } catch (_) {
          return RazorPayResult(
            errorType: RazorPayErrorType.invalidResponse,
            errorMessage:
                'Unable to initialize payment. Please try again later.',
          );
        }
      } else {
        String errorMsg =
            'Payment service is temporarily unavailable. Please try again later.';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map<String, dynamic>) {
            if (errorData.containsKey('error')) {
              errorMsg = errorData['error'] is Map
                  ? (errorData['error']['description']?.toString() ?? errorMsg)
                  : errorData['error'].toString();
            } else if (errorData.containsKey('message')) {
              errorMsg = errorData['message'].toString();
            }
          }
        } catch (_) {}
        return RazorPayResult(
            errorType: RazorPayErrorType.apiError, errorMessage: errorMsg);
      }
    } catch (e) {
      final isTimeout = e.toString().contains('timeout') ||
          e.toString().contains('TimeoutException');
      return RazorPayResult(
        errorType:
            isTimeout ? RazorPayErrorType.timeout : RazorPayErrorType.networkError,
        errorMessage:
            'Unable to initialize payment. Please try again later.',
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
