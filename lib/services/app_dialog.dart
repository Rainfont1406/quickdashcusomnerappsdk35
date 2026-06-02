import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';

enum AppDialogType { error, warning, success, info, confirm }

/// Centralised dialog service for QuickDash.
///
/// showError   — red title, error icon, single OK/Retry button
/// showWarning — orange title, warning icon, single OK button
/// showSuccess — green title, check icon, single Continue button
/// showInfo    — purple title, info icon, single OK button
/// showConfirm — purple/red title, confirm + cancel buttons, returns bool
class AppDialog {
  AppDialog._();

  // ── Public API ──────────────────────────────────────────────────────

  static Future<void> showError(
    BuildContext context, {
    String title = 'Something Went Wrong',
    required String message,
    String buttonLabel = 'OK',
    VoidCallback? onTap,
  }) =>
      _showSingle(context,
          type: AppDialogType.error,
          title: title,
          message: message,
          primaryLabel: buttonLabel,
          onPrimary: onTap);

  static Future<void> showWarning(
    BuildContext context, {
    String title = 'Please Check',
    required String message,
    String buttonLabel = 'OK',
    VoidCallback? onTap,
  }) =>
      _showSingle(context,
          type: AppDialogType.warning,
          title: title,
          message: message,
          primaryLabel: buttonLabel,
          onPrimary: onTap);

  static Future<void> showSuccess(
    BuildContext context, {
    String title = 'Success',
    required String message,
    String buttonLabel = 'Continue',
    VoidCallback? onTap,
  }) =>
      _showSingle(context,
          type: AppDialogType.success,
          title: title,
          message: message,
          primaryLabel: buttonLabel,
          onPrimary: onTap);

  static Future<void> showInfo(
    BuildContext context, {
    String title = 'Information',
    required String message,
    String buttonLabel = 'OK',
    VoidCallback? onTap,
  }) =>
      _showSingle(context,
          type: AppDialogType.info,
          title: title,
          message: message,
          primaryLabel: buttonLabel,
          onPrimary: onTap);

  /// Returns `true` if the user confirmed, `false` if they cancelled.
  static Future<bool> showConfirm(
    BuildContext context, {
    String title = 'Are You Sure?',
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AppDialogWidget(
        type: AppDialogType.confirm,
        title: title,
        message: message,
        primaryLabel: confirmLabel,
        secondaryLabel: cancelLabel,
        destructive: destructive,
      ),
    );
    return result ?? false;
  }

  // ── Internal ────────────────────────────────────────────────────────

  static Future<void> _showSingle(
    BuildContext context, {
    required AppDialogType type,
    required String title,
    required String message,
    required String primaryLabel,
    VoidCallback? onPrimary,
  }) =>
      showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => AppDialogWidget(
          type: type,
          title: title,
          message: message,
          primaryLabel: primaryLabel,
          onPrimary: onPrimary,
        ),
      );
}

// ── Public widget (also used by ShowDialogToDismiss in helper.dart) ───────

class AppDialogWidget extends StatelessWidget {
  final AppDialogType type;
  final String title;
  final String message;
  final String primaryLabel;
  final String? secondaryLabel;
  final VoidCallback? onPrimary;
  final bool destructive;

  const AppDialogWidget({
    super.key,
    required this.type,
    required this.title,
    required this.message,
    required this.primaryLabel,
    this.secondaryLabel,
    this.onPrimary,
    this.destructive = false,
  });

  Color _accent() {
    switch (type) {
      case AppDialogType.error:
      case AppDialogType.warning:
        return AppThemeData.error500;
      case AppDialogType.success:
        return AppThemeData.success400;
      case AppDialogType.confirm:
        return destructive ? AppThemeData.error500 : AppThemeData.primary500;
      case AppDialogType.info:
        return AppThemeData.primary500;
    }
  }

  IconData _icon() {
    switch (type) {
      case AppDialogType.error:
        return Icons.error_outline_rounded;
      case AppDialogType.warning:
        return Icons.warning_amber_rounded;
      case AppDialogType.success:
        return Icons.check_circle_outline_rounded;
      case AppDialogType.confirm:
        return destructive
            ? Icons.delete_outline_rounded
            : Icons.help_outline_rounded;
      case AppDialogType.info:
        return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    final accent = _accent();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        decoration: BoxDecoration(
          color: dark ? AppThemeData.grey800 : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon badge
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(_icon(), color: accent, size: 30),
            ),
            const SizedBox(height: 16),
            // Title
            Text(
              title.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: accent,
                fontSize: 17,
                fontFamily: AppThemeData.bold,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            // Message
            Text(
              message.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: dark ? AppThemeData.grey300 : AppThemeData.grey600,
                fontSize: 14,
                fontFamily: AppThemeData.regular,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 24),
            // Buttons
            if (secondaryLabel != null) ...[
              _PrimaryBtn(label: primaryLabel, color: accent, onTap: () {
                Navigator.of(context).pop(true);
                onPrimary?.call();
              }),
              const SizedBox(height: 10),
              _CancelBtn(label: secondaryLabel!, dark: dark,
                  onTap: () => Navigator.of(context).pop(false)),
            ] else
              _PrimaryBtn(label: primaryLabel, color: accent, onTap: () {
                Navigator.of(context).pop();
                onPrimary?.call();
              }),
          ],
        ),
      ),
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _PrimaryBtn({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48,
          width: double.infinity,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            label.tr,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontFamily: AppThemeData.semiBold,
            ),
          ),
        ),
      );
}

class _CancelBtn extends StatelessWidget {
  final String label;
  final bool dark;
  final VoidCallback onTap;
  const _CancelBtn({required this.label, required this.dark, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: dark ? AppThemeData.grey600 : AppThemeData.grey300,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label.tr,
            style: TextStyle(
              color: dark ? AppThemeData.grey300 : AppThemeData.grey600,
              fontSize: 15,
              fontFamily: AppThemeData.medium,
            ),
          ),
        ),
      );
}
