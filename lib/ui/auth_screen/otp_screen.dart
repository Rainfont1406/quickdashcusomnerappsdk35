import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/notification_service.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/auth_screen/auth_widgets.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/ui/auth_screen/signup_screen.dart';
import 'package:emartconsumer/ui/location_permission_screen.dart';
import 'package:emartconsumer/ui/service_list_screen.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

class OtpScreen extends StatefulWidget {
  final String? countryCode;
  final String? phoneNumber;
  final String? verificationId;

  const OtpScreen({
    super.key,
    this.countryCode,
    this.phoneNumber,
    this.verificationId,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final TextEditingController _otpController = TextEditingController();

  late String countryCode;
  late String phoneNumber;
  late String verificationId;
  int resendToken = 0;

  Timer? _timer;
  int _remainingTime = 30;
  bool _canResend = false;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    countryCode = widget.countryCode ?? '';
    phoneNumber = widget.phoneNumber ?? '';
    verificationId = widget.verificationId ?? '';
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _canResend = false;
    _remainingTime = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remainingTime == 0) {
        setState(() => _canResend = true);
        timer.cancel();
      } else {
        setState(() => _remainingTime--);
      }
    });
  }

  String get _formattedTime =>
      '0:${_remainingTime.toString().padLeft(2, '0')}';

  Future<void> _resendOtp() async {
    if (!_canResend || _isVerifying) return;
    _otpController.clear();
    _startTimer();
    ShowToastDialog.showLoader('Sending OTP…'.tr());
    try {
      await auth.FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: countryCode + phoneNumber,
        verificationCompleted: (_) {},
        verificationFailed: (auth.FirebaseAuthException e) {
          ShowToastDialog.closeLoader();
          if (e.code == 'too-many-requests') {
            ShowToastDialog.showToast(
                'Too many requests. Please wait before requesting a new OTP.');
          } else if (e.code == 'invalid-phone-number') {
            ShowToastDialog.showToast('Invalid phone number. Please go back and try again.');
          } else {
            ShowToastDialog.showToast(e.message ?? 'Failed to send OTP. Please try again.');
          }
        },
        codeSent: (String vid, int? token) {
          verificationId = vid;
          if (token != null) resendToken = token;
          ShowToastDialog.closeLoader();
          ShowToastDialog.showToast('A new OTP has been sent to your number.');
        },
        timeout: const Duration(seconds: 25),
        forceResendingToken: resendToken,
        codeAutoRetrievalTimeout: (_) {
          ShowToastDialog.closeLoader();
        },
      );
    } catch (_) {
      ShowToastDialog.closeLoader();
      ShowToastDialog.showToast('Failed to resend OTP. Please try again.');
    }
  }

  Future<void> _verifyOtp() async {
    if (_isVerifying) return;
    if (_otpController.text.length != 6) {
      ShowToastDialog.showToast('Please enter the complete 6-digit OTP.'.tr());
      return;
    }

    if (mounted) setState(() => _isVerifying = true);
    ShowToastDialog.showLoader('Verifying…'.tr());
    try {
      final credential = auth.PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: _otpController.text,
      );

      final fcmTokenFuture = NotificationService.getToken();
      final value = await auth.FirebaseAuth.instance
          .signInWithCredential(credential);
      final String fcmToken = await fcmTokenFuture;

      if (!mounted) return;

      if (value.additionalUserInfo!.isNewUser) {
        User userModel = User()
          ..userID = value.user!.uid
          ..countryCode = countryCode
          ..phoneNumber = phoneNumber
          ..fcmToken = fcmToken;
        ShowToastDialog.closeLoader();
        push(context, SignupScreen(type: 'mobileNumber', userModel: userModel));
        return;
      }

      final bool userExists =
          await FireStoreUtils.userExistOrNot(value.user!.uid) == true;

      if (!userExists) {
        User userModel = User()
          ..userID = value.user!.uid
          ..countryCode = countryCode
          ..phoneNumber = phoneNumber
          ..fcmToken = fcmToken;
        ShowToastDialog.closeLoader();
        if (!mounted) return;
        pushReplacement(context,
            SignupScreen(userModel: userModel, type: 'mobileNumber'));
        return;
      }

      User? userModel =
          await FireStoreUtils.getUserProfile(value.user!.uid);

      if (userModel == null) {
        ShowToastDialog.showToast(
            'No account found for this number. Please sign up.');
        await auth.FirebaseAuth.instance.signOut();
        ShowToastDialog.closeLoader();
        if (!mounted) return;
        pushAndRemoveUntil(context, const LoginScreen());
        return;
      }

      if (userModel.role != USER_ROLE_CUSTOMER) {
        ShowToastDialog.showToast(
            'This account is not registered as a customer. Please use the correct QuickDash app.');
        await auth.FirebaseAuth.instance.signOut();
        ShowToastDialog.closeLoader();
        if (!mounted) return;
        pushAndRemoveUntil(context, const LoginScreen());
        return;
      }

      if (!userModel.active) {
        ShowToastDialog.showToast(
            'Your account has been deactivated. Please contact support for assistance.');
        await auth.FirebaseAuth.instance.signOut();
        ShowToastDialog.closeLoader();
        if (!mounted) return;
        pushAndRemoveUntil(context, const LoginScreen());
        return;
      }

      userModel.fcmToken = fcmToken;
      await FireStoreUtils.updateCurrentUser(userModel);

      ShowToastDialog.closeLoader();
      if (!mounted) return;

      final addresses = userModel.shippingAddress;
      if (addresses != null && addresses.isNotEmpty) {
        final defaultAddr = addresses.where((e) => e.isDefault == true).isNotEmpty
            ? addresses.where((e) => e.isDefault == true).single
            : addresses.first;
        if (defaultAddr.location != null) {
          MyAppState.selectedPosotion = defaultAddr;
          pushAndRemoveUntil(context, ServiceListScreen());
        } else {
          pushAndRemoveUntil(context, LocationPermissionScreen());
        }
      } else {
        pushAndRemoveUntil(context, LocationPermissionScreen());
      }
    } on auth.FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'invalid-verification-code':
          ShowToastDialog.showToast(
              'The OTP you entered is incorrect. Please try again.');
          break;
        case 'session-expired':
          ShowToastDialog.showToast(
              'OTP has expired. Please tap Resend to get a new code.');
          break;
        case 'too-many-requests':
          ShowToastDialog.showToast(
              'Too many attempts. Please wait a moment and try again.');
          break;
        case 'network-request-failed':
          ShowToastDialog.showToast(
              'Network error. Please check your internet connection and try again.');
          break;
        default:
          ShowToastDialog.showToast(
              e.message ?? 'Verification failed. Please try again.');
      }
    } catch (_) {
      ShowToastDialog.showToast('Something went wrong. Please try again.');
    } finally {
      ShowToastDialog.closeLoader();
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    return Scaffold(
      backgroundColor:
          dark ? AppThemeData.surfaceDark : const Color(0xFFF5F6FA),
      body: Column(
        children: [
          // Gradient header — matches other auth screens
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
                    // Back button
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
                    const SizedBox(height: 20),
                    // Logo row
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
                          padding: const EdgeInsets.all(8),
                          child: Image.asset(
                            'assets/images/app_logo_new.png',
                            fit: BoxFit.contain,
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
                      'Verify Your Number'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontFamily: AppThemeData.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${'Code sent to'.tr()} $countryCode $phoneNumber',
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

          // Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // OTP boxes
                  PinCodeTextField(
                    length: 6,
                    appContext: context,
                    keyboardType: TextInputType.phone,
                    enablePinAutofill: true,
                    hintCharacter: '·',
                    hintStyle: TextStyle(
                      color: dark
                          ? AppThemeData.grey600
                          : AppThemeData.grey300,
                      fontSize: 22,
                    ),
                    textStyle: TextStyle(
                      color: dark
                          ? AppThemeData.grey50
                          : AppThemeData.grey900,
                      fontFamily: AppThemeData.semiBold,
                      fontSize: 20,
                    ),
                    pinTheme: PinTheme(
                      fieldHeight: 54,
                      fieldWidth: 46,
                      inactiveFillColor: Colors.transparent,
                      selectedFillColor: Colors.transparent,
                      activeFillColor: Colors.transparent,
                      selectedColor: AppThemeData.primary500,
                      activeColor: AppThemeData.primary500,
                      inactiveColor: dark
                          ? AppThemeData.grey600
                          : AppThemeData.grey300,
                      disabledColor: AppThemeData.grey300,
                      shape: PinCodeFieldShape.box,
                      errorBorderColor: AppThemeData.error500,
                      borderRadius:
                          const BorderRadius.all(Radius.circular(12)),
                      borderWidth: 1.5,
                    ),
                    cursorColor: AppThemeData.primary500,
                    enableActiveFill: true,
                    controller: _otpController,
                    onCompleted: (_) => _verifyOtp(),
                    onChanged: (_) {},
                  ),

                  const SizedBox(height: 28),

                  // Timer + resend row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "${'Resend code in'.tr()} ",
                        style: TextStyle(
                          fontSize: 14,
                          fontFamily: AppThemeData.regular,
                          color: dark
                              ? AppThemeData.grey400
                              : AppThemeData.grey500,
                        ),
                      ),
                      _canResend
                          ? GestureDetector(
                              onTap: _resendOtp,
                              child: Text(
                                'Resend'.tr(),
                                style: const TextStyle(
                                  color: AppThemeData.primary500,
                                  fontFamily: AppThemeData.semiBold,
                                  fontSize: 14,
                                ),
                              ),
                            )
                          : Text(
                              _formattedTime,
                              style: TextStyle(
                                fontSize: 14,
                                fontFamily: AppThemeData.semiBold,
                                color: dark
                                    ? AppThemeData.grey200
                                    : AppThemeData.grey700,
                              ),
                            ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Verify button — uses AuthPrimaryButton which stretches
                  // correctly without a fixed pixel/percentage width
                  AuthPrimaryButton(
                    label: 'Verify & Continue'.tr(),
                    onTap: _verifyOtp,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
