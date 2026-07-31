import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/AddressModel.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/ui/deliveryAddressScreen/add_address_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class DeliveryAddressScreen extends StatefulWidget {
  const DeliveryAddressScreen({super.key});

  @override
  State<DeliveryAddressScreen> createState() => _DeliveryAddressScreenState();
}

class _DeliveryAddressScreenState extends State<DeliveryAddressScreen> {
  List<AddressModel> shippingAddress = [];

  @override
  void initState() {
    super.initState();
    getListAddress();
  }

  void getListAddress() {
    setState(() {
      if (MyAppState.currentUser?.shippingAddress != null) {
        shippingAddress = MyAppState.currentUser!.shippingAddress!;
      }
    });
  }

  // ── icon helper ──────────────────────────────────────────────────────────
  IconData _labelIcon(String? label) {
    switch (label?.toLowerCase()) {
      case 'home':
        return Icons.home_rounded;
      case 'work':
        return Icons.work_rounded;
      case 'hotel':
        return Icons.hotel_rounded;
      default:
        return Icons.location_on_rounded;
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    return Scaffold(
      backgroundColor:
          dark ? AppThemeData.surfaceDark : const Color(0xFFF2F4F8),
      appBar: AppBar(
        backgroundColor: dark ? AppThemeData.darkBgSecondary : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 20,
              color: dark
                  ? AppThemeData.darkTextPrimary
                  : AppThemeData.neutral900),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Select Address'.tr(),
          style: TextStyle(
            fontSize: 18,
            fontFamily: AppThemeData.semiBold,
            color: dark
                ? AppThemeData.darkTextPrimary
                : AppThemeData.neutral900,
          ),
        ),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  if (MyAppState.currentUser != null) {
                    await Navigator.of(context)
                        .push(MaterialPageRoute(
                            builder: (_) => const AddAddressScreen()))
                        .then((_) => getListAddress());
                  } else {
                    Navigator.pop(context);
                    push(context, LoginScreen());
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        AppThemeData.primary500,
                        AppThemeData.primary600
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppThemeData.primary500.withValues(alpha: 0.30),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_rounded,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 5),
                      Text(
                        'New Address'.tr(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: AppThemeData.semiBold,
                          fontSize: 13,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
              height: 1,
              thickness: 1,
              color: dark
                  ? AppThemeData.darkBorderSecondary
                  : AppThemeData.neutral200),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        physics: const BouncingScrollPhysics(),
        children: [
          // ── Saved addresses ───────────────────────────────────────────────
          if (shippingAddress.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Saved Addresses'.tr(),
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: AppThemeData.semiBold,
                  color: dark
                      ? AppThemeData.darkTextSecondary
                      : AppThemeData.neutral500,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            ...shippingAddress.asMap().entries.map((e) => _AddressCard(
                  addressModel: e.value,
                  dark: dark,
                  labelIcon: _labelIcon(e.value.addressAs),
                  onTap: () => Navigator.pop(context, e.value),
                  onMore: () => _showActionSheet(context, e.key),
                )),
          ],
        ],
      ),
    );
  }

  // ── Action sheet ─────────────────────────────────────────────────────────
  void _showActionSheet(BuildContext context1, int index) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              await Navigator.of(context)
                  .push(MaterialPageRoute(
                      builder: (_) => AddAddressScreen(index: index)))
                  .then((_) => getListAddress());
            },
            child: Text('Edit'.tr(),
                style: const TextStyle(color: Colors.blue)),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              shippingAddress.removeAt(index);
              if (MyAppState.currentUser != null) {
                MyAppState.currentUser!.shippingAddress = shippingAddress;
                FireStoreUtils.updateCurrentUser(MyAppState.currentUser!);
              }
              getListAddress();
              Navigator.pop(ctx);
            },
            child: Text('Delete'.tr(),
                style: const TextStyle(color: AppThemeData.error500)),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx, 'Cancel'),
          child: Text('Cancel'.tr()),
        ),
      ),
    );
  }
}

// ── Address card ─────────────────────────────────────────────────────────────
class _AddressCard extends StatelessWidget {
  final AddressModel addressModel;
  final bool dark;
  final IconData labelIcon;
  final VoidCallback onTap;
  final VoidCallback onMore;

  const _AddressCard({
    required this.addressModel,
    required this.dark,
    required this.labelIcon,
    required this.onTap,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: dark ? AppThemeData.darkBgSecondary : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: dark
                    ? AppThemeData.darkBorderPrimary
                    : AppThemeData.neutral200,
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Type icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: dark
                        ? AppThemeData.darkBgTertiary
                        : AppThemeData.neutral100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    labelIcon,
                    color: dark
                        ? AppThemeData.darkTextSecondary
                        : AppThemeData.neutral500,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                // Address info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Label badge (no default styling)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: dark
                              ? AppThemeData.darkBgTertiary
                              : AppThemeData.neutral100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          (addressModel.addressAs ?? 'Other').tr(),
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: AppThemeData.semiBold,
                            color: dark
                                ? AppThemeData.darkTextSecondary
                                : AppThemeData.neutral600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        addressModel.getFullAddress(),
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: AppThemeData.regular,
                          height: 1.45,
                          color: dark
                              ? AppThemeData.darkTextSecondary
                              : AppThemeData.neutral700,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.touch_app_rounded,
                              size: 13,
                              color: AppThemeData.primary500
                                  .withValues(alpha: 0.7)),
                          const SizedBox(width: 4),
                          Text(
                            'Tap to select'.tr(),
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: AppThemeData.regular,
                              color: dark
                                  ? AppThemeData.darkTextTertiary
                                  : AppThemeData.neutral400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // More button
                GestureDetector(
                  onTap: onMore,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: dark
                          ? AppThemeData.darkBgTertiary
                          : AppThemeData.neutral100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.more_vert_rounded,
                      size: 18,
                      color: dark
                          ? AppThemeData.darkTextTertiary
                          : AppThemeData.neutral500,
                    ),
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
