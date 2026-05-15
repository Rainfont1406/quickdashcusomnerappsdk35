import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/controller/on_boarding_controller.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/theme/responsive.dart';
import 'package:emartconsumer/theme/round_button_fill.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/utils/DarkThemeProvider.dart';
import 'package:emartconsumer/utils/network_image_widget.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

class OnBoardingScreen extends StatelessWidget {
  const OnBoardingScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeChange = Provider.of<DarkThemeProvider>(context);
    return GetX<OnBoardingController>(
      init: OnBoardingController(),
      builder: (controller) {
        return Scaffold(
          backgroundColor: isDarkMode(context) ? AppThemeData.surfaceDark : AppThemeData.surface,
          body: controller.isLoading.value
              ? Center(child: CircularProgressIndicator())
              : Container(
                  color: themeChange.getThem() ? AppThemeData.surfaceDark : AppThemeData.surface,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 50),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: RoundedButtonFill(
                              title: "Skip",
                              width: 20,
                              height: 5,
                              color: themeChange.getThem() ? AppThemeData.primary600 : AppThemeData.primary50,
                              textColor: AppThemeData.primary500,
                              onPress: () {
                                setFinishedOnBoarding();
                                pushReplacement(context, const LoginScreen());
                              },
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 20,
                        ),
                        Expanded(
                          child: PageView.builder(
                              controller: controller.pageController,
                              onPageChanged: controller.selectedPageIndex.call,
                              itemCount: controller.onBoardingList.length,
                              itemBuilder: (context, index) {
                                return Column(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      controller.onBoardingList[index].title.toString(),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: themeChange.getThem() ? AppThemeData.grey50 : AppThemeData.grey900,
                                        fontSize: 24,
                                        fontFamily: AppThemeData.semiBold,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                    const SizedBox(
                                      height: 12,
                                    ),
                                    Text(
                                      controller.onBoardingList[index].description.toString(),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: themeChange.getThem() ? AppThemeData.grey300 : AppThemeData.grey600,
                                        fontSize: 14,
                                        fontFamily: AppThemeData.regular,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                    const SizedBox(
                                      height: 12,
                                    ),
                                    Expanded(
                                      child: NetworkImageWidget(
                                        imageUrl: controller.onBoardingList[controller.selectedPageIndex.value].image.toString(),
                                        width: Responsive.width(90, context),
                                      ),
                                    ),
                                  ],
                                );
                              }),
                        ),
                        const SizedBox(
                          height: 32,
                        ),
                        RoundedButtonFill(
                          title: controller.selectedPageIndex.value == 2 ? "Get Started" : "Next",
                          width: 60,
                          color: controller.selectedPageIndex == 2
                              ? isDarkMode(context)
                                  ? AppThemeData.grey50
                                  : AppThemeData.grey900
                              : isDarkMode(context)
                                  ? AppThemeData.grey900
                                  : AppThemeData.grey200,
                          textColor: controller.selectedPageIndex == 2
                              ? isDarkMode(context)
                                  ? AppThemeData.grey900
                                  : AppThemeData.grey50
                              : isDarkMode(context)
                                  ? AppThemeData.grey50
                                  : AppThemeData.grey900,
                          onPress: () {
                            if (controller.selectedPageIndex.value == 2) {
                              setFinishedOnBoarding();
                              pushReplacement(context, const LoginScreen());
                            } else {
                              controller.pageController.jumpToPage(controller.selectedPageIndex.value + 1);
                            }
                          },
                        ),
                        const SizedBox(
                          height: 20,
                        ),
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
