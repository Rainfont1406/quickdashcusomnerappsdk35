import 'dart:async';
import 'dart:io';

import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/device_session_service.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/notification_service.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/auth_screen/auth_widgets.dart';
import 'package:emartconsumer/ui/auth_screen/signup_screen.dart';
import 'package:emartconsumer/ui/forgot_password_screen/forgot_password_screen.dart';
import 'package:emartconsumer/ui/location_permission_screen.dart';
import 'package:emartconsumer/ui/service_list_screen.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class EmailLoginScreen extends StatefulWidget {
  const EmailLoginScreen({super.key});

  @override
  State<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends State<EmailLoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _passwordVisible = true;
  bool _isBusy = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final emailError = validateEmail(email);
    if (email.isEmpty || emailError != null) {
      ShowToastDialog.showToast(emailError ?? 'Please enter a valid email address.'.tr);
      return;
    }
    if (password.isEmpty) {
      ShowToastDialog.showToast('Please enter your password.'.tr);
      return;
    }
    if (_isBusy) return;
    if (mounted) setState(() => _isBusy = true);
    ShowToastDialog.showLoader('Verifying your account...');
    // Set right before showSuccess() below - skips finally's plain dismiss
    // so the success checkmark isn't cut off the instant it appears
    // (2026-08-27).
    var didShowSuccess = false;
    // TEMPORARY [LOGIN-PERF] - timing instrumentation for the login-speed
    // investigation. Remove once done.
    final totalSw = Stopwatch()..start();
    try {
      final signInSw = Stopwatch()..start();
      // 2026-10-30: a customer with its OWN password (different from the same
      // email's vendor password) is decided by that password alone.
      final roleResult = await FireStoreUtils.roleLogin(email, password);
      if (roleResult is RoleAuthError) {
        ShowToastDialog.showToast(roleResult.message);
        return;
      }
      final auth.User? fbUser = roleResult is auth.User
          ? roleResult
          : (await auth.FirebaseAuth.instance
                  .signInWithEmailAndPassword(email: email, password: password))
              .user;
      debugPrint('[LOGIN-PERF] signInWithEmailAndPassword — ${signInSw.elapsedMilliseconds}ms');
      if (fbUser == null) {
        ShowToastDialog.showToast('Login failed. Please try again.');
        return;
      }

      // getUserProfile and the FCM token fetch are independent of each other
      // (the token fetch needs no data from the user profile) — run them
      // concurrently instead of paying for the token fetch strictly after
      // the Firestore lookup resolves. Same fix as hasFinishedOnBoarding()
      // in main.dart's session-restore path. Explicit <dynamic> because
      // NotificationService.getToken() has no declared return type.
      // Individually timed (temporary diagnostic) — still run concurrently
      // via Future.wait, just wrapped so each leg's own completion time is
      // visible instead of only the combined parallel total.
      final profileSw = Stopwatch()..start();
      final profileFuture =
          FireStoreUtils.getUserProfile(fbUser.uid).then((r) {
        debugPrint('[LOGIN-PERF] getUserProfile — ${profileSw.elapsedMilliseconds}ms');
        return r;
      });
      final tokenSw = Stopwatch()..start();
      final tokenFuture = NotificationService.getToken().then((r) {
        debugPrint('[LOGIN-PERF] getToken (FCM) — ${tokenSw.elapsedMilliseconds}ms');
        return r;
      });
      final loginResults = await Future.wait<dynamic>([profileFuture, tokenFuture]);
      debugPrint('[LOGIN-PERF] getUserProfile+getToken (parallel) — ${profileSw.elapsedMilliseconds}ms');
      User? userModel = loginResults[0] as User?;
      final fcmToken = loginResults[1] as String;
      if (userModel == null) {
        ShowToastDialog.showToast('No account found. Please sign up to create an account.');
        await auth.FirebaseAuth.instance.signOut();
        return;
      }

      if (userModel.role != USER_ROLE_CUSTOMER) {
        // A vendor/driver login may also own a customer account (separate uid,
        // issued by the server) - switch to it if it exists.
        final linked = await FireStoreUtils.linkCustomerRole();
        final linkedProfile = linked == null ? null : await FireStoreUtils.getUserProfile(linked.uid);
        if (linkedProfile == null || linkedProfile.role != USER_ROLE_CUSTOMER) {
          ShowToastDialog.showToast(linked == null
              ? 'This account is not registered as a customer. Please use the correct QuickDash app.'
              : 'No customer account for this email yet. Tap "Create one" to add it.');
          await auth.FirebaseAuth.instance.signOut();
          return;
        }
        userModel = linkedProfile;
      }

      // Never-finished signup (inactive, no location yet): resume, don't block.
      if (userModel.isUnfinishedSignup) userModel.active = true;

      if (userModel.active != true) {
        ShowToastDialog.showToast(
            'Your account is temporarily restricted. Please contact support.');
        await auth.FirebaseAuth.instance.signOut();
        return;
      }

      final deviceSessionSw = Stopwatch()..start();
      final sessionResult = await DeviceSessionService.authorize(fcmToken: fcmToken);
      debugPrint('[LOGIN-PERF] DeviceSessionService.authorize — ${deviceSessionSw.elapsedMilliseconds}ms');
      if (!sessionResult.allowed) {
        ShowToastDialog.showToast(sessionResult.message!);
        return;
      }

      // Never overwrite the saved token with an empty one (push unavailable on this phone).
      if (fcmToken.isNotEmpty) userModel.fcmToken = fcmToken;
      if (fcmToken.isEmpty) NotificationService.fillTokenLater(userModel.userID);
      // Fire-and-forget: navigation doesn't need to wait on this write's
      // round trip — MyAppState/userModel below already reflect the update
      // in memory. Same fix as hasFinishedOnBoarding() in main.dart.
      unawaited(FireStoreUtils.updateCurrentUser(userModel));
      if (!mounted) return;
      didShowSuccess = true;
      ShowToastDialog.showSuccess('Login successful!');
      debugPrint('[LOGIN-PERF] TOTAL (tap to navigate) — ${totalSw.elapsedMilliseconds}ms');
      if (!userModel.needsLocation) {
        if (userModel.shippingAddress!.where((e) => e.isDefault == true).isNotEmpty) {
          MyAppState.selectedPosotion =
              userModel.shippingAddress!.where((e) => e.isDefault == true).single;
        } else {
          MyAppState.selectedPosotion = userModel.shippingAddress!.first;
        }
        // TEMPORARY [LOGIN-PERF] - marks the exact handoff moment so the
        // gap between here and ServiceListScreen's own initState ENTER log
        // isolates pure navigation/widget-creation overhead from the async
        // work that happens inside ServiceListScreen itself.
        debugPrint('[LOGIN-PERF] pushAndRemoveUntil(ServiceListScreen) — ${totalSw.elapsedMilliseconds}ms since tap');
        pushAndRemoveUntil(context, ServiceListScreen(user: userModel));
      } else {
        debugPrint('[LOGIN-PERF] pushAndRemoveUntil(LocationPermissionScreen) — ${totalSw.elapsedMilliseconds}ms since tap');
        pushAndRemoveUntil(context, LocationPermissionScreen());
      }
    } on auth.FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
          ShowToastDialog.showToast('No account found with this email. Please sign up first.');
          break;
        case 'wrong-password':
        case 'invalid-credential':
          ShowToastDialog.showToast('Incorrect email or password. Please try again.');
          break;
        case 'invalid-email':
          ShowToastDialog.showToast('Please enter a valid email address.');
          break;
        case 'user-disabled':
          ShowToastDialog.showToast('Your account has been disabled. Please contact support.');
          break;
        case 'too-many-requests':
          ShowToastDialog.showToast(
              'Too many failed attempts. Please try again later or reset your password.');
          break;
        case 'network-request-failed':
          ShowToastDialog.showToast('Unable to connect right now. Please try again.');
          break;
        default:
          ShowToastDialog.showToast(e.message ?? 'Login failed. Please try again.');
      }
    } catch (_) {
      ShowToastDialog.showToast('Something went wrong. Please try again.');
    } finally {
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
                title: 'Sign In with Email'.tr,
                subtitle: 'Enter your credentials to continue.'.tr,
                showBackButton: true,
              ),
              Expanded(
                child: AuthFormCard(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(24, 28, 24, Platform.isAndroid ? 24 : 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AuthFieldLabel(text: 'Email Address'.tr),
                      AuthTextField(
                        controller: _emailCtrl,
                        hint: 'Enter email address'.tr,
                        iconPath: 'assets/icons/ic_mail.svg',
                        keyboardType: TextInputType.emailAddress,
                        textCapitalization: TextCapitalization.none,
                        maxLength: 254,
                      ),
                      const SizedBox(height: 20),
                      AuthFieldLabel(text: 'Password'.tr),
                      AuthTextField(
                        controller: _passwordCtrl,
                        hint: 'Enter password'.tr,
                        iconPath: 'assets/icons/ic_lock.svg',
                        obscureText: _passwordVisible,
                        showVisibility: true,
                        isVisible: _passwordVisible,
                        onToggle: () =>
                            setState(() => _passwordVisible = !_passwordVisible),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () => push(context, ForgotPasswordScreen()),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              'Forgot Password?'.tr,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.70),
                                fontSize: 13,
                                fontFamily: AppThemeData.medium,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      AuthPrimaryButton(label: 'Login'.tr, onTap: _login),
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
        // Clear the system navigation bar: the app draws edge to edge
        // (Android 15), so a fixed gap put the bar's back button over
        // this text. padding.bottom drops to 0 while the keyboard is up.
        bottom: MediaQuery.paddingOf(context).bottom + 16,
        top: 4,
      ),
      // Whole line is the tap target, min 48px - see login_screen.dart.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => push(context, const SignupScreen()),
        child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: double.infinity),
        child: Center(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: "Don't have an account?  ".tr,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontFamily: AppThemeData.regular,
                  fontSize: 14,
                ),
              ),
              TextSpan(
                text: 'Create one'.tr,
                style: const TextStyle(
                  color: AppThemeData.primary400,
                  fontFamily: AppThemeData.bold,
                  // Bumped from 14 (2026-08-27) - see login_screen.dart's
                  // identical fix for why.
                  fontSize: 17,
                ),
              ),
            ],
          ),
        ),
        ),
        ),
      ),
    );
  }
}
