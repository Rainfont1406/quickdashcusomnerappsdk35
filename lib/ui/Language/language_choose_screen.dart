import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/theme/round_button_fill.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'language_model.dart';

class LanguageChooseScreen extends StatefulWidget {
  final bool isContainer;

  const LanguageChooseScreen({Key? key, required this.isContainer}) : super(key: key);

  @override
  State<LanguageChooseScreen> createState() => _LanguageChooceScreenState();
}

class _LanguageChooceScreenState extends State<LanguageChooseScreen> with SingleTickerProviderStateMixin {
  var languageList = <LanguageModel>[];
  String selectedLanguage = "en";
  bool isLoading = true;

  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    loadData();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  void loadData() async {
    languageList.clear();
    await FireStoreUtils.firestore.collection(Setting).doc("languages").get().then((value) {
      List list = value.data()!["list"];
      for (int i = 0; i < list.length; i++) {
        if (list[i]['isActive'] == true) {
          LanguageModel languageModel = LanguageModel.fromJson(list[i]);
          languageList.add(languageModel);
        }
      }
    });
    SharedPreferences sp = await SharedPreferences.getInstance();
    if (sp.containsKey("languageCode")) {
      selectedLanguage = sp.getString("languageCode")!;
    }
    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkMode(context);
    return Scaffold(
      backgroundColor: isDark ? AppThemeData.surfaceDark : AppThemeData.surface,
      body: Column(
        children: [
          _buildGradientHeader(),
          Expanded(
            child: isLoading ? _buildShimmerList() : _buildLanguageList(),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(20.0),
        child: RoundedButtonFill(
          title: "Save".tr(),
          color: AppThemeData.primary500,
          textColor: AppThemeData.grey50,
          onPress: () async {
            SharedPreferences sp = await SharedPreferences.getInstance();
            sp.setString("languageCode", selectedLanguage);
            context.setLocale(Locale(selectedLanguage));

            if (widget.isContainer) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Language change successfully'.tr(),
                    style: const TextStyle(color: Colors.white),
                  ).tr(),
                  duration: const Duration(seconds: 2),
                  backgroundColor: Colors.black,
                ),
              );
            } else {
              Navigator.pop(context);
            }
          },
        ),
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
              if (!widget.isContainer)
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
              if (!widget.isContainer) const SizedBox(width: 12),
              Text(
                'Select Language'.tr(),
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

  Widget _buildShimmerList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 5,
      itemBuilder: (_, __) => AnimatedBuilder(
        animation: _shimmerController,
        builder: (context, _) {
          final color = Color.lerp(
            isDarkMode(context) ? AppThemeData.grey900 : AppThemeData.grey100,
            isDarkMode(context) ? AppThemeData.grey700 : AppThemeData.grey300,
            _shimmerController.value,
          )!;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: color,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLanguageList() {
    final isDark = isDarkMode(context);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: languageList.length,
      shrinkWrap: true,
      itemBuilder: (context, index) {
        final isSelected = languageList[index].slug == selectedLanguage;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: InkWell(
            onTap: () {
              setState(() {
                selectedLanguage = languageList[index].slug.toString();
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: isSelected
                    ? AppThemeData.primary500.withValues(alpha: 0.08)
                    : (isDark ? AppThemeData.darkBgSecondary : AppThemeData.neutral0),
                border: Border.all(
                  color: isSelected ? AppThemeData.primary500 : (isDark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral200),
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected
                    ? []
                    : [
                        BoxShadow(
                          color: const Color(0x08000000),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: languageList[index].flag != null
                          ? Image.network(
                              languageList[index].flag.toString(),
                              height: 36,
                              width: 52,
                              fit: BoxFit.cover,
                            )
                          : Image.network(
                              placeholderImage,
                              height: 36,
                              width: 52,
                              fit: BoxFit.cover,
                            ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        languageList[index].title.toString(),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected
                              ? AppThemeData.primary500
                              : (isDark ? AppThemeData.darkTextPrimary : AppThemeData.neutral800),
                        ),
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_circle_rounded, color: AppThemeData.primary500, size: 22),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
