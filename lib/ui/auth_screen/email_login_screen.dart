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
import 'package:emartconsumer/ui/auth_screen/signup_screen.dart';
import 'package:emartconsumer/ui/forgot_password_screen/forgot_password_screen.dart';
import 'package:emartconsumer/ui/location_permission_screen.dart';
import 'package:emartconsumer/ui/service_list_screen.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/gestures.dart';
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
    try {
      final credential = await auth.FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      if (credential.user == null) {
        ShowToastDialog.showToast('Login failed. Please try again.');
        return;
      }

      User? userModel = await FireStoreUtils.getUserProfile(credential.user!.uid);
      if (userModel == null) {
        ShowToastDialog.showToast('No account found. Please sign up to create an account.');
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
      if (userModel.shippingAddress != null && userModel.shippingAddress!.isNotEmpty) {
        if (userModel.shippingAddress!.where((e) => e.isDefault == true).isNotEmpty) {
          MyAppState.selectedPosotion =
              userModel.shippingAddress!.where((e) => e.isDefault == true).single;
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
      ShowToastDialog.closeLoader();
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
                  color: Colors.white.withValues(alpha: 0.65),
                  fontFamily: AppThemeData.regular,
                  fontSize: 14,
                ),
              ),
              TextSpan(
                recognizer: TapGestureRecognizer()
                  ..onTap = () => push(context, const SignupScreen()),
                text: 'Create one'.tr,
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
