import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/AppGlobal.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';

class AccountDetailsScreen extends StatefulWidget {
  AccountDetailsScreen({Key? key}) : super(key: key);

  @override
  _AccountDetailsScreenState createState() {
    return _AccountDetailsScreenState();
  }
}

class _AccountDetailsScreenState extends State<AccountDetailsScreen> {
  final GlobalKey<FormState> _key = GlobalKey();
  AutovalidateMode _validate = AutovalidateMode.disabled;
  final TextEditingController name = TextEditingController();
  final TextEditingController email = TextEditingController();
  final TextEditingController mobile = TextEditingController();

  @override
  void initState() {
    super.initState();

    setState(() {
      name.text = '${MyAppState.currentUser!.firstName} ${MyAppState.currentUser!.lastName}'.trim();
      email.text = MyAppState.currentUser!.email;
      mobile.text = MyAppState.currentUser!.phoneNumber;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkModeEnabled = isDarkMode(context);

    return Scaffold(
      backgroundColor: isDarkModeEnabled ? AppThemeData.darkBgSecondary : AppThemeData.neutral50,
      appBar: AppGlobal.buildSimpleAppBar(context, "accountDetails".tr()),
      body: SingleChildScrollView(
        child: Form(
          key: _key,
          autovalidateMode: _validate,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: 24), // Spacing-6

                // Details Section
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    'Details'.tr(),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 20, // h4
                    ),
                  ),
                ),

                // Name Field
                _buildFormTextField(
                  labelText: 'Name'.tr(),
                  controller: name,
                  validator: validateName,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  keyboardType: TextInputType.text,
                ),
                const SizedBox(height: 20), // Spacing-5

                // Email Field
                _buildFormTextField(
                  labelText: 'emailAddress'.tr(),
                  controller: email,
                  validator: validateEmail,
                  enabled: false,
                ),
                const SizedBox(height: 20), // Spacing-5

                // Phone Number Field
                _buildFormTextField(
                  labelText: 'phoneNumber'.tr(),
                  controller: mobile,
                  enabled: false,
                ),

                const SizedBox(height: 40), // Spacing-8
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppThemeData.primary500,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
              elevation: 2,
            ),
            onPressed: _validateAndSave,
            child: Text(
              'save'.tr(),
              style: theme.textTheme.labelLarge?.copyWith(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormTextField({
    required String labelText,
    required TextEditingController controller,
    String? Function(String?)? validator,
    bool enabled = true,
    TextInputAction? textInputAction,
    TextCapitalization textCapitalization = TextCapitalization.none,
    TextInputType? keyboardType,
  }) {
    final theme = Theme.of(context);
    final isDarkModeEnabled = isDarkMode(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelText,
          style: theme.textTheme.labelMedium?.copyWith(
            color: isDarkModeEnabled ? AppThemeData.darkTextSecondary : AppThemeData.neutral600,
          ),
        ),
        const SizedBox(height: 8.0), // spacing-2
        TextFormField(
          controller: controller,
          validator: validator,
          enabled: enabled,
          textInputAction: textInputAction,
          textCapitalization: textCapitalization,
          keyboardType: keyboardType,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isDarkModeEnabled ? AppThemeData.darkTextPrimary : AppThemeData.neutral800,
          ),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
            filled: true,
            fillColor: enabled
                ? (isDarkModeEnabled ? AppThemeData.darkBgTertiary : AppThemeData.neutral0)
                : (isDarkModeEnabled ? AppThemeData.darkBgSecondary : AppThemeData.neutral100),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0), // radius-lg
              borderSide: BorderSide(
                color: isDarkModeEnabled ? AppThemeData.darkBorderPrimary : AppThemeData.neutral300,
                width: 1.0,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
              borderSide: BorderSide(
                color: isDarkModeEnabled ? AppThemeData.darkBorderPrimary : AppThemeData.neutral300,
                width: 1.0,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
              borderSide: BorderSide(color: AppThemeData.primary500, width: 2.0),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
              borderSide: BorderSide.none,
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
              borderSide: BorderSide(color: AppThemeData.error500, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
              borderSide: BorderSide(color: AppThemeData.error500, width: 2.0),
            ),
          ),
        ),
      ],
    );
  }

  _validateAndSave() async {
    if (_key.currentState?.validate() ?? false) {
      _key.currentState!.save();
      await showProgress("Please wait...".tr(), false);
      await _updateUser();
    } else {
      setState(() {
        _validate = AutovalidateMode.onUserInteraction;
      });
    }
  }

  _updateUser() async {
    final parts = name.text.trim().split(' ');
    MyAppState.currentUser!.firstName = parts.first;
    MyAppState.currentUser!.lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    MyAppState.currentUser!.email = email.text;
    MyAppState.currentUser!.phoneNumber = mobile.text;
    await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!)
        .then((value) {
      if (value != null) {
        setState(() {
          MyAppState.currentUser = value;
        });

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
          'detailsSavedSuccessfully'.tr(),
          style: TextStyle(fontSize: 17),
        ).tr()));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
          'couldNotSaveDetailsPleaseTryAgain'.tr(),
          style: TextStyle(fontSize: 17),
        ).tr()));
      }
    });
    await hideProgress();
  }

}
