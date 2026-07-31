import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/app_dialog.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/accountDetails/AccountDetailsScreen.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';

import 'package:emartconsumer/ui/settings/SettingsScreen.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _imagePicker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    return Scaffold(
      backgroundColor: dark ? AppThemeData.surfaceDark : const Color(0xFFF2F4F8),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildHeader(context, dark),
          const SizedBox(height: 20),
          _buildSection(
            context,
            dark,
            title: 'Account'.tr(),
            items: [
              _MenuItem(
                icon: CupertinoIcons.person_alt_circle,
                label: 'Account Details'.tr(),
                onTap: () => push(context, AccountDetailsScreen()),
              ),
              _MenuItem(
                icon: CupertinoIcons.settings_solid,
                label: 'Settings'.tr(),
                onTap: () => push(context, SettingsScreen(user: MyAppState.currentUser!)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSection(
            context,
            dark,
            title: 'Danger Zone'.tr(),
            items: [
              _MenuItem(
                icon: CupertinoIcons.delete_solid,
                label: 'Delete Account'.tr(),
                isDestructive: true,
                onTap: () => _showDeleteAccountDialog(context, dark),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildLogoutButton(context),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool dark) {
    final user = MyAppState.currentUser ?? User();
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppThemeData.primary500, AppThemeData.primary600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: AppThemeData.primary500.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 28),
      child: Column(
        children: [
          // Avatar
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 52,
                  backgroundColor: AppThemeData.neutral100,
                  backgroundImage: user.profilePictureURL.isNotEmpty
                      ? NetworkImage(user.profilePictureURL) as ImageProvider
                      : null,
                  child: user.profilePictureURL.isEmpty
                      ? const Icon(Icons.person_rounded, size: 48, color: Colors.white70)
                      : null,
                ),
              ),
              GestureDetector(
                onTap: _onCameraClick,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6)],
                  ),
                  child: Icon(Icons.camera_alt_rounded, size: 18, color: AppThemeData.primary500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            user.fullName(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontFamily: AppThemeData.bold,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            user.email,
            style: TextStyle(
              fontSize: 14,
              fontFamily: AppThemeData.regular,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          if (user.phoneNumber.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              user.phoneNumber,
              style: TextStyle(
                fontSize: 13,
                fontFamily: AppThemeData.regular,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    bool dark, {
    required String title,
    required List<_MenuItem> items,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontFamily: AppThemeData.semiBold,
                letterSpacing: 0.8,
                color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral500,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: dark ? AppThemeData.darkBgSecondary : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.0 : 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: List.generate(items.length, (i) {
                final item = items[i];
                final isLast = i == items.length - 1;
                final color = item.isDestructive
                    ? AppThemeData.error500
                    : (dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900);
                final iconColor = item.isDestructive
                    ? AppThemeData.error500
                    : AppThemeData.primary500;

                return Column(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.vertical(
                          top: i == 0 ? const Radius.circular(16) : Radius.zero,
                          bottom: isLast ? const Radius.circular(16) : Radius.zero,
                        ),
                        onTap: item.onTap,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: item.isDestructive
                                      ? AppThemeData.error500.withValues(alpha: 0.1)
                                      : AppThemeData.primary500.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(item.icon, color: iconColor, size: 20),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  item.label,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontFamily: AppThemeData.medium,
                                    color: color,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 20,
                                color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral400,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (!isLast)
                      Divider(
                        height: 1,
                        indent: 68,
                        color: dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral100,
                      ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: AppThemeData.error500, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: Icon(Icons.logout_rounded, color: AppThemeData.error500, size: 20),
          label: Text(
            'Log Out'.tr(),
            style: TextStyle(
              fontSize: 15,
              fontFamily: AppThemeData.semiBold,
              color: AppThemeData.error500,
            ),
          ),
          onPressed: () async {
            MyAppState.currentUser!.lastOnlineTimestamp = Timestamp.now();
            await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!);
            await auth.FirebaseAuth.instance.signOut();
            MyAppState.currentUser = null;
            pushAndRemoveUntil(context, const LoginScreen());
          },
        ),
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context, bool dark) async {
    final confirmed = await AppDialog.showConfirm(
      context,
      title: 'Delete Account?',
      message: 'Are you sure you want to permanently delete your account? This action cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      destructive: true,
    );
    if (!confirmed) return;
    ShowToastDialog.showLoader('Please wait...');
    await FireStoreUtils.deleteUser();
    MyAppState.currentUser = null;
    ShowToastDialog.closeLoader();
    ShowToastDialog.showToast('Account deleted successfully.');
    if (context.mounted) pushAndRemoveUntil(context, const LoginScreen());
  }

  void _onCameraClick() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        message: Text(
          'Add Profile Picture'.tr(),
          style: TextStyle(fontSize: 15, color: AppThemeData.neutral600),
        ),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(ctx);
              await showProgress('Please wait...'.tr(), false);
              MyAppState.currentUser!.profilePictureURL = '';
              await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!);
              hideProgress();
              setState(() {});
            },
            child: Text('Remove picture'.tr()),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              final img = await _imagePicker.pickImage(source: ImageSource.gallery);
              if (img != null) await _imagePicked(File(img.path));
              setState(() {});
            },
            child: Text('chooseImageFromGallery'.tr()),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              final img = await _imagePicker.pickImage(source: ImageSource.camera);
              if (img != null) await _imagePicked(File(img.path));
              setState(() {});
            },
            child: Text('Take a picture'.tr()),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Cancel'.tr(), style: TextStyle(fontFamily: AppThemeData.semiBold)),
        ),
      ),
    );
  }

  Future<void> _imagePicked(File image) async {
    await showProgress('Please wait...'.tr(), false);
    final url = await FireStoreUtils.uploadUserImageToFireStorage(
        image, MyAppState.currentUser!.userID);
    if (url != null) {
      MyAppState.currentUser!.profilePictureURL = url;
      await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!);
    }
    hideProgress();
    setState(() {});
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });
}
