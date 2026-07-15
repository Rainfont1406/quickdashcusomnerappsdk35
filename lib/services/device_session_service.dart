import 'dart:convert';
import 'dart:developer';

import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _kApiBase = 'https://admin.quickdash.co.in';
const _kDeviceIdPrefKey = 'device_session_device_id';

class DeviceSessionResult {
  final bool allowed;
  final String? message;
  final DateTime? retryAt;

  const DeviceSessionResult.allowed()
      : allowed = true,
        message = null,
        retryAt = null;

  const DeviceSessionResult.denied(this.message, this.retryAt) : allowed = false;
}

/// Outcome of a reconnect-triggered re-check (see [DeviceSessionService.verifyOnReconnect]).
/// Distinct from a plain bool so the offline gate can tell "confirmed still
/// active" apart from "couldn't get a definitive answer" — the latter fails
/// open (closes the gate) rather than being treated as invalidated.
enum ReconnectCheckResult { active, invalidated, unknown }

/// One-active-device login gate with a 2-hour device-switch cooldown,
/// enforced server-side (see DeviceSessionController::authorizeLogin on the
/// admin.quickdash.co.in backend). The server owns the clock and the
/// allow/deny decision; this client only calls it and acts on the result.
class DeviceSessionService {
  /// Stable per-install identifier. Persisted locally — a reinstall gets a
  /// new one, which is expected (there's no cross-install device identity
  /// on mobile without a native plugin).
  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kDeviceIdPrefKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_kDeviceIdPrefKey, id);
    }
    return id;
  }

  /// Must be called right after a Firebase Auth sign-in succeeds
  /// (email/password or OTP custom-token), before the account is used for
  /// anything else. On denial this signs the just-established session back
  /// out — the caller must stop and surface [DeviceSessionResult.message],
  /// not proceed to load the profile or navigate in.
  static Future<DeviceSessionResult> authorize({required String fcmToken}) async {
    final user = auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const DeviceSessionResult.denied('Not signed in.', null);
    }

    try {
      final idToken = await user.getIdToken();
      final deviceId = await getDeviceId();

      final resp = await http
          .post(
            Uri.parse('$_kApiBase/api/auth/device-session/authorize'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({'device_id': deviceId, 'fcm_token': fcmToken}),
          )
          .timeout(const Duration(seconds: 20));

      final body = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode == 409 || body['allowed'] == false) {
        await auth.FirebaseAuth.instance.signOut();
        final retryAtRaw = body['retry_at'] as String?;
        final retryAt = retryAtRaw != null ? DateTime.tryParse(retryAtRaw) : null;
        final baseMessage = (body['message'] as String?) ??
            'This account is active on another device. You can switch devices after 2 hours.';
        return DeviceSessionResult.denied(withRetryTime(baseMessage, retryAt), retryAt);
      }

      if (resp.statusCode != 200) {
        // Unexpected server error — fail open on login rather than let a
        // gate outage block every customer from signing in. The one-device
        // rule is a UX/anti-sharing control, not the account's real
        // security boundary, so this trade-off favours availability.
        log('[DeviceSession] authorize failed: HTTP ${resp.statusCode} ${resp.body}');
        return const DeviceSessionResult.allowed();
      }

      return const DeviceSessionResult.allowed();
    } catch (e) {
      log('[DeviceSession] authorize error: $e');
      return const DeviceSessionResult.allowed();
    }
  }

  static String withRetryTime(String baseMessage, DateTime? retryAt) {
    if (retryAt == null) return baseMessage;
    final remaining = retryAt.difference(DateTime.now());
    if (remaining.isNegative) return baseMessage;
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    return '$baseMessage Please try again after ${hours}h ${minutes}m.';
  }

  /// Cooldown-gated device-ownership claim triggered by a trusted server
  /// verification event — NOT a login. Currently called only from Vendor
  /// Bill Pay's "Accept & Pay" tap (the normal Place Order flow's equivalent
  /// claim happens server-side, inside createVerifiedOrderPayment, since
  /// that's already a server-to-server trusted event). Must be called only
  /// at the moment of a deliberate, verified action — never from passive
  /// browsing/resume, or simply opening a screen would change session
  /// ownership.
  ///
  /// Same allow/deny/switch semantics as [authorize]: on denial this signs
  /// the caller out (a device denied here has just learned another device
  /// is genuinely active) and the caller must stop and surface
  /// [DeviceSessionResult.message], not proceed.
  static Future<DeviceSessionResult> claim({required String fcmToken}) async {
    final user = auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const DeviceSessionResult.denied('Not signed in.', null);
    }

    try {
      final idToken = await user.getIdToken();
      final deviceId = await getDeviceId();

      final resp = await http
          .post(
            Uri.parse('$_kApiBase/api/auth/device-session/claim'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({'device_id': deviceId, 'fcm_token': fcmToken}),
          )
          .timeout(const Duration(seconds: 20));

      final body = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode == 409 || body['allowed'] == false) {
        await auth.FirebaseAuth.instance.signOut();
        final retryAtRaw = body['retry_at'] as String?;
        final retryAt = retryAtRaw != null ? DateTime.tryParse(retryAtRaw) : null;
        final baseMessage = (body['message'] as String?) ??
            'This account is active on another device. You can switch devices after 2 hours.';
        return DeviceSessionResult.denied(withRetryTime(baseMessage, retryAt), retryAt);
      }

      if (resp.statusCode != 200) {
        // Same fail-open trade-off as authorize() — an outage in this gate
        // must not block every checkout, and the login-time gate already
        // provides the main protection.
        log('[DeviceSession] claim failed: HTTP ${resp.statusCode} ${resp.body}');
        return const DeviceSessionResult.allowed();
      }

      return const DeviceSessionResult.allowed();
    } catch (e) {
      log('[DeviceSession] claim error: $e');
      return const DeviceSessionResult.allowed();
    }
  }

  static DateTime? _lastCheckAt;
  static bool _lastCheckActive = true;
  static const _checkCacheWindow = Duration(seconds: 20);

  /// Confirms this device is still the account's active device. Call this
  /// on app resume and before sensitive actions (placing an order, paying a
  /// bill, wallet top-up, saving profile) — a login-time check alone misses
  /// the case where this device got switched out by another login while it
  /// had no signal to receive the force-logout push (offline, backgrounded,
  /// notifications denied, etc.).
  ///
  /// Results are cached briefly so gating several actions in quick
  /// succession doesn't fire a network call per tap; fails open on
  /// network/server errors for the same availability reasons as [authorize].
  static Future<bool> checkActive() async {
    final user = auth.FirebaseAuth.instance.currentUser;
    if (user == null) return true; // nothing to invalidate — not this service's concern

    final now = DateTime.now();
    if (_lastCheckAt != null && now.difference(_lastCheckAt!) < _checkCacheWindow) {
      return _lastCheckActive;
    }

    try {
      final idToken = await user.getIdToken();
      final deviceId = await getDeviceId();

      final resp = await http
          .post(
            Uri.parse('$_kApiBase/api/auth/device-session/check'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({'device_id': deviceId}),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        log('[DeviceSession] check failed: HTTP ${resp.statusCode} ${resp.body}');
        return true; // fail open — see [authorize]
      }

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final active = body['active'] != false;
      _lastCheckAt = now;
      _lastCheckActive = active;
      return active;
    } catch (e) {
      log('[DeviceSession] check error: $e');
      return true; // fail open — see [authorize]
    }
  }

  /// One-off, cache-bypassing re-check for the offline connectivity gate:
  /// called the instant connectivity returns after the device was offline.
  /// Deliberately reuses the passive check endpoint (not [claim]) — merely
  /// reconnecting must never change session ownership, only confirm it.
  ///
  /// Distinguishes a confirmed "you've been superseded" (runs the normal
  /// force-logout flow and returns [ReconnectCheckResult.invalidated]) from
  /// "couldn't get a definitive answer" ([ReconnectCheckResult.unknown]) —
  /// the gate fails OPEN on the latter (a Laravel-side outage must not trap
  /// every currently-logged-in user behind the offline screen), same as
  /// every other device-session touchpoint in this system.
  static Future<ReconnectCheckResult> verifyOnReconnect(BuildContext? context) async {
    final user = auth.FirebaseAuth.instance.currentUser;
    if (user == null) return ReconnectCheckResult.active; // nothing to invalidate — not this service's concern

    try {
      final idToken = await user.getIdToken();
      final deviceId = await getDeviceId();

      final resp = await http
          .post(
            Uri.parse('$_kApiBase/api/auth/device-session/check'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({'device_id': deviceId}),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        log('[DeviceSession] verifyOnReconnect failed: HTTP ${resp.statusCode} ${resp.body}');
        return ReconnectCheckResult.unknown;
      }

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final active = body['active'] != false;
      _lastCheckAt = DateTime.now();
      _lastCheckActive = active;

      if (!active) {
        await handleSessionInvalidated(
          context,
          message: 'Your account is active on another device. Please sign in again.',
        );
        return ReconnectCheckResult.invalidated;
      }
      return ReconnectCheckResult.active;
    } catch (e) {
      log('[DeviceSession] verifyOnReconnect error: $e');
      return ReconnectCheckResult.unknown;
    }
  }

  /// Signs out locally because the server says this is no longer the active
  /// device. Shared by the FCM force-logout push handler and [enforceActive].
  static Future<void> handleSessionInvalidated(BuildContext? context, {String? message}) async {
    if (auth.FirebaseAuth.instance.currentUser == null) return;
    await auth.FirebaseAuth.instance.signOut();
    MyAppState.currentUser = null;
    _lastCheckAt = null;
    if (context != null && context.mounted) {
      ShowToastDialog.showToast(
          (message ?? 'You were logged out because your account was signed in on another device.').tr());
      pushAndRemoveUntil(context, const LoginScreen());
    }
  }

  /// Convenience guard for sensitive actions: `if (!await DeviceSessionService.enforceActive(context)) return;`
  /// Returns true if the caller may proceed; on false it has already signed
  /// the user out and navigated to the login screen.
  static Future<bool> enforceActive(BuildContext context) async {
    final active = await checkActive();
    if (!active) {
      await handleSessionInvalidated(context);
      return false;
    }
    return true;
  }
}
