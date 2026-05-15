import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/on_boarding_model.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
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
    await FireStoreUtils.firestore.collection(Setting).doc("globalSettings").get().then((value) {
      if (value.exists) {
        AppThemeData.primary300 = Color(int.parse(value.data()!['app_customer_color'].replaceFirst("#", "0xff")));
      }
    });
    await FireStoreUtils.getOnBoardingList().then((value) {
      onBoardingList.value = value;
    });
    // onBoardingList.add(OnBoardingModel(
    //     id: "",
    //     title: "All-in-One Multi-Service App",
    //     description: "Discover eMart, the ultimate platform for food delivery, on-demand eCommerce, parcel services, taxi booking, and car rentals—all in one app.",
    //     image: "assets/images/image_1.png"));
    // onBoardingList.add(OnBoardingModel(
    //     id: "",
    //     title: "Convenient & Captivating User Experience",
    //     description:
    //         "Enjoy eMart’s modern UI that makes navigating multiple services a breeze. Whether it’s booking a taxi or ordering groceries, every service is at your fingertips.",
    //     image: "assets/images/image_2.png"));
    // onBoardingList.add(OnBoardingModel(
    //     id: "",
    //     title: "From Shopping to Rides, We’ve Got You Covered",
    //     description: "Manage vendors, orders, bookings, and transactions efficiently with a user-friendly interface.",
    //     image: "assets/images/image_3.png"));

    isLoading.value = false;
    update();
  }
}
