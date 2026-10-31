import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// What the user entered in [showEmailCodeDialog].
class EmailCodeResult {
  final String code;
  final String? newPassword;
  const EmailCodeResult(this.code, {this.newPassword});
}

/// Asks for the 6-digit code the server emailed (2026-10-30), and optionally a
/// new password (password reset). Returns null when cancelled. [onResend]
/// asks the server for a fresh code and returns an error message, or null when
/// a new code was sent.
Future<EmailCodeResult?> showEmailCodeDialog({
  required BuildContext context,
  required String title,
  required String message,
  bool askNewPassword = false,
  String? errorText,
  Future<String?> Function()? onResend,
}) {
  // The app runs on a plain MaterialApp (not GetMaterialApp), so Get.dialog
  // has no navigator to attach to and shows nothing.
  return showDialog<EmailCodeResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _EmailCodeDialog(
      title: title,
      message: message,
      askNewPassword: askNewPassword,
      errorText: errorText,
      onResend: onResend,
    ),
  );
}

class _EmailCodeDialog extends StatefulWidget {
  final String title;
  final String message;
  final bool askNewPassword;
  final String? errorText;
  final Future<String?> Function()? onResend;

  const _EmailCodeDialog({
    required this.title,
    required this.message,
    required this.askNewPassword,
    this.errorText,
    this.onResend,
  });

  @override
  State<_EmailCodeDialog> createState() => _EmailCodeDialogState();
}

class _EmailCodeDialogState extends State<_EmailCodeDialog> {
  final _codeCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String? _error;
  String? _info;
  bool _resending = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _error = widget.errorText;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _codeCtrl.text.trim();
    if (code.length < 6) {
      setState(() => _error = 'Enter the 6-digit code from the email.'.tr);
      return;
    }
    if (widget.askNewPassword && _passCtrl.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.'.tr);
      return;
    }
    Navigator.of(context).pop(EmailCodeResult(code,
        newPassword: widget.askNewPassword ? _passCtrl.text : null));
  }

  Future<void> _resend() async {
    if (_resending || widget.onResend == null) return;
    setState(() {
      _resending = true;
      _error = null;
      _info = null;
    });
    final err = await widget.onResend!();
    if (!mounted) return;
    setState(() {
      _resending = false;
      if (err == null) {
        _info = 'A new code was sent.'.tr;
      } else {
        _error = err;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message),
            const SizedBox(height: 14),
            TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Verification code'.tr,
                counterText: '',
                border: const OutlineInputBorder(),
              ),
            ),
            if (widget.askNewPassword) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'New password'.tr,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            if (_info != null) ...[
              const SizedBox(height: 10),
              Text(_info!, style: const TextStyle(color: Colors.green, fontSize: 12)),
            ],
            if (widget.onResend != null)
              TextButton(
                onPressed: _resending ? null : _resend,
                child: Text(_resending ? 'Sending…'.tr : 'Resend code'.tr),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel'.tr),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(widget.askNewPassword ? 'Reset password'.tr : 'Verify'.tr),
        ),
      ],
    );
  }
}
