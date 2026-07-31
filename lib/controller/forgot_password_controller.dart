import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ForgotPasswordController extends GetxController {
  Rx<TextEditingController> emailEditingController = TextEditingController().obs;

  Future<bool> forgotPassword() async {
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
