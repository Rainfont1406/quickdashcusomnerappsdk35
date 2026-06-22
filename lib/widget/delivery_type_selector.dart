import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/services/app_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:emartconsumer/services/localDatabase.dart';

class DeliveryTypeSelector extends StatefulWidget {
  final String selectedValue;
  final Function(String) onValueChanged;
  final bool isDarkMode;
  final bool allowDelivery;
  final bool allowDineaway;

  const DeliveryTypeSelector({
    Key? key,
    required this.selectedValue,
    required this.onValueChanged,
    required this.isDarkMode,
    this.allowDelivery = true,
    this.allowDineaway = true,
  }) : super(key: key);

  @override
  State<DeliveryTypeSelector> createState() => _DeliveryTypeSelectorState();
}

class _DeliveryTypeSelectorState extends State<DeliveryTypeSelector> {
  IconData _iconFor(String value) {
    if (value == 'Delivery'.tr()) return Icons.delivery_dining_rounded;
    if (value == 'Dineaway'.tr()) return Icons.restaurant_menu_rounded;
    return Icons.local_shipping_rounded;
  }

  void _openSelector() {
    // Capture parent context BEFORE the modal opens so we can use it safely
    // after the bottom sheet is popped (fixes the stale-context bug).
    final rootCtx = context;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      isScrollControlled: true,
      builder: (sheetCtx) => _SectionSelectorSheet(
        selectedValue: widget.selectedValue,
        isDarkMode: widget.isDarkMode,
        allowDelivery: widget.allowDelivery,
        allowDineaway: widget.allowDineaway,
        onSelect: (newValue) async {
          // Same section — nothing to do
          if (newValue == widget.selectedValue) return;

          int cartCount = 0;
          try {
            final products = await Provider.of<CartDatabase>(
              rootCtx,
              listen: false,
            ).allCartProducts;
            cartCount = products.length;
          } catch (_) {}

          if (cartCount > 0) {
            // Show confirmation using the stable root context, not the sheet's
            _showSwitchConfirmation(rootCtx, newValue);
          } else {
            widget.onValueChanged(newValue);
          }
        },
        onUnavailableTap: (unavailableValue) {
          _showUnavailableDialog(rootCtx, unavailableValue);
        },
      ),
    );
  }

  void _showUnavailableDialog(BuildContext ctx, String value) {
    final isDelivery = value == 'Delivery'.tr();
    AppDialog.showError(
      ctx,
      title: isDelivery ? 'Delivery Unavailable' : 'DineAway Unavailable',
      message: isDelivery
          ? 'One or more items in your cart are not available for Delivery. Please remove those items or choose DineAway.'
          : 'One or more items in your cart are not available for DineAway. Please remove those items or choose Delivery.',
      buttonLabel: 'Got It',
    );
  }

  void _showSwitchConfirmation(BuildContext rootCtx, String newValue) {
    showModalBottomSheet(
      context: rootCtx,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: false,
      isScrollControlled: true,
      builder: (sheetCtx) => _SwitchConfirmationSheet(
        isDarkMode: widget.isDarkMode,
        newSectionName: newValue,
        onCancel: () => Navigator.of(sheetCtx).pop(),
        onConfirm: () {
          Navigator.of(sheetCtx).pop();
          Provider.of<CartDatabase>(rootCtx, listen: false).deleteAllProducts();
          widget.onValueChanged(newValue);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.isDarkMode;
    return GestureDetector(
      onTap: _openSelector,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: dark
              ? AppThemeData.grey800.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: dark
                ? AppThemeData.grey700.withValues(alpha: 0.50)
                : AppThemeData.grey200,
            width: 1,
          ),
          boxShadow: dark
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: AppThemeData.primary500.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _iconFor(widget.selectedValue),
                size: 16,
                color: AppThemeData.primary500,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              widget.selectedValue,
              style: TextStyle(
                fontFamily: AppThemeData.semiBold,
                fontSize: 14,
                color: dark ? AppThemeData.grey50 : AppThemeData.grey900,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: dark ? AppThemeData.grey400 : AppThemeData.grey500,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section Selector Sheet ─────────────────────────────────────────────
class _SectionSelectorSheet extends StatelessWidget {
  final String selectedValue;
  final bool isDarkMode;
  final Future<void> Function(String) onSelect;
  final bool allowDelivery;
  final bool allowDineaway;
  final void Function(String) onUnavailableTap;

  const _SectionSelectorSheet({
    required this.selectedValue,
    required this.isDarkMode,
    required this.onSelect,
    required this.allowDelivery,
    required this.allowDineaway,
    required this.onUnavailableTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode;
    final options = [
      {
        'value': 'Delivery'.tr(),
        'label': 'Delivery',
        'subtitle': 'Home Delivery',
        'icon': Icons.delivery_dining_rounded,
      },
      {
        'value': 'Dineaway'.tr(),
        'label': 'DineAway',
        'subtitle': 'Dining & Takeaway',
        'icon': Icons.restaurant_menu_rounded,
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgSecondary : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 20),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: dark ? AppThemeData.grey700 : AppThemeData.grey300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Order Mode',
                  style: TextStyle(
                    fontSize: 18,
                    fontFamily: AppThemeData.bold,
                    fontWeight: FontWeight.w700,
                    color: dark
                        ? AppThemeData.darkTextPrimary
                        : AppThemeData.neutral900,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: dark
                          ? AppThemeData.darkBgTertiary
                          : AppThemeData.neutral100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: dark
                          ? AppThemeData.darkTextSecondary
                          : AppThemeData.neutral600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Option cards
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: options.map((opt) {
                final val = opt['value'] as String;
                final label = opt['label'] as String;
                final subtitle = opt['subtitle'] as String;
                final icon = opt['icon'] as IconData;
                final isSelected = selectedValue == val;
                final isDeliveryOption = val == 'Delivery'.tr();
                final isAllowed =
                    isDeliveryOption ? allowDelivery : allowDineaway;

                return GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    if (!isAllowed) {
                      onUnavailableTap(val);
                    } else {
                      onSelect(val);
                    }
                  },
                  child: Opacity(
                    opacity: isAllowed ? 1.0 : 0.55,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: !isAllowed
                            ? (dark
                                ? AppThemeData.darkBgPrimary
                                : AppThemeData.neutral100)
                            : isSelected
                                ? AppThemeData.primary500.withValues(alpha: 0.08)
                                : (dark
                                    ? AppThemeData.darkBgTertiary
                                    : AppThemeData.neutral50),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: !isAllowed
                              ? (dark
                                  ? AppThemeData.darkBorderSecondary
                                  : AppThemeData.neutral200)
                              : isSelected
                                  ? AppThemeData.primary500
                                  : (dark
                                      ? AppThemeData.darkBorderSecondary
                                      : AppThemeData.neutral200),
                          width: isSelected && isAllowed ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: !isAllowed
                                  ? (dark
                                      ? AppThemeData.darkBgTertiary
                                      : AppThemeData.neutral200)
                                  : isSelected
                                      ? AppThemeData.primary500
                                      : (dark
                                          ? AppThemeData.darkBgSecondary
                                          : AppThemeData.neutral100),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              icon,
                              size: 22,
                              color: !isAllowed
                                  ? (dark
                                      ? AppThemeData.neutral600
                                      : AppThemeData.neutral400)
                                  : isSelected
                                      ? Colors.white
                                      : (dark
                                          ? AppThemeData.darkTextSecondary
                                          : AppThemeData.neutral600),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontFamily: AppThemeData.semiBold,
                                    fontWeight: FontWeight.w600,
                                    color: !isAllowed
                                        ? (dark
                                            ? AppThemeData.darkTextTertiary
                                            : AppThemeData.neutral400)
                                        : isSelected
                                            ? AppThemeData.primary500
                                            : (dark
                                                ? AppThemeData.darkTextPrimary
                                                : AppThemeData.neutral900),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  !isAllowed
                                      ? 'Not available for cart items'.tr()
                                      : subtitle,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontFamily: AppThemeData.regular,
                                    fontStyle: !isAllowed
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                                    color: !isAllowed
                                        ? AppThemeData.error500
                                            .withValues(alpha: 0.75)
                                        : (dark
                                            ? AppThemeData.darkTextTertiary
                                            : AppThemeData.neutral500),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!isAllowed)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppThemeData.error500
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'N/A'.tr(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: AppThemeData.semiBold,
                                  fontWeight: FontWeight.w600,
                                  color: AppThemeData.error500,
                                ),
                              ),
                            )
                          else if (isSelected)
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: AppThemeData.primary500,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Switch Confirmation Sheet ──────────────────────────────────────────
class _SwitchConfirmationSheet extends StatelessWidget {
  final bool isDarkMode;
  final String newSectionName;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const _SwitchConfirmationSheet({
    required this.isDarkMode,
    required this.newSectionName,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode;

    return Container(
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgSecondary : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 28,
        left: 24,
        right: 24,
        top: 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Warning icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppThemeData.warning400.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.swap_horiz_rounded,
              size: 30,
              color: AppThemeData.warning400,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Switch Section?',
            style: TextStyle(
              fontSize: 19,
              fontFamily: AppThemeData.bold,
              fontWeight: FontWeight.w700,
              color:
                  dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Your current cart contains items from the selected section.\nChanging section will remove all cart items.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontFamily: AppThemeData.regular,
              color: dark
                  ? AppThemeData.darkTextSecondary
                  : AppThemeData.neutral500,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(
                      color: dark
                          ? AppThemeData.darkBorderPrimary
                          : AppThemeData.neutral300,
                    ),
                  ),
                  child: Text(
                    'Cancel'.tr(),
                    style: TextStyle(
                      fontSize: 15,
                      fontFamily: AppThemeData.semiBold,
                      fontWeight: FontWeight.w600,
                      color: dark
                          ? AppThemeData.darkTextSecondary
                          : AppThemeData.neutral700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppThemeData.primary500,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Switch & Clear Cart'.tr(),
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: AppThemeData.semiBold,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
