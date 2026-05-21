import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';

/// Branded gradient header shared by login and signup screens.
class AuthHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? action;
  final bool showBackButton;

  const AuthHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
    this.showBackButton = false,
  });

  @override
  Widget build(BuildContext context) {
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
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (showBackButton)
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
                    )
                  else
                    const SizedBox(),
                  if (action != null) action! else const SizedBox(),
                ],
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
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontFamily: AppThemeData.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
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
    );
  }
}

class AuthFieldLabel extends StatelessWidget {
  final String text;
  const AuthFieldLabel({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: isDarkMode(context) ? AppThemeData.grey200 : AppThemeData.grey700,
          fontSize: 14,
          fontFamily: AppThemeData.medium,
        ),
      ),
    );
  }
}

class AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String? iconPath;
  final bool obscureText;
  final bool showVisibility;
  final bool? isVisible;
  final VoidCallback? onToggle;
  final TextInputType? keyboardType;
  final bool enabled;
  final Widget? prefixWidget;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final TextCapitalization textCapitalization;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.iconPath,
    this.obscureText = false,
    this.showVisibility = false,
    this.isVisible,
    this.onToggle,
    this.keyboardType,
    this.enabled = true,
    this.prefixWidget,
    this.inputFormatters,
    this.textInputAction,
    this.onChanged,
    this.textCapitalization = TextCapitalization.sentences,
  });

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      obscuringCharacter: '●',
      keyboardType: keyboardType ?? TextInputType.text,
      textCapitalization: textCapitalization,
      enabled: enabled,
      inputFormatters: inputFormatters,
      textInputAction: textInputAction ?? TextInputAction.done,
      onChanged: onChanged,
      style: TextStyle(
        color: dark ? AppThemeData.grey50 : AppThemeData.grey900,
        fontFamily: AppThemeData.medium,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: dark
            ? (enabled ? AppThemeData.grey800 : AppThemeData.grey900)
            : (enabled ? Colors.white : AppThemeData.grey100),
        hintText: hint,
        hintStyle: TextStyle(
          color: dark ? AppThemeData.grey600 : AppThemeData.grey400,
          fontSize: 14,
          fontFamily: AppThemeData.regular,
        ),
        prefixIcon: prefixWidget ??
            (iconPath != null
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: SvgPicture.asset(
                      iconPath!,
                      width: 20,
                      height: 20,
                      colorFilter: ColorFilter.mode(
                        dark ? AppThemeData.grey400 : AppThemeData.grey500,
                        BlendMode.srcIn,
                      ),
                    ),
                  )
                : null),
        suffixIcon: showVisibility
            ? GestureDetector(
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: SvgPicture.asset(
                    (isVisible ?? true)
                        ? 'assets/icons/ic_password_show.svg'
                        : 'assets/icons/ic_password_close.svg',
                    width: 20,
                    height: 20,
                    colorFilter: ColorFilter.mode(
                      dark ? AppThemeData.grey400 : AppThemeData.grey500,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: dark ? AppThemeData.grey700 : AppThemeData.grey200,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: dark ? AppThemeData.grey700 : AppThemeData.grey200,
          ),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: AppThemeData.primary500, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: dark ? AppThemeData.grey800 : AppThemeData.grey200,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppThemeData.error500),
        ),
      ),
    );
  }
}

class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const AuthPrimaryButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
        onTap();
      },
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppThemeData.primary500, AppThemeData.primary400],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppThemeData.primary500.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontFamily: AppThemeData.semiBold,
            ),
          ),
        ),
      ),
    );
  }
}

class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Divider(
            color: isDarkMode(context)
                ? AppThemeData.grey700
                : AppThemeData.grey200,
            thickness: 1,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'or'.tr,
            style: TextStyle(
              color: isDarkMode(context)
                  ? AppThemeData.grey500
                  : AppThemeData.grey400,
              fontSize: 13,
              fontFamily: AppThemeData.medium,
            ),
          ),
        ),
        Expanded(
          child: Divider(
            color: isDarkMode(context)
                ? AppThemeData.grey700
                : AppThemeData.grey200,
            thickness: 1,
          ),
        ),
      ],
    );
  }
}

class AuthOutlinedButton extends StatelessWidget {
  final String label;
  final String? iconPath;
  final VoidCallback onTap;

  const AuthOutlinedButton({
    super.key,
    required this.label,
    required this.onTap,
    this.iconPath,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
        onTap();
      },
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppThemeData.primary500,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (iconPath != null) ...[
              SvgPicture.asset(
                iconPath!,
                width: 20,
                height: 20,
                colorFilter: const ColorFilter.mode(
                  AppThemeData.primary500,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: const TextStyle(
                color: AppThemeData.primary500,
                fontSize: 15,
                fontFamily: AppThemeData.semiBold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
