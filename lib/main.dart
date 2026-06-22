import 'dart:async';
import 'dart:developer';
import 'package:flutter/foundation.dart';

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
import 'package:flutter/services.dart';
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
  await FirebaseAppCheck.instance.activate(
    androidProvider: kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug,
    appleProvider: kReleaseMode ? AppleProvider.appAttest : AppleProvider.debug,
  );
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

  // App is portrait-only by design (no screen has a responsive landscape
  // layout) — enforced here too since Android split-screen/freeform
  // multi-window can override the manifest's screenOrientation attribute.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

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
        if (value.exists) appVersion = value.data()!['app_version'].toString();
      });

      await FireStoreUtils.firestore
          .collection(Setting)
          .doc("googleMapKey")
          .get()
          .then((value) {
        if (value.exists) GOOGLE_API_KEY = value.data()!['key'].toString();
      });

      await FireStoreUtils.firestore
          .collection(Setting)
          .doc("DriverNearBy")
          .get()
          .then((value) {
        if (value.exists) selectedMapType = value.data()!['selectedMapType'].toString();
      });

      await FireStoreUtils.firestore
          .collection(Setting)
          .doc("notification_setting")
          .get()
          .then((value) {
        if (value.exists) {
          senderId = value.data()!['senderId'].toString();
          jsonNotificationFileURL = value.data()!['serviceJson'].toString();
        }
      });

      await FireStoreUtils.firestore
          .collection(Setting)
          .doc("placeHolderImage")
          .get()
          .then((value) {
        if (value.exists) placeholderImage = value.data()!['image'].toString();
      });

      SharedPreferences sp = await SharedPreferences.getInstance();
      final langCode = sp.getString("languageCode");
      if (langCode != null && langCode.isNotEmpty) {
        context.setLocale(Locale(langCode));
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-sync lightweight global settings (theme colour, wallet, currency)
      // so they reflect any admin changes made while the app was backgrounded.
      initializeFlutterFire();
      FireStoreUtils.getWalletSettingData();
    }
  }
}

class OnBoarding extends StatefulWidget {
  const OnBoarding({Key? key}) : super(key: key);

  @override
  State createState() {
    return OnBoardingState();
  }
}

class OnBoardingState extends State<OnBoarding> with TickerProviderStateMixin {

  // ── Animation controllers ──────────────────────────────────────────────
  late final AnimationController _logoCtrl;
  late final AnimationController _contentCtrl;

  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _titleOpacity;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _taglineOpacity;
  late final Animation<Offset> _taglineSlide;
  late final Animation<double> _sublineOpacity;
  late final Animation<double> _loadingOpacity;

