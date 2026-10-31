import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/ui/auth_screen/email_code_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ForgotPasswordController extends GetxController {
  Rx<TextEditingController> emailEditingController = TextEditingController().obs;

  Future<bool> forgotPassword(BuildContext context) async {
    final email = emailEditingController.value.text.trim();
    if (email.isEmpty) {
      ShowToastDialog.showToast('Please enter your email address.'.tr);
      return false;
    }
    // Basic email format check
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    if (!emailRegex.hasMatch(email)) {
      ShowToastDialog.showToast('Please enter a valid email address.'.tr);
      return false;
    }
    try {
      ShowToastDialog.showLoader("Please wait".tr);
      // 2026-10-30: a customer with its OWN password is reset with an emailed
      // code; everyone else keeps Firebase's reset email.
      final init = await FireStoreUtils.requestRoleCode(email, 'reset');
      if (init is RoleAuthError) {
        ShowToastDialog.showToast(init.message);
        return false;
      }
      if ((init as Map)['method'] == 'code') {
        ShowToastDialog.closeLoader();
        String? err;
        while (true) {
          if (!context.mounted) return false;
          final entered = await showEmailCodeDialog(
            context: context,
            title: 'Reset your password'.tr,
            message: '${'We emailed a code to'.tr} ${init['sent_to']}. ${'Enter it and choose a new password.'.tr}',
            askNewPassword: true,
            errorText: err,
            onResend: () async {
              final again = await FireStoreUtils.requestRoleCode(email, 'reset');
              return again is RoleAuthError ? again.message : null;
            },
          );
          if (entered == null) return false;
          ShowToastDialog.showLoader("Please wait".tr);
          err = await FireStoreUtils.resetRolePassword(email, entered.code, entered.newPassword!);
          ShowToastDialog.closeLoader();
          if (err == null) break;
        }
        ShowToastDialog.showToast('Password updated. You can log in now.'.tr);
        return true;
      }
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      ShowToastDialog.showToast(
          'A password reset link has been sent to $email. Please check your inbox.');
      return true;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
          ShowToastDialog.showToast(
              'No account found with this email address.');
          break;
        case 'invalid-email':
          ShowToastDialog.showToast('Please enter a valid email address.');
          break;
        case 'too-many-requests':
          ShowToastDialog.showToast(
              'Too many requests. Please wait a moment and try again.');
          break;
        case 'network-request-failed':
          ShowToastDialog.showToast(
              'Network error. Please check your internet connection.');
          break;
        default:
          ShowToastDialog.showToast(
              e.message ?? 'Failed to send reset link. Please try again.');
      }
      return false;
    } catch (e) {
      debugPrint('ForgotPassword unexpected error: ${e.runtimeType} -> $e');
      ShowToastDialog.showToast('Something went wrong. Please try again.');
      return false;
    } finally {
      ShowToastDialog.closeLoader();
    }
  }
}
