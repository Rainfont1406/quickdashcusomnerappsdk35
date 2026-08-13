import 'dart:async';

import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/CurrencyModel.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/ui/container/ContainerScreen.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/SectionModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/utils/DarkThemeProvider.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:provider/provider.dart';


class ServiceListScreen extends StatefulWidget {
  // (2026-08-04) Every caller (email/phone login, email/phone signup) already
  // has a fully-populated User object - including a freshly-fetched FCM
  // token - sitting in a local variable at the exact moment it navigates
  // here. Passing it through lets this screen skip both getCurrentUser()
  // (a second read of the identical document the caller just read/wrote)
  // and its own redundant FCM token re-fetch. Still fully optional - null
  // preserves the original re-fetch-from-scratch behavior for any caller
  // that doesn't have one handy.
  final User? user;
  const ServiceListScreen({super.key, this.user});

  @override
  State<ServiceListScreen> createState() => _ServiceListScreenState();
}

class _ServiceListScreenState extends State<ServiceListScreen> {
  List<SectionModel> sectionList = [];

  @override
  void initState() {
    // TEMPORARY [LOGIN-PERF] - this screen is invisible (SizedBox.shrink()
    // body below) and was previously completely unlogged - the 2026-08-03
    // investigation found a 36s gap between login completing and
    // ContainerScreen's own initState with nothing at all logged in
    // between; this screen's own async chain (below) is the prime suspect
    // since it's the only unlogged thing on the path. Remove all of this
    // once the real bottleneck step is identified and fixed.
    debugPrint('[LOGIN-PERF][SVC] ServiceListScreen initState ENTER (${DateTime.now().toIso8601String()})');
    getSection();
    super.initState();
  }

  getSection() async {
    await _autoSelectFirstService();
  }

  _autoSelectFirstService() async {
    final totalSw = Stopwatch()..start();
    try {
      ShowToastDialog.showLoader("Please wait");

      final currencySw = Stopwatch()..start();
      final currencyFuture = FireStoreUtils().getCurrency().then((r) {
        debugPrint('[LOGIN-PERF][SVC] getCurrency — ${currencySw.elapsedMilliseconds}ms');
        return r;
      });
      final placeMarksSw = Stopwatch()..start();
      final placeMarksFuture = placemarkFromCoordinates(
        MyAppState.selectedPosotion.location!.latitude,
        MyAppState.selectedPosotion.location!.longitude,
      ).then((r) {
        debugPrint('[LOGIN-PERF][SVC] placemarkFromCoordinates — ${placeMarksSw.elapsedMilliseconds}ms');
        return r;
      });
      final sectionsSw = Stopwatch()..start();
      final sectionsFuture = FireStoreUtils.getSections().then((r) {
        debugPrint('[LOGIN-PERF][SVC] getSections — ${sectionsSw.elapsedMilliseconds}ms');
        return r;
      });

      // Was 12 separate fire-and-forget calls, direct to FirebaseHelper —
      // already non-blocking, but bypassed ensurePaymentGatewaySettingsLoaded's
      // session-wide memoization, so Cart/Payment/Wallet/GiftCard reached
      // later in the same session would re-fetch all 12 from scratch. Routing
      // through the guard here fixes that without changing this screen's own
      // (already correct) non-blocking behavior.
      unawaited(FireStoreUtils.ensurePaymentGatewaySettingsLoaded());
      FireStoreUtils.getWalletSettingData();

      final currencyValue = await currencyFuture;
      currencyData = currencyValue ?? CurrencyModel(id: "", code: "USD", decimal: 2, isactive: true, name: "US Dollar", symbol: "\$", symbolatright: false);

      final placeMarks = await placeMarksFuture;
      country = placeMarks.first.country;

      sectionList = await sectionsFuture;
      debugPrint('[LOGIN-PERF][SVC] currency+placemark+sections all resolved — ${totalSw.elapsedMilliseconds}ms total so far');

      if (sectionList.isEmpty) {
        ShowToastDialog.closeLoader();
        return;
      }

      SectionModel firstSection = sectionList[0];
      AppThemeData.primary300 = Color(int.parse(firstSection.color!.replaceFirst("#", "0xff")));

      if (MyAppState.currentUser != null) {
        User? user;
        if (widget.user != null) {
          // Caller already has a fresh copy (including its own fresh FCM
          // token) - skip both the redundant Firestore read and the
          // redundant token re-fetch below entirely.
          user = widget.user;
          debugPrint('[LOGIN-PERF][SVC] using user passed from caller — skipped getCurrentUser() + FCM re-fetch');
        } else {
          final getCurrentUserSw = Stopwatch()..start();
          user = await FireStoreUtils.getCurrentUser(MyAppState.currentUser!.userID);
          debugPrint('[LOGIN-PERF][SVC] getCurrentUser — ${getCurrentUserSw.elapsedMilliseconds}ms');
        }

        if (user != null && user.role == USER_ROLE_CUSTOMER) {
          user.active = true;
          user.role = USER_ROLE_CUSTOMER;
          sectionConstantModel = firstSection;

          if (widget.user == null) {
            final getTokenSw = Stopwatch()..start();
            user.fcmToken = await FireStoreUtils.firebaseMessaging.getToken() ?? '';
            debugPrint('[LOGIN-PERF][SVC] firebaseMessaging.getToken (re-fetch, already have one from login) — ${getTokenSw.elapsedMilliseconds}ms');
          }
          // (2026-08-04) Was awaited here - measured 28.6s on a real device,
          // 71% of the entire login-to-Home time, on what is otherwise just
          // a routine profile-field refresh (active/role/fcmToken) for a
          // user who already exists (getCurrentUser above already confirmed
          // the doc exists and role == customer, unlike signup's version of
          // this same call, which creates the doc via .set(merge:true) and
          // must stay awaited). ContainerScreen(user: user) below is
          // constructed with this exact in-memory object directly, so it
          // never depends on the write landing - but ContainerScreen's own
          // *default* currentWidget falls back to HomeScreen(user:
          // MyAppState.currentUser, ...), reading global state rather than
          // this local variable, so it's set synchronously right here
          // (matching updateCurrentUser's own would-be side effect) instead
          // of relying on the now-backgrounded write's completion callback.
          MyAppState.currentUser = user;
          unawaited(FireStoreUtils.updateCurrentUser(user));
          debugPrint('[LOGIN-PERF][SVC] updateCurrentUser (now fire-and-forget) — dispatched, not awaited');
          ShowToastDialog.closeLoader();
          debugPrint('[LOGIN-PERF][SVC] TOTAL before cart check — ${totalSw.elapsedMilliseconds}ms');

          final cartSw = Stopwatch()..start();
          await Provider.of<CartDatabase>(context, listen: false).allCartProducts.then((value) {
            debugPrint('[LOGIN-PERF][SVC] allCartProducts — ${cartSw.elapsedMilliseconds}ms');
            if (value.isNotEmpty) {
              Provider.of<CartDatabase>(context, listen: false).deleteAllProducts();
            }
            debugPrint('[LOGIN-PERF][SVC] TOTAL (about to pushReplacement ContainerScreen) — ${totalSw.elapsedMilliseconds}ms');
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
