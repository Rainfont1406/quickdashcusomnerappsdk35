import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/model/referral_model.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/notification_service.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/auth_screen/auth_widgets.dart';
import 'package:emartconsumer/ui/auth_screen/phone_number_screen.dart';
import 'package:emartconsumer/ui/forgot_password_screen/forgot_password_screen.dart';
import 'package:emartconsumer/ui/location_permission_screen.dart';
import 'package:emartconsumer/ui/service_list_screen.dart';
import 'package:emartconsumer/utils/country_phone_length.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';

class LoginScreen extends StatefulWidget {
  final bool startOnSignup;
  const LoginScreen({super.key, this.startOnSignup = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late bool _isLogin;

  // Login controllers
  final _loginEmailCtrl = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();
  bool _loginPasswordVisible = true;

  // Signup controllers
  final _signupFullNameCtrl = TextEditingController();
  final _signupEmailCtrl = TextEditingController();
  final _signupPhoneCtrl = TextEditingController();
  final _signupCountryCodeCtrl = TextEditingController();
  final _signupPasswordCtrl = TextEditingController();
  final _signupConfirmPasswordCtrl = TextEditingController();
  final _signupReferralCtrl = TextEditingController();
  bool _signupPasswordVisible = true;
  bool _signupConfirmPasswordVisible = true;
  int _phoneMaxLength = 10;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _isLogin = !widget.startOnSignup;
    _signupCountryCodeCtrl.text = '+91';
    _updatePhoneMaxLength();
  }

  @override
  void dispose() {
    _loginEmailCtrl.dispose();
    _loginPasswordCtrl.dispose();
    _signupFullNameCtrl.dispose();
    _signupEmailCtrl.dispose();
    _signupPhoneCtrl.dispose();
    _signupCountryCodeCtrl.dispose();
    _signupPasswordCtrl.dispose();
    _signupConfirmPasswordCtrl.dispose();
    _signupReferralCtrl.dispose();
    super.dispose();
  }

  void _switchTab(bool isLogin) {
    if (_isLogin == isLogin) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _isLogin = isLogin);
  }

  // ── Signup helpers ─────────────────────────────────────────────────

  void _updatePhoneMaxLength() {
    setState(() {
      _phoneMaxLength =
          CountryPhoneLength.getMaxLength(_signupCountryCodeCtrl.text);
    });
  }

  bool _isPhoneNumberValid() => CountryPhoneLength.isValidLength(
        _signupCountryCodeCtrl.text,
        _signupPhoneCtrl.text,
      );

