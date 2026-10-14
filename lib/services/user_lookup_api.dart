import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emartconsumer/constants.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:http/http.dart' as http;

/// Server-side replacements for pre-login queries on the `users` collection (Phase 1 of closing
/// firestore.rules `allow list: if true` on users/{uid}, 2026-10-14). The server answers only yes/no
/// (POST /api/auth/lookup, see UserLookupController). While [allowDirectQueryFallback] is true a
/// server that cannot be reached falls back to the old direct query, so nothing changes for users in
/// the transition. Phase 2 sets it to false when the rule closes.
class UserLookupApi {
  static const bool allowDirectQueryFallback = true;

  static String get _base =>
      appFlavor == 'staging' ? 'https://staging-admin.quickdash.co.in' : 'https://admin.quickdash.co.in';

  /// true / false = the server's answer. null = the server could not be reached or answered with an error.
  static Future<bool?> exists({
    required String check,
    required String value,
    String? role,
    String? countryCode,
    String? excludeUid,
  }) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$_base/api/auth/lookup'),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({
              'check': check,
              'value': value,
              if (role != null) 'role': role,
              if (countryCode != null && countryCode.isNotEmpty) 'countryCode': countryCode,
              if (excludeUid != null) 'excludeUid': excludeUid,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      if (body is Map && body['exists'] is bool) return body['exists'] as bool;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Is there already a CUSTOMER account with this email? (role-scoped: a vendor or driver with the
  /// same email is not a conflict).
  static Future<bool> customerEmailTaken(String normalizedEmail) async {
    final r = await exists(check: 'email', value: normalizedEmail, role: USER_ROLE_CUSTOMER);
    if (r != null) return r;
    if (!allowDirectQueryFallback) throw StateError('user lookup unavailable');
    final snap = await FirebaseFirestore.instance.collection(USERS).where('email', isEqualTo: normalizedEmail).get();
    return snap.docs.any((d) => (d.data()['role'] as String? ?? '') == USER_ROLE_CUSTOMER);
  }

  /// Is there already a CUSTOMER account with this phone number and country code?
  static Future<bool> customerPhoneRegistered(String phone, String countryCode) async {
    final r = await exists(check: 'phone', value: phone.trim(), role: USER_ROLE_CUSTOMER, countryCode: countryCode);
    if (r != null) return r;
    if (!allowDirectQueryFallback) throw StateError('user lookup unavailable');
    final snap = await FirebaseFirestore.instance.collection(USERS).where('phoneNumber', isEqualTo: phone.trim()).get();
    return snap.docs.any((d) {
      final data = d.data();
      return (data['role'] as String? ?? '') == USER_ROLE_CUSTOMER && (data['countryCode'] as String? ?? '') == countryCode;
    });
  }
}
