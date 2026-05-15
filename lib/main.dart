import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/firebase_options.dart';
import 'package:emartconsumer/model/AddressModel.dart';
import 'package:emartconsumer/model/CurrencyModel.dart';
import 'package:emartconsumer/model/mail_setting.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/services/notification_service.dart';
import 'package:emartconsumer/ui/container/ContainerScreen.dart';
import 'package:emartconsumer/ui/home/HomeScreen.dart';
import 'package:emartconsumer/ui/service_list_screen.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/ui/location_permission_screen.dart';
import 'package:emartconsumer/ui/onBoarding/on_boarding_screen.dart';
import 'package:emartconsumer/userPrefrence.dart';
import 'package:emartconsumer/utils/Styles.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'model/User.dart';
import 'theme/app_them_data.dart';
import 'utils/DarkThemeProvider.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // TODO: Re-enable App Check with proper configuration for production
  // await FirebaseAppCheck.instance.activate(
  //   webProvider: ReCaptchaV3Provider('recaptcha-v3-site-key'),
  //   androidProvider: AndroidProvider.playIntegrity,
  //   appleProvider: AppleProvider.appAttest,
  // );
  await EasyLocalization.ensureInitialized();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    announcement: false,
    badge: true,
    carPlay: false,
    criticalAlert: false,
    provisional: false,
    sound: true,
  );

  await UserPreference.init();

  runApp(
    MultiProvider(
      providers: [
        Provider<CartDatabase>(
          create: (_) => CartDatabase(),
        )
      ],
      child: EasyLocalization(
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('nl')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          saveLocale: false,
          useOnlyLangCode: true,
          useFallbackTranslations: true,
          child: const MyApp()),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  static User? currentUser;
  static AddressModel selectedPosotion = AddressModel();

  //  late Stream<StripeKeyModel> futureStirpe;
  //  String? data,d;

  // Define an async function to initialize FlutterFire
  NotificationService notificationService = NotificationService();

  notificationInit() {
    notificationService.initInfo().then((value) async {
      String token = await NotificationService.getToken();
      log(":::::::TOKEN:::::: $token");
      if (currentUser != null) {
        await FireStoreUtils.getCurrentUser(currentUser!.userID).then((value) {
          if (value != null) {
            currentUser = value;
            currentUser!.fcmToken = token;
            FireStoreUtils.updateCurrentUser(currentUser!);
          }
        });
      }
    });
  }

  // Define an async function to initialize FlutterFire
  void initializeFlutterFire() async {
    try {
      await FireStoreUtils.firestore
          .collection(Setting)
          .doc("globalSettings")
          .get()
          .then((value) {
        if (value.exists) {
          AppThemeData.primary300 = Color(int.parse(
              value.data()!['app_customer_color'].replaceFirst("#", "0xff")));
        }
      });
      await FireStoreUtils.firestore
          .collection(Setting)
          .doc("emailSetting")
          .get()
          .then((value) {
        if (value.exists) {
          mailSettings = MailSettings.fromJson(value.data()!);
        }
      });
      await FireStoreUtils.firestore
          .collection(Setting)
          .doc("Version")
          .get()
          .then((value) {
        appVersion = value.data()!['app_version'].toString();
      });

      await FireStoreUtils.firestore
          .collection(Setting)
          .doc("googleMapKey")
          .get()
          .then((value) {
        GOOGLE_API_KEY = value.data()!['key'].toString();
      });

      await FireStoreUtils.firestore
          .collection(Setting)
          .doc("DriverNearBy")
          .get()
          .then((value) {
        selectedMapType = value.data()!['selectedMapType'].toString();
      });

      await FireStoreUtils.firestore
          .collection(Setting)
          .doc("notification_setting")
          .get()
          .then((value) {
        senderId = value.data()!['senderId'].toString();
        jsonNotificationFileURL = value.data()!['serviceJson'].toString();
      });

      await FireStoreUtils.firestore
          .collection(Setting)
          .doc("placeHolderImage")
          .get()
          .then((value) {
        placeholderImage = value.data()!['image'].toString();
      });

      SharedPreferences sp = await SharedPreferences.getInstance();
      if (sp.getString("languageCode") != null ||
          sp.getString("languageCode")!.isNotEmpty) {
        context.setLocale(Locale(sp.getString("languageCode") ?? "en"));
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  DarkThemeProvider themeChangeProvider = DarkThemeProvider();

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        return themeChangeProvider;
      },
      child: Consumer<DarkThemeProvider>(
        builder: (context, value, child) {
          return MaterialApp(
              navigatorKey: notificationService.navigatorKey,
              localizationsDelegates: context.localizationDelegates,
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              debugShowCheckedModeBanner: false,
              theme: Styles.themeData(false, context),
              darkTheme: Styles.themeData(true, context),
              themeMode: themeChangeProvider.darkTheme ? ThemeMode.dark : ThemeMode.light,
              builder: EasyLoading.init(),
              home: const OnBoarding());
        },
      ),
    );
  }

  late StreamSubscription eventBusStream;

  @override
  void initState() {
    notificationInit();
    initializeFlutterFire();
    WidgetsBinding.instance.addObserver(this);
    getCurrentAppTheme();
    _configureEasyLoading();
    super.initState();
  }

  void _configureEasyLoading() {
    EasyLoading.instance
      ..displayDuration = const Duration(milliseconds: 2500)
      ..indicatorType = EasyLoadingIndicatorType.threeBounce
      ..loadingStyle = EasyLoadingStyle.custom
      ..indicatorSize = 32.0
      ..radius = 16.0
      ..backgroundColor = const Color(0xFF111827).withOpacity(0.92)
      ..indicatorColor = Colors.white
      ..textColor = Colors.white
      ..maskColor = Colors.black.withOpacity(0.3)
      ..userInteractions = false
      ..dismissOnTap = false;
  }

  void getCurrentAppTheme() async {
    themeChangeProvider.darkTheme =
        await themeChangeProvider.darkThemePreference.getTheme();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}
}

class OnBoarding extends StatefulWidget {
  const OnBoarding({Key? key}) : super(key: key);

  @override
  State createState() {
    return OnBoardingState();
  }
}

class OnBoardingState extends State<OnBoarding> {
  late Future<List<CurrencyModel>> futureCurrency;

  Future hasFinishedOnBoarding() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool finishedOnBoarding = (prefs.getBool(FINISHED_ON_BOARDING) ?? false);

    if (finishedOnBoarding) {
      auth.User? firebaseUser = auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        User? user = await FireStoreUtils.getCurrentUser(firebaseUser.uid);
        if (user != null && user.role == USER_ROLE_CUSTOMER) {
          if (user.active) {
            user.active = true;
            user.role = USER_ROLE_CUSTOMER;
            user.fcmToken =
                await FireStoreUtils.firebaseMessaging.getToken() ?? '';
            await FireStoreUtils.updateCurrentUser(user);
            MyAppState.currentUser = user;

            if (MyAppState.currentUser!.shippingAddress != null &&
                MyAppState.currentUser!.shippingAddress!.isNotEmpty) {
              if (MyAppState.currentUser!.shippingAddress!
                  .where((element) => element.isDefault == true)
                  .isNotEmpty) {
                MyAppState.selectedPosotion = MyAppState
                    .currentUser!.shippingAddress!
                    .where((element) => element.isDefault == true)
                    .single;
              } else {
                MyAppState.selectedPosotion =
                    MyAppState.currentUser!.shippingAddress!.first;
              }
              // --- Begin: Set section info as ServiceListScreen does ---
              final sections = await FireStoreUtils.getSections();
              if (sections.isNotEmpty) {
                sectionConstantModel = sections.first;

                if (sectionConstantModel?.color != null) {
                  AppThemeData.primary300 = Color(
                    int.parse(sectionConstantModel!.color!
                        .replaceFirst("#", "0xff")),
                  );
                }

                // Payment gateway methods use .then() internally and return
                // immediately — kick them off now so their Firestore requests
                // run while we await the FCM token
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

                MyAppState.currentUser!.fcmToken =
                    await FireStoreUtils.firebaseMessaging.getToken() ?? '';
                await FireStoreUtils.updateCurrentUser(
                    MyAppState.currentUser!);
              }

              // Push to HomeScreen with drawer support
              pushReplacement(
                  context,
                  ContainerScreen(
                    user: MyAppState.currentUser!,
                    currentWidget: HomeScreen(user: MyAppState.currentUser!),
                    appBarTitle: 'Home',
                    drawerSelection: DrawerSelection.Home,
                  ));
              // --- End ---
            } else {
              pushAndRemoveUntil(context, LocationPermissionScreen());
            }
          } else {
            user.lastOnlineTimestamp = Timestamp.now();
            user.fcmToken = "";
            await FireStoreUtils.updateCurrentUser(user);
            await auth.FirebaseAuth.instance.signOut();
            MyAppState.currentUser = null;
            pushReplacement(context, const LoginScreen());
          }

          //UserPreference.setUserId(userID: user.userID);
          //
        } else {
          pushReplacement(context, const LoginScreen());
        }
      } else {
        pushReplacement(context, const LoginScreen());
      }
    } else {
      pushReplacement(context, const OnBoardingScreen());
    }
  }

  @override
  void initState() {
    super.initState();

    hasFinishedOnBoarding();
    // futureCurrency= FireStoreUtils().getCurrency();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppThemeData.primary500, AppThemeData.primary400],
          ),
        ),
        child: Stack(
          children: [
            // Decorative background circles
            Positioned(
              top: -70,
              right: -70,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
            ),
            Positioned(
              top: 60,
              right: 30,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),
            Positioned(
              bottom: -90,
              left: -90,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
            ),
            Positioned(
              bottom: 110,
              left: 24,
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),
            // Main content
            SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  // App logo
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 32,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(18),
                    child: Image.asset(
                      'assets/images/app_logo_new.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 28),
                  // App name
                  const Text(
                    'QuickDash',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontFamily: AppThemeData.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Tagline
                  Text(
                    'Food  ·  Delivery  ·  Services',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.72),
                      fontSize: 13,
                      fontFamily: AppThemeData.regular,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const Spacer(flex: 3),
                  // Loading spinner
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.white.withOpacity(0.85),
                      ),
                      strokeWidth: 2.2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Getting things ready…',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                      fontFamily: AppThemeData.regular,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 52),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
