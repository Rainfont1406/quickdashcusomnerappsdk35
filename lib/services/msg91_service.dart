import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class Msg91Response {
  final bool success;
  final String message;
  const Msg91Response({required this.success, required this.message});
}

class _Msg91Settings {
  final String authKey;
  final String templateId;
  final String senderId;
  final int otpLength;
  final int otpExpiryMinutes;

  const _Msg91Settings({
    required this.authKey,
    required this.templateId,
    required this.senderId,
    required this.otpLength,
    required this.otpExpiryMinutes,
  });
}

/// Calls MSG91 OTP API directly.
/// Credentials live in Firestore: settings/msg91
/// Fields: authkey, templateid, senderid, otpLength, otpExpiryMinutes, enabled
class Msg91Service {
  static _Msg91Settings? _cache;
  static const _base = 'https://api.msg91.com/api/v5/otp';
  static const _timeout = Duration(seconds: 30);

  /// OTP digit length — read from Firestore; exposed so UI can configure PinField.
  static int get otpLength => _cache?.otpLength ?? 4;

  // ── Credential loader ─────────────────────────────────────────────────
  static Future<_Msg91Settings?> _settings() async {
    if (_cache != null) return _cache;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('msg91')
          .get();
      if (!doc.exists || doc.data() == null) return null;
      final d = doc.data()!;

      final enabled = d['enabled'] as bool? ?? true;
      if (!enabled) return null;

      _cache = _Msg91Settings(
        authKey: d['authkey']?.toString() ?? '',
        templateId: d['templateid']?.toString() ?? '',
        senderId: d['senderid']?.toString() ?? 'msg91',
        otpLength: (d['otpLength'] as num?)?.toInt() ?? 4,
        otpExpiryMinutes: (d['otpExpiryMinutes'] as num?)?.toInt() ?? 10,
      );
      return _cache;
    } catch (_) {
      return null;
    }
  }

  /// Clears cached settings (call after Firestore settings are updated).
  static void clearCache() => _cache = null;

  static String _mobile(String countryCode, String phone) =>
      countryCode.replaceFirst('+', '') + phone.replaceAll(RegExp(r'\D'), '');

  // ── Send OTP ──────────────────────────────────────────────────────────
  static Future<Msg91Response> sendOtp(
      String countryCode, String phoneNumber) async {
    final s = await _settings();
    if (s == null || s.authKey.isEmpty) {
      return const Msg91Response(
          success: false,
          message: 'OTP service is not configured. Please contact support.');
    }
    try {
      final uri = Uri.parse(_base).replace(queryParameters: {
        'template_id': s.templateId,
        'mobile': _mobile(countryCode, phoneNumber),
        'authkey': s.authKey,
        'otp_length': s.otpLength.toString(),
        'otp_expiry': s.otpExpiryMinutes.toString(),
        'sender': s.senderId,
      });
      final resp = await http.get(uri).timeout(_timeout);
      return _parse(resp, ok: 'Verification code sent successfully.');
    } on SocketException {
      return const Msg91Response(
          success: false,
          message: 'No internet connection. Please try again.');
    } catch (_) {
      return const Msg91Response(
          success: false,
          message: 'Failed to send OTP. Please try again.');
    }
  }

  // ── Verify OTP ────────────────────────────────────────────────────────
  static Future<Msg91Response> verifyOtp(
      String countryCode, String phoneNumber, String otp) async {
    final s = await _settings();
    if (s == null || s.authKey.isEmpty) {
      return const Msg91Response(
          success: false, message: 'OTP service is not configured.');
    }
    try {
      final uri = Uri.parse('$_base/verify').replace(queryParameters: {
        'otp': otp,
        'mobile': _mobile(countryCode, phoneNumber),
        'authkey': s.authKey,
      });
      final resp = await http.get(uri).timeout(_timeout);
      return _parse(resp, ok: 'OTP verified successfully.');
    } on SocketException {
      return const Msg91Response(
          success: false,
          message: 'No internet connection. Please try again.');
    } catch (_) {
      return const Msg91Response(
          success: false,
          message: 'Verification failed. Please try again.');
    }
  }

  // ── Resend OTP ────────────────────────────────────────────────────────
  static Future<Msg91Response> resendOtp(
      String countryCode, String phoneNumber) async {
    final s = await _settings();
    if (s == null || s.authKey.isEmpty) {
      return const Msg91Response(
          success: false, message: 'OTP service is not configured.');
    }
    try {
      final uri = Uri.parse('$_base/retry').replace(queryParameters: {
        'retrytype': 'text',
        'mobile': _mobile(countryCode, phoneNumber),
        'authkey': s.authKey,
      });
      final resp = await http.get(uri).timeout(_timeout);
      return _parse(resp, ok: 'Verification code resent successfully.');
    } on SocketException {
      return const Msg91Response(
          success: false,
          message: 'No internet connection. Please try again.');
    } catch (_) {
      return const Msg91Response(
          success: false,
          message: 'Failed to resend OTP. Please try again.');
    }
  }

  // ── Response parser ───────────────────────────────────────────────────
  static Msg91Response _parse(http.Response resp, {required String ok}) {
    try {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final success = data['type']?.toString() == 'success';
      final raw = data['message']?.toString() ?? '';
      return Msg91Response(
          success: success, message: success ? ok : _friendly(raw));
    } catch (_) {
      final success = resp.statusCode == 200;
      return Msg91Response(
          success: success,
          message:
              success ? ok : 'Something went wrong. Please try again.');
    }
  }

  static String _friendly(String raw) {
    if (raw.isEmpty) return 'Something went wrong. Please try again.';
    final lower = raw.toLowerCase();
    if (lower.contains('invalid otp') ||
        lower.contains('otp not found') ||
        lower.contains('otp not match') ||
        lower.contains('incorrect otp')) {
      return 'Incorrect OTP. Please try again.';
    }
    if (lower.contains('expir')) {
      return 'OTP has expired. Please request a new one.';
    }
    if (lower.contains('too many') || lower.contains('limit')) {
      return 'Too many attempts. Please try again in a few minutes.';
    }
    if (lower.contains('invalid mobile') || lower.contains('invalid number')) {
      return 'Invalid phone number. Please check and try again.';
    }
    return raw;
  }
}
