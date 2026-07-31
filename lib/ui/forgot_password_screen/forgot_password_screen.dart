import 'package:emartconsumer/controller/forgot_password_controller.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:emartconsumer/utils/DarkThemeProvider.dart';

class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeChange = Provider.of<DarkThemeProvider>(context);
    final dark = themeChange.getThem();
    return GetX(
      init: ForgotPasswordController(),
      builder: (controller) {
        return Scaffold(
          backgroundColor: dark ? AppThemeData.surfaceDark : AppThemeData.surface,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 20,
                color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: GestureDetector(
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // Icon hero
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppThemeData.primary500, AppThemeData.primary600],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: AppThemeData.primary500.withValues(alpha: 0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.lock_reset_rounded, color: Colors.white, size: 44),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Forgot Password?'.tr,
                    style: TextStyle(
                      fontSize: 26,
                      fontFamily: AppThemeData.bold,
                      color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your registered email address and we\'ll send you a link to reset your password.'.tr,
                    style: TextStyle(
                      fontSize: 15,
                      fontFamily: AppThemeData.regular,
                      height: 1.55,
                      color: dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral500,
                    ),
                  ),
                  const SizedBox(height: 36),
                  // Email label
                  Text(
                    'Email Address'.tr,
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: AppThemeData.semiBold,
                      color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Email field
                  TextFormField(
                    controller: controller.emailEditingController.value,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    style: TextStyle(
                      fontSize: 15,
                      fontFamily: AppThemeData.medium,
                      color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
                    ),
                    decoration: InputDecoration(
                      hintText: 'you@example.com'.tr,
                      hintStyle: TextStyle(
                        fontSize: 15,
                        fontFamily: AppThemeData.regular,
                        color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral400,
                      ),
                      prefixIcon: Icon(
                        Icons.email_outlined,
                        color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral400,
                        size: 20,
                      ),
                      filled: true,
                      fillColor: dark ? AppThemeData.darkBgSecondary : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral200,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral200,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppThemeData.primary500, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // CTA Button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: () async {
                        final success = await controller.forgotPassword();
                        if (success && context.mounted) Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppThemeData.primary500,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                          const SizedBox(width: 10),
                          Text(
                            'Send Reset Link'.tr,
                            style: const TextStyle(
                              fontSize: 16,
                              fontFamily: AppThemeData.semiBold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Back to login hint
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: RichText(
                        text: TextSpan(
                          text: 'Remember your password? '.tr,
                          style: TextStyle(
                            fontSize: 14,
                            fontFamily: AppThemeData.regular,
                            color: dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral500,
                          ),
                          children: [
                            TextSpan(
                              text: 'Sign In'.tr,
                              style: const TextStyle(
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
          ),
        );
      },
    );
  }
}
