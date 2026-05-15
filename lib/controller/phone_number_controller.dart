import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/ui/auth_screen/otp_screen.dart';
import 'package:emartconsumer/utils/country_phone_length.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PhoneNumberController extends GetxController {
  final phoneNUmberEditingController = TextEditingController().obs;
  final countryCodeEditingController = TextEditingController().obs;

  // Max length for phone number based on selected country
  final RxInt phoneMaxLength = 10.obs;

  @override
  void onInit() {
    super.onInit();
    countryCodeEditingController.value.text =
        '+91'; // Set India dialing code as default
    _updatePhoneMaxLength();
  }

  /// Update the max phone length when country code changes
  void onCountryCodeChanged(String dialCode) {
    countryCodeEditingController.value.text = dialCode;
    _updatePhoneMaxLength();
  }

  /// Update phone max length based on current country code
  void _updatePhoneMaxLength() {
    phoneMaxLength.value =
        CountryPhoneLength.getMaxLength(countryCodeEditingController.value.text);
  }

  /// Validate phone number length based on country code
  bool isPhoneNumberValid() {
    return CountryPhoneLength.isValidLength(
      countryCodeEditingController.value.text,
      phoneNUmberEditingController.value.text,
    );
  }

  /// Get validation error message
  String getValidationErrorMessage() {
    return CountryPhoneLength.getValidationMessage(
      countryCodeEditingController.value.text,
    );
  }

  sendCode(BuildContext context) async {
    // Validate phone number length before sending OTP
    if (!isPhoneNumberValid()) {
      ShowToastDialog.showToast(getValidationErrorMessage());
      return;
    }

    ShowToastDialog.showLoader("Please wait".tr);
    await FirebaseAuth.instance
        .verifyPhoneNumber(
            phoneNumber: countryCodeEditingController.value.text +
                phoneNUmberEditingController.value.text,
            verificationCompleted: (PhoneAuthCredential credential) {},
            verificationFailed: (FirebaseAuthException e) {
              debugPrint("FirebaseAuthException--->${e.message}");
              ShowToastDialog.closeLoader();
              if (e.code == 'invalid-phone-number') {
                ShowToastDialog.showToast("invalid_phone_number".tr);
              } else {
                ShowToastDialog.showToast(e.message);
              }
            },
            codeSent: (String verificationId, int? resendToken) {
              ShowToastDialog.closeLoader();
              push(
                  context,
                  OtpScreen(
                    countryCode: countryCodeEditingController.value.text,
                    phoneNumber: phoneNUmberEditingController.value.text,
                    verificationId: verificationId,
                  ));
            },
            codeAutoRetrievalTimeout: (String verificationId) {})
        .catchError((error) {
      debugPrint("catchError--->$error");
      ShowToastDialog.closeLoader();
      ShowToastDialog.showToast("multiple_time_request".tr);
    });
  }
}