  // ── Firebase routing ───────────────────────────────────────────────────
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
                FireStoreUtils.getPhonePaySettingData();

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
        // No Firebase Auth session — try to restore a MSG91 phone user's session
        final savedPhoneUid = prefs.getString(PHONE_AUTH_USER_ID);
        if (savedPhoneUid != null && savedPhoneUid.isNotEmpty) {
          User? user = await FireStoreUtils.getCurrentUser(savedPhoneUid);
          if (user != null && user.role == USER_ROLE_CUSTOMER && user.active) {
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
              final sections = await FireStoreUtils.getSections();
              if (sections.isNotEmpty) {
                sectionConstantModel = sections.first;
                if (sectionConstantModel?.color != null) {
                  AppThemeData.primary300 = Color(
                    int.parse(sectionConstantModel!.color!
                        .replaceFirst("#", "0xff")),
                  );
                }
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
                FireStoreUtils.getPhonePaySettingData();
              }
              pushReplacement(
                  context,
                  ContainerScreen(
                    user: MyAppState.currentUser!,
                    currentWidget: HomeScreen(user: MyAppState.currentUser!),
                    appBarTitle: 'Home',
                    drawerSelection: DrawerSelection.Home,
                  ));
            } else {
              pushAndRemoveUntil(context, LocationPermissionScreen());
            }
          } else {
            // Stored session is invalid or user deactivated — clear it
            await prefs.remove(PHONE_AUTH_USER_ID);
            pushReplacement(context, const LoginScreen());
          }
        } else {
          pushReplacement(context, const LoginScreen());
        }
      }
    } else {
      pushReplacement(context, const OnBoardingScreen());
    }
  }

  @override
  void initState() {
    super.initState();
    _initAnimations();
    hasFinishedOnBoarding();
  }

  void _initAnimations() {
    // Logo: scale-in + fade-in
    _logoCtrl = AnimationController(
      duration: const Duration(milliseconds: 650),
      vsync: this,
    );
    _logoOpacity = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOut);
    _logoScale = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutBack),
    );

    // Staggered text content
    _contentCtrl = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _titleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _contentCtrl,
          curve: const Interval(0.0, 0.55, curve: Curves.easeOut)),
    );
    _titleSlide = Tween<Offset>(
            begin: const Offset(0, 0.35), end: Offset.zero)
        .animate(CurvedAnimation(parent: _contentCtrl,
            curve: const Interval(0.0, 0.6, curve: Curves.easeOut)));
    _taglineOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _contentCtrl,
          curve: const Interval(0.2, 0.75, curve: Curves.easeOut)),
    );
    _taglineSlide = Tween<Offset>(
            begin: const Offset(0, 0.4), end: Offset.zero)
        .animate(CurvedAnimation(parent: _contentCtrl,
            curve: const Interval(0.25, 0.8, curve: Curves.easeOut)));
    _sublineOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _contentCtrl,
          curve: const Interval(0.4, 0.9, curve: Curves.easeOut)),
    );
    _loadingOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _contentCtrl,
          curve: const Interval(0.65, 1.0, curve: Curves.easeOut)),
    );

    _logoCtrl.forward();
    Future.delayed(const Duration(milliseconds: 320), () {
      if (mounted) _contentCtrl.forward();
    });
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  // ── Logo mark: blue rounded container with white "Q" ─────────────────

  Widget _buildLogoMark() {
    return Container(
      width: 116,
      height: 116,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppThemeData.primary400, AppThemeData.primary600],
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: AppThemeData.primary500.withValues(alpha: 0.28),
            blurRadius: 40,
            offset: const Offset(0, 16),
            spreadRadius: -4,
          ),
          BoxShadow(
            color: AppThemeData.primary500.withValues(alpha: 0.12),
            blurRadius: 80,
            offset: const Offset(0, 32),
            spreadRadius: -8,
          ),
        ],
      ),
      child: const Center(
        child: Text(
          'Q',
          style: TextStyle(
            fontSize: 66,
            fontFamily: AppThemeData.bold,
            color: Colors.white,
            height: 1.0,
            letterSpacing: -3.0,
          ),
        ),
      ),
    );
  }

  // ── Subtle blue-tinted decorative circle (for white bg) ───────────────

  Widget _bgCircle(double size, double opacity) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppThemeData.primary100.withValues(alpha: opacity),
        ),
      );

  // ── Outlined service pill (blue border + fill on white bg) ────────────

  Widget _servicePill(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppThemeData.primary50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppThemeData.primary200,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppThemeData.primary500,
            fontSize: 11.5,
            fontFamily: AppThemeData.semiBold,
            letterSpacing: 0.3,
            height: 1.2,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF7C3AED),
      body: FadeTransition(
        opacity: _logoOpacity,
        child: Stack(
          children: [
            // ── Full-screen gradient background ───────────────────────
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF9651F5), Color(0xFF7C3AED)],
                ),
              ),
            ),

            // ── Centered logo image ───────────────────────────────────
            Center(
              child: Image.asset(
                'assets/images/quickdash_icon_1024.png',
                width: screenWidth,
                fit: BoxFit.fitWidth,
              ),
            ),

            // ── Loading indicator at bottom ───────────────────────────
            Positioned(
              bottom: bottomPad + 48,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _loadingOpacity,
                child: const Column(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white54),
                        strokeWidth: 2.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
