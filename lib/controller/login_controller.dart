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

  @override
  void onInit() {
    // TODO: implement onInit
    super.onInit();
  }

  loginWithEmailAndPassword(BuildContext context) async {
    print("=== LOGIN FUNCTION CALLED ===");
    ShowToastDialog.showLoader("Please wait".tr);
    print("=== LOADER SHOWN ===");
    try {
      print("=== Step 1: Starting login ===");
      print("Email: ${emailEditingController.value.text.trim()}");

      final credential =
          await auth.FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailEditingController.value.text.trim(),
        password: passwordEditingController.value.text.trim(),
      );
      print("=== Step 2: Auth successful, user: ${credential.user?.uid} ===");

      if (credential.user == null) {
        ShowToastDialog.showToast("Login failed, please try again.");
        ShowToastDialog.closeLoader();
        return;
      }

      print("=== Step 3: Fetching user profile ===");
      User? userModel =
          await FireStoreUtils.getUserProfile(credential.user!.uid);
      print("=== Step 4: User profile: ${userModel != null ? 'Found' : 'Not found'} ===");

      if (userModel == null) {
        ShowToastDialog.showToast("No user profile found for this account.");
        await auth.FirebaseAuth.instance.signOut();
        ShowToastDialog.closeLoader();
        pushAndRemoveUntil(context, LoginScreen());
        return;
      }

      print("=== Step 5: User role: ${userModel.role}, active: ${userModel.active} ===");
      if (userModel.role == USER_ROLE_CUSTOMER) {
        if (userModel.active == true) {
          print("=== Step 6: User is active, updating FCM token ===");
          userModel.fcmToken = await NotificationService.getToken();
          await FireStoreUtils.updateCurrentUser(userModel);
          print("=== Step 7: Checking shipping address ===");
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
            print("=== Step 8: Navigating to ServiceListScreen ===");
            pushAndRemoveUntil(context, ServiceListScreen());
          } else {
            print("=== Step 8: Navigating to LocationPermissionScreen ===");
            pushAndRemoveUntil(context, LocationPermissionScreen());
          }
        } else {
          ShowToastDialog.showToast(
              "This user is disable please contact to administrator");
          await auth.FirebaseAuth.instance.signOut();
          ShowToastDialog.closeLoader();
          pushAndRemoveUntil(context, LoginScreen());
        }
      } else {
        print("=== Step 6: Invalid role, signing out ===");
        await auth.FirebaseAuth.instance.signOut();
        ShowToastDialog.closeLoader();
        pushAndRemoveUntil(context, LoginScreen());
      }
    } on auth.FirebaseAuthException catch (e) {
      print("=== FirebaseAuthException: ${e.code} - ${e.message} ===");
      if (e.code == 'user-not-found') {
        ShowToastDialog.showToast("No user found for that email.");
      } else if (e.code == 'wrong-password') {
        ShowToastDialog.showToast("Wrong password provided for that user.");
      } else if (e.code == 'invalid-email') {
        ShowToastDialog.showToast("Invalid Email.");
      } else {
        ShowToastDialog.showToast("${e.message}");
      }
    } catch (e) {
      print("=== Exception: $e ===");
      ShowToastDialog.showToast(e.toString());
    } finally {
      print("=== Closing loader ===");
      ShowToastDialog.closeLoader();
    }
  }
}
