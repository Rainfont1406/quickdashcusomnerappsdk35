import 'package:emartconsumer/utils/country_phone_length.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Legacy controller — kept for compatibility but no longer used by phone auth screens.
/// Phone auth is now handled via MSG91 directly in PhoneNumberScreen.
class PhoneNumberController extends GetxController {
  final phoneNUmberEditingController = TextEditingController().obs;
  final countryCodeEditingController = TextEditingController().obs;

  final RxInt phoneMaxLength = 10.obs;

  @override
  void onInit() {
    super.onInit();
    countryCodeEditingController.value.text = '+91';
    _updatePhoneMaxLength();
  }

  void onCountryCodeChanged(String dialCode) {
    countryCodeEditingController.value.text = dialCode;
    _updatePhoneMaxLength();
  }

  void _updatePhoneMaxLength() {
    phoneMaxLength.value =
        CountryPhoneLength.getMaxLength(countryCodeEditingController.value.text);
  }

  bool isPhoneNumberValid() {
    return CountryPhoneLength.isValidLength(
      countryCodeEditingController.value.text,
      phoneNUmberEditingController.value.text,
    );
  }

  String getValidationErrorMessage() {
    return CountryPhoneLength.getValidationMessage(
      countryCodeEditingController.value.text,
    );
  }
}
