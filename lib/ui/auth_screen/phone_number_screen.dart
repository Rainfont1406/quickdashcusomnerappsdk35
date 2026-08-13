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
import 'package:emartconsumer/ui/auth_screen/auth_widgets.dart';
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
  /// Pre-fill values passed from a parent screen (e.g. LoginScreen).
  final String? initialPhone;
  final String? initialCountryCode;

  const PhoneNumberScreen({
    super.key,
    this.isSignup = false,
    this.initialPhone,
    this.initialCountryCode,
  });

  @override
  State<PhoneNumberScreen> createState() => _PhoneNumberScreenState();
}

class _PhoneNumberScreenState extends State<PhoneNumberScreen> {
  final TextEditingController _phoneController = TextEditingController();
  String _countryCode = '+91';
  int _phoneMaxLength = 10;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialPhone != null && widget.initialPhone!.isNotEmpty) {
      _phoneController.text = widget.initialPhone!;
    }
    if (widget.initialCountryCode != null && widget.initialCountryCode!.isNotEmpty) {
      _countryCode = widget.initialCountryCode!;
      _phoneMaxLength = CountryPhoneLength.getMaxLength(_countryCode);
    }
  }

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
    // (2026-08-04) Captured here so OtpScreen's own login-branch lookup
    // (after the OTP is verified) can do a direct doc(id).get() instead of
    // repeating this exact same 3-field query from scratch.
    String? existingUserId;
    try {
      final snap = await FirebaseFirestore.instance
          .collection(USERS)
          .where('phoneNumber', isEqualTo: _phoneController.text.trim())
          .where('countryCode', isEqualTo: _countryCode)
          .where('role', isEqualTo: USER_ROLE_CUSTOMER)
          .get();
      isNewUser = snap.docs.isEmpty;
      if (!isNewUser) existingUserId = snap.docs.first.id;
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
        existingUserId: existingUserId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSignup = widget.isSignup;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0620),
      body: AuthBackground(
        child: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: Column(
            children: [
              AuthHeader(
                title: isSignup ? 'Create Account'.tr() : 'Enter Mobile Number'.tr(),
                subtitle: isSignup
                    ? 'Enter your number to verify your identity and get started.'.tr()
                    : "We'll send you a one-time verification code.".tr(),
                showBackButton: true,
                action: !isSignup
                    ? GestureDetector(
                        onTap: () async {
                          final permission = await Geolocator.checkPermission();
                          if (!mounted) return;
                          if (permission == LocationPermission.always ||
                              permission == LocationPermission.whileInUse) {
                            if (MyAppState.selectedPosotion.location == null) {
                              pushAndRemoveUntil(context, LocationPermissionScreen());
                            } else {
                              pushAndRemoveUntil(context, ServiceListScreen());
                            }
                          } else {
                            pushAndRemoveUntil(context, LocationPermissionScreen());
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
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
                    : null,
              ),
              Expanded(
                child: AuthFormCard(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(24, 28, 24, Platform.isAndroid ? 24 : 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AuthFieldLabel(text: 'Mobile Number'.tr()),
                        AuthTextField(
                          controller: _phoneController,
                          hint: 'Enter phone number'.tr(),
                          keyboardType: const TextInputType.numberWithOptions(
                              signed: true, decimal: true),
                          textInputAction: TextInputAction.done,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(_phoneMaxLength),
                          ],
                          prefixWidget: CountryCodePicker(
                            onChanged: (value) =>
                                _onCountryCodeChanged(value.dialCode.toString()),
                            initialSelection: 'IN',
                            favorite: const ['+91'],
                            showCountryOnly: false,
                            showOnlyCountryWhenClosed: false,
                            alignLeft: false,
                            textStyle: const TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                              fontFamily: AppThemeData.medium,
                            ),
                            dialogTextStyle: const TextStyle(
                              color: AppThemeData.grey50,
                              fontWeight: FontWeight.w500,
                              fontFamily: AppThemeData.medium,
                            ),
                            dialogBackgroundColor: AppThemeData.grey800,
                            searchStyle: const TextStyle(
                              color: AppThemeData.grey50,
                              fontWeight: FontWeight.w500,
                              fontFamily: AppThemeData.medium,
                            ),
                            flagWidth: 24,
                            padding: const EdgeInsets.only(left: 8),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Max $_phoneMaxLength digits',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 12,
                              fontFamily: AppThemeData.regular,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        AuthPrimaryButton(
                          label: _isSending ? 'Sending...'.tr() : 'Send OTP'.tr(),
                          onTap: _isSending ? () {} : _sendCode,
                        ),
                        const SizedBox(height: 28),
                        const AuthOrDivider(),
                        const SizedBox(height: 20),
                        AuthOutlinedButton(
                          label: isSignup
                              ? 'Sign up with Email instead'.tr()
                              : 'Continue with Email'.tr(),
                          iconPath: 'assets/icons/ic_mail.svg',
                          onTap: () => Navigator.pop(context),
                        ),
                        const SizedBox(height: 28),
                        Text.rich(
                          TextSpan(
                            text: 'By continuing, you agree to our '.tr(),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.50),
                              fontSize: 12,
                              fontFamily: AppThemeData.regular,
                            ),
                            children: [
                              TextSpan(
                                text: 'Terms & Conditions'.tr(),
                                style: const TextStyle(
                                  color: AppThemeData.primary400,
                                  decoration: TextDecoration.underline,
                                  decorationColor: AppThemeData.primary400,
                                  fontFamily: AppThemeData.medium,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () => push(context, const TermsAndCondition()),
                              ),
                              TextSpan(
                                text: ' and '.tr(),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.50),
                                ),
                              ),
                              TextSpan(
                                text: 'Privacy Policy'.tr(),
                                style: const TextStyle(
                                  color: AppThemeData.primary400,
                                  decoration: TextDecoration.underline,
                                  decorationColor: AppThemeData.primary400,
                                  fontFamily: AppThemeData.medium,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () => push(context, const PrivacyPolicyScreen()),
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
              _buildFooter(context, isSignup),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, bool isSignup) {
    return Padding(
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
                  color: Colors.white.withValues(alpha: 0.65),
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
                  color: AppThemeData.primary400,
                  fontFamily: AppThemeData.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
