import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';

class QuickDashPaymentSheet extends StatefulWidget {
  final double amount;
  final bool isWalletEnabled;
  final double walletBalance;
  final bool walletHasSufficientBalance;
  final bool isCodEnabled;
  final bool isRazorpayEnabled;
  final Function(String appHint) onUpiSelected;
  final VoidCallback onCardSelected;
  final VoidCallback onWalletSelected;
  final VoidCallback onCodSelected;
  final VoidCallback onMoreOptions;

  const QuickDashPaymentSheet({
    Key? key,
    required this.amount,
    required this.isWalletEnabled,
    required this.walletBalance,
    required this.walletHasSufficientBalance,
    required this.isCodEnabled,
    required this.isRazorpayEnabled,
    required this.onUpiSelected,
    required this.onCardSelected,
    required this.onWalletSelected,
    required this.onCodSelected,
    required this.onMoreOptions,
  }) : super(key: key);

  @override
  State<QuickDashPaymentSheet> createState() => _QuickDashPaymentSheetState();
}

class _QuickDashPaymentSheetState extends State<QuickDashPaymentSheet> {
  bool _tapped = false;

  void _tap(VoidCallback cb) {
    if (_tapped) return;
    _tapped = true;
    Navigator.pop(context);
    cb();
  }

  void _tapUpi(String appHint) {
    if (_tapped) return;
    _tapped = true;
    Navigator.pop(context);
    widget.onUpiSelected(appHint);
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    final bg = dark ? AppThemeData.surfaceDark : Colors.white;
    final bool isAndroid = !kIsWeb && Platform.isAndroid;
    final bool showUpi = isAndroid && widget.isRazorpayEnabled;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── drag handle ──
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 2),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: dark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // ── header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        amountShow(amount: widget.amount.toString()),
                        style: TextStyle(
                          fontSize: 22,
                          fontFamily: AppThemeData.bold,
                          color: dark ? Colors.white : AppThemeData.neutral900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Select payment method'.tr(),
                        style: TextStyle(
                          fontSize: 13,
                          color: dark ? Colors.white54 : AppThemeData.neutral500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_rounded, size: 12, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        'Secure'.tr(),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: dark ? Colors.white10 : AppThemeData.neutral100),
          // ── scrollable content ──
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16, 16, 16, MediaQuery.of(context).padding.bottom + 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── UPI SECTION (Android only) ───
                  if (showUpi) ...[
                    _sectionLabel('Pay via UPI'.tr(), dark),
                    const SizedBox(height: 10),
                    _methodTile(
                      dark: dark,
                      iconBg: const Color(0xFF1A73E8),
                      icon: Icons.g_mobiledata_rounded,
                      title: 'Google Pay'.tr(),
                      subtitle: 'Pay directly with GPay'.tr(),
                      onTap: () => _tapUpi('gpay'),
                    ),
                    _methodTile(
                      dark: dark,
                      iconBg: const Color(0xFF5F259F),
                      icon: Icons.phone_android_rounded,
                      title: 'PhonePe'.tr(),
                      subtitle: 'Pay directly with PhonePe'.tr(),
                      onTap: () => _tapUpi('phonepe'),
                    ),
                    _methodTile(
                      dark: dark,
                      iconBg: const Color(0xFF00B9F1),
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Paytm'.tr(),
                      subtitle: 'Pay directly with Paytm'.tr(),
                      onTap: () => _tapUpi('paytm'),
                    ),
                    _methodTile(
                      dark: dark,
                      iconBg: const Color(0xFF4CAF50),
                      icon: Icons.account_balance_rounded,
                      title: 'Other UPI Apps'.tr(),
                      subtitle: 'BHIM, Amazon Pay & more'.tr(),
                      onTap: () => _tapUpi('upi'),
                    ),
                    const SizedBox(height: 4),
                  ],

                  // ─── OTHER METHODS ───
                  _sectionLabel(
                    showUpi ? 'Other Payment Methods'.tr() : 'Payment Method'.tr(),
                    dark,
                  ),
                  const SizedBox(height: 10),

                  // Card (Razorpay)
                  if (widget.isRazorpayEnabled)
                    _methodTile(
                      dark: dark,
                      iconBg: const Color(0xFF4F46E5),
                      icon: Icons.credit_card_rounded,
                      title: 'Credit / Debit Card'.tr(),
                      subtitle: 'Visa, Mastercard, RuPay & more'.tr(),
                      onTap: () => _tap(widget.onCardSelected),
                    ),

                  // Wallet
                  if (widget.isWalletEnabled)
                    _methodTile(
                      dark: dark,
                      iconBg: const Color(0xFF059669),
                      icon: Icons.account_balance_wallet_rounded,
                      title: 'Wallet'.tr(),
                      subtitle: widget.walletHasSufficientBalance
                          ? '${'Balance'.tr()}: ${amountShow(amount: widget.walletBalance.toString())}'
                          : '${'Insufficient balance'.tr()} (${amountShow(amount: widget.walletBalance.toString())})',
                      subtitleColor: widget.walletHasSufficientBalance
                          ? null
                          : Colors.red.shade400,
                      onTap: widget.walletHasSufficientBalance
                          ? () => _tap(widget.onWalletSelected)
                          : null,
                    ),

                  // COD
                  if (widget.isCodEnabled)
                    _methodTile(
                      dark: dark,
                      iconBg: const Color(0xFFD97706),
                      icon: Icons.payments_rounded,
                      title: 'Cash on Delivery'.tr(),
                      subtitle: 'Pay when your order arrives'.tr(),
                      onTap: () => _tap(widget.onCodSelected),
                    ),

                  // More options link
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onMoreOptions();
                      },
                      child: Text(
                        'More payment options'.tr(),
                        style: TextStyle(
                          fontSize: 13,
                          color: AppThemeData.primary500,
                          fontFamily: AppThemeData.medium,
                        ),
                      ),
                    ),
                  ),

                  // Security badge
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 13,
                          color: dark ? Colors.white30 : AppThemeData.neutral400,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Payments secured by Razorpay'.tr(),
                          style: TextStyle(
                            fontSize: 11,
                            color: dark ? Colors.white30 : AppThemeData.neutral400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, bool dark) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontFamily: AppThemeData.semiBold,
            letterSpacing: 0.6,
            color: dark ? Colors.white38 : AppThemeData.neutral500,
          ),
        ),
      );

  Widget _methodTile({
    required bool dark,
    required Color iconBg,
    required IconData icon,
    required String title,
    required String subtitle,
    Color? subtitleColor,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final bool disabled = onTap == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: disabled ? 0.45 : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF1E1E2E) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: dark ? Colors.white12 : AppThemeData.neutral200,
              ),
              boxShadow: dark
                  ? []
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: iconBg.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: iconBg, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontFamily: AppThemeData.medium,
                          color: dark ? Colors.white : AppThemeData.neutral900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: subtitleColor ??
                              (dark ? Colors.white54 : AppThemeData.neutral500),
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  trailing,
                  const SizedBox(width: 8),
                ],
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: dark ? Colors.white30 : AppThemeData.neutral300,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
