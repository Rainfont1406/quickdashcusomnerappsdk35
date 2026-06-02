import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/msg91_service.dart';
import 'package:emartconsumer/services/notification_service.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/ui/auth_screen/signup_screen.dart';
import 'package:emartconsumer/ui/location_permission_screen.dart';
import 'package:emartconsumer/ui/service_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sms_autofill/sms_autofill.dart';
import 'package:uuid/uuid.dart';

class OtpScreen extends StatefulWidget {
  final String? countryCode;
  final String? phoneNumber;
  /// Kept for API compatibility — not used in the MSG91 flow.
  final String? verificationId;
  final bool isSignup;

  const OtpScreen({
    super.key,
    this.countryCode,
    this.phoneNumber,
    this.verificationId,
    this.isSignup = false,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

/// [CodeAutoFill] mixin wires up the Android SMS Retriever API.
/// [codeUpdated] is called whenever the platform delivers a matching SMS code;
/// [code] is the extracted digit string at that point.
class _OtpScreenState extends State<OtpScreen> with CodeAutoFill {
  final TextEditingController _otpController = TextEditingController();

  late String countryCode;
  late String phoneNumber;

  Timer? _countdownTimer;
  Timer? _smsListenTimer;
  int _remainingTime = 30;
  bool _canResend = false;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    countryCode = widget.countryCode ?? '';
    phoneNumber = widget.phoneNumber ?? '';
    _startCountdown();
    _startSmsRetriever();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _smsListenTimer?.cancel();
    cancel();             // cancel stream subscription (mixin)
    unregisterListener(); // stop Android SMS Retriever (mixin)
    _otpController.dispose();
    super.dispose();
  }

  // ── Countdown timer ───────────────────────────────────────────────────
  void _startCountdown() {
    _canResend = false;
    _remainingTime = 30;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_remainingTime == 0) {
        setState(() => _canResend = true);
        t.cancel();
      } else {
        setState(() => _remainingTime--);
      }
    });
  }

  String get _formattedTime =>
      '0:${_remainingTime.toString().padLeft(2, '0')}';

  // ── SMS Retriever API ─────────────────────────────────────────────────
  void _startSmsRetriever() {
    // Regex matches 4-to-6-digit blocks — works for MSG91's 4-digit OTPs
    listenForCode(smsCodeRegexPattern: r'\d{4,6}');

    // Auto-stop after 5 minutes to avoid stale listeners
    _smsListenTimer?.cancel();
    _smsListenTimer = Timer(const Duration(minutes: 5), () {
      cancel();
      unregisterListener();
    });

    // Log app hash so it can be added to the MSG91 SMS template
    SmsAutoFill().getAppSignature.then((hash) {
      if (hash.isNotEmpty) {
        debugPrint('════════════════════════════════════════════════');
        debugPrint('MSG91 app hash  : $hash');
        debugPrint('Add to template : <#> Your OTP is {{otp}} $hash');
        debugPrint('════════════════════════════════════════════════');
      }
    });
  }

  /// Called by [CodeAutoFill] mixin when the Android SMS Retriever delivers
  /// a code. [code] (mixin field) contains the extracted digit string.
  @override
  void codeUpdated() {
    if (!mounted || _isVerifying) return;
    final raw = code ?? '';
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return;
    final otp = digits.substring(0, 4);

    // Stop listening — OTP received, no need to stay active
    _smsListenTimer?.cancel();
    cancel();
    unregisterListener();

    setState(() => _otpController.text = otp);

    // Belt-and-suspenders: verify after short delay so the pin field renders
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted && !_isVerifying) _verifyOtp();
    });
  }

  // ── Resend via MSG91 ──────────────────────────────────────────────────
  Future<void> _resendOtp() async {
    if (!_canResend || _isVerifying) return;
    _otpController.clear();
    _startCountdown();
    ShowToastDialog.showLoader('Sending verification code...');
    final result = await Msg91Service.resendOtp(countryCode, phoneNumber);
    ShowToastDialog.closeLoader();
    ShowToastDialog.showToast(result.message);

    if (result.success) {
      // Re-arm the SMS listener for the newly sent OTP
      await cancel();
      await unregisterListener();
      _startSmsRetriever();
    }
  }

  // ── Verify via MSG91 → Firestore lookup ───────────────────────────────
  Future<void> _verifyOtp() async {
    if (_isVerifying) return;
    final otp = _otpController.text.trim();
    if (otp.length != 4) {
      ShowToastDialog.showToast('Please enter the complete 4-digit OTP.'.tr());
      return;
    }

    if (mounted) setState(() => _isVerifying = true);
    ShowToastDialog.showLoader('Verifying your account...');

    try {
      // ── Step 1: verify OTP with MSG91 ──────────────────────────────
      final verifyResult =
          await Msg91Service.verifyOtp(countryCode, phoneNumber, otp);

      if (!verifyResult.success) {
        ShowToastDialog.closeLoader();
        if (mounted) setState(() => _isVerifying = false);
        ShowToastDialog.showToast(verifyResult.message.isNotEmpty
            ? verifyResult.message
            : 'Incorrect OTP. Please try again.');
        return;
      }

      if (!mounted) return;

      // ── Step 2a: LOGIN flow ────────────────────────────────────────
      if (!widget.isSignup) {
        final snap = await FirebaseFirestore.instance
            .collection(USERS)
            .where('phoneNumber', isEqualTo: phoneNumber)
            .where('countryCode', isEqualTo: countryCode)
            .where('role', isEqualTo: USER_ROLE_CUSTOMER)
            .get();

        if (!mounted) return;

        if (snap.docs.isEmpty) {
          ShowToastDialog.closeLoader();
          if (mounted) setState(() => _isVerifying = false);
          ShowToastDialog.showToast(
              'No account found with this number. Please sign up first.');
          if (mounted) pushAndRemoveUntil(context, const LoginScreen());
          return;
        }

        final userModel = User.fromJson(snap.docs.first.data());

        if (userModel.role != USER_ROLE_CUSTOMER) {
          ShowToastDialog.closeLoader();
          if (mounted) setState(() => _isVerifying = false);
          ShowToastDialog.showToast(
              'This account is not registered as a customer. Please use the correct QuickDash app.');
          if (mounted) pushAndRemoveUntil(context, const LoginScreen());
          return;
        }

        if (!userModel.active) {
          ShowToastDialog.closeLoader();
          if (mounted) setState(() => _isVerifying = false);
          ShowToastDialog.showToast(
              'Your account is temporarily restricted. Please contact support.');
          if (mounted) pushAndRemoveUntil(context, const LoginScreen());
          return;
        }

        userModel.fcmToken = await NotificationService.getToken();
        await FireStoreUtils.updateCurrentUser(userModel);

        // Persist phone user ID so the session survives app restarts
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(PHONE_AUTH_USER_ID, userModel.userID);

        if (!mounted) return;
        ShowToastDialog.closeLoader();

        final addresses = userModel.shippingAddress;
        if (addresses != null && addresses.isNotEmpty) {
          final defaultAddr = addresses.firstWhere(
            (e) => e.isDefault == true,
            orElse: () => addresses.first,
          );
          if (defaultAddr.location != null) {
            MyAppState.selectedPosotion = defaultAddr;
            pushAndRemoveUntil(context, ServiceListScreen());
          } else {
            pushAndRemoveUntil(context, LocationPermissionScreen());
          }
        } else {
          pushAndRemoveUntil(context, LocationPermissionScreen());
        }
        return;
      }

      // ── Step 2b: SIGNUP flow ───────────────────────────────────────
      final fcmToken = await NotificationService.getToken();
      final newUid = const Uuid().v4();
      final User userModel = User()
        ..userID = newUid
        ..countryCode = countryCode
        ..phoneNumber = phoneNumber
        ..fcmToken = fcmToken;

      ShowToastDialog.closeLoader();
      if (!mounted) return;
      push(context, SignupScreen(type: 'mobileNumber', userModel: userModel));
    } catch (e) {
      ShowToastDialog.closeLoader();
      final msg = e.toString();
      if (msg.contains('SocketException') ||
          msg.contains('TimeoutException') ||
          msg.contains('NetworkException')) {
        ShowToastDialog.showToast(
            'No internet connection. Please try again.');
      } else {
        ShowToastDialog.showToast('Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    return Scaffold(
      backgroundColor:
          dark ? AppThemeData.surfaceDark : const Color(0xFFF5F6FA),
      body: Column(
        children: [
          // Gradient header
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
                  // OTP pin boxes — 4 digits, keyboard OTP suggestion enabled
                  PinCodeTextField(
                    length: 4,
                    appContext: context,
                    keyboardType: TextInputType.number,
                    enablePinAutofill: true,
                    hintCharacter: '·',
                    hintStyle: TextStyle(
                      color: dark
                          ? AppThemeData.grey600
                          : AppThemeData.grey300,
                      fontSize: 22,
                    ),
                    textStyle: TextStyle(
                      color: dark ? AppThemeData.grey50 : AppThemeData.grey900,
                      fontFamily: AppThemeData.semiBold,
                      fontSize: 20,
                    ),
                    pinTheme: PinTheme(
                      fieldHeight: 58,
                      fieldWidth: 58,
                      inactiveFillColor: Colors.transparent,
                      selectedFillColor: Colors.transparent,
                      activeFillColor: Colors.transparent,
                      selectedColor: AppThemeData.primary500,
                      activeColor: AppThemeData.primary500,
                      inactiveColor:
                          dark ? AppThemeData.grey600 : AppThemeData.grey300,
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

                  // Timer / resend row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _canResend
                            ? "${'Didn\'t receive the code?'.tr()} "
                            : "${'Resend code in'.tr()} ",
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

                  // Verify button
                  GestureDetector(
                    onTap: _isVerifying ? null : _verifyOtp,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _isVerifying
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
                        boxShadow: _isVerifying
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
                        child: _isVerifying
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Verify & Continue'.tr(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontFamily: AppThemeData.semiBold,
                                ),
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Wrong number? Go back
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Wrong number? '.tr(),
                              style: TextStyle(
                                fontSize: 13,
                                fontFamily: AppThemeData.regular,
                                color: dark
                                    ? AppThemeData.grey400
                                    : AppThemeData.grey500,
                              ),
                            ),
                            TextSpan(
                              text: 'Change'.tr(),
                              style: const TextStyle(
                                fontSize: 13,
                                fontFamily: AppThemeData.semiBold,
                                color: AppThemeData.primary500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
