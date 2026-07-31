import 'package:clipboard/clipboard.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/model/referral_model.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:emartconsumer/constants.dart';
import 'package:share_plus/share_plus.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({Key? key}) : super(key: key);

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  ReferralModel? referralModel = ReferralModel();
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    getReferralCode();
  }

  getReferralCode() async {
    await FireStoreUtils.getReferralUserBy().then((value) {
      setState(() {
        isLoading = false;
        referralModel = value;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildGradientHeader(),
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator.adaptive(
                      valueColor: AlwaysStoppedAnimation(AppThemeData.primary500),
                    ),
                  )
                : referralModel == null
                    ? Center(child: Text('Something went wrong'.tr()))
                    : _buildContent(),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
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
                    'Refer a Friend'.tr(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Image.asset('assets/images/earn_icon.png', width: 120),
              const SizedBox(height: 16),
              Text(
                'Refer your friends and'.tr(),
                style: const TextStyle(color: Colors.white, letterSpacing: 1.2),
              ),
              const SizedBox(height: 6),
              if (!isLoading && referralModel != null)
                Text(
                  '${'Earn'.tr()} ${amountShow(amount: sectionConstantModel!.referralAmount.toString())} ${'each'.tr()}',
                  style: const TextStyle(
                    fontSize: 22,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Invite Friend & Businesses'.tr(),
              style: TextStyle(
                color: isDarkMode(context) ? AppThemeData.darkTextPrimary : Colors.black,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
                fontSize: 18,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              '${'Invite Friend to sign up using your code and you\'ll get'.tr()} ${amountShow(amount: sectionConstantModel!.referralAmount.toString())} ${'after successfully order complete.'.tr()}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0XFF666666), fontWeight: FontWeight.w500, letterSpacing: 1.0),
            ),
            const SizedBox(height: 40),
            GestureDetector(
              onTap: () {
                FlutterClipboard.copy(referralModel!.referralCode.toString()).then((_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Coupon code copied'.tr(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                });
              },
              child: DottedBorder(
                borderType: BorderType.RRect,
                radius: const Radius.circular(8),
                padding: const EdgeInsets.all(16),
                color: AppThemeData.primary500,
                strokeWidth: 2,
                dashPattern: const [5],
                child: Container(
                  constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width * 0.3),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: AppThemeData.primary50,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        referralModel!.referralCode.toString(),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.0,
                          fontSize: 18,
                          color: AppThemeData.primary500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.copy_rounded, size: 18, color: AppThemeData.primary500),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppThemeData.primary500,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25.0),
                  ),
                  elevation: 0,
                ),
                onPressed: share,
                child: Text(
                  'Refer Friend'.tr(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> share() async {
    await Share.share(
      '${'Hey there! Use my referral code'.tr()} ${referralModel!.referralCode.toString()} ${'on QuickDash and get'.tr()} ${amountShow(amount: sectionConstantModel!.referralAmount.toString())} ${'when your first order is completed!'.tr()}\n\n${'Download QuickDash now:'.tr()}\nhttps://play.google.com/store/apps/details?id=com.quickdash.hadeveloper',
      subject: 'QuickDash',
    );
  }
}
