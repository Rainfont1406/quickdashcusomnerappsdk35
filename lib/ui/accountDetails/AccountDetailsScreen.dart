import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/AppGlobal.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/device_session_service.dart';
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

  DateTime? _dob;
  // True when a DOB is already saved in Firestore — field becomes read-only.
  bool _dobLocked = false;

  @override
  void initState() {
    super.initState();
    name.text = '${MyAppState.currentUser!.firstName} ${MyAppState.currentUser!.lastName}'.trim();
    email.text = MyAppState.currentUser!.email;
    mobile.text = MyAppState.currentUser!.phoneNumber;

    final dobStr = MyAppState.currentUser!.dob;
    if (dobStr != null && dobStr.isNotEmpty) {
      _dob = DateTime.tryParse(dobStr);
      _dobLocked = true;
    }
  }

  String _formatDob(DateTime d) => DateFormat('dd MMM yyyy').format(d);

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = _dob ?? DateTime(now.year - 25);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year - 5, now.month, now.day),
      helpText: 'Select date of birth'.tr(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.fromSeed(seedColor: AppThemeData.primary500),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dob = picked);
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
                const SizedBox(height: 24),

                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    'Details'.tr(),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 20,
                    ),
                  ),
                ),

                // Name Field
                _buildFormTextField(
                  labelText: 'Name'.tr(),
                  hintText: 'Enter your full name'.tr(),
                  controller: name,
                  validator: validateName,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  keyboardType: TextInputType.text,
                  maxLength: 50,
                ),
                const SizedBox(height: 20),

                // Email Field
                _buildFormTextField(
                  labelText: 'emailAddress'.tr(),
                  controller: email,
                  validator: validateEmail,
                  enabled: false,
                ),
                const SizedBox(height: 20),

                // Phone Number Field
                _buildFormTextField(
                  labelText: 'phoneNumber'.tr(),
                  controller: mobile,
                  enabled: false,
                ),
                const SizedBox(height: 20),

                // Date of Birth
                _buildDobField(isDarkModeEnabled, theme),

                const SizedBox(height: 40),
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

  Widget _buildDobField(bool isDarkModeEnabled, ThemeData theme) {
    final labelColor = isDarkModeEnabled ? AppThemeData.darkTextSecondary : AppThemeData.neutral600;
    final valueColor = isDarkModeEnabled ? AppThemeData.darkTextPrimary : AppThemeData.neutral800;
    final hintColor = isDarkModeEnabled ? AppThemeData.darkTextSecondary : AppThemeData.neutral400;

    // Locked: matches the disabled TextFormField style used for email/phone.
    final lockedBg = isDarkModeEnabled ? AppThemeData.darkBgSecondary : AppThemeData.neutral100;
    final activeBg = isDarkModeEnabled ? AppThemeData.darkBgTertiary : AppThemeData.neutral0;
    final borderColor = isDarkModeEnabled ? AppThemeData.darkBorderPrimary : AppThemeData.neutral300;

    final bgColor = _dobLocked ? lockedBg : activeBg;
    final textColor = _dobLocked
        ? (isDarkModeEnabled ? AppThemeData.darkTextSecondary : AppThemeData.neutral500)
        : (_dob != null ? valueColor : hintColor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Date of Birth'.tr(),
              style: theme.textTheme.labelMedium?.copyWith(color: labelColor),
            ),
            if (_dobLocked) ...[
              const SizedBox(width: 6),
              Icon(Icons.lock_outline_rounded, size: 13, color: hintColor),
            ],
          ],
        ),
        const SizedBox(height: 8.0),
        GestureDetector(
          onTap: _dobLocked ? null : _pickDob,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12.0),
              border: _dobLocked
                  ? Border.all(color: Colors.transparent)
                  : Border.all(color: borderColor, width: 1.0),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _dob != null ? _formatDob(_dob!) : 'Select date of birth'.tr(),
                    style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
                  ),
                ),
                Icon(
                  _dobLocked ? Icons.lock_outline_rounded : Icons.calendar_today_outlined,
                  size: 18,
                  color: hintColor,
                ),
              ],
            ),
          ),
        ),
        if (_dobLocked)
          Padding(
            padding: const EdgeInsets.only(top: 6.0, left: 4.0),
            child: Text(
              'Date of birth cannot be changed after saving.'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(color: hintColor),
            ),
          ),
      ],
    );
  }

  Widget _buildFormTextField({
    required String labelText,
    required TextEditingController controller,
    String? hintText,
    String? Function(String?)? validator,
    bool enabled = true,
    TextInputAction? textInputAction,
    TextCapitalization textCapitalization = TextCapitalization.none,
    TextInputType? keyboardType,
    int? maxLength,
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
        const SizedBox(height: 8.0),
        TextFormField(
          controller: controller,
          validator: validator,
          enabled: enabled,
          textInputAction: textInputAction,
          textCapitalization: textCapitalization,
          keyboardType: keyboardType,
          maxLength: maxLength,
          buildCounter: maxLength == null
              ? null
              : (context, {required currentLength, required isFocused, maxLength}) => null,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isDarkModeEnabled ? AppThemeData.darkTextPrimary : AppThemeData.neutral800,
          ),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
            hintText: hintText,
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: isDarkModeEnabled ? AppThemeData.darkTextTertiary : AppThemeData.neutral400,
            ),
            filled: true,
            fillColor: enabled
                ? (isDarkModeEnabled ? AppThemeData.darkBgTertiary : AppThemeData.neutral0)
                : (isDarkModeEnabled ? AppThemeData.darkBgSecondary : AppThemeData.neutral100),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
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
    if (!await DeviceSessionService.enforceActive(context)) return;
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
    MyAppState.currentUser!.dob = _dob != null
        ? DateFormat('yyyy-MM-dd').format(_dob!)
        : MyAppState.currentUser!.dob;

    await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!)
        .then((value) {
      if (value != null) {
        setState(() {
          MyAppState.currentUser = value;
          // Lock the DOB field now that it has been saved to Firestore.
          if (_dob != null) _dobLocked = true;
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
