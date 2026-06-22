import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

import 'package:emartconsumer/theme/app_them_data.dart';

// ─────────────────────────────────────────────────────────────────────────────
/// Fills its constraints with a dark purple/indigo gradient and places [child]
/// on top. Uses a plain [Container] decoration — no Stack, no Positioned —
/// so the gradient and the child share the same layout pass without any
/// flex/positioning ambiguity.
// ─────────────────────────────────────────────────────────────────────────────
class AuthBackground extends StatelessWidget {
  final Widget child;
  const AuthBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0D0620), // deep purple-black
            Color(0xFF1B0F4E), // deep indigo
            Color(0xFF2D1878), // rich violet
            Color(0xFF120830), // back to deep purple
          ],
          stops: [0.0, 0.30, 0.65, 1.0],
        ),
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// Semi-transparent glass panel for the form section.
/// Does NOT return [Expanded] — wrap it in Expanded at the call site so the
/// parent Column can flex it correctly.
// ─────────────────────────────────────────────────────────────────────────────
class AuthFormCard extends StatelessWidget {
  final Widget child;
  const AuthFormCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// Branded header — renders directly on the gradient, no surrounding box.
// ─────────────────────────────────────────────────────────────────────────────
class AuthHeader extends StatelessWidget {
  final String title;
  final String? tagline;
  final String subtitle;
  final Widget? action;
  final bool showBackButton;

  const AuthHeader({
    super.key,
    required this.title,
    this.tagline,
    required this.subtitle,
    this.action,
    this.showBackButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
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
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25)),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 17,
                      ),
                    ),
                  )
                else
                  const SizedBox(),
                if (action != null) action! else const SizedBox(),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontFamily: AppThemeData.bold,
                height: 1.18,
                letterSpacing: -0.3,
              ),
            ),
            if (tagline != null) ...[
              const SizedBox(height: 8),
              Text(
                tagline!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.60),
                  fontSize: 12,
                  fontFamily: AppThemeData.regular,
                  height: 1.55,
                ),
              ),
            ],
            const SizedBox(height: 7),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 14,
                fontFamily: AppThemeData.regular,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// Field label — always white on the gradient.
// ─────────────────────────────────────────────────────────────────────────────
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
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: 13,
          fontFamily: AppThemeData.medium,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// Input field with a solid dark-indigo fill so it's clearly visible against
/// both the gradient background and the glass card.
// ─────────────────────────────────────────────────────────────────────────────
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
    // Solid fill so fields pop clearly against the gradient.
    const fillColor         = Color(0xFF1E1252);
    const fillColorDisabled = Color(0xFF160D3A);
    const borderNormal      = Color(0x80FFFFFF); // white 50%
    const borderFocused     = AppThemeData.primary400;
    const borderDisabled    = Color(0x40FFFFFF);

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
      style: const TextStyle(
        color: Colors.white,
        fontFamily: AppThemeData.medium,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: enabled ? fillColor : fillColorDisabled,
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.42),
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
                        Colors.white.withValues(alpha: 0.65),
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
                      Colors.white.withValues(alpha: 0.65),
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              )
            : null,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: borderNormal),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: borderNormal),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: borderFocused, width: 1.8),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: borderDisabled),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: AppThemeData.error500),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// Gradient CTA button.
// ─────────────────────────────────────────────────────────────────────────────
class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const AuthPrimaryButton(
      {super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          FocusScope.of(context).unfocus();
          onTap();
        },
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppThemeData.primary500, AppThemeData.primary400],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppThemeData.primary500.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 6),
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
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// "or" divider.
// ─────────────────────────────────────────────────────────────────────────────
class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final lineColor = Colors.white.withValues(alpha: 0.30);
    return Row(
      children: [
        Expanded(child: Divider(color: lineColor, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'or'.tr,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 13,
              fontFamily: AppThemeData.medium,
            ),
          ),
        ),
        Expanded(child: Divider(color: lineColor, thickness: 1)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// Secondary outlined button.
// ─────────────────────────────────────────────────────────────────────────────
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
          color: Colors.white.withValues(alpha: 0.10),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.35),
            width: 1.4,
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
                    Colors.white, BlendMode.srcIn),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.90),
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
