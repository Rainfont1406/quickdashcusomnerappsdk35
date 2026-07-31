import 'dart:convert';
import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────
// Trusted-backend write path for GLOBAL (not user-owned) analytics
// aggregates (2026-07-24) - bannerAnalytics/{bannerId} and
// restaurantPairings/{pairId} only. Everything else BehaviorTracker
// collects stays exactly as it was: written directly to Firestore under
// users/{uid}, which ownership-scoped rules already protect correctly.
//
// WHY THIS EXISTS: bannerAnalytics/restaurantPairings aren't owned by any
// single user, so the Firestore rule protecting them could only ever be
// "isSignedIn()" - any authenticated account, any value, direct write, no
// way to bound it further at the rules layer. Firestore rules now deny
// client writes to both collections entirely (see firestore.rules); this
// endpoint (GlobalAnalyticsController::ingestBatch on the Laravel admin
// panel backend) is the only remaining writer, gated by a real Firebase ID
// token check plus server-side delta validation.
//
// Same base URL / Bearer-token / http package conventions as
// device_session_service.dart (this app's existing template for a
// Firebase-ID-token-authenticated call to the Laravel backend) - not a new
// pattern.
//
// Deliberately NOT fail-open: unlike DeviceSessionService (where an outage
// must not block login/checkout), a failed call here just means
// BehaviorTracker leaves its queue untouched and retries on the next flush
// trigger - the existing offline-durability contract, unchanged.
class GlobalAnalyticsApi {
  GlobalAnalyticsApi._();

  static const _kApiBase = 'https://admin.quickdash.co.in';

  /// Sends one pre-aggregated batch of banner/restaurant-pairing deltas.
  /// Returns true only on a confirmed 2xx - any other outcome (network
  /// error, timeout, non-2xx, not signed in) returns false so the caller
  /// knows to leave its local queue intact for the next retry.
  static Future<bool> sendBatch({
    required List<Map<String, dynamic>> banners,
    required List<Map<String, dynamic>> restaurantPairs,
  }) async {
    if (banners.isEmpty && restaurantPairs.isEmpty) return true; // nothing to send is a trivial success

    try {
      final user = auth.FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      final idToken = await user.getIdToken();

      final resp = await http
          .post(
            Uri.parse('$_kApiBase/api/analytics/global-batch'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({
              'banners': banners,
              'restaurantPairs': restaurantPairs,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode != 200) {
        log('[GlobalAnalyticsApi] sendBatch failed: HTTP ${resp.statusCode} ${resp.body}');
        return false;
      }
      return true;
    } catch (e) {
      log('[GlobalAnalyticsApi] sendBatch error: $e');
      return false;
    }
  }
}
