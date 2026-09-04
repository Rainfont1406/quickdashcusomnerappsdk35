import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/firestore_instrumentation.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({Key? key}) : super(key: key);

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  String? _privacyHtml;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    FireStoreUtils.firestore.collection(Setting).doc('privacyPolicy').getLogged('initState:Setting').then((value) {
      if (mounted) {
        setState(() {
          _privacyHtml = value['privacy_policy']?.toString();
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => _error = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    return Scaffold(
      backgroundColor: dark ? AppThemeData.surfaceDark : const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: dark ? AppThemeData.darkBgSecondary : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Privacy Policy'.tr(),
          style: TextStyle(
            fontSize: 18,
            fontFamily: AppThemeData.semiBold,
            color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
          ),
        ),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: dark ? AppThemeData.darkBorderSecondary : AppThemeData.neutral200,
          ),
        ),
      ),
      body: _buildBody(dark),
    );
  }

  Widget _buildBody(bool dark) {
    if (_error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 52,
                  color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral400),
              const SizedBox(height: 16),
              Text(
                'Failed to load privacy policy'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontFamily: AppThemeData.medium,
                  color: dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_privacyHtml == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              valueColor: const AlwaysStoppedAnimation<Color>(AppThemeData.primary500),
              strokeWidth: 2.5,
            ),
            const SizedBox(height: 16),
            Text(
              'Loading...'.tr(),
              style: TextStyle(
                fontSize: 14,
                fontFamily: AppThemeData.regular,
                color: dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral500,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header card
          Container(
            margin: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppThemeData.primary500, AppThemeData.primary600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppThemeData.primary500.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.privacy_tip_rounded, color: Colors.white, size: 32),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Privacy Matters'.tr(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontFamily: AppThemeData.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Last updated: ${DateFormat('MMMM d, y').format(DateTime.now())}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                          fontFamily: AppThemeData.regular,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Policy content
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: dark ? AppThemeData.darkBgSecondary : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral200,
                width: 1,
              ),
            ),
            child: HtmlWidget(
              _privacyHtml!,
              textStyle: TextStyle(
                fontSize: 14.5,
                fontFamily: AppThemeData.regular,
                height: 1.65,
                color: dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral700,
              ),
              onErrorBuilder: (context, element, error) =>
                  Text('$element error: $error', style: TextStyle(color: AppThemeData.error500)),
              onLoadingBuilder: (context, element, loadingProgress) =>
                  const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
        ],
      ),
    );
  }
}
