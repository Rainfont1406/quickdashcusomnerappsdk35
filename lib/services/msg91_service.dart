import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// MSG91 OTP service — calls the QuickDash Laravel server proxy.
/// The MSG91 authkey never leaves the server; apps only send the phone number.
class Msg91Response {
  final bool success;
  final String message;
  const Msg91Response({required this.success, required this.message});
}

class Msg91Service {
  static const _base = 'https://admin.quickdash.co.in/api/msg91';
  static const _timeout = Duration(seconds: 25);

  // Cached from /api/msg91/config
  static int _otpLength = 4;
  static int get otpLength => _otpLength;

  /// Call once at app start (or before the OTP screen) to get non-secret config.
  static Future<void> loadConfig() async {
    try {
      final resp = await http
          .get(Uri.parse('$_base/config'))
          .timeout(_timeout);
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (body['success'] == true && body['data'] != null) {
        _otpLength = (body['data']['otpLength'] as num?)?.toInt() ?? 4;
      }
    } catch (_) {}
  }

  static String _mobile(String countryCode, String phone) =>
      countryCode.replaceFirst('+', '') + phone.replaceAll(RegExp(r'\D'), '');

  // ── Send OTP ──────────────────────────────────────────────────────────

  static Future<Msg91Response> sendOtp(
      String countryCode, String phoneNumber) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$_base/send'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'mobile': _mobile(countryCode, phoneNumber)}),
          )
          .timeout(_timeout);
      return _parse(resp, ok: 'Verification code sent successfully.');
    } on TimeoutException {
      return const Msg91Response(
          success: false,
          message: 'Request timed out. Please try again.');
    } catch (_) {
      return const Msg91Response(
          success: false,
          message: 'No internet connection. Please try again.');
    }
  }

  // ── Verify OTP ────────────────────────────────────────────────────────

  static Future<Msg91Response> verifyOtp(
      String countryCode, String phoneNumber, String otp) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$_base/verify'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'mobile': _mobile(countryCode, phoneNumber),
              'otp': otp,
            }),
          )
          .timeout(_timeout);
      return _parse(resp, ok: 'OTP verified successfully.');
    } on TimeoutException {
      return const Msg91Response(
          success: false,
          message: 'Request timed out. Please try again.');
    } catch (_) {
      return const Msg91Response(
          success: false,
          message: 'Verification failed. Please try again.');
    }
  }

  // ── Resend OTP ────────────────────────────────────────────────────────

  static Future<Msg91Response> resendOtp(
      String countryCode, String phoneNumber) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$_base/resend'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'mobile': _mobile(countryCode, phoneNumber)}),
          )
          .timeout(_timeout);
      return _parse(resp, ok: 'Verification code resent successfully.');
    } on TimeoutException {
      return const Msg91Response(
          success: false,
          message: 'Request timed out. Please try again.');
    } catch (_) {
      return const Msg91Response(
          success: false,
          message: 'Failed to resend OTP. Please try again.');
    }
  }

  // ── Parser ────────────────────────────────────────────────────────────

  static Msg91Response _parse(http.Response resp, {required String ok}) {
    try {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final success = data['success'] == true;
      return Msg91Response(
          success: success,
          message: success ? ok : (data['message']?.toString() ?? ok));
    } catch (_) {
      final success = resp.statusCode == 200;
      return Msg91Response(
          success: success,
          message: success ? ok : 'Something went wrong. Please try again.');
    }
  }
}

// ── Compatibility shims for callers that import the old OTPResponse types ──

class OTPResponse {
  final bool success;
  final String message;
  final String? type;
  final String? error;
  final int? httpStatus;

  OTPResponse({
    required this.success,
    required this.message,
    this.type,
    this.error,
    this.httpStatus,
  });
}

class OTPVerificationResponse {
  final bool success;
  final String message;
  final String? verificationId;
  final String? error;
  final int? httpStatus;

  OTPVerificationResponse({
    required this.success,
    required this.message,
    this.verificationId,
    this.error,
    this.httpStatus,
  });
}

/// Legacy-compatible class used by PhoneNumberController in the Customer App.
class MSG91Service {
  static int get otpDigits => Msg91Service.otpLength;

  static Future<void> init() => Msg91Service.loadConfig();

  static Future<OTPResponse> sendOTP(String phoneNumber) async {
    final r = await Msg91Service.sendOtp('', phoneNumber);
    return OTPResponse(success: r.success, message: r.message);
  }

  static Future<OTPVerificationResponse> verifyOTP(
      String phoneNumber, String otp) async {
    final r = await Msg91Service.verifyOtp('', phoneNumber, otp);
    return OTPVerificationResponse(
        success: r.success, message: r.message, verificationId: phoneNumber);
  }

  static Future<OTPResponse> resendOTP(String phoneNumber) async {
    final r = await Msg91Service.resendOtp('', phoneNumber);
    return OTPResponse(success: r.success, message: r.message);
  }
}
