import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class InstalledUpiApp {
  final String packageName;
  final String appName;
  final Uint8List? icon;

  InstalledUpiApp({required this.packageName, required this.appName, this.icon});
}

// Wraps MainActivity.kt's native UPI-app enumeration (2026-08-31) so
// PaymentScreen can show the customer's actually-installed UPI apps with
// their own real name/icon (Google Pay, PhonePe, Paytm, WhatsApp, Amazon
// Pay, whatever else resolves a upi://pay intent on THIS device), instead
// of a fixed guess list.
class UpiAppsService {
  static const MethodChannel _channel = MethodChannel('com.quickdash.customer/upi_apps');

  // Android-only; returns an empty list on iOS/web (Cards + the generic
  // "Other UPI Apps" fallback still work there) or if the platform call
  // fails for any reason - never throws.
  static Future<List<InstalledUpiApp>> getInstalledApps() async {
    if (kIsWeb || !Platform.isAndroid) return [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getInstalledUpiApps');
      if (raw == null) return [];
      return raw.map((entry) {
        final map = Map<String, dynamic>.from(entry as Map);
        return InstalledUpiApp(
          packageName: map['packageName'] as String,
          appName: map['appName'] as String,
          icon: map['icon'] as Uint8List?,
        );
      }).toList();
    } catch (e) {
      debugPrint('[UpiAppsService] getInstalledApps failed: $e');
      return [];
    }
  }

  // Opens the given upi://pay link in ONE specific app (native
  // Intent.setPackage), instead of url_launcher's plain ACTION_VIEW which -
  // when more than one UPI app is installed - lets Android show its own
  // chooser regardless of which app tile the customer actually tapped.
  // Returns false (never throws) if that package can no longer handle the
  // intent (uninstalled since the list was fetched, non-Android, etc.) so
  // the caller can fall back to the generic launcher.
  static Future<bool> launchForPackage(String intentUrl, String packageName) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'launchUpiApp',
        {'uri': intentUrl, 'packageName': packageName},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('[UpiAppsService] launchForPackage failed: $e');
      return false;
    }
  }
}
