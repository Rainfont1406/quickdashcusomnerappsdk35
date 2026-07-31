import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/device_session_service.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/msg91_service.dart';
import 'package:emartconsumer/services/notification_service.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/auth_screen/auth_widgets.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/ui/auth_screen/signup_screen.dart';
import 'package:emartconsumer/ui/location_permission_screen.dart';
import 'package:emartconsumer/ui/service_list_screen.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sms_autofill/sms_autofill.dart';
import 'package:uuid/uuid.dart';

// Base URL of the QuickDash admin/API server.
const _kApiBase = 'https://admin.quickdash.co.in';

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

  // ── Server-side OTP verification → Firebase Auth → Firestore ─────────
  Future<void> _verifyOtp() async {
    if (_isVerifying) return;
    final otp = _otpController.text.trim();
    if (otp.length != 4) {
      ShowToastDialog.showToast('Please enter the complete 4-digit OTP.'.tr());
      return;
    }

    if (mounted) setState(() => _isVerifying = true);
    ShowToastDialog.showLoader('Verifying your account...');

    // TEMPORARY [LOGIN-PERF] - timing instrumentation for the login-speed
    // investigation. Remove once done.
    final totalSw = Stopwatch()..start();
    try {
      // ── Step 1: For signup, generate the UUID now so the server can mint
      //            a token for it. For login the server does the Firestore
      //            lookup and returns the existing userID.
      final newUid = widget.isSignup ? const Uuid().v4() : null;

      // ── Step 2: Call the admin server to verify OTP with MSG91 and
      //            return a Firebase custom token. The server is the sole
      //            verifier — doing it here prevents the authKey from ever
      //            leaving the server and closes the single-use OTP race.
      final mobile = '${countryCode.replaceAll('+', '')}$phoneNumber';
      final body = {
        'otp': otp,
        'mobile': mobile,
        'phone_number': phoneNumber,
        'country_code': countryCode,
        'role': USER_ROLE_CUSTOMER,
        'is_signup': widget.isSignup,
        if (newUid != null) 'new_user_id': newUid,
      };

      final verifyOtpSw = Stopwatch()..start();
      final resp = await http
          .post(
            Uri.parse('$_kApiBase/api/auth/verify-otp'),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      debugPrint('[LOGIN-PERF] HTTP POST verify-otp — ${verifyOtpSw.elapsedMilliseconds}ms (status=${resp.statusCode})');

      final respJson = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode != 200) {
        ShowToastDialog.closeLoader();
        if (mounted) setState(() => _isVerifying = false);
        ShowToastDialog.showToast(
            (respJson['error'] as String?) ?? 'OTP verification failed. Please try again.');
        return;
      }

      final firebaseToken = respJson['firebase_token'] as String;

      // ── Step 3: Establish a real Firebase Auth session so request.auth.uid
      //            equals the user's Firestore document ID for all subsequent
      //            Firestore writes.
      final signInSw = Stopwatch()..start();
      await firebase_auth.FirebaseAuth.instance
          .signInWithCustomToken(firebaseToken);
      debugPrint('[LOGIN-PERF] signInWithCustomToken — ${signInSw.elapsedMilliseconds}ms');

      if (!mounted) return;

      // ── Step 4a: LOGIN flow ────────────────────────────────────────
      if (!widget.isSignup) {
        // The user lookup and the FCM token fetch are independent of each
        // other — run them concurrently instead of paying for the token
        // fetch strictly after the Firestore query resolves. Same fix as
        // hasFinishedOnBoarding() in main.dart's session-restore path.
        // Explicit <dynamic> because NotificationService.getToken() has no
        // declared return type.
        final userLookupSw = Stopwatch()..start();
        final loginResults = await Future.wait<dynamic>([
          FirebaseFirestore.instance
              .collection(USERS)
              .where('phoneNumber', isEqualTo: phoneNumber)
              .where('countryCode', isEqualTo: countryCode)
              .where('role', isEqualTo: USER_ROLE_CUSTOMER)
              .get(),
          NotificationService.getToken(),
        ]);
        debugPrint('[LOGIN-PERF] user lookup+getToken (parallel) — ${userLookupSw.elapsedMilliseconds}ms');
        final snap = loginResults[0] as QuerySnapshot<Map<String, dynamic>>;
        final fcmToken = loginResults[1] as String;

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

        final deviceSessionSw = Stopwatch()..start();
        final sessionResult = await DeviceSessionService.authorize(fcmToken: fcmToken);
        debugPrint('[LOGIN-PERF] DeviceSessionService.authorize — ${deviceSessionSw.elapsedMilliseconds}ms');
        if (!sessionResult.allowed) {
          ShowToastDialog.closeLoader();
          if (mounted) setState(() => _isVerifying = false);
          ShowToastDialog.showToast(sessionResult.message!);
          if (mounted) pushAndRemoveUntil(context, const LoginScreen());
          return;
        }

        userModel.fcmToken = fcmToken;
        // This write now succeeds: request.auth.uid == userModel.userID.
        // Fire-and-forget: navigation doesn't need to wait on this write's
        // round trip — MyAppState.currentUser below already reflects the
        // update in memory. Same fix as hasFinishedOnBoarding() in main.dart.
        unawaited(FireStoreUtils.updateCurrentUser(userModel));

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(PHONE_AUTH_USER_ID, userModel.userID);

        MyAppState.currentUser = userModel;

        if (!mounted) return;
        ShowToastDialog.closeLoader();
        debugPrint('[LOGIN-PERF] TOTAL (tap to navigate) — ${totalSw.elapsedMilliseconds}ms');

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

      // ── Step 4b: SIGNUP flow ───────────────────────────────────────
      final fcmToken = await NotificationService.getToken();
      final User userModel = User()
        ..userID = newUid!
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
        ShowToastDialog.showToast('No internet connection. Please try again.');
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
    return Scaffold(
      backgroundColor: const Color(0xFF0D0620),
      body: AuthBackground(
        child: Column(
          children: [
            AuthHeader(
              title: 'Verify Your Number'.tr(),
              subtitle: '${'Code sent to'.tr()} $countryCode $phoneNumber',
              showBackButton: true,
            ),
            Expanded(
              child: AuthFormCard(
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
                        color: Colors.white.withValues(alpha: 0.30),
                        fontSize: 22,
                      ),
                      textStyle: const TextStyle(
                        color: Colors.white,
                        fontFamily: AppThemeData.semiBold,
                        fontSize: 20,
                      ),
                      pinTheme: PinTheme(
                        fieldHeight: 58,
                        fieldWidth: 58,
                        inactiveFillColor: Colors.white.withValues(alpha: 0.08),
                        selectedFillColor: Colors.white.withValues(alpha: 0.14),
                        activeFillColor: Colors.white.withValues(alpha: 0.08),
                        selectedColor: AppThemeData.primary400,
                        activeColor: AppThemeData.primary400,
                        inactiveColor: Colors.white.withValues(alpha: 0.28),
                        disabledColor: Colors.white.withValues(alpha: 0.15),
                        shape: PinCodeFieldShape.box,
                        errorBorderColor: AppThemeData.error500,
                        borderRadius:
                            const BorderRadius.all(Radius.circular(12)),
                        borderWidth: 1.5,
                      ),
                      cursorColor: AppThemeData.primary400,
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
                            color: Colors.white.withValues(alpha: 0.65),
                          ),
                        ),
                        _canResend
                            ? GestureDetector(
                                onTap: _resendOtp,
                                child: Text(
                                  'Resend'.tr(),
                                  style: const TextStyle(
                                    color: AppThemeData.primary400,
                                    fontFamily: AppThemeData.semiBold,
                                    fontSize: 14,
                                  ),
                                ),
                              )
                            : Text(
                                _formattedTime,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontFamily: AppThemeData.semiBold,
                                  color: Colors.white,
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
                                        .withValues(alpha: 0.40),
                                    blurRadius: 16,
                                    offset: const Offset(0, 5),
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
                                  color: Colors.white.withValues(alpha: 0.65),
                                ),
                              ),
                              TextSpan(
                                text: 'Change'.tr(),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontFamily: AppThemeData.semiBold,
                                  color: AppThemeData.primary400,
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
            ),
          ],
        ),
      ),
    );
  }
}
