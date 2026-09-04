import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:emartconsumer/constants.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/model/referral_model.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/device_session_service.dart';
import 'package:emartconsumer/services/firestore_instrumentation.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/notification_service.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/auth_screen/auth_widgets.dart';
import 'package:emartconsumer/ui/auth_screen/phone_number_screen.dart';
import 'package:emartconsumer/ui/location_permission_screen.dart';
import 'package:emartconsumer/ui/service_list_screen.dart';
import 'package:emartconsumer/utils/country_phone_length.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SignupScreen extends StatefulWidget {
  final User? userModel;
  final String? type;

  const SignupScreen({super.key, this.userModel, this.type});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  TextEditingController fullNameEditingController = TextEditingController();
  TextEditingController emailEditingController = TextEditingController();
  TextEditingController phoneNUmberEditingController = TextEditingController();
  TextEditingController countryCodeEditingController = TextEditingController();
  TextEditingController passwordEditingController = TextEditingController();
  TextEditingController conformPasswordEditingController =
      TextEditingController();
  TextEditingController referralCodeEditingController = TextEditingController();

  bool passwordVisible = true;
  bool conformPasswordVisible = true;

  String type = "";
  int phoneMaxLength = 10;

  User userModel = User();

  // Instant (debounced) duplicate checks (2026-08-27, vendor request) - shown
  // right under each field as the vendor finishes typing, instead of only
  // surfacing at the final Sign Up tap after the whole form is filled in.
  // _validateSignupForm/signUp() still run the authoritative check on
  // submit regardless - this is purely an earlier warning, not a
  // replacement (closes the race where someone else registers the same
  // email/phone in the gap between typing here and tapping Sign Up).
  String? _emailInlineError;
  String? _phoneInlineError;
  bool _checkingEmail = false;
  bool _checkingPhone = false;
  Timer? _emailDebounce;
  Timer? _phoneDebounce;

  @override
  void initState() {
    super.initState();
    type = widget.type ?? '';
    userModel = widget.userModel ?? User();
    if (type == "mobileNumber") {
      phoneNUmberEditingController.text = userModel.phoneNumber.toString();
      countryCodeEditingController.text = userModel.countryCode.toString();
    } else {
      if (countryCodeEditingController.text.isEmpty) {
        countryCodeEditingController.text = '+91';
      }
    }
    phoneMaxLength =
        CountryPhoneLength.getMaxLength(countryCodeEditingController.text);
  }

  @override
  void dispose() {
    _emailDebounce?.cancel();
    _phoneDebounce?.cancel();
    super.dispose();
  }

  // Same query/role-scoping as _findExistingCustomerConflict below, split
  // out per-field so each can run and report independently as the vendor
  // types (2026-08-27).
  Future<String?> _checkEmailAlreadyRegistered(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty || validateEmail(normalized) != null) return null;
    final snap =
        await FirebaseFirestore.instance.collection(USERS).where('email', isEqualTo: normalized).getLogged('_checkEmailAlreadyRegistered:USERS');
    final conflict =
        snap.docs.any((doc) => (doc.data()['role'] as String? ?? '') == USER_ROLE_CUSTOMER);
    return conflict ? 'This email is already registered.'.tr : null;
  }

  Future<String?> _checkPhoneAlreadyRegistered(String phoneNumber, String countryCode) async {
    final trimmed = phoneNumber.trim();
    if (trimmed.isEmpty || !_isPhoneNumberValid()) return null;
    final snap = await FirebaseFirestore.instance
        .collection(USERS)
        .where('phoneNumber', isEqualTo: trimmed)
        .getLogged('_checkPhoneAlreadyRegistered:USERS');
    final conflict = snap.docs.any((doc) {
      final data = doc.data();
      return (data['role'] as String? ?? '') == USER_ROLE_CUSTOMER &&
          (data['countryCode'] as String? ?? '') == countryCode;
    });
    return conflict ? 'This number is already registered.'.tr : null;
  }

  void _onEmailChangedInline(String value) {
    _emailDebounce?.cancel();
    setState(() {
      _emailInlineError = null;
      _checkingEmail = false;
    });
    final trimmed = value.trim();
    if (trimmed.isEmpty || validateEmail(trimmed) != null) return;
    _emailDebounce = Timer(const Duration(milliseconds: 700), () async {
      if (!mounted) return;
      setState(() => _checkingEmail = true);
      final conflict = await _checkEmailAlreadyRegistered(trimmed);
      if (!mounted) return;
      setState(() {
        _checkingEmail = false;
        _emailInlineError = conflict;
      });
    });
  }

  void _onPhoneChangedInline(String value) {
    _phoneDebounce?.cancel();
    setState(() {
      _phoneInlineError = null;
      _checkingPhone = false;
    });
    // type == "mobileNumber" -> phone is locked/pre-verified, never re-checked.
    if (type == "mobileNumber" || value.trim().isEmpty || !_isPhoneNumberValid()) return;
    _phoneDebounce = Timer(const Duration(milliseconds: 700), () async {
      if (!mounted) return;
      setState(() => _checkingPhone = true);
      final conflict =
          await _checkPhoneAlreadyRegistered(value, countryCodeEditingController.text);
      if (!mounted) return;
      setState(() {
        _checkingPhone = false;
        _phoneInlineError = conflict;
      });
    });
  }

  void _updatePhoneMaxLength() {
    setState(() {
      phoneMaxLength =
          CountryPhoneLength.getMaxLength(countryCodeEditingController.text);
    });
  }

  void _onCountryCodeChanged(String dialCode) {
    countryCodeEditingController.text = dialCode;
    _updatePhoneMaxLength();
  }

  bool _isPhoneNumberValid() {
    return CountryPhoneLength.isValidLength(
      countryCodeEditingController.text,
      phoneNUmberEditingController.text,
    );
  }

  String _getValidationErrorMessage() {
    return CountryPhoneLength.getValidationMessage(
        countryCodeEditingController.text);
  }

  Map<String, String> _splitFullName(String fullName) {
    final trimmedName = fullName.trim();
    if (trimmedName.isEmpty) return {'firstName': '', 'lastName': ''};
    final parts = trimmedName.split(RegExp(r'\s+'));
    if (parts.length == 1) return {'firstName': parts[0], 'lastName': ''};
    return {'firstName': parts[0], 'lastName': parts.sublist(1).join(' ')};
  }

  bool _validateSignupForm() {
    final fullName = fullNameEditingController.text.trim();
    final email = emailEditingController.text.trim();
    final phoneNumber = phoneNUmberEditingController.text.trim();
    final password = passwordEditingController.text.trim();
    final confirmPassword = conformPasswordEditingController.text.trim();
    final emailValidationMessage = validateEmail(email);

    final nameValidationMessage = validateName(fullName);
    if (fullName.isEmpty || nameValidationMessage != null) {
      ShowToastDialog.showToast(nameValidationMessage ?? "Please enter full name".tr);
      return false;
    } else if (email.isEmpty || emailValidationMessage != null) {
      ShowToastDialog.showToast(
          emailValidationMessage ?? "Please enter valid email".tr);
      return false;
    } else if (phoneNumber.isEmpty) {
      ShowToastDialog.showToast("Please enter valid phone number".tr);
      return false;
    } else if (!_isPhoneNumberValid()) {
      ShowToastDialog.showToast(_getValidationErrorMessage());
      return false;
    } else if (type != "mobileNumber") {
      if (password.isEmpty) {
        ShowToastDialog.showToast("Please enter password".tr);
        return false;
      } else if (password.length < 8) {
        ShowToastDialog.showToast("Password must be at least 8 characters".tr);
        return false;
      } else if (confirmPassword.isEmpty) {
        ShowToastDialog.showToast("Please enter Confirm password".tr);
        return false;
      } else if (password != confirmPassword) {
        ShowToastDialog.showToast(
            "Password and Confirm password doesn't match".tr);
        return false;
      }
    }
    return true;
  }

  bool _isBusy = false;

  /// Role-scoped duplicate check: a CUSTOMER account must have a unique
  /// email and unique (phone + countryCode) among other CUSTOMER accounts.
  /// A vendor/driver already using the same email/phone is NOT a conflict -
  /// only a second account with role == customer is. Returns a
  /// user-facing message if a conflict is found, else null.
  Future<String?> _findExistingCustomerConflict({
    required String email,
    required String phoneNumber,
    required String countryCode,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();

    // Email and phone conflict checks are independent — kick off both
    // Firestore queries immediately (calling .get() starts the request;
    // Dart doesn't run past this synchronous point until an await), then
    // await each only where it's needed, instead of the phone query
    // strictly following the email query's full round trip.
    final emailFuture = normalizedEmail.isNotEmpty
        ? FirebaseFirestore.instance
            .collection(USERS)
            .where('email', isEqualTo: normalizedEmail)
            .getLogged('_findExistingCustomerConflict:USERS')
        : null;
    final phoneFuture = FirebaseFirestore.instance
        .collection(USERS)
        .where('phoneNumber', isEqualTo: phoneNumber.trim())
        .getLogged('_findExistingCustomerConflict:USERS');

    if (emailFuture != null) {
      final emailSnap = await emailFuture;
      final emailConflict = emailSnap.docs.any((doc) =>
          (doc.data()['role'] as String? ?? '') == USER_ROLE_CUSTOMER);
      if (emailConflict) {
        return 'This email is already registered. Please log in to continue.';
      }
    }

    final phoneSnap = await phoneFuture;
    final phoneConflict = phoneSnap.docs.any((doc) {
      final data = doc.data();
      return (data['role'] as String? ?? '') == USER_ROLE_CUSTOMER &&
          (data['countryCode'] as String? ?? '') == countryCode;
    });
    if (phoneConflict) {
      return 'This number is already registered. Please log in to continue.';
    }

    return null;
  }

  signUpWithEmailAndPassword(BuildContext context) async {
    if (_isBusy) return;
    if (referralCodeEditingController.text.trim().isNotEmpty) {
      final valid = await FireStoreUtils.checkReferralCodeValidOrNot(
          referralCodeEditingController.text.trim());
      if (valid != true) {
        ShowToastDialog.showToast('Referral code not found.');
        return;
      }
    }
    signUp(context);
  }

  // A signup that fails AFTER the Firebase Auth account already exists
  // (device-session denied, an existing-customer conflict found only after
  // OTP already created the phone credential, or any later exception) used
  // to just sign out locally, leaving a permanently orphaned Auth account
  // behind - it has no matching Firestore user doc, so a retry with the
  // same email/phone fails as "already registered" while login fails as
  // "not registered," with no way out (2026-08-27 fix, found via a live
  // Auth-vs-Firestore diff: 38 real accounts stuck exactly this way).
  // Deleting the account here instead means the same email/phone is
  // immediately signup-able again.
  Future<void> _abortOrphanedSignup(BuildContext context, String message) async {
    ShowToastDialog.showToast(message);
    final user = auth.FirebaseAuth.instance.currentUser;
    if (user != null) {
      // Log the attempt for admin visibility BEFORE deleting the account -
      // once it's gone there is otherwise zero trace this ever happened, so
      // an admin has no way to see who tried to sign up and hit a wall
      // (2026-08-27, vendor request). Best-effort: a logging failure must
      // never block the actual account cleanup below.
      try {
        await FirebaseFirestore.instance.collection('failed_signups').addLogged({
          'deletedAuthUid': user.uid,
          'signupType': type.isEmpty ? 'email' : type,
          'attemptedEmail': emailEditingController.text.trim().toLowerCase(),
          'attemptedPhone': phoneNUmberEditingController.text.trim(),
          'countryCode': countryCodeEditingController.text,
          'reason': message,
          'createdAt': FieldValue.serverTimestamp(),
          // Firestore TTL policy (configured on the collection, not in code)
          // auto-deletes this doc 30 days after it's written - admin-only
          // tracking, not meant to accumulate indefinitely (2026-08-27).
          'ttlAt': Timestamp.fromDate(DateTime.now().toUtc().add(const Duration(days: 30))),
        }, '_abortOrphanedSignup:failed_signups');
      } catch (_) {}
      try {
        await user.delete();
      } catch (_) {
        // requires-recent-login or similar - fall back to at least signing
        // out locally rather than leaving a live session on a broken account.
        await auth.FirebaseAuth.instance.signOut();
      }
    }
    if (mounted) pushAndRemoveUntil(context, const LoginScreen());
  }

  signUp(BuildContext context) async {
    if (mounted) setState(() => _isBusy = true);
    ShowToastDialog.showLoader('Creating your account...');
    // Set right before showSuccess() below, on the one path that actually
    // reaches it - skips finally's plain dismiss so the success checkmark
    // isn't cut off the instant it appears (2026-08-27).
    var didShowSuccess = false;
    final nameParts = _splitFullName(fullNameEditingController.text.toString());
    // TEMPORARY [LOGIN-PERF] - timing instrumentation for the login/signup
    // speed investigation, matching email_login_screen.dart/otp_screen.dart.
    // Remove once done.
    final totalSw = Stopwatch()..start();
    try {
      if (type == "mobileNumber") {
        // Phone uniqueness for signup is already enforced server-side
        // (OtpVerifyController::verifyAndMint rejects a duplicate
        // phone+role before this screen is ever reached) - but email is
        // only collected here, so it still needs its own check.
        //
        // The conflict check, FCM token fetch, and referral lookup are all
        // independent of each other (none needs another's result, only
        // locally-available text field input) — run them concurrently
        // instead of paying for each strictly after the previous one
        // resolves. Explicit <dynamic> because NotificationService.getToken()
        // has no declared return type.
        final batchSw = Stopwatch()..start();
        final signupResults = await Future.wait<dynamic>([
          _findExistingCustomerConflict(
            email: emailEditingController.text,
            phoneNumber: phoneNUmberEditingController.text,
            countryCode: countryCodeEditingController.text,
          ),
          NotificationService.getToken(),
          FireStoreUtils.getReferralUserByCode(referralCodeEditingController.text),
        ]);
        debugPrint('[LOGIN-PERF] SIGNUP(phone) conflict+token+referral (parallel) — ${batchSw.elapsedMilliseconds}ms');
        final conflict = signupResults[0] as String?;
        final fcmToken = signupResults[1] as String;
        final referralUser = signupResults[2] as ReferralModel?;

        if (conflict != null) {
          await _abortOrphanedSignup(context, conflict);
          return;
        }

        // Registers this device as the account's authorized device the
        // moment it's created — without this, a brand-new account has no
        // device_id on file until its first subsequent login, leaving a
        // window where a second device could complete its own login-time
        // authorize() with nothing yet to conflict against.
        final deviceSessionSw = Stopwatch()..start();
        final sessionResult = await DeviceSessionService.authorize(fcmToken: fcmToken);
        debugPrint('[LOGIN-PERF] SIGNUP(phone) DeviceSessionService.authorize — ${deviceSessionSw.elapsedMilliseconds}ms');
        if (!sessionResult.allowed) {
          await _abortOrphanedSignup(context, sessionResult.message!);
          return;
        }

        userModel.firstName = nameParts['firstName']!;
        userModel.lastName = nameParts['lastName']!;
        userModel.email = emailEditingController.text.trim().toLowerCase();
        userModel.phoneNumber = phoneNUmberEditingController.text.trim();
        userModel.role = USER_ROLE_CUSTOMER;
        userModel.fcmToken = fcmToken;
        // Must be false (or absent) on this very first write - firestore.rules
        // rejects a self-created user doc with active: true (2026-08-18
        // hardening, to stop a client self-approving). ServiceListScreen/
        // LocationPermissionScreen already promote it to true themselves via
        // a separate update right after this, which the rules do allow -
        // this was the actual cause of every new signup silently failing to
        // write its Firestore profile (2026-08-27 fix).
        userModel.active = false;
        userModel.countryCode = countryCodeEditingController.text;
        userModel.createdAt = Timestamp.now();

        final referralAddSw = Stopwatch()..start();
        await FireStoreUtils.referralAdd(ReferralModel(
          id: userModel.userID,
          referralBy: referralUser?.id ?? '',
          referralCode: getReferralCode(),
        ));
        debugPrint('[LOGIN-PERF] SIGNUP(phone) referralAdd — ${referralAddSw.elapsedMilliseconds}ms');

        final updateUserSw = Stopwatch()..start();
        await FireStoreUtils.updateCurrentUser(userModel);
        debugPrint('[LOGIN-PERF] SIGNUP(phone) updateCurrentUser — ${updateUserSw.elapsedMilliseconds}ms');
        // Persist phone user ID so the session survives app restarts
        final signupPrefs = await SharedPreferences.getInstance();
        await signupPrefs.setString(PHONE_AUTH_USER_ID, userModel.userID);
        if (!mounted) return;
        didShowSuccess = true;
        ShowToastDialog.showSuccess('Account created!');
        debugPrint('[LOGIN-PERF] SIGNUP(phone) TOTAL (tap to navigate) — ${totalSw.elapsedMilliseconds}ms');
        if (userModel.shippingAddress != null &&
            userModel.shippingAddress!.isNotEmpty) {
          if (userModel.shippingAddress!
              .where((element) => element.isDefault == true)
              .isNotEmpty) {
            MyAppState.selectedPosotion = userModel.shippingAddress!
                .where((element) => element.isDefault == true)
                .single;
          } else {
            MyAppState.selectedPosotion = userModel.shippingAddress!.first;
          }
          debugPrint('[LOGIN-PERF] SIGNUP(phone) pushAndRemoveUntil(ServiceListScreen) — ${totalSw.elapsedMilliseconds}ms since tap');
          pushAndRemoveUntil(context, ServiceListScreen(user: userModel));
        } else {
          debugPrint('[LOGIN-PERF] SIGNUP(phone) pushAndRemoveUntil(LocationPermissionScreen) — ${totalSw.elapsedMilliseconds}ms since tap');
          pushAndRemoveUntil(context, LocationPermissionScreen());
        }
        return;
      }

      // Kick off the FCM token fetch immediately — it doesn't depend on the
      // conflict check, account creation, or anything else below, so let
      // it run concurrently with all of that instead of waiting until the
      // exact point it used to be requested.
      final fcmTokenFuture = NotificationService.getToken();

      final conflictSw = Stopwatch()..start();
      final conflict = await _findExistingCustomerConflict(
        email: emailEditingController.text,
        phoneNumber: phoneNUmberEditingController.text,
        countryCode: countryCodeEditingController.text,
      );
      debugPrint('[LOGIN-PERF] SIGNUP(email) _findExistingCustomerConflict — ${conflictSw.elapsedMilliseconds}ms');
      if (conflict != null) {
        ShowToastDialog.showToast(conflict);
        return;
      }

      final createUserSw = Stopwatch()..start();
      final credential =
          await auth.FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailEditingController.text.trim(),
        password: passwordEditingController.text.trim(),
      );
      debugPrint('[LOGIN-PERF] SIGNUP(email) createUserWithEmailAndPassword — ${createUserSw.elapsedMilliseconds}ms');
      if (credential.user == null) {
        await _abortOrphanedSignup(context, "Signup failed. Please try again.");
        return;
      }

      // Same registration-at-signup fix as the mobileNumber branch above —
      // see its comment for why this can't just wait for the first login.
      final fcmTokenSw = Stopwatch()..start();
      final fcmToken = await fcmTokenFuture;
      debugPrint('[LOGIN-PERF] SIGNUP(email) getToken (FCM, awaited here) — ${fcmTokenSw.elapsedMilliseconds}ms');
      final deviceSessionSw = Stopwatch()..start();
      final sessionResult = await DeviceSessionService.authorize(fcmToken: fcmToken);
      debugPrint('[LOGIN-PERF] SIGNUP(email) DeviceSessionService.authorize — ${deviceSessionSw.elapsedMilliseconds}ms');
      if (!sessionResult.allowed) {
        await _abortOrphanedSignup(context, sessionResult.message!);
        return;
      }

      // Also independent of everything else here — start both the moment
      // the account exists instead of waiting until right before each is
      // needed.
      final emailVerificationFuture = credential.user!.sendEmailVerification();
      final referralFuture = FireStoreUtils.getReferralUserByCode(
          referralCodeEditingController.text);

      userModel.userID = credential.user!.uid;
      userModel.firstName = nameParts['firstName']!;
      userModel.lastName = nameParts['lastName']!;
      userModel.email = emailEditingController.text.trim().toLowerCase();
      userModel.phoneNumber = phoneNUmberEditingController.text.trim();
      userModel.role = USER_ROLE_CUSTOMER;
      userModel.fcmToken = fcmToken;
      // Must be false (or absent) on this very first write - see the
      // identical comment on the phone branch above for why.
      userModel.active = false;
      userModel.countryCode = countryCodeEditingController.text;
      userModel.createdAt = Timestamp.now();

      final referralAddSw = Stopwatch()..start();
      final referralUser = await referralFuture;
      await FireStoreUtils.referralAdd(ReferralModel(
        id: FireStoreUtils.getCurrentUid(),
        referralBy: referralUser?.id ?? '',
        referralCode: getReferralCode(),
      ));
      debugPrint('[LOGIN-PERF] SIGNUP(email) referralFuture+referralAdd — ${referralAddSw.elapsedMilliseconds}ms');

      final updateUserSw = Stopwatch()..start();
      await FireStoreUtils.updateCurrentUser(userModel);
      debugPrint('[LOGIN-PERF] SIGNUP(email) updateCurrentUser — ${updateUserSw.elapsedMilliseconds}ms');

      final emailVerifySw = Stopwatch()..start();
      try {
        await emailVerificationFuture;
        debugPrint('[LOGIN-PERF] SIGNUP(email) sendEmailVerification — ${emailVerifySw.elapsedMilliseconds}ms');
      } catch (_) {}

      if (!mounted) return;
      didShowSuccess = true;
      ShowToastDialog.showSuccess('Account created!');
      debugPrint('[LOGIN-PERF] SIGNUP(email) TOTAL (tap to navigate) — ${totalSw.elapsedMilliseconds}ms');
      if (userModel.shippingAddress != null &&
          userModel.shippingAddress!.isNotEmpty) {
        if (userModel.shippingAddress!
            .where((element) => element.isDefault == true)
            .isNotEmpty) {
          MyAppState.selectedPosotion = userModel.shippingAddress!
              .where((element) => element.isDefault == true)
              .single;
        } else {
          MyAppState.selectedPosotion = userModel.shippingAddress!.first;
        }
        debugPrint('[LOGIN-PERF] SIGNUP(email) pushAndRemoveUntil(ServiceListScreen) — ${totalSw.elapsedMilliseconds}ms since tap');
        pushAndRemoveUntil(context, ServiceListScreen(user: userModel));
      } else {
        debugPrint('[LOGIN-PERF] SIGNUP(email) pushAndRemoveUntil(LocationPermissionScreen) — ${totalSw.elapsedMilliseconds}ms since tap');
        pushAndRemoveUntil(context, LocationPermissionScreen());
      }
    } on auth.FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'weak-password':
          ShowToastDialog.showToast(
              "Password is too weak. Use at least 8 characters with letters and numbers.");
          break;
        case 'email-already-in-use':
          ShowToastDialog.showToast(
              'This email is already linked to an account.');
          break;
        case 'invalid-email':
          ShowToastDialog.showToast("Please enter a valid email address.");
          break;
        case 'network-request-failed':
          ShowToastDialog.showToast(
              'Unable to connect right now. Please try again.');
          break;
        default:
          ShowToastDialog.showToast(e.message ?? "Signup failed. Please try again.");
      }
    } catch (_) {
      // Any exception this late (e.g. the Firestore profile write failing
      // right after a successful authorize() call) means signup did not
      // actually complete - deleting the Auth account (2026-08-27, see
      // _abortOrphanedSignup) rather than just signing out means the
      // customer can immediately retry with the same email/phone instead
      // of being permanently stuck.
      await _abortOrphanedSignup(context, "Something went wrong. Please try again.");
    } finally {
      // Skip the plain dismiss on the success path - showSuccess() above
      // already transitions the same overlay to a checkmark and dismisses
      // itself on its own timer; closeLoader() here would cut that off
      // before the user ever sees it.
      if (!didShowSuccess) ShowToastDialog.closeLoader();
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0620),
      body: AuthBackground(
        child: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: Column(
            children: [
              AuthHeader(
                // Phone is already verified by the time this shows - framed
                // as completing a profile, not still "signing up"
                // (2026-08-27, better first-run experience).
                title: (type == "mobileNumber" ? 'Set Your Profile' : 'Create Your Account').tr,
                subtitle: (type == "mobileNumber"
                        ? 'Your number is verified - just a couple more details to get started.'
                        : 'Join QuickDash and start enjoying faster dining experiences.')
                    .tr,
                showBackButton: true,
              ),
              Expanded(
                child: AuthFormCard(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: _buildEmailForm(context),
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

  Widget _buildEmailForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthFieldLabel(text: 'Full Name'.tr),
        AuthTextField(
          controller: fullNameEditingController,
          hint: 'Enter Full Name'.tr,
          iconPath: 'assets/icons/ic_user.svg',
          maxLength: 50,
        ),
        const SizedBox(height: 16),
        AuthFieldLabel(text: 'Email Address'.tr),
        AuthTextField(
          controller: emailEditingController,
          hint: 'Enter Email Address'.tr,
          iconPath: 'assets/icons/ic_mail.svg',
          keyboardType: TextInputType.emailAddress,
          textCapitalization: TextCapitalization.none,
          maxLength: 254,
          onChanged: _onEmailChangedInline,
        ),
        _buildInlineFieldStatus(checking: _checkingEmail, error: _emailInlineError),
        const SizedBox(height: 16),
        AuthFieldLabel(text: 'Phone Number'.tr),
        AuthTextField(
          controller: phoneNUmberEditingController,
          hint: 'Enter Phone Number'.tr,
          enabled: type != "mobileNumber",
          keyboardType: const TextInputType.numberWithOptions(
              signed: true, decimal: true),
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(phoneMaxLength),
          ],
          onChanged: _onPhoneChangedInline,
          prefixWidget: CountryCodePicker(
            enabled: type != "mobileNumber",
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
            comparator: (a, b) =>
                b.name!.compareTo(a.name.toString()),
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
        if (type != "mobileNumber")
          _buildInlineFieldStatus(checking: _checkingPhone, error: _phoneInlineError),
        if (type != "mobileNumber") ...[
          const SizedBox(height: 16),
          AuthFieldLabel(text: 'Password'.tr),
          AuthTextField(
            controller: passwordEditingController,
            hint: 'Enter Password'.tr,
            iconPath: 'assets/icons/ic_lock.svg',
            obscureText: passwordVisible,
            showVisibility: true,
            isVisible: passwordVisible,
            onToggle: () =>
                setState(() => passwordVisible = !passwordVisible),
          ),
          const SizedBox(height: 16),
          AuthFieldLabel(text: 'Confirm Password'.tr),
          AuthTextField(
            controller: conformPasswordEditingController,
            hint: 'Enter Confirm Password'.tr,
            iconPath: 'assets/icons/ic_lock.svg',
            obscureText: conformPasswordVisible,
            showVisibility: true,
            isVisible: conformPasswordVisible,
            onToggle: () => setState(() =>
                conformPasswordVisible = !conformPasswordVisible),
          ),
        ],
        const SizedBox(height: 16),
        AuthFieldLabel(text: 'Referral Code (Optional)'.tr),
        AuthTextField(
          controller: referralCodeEditingController,
          hint: 'Enter Referral Code'.tr,
          iconPath: 'assets/icons/ic_gift.svg',
          textCapitalization: TextCapitalization.characters,
        ),
        const SizedBox(height: 24),
        AuthPrimaryButton(
          label: (type == "mobileNumber" ? 'Continue' : 'Sign Up').tr,
          onTap: () {
            if (_checkingEmail || _checkingPhone) {
              ShowToastDialog.showToast('Still checking your details, please wait a moment.'.tr);
              return;
            }
            if (_emailInlineError != null) {
              ShowToastDialog.showToast(_emailInlineError!);
              return;
            }
            if (_phoneInlineError != null) {
              ShowToastDialog.showToast(_phoneInlineError!);
              return;
            }
            if (_validateSignupForm()) {
              signUpWithEmailAndPassword(context);
            }
          },
        ),
        // Doesn't apply once already on the phone flow's own profile step -
        // "sign up with phone number" makes no sense to offer here
        // (2026-08-27 fix, found while reworking this screen for phone
        // signup).
        if (type != "mobileNumber") ...[
          const SizedBox(height: 20),
          const AuthOrDivider(),
          const SizedBox(height: 16),
          Center(
            child: GestureDetector(
              onTap: () => push(context, const PhoneNumberScreen(isSignup: true)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Sign up with Phone Number'.tr,
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
        const SizedBox(height: 8),
      ],
    );
  }

  // "Checking…" / error text under an email or phone field, or nothing at
  // all when there's no status to show (2026-08-27) - kept as a fixed-height
  // slot below the field rather than inside AuthTextField itself, since that
  // shared widget doesn't have an error/suffix slot and is used elsewhere
  // in the app too.
  Widget _buildInlineFieldStatus({required bool checking, required String? error}) {
    if (!checking && error == null) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: checking
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                    width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white54)),
                const SizedBox(width: 6),
                Text('Checking…'.tr, style: const TextStyle(fontSize: 11, color: Colors.white54)),
              ],
            )
          : Text(error!, style: const TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.w600)),
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
                text: 'Already have an account?  '.tr,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontFamily: AppThemeData.regular,
                  fontSize: 14,
                ),
              ),
              TextSpan(
                recognizer: TapGestureRecognizer()
                  ..onTap = () => pushAndRemoveUntil(
                      context, const LoginScreen()),
                text: 'Login'.tr,
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
