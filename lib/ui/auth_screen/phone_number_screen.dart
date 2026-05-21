import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/ui/auth_screen/otp_screen.dart';
import 'package:emartconsumer/ui/location_permission_screen.dart';
import 'package:emartconsumer/ui/privacy_policy/privacy_policy.dart';
import 'package:emartconsumer/ui/service_list_screen.dart';
import 'package:emartconsumer/ui/termsAndCondition/terms_and_codition.dart';
import 'package:emartconsumer/utils/country_phone_length.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

class PhoneNumberScreen extends StatefulWidget {
  const PhoneNumberScreen({super.key});

  @override
  State<PhoneNumberScreen> createState() => _PhoneNumberScreenState();
}

class _PhoneNumberScreenState extends State<PhoneNumberScreen> {
  final TextEditingController _phoneController = TextEditingController();
  String _countryCode = '+91';
  int _phoneMaxLength = 10;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _onCountryCodeChanged(String dialCode) {
    setState(() {
      _countryCode = dialCode;
      _phoneMaxLength = CountryPhoneLength.getMaxLength(dialCode);
    });
  }

  bool _isPhoneNumberValid() =>
      CountryPhoneLength.isValidLength(_countryCode, _phoneController.text);

  String _getValidationErrorMessage() =>
      CountryPhoneLength.getValidationMessage(_countryCode);

  bool _isSending = false;

