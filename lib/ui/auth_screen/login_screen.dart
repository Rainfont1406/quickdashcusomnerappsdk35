import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/services/firestore_instrumentation.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/msg91_service.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/auth_screen/auth_widgets.dart';
import 'package:emartconsumer/ui/auth_screen/email_login_screen.dart';
import 'package:emartconsumer/ui/auth_screen/otp_screen.dart';
import 'package:emartconsumer/ui/auth_screen/signup_screen.dart';
import 'package:emartconsumer/utils/country_phone_length.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LoginScreen extends StatefulWidget {
  // kept for backwards-compat; callers using startOnSignup:true will land on SignupScreen
  final bool startOnSignup;
  const LoginScreen({super.key, this.startOnSignup = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneCtrl = TextEditingController();
  String _countryCode = '+91';
  int _phoneMaxLength = 10;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    if (widget.startOnSignup) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) pushReplacement(context, const SignupScreen());
      });
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _onCountryCodeChanged(String dialCode) {
    setState(() {
      _countryCode = dialCode;
      _phoneMaxLength = CountryPhoneLength.getMaxLength(dialCode);
    });
  }

  Future<void> _sendOtp() async {
    FocusScope.of(context).unfocus();
    final phone = _phoneCtrl.text.trim();

    if (phone.isEmpty) {
      ShowToastDialog.showToast('Please enter your mobile number.'.tr());
      return;
    }
    if (!CountryPhoneLength.isValidLength(_countryCode, phone)) {
      ShowToastDialog.showToast(
          CountryPhoneLength.getValidationMessage(_countryCode));
      return;
    }
    if (_isSending) return;
    if (mounted) setState(() => _isSending = true);

    ShowToastDialog.showLoader('Checking your account...'.tr());
    bool isNewUser;
    try {
      final snap = await FirebaseFirestore.instance
          .collection(USERS)
          .where('phoneNumber', isEqualTo: phone)
          .where('countryCode', isEqualTo: _countryCode)
          .where('role', isEqualTo: USER_ROLE_CUSTOMER)
          .getLogged('_sendOtp:USERS');
      isNewUser = snap.docs.isEmpty;
    } catch (_) {
      ShowToastDialog.closeLoader();
      if (mounted) setState(() => _isSending = false);
      ShowToastDialog.showToast(
          'Unable to connect right now. Please try again.'.tr());
      return;
    }

    if (!mounted) {
      ShowToastDialog.closeLoader();
      return;
    }

    if (isNewUser) {
      ShowToastDialog.closeLoader();
      if (mounted) setState(() => _isSending = false);
      ShowToastDialog.showToast(
          'No account found with this number. Please sign up first.'.tr());
      return;
    }

    ShowToastDialog.closeLoader();

    ShowToastDialog.showLoader('Sending verification code...'.tr());
    final result = await Msg91Service.sendOtp(_countryCode, phone);
    ShowToastDialog.closeLoader();

    if (!mounted) return;
    if (mounted) setState(() => _isSending = false);

    if (!result.success) {
      ShowToastDialog.showToast(result.message);
      return;
    }

    ShowToastDialog.showToast(result.message);
    push(context, OtpScreen(
      countryCode: _countryCode,
      phoneNumber: phone,
      isSignup: false,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0620),
      body: AuthBackground(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: [
              AuthHeader(
                title: 'Welcome Back'.tr(),
                subtitle: 'Sign in to continue your seamless dining experience.'.tr(),
              ),
              Expanded(
               child: AuthFormCard(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24, 28, 24, Platform.isAndroid ? 24 : 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AuthFieldLabel(text: 'Phone Number'.tr()),
                      AuthTextField(
                        controller: _phoneCtrl,
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
                          dialogTextStyle: const TextStyle(
                            color: AppThemeData.grey50,
                            fontWeight: FontWeight.w500,
                            fontFamily: AppThemeData.medium,
                          ),
                          dialogBackgroundColor: AppThemeData.grey800,
                          initialSelection: 'IN',
                          favorite: const ['+91'],
                          comparator: (a, b) => b.name!.compareTo(a.name.toString()),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontFamily: AppThemeData.medium,
                          ),
                          searchDecoration: const InputDecoration(
                            iconColor: AppThemeData.grey50,
                          ),
                          searchStyle: const TextStyle(
                            color: AppThemeData.grey50,
                            fontWeight: FontWeight.w500,
                            fontFamily: AppThemeData.medium,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      AuthPrimaryButton(
                        label: _isSending ? 'Sending...'.tr() : 'Get OTP'.tr(),
                        onTap: _isSending ? () {} : _sendOtp,
                      ),
                      const SizedBox(height: 28),
                      const AuthOrDivider(),
                      const SizedBox(height: 20),
                      Center(
                        child: GestureDetector(
                          onTap: () => push(context, const EmailLoginScreen()),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Login with Email'.tr(),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.88),
                                fontFamily: AppThemeData.semiBold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
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
                text: "Don't have an account?  ".tr(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontFamily: AppThemeData.regular,
                  fontSize: 14,
                ),
              ),
              TextSpan(
                recognizer: TapGestureRecognizer()
                  ..onTap = () => push(context, const SignupScreen()),
                text: 'Create one'.tr(),
                style: const TextStyle(
                  color: AppThemeData.primary400,
                  fontFamily: AppThemeData.bold,
                  // Bumped from 14 (2026-08-27, vendor-reported: many users
                  // never noticed this was tappable at the same size as the
                  // surrounding plain text).
                  fontSize: 17,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
