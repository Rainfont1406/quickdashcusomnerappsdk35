import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/controller/on_boarding_controller.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/auth_screen/auth_widgets.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/utils/network_image_widget.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
// Hide GetX's own String.tr getter (Trans extension) — it collides with
// easy_localization's String.tr() method, which is what the rest of the
// app actually uses for translations. GetX is only used here for its
// GetX<T>/Rx state management, not its i18n system.
import 'package:get/get.dart' hide Trans;
import 'package:shared_preferences/shared_preferences.dart';

class OnBoardingScreen extends StatelessWidget {
  const OnBoardingScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    return GetX<OnBoardingController>(
      init: OnBoardingController(),
      builder: (controller) {
        return Scaffold(
          backgroundColor: dark ? AppThemeData.surfaceDark : AppThemeData.surface,
          body: controller.isLoading.value
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 8),

                        // ── Skip ─────────────────────────────────────────
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              setFinishedOnBoarding();
                              pushReplacement(context, const LoginScreen());
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: AppThemeData.primary500,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                            child: Text(
                              'Skip'.tr(),
                              style: const TextStyle(
                                fontFamily: AppThemeData.semiBold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),

                        // ── Swipeable pages ──────────────────────────────
                        Expanded(
                          child: PageView.builder(
                            controller: controller.pageController,
                            onPageChanged: controller.selectedPageIndex.call,
                            itemCount: controller.onBoardingList.length,
                            itemBuilder: (context, index) {
                              final item = controller.onBoardingList[index];
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Image gets the lion's share of the page
                                  // and is never cropped — BoxFit.contain
                                  // shows the whole illustration, letterboxed
                                  // rather than clipped, whatever its aspect
                                  // ratio. See perfect-fit size guidance in
                                  // the file-level doc comment below.
                                  Expanded(
                                    flex: 5,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 16),
                                      child: NetworkImageWidget(
                                        imageUrl: item.image.toString(),
                                        fit: BoxFit.contain,
                                        width: double.infinity,
                                        height: double.infinity,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    item.title.toString(),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: dark
                                          ? AppThemeData.grey50
                                          : AppThemeData.grey900,
                                      fontSize: 24,
                                      fontFamily: AppThemeData.bold,
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    child: Text(
                                      item.description.toString(),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: dark
                                            ? AppThemeData.grey400
                                            : AppThemeData.grey600,
                                        fontSize: 14,
                                        fontFamily: AppThemeData.regular,
                                        height: 1.6,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ── Page dots ────────────────────────────────────
                        // Driven entirely by onBoardingList.length — never
                        // assumes a fixed page count.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            controller.onBoardingList.length,
                            (i) => AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: controller.selectedPageIndex.value == i
                                  ? 22
                                  : 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: controller.selectedPageIndex.value == i
                                    ? AppThemeData.primary500
                                    : (dark
                                        ? AppThemeData.grey700
                                        : AppThemeData.grey200),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ── Next / Get Started ───────────────────────────
                        // Uses the controller's own isLastPage (based on
                        // onBoardingList.length), not a hardcoded page index
                        // — works correctly no matter how many onboarding
                        // pages are configured in the admin panel.
                        AuthPrimaryButton(
                          label: controller.isLastPage
                              ? 'Get Started'.tr()
                              : 'Next'.tr(),
                          onTap: () {
                            if (controller.isLastPage) {
                              setFinishedOnBoarding();
                              pushReplacement(context, const LoginScreen());
                            } else {
                              controller.pageController.nextPage(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOut,
                              );
                            }
                          },
                        ),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  Future<bool> setFinishedOnBoarding() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.setBool(FINISHED_ON_BOARDING, true);
  }
}
