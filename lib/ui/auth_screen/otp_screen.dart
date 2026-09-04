import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/model/referral_model.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/device_session_service.dart';
import 'package:emartconsumer/services/firestore_instrumentation.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/msg91_service.dart';
import 'package:emartconsumer/services/notification_service.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/auth_screen/auth_widgets.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
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
  // (2026-08-04) PhoneNumberScreen's own pre-check (the "Checking your
  // account..." step, before the OTP is even sent) already ran the exact
  // same phoneNumber+countryCode+role query this screen's login branch used
  // to run again from scratch - it already knows the account's userID when
  // one exists. Passing it through turns that second lookup into a direct
  // doc(id).get() instead of a 3-field indexed query. Still a live re-read
  // (not a reused snapshot) - active/role are re-checked fresh right here,
  // this only changes how the doc is found, not whether it's re-read.
  final String? existingUserId;

  const OtpScreen({
    super.key,
    this.countryCode,
    this.phoneNumber,
    this.verificationId,
    this.isSignup = false,
    this.existingUserId,
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
        final existingUserId = widget.existingUserId;
        final userLookupFuture = existingUserId != null
            ? FirebaseFirestore.instance.collection(USERS).doc(existingUserId).getLogged('_verifyOtp:USERS')
            : FirebaseFirestore.instance
                .collection(USERS)
                .where('phoneNumber', isEqualTo: phoneNumber)
                .where('countryCode', isEqualTo: countryCode)
                .where('role', isEqualTo: USER_ROLE_CUSTOMER)
                .getLogged('_verifyOtp:USERS');
        final loginResults = await Future.wait<dynamic>([
          userLookupFuture,
          NotificationService.getToken(),
        ]);
        debugPrint('[LOGIN-PERF] user lookup+getToken (parallel) — ${userLookupSw.elapsedMilliseconds}ms'
            '${existingUserId != null ? " (direct doc get)" : " (query fallback)"}');
        final fcmToken = loginResults[1] as String;

        Map<String, dynamic>? userData;
        if (existingUserId != null) {
          final doc = loginResults[0] as DocumentSnapshot<Map<String, dynamic>>;
          userData = doc.exists ? doc.data() : null;
        } else {
          final snap = loginResults[0] as QuerySnapshot<Map<String, dynamic>>;
          userData = snap.docs.isNotEmpty ? snap.docs.first.data() : null;
        }

        if (!mounted) return;

        if (userData == null) {
          ShowToastDialog.closeLoader();
          if (mounted) setState(() => _isVerifying = false);
          ShowToastDialog.showToast(
              'No account found with this number. Please sign up first.');
          if (mounted) pushAndRemoveUntil(context, const LoginScreen());
          return;
        }

        final userModel = User.fromJson(userData);

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
        // showSuccess() transitions the same loading overlay to a checkmark
        // and dismisses itself on its own timer (2026-08-27) - no finally
        // block wraps this call, so nothing re-dismisses it early.
        ShowToastDialog.showSuccess('Login successful!');
        debugPrint('[LOGIN-PERF] TOTAL (tap to navigate) — ${totalSw.elapsedMilliseconds}ms');

        final addresses = userModel.shippingAddress;
        if (addresses != null && addresses.isNotEmpty) {
          final defaultAddr = addresses.firstWhere(
            (e) => e.isDefault == true,
            orElse: () => addresses.first,
          );
          if (defaultAddr.location != null) {
            MyAppState.selectedPosotion = defaultAddr;
            debugPrint('[LOGIN-PERF] pushAndRemoveUntil(ServiceListScreen) — ${totalSw.elapsedMilliseconds}ms since tap');
            pushAndRemoveUntil(context, ServiceListScreen(user: userModel));
          } else {
            debugPrint('[LOGIN-PERF] pushAndRemoveUntil(LocationPermissionScreen) — ${totalSw.elapsedMilliseconds}ms since tap');
            pushAndRemoveUntil(context, LocationPermissionScreen());
          }
        } else {
          debugPrint('[LOGIN-PERF] pushAndRemoveUntil(LocationPermissionScreen) — ${totalSw.elapsedMilliseconds}ms since tap');
          pushAndRemoveUntil(context, LocationPermissionScreen());
        }
        return;
      }

      // ── Step 4b: SIGNUP flow ───────────────────────────────────────
      final User userModel = User()
        ..userID = newUid!
        ..countryCode = countryCode
        ..phoneNumber = phoneNumber;

      if (!mounted) return;
      // Same pattern as Step 4a's "Login successful!" above (2026-08-27) -
      // OTP verification gets its own clear success moment before handing
      // off to the profile sheet, instead of the loader just vanishing.
      ShowToastDialog.showSuccess('Phone verified!');
      debugPrint('[LOGIN-PERF] TOTAL (OTP verify -> profile sheet) — ${totalSw.elapsedMilliseconds}ms since tap');
      // A bottom sheet, not a full SignupScreen push (2026-08-27, vendor
      // request) - keeps this lightweight, signup-only 3-field step
      // (name/email/referral) fully decoupled from AccountDetailsScreen,
      // which is free to grow more fields later for editing an existing
      // profile without entangling with signup at all.
      await _completePhoneSignup(userModel);
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

  // ── Phone signup: 3-field profile sheet + account creation ────────────
  // Moved here from signup_screen.dart's SignupScreen(type: 'mobileNumber')
  // (2026-08-27, vendor request) - a lightweight bottom sheet instead of a
  // full screen, so this signup-only step (name/email/referral, nothing
  // else) never has to grow alongside AccountDetailsScreen (the separate,
  // pre-existing profile-editing screen for an already-signed-up user,
  // which may gain more fields later with no bearing on signup at all).
  Future<void> _completePhoneSignup(User userModel) async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final referralCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    Timer? emailDebounce;

    // Mandatory, no dismiss (2026-08-25 decision: name+email required right
    // after OTP, not deferred) - the phone-auth account already exists at
    // this point, so backing out without completing still needs the same
    // orphan cleanup as any other aborted signup, handled below.
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          // Instant duplicate check as the vendor finishes typing the email
          // (2026-08-27, vendor request) - shown right under the field
          // instead of only surfacing at the final Continue tap, so a
          // known-taken email is caught immediately rather than after
          // filling in the rest of the sheet. _finishPhoneSignup still runs
          // the authoritative check on submit regardless (a race between
          // typing here and someone else registering the same email in the
          // meantime is still possible, however unlikely) - this is purely
          // an earlier warning, not a replacement for that check.
          String? emailError;
          bool checkingEmail = false;

          void onEmailChanged(String value) {
            emailDebounce?.cancel();
            setSheetState(() {
              emailError = null;
              checkingEmail = false;
            });
            final trimmed = value.trim();
            if (trimmed.isEmpty || validateEmail(trimmed) != null) return;
            emailDebounce = Timer(const Duration(milliseconds: 700), () async {
              setSheetState(() => checkingEmail = true);
              final conflict = await _checkEmailAlreadyRegistered(trimmed);
              setSheetState(() {
                checkingEmail = false;
                emailError = conflict;
              });
            });
          }

          return PopScope(
            canPop: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Set Your Profile'.tr(),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87)),
                      const SizedBox(height: 4),
                      Text(
                          'Your number is verified - just a couple more details to get started.'
                              .tr(),
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(labelText: 'Full Name'.tr()),
                        validator: validateName,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textCapitalization: TextCapitalization.none,
                        onChanged: onEmailChanged,
                        decoration: InputDecoration(
                          labelText: 'Email Address'.tr(),
                          suffixIcon: checkingEmail
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                )
                              : null,
                          errorText: emailError,
                        ),
                        validator: (v) => validateEmail(v) ?? emailError,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: referralCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(labelText: 'Referral Code (Optional)'.tr()),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppThemeData.primary500,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: checkingEmail
                              ? null
                              : () {
                                  if (formKey.currentState?.validate() ?? false) {
                                    Navigator.pop(ctx, true);
                                  }
                                },
                          child: Text('Continue'.tr(),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    emailDebounce?.cancel();

    if (submitted != true) {
      await _abortOrphanedPhoneSignup(userModel, 'Signup was not completed.');
      return;
    }

    await _finishPhoneSignup(
      userModel,
      fullName: nameCtrl.text,
      email: emailCtrl.text,
      referralCode: referralCtrl.text,
    );
  }

  // Shared by the instant-check above and _finishPhoneSignup's own
  // authoritative check on submit - same query, same role scoping.
  Future<String?> _checkEmailAlreadyRegistered(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final snap =
        await FirebaseFirestore.instance.collection(USERS).where('email', isEqualTo: normalized).getLogged('_checkEmailAlreadyRegistered:USERS');
    final conflict =
        snap.docs.any((doc) => (doc.data()['role'] as String? ?? '') == USER_ROLE_CUSTOMER);
    return conflict ? 'This email is already registered.'.tr() : null;
  }

  Map<String, String> _splitFullName(String fullName) {
    final trimmedName = fullName.trim();
    if (trimmedName.isEmpty) return {'firstName': '', 'lastName': ''};
    final parts = trimmedName.split(RegExp(r'\s+'));
    if (parts.length == 1) return {'firstName': parts[0], 'lastName': ''};
    return {'firstName': parts[0], 'lastName': parts.sublist(1).join(' ')};
  }

  // Same account-creation logic previously in signup_screen.dart's
  // signUp()'s mobileNumber branch, moved here unchanged (2026-08-27).
  Future<void> _finishPhoneSignup(
    User userModel, {
    required String fullName,
    required String email,
    required String referralCode,
  }) async {
    ShowToastDialog.showLoader('Creating your account...');
    var didShowSuccess = false;
    try {
      // Phone uniqueness for signup is already enforced server-side
      // (OtpVerifyController::verifyAndMint rejects a duplicate phone+role
      // before this screen is ever reached) - but email is only collected
      // here, so it still needs its own check. Authoritative re-check here
      // regardless of what the sheet's instant check already found - closes
      // the race where someone else registers the same email in the gap
      // between typing it and tapping Continue.
      final emailConflict = await _checkEmailAlreadyRegistered(email);
      if (emailConflict != null) {
        await _abortOrphanedPhoneSignup(userModel, emailConflict);
        return;
      }

      final fcmToken = await NotificationService.getToken();

      // Registers this device as the account's authorized device the
      // moment it's created - without this, a brand-new account has no
      // device_id on file until its first subsequent login, leaving a
      // window where a second device could complete its own login-time
      // authorize() with nothing yet to conflict against.
      final sessionResult = await DeviceSessionService.authorize(fcmToken: fcmToken);
      if (!sessionResult.allowed) {
        await _abortOrphanedPhoneSignup(userModel, sessionResult.message!);
        return;
      }

      final nameParts = _splitFullName(fullName);
      userModel.firstName = nameParts['firstName']!;
      userModel.lastName = nameParts['lastName']!;
      userModel.email = email.trim().toLowerCase();
      userModel.role = USER_ROLE_CUSTOMER;
      userModel.fcmToken = fcmToken;
      // Must be false (or absent) on this very first write - firestore.rules
      // rejects a self-created user doc with active: true (2026-08-18
      // hardening, to stop a client self-approving). ServiceListScreen/
      // LocationPermissionScreen already promote it to true themselves via
      // a separate update right after this, which the rules do allow.
      userModel.active = false;
      userModel.createdAt = Timestamp.now();

      final referralUser = await FireStoreUtils.getReferralUserByCode(referralCode);
      await FireStoreUtils.referralAdd(ReferralModel(
        id: userModel.userID,
        referralBy: referralUser?.id ?? '',
        referralCode: getReferralCode(),
      ));

      await FireStoreUtils.updateCurrentUser(userModel);
      // Persist phone user ID so the session survives app restarts
      final signupPrefs = await SharedPreferences.getInstance();
      await signupPrefs.setString(PHONE_AUTH_USER_ID, userModel.userID);
      if (!mounted) return;
      didShowSuccess = true;
      ShowToastDialog.showSuccess('Account created!');
      if (userModel.shippingAddress != null && userModel.shippingAddress!.isNotEmpty) {
        if (userModel.shippingAddress!.where((e) => e.isDefault == true).isNotEmpty) {
          MyAppState.selectedPosotion =
              userModel.shippingAddress!.where((e) => e.isDefault == true).single;
        } else {
          MyAppState.selectedPosotion = userModel.shippingAddress!.first;
        }
        pushAndRemoveUntil(context, ServiceListScreen(user: userModel));
      } else {
        pushAndRemoveUntil(context, LocationPermissionScreen());
      }
    } catch (_) {
      await _abortOrphanedPhoneSignup(userModel, 'Something went wrong. Please try again.');
    } finally {
      if (!didShowSuccess) ShowToastDialog.closeLoader();
    }
  }

  // Same rollback as signup_screen.dart's _abortOrphanedSignup (2026-08-27)
  // - the phone-auth Firebase account already exists by the time this
  // screen is reached, so any failure/abandonment from here on must delete
  // it rather than leave an orphan with no Firestore profile. Logs the
  // attempt to failed_signups first, for admin visibility only - see that
  // method's own comment for the full reasoning, identical here.
  Future<void> _abortOrphanedPhoneSignup(User userModel, String message) async {
    ShowToastDialog.showToast(message);
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('failed_signups').addLogged({
          'deletedAuthUid': user.uid,
          'signupType': 'phone',
          'attemptedPhone': userModel.phoneNumber,
          'countryCode': userModel.countryCode,
          'reason': message,
          'createdAt': FieldValue.serverTimestamp(),
          'ttlAt': Timestamp.fromDate(DateTime.now().toUtc().add(const Duration(days: 30))),
        }, '_abortOrphanedPhoneSignup:failed_signups');
      } catch (_) {}
      try {
        await user.delete();
      } catch (_) {
        await firebase_auth.FirebaseAuth.instance.signOut();
      }
    }
    if (mounted) pushAndRemoveUntil(context, const LoginScreen());
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
