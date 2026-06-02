import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/msg91_service.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/ui/auth_screen/signup_screen.dart';
import 'package:emartconsumer/ui/auth_screen/otp_screen.dart';
import 'package:emartconsumer/ui/location_permission_screen.dart';
import 'package:emartconsumer/ui/privacy_policy/privacy_policy.dart';
import 'package:emartconsumer/ui/service_list_screen.dart';
import 'package:emartconsumer/ui/termsAndCondition/terms_and_codition.dart';
import 'package:emartconsumer/utils/country_phone_length.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

class PhoneNumberScreen extends StatefulWidget {
  /// When true, this screen was reached from the Sign-Up flow.
  final bool isSignup;

  const PhoneNumberScreen({super.key, this.isSignup = false});

  @override
  State<PhoneNumberScreen> createState() => _PhoneNumberScreenState();
}

class _PhoneNumberScreenState extends State<PhoneNumberScreen> {
  final TextEditingController _phoneController = TextEditingController();
  String _countryCode = '+91';
  int _phoneMaxLength = 10;
  bool _isSending = false;

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

    // ── Firestore: check whether this number has an existing account ───
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
      ShowToastDialog.showToast(
          'Unable to connect right now. Please try again.');
      return;
    }

    if (!mounted) {
      ShowToastDialog.closeLoader();
      return;
    }

    // Gate: signup → block if number already registered
    if (widget.isSignup && !isNewUser) {
      ShowToastDialog.closeLoader();
      if (mounted) setState(() => _isSending = false);
      ShowToastDialog.showToast(
          'This number is already registered. Please log in instead.');
      return;
    }

    // Gate: login → block if number not found
    if (!widget.isSignup && isNewUser) {
      ShowToastDialog.closeLoader();
      if (mounted) setState(() => _isSending = false);
      ShowToastDialog.showToast(
          'No account found with this number. Please sign up first.');
      return;
    }

    ShowToastDialog.closeLoader();

    // ── Send OTP via MSG91 ─────────────────────────────────────────────
    ShowToastDialog.showLoader('Sending verification code...');
    final result = await Msg91Service.sendOtp(
        _countryCode, _phoneController.text.trim());
    ShowToastDialog.closeLoader();

    if (!mounted) return;

    if (!result.success) {
      if (mounted) setState(() => _isSending = false);
      ShowToastDialog.showToast(result.message);
      return;
    }

    ShowToastDialog.showToast(result.message);
    if (mounted) setState(() => _isSending = false);

    push(
      context,
      OtpScreen(
        countryCode: _countryCode,
        phoneNumber: _phoneController.text.trim(),
        isSignup: widget.isSignup,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    final isSignup = widget.isSignup;

    return Scaffold(
      backgroundColor: dark ? AppThemeData.surfaceDark : const Color(0xFFF5F6FA),
      body: Column(
        children: [
          // ── Branded gradient header ────────────────────────────────────
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
                        if (!isSignup)
                          GestureDetector(
                            onTap: () async {
                              final permission =
                                  await Geolocator.checkPermission();
                              if (!mounted) return;
                              if (permission == LocationPermission.always ||
                                  permission == LocationPermission.whileInUse) {
                                if (MyAppState.selectedPosotion.location ==
                                    null) {
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
                          )
                        else
                          const SizedBox(),
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
                      isSignup
                          ? 'Create Account'.tr()
                          : 'Enter Mobile Number'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontFamily: AppThemeData.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isSignup
                          ? "Enter your number to verify your identity and get started."
                              .tr()
                          : "We'll send you a one-time verification code.".tr(),
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

          // ── Form area ─────────────────────────────────────────────────
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
                        color:
                            dark ? AppThemeData.grey200 : AppThemeData.grey700,
                        fontSize: 14,
                        fontFamily: AppThemeData.medium,
                      ),
                    ),
                    const SizedBox(height: 8),
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
                              keyboardType:
                                  const TextInputType.numberWithOptions(
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
                        color:
                            dark ? AppThemeData.grey500 : AppThemeData.grey400,
                        fontSize: 12,
                        fontFamily: AppThemeData.regular,
                      ),
                      textAlign: TextAlign.right,
                    ),
                    const SizedBox(height: 24),

                    // Send OTP button
                    GestureDetector(
                      onTap: _isSending ? null : _sendCode,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _isSending
                                ? [
                                    AppThemeData.primary500
                                        .withValues(alpha: 0.6),
                                    AppThemeData.primary400
                                        .withValues(alpha: 0.6),
                                  ]
                                : [
                                    AppThemeData.primary500,
                                    AppThemeData.primary400,
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: _isSending
                              ? []
                              : [
                                  BoxShadow(
                                    color: AppThemeData.primary500
                                        .withValues(alpha: 0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                        ),
                        child: Center(
                          child: _isSending
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
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
                              isSignup
                                  ? 'Sign up with Email instead'.tr()
                                  : 'Continue with Email'.tr(),
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
                          color: dark
                              ? AppThemeData.grey400
                              : AppThemeData.grey500,
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
                              ..onTap = () =>
                                  push(context, const PrivacyPolicyScreen()),
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

          // ── Bottom account-toggle link ────────────────────────────────
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
                      text: isSignup
                          ? 'Already have an account?  '.tr()
                          : "Don't have an account?  ".tr(),
                      style: TextStyle(
                        color: dark
                            ? AppThemeData.grey400
                            : AppThemeData.grey500,
                        fontFamily: AppThemeData.regular,
                        fontSize: 14,
                      ),
                    ),
                    TextSpan(
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          if (isSignup) {
                            pushAndRemoveUntil(context, const LoginScreen());
                          } else {
                            pushAndRemoveUntil(context, const SignupScreen());
                          }
                        },
                      text: isSignup ? 'Log in'.tr() : 'Sign up'.tr(),
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
