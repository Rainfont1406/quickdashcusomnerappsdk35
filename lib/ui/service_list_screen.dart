import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/CurrencyModel.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/ui/container/ContainerScreen.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/SectionModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/utils/DarkThemeProvider.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:provider/provider.dart';


class ServiceListScreen extends StatefulWidget {
  const ServiceListScreen({super.key});

  @override
  State<ServiceListScreen> createState() => _ServiceListScreenState();
}

class _ServiceListScreenState extends State<ServiceListScreen> {
  List<SectionModel> sectionList = [];

  @override
  void initState() {
    getSection();
    super.initState();
  }

  getSection() async {
    await _autoSelectFirstService();
  }

  _autoSelectFirstService() async {
    try {
      ShowToastDialog.showLoader("Please wait");

      final currencyFuture = FireStoreUtils().getCurrency();
      final placeMarksFuture = placemarkFromCoordinates(
        MyAppState.selectedPosotion.location!.latitude,
        MyAppState.selectedPosotion.location!.longitude,
      );
      final sectionsFuture = FireStoreUtils.getSections();

      FireStoreUtils.getRazorPayDemo();
      FireStoreUtils.getPaypalSettingData();
      FireStoreUtils.getStripeSettingData();
      FireStoreUtils.getPayStackSettingData();
      FireStoreUtils.getFlutterWaveSettingData();
      FireStoreUtils.getPaytmSettingData();
      FireStoreUtils.getPayFastSettingData();
      FireStoreUtils.getWalletSettingData();
      FireStoreUtils.getMercadoPagoSettingData();
      FireStoreUtils.getOrangeMoneySettingData();
      FireStoreUtils.getXenditSettingData();
      FireStoreUtils.getMidTransSettingData();

      final currencyValue = await currencyFuture;
      currencyData = currencyValue ?? CurrencyModel(id: "", code: "USD", decimal: 2, isactive: true, name: "US Dollar", symbol: "\$", symbolatright: false);

      final placeMarks = await placeMarksFuture;
      country = placeMarks.first.country;

      sectionList = await sectionsFuture;

      if (sectionList.isEmpty) {
        ShowToastDialog.closeLoader();
        return;
      }

      SectionModel firstSection = sectionList[0];
      AppThemeData.primary300 = Color(int.parse(firstSection.color!.replaceFirst("#", "0xff")));

      if (auth.FirebaseAuth.instance.currentUser != null && MyAppState.currentUser != null) {
        User? user = await FireStoreUtils.getCurrentUser(MyAppState.currentUser!.userID);

        if (user!.role == USER_ROLE_CUSTOMER) {
          user.active = true;
          user.role = USER_ROLE_CUSTOMER;
          sectionConstantModel = firstSection;

          user.fcmToken = await FireStoreUtils.firebaseMessaging.getToken() ?? '';
          await FireStoreUtils.updateCurrentUser(user);
          ShowToastDialog.closeLoader();

          await Provider.of<CartDatabase>(context, listen: false).allCartProducts.then((value) {
            if (value.isNotEmpty) {
              Provider.of<CartDatabase>(context, listen: false).deleteAllProducts();
            }
            pushReplacement(context, ContainerScreen(user: user));
          });
        } else {
          ShowToastDialog.closeLoader();
          pushReplacement(context, const LoginScreen());
        }
      } else {
        sectionConstantModel = firstSection;
        ShowToastDialog.closeLoader();
        pushReplacement(context, ContainerScreen(user: null));
      }
    } catch (e) {
      ShowToastDialog.closeLoader();
      print("Error in auto-selection: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeChange = Provider.of<DarkThemeProvider>(context);
    return Scaffold(
      backgroundColor: themeChange.getThem() ? AppThemeData.surfaceDark : AppThemeData.surface,
      body: const SizedBox.shrink(),
    );
  }

}
