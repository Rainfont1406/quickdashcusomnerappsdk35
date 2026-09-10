import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Global, root-level full-screen gate: if the installed app's own
/// versionName is below the admin-configured `min_supported_version` Remote
/// Config parameter, blocks the entire app behind a non-dismissible "please
/// update" page. Deliberately Remote Config, not a Firestore document - this
/// check fires on every app open, and Remote Config is served from Google's
/// own config-delivery network (a separate, free product), not billed as a
/// Firestore read the way a `Setting/appVersion` doc would be. See
/// ORDER_TYPE_NAMING_AUDIT / FIRESTORE_DOCUMENT_SIZE_AUDIT sessions for the
/// egress-cost reasoning this follows.
///
/// Same overlay-via-Stack shape as ConnectivityGate (mounted once above
/// MaterialApp's `home` via the `builder:` callback) - a pushed route would
/// create back-button/navigation-stack edge cases on an unconditional block.
/// Unlike ConnectivityGate, there's no retry/auto-close path here: once
/// blocked, the only way out is an actual app update, so the check runs once
/// at startup and never re-checks mid-session (the version can't change
/// while the app is running).
class ForceUpdateGate extends StatefulWidget {
  final Widget? child;

  const ForceUpdateGate({Key? key, required this.child}) : super(key: key);

  @override
  State<ForceUpdateGate> createState() => _ForceUpdateGateState();
}

class _ForceUpdateGateState extends State<ForceUpdateGate> {
  bool _blocked = false;
  String _message = '';
  String _storeUrl = '';

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(minutes: 1),
      ));
      await remoteConfig.fetchAndActivate();

      final minVersion = remoteConfig.getString('min_supported_version');
      if (minVersion.isEmpty) return; // not configured - fail open, never block

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      if (_compareVersions(currentVersion, minVersion) < 0) {
        if (!mounted) return;
        setState(() {
          _blocked = true;
          _message = remoteConfig.getString('force_update_message');
          _storeUrl = remoteConfig.getString('play_store_url');
        });
      }
    } catch (e) {
      // Network failure, Remote Config unreachable, etc. - fail open. A
      // force-update gate that can itself lock every user out on an
      // unrelated network blip is worse than the update-nagging it exists
      // to add; ConnectivityGate already covers genuine offline handling.
      debugPrint('[ForceUpdateGate] check failed, failing open: $e');
    }
  }

  // Numeric dot-separated comparison ("1.0.13" vs "1.0.9") - a plain string
  // compare would wrongly rank "1.10.0" below "1.9.0". Missing trailing
  // segments treated as 0 (e.g. "1.1" == "1.1.0").
  int _compareVersions(String a, String b) {
    final partsA = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final partsB = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final len = partsA.length > partsB.length ? partsA.length : partsB.length;
    for (var i = 0; i < len; i++) {
      final pa = i < partsA.length ? partsA[i] : 0;
      final pb = i < partsB.length ? partsB[i] : 0;
      if (pa != pb) return pa.compareTo(pb);
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (widget.child != null) widget.child!,
        if (_blocked) _ForceUpdateScreen(message: _message, storeUrl: _storeUrl),
      ],
    );
  }
}

class _ForceUpdateScreen extends StatelessWidget {
  final String message;
  final String storeUrl;

  const _ForceUpdateScreen({required this.message, required this.storeUrl});

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    return Material(
      color: dark ? AppThemeData.darkBgPrimary : Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppThemeData.primary500.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.system_update_rounded, size: 40, color: AppThemeData.primary500),
                ),
                const SizedBox(height: 24),
                Text(
                  'Update Required'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppThemeData.semiBold,
                    fontSize: 20,
                    color: dark ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message.isNotEmpty
                      ? message
                      : 'A new version of QuickDash is available with important fixes. Please update to continue.'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppThemeData.regular,
                    fontSize: 14,
                    color: AppThemeData.neutral400,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: storeUrl.isEmpty
                        ? null
                        : () => launchUrl(Uri.parse(storeUrl), mode: LaunchMode.externalApplication),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppThemeData.primary500,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'Update Now'.tr(),
                      style: const TextStyle(color: Colors.white, fontFamily: AppThemeData.semiBold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
