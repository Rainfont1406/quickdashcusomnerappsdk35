import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:emartconsumer/ui/chat_screen/admin_chat_screeen.dart';

class ContactUsScreen extends StatefulWidget {
  const ContactUsScreen({Key? key}) : super(key: key);

  @override
  _ContactUsScreenState createState() => _ContactUsScreenState();
}

class _ContactUsScreenState extends State<ContactUsScreen> {
  String address = '', phone = '', email = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    FireStoreUtils().getContactUs().then((value) {
      if (mounted) {
        setState(() {
          address = value['Address'] ?? '';
          phone = value['Phone'] ?? '';
          email = value['Email'] ?? '';
          _loading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    return Scaffold(
      backgroundColor: dark ? AppThemeData.darkBgPrimary : const Color(0xFFF2F4F8),
      appBar: AppBar(
        backgroundColor: dark ? AppThemeData.darkBgSecondary : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20,
              color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Contact Us'.tr(),
          style: TextStyle(
            fontSize: 18,
            fontFamily: AppThemeData.semiBold,
            color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
          ),
        ),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1,
              color: dark ? AppThemeData.darkBorderSecondary : AppThemeData.neutral200),
        ),
      ),
      body: _loading ? _buildShimmer(dark) : _buildBody(dark),
    );
  }

  Widget _buildBody(bool dark) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppThemeData.primary500, AppThemeData.primary600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppThemeData.primary500.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "We're here to help".tr(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontFamily: AppThemeData.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Reach out anytime — we respond quickly'.tr(),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                          fontFamily: AppThemeData.regular,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(CupertinoIcons.headphones, color: Colors.white, size: 26),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _sectionLabel('Get in Touch'.tr(), dark),
          const SizedBox(height: 10),
          // Phone
          _contactCard(
            dark: dark,
            icon: CupertinoIcons.phone_solid,
            iconBg: AppThemeData.primary500.withValues(alpha: 0.1),
            iconColor: AppThemeData.primary500,
            title: 'Call Us'.tr(),
            subtitle: phone.isNotEmpty ? phone : '—',
            actionLabel: 'Call Now'.tr(),
            onTap: phone.isNotEmpty ? () => launchUrl(Uri.parse('tel:$phone')) : null,
          ),
          const SizedBox(height: 12),
          // Email
          _contactCard(
            dark: dark,
            icon: CupertinoIcons.mail_solid,
            iconBg: const Color(0xFFEFF6FF),
            iconColor: const Color(0xFF2563EB),
            title: 'Email Us'.tr(),
            subtitle: email.isNotEmpty ? email : '—',
            actionLabel: 'Send Email'.tr(),
            onTap: email.isNotEmpty ? () => launchUrl(Uri.parse('mailto:$email')) : null,
          ),
          const SizedBox(height: 12),
          // Chat
          _contactCard(
            dark: dark,
            icon: CupertinoIcons.chat_bubble_2_fill,
            iconBg: const Color(0xFFF0FDF4),
            iconColor: const Color(0xFF16A34A),
            title: 'Live Chat'.tr(),
            subtitle: 'Chat with our support team'.tr(),
            actionLabel: 'Start Chat'.tr(),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AdminChatScreen()),
            ),
          ),
          const SizedBox(height: 24),
          if (address.isNotEmpty) ...[
            _sectionLabel('Our Location'.tr(), dark),
            const SizedBox(height: 10),
            _addressCard(dark),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, bool dark) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontFamily: AppThemeData.semiBold,
        letterSpacing: 0.8,
        color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral500,
      ),
    );
  }

  Widget _contactCard({
    required bool dark,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: dark ? AppThemeData.darkBgSecondary : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral200,
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: dark ? AppThemeData.darkBgTertiary : iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontFamily: AppThemeData.semiBold,
                        color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: AppThemeData.regular,
                        color: dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppThemeData.primary500.withValues(alpha: dark ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  actionLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: AppThemeData.semiBold,
                    color: AppThemeData.primary500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addressCard(bool dark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgSecondary : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral200,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: dark ? AppThemeData.darkBgTertiary : AppThemeData.primary50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(CupertinoIcons.location_solid, color: AppThemeData.primary500, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Our Address'.tr(),
                  style: TextStyle(
                    fontSize: 15,
                    fontFamily: AppThemeData.semiBold,
                    color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  address.replaceAll(r'\n', '\n'),
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: AppThemeData.regular,
                    height: 1.5,
                    color: dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmer(bool dark) {
    final shimmerColor = dark ? AppThemeData.darkBgTertiary : AppThemeData.neutral200;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        children: [
          _shimmerBox(shimmerColor, height: 110, radius: 20),
          const SizedBox(height: 24),
          _shimmerBox(shimmerColor, height: 78, radius: 16),
          const SizedBox(height: 12),
          _shimmerBox(shimmerColor, height: 78, radius: 16),
          const SizedBox(height: 12),
          _shimmerBox(shimmerColor, height: 78, radius: 16),
        ],
      ),
    );
  }

  Widget _shimmerBox(Color color, {required double height, double radius = 12}) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
