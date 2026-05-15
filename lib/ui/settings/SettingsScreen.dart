import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/utils/DarkThemeProvider.dart';
import 'package:flutter/cupertino.dart';
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
  int cartCount = 0;

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
    return Scaffold(
      backgroundColor: isDarkMode(context) ? AppThemeData.darkBgPrimary : AppThemeData.neutral50,
      appBar: AppBar(
        backgroundColor: AppThemeData.neutral0,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'settings'.tr(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: isDarkMode(context) ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
          ),
        ),
        iconTheme: IconThemeData(
          color: isDarkMode(context) ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
        ),
      ),
      body: SingleChildScrollView(
        child: Builder(
            builder: (buildContext) => Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // Section Header
                      Text(
                        'pushNotifications'.tr(),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode(context) ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Notification Settings Card
                      Container(
                        decoration: BoxDecoration(
                          color: isDarkMode(context) ? AppThemeData.darkBgSecondary : AppThemeData.neutral0,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
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
                              onChanged: (bool newValue) {
                                pushNewMessages = newValue;
                                setState(() {});
                              },
                              isDarkMode: isDarkMode(context),
                            ),
                            Divider(height: 1, color: AppThemeData.neutral200),
                            _buildSwitchTile(
                              title: 'Order Updates'.tr(),
                              value: orderUpdates,
                              onChanged: (bool newValue) {
                                orderUpdates = newValue;
                                setState(() {});
                              },
                              isDarkMode: isDarkMode(context),
                            ),
                            Divider(height: 1, color: AppThemeData.neutral200),
                            _buildSwitchTile(
                              title: 'Promotions'.tr(),
                              value: promotions,
                              onChanged: (bool newValue) {
                                promotions = newValue;
                                setState(() {});
                              },
                              isDarkMode: isDarkMode(context),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Dark Mode Section
                      Text(
                        'appearance'.tr(),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode(context) ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Dark Mode Card
                      Container(
                        decoration: BoxDecoration(
                          color: isDarkMode(context) ? AppThemeData.darkBgSecondary : AppThemeData.neutral0,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Color.fromRGBO(0, 0, 0, 0.06),
                              offset: Offset(0, 2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Consumer<DarkThemeProvider>(
                          builder: (context, themeProvider, child) {
                            return _buildSwitchTile(
                              title: 'darkMode'.tr(),
                              value: themeProvider.darkTheme,
                              onChanged: (bool newValue) {
                                themeProvider.darkTheme = newValue;
                              },
                              isDarkMode: isDarkMode(context),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Save Button
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
                                  ).tr()));
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
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDarkMode,
  }) {
    return SwitchListTile.adaptive(
      activeColor: AppThemeData.primary500,
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: isDarkMode ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
        ),
      ),
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
