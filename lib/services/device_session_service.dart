import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _kApiBase = 'https://admin.quickdash.co.in';
const _kDeviceIdPrefKey = 'device_session_device_id';

/// See DeviceSessionService._checkActiveDetailed's doc comment.
class _CheckResult {
  final bool active;
  final bool confirmed;
  const _CheckResult(this.active, this.confirmed);
}

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
  /// Stable per-device identifier, backed by the OS-level Android ID /
  /// iOS identifierForVendor rather than a random value stored in app data.
  /// SharedPreferences here is just a cache to avoid repeated plugin calls —
  /// it is NOT the source of truth, specifically because it isn't durable:
  /// (2026-07-30) root-caused a "logged in on another device" report to a
  /// user clearing app storage (which wipes SharedPreferences) and logging
  /// back in on the SAME physical phone — the old random-UUID-in-prefs
  /// approach had no way to tell that apart from a genuinely different
  /// device, since it minted a brand-new id every time prefs was empty, and
  /// the server's one-device gate correctly (by its own logic) read that as
  /// a device-switch attempt. This also independently guards against the
  /// SharedPreferences.apply() write-loss race noted below, since re-reading
  /// the platform id after a lost write returns the identical value instead
  /// of minting a new one.
  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kDeviceIdPrefKey);
    if (id == null || id.isEmpty) {
      id = await _readPlatformDeviceId();
      await prefs.setString(_kDeviceIdPrefKey, id);
      // TEMPORARY [DEVICESESSION-DEBUG] - remove once the same-device
      // auto-logout report is confirmed fixed in the field. A fresh id
      // being cached here should now consistently reproduce the same
      // platform id across storage clears / lost prefs writes - if this
      // line ever logs a DIFFERENT id for the same physical device, the
      // platform id itself isn't as stable as expected and needs revisiting.
      log('[DEVICESESSION-DEBUG] getDeviceId() cached platform id: $id (no prior id found in prefs)');
    } else {
      log('[DEVICESESSION-DEBUG] getDeviceId() read EXISTING id from prefs: $id');
    }
    return id;
  }

  // (2026-08-03) Settings.Secure.ANDROID_ID via a native platform channel,
  // NOT device_info_plus's AndroidDeviceInfo.id — that field is a direct
  // passthrough of Build.ID (see device_info_plus's Android
  // MethodCallHandlerImpl.kt), which is the OS firmware build tag, e.g.
  // "UKQ1.230924.001" — identical across every physical device running that
  // exact firmware build, not a per-device identifier at all. Confirmed on
  // a real device: two different phones on the same ROM build would have
  // collided on this value, letting the server mistake a second physical
  // device for the same one and silently defeat the whole one-device gate.
  // ANDROID_ID is scoped per app-signing-key + user + physical device — it
  // stays stable across this app's own data clears/reinstalls (same signing
  // key, verified 2026-08-03: value unchanged after a clean+re-login) but
  // genuinely differs between two different physical devices, which is what
  // this gate actually needs. device_info_plus doesn't expose ANDROID_ID in
  // this app's pinned version (11.3.0), hence the native channel below.
  static const MethodChannel _androidIdChannel =
      MethodChannel('com.quickdash.customer/android_id');

  /// Reads the OS-level device identifier. Falls back to a random UUID
  /// (the old behavior) on any platform the plugin doesn't cover or if the
  /// read fails for any reason — never let device-id resolution itself
  /// block login.
  static Future<String> _readPlatformDeviceId() async {
    try {
      if (Platform.isAndroid) {
        final id = await _androidIdChannel.invokeMethod<String>('getAndroidId');
        if (id != null && id.isNotEmpty) return 'android_$id';
      } else if (Platform.isIOS) {
        final plugin = DeviceInfoPlugin();
        final info = await plugin.iosInfo;
        final vendorId = info.identifierForVendor;
        if (vendorId != null && vendorId.isNotEmpty) return 'ios_$vendorId';
      }
    } catch (e) {
      log('[DeviceSession] platform device id read failed, falling back to random: $e');
    }
    return const Uuid().v4();
  }

  /// Must be called right after a Firebase Auth sign-in succeeds
  /// (email/password or OTP custom-token), before the account is used for
  /// anything else. On denial this signs the just-established session back
  /// out — the caller must stop and surface [DeviceSessionResult.message],
  /// not proceed to load the profile or navigate in.
  static Future<DeviceSessionResult> authorize({required String fcmToken}) async {
    // TEMPORARY [DEVICESESSION-PERF] - timing instrumentation to find out how
    // much of successful-login time this one call accounts for (it never
    // runs on a rejected login, only a successful one - see the doc comment
    // above). Remove once the login-speed investigation is done.
    final overallSw = Stopwatch()..start();
    final user = auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const DeviceSessionResult.denied('Not signed in.', null);
    }

    // A new login always starts a new session, regardless of whether the
    // PREVIOUS session's Order Details flag ever got cleared (e.g. a
    // voluntary logout, which doesn't itself go through this service) -
    // resetting here, unconditionally, before this login is even verified,
    // is what actually guarantees the "reset on new login" contract rather
    // than relying on every logout call site to remember to clear it.
    _orderVerifiedThisSession = false;
    _lastVerifiedAt = null;

    try {
      final tokenSw = Stopwatch()..start();
      final idToken = await user.getIdToken();
      log('[DEVICESESSION-PERF] getIdToken — ${tokenSw.elapsedMilliseconds}ms');

      final deviceIdSw = Stopwatch()..start();
      final deviceId = await getDeviceId();
      log('[DEVICESESSION-PERF] getDeviceId — ${deviceIdSw.elapsedMilliseconds}ms');
      // TEMPORARY [DEVICESESSION-DEBUG] - remove alongside the logging in
      // getDeviceId()/checkActive(). This is the baseline id claimed at
      // login - compare it against whatever checkActive() logs hours later
      // for the same account/device to see if it ever changes.
      log('[DEVICESESSION-DEBUG] authorize() logging in with device_id=$deviceId');

      final httpSw = Stopwatch()..start();
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
      log('[DEVICESESSION-PERF] HTTP POST device-session/authorize — '
          '${httpSw.elapsedMilliseconds}ms (status=${resp.statusCode})');

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
    } finally {
      log('[DEVICESESSION-PERF] authorize() TOTAL — ${overallSw.elapsedMilliseconds}ms');
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
  static Future<bool> checkActive() async => (await _checkActiveDetailed()).active;

  /// Same check as [checkActive], but also reports whether `active` came
  /// from a genuine server verdict (`confirmed: true`) or a fail-open
  /// default (`confirmed: false` — no signed-in user, network error,
  /// timeout, or non-200 response). [checkActive] collapses this down to
  /// just the bool for its many existing callers; [enforceActiveForOrder]
  /// needs the distinction so a network hiccup can't get cached as a real
  /// verified order for a full TTL window (2026-08-03 fix).
  static Future<_CheckResult> _checkActiveDetailed() async {
    final user = auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const _CheckResult(true, false); // nothing to invalidate — not this service's concern
    }

    final now = DateTime.now();
    if (_lastCheckAt != null && now.difference(_lastCheckAt!) < _checkCacheWindow) {
      // Reusing a cached result - only ever populated by a genuine 200
      // response below, so this is still a confirmed verdict, just cached.
      return _CheckResult(_lastCheckActive, true);
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
        return const _CheckResult(true, false); // fail open — see [authorize]
      }

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final active = body['active'] != false;
      // TEMPORARY [DEVICESESSION-DEBUG] - remove alongside the getDeviceId()
      // logging above once root-caused. Pairs the id THIS call sent with
      // the server's verdict, so a false "inactive" can be matched against
      // whether getDeviceId() just minted a fresh id a moment earlier.
      log('[DEVICESESSION-DEBUG] checkActive() sent device_id=$deviceId -> server active=$active (session_version=${body['session_version']})');
      _lastCheckAt = now;
      _lastCheckActive = active;
      return _CheckResult(active, true);
    } catch (e) {
      log('[DeviceSession] check error: $e');
      return const _CheckResult(true, false); // fail open — see [authorize]
    }
  }

  /// One-off, cache-bypassing re-check for the offline connectivity gate:
  /// called the instant connectivity returns after the device was offline.
  /// Deliberately reuses the passive check endpoint (never one that could
  /// switch device ownership) — merely reconnecting must never change
  /// session ownership, only confirm it.
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
    // Also clear the session-verified flag (see enforceActiveForOrder) -
    // without this, a stale "verified this session" latch survives past
    // the very sign-out it should have been invalidated by, and would
    // incorrectly skip a real check the next time anyone signs in on this
    // device and opens Order Details.
    _orderVerifiedThisSession = false;
    _lastVerifiedAt = null;
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

  // (2026-08-03) Deliberately NOT keyed by orderId - the user explicitly
  // asked for a session-scoped flag instead of a per-order cache. A single
  // bool: the first Order Details/gate-pass open after sign-in (or an app
  // restart, which clears this since it's in-memory only) does a real
  // check; every later open - same order, a different order, any elapsed
  // time - is skipped until the session actually ends (sign-out/
  // invalidation, see handleSessionInvalidated). No TTL, unlike
  // [checkActive]'s own blanket 20s window - "session" itself is the
  // boundary here, not a timer.
  //
  // Trade-off worth knowing: a login session that's never restarted or
  // signed out (Firebase Auth sessions can live for a long time) only ever
  // re-verifies via THIS path once, at its very first Order Details open -
  // after that, this specific fallback goes quiet for the rest of the
  // session. FCM's force_logout push and the other sensitive-action gates
  // (checkout, wallet, profile) remain the protection for anything after
  // that first check.
  static bool _orderVerifiedThisSession = false;
  // Bookkeeping only (2026-08-03, per explicit request) - not read for any
  // expiry/TTL decision, since this cache deliberately has none; kept for
  // debugging/logging visibility into when the session's one check ran.
  static DateTime? _lastVerifiedAt;

  /// Order Details/QR/gate-pass verification gate. Same convenience-guard
  /// contract as [enforceActive]: returns true if the caller may proceed;
  /// on false it has already signed the user out and navigated to the login
  /// screen.
  static Future<bool> enforceActiveForOrder(BuildContext context) async {
    if (_orderVerifiedThisSession) return true;

    final result = await _checkActiveDetailed();
    if (!result.active) {
      await handleSessionInvalidated(context);
      return false;
    }
    // Only latch the session flag on a genuinely server-confirmed result -
    // a fail-open default (offline, timeout, non-200) must not mark the
    // whole rest of the session as "verified" just because the network
    // happened to hiccup on this one call; the next Order Details open
    // should retry for real instead of trusting today's outage.
    // Availability is still preserved either way - the caller can proceed
    // regardless - only the LATCHING of that outcome is withheld.
    if (result.confirmed) {
      _orderVerifiedThisSession = true;
      _lastVerifiedAt = DateTime.now();
      log('[DeviceSession] Order Details verified for this session at $_lastVerifiedAt '
          '- no further checks via this path until sign-out/new login/app restart.');
    }
    return true;
  }
}
