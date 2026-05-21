import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  final User user;

  const SettingsScreen({Key? key, required this.user}) : super(key: key);

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late User user;
  late CartDatabase cartDatabase;
  late bool pushNewMessages, orderUpdates, newArrivals, promotions;

  @override
  void initState() {
    super.initState();
    user = widget.user;
    pushNewMessages = user.settings.pushNewMessages;
    orderUpdates = user.settings.orderUpdates;
    newArrivals = user.settings.newArrivals;
    promotions = user.settings.promotions;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    cartDatabase = Provider.of<CartDatabase>(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkMode(context);
    return Scaffold(
      backgroundColor: isDark ? AppThemeData.darkBgPrimary : AppThemeData.neutral50,
      body: Column(
        children: [
          _buildGradientHeader(),
          Expanded(
            child: SingleChildScrollView(
              child: Builder(
                builder: (buildContext) => Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const SizedBox(height: 8),
                      Text(
                        'pushNotifications'.tr(),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: isDark ? AppThemeData.darkBgSecondary : AppThemeData.neutral0,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(
                              color: Color.fromRGBO(0, 0, 0, 0.06),
                              offset: Offset(0, 2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Column(
                          children: <Widget>[
                            _buildSwitchTile(
                              title: 'allowPushNotifications'.tr(),
                              value: pushNewMessages,
                              onChanged: (v) => setState(() => pushNewMessages = v),
                              isDark: isDark,
                            ),
                            Divider(height: 1, color: AppThemeData.neutral200),
                            _buildSwitchTile(
                              title: 'Order Updates'.tr(),
                              value: orderUpdates,
                              onChanged: (v) => setState(() => orderUpdates = v),
                              isDark: isDark,
                            ),
                            Divider(height: 1, color: AppThemeData.neutral200),
                            _buildSwitchTile(
                              title: 'Promotions'.tr(),
                              value: promotions,
                              onChanged: (v) => setState(() => promotions = v),
                              isDark: isDark,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            await showProgress("Please wait...".tr(), false);
                            user.settings.pushNewMessages = pushNewMessages;
                            user.settings.orderUpdates = orderUpdates;
                            user.settings.newArrivals = newArrivals;
                            user.settings.promotions = promotions;
                            User? updateUser = await FireStoreUtils.updateCurrentUser(user);
                            hideProgress();
                            if (updateUser != null) {
                              this.user = updateUser;
                              MyAppState.currentUser = user;
                              ScaffoldMessenger.of(buildContext).showSnackBar(SnackBar(
                                duration: const Duration(seconds: 3),
                                content: Text(
                                  'settingsSavedSuccessfully'.tr(),
                                  style: const TextStyle(fontSize: 17),
                                ).tr(),
                              ));
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppThemeData.primary500,
                            foregroundColor: AppThemeData.neutral0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'save'.tr(),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppThemeData.primary500, AppThemeData.primary400],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Row(
            children: [
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
              ),
              const SizedBox(width: 12),
              Text(
                'settings'.tr(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) {
    return SwitchListTile.adaptive(
      activeColor: AppThemeData.primary500,
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: isDark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
        ),
      ),
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
