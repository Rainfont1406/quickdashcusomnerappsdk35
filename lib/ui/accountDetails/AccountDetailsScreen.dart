import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/AppGlobal.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl_phone_number_input/intl_phone_number_input.dart';

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
  final TextEditingController firstName = TextEditingController();
  final TextEditingController lastName = TextEditingController();
  final TextEditingController email = TextEditingController();
  final TextEditingController mobile = TextEditingController();

  @override
  void initState() {
    super.initState();

    setState(() {
      firstName.text = MyAppState.currentUser!.firstName;
      lastName.text = MyAppState.currentUser!.lastName;
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

                // First Name Field
                _buildFormTextField(
                  labelText: 'firstName'.tr(),
                  controller: firstName,
                  validator: validateName,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  keyboardType: TextInputType.text,
                ),
                const SizedBox(height: 20), // Spacing-5

                // Last Name Field
                _buildFormTextField(
                  labelText: 'lastName'.tr(),
                  controller: lastName,
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
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppThemeData.primary500,
            minimumSize: const Size(double.infinity, 56), // Height 56px
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0), // radius-lg
            ),
            elevation: 2, // shadow-sm
          ),
          onPressed: _validateAndSave,
          child: Text(
            'save'.tr(),
            style: theme.textTheme.labelLarge?.copyWith(color: Colors.white),
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
    MyAppState.currentUser!.firstName = firstName.text;
    MyAppState.currentUser!.lastName = lastName.text;
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

  showAlertDialog(BuildContext context) {
    // set up the buttons
    Widget cancelButton = TextButton(
      child: const Text("Cancel").tr(),
      onPressed: () {
        Navigator.pop(context);
      },
    );
    Widget continueButton = TextButton(
      child: const Text("continue").tr(),
      onPressed: () {
        if (_isPhoneValid) {
          setState(() {
            MyAppState.currentUser!.phoneNumber = _phoneNumber.toString();
            mobile.text = _phoneNumber.toString();
          });
          Navigator.pop(context);
        }
      },
    );

    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: const Text("Change Phone Number").tr(),
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            shape: BoxShape.rectangle,
            border: Border.all(color: Colors.grey.shade200)),
        child: InternationalPhoneNumberInput(
          onInputChanged: (value) {
            _phoneNumber = "${value.phoneNumber}";
          },
          onInputValidated: (bool value) => _isPhoneValid = value,
          ignoreBlank: true,
          autoValidateMode: AutovalidateMode.onUserInteraction,
          inputDecoration: InputDecoration(
            hintText: 'Phone Number'.tr(),
            border: const OutlineInputBorder(
              borderSide: BorderSide.none,
            ),
            isDense: true,
            errorBorder: const OutlineInputBorder(
              borderSide: BorderSide.none,
            ),
          ),
          inputBorder: const OutlineInputBorder(
            borderSide: BorderSide.none,
          ),
          initialValue: PhoneNumber(isoCode: 'US'),
          selectorConfig:
              const SelectorConfig(selectorType: PhoneInputSelectorType.DIALOG),
        ),
      ),
      actions: [
        cancelButton,
        continueButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  bool _isPhoneValid = false;
  String? _phoneNumber = "";
}