  Map<String, String> _splitFullName(String fullName) {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return {'firstName': '', 'lastName': ''};
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) return {'firstName': parts[0], 'lastName': ''};
    return {'firstName': parts[0], 'lastName': parts.sublist(1).join(' ')};
  }

  bool _validateSignupForm() {
    final fullName = _signupFullNameCtrl.text.trim();
    final email = _signupEmailCtrl.text.trim();
    final phone = _signupPhoneCtrl.text.trim();
    final password = _signupPasswordCtrl.text.trim();
    final confirm = _signupConfirmPasswordCtrl.text.trim();
    final emailError = validateEmail(email);

    if (fullName.isEmpty) {
      ShowToastDialog.showToast('Please enter full name'.tr);
      return false;
    }
    if (email.isEmpty || emailError != null) {
      ShowToastDialog.showToast(emailError ?? 'Please enter valid email'.tr);
      return false;
    }
    if (phone.isEmpty) {
      ShowToastDialog.showToast('Please enter valid phone number'.tr);
      return false;
    }
    if (!_isPhoneNumberValid()) {
      ShowToastDialog.showToast(
          CountryPhoneLength.getValidationMessage(_signupCountryCodeCtrl.text));
      return false;
    }
    if (password.isEmpty) {
      ShowToastDialog.showToast('Please enter password'.tr);
      return false;
    }
    if (password.length < 6) {
      ShowToastDialog.showToast('Please enter minimum 6 digit password'.tr);
      return false;
    }
    if (confirm.isEmpty) {
      ShowToastDialog.showToast('Please enter confirm password'.tr);
      return false;
    }
    if (password != confirm) {
      ShowToastDialog.showToast("Password and Confirm password doesn't match".tr);
      return false;
    }
    return true;
  }

  Future<void> _signUp() async {
    if (_isBusy) return;
    final referral = _signupReferralCtrl.text.trim();
    if (referral.isNotEmpty) {
      final valid =
          await FireStoreUtils.checkReferralCodeValidOrNot(referral);
      if (valid != true) {
        ShowToastDialog.showToast('Referral code is invalid. Please check and try again.');
        return;
      }
    }
    await _doSignUp();
  }

  Future<void> _doSignUp() async {
    if (mounted) setState(() => _isBusy = true);
    ShowToastDialog.showLoader('Please wait'.tr);
    final nameParts = _splitFullName(_signupFullNameCtrl.text);
    try {
      // Pre-check: is this phone number already registered as a customer?
      final phoneSnap = await FirebaseFirestore.instance
          .collection(USERS)
          .where('phoneNumber', isEqualTo: _signupPhoneCtrl.text.trim())
          .get();
      final phoneConflict = phoneSnap.docs.any((doc) {
        final data = doc.data();
        return data['role'] == USER_ROLE_CUSTOMER &&
            (data['countryCode'] as String? ?? '') == _signupCountryCodeCtrl.text;
      });
      if (phoneConflict) {
        ShowToastDialog.showToast(
            'An account already exists with this phone number. Please login to continue.');
        return;
      }

      final credential = await auth.FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: _signupEmailCtrl.text.trim(),
        password: _signupPasswordCtrl.text.trim(),
      );
      if (credential.user == null) {
        ShowToastDialog.showToast('Signup failed. Please try again.');
        return;
      }

      User userModel = User();
      userModel.userID = credential.user!.uid;
      userModel.firstName = nameParts['firstName']!;
      userModel.lastName = nameParts['lastName']!;
      userModel.email = _signupEmailCtrl.text.trim().toLowerCase();
      userModel.phoneNumber = _signupPhoneCtrl.text.trim();
      userModel.role = USER_ROLE_CUSTOMER;
      userModel.fcmToken = await NotificationService.getToken();
      userModel.active = true;
      userModel.countryCode = _signupCountryCodeCtrl.text;
      userModel.createdAt = Timestamp.now();

      final referralUser = await FireStoreUtils.getReferralUserByCode(
          _signupReferralCtrl.text);
      await FireStoreUtils.referralAdd(ReferralModel(
        id: FireStoreUtils.getCurrentUid(),
        referralBy: referralUser?.id ?? '',
        referralCode: getReferralCode(),
      ));
      await FireStoreUtils.updateCurrentUser(userModel);

      try {
        await credential.user!.sendEmailVerification();
      } catch (_) {}

      if (!mounted) return;
      ShowToastDialog.showToast('Account created successfully! Welcome to QuickDash.');
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
        case 'weak-password':
          ShowToastDialog.showToast(
              'Password is too weak. Use at least 8 characters with letters and numbers.');
          break;
        case 'email-already-in-use':
          ShowToastDialog.showToast(
              'An account already exists with this email. Please login to continue.');
          break;
        case 'invalid-email':
          ShowToastDialog.showToast('Please enter a valid email address.');
          break;
        case 'network-request-failed':
          ShowToastDialog.showToast(
              'Network error. Please check your internet connection and try again.');
          break;
        default:
          ShowToastDialog.showToast(e.message ?? 'Signup failed. Please try again.');
      }
    } catch (_) {
      ShowToastDialog.showToast('Something went wrong. Please try again.');
    } finally {
      ShowToastDialog.closeLoader();
      if (mounted) setState(() => _isBusy = false);
    }
  }

  // ── Login helpers ──────────────────────────────────────────────────

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
    ShowToastDialog.showLoader('Please wait'.tr);
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
            'Your account has been deactivated. Please contact support for assistance.');
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
              .where ((e) => e.isDefault == true)
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
              'Network error. Please check your internet connection and try again.');
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

  // ── Build ──────────────────────────────────────────────────────────

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
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    24, 28, 24, Platform.isAndroid ? 24 : 40),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                  child: _isLogin
                      ? _buildLoginForm(context)
                      : _buildSignupForm(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
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
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: logo + skip
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(6),
                        child: Image.asset(
                          'assets/images/app_logo_new.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'QuickDash',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontFamily: AppThemeData.bold,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () async {
                      final permission =
                          await Geolocator.checkPermission();
                      if (!mounted) return;
                      if (permission == LocationPermission.always ||
                          permission == LocationPermission.whileInUse) {
                        if (MyAppState.selectedPosotion.location == null) {
                          pushAndRemoveUntil(
                              context, LocationPermissionScreen());
                        } else {
                          pushAndRemoveUntil(context, ServiceListScreen());
                        }
                      } else {
                        pushAndRemoveUntil(
                            context, LocationPermissionScreen());
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Skip'.tr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontFamily: AppThemeData.medium,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // Dynamic title
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Column(
                  key: ValueKey(_isLogin),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isLogin ? 'Welcome Back!'.tr : 'Create Account'.tr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontFamily: AppThemeData.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isLogin
                          ? 'Sign in to your account'.tr
                          : 'Join QuickDash today'.tr,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                        fontFamily: AppThemeData.regular,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Tab toggle pill
              _buildTabToggle(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabToggle() {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _tabButton('Login'.tr, isLoginTab: true),
          _tabButton('Sign Up'.tr, isLoginTab: false),
        ],
      ),
    );
  }

  Widget _tabButton(String label, {required bool isLoginTab}) {
    final selected = _isLogin == isLoginTab;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchTab(isLoginTab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? AppThemeData.primary500
                  : Colors.white.withValues(alpha: 0.85),
              fontFamily:
                  selected ? AppThemeData.semiBold : AppThemeData.medium,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  // ── Login form ─────────────────────────────────────────────────────

  Widget _buildLoginForm(BuildContext context) {
    return Column(
      key: const ValueKey('login'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        const SizedBox(height: 28),
        const AuthOrDivider(),
        const SizedBox(height: 20),
        AuthOutlinedButton(
          label: 'Continue with Mobile Number'.tr,
          iconPath: 'assets/icons/ic_phone.svg',
          onTap: () => push(context, PhoneNumberScreen()),
        ),
      ],
    );
  }

  // ── Signup form ────────────────────────────────────────────────────

  Widget _buildSignupForm(BuildContext context) {
    return Column(
      key: const ValueKey('signup'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthFieldLabel(text: 'Full Name'.tr),
        AuthTextField(
          controller: _signupFullNameCtrl,
          hint: 'Enter Full Name'.tr,
          iconPath: 'assets/icons/ic_user.svg',
        ),
        const SizedBox(height: 16),
        AuthFieldLabel(text: 'Email Address'.tr),
        AuthTextField(
          controller: _signupEmailCtrl,
          hint: 'Enter Email Address'.tr,
          iconPath: 'assets/icons/ic_mail.svg',
          keyboardType: TextInputType.emailAddress,
          textCapitalization: TextCapitalization.none,
        ),
        const SizedBox(height: 16),
        AuthFieldLabel(text: 'Phone Number'.tr),
        AuthTextField(
          controller: _signupPhoneCtrl,
          hint: 'Enter Phone Number'.tr,
          keyboardType: const TextInputType.numberWithOptions(
              signed: true, decimal: true),
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(_phoneMaxLength),
          ],
          prefixWidget: CountryCodePicker(
            onChanged: (value) {
              _signupCountryCodeCtrl.text = value.dialCode.toString();
              _updatePhoneMaxLength();
            },
            dialogTextStyle: TextStyle(
              color: isDarkMode(context)
                  ? AppThemeData.grey50
                  : AppThemeData.grey900,
              fontWeight: FontWeight.w500,
              fontFamily: AppThemeData.medium,
            ),
            dialogBackgroundColor: isDarkMode(context)
                ? AppThemeData.grey800
                : AppThemeData.grey100,
            initialSelection: 'IN',
            favorite: const ['+91'],
            comparator: (a, b) => b.name!.compareTo(a.name.toString()),
            textStyle: TextStyle(
              fontSize: 14,
              color: isDarkMode(context)
                  ? AppThemeData.grey50
                  : AppThemeData.grey900,
              fontFamily: AppThemeData.medium,
            ),
            searchDecoration: InputDecoration(
              iconColor: isDarkMode(context)
                  ? AppThemeData.grey50
                  : AppThemeData.grey900,
            ),
            searchStyle: TextStyle(
              color: isDarkMode(context)
                  ? AppThemeData.grey50
                  : AppThemeData.grey900,
              fontWeight: FontWeight.w500,
              fontFamily: AppThemeData.medium,
            ),
          ),
        ),
        const SizedBox(height: 16),
        AuthFieldLabel(text: 'Password'.tr),
        AuthTextField(
          controller: _signupPasswordCtrl,
          hint: 'Enter Password'.tr,
          iconPath: 'assets/icons/ic_lock.svg',
          obscureText: _signupPasswordVisible,
          showVisibility: true,
          isVisible: _signupPasswordVisible,
          onToggle: () => setState(
              () => _signupPasswordVisible = !_signupPasswordVisible),
        ),
        const SizedBox(height: 16),
        AuthFieldLabel(text: 'Confirm Password'.tr),
        AuthTextField(
          controller: _signupConfirmPasswordCtrl,
          hint: 'Enter Confirm Password'.tr,
          iconPath: 'assets/icons/ic_lock.svg',
          obscureText: _signupConfirmPasswordVisible,
          showVisibility: true,
          isVisible: _signupConfirmPasswordVisible,
          onToggle: () => setState(() =>
              _signupConfirmPasswordVisible = !_signupConfirmPasswordVisible),
        ),
        const SizedBox(height: 16),
        AuthFieldLabel(text: 'Referral Code (Optional)'.tr),
        AuthTextField(
          controller: _signupReferralCtrl,
          hint: 'Enter Referral Code'.tr,
          iconPath: 'assets/icons/ic_gift.svg',
          textCapitalization: TextCapitalization.characters,
        ),
        const SizedBox(height: 24),
        AuthPrimaryButton(
          label: 'Sign Up'.tr,
          onTap: () {
            if (_validateSignupForm()) _signUp();
          },
        ),
        const SizedBox(height: 28),
        const AuthOrDivider(),
        const SizedBox(height: 20),
        AuthOutlinedButton(
          label: 'Continue with Mobile Number'.tr,
          iconPath: 'assets/icons/ic_phone.svg',
          onTap: () => push(context, PhoneNumberScreen()),
        ),
      ],
    );
  }
}
