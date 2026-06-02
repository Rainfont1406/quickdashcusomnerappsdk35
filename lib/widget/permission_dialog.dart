import 'package:emartconsumer/services/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// Shown when location permission has been permanently denied.
/// Uses the unified AppDialogWidget so styling is fully consistent.
class PermissionDialog extends StatelessWidget {
  const PermissionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AppDialogWidget(
      type: AppDialogType.error,
      title: 'Location Permission Denied',
      message:
          'Location access was permanently denied. Please enable it in your device settings to find nearby restaurants and get accurate delivery.',
      primaryLabel: 'Open Settings',
      secondaryLabel: 'Not Now',
      onPrimary: () async {
        await Geolocator.openAppSettings();
      },
    );
  }
}
