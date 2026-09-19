import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/on_boarding_model.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/firestore_instrumentation.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class OnBoardingController extends GetxController {
  var selectedPageIndex = 0.obs;

  bool get isLastPage => selectedPageIndex.value == onBoardingList.length - 1;
  var pageController = PageController();

  @override
  void onInit() {
    getOnBoardingData();
    super.onInit();
  }

  RxBool isLoading = true.obs;
  RxList<OnBoardingModel> onBoardingList = <OnBoardingModel>[].obs;

  getOnBoardingData() async {
    try {
      // 2026-09-19: was a raw .get(), invisible to FirestoreReadStats - a
      // second, independent unlogged read of the exact same doc main.dart's
      // own warm-up call already reads.
      final value = await FireStoreUtils.firestore
          .collection(Setting)
          .doc("globalSettings")
          .getLogged('OnBoardingController:globalSettings')
          .timeout(const Duration(seconds: 10));
      if (value.exists) {
        final rawColor = value.data()?['app_customer_color'];
        if (rawColor is String && rawColor.isNotEmpty) {
          try {
            AppThemeData.primary300 = Color(int.parse(rawColor.replaceFirst("#", "0xff")));
          } catch (e) {
            debugPrint('OnBoarding: bad app_customer_color "$rawColor" -> $e');
          }
        }
      }
    } catch (e) {
      debugPrint('OnBoarding: failed to load globalSettings -> $e');
    }

    try {
      final value = await FireStoreUtils.getOnBoardingList().timeout(const Duration(seconds: 10));
      onBoardingList.value = value;
    } catch (e) {
      debugPrint('OnBoarding: failed to load onboarding list -> $e');
    }

    isLoading.value = false;
    update();
  }
}
