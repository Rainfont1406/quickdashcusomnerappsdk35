import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:emartconsumer/constants.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
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
import 'package:emartconsumer/ui/location_permission_screen.dart';
import 'package:emartconsumer/ui/service_list_screen.dart';
import 'package:emartconsumer/utils/country_phone_length.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

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

    if (fullName.isEmpty) {
      ShowToastDialog.showToast("Please enter full name".tr);
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

  signUp(BuildContext context) async {
    if (mounted) setState(() => _isBusy = true);
    ShowToastDialog.showLoader('Creating your account...');
    final nameParts = _splitFullName(fullNameEditingController.text.toString());
    try {
      if (type == "mobileNumber") {
        // For mobile signup, the email field might be filled in after OTP,
        // no duplicate phone check needed (Firebase OTP already handled it).
        userModel.firstName = nameParts['firstName']!;
        userModel.lastName = nameParts['lastName']!;
        userModel.email = emailEditingController.text.trim().toLowerCase();
        userModel.phoneNumber = phoneNUmberEditingController.text.trim();
        userModel.role = USER_ROLE_CUSTOMER;
        userModel.fcmToken = await NotificationService.getToken();
        userModel.active = true;
        userModel.countryCode = countryCodeEditingController.text;
        userModel.createdAt = Timestamp.now();

        final referralUser = await FireStoreUtils.getReferralUserByCode(
            referralCodeEditingController.text);
        await FireStoreUtils.referralAdd(ReferralModel(
          id: FireStoreUtils.getCurrentUid(),
          referralBy: referralUser?.id ?? '',
          referralCode: getReferralCode(),
        ));

        await FireStoreUtils.updateCurrentUser(userModel);
        if (!mounted) return;
        ShowToastDialog.showToast('Welcome to QuickDash! Your account is ready.');
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
          pushAndRemoveUntil(context, ServiceListScreen());
        } else {
          pushAndRemoveUntil(context, LocationPermissionScreen());
        }
        return;
      }

      // Email+password signup — pre-check if phone is already registered as customer
      final phoneSnap = await FirebaseFirestore.instance
          .collection(USERS)
          .where('phoneNumber', isEqualTo: phoneNUmberEditingController.text.trim())
          .get();
      final phoneConflict = phoneSnap.docs.any((doc) {
        final data = doc.data();
        return data['role'] == USER_ROLE_CUSTOMER &&
            (data['countryCode'] as String? ?? '') == countryCodeEditingController.text;
      });
      if (phoneConflict) {
        ShowToastDialog.showToast(
            'This number is already registered. Log in to continue.');
        return;
      }

      final credential =
          await auth.FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailEditingController.text.trim(),
        password: passwordEditingController.text.trim(),
      );
      if (credential.user == null) {
        ShowToastDialog.showToast("Signup failed. Please try again.");
        return;
      }

      userModel.userID = credential.user!.uid;
      userModel.firstName = nameParts['firstName']!;
      userModel.lastName = nameParts['lastName']!;
      userModel.email = emailEditingController.text.trim().toLowerCase();
      userModel.phoneNumber = phoneNUmberEditingController.text.trim();
      userModel.role = USER_ROLE_CUSTOMER;
      userModel.fcmToken = await NotificationService.getToken();
      userModel.active = true;
      userModel.countryCode = countryCodeEditingController.text;
      userModel.createdAt = Timestamp.now();

      final referralUser = await FireStoreUtils.getReferralUserByCode(
          referralCodeEditingController.text);
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
      ShowToastDialog.showToast('Welcome to QuickDash! Your account is ready.');
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
        pushAndRemoveUntil(context, ServiceListScreen());
      } else {
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
      ShowToastDialog.showToast("Something went wrong. Please try again.");
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
              title: 'Create Account'.tr,
              subtitle: 'Join QuickDash today'.tr,
              showBackButton: true,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AuthFieldLabel(text: 'Full Name'.tr),
                    AuthTextField(
                      controller: fullNameEditingController,
                      hint: 'Enter Full Name'.tr,
                      iconPath: 'assets/icons/ic_user.svg',
                    ),
                    const SizedBox(height: 16),
                    AuthFieldLabel(text: 'Email Address'.tr),
                    AuthTextField(
                      controller: emailEditingController,
                      hint: 'Enter Email Address'.tr,
                      iconPath: 'assets/icons/ic_mail.svg',
                      keyboardType: TextInputType.emailAddress,
                      textCapitalization: TextCapitalization.none,
                    ),
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
                      prefixWidget: CountryCodePicker(
                        enabled: type != "mobileNumber",
                        onChanged: (value) =>
                            _onCountryCodeChanged(value.dialCode.toString()),
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
                        comparator: (a, b) =>
                            b.name!.compareTo(a.name.toString()),
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
                      label: 'Sign Up'.tr,
                      onTap: () {
                        if (_validateSignupForm()) {
                          signUpWithEmailAndPassword(context);
                        }
                      },
                    ),
                    const SizedBox(height: 28),
                    const AuthOrDivider(),
                    const SizedBox(height: 28),
                    AuthOutlinedButton(
                      label: 'Continue with Mobile Number'.tr,
                      iconPath: 'assets/icons/ic_phone.svg',
                      onTap: () => pushReplacement(context, PhoneNumberScreen()),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
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
                    color: isDarkMode(context)
                        ? AppThemeData.grey400
                        : AppThemeData.grey500,
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
                    color: AppThemeData.primary500,
                    fontFamily: AppThemeData.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
