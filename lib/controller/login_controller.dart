import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/notification_service.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/ui/location_permission_screen.dart';
import 'package:emartconsumer/ui/service_list_screen.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

class LoginController extends GetxController {
  Rx<TextEditingController> emailEditingController =
      TextEditingController().obs;
  Rx<TextEditingController> passwordEditingController =
      TextEditingController().obs;

  RxBool passwordVisible = true.obs;

  loginWithEmailAndPassword(BuildContext context) async {
    ShowToastDialog.showLoader("Please wait".tr);
    try {
      final credential =
          await auth.FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailEditingController.value.text.trim(),
        password: passwordEditingController.value.text.trim(),
      );

      if (credential.user == null) {
        ShowToastDialog.showToast("Login failed. Please try again.");
        ShowToastDialog.closeLoader();
        return;
      }

      User? userModel =
          await FireStoreUtils.getUserProfile(credential.user!.uid);

      if (userModel == null) {
        ShowToastDialog.showToast(
            "No account found. Please sign up to create an account.");
        await auth.FirebaseAuth.instance.signOut();
        ShowToastDialog.closeLoader();
        pushAndRemoveUntil(context, const LoginScreen());
        return;
      }

      if (userModel.role == USER_ROLE_CUSTOMER) {
        if (userModel.active == true) {
          userModel.fcmToken = await NotificationService.getToken();
          await FireStoreUtils.updateCurrentUser(userModel);
          if (userModel.shippingAddress != null &&
              userModel.shippingAddress!.isNotEmpty) {
            if (userModel.shippingAddress!
                .where((element) => element.isDefault == true)
                .isNotEmpty) {
              MyAppState.selectedPosotion = userModel.shippingAddress!
                  .where((element) => element.isDefault == true)
                  .single;
            } else {
              MyAppState.selectedPosotion = userModel.shippingAddress!.first;
            }
            pushAndRemoveUntil(context, ServiceListScreen());
          } else {
            pushAndRemoveUntil(context, LocationPermissionScreen());
          }
        } else {
          ShowToastDialog.showToast(
              "Your account is temporarily restricted. Please contact support.");
          await auth.FirebaseAuth.instance.signOut();
          ShowToastDialog.closeLoader();
          pushAndRemoveUntil(context, const LoginScreen());
        }
      } else {
        ShowToastDialog.showToast(
            "This account is not registered as a customer. Please use the correct QuickDash app.");
        await auth.FirebaseAuth.instance.signOut();
        ShowToastDialog.closeLoader();
        pushAndRemoveUntil(context, const LoginScreen());
      }
    } on auth.FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
          ShowToastDialog.showToast(
              "No account found with this email. Please sign up first.");
          break;
        case 'wrong-password':
        case 'invalid-credential':
          ShowToastDialog.showToast(
              "Incorrect email or password. Please try again.");
          break;
        case 'invalid-email':
          ShowToastDialog.showToast("Please enter a valid email address.");
          break;
        case 'too-many-requests':
          ShowToastDialog.showToast(
              "Too many failed attempts. Please try again later or reset your password.");
          break;
        case 'network-request-failed':
          ShowToastDialog.showToast(
              "Unable to connect right now. Please try again.");
          break;
        default:
          ShowToastDialog.showToast("Login failed. Please try again.");
      }
    } catch (_) {
      ShowToastDialog.showToast("Something went wrong. Please try again.");
    } finally {
      ShowToastDialog.closeLoader();
    }
  }
}
