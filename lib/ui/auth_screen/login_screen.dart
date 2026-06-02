import 'dart:io';

import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/notification_service.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/auth_screen/auth_widgets.dart';
import 'package:emartconsumer/ui/auth_screen/phone_number_screen.dart';
import 'package:emartconsumer/ui/auth_screen/signup_screen.dart';
import 'package:emartconsumer/ui/forgot_password_screen/forgot_password_screen.dart';
import 'package:emartconsumer/ui/location_permission_screen.dart';
import 'package:emartconsumer/ui/service_list_screen.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class LoginScreen extends StatefulWidget {
  // kept for backwards-compat; callers using startOnSignup:true will land on SignupScreen
  final bool startOnSignup;
  const LoginScreen({super.key, this.startOnSignup = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginEmailCtrl = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();
  bool _loginPasswordVisible = true;
  bool _showEmailForm = false;
  bool _isBusy = false;

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
    _loginEmailCtrl.dispose();
    _loginPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _loginEmailCtrl.text.trim();
    final password = _loginPasswordCtrl.text.trim();
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
    try {
      final credential = await auth.FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      if (credential.user == null) {
        ShowToastDialog.showToast('Login failed. Please try again.');
        return;
      }

      User? userModel =
          await FireStoreUtils.getUserProfile(credential.user!.uid);
      if (userModel == null) {
        ShowToastDialog.showToast(
            'No account found. Please sign up to create an account.');
        await auth.FirebaseAuth.instance.signOut();
        return;
      }

      if (userModel.role != USER_ROLE_CUSTOMER) {
        ShowToastDialog.showToast(
            'This account is not registered as a customer. Please use the correct QuickDash app.');
        await auth.FirebaseAuth.instance.signOut();
        return;
      }

      if (userModel.active != true) {
        ShowToastDialog.showToast(
            'Your account is temporarily restricted. Please contact support.');
        await auth.FirebaseAuth.instance.signOut();
        return;
      }

      userModel.fcmToken = await NotificationService.getToken();
      await FireStoreUtils.updateCurrentUser(userModel);
      if (!mounted) return;
      if (userModel.shippingAddress != null &&
          userModel.shippingAddress!.isNotEmpty) {
        if (userModel.shippingAddress!
            .where((e) => e.isDefault == true)
            .isNotEmpty) {
          MyAppState.selectedPosotion = userModel.shippingAddress!
              .where((e) => e.isDefault == true)
              .single;
        } else {
          MyAppState.selectedPosotion = userModel.shippingAddress!.first;
        }
        pushAndRemoveUntil(context, ServiceListScreen());
      } else {
        pushAndRemoveUntil(context, LocationPermissionScreen());
      }
    } on auth.FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
          ShowToastDialog.showToast(
              'No account found with this email. Please sign up first.');
          break;
        case 'wrong-password':
        case 'invalid-credential':
          ShowToastDialog.showToast(
              'Incorrect email or password. Please try again.');
          break;
        case 'invalid-email':
          ShowToastDialog.showToast('Please enter a valid email address.');
          break;
        case 'user-disabled':
          ShowToastDialog.showToast(
              'Your account has been disabled. Please contact support.');
          break;
        case 'too-many-requests':
          ShowToastDialog.showToast(
              'Too many failed attempts. Please try again later or reset your password.');
          break;
        case 'network-request-failed':
          ShowToastDialog.showToast(
              'Unable to connect right now. Please try again.');
          break;
        default:
          ShowToastDialog.showToast(e.message ?? 'Login failed. Please try again.');
      }
    } catch (_) {
      ShowToastDialog.showToast('Something went wrong. Please try again.');
    } finally {
      ShowToastDialog.closeLoader();
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDarkMode(context)
          ? AppThemeData.surfaceDark
          : const Color(0xFFF5F6FA),
      body: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Column(
          children: [
            AuthHeader(
              title: 'Welcome Back to QuickDash'.tr,
              tagline:
                  'Live restaurant menus. Direct ordering. No paper menus. Zero waiting time dining with QuickDash.',
              subtitle: 'Sign in to continue your seamless dining experience.'.tr,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    24, 28, 24, Platform.isAndroid ? 24 : 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AuthOutlinedButton(
                      label: 'Continue with Phone Number'.tr,
                      iconPath: 'assets/icons/ic_phone.svg',
                      onTap: () => push(context, PhoneNumberScreen()),
                    ),
                    const SizedBox(height: 16),
                    AuthOutlinedButton(
                      label: 'Continue with Email Address'.tr,
                      iconPath: 'assets/icons/ic_mail.svg',
                      onTap: () {
                        setState(() => _showEmailForm = !_showEmailForm);
                      },
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: _showEmailForm
                          ? _buildEmailForm(context)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const AuthOrDivider(),
        const SizedBox(height: 24),
        AuthFieldLabel(text: 'Email Address'.tr),
        AuthTextField(
          controller: _loginEmailCtrl,
          hint: 'Enter email address'.tr,
          iconPath: 'assets/icons/ic_mail.svg',
          keyboardType: TextInputType.emailAddress,
          textCapitalization: TextCapitalization.none,
        ),
        const SizedBox(height: 20),
        AuthFieldLabel(text: 'Password'.tr),
        AuthTextField(
          controller: _loginPasswordCtrl,
          hint: 'Enter password'.tr,
          iconPath: 'assets/icons/ic_lock.svg',
          obscureText: _loginPasswordVisible,
          showVisibility: true,
          isVisible: _loginPasswordVisible,
          onToggle: () =>
              setState(() => _loginPasswordVisible = !_loginPasswordVisible),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () => push(context, ForgotPasswordScreen()),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Forgot Password?'.tr,
                style: const TextStyle(
                  color: AppThemeData.secondary300,
                  fontSize: 13,
                  fontFamily: AppThemeData.medium,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        AuthPrimaryButton(label: 'Login'.tr, onTap: _login),
        const SizedBox(height: 8),
      ],
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
                text: "Don't have an account?  ".tr,
                style: TextStyle(
                  color: isDarkMode(context)
                      ? AppThemeData.grey400
                      : AppThemeData.grey500,
                  fontFamily: AppThemeData.regular,
                  fontSize: 14,
                ),
              ),
              TextSpan(
                recognizer: TapGestureRecognizer()
                  ..onTap = () => push(context, const SignupScreen()),
                text: 'Create one'.tr,
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
    );
  }
}