  Future<void> _sendCode() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_phoneController.text.isEmpty) {
      ShowToastDialog.showToast('Please enter your mobile number.'.tr());
      return;
    }
    if (!_isPhoneNumberValid()) {
      ShowToastDialog.showToast(_getValidationErrorMessage());
      return;
    }
    if (_isSending) return;
    if (mounted) setState(() => _isSending = true);

    // Step 1: Check whether this phone number already has an account
    ShowToastDialog.showLoader('Checking your account...');
    bool isNewUser;
    try {
      final snap = await FirebaseFirestore.instance
          .collection(USERS)
          .where('phoneNumber', isEqualTo: _phoneController.text.trim())
          .where('countryCode', isEqualTo: _countryCode)
          .where('role', isEqualTo: USER_ROLE_CUSTOMER)
          .get();
      isNewUser = snap.docs.isEmpty;
    } catch (_) {
      ShowToastDialog.closeLoader();
      if (mounted) setState(() => _isSending = false);
      ShowToastDialog.showToast('Unable to connect right now. Please try again.');
      return;
    }
    if (!mounted) {
      ShowToastDialog.closeLoader();
      setState(() => _isSending = false);
      return;
    }
    ShowToastDialog.closeLoader();
    if (!isNewUser) {
      ShowToastDialog.showToast("Welcome back! Let's get you in.");
    } else {
      ShowToastDialog.showToast("Looks like you're new here. Let's create your account.");
    }

    // Step 2: Send OTP
    ShowToastDialog.showLoader('Sending verification code...');
    try {
      await auth.FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: _countryCode + _phoneController.text,
        verificationCompleted: (_) {
          ShowToastDialog.closeLoader();
        },
        verificationFailed: (auth.FirebaseAuthException e) {
          ShowToastDialog.closeLoader();
          if (mounted) setState(() => _isSending = false);
          switch (e.code) {
            case 'invalid-phone-number':
              ShowToastDialog.showToast(
                  'Invalid phone number. Please check and try again.');
              break;
            case 'too-many-requests':
              ShowToastDialog.showToast(
                  'Too many attempts. Please try again in a few minutes.');
              break;
            case 'network-request-failed':
              ShowToastDialog.showToast(
                  'Unable to connect right now. Please try again.');
              break;
            default:
              ShowToastDialog.showToast(
                  e.message ?? 'Failed to send OTP. Please try again.');
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          ShowToastDialog.closeLoader();
          ShowToastDialog.showToast('Verification code sent successfully.');
          if (mounted) setState(() => _isSending = false);
          if (!mounted) return;
          push(
            context,
            OtpScreen(
              countryCode: _countryCode,
              phoneNumber: _phoneController.text,
              verificationId: verificationId,
            ),
          );
        },
        codeAutoRetrievalTimeout: (_) {
          ShowToastDialog.closeLoader();
          if (mounted) setState(() => _isSending = false);
        },
      );
    } catch (_) {
      ShowToastDialog.closeLoader();
      if (mounted) setState(() => _isSending = false);
      ShowToastDialog.showToast(
          'Too many attempts. Please try again in a few minutes.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    return Scaffold(
      backgroundColor: dark ? AppThemeData.surfaceDark : const Color(0xFFF5F6FA),
      body: Column(
        children: [
          // Branded header
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppThemeData.primary500, AppThemeData.primary400],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () async {
                            final permission =
                                await Geolocator.checkPermission();
                            if (!mounted) return;
                            if (permission == LocationPermission.always ||
                                permission == LocationPermission.whileInUse) {
                              if (MyAppState.selectedPosotion.location == null) {
                                pushAndRemoveUntil(
                                    context, LocationPermissionScreen());
                              } else {
                                pushAndRemoveUntil(
                                    context, ServiceListScreen());
                              }
                            } else {
                              pushAndRemoveUntil(
                                  context, LocationPermissionScreen());
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Skip'.tr(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontFamily: AppThemeData.medium,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              'Q',
                              style: TextStyle(
                                fontSize: 26,
                                fontFamily: AppThemeData.bold,
                                color: AppThemeData.primary500,
                                height: 1.0,
                                letterSpacing: -1.0,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'QuickDash',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontFamily: AppThemeData.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Enter Mobile Number'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontFamily: AppThemeData.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "We'll send you a one-time verification code".tr(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                        fontFamily: AppThemeData.regular,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Form area
          Expanded(
            child: GestureDetector(
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Mobile Number'.tr(),
                    style: TextStyle(
                      color: dark ? AppThemeData.grey200 : AppThemeData.grey700,
                      fontSize: 14,
                      fontFamily: AppThemeData.medium,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Phone number input with country picker
                  Container(
                    decoration: BoxDecoration(
                      color: dark ? AppThemeData.grey800 : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: dark
                            ? AppThemeData.grey700
                            : AppThemeData.grey200,
                      ),
                    ),
                    child: Row(
                      children: [
                        CountryCodePicker(
                          onChanged: (value) =>
                              _onCountryCodeChanged(value.dialCode.toString()),
                          initialSelection: 'IN',
                          favorite: const ['+91'],
                          showCountryOnly: false,
                          showOnlyCountryWhenClosed: false,
                          alignLeft: false,
                          textStyle: TextStyle(
                            fontSize: 14,
                            color: dark
                                ? AppThemeData.grey50
                                : AppThemeData.grey900,
                            fontFamily: AppThemeData.medium,
                          ),
                          dialogTextStyle: TextStyle(
                            color: dark
                                ? AppThemeData.grey50
                                : AppThemeData.grey900,
                            fontFamily: AppThemeData.medium,
                          ),
                          dialogBackgroundColor: dark
                              ? AppThemeData.grey800
                              : AppThemeData.grey100,
                          searchStyle: TextStyle(
                            color: dark
                                ? AppThemeData.grey50
                                : AppThemeData.grey900,
                            fontFamily: AppThemeData.medium,
                          ),
                          flagWidth: 24,
                          padding: const EdgeInsets.only(left: 8),
                        ),
                        Container(
                          width: 1,
                          height: 28,
                          color: dark
                              ? AppThemeData.grey700
                              : AppThemeData.grey200,
                        ),
                        Expanded(
                          child: TextField(
                            controller: _phoneController,
                            keyboardType: const TextInputType.numberWithOptions(
                                signed: true, decimal: true),
                            textInputAction: TextInputAction.done,
                            maxLength: _phoneMaxLength,
                            style: TextStyle(
                              color: dark
                                  ? AppThemeData.grey50
                                  : AppThemeData.grey900,
                              fontFamily: AppThemeData.medium,
                              fontSize: 14,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(_phoneMaxLength),
                            ],
                            decoration: InputDecoration(
                              hintText: 'Enter phone number'.tr(),
                              hintStyle: TextStyle(
                                color: dark
                                    ? AppThemeData.grey600
                                    : AppThemeData.grey400,
                                fontSize: 14,
                                fontFamily: AppThemeData.regular,
                              ),
                              border: InputBorder.none,
                              counterText: '',
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Max $_phoneMaxLength digits',
                    style: TextStyle(
                      color: dark ? AppThemeData.grey500 : AppThemeData.grey400,
                      fontSize: 12,
                      fontFamily: AppThemeData.regular,
                    ),
                    textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 24),

                  // Send OTP button
                  GestureDetector(
                    onTap: _sendCode,
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            AppThemeData.primary500,
                            AppThemeData.primary400,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppThemeData.primary500.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          'Send OTP'.tr(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontFamily: AppThemeData.semiBold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // OR divider
                  Row(
                    children: [
                      Expanded(
                        child: Divider(
                          color: dark
                              ? AppThemeData.grey700
                              : AppThemeData.grey200,
                          thickness: 1,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'or'.tr(),
                          style: TextStyle(
                            color: dark
                                ? AppThemeData.grey500
                                : AppThemeData.grey400,
                            fontSize: 13,
                            fontFamily: AppThemeData.medium,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Divider(
                          color: dark
                              ? AppThemeData.grey700
                              : AppThemeData.grey200,
                          thickness: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // Continue with Email button
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppThemeData.primary500,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.email_outlined,
                            color: AppThemeData.primary500,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Continue with Email'.tr(),
                            style: const TextStyle(
                              color: AppThemeData.primary500,
                              fontSize: 15,
                              fontFamily: AppThemeData.semiBold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Terms and conditions
                  Text.rich(
                    TextSpan(
                      text: 'By continuing, you agree to our '.tr(),
                      style: TextStyle(
                        color:
                            dark ? AppThemeData.grey400 : AppThemeData.grey500,
                        fontSize: 12,
                        fontFamily: AppThemeData.regular,
                      ),
                      children: [
                        TextSpan(
                          text: 'Terms & Conditions'.tr(),
                          style: const TextStyle(
                            color: AppThemeData.primary500,
                            decoration: TextDecoration.underline,
                            decorationColor: AppThemeData.primary500,
                            fontFamily: AppThemeData.medium,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap =
                                () => push(context, const TermsAndCondition()),
                        ),
                        TextSpan(
                          text: ' and '.tr(),
                          style: TextStyle(
                            color: dark
                                ? AppThemeData.grey400
                                : AppThemeData.grey500,
                          ),
                        ),
                        TextSpan(
                          text: 'Privacy Policy'.tr(),
                          style: const TextStyle(
                            color: AppThemeData.primary500,
                            decoration: TextDecoration.underline,
                            decorationColor: AppThemeData.primary500,
                            fontFamily: AppThemeData.medium,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap =
                                () => push(context, const PrivacyPolicyScreen()),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            ),
          ),

          // Bottom sign up link
          Padding(
            padding: EdgeInsets.only(
              bottom: Platform.isAndroid ? 16 : 32,
              top: 12,
            ),
            child: Center(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: "Don't have an account?  ".tr(),
                      style: TextStyle(
                        color:
                            dark ? AppThemeData.grey400 : AppThemeData.grey500,
                        fontFamily: AppThemeData.regular,
                        fontSize: 14,
                      ),
                    ),
                    TextSpan(
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => pushAndRemoveUntil(context, const LoginScreen(startOnSignup: true)),
                      text: 'Sign up'.tr(),
                      style: const TextStyle(
                        color: AppThemeData.primary500,
                        fontFamily: AppThemeData.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
