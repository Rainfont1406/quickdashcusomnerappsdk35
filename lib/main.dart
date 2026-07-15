import 'dart:async';
import 'dart:developer';
import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/firebase_options.dart';
import 'package:emartconsumer/firebase_options_staging.dart' as staging;
import 'package:emartconsumer/model/AddressModel.dart';
import 'package:emartconsumer/model/CurrencyModel.dart';
import 'package:emartconsumer/model/mail_setting.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/connectivity_gate.dart';
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

/// Picks staging vs production Firebase config based on the `--flavor` the
/// app was built with (set in android/app/build.gradle productFlavors).
FirebaseOptions get _activeFirebaseOptions => appFlavor == 'staging'
    ? staging.DefaultFirebaseOptions.currentPlatform
    : DefaultFirebaseOptions.currentPlatform;

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: _activeFirebaseOptions,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: _activeFirebaseOptions);

  // Replace the default red/yellow crash screen with a friendly error page.
  // This catches any widget that throws during build() — navigation errors,
  // null assertions, assertion failures from Flutter framework, etc.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return _AppErrorScreen(details: details);
  };

  // Fire-and-forget: Play Integrity/App Attest attestation is a network
  // round-trip and must not delay the first frame. (Notification permission
  // request and FCM presentation options are handled once, in
  // NotificationService.initInfo(), after the first frame.)
  unawaited(FirebaseAppCheck.instance.activate(
    androidProvider: kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug,
    appleProvider: kReleaseMode ? AppleProvider.appAttest : AppleProvider.debug,
  ));

  // Fire-and-forget Firestore warm-up: measured startup logs showed the
  // *first* Firestore call in a session pays a one-time gRPC channel/
  // connection-setup cost of ~5.7-6.2s, vs ~400-700ms for every call after
  // it (confirmed to be Firestore itself, not an Auth token refresh — the ID
  // token was fetched separately and returned in ~150ms). Reading a small,
  // publicly-readable doc here, concurrently with the rest of this
  // function's startup work, pays that one-time cost off the user's path so
  // hasFinishedOnBoarding()'s real getCurrentUser() call — which used to be
  // the one eating this cost inline — hits an already-warm connection.
  // Result is discarded either way; only the connection side effect matters.
  unawaited(_timedStep(
          'Firestore warm-up (globalSettings, throwaway)',
          () => FireStoreUtils.firestore
              .collection(Setting)
              .doc('globalSettings')
              .get())
      .catchError((_) {}));

  await EasyLocalization.ensureInitialized();

  // Pre-decode splash logo into image cache so the first Flutter frame
  // renders it immediately — no blank-purple-then-logo flash.
  const AssetImage('assets/images/quickdash_logo_white.png')
      .resolve(const ImageConfiguration())
      .addListener(ImageStreamListener((_, __) {}));

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

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
      // These 7 settings docs are independent of each other — fetch them
      // concurrently instead of awaiting each network round-trip in series.
      final settingsCollection = FireStoreUtils.firestore.collection(Setting);
      final results = await Future.wait([
        settingsCollection.doc("globalSettings").get(),
        settingsCollection.doc("emailSetting").get(),
        settingsCollection.doc("Version").get(),
        settingsCollection.doc("googleMapKey").get(),
        settingsCollection.doc("DriverNearBy").get(),
        settingsCollection.doc("notification_setting").get(),
        settingsCollection.doc("placeHolderImage").get(),
      ]);

      final globalSettings = results[0];
      if (globalSettings.exists) {
        AppThemeData.primary300 = Color(int.parse(
            globalSettings.data()!['app_customer_color'].replaceFirst("#", "0xff")));
        final rawMaxCombined = globalSettings.data()!['maxCombinedDiscountPercent'];
        final parsedMaxCombined = double.tryParse(rawMaxCombined?.toString() ?? '');
        if (parsedMaxCombined != null && parsedMaxCombined > 0 && parsedMaxCombined <= 100) {
          maxCombinedDiscountPercent = parsedMaxCombined;
        }
      }

      final emailSetting = results[1];
      if (emailSetting.exists) {
        mailSettings = MailSettings.fromJson(emailSetting.data()!);
      }

      final version = results[2];
      if (version.exists) appVersion = version.data()!['app_version'].toString();

      final googleMapKey = results[3];
      if (googleMapKey.exists) GOOGLE_API_KEY = googleMapKey.data()!['key'].toString();

      final driverNearBy = results[4];
      if (driverNearBy.exists) selectedMapType = driverNearBy.data()!['selectedMapType'].toString();

      final notificationSetting = results[5];
      if (notificationSetting.exists) {
        senderId = notificationSetting.data()!['senderId'].toString();
        jsonNotificationFileURL = notificationSetting.data()!['serviceJson'].toString();
      }

      final placeHolderImage = results[6];
      if (placeHolderImage.exists) placeholderImage = placeHolderImage.data()!['image'].toString();

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
              builder: (context, child) =>
                  ConnectivityGate(child: EasyLoading.init()(context, child)),
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

// ── TEMPORARY STARTUP PERF LOGGING ──────────────────────────────────────────
// Instrumentation only, no behavior change. Wraps an awaited operation with
// start/end/elapsed logging so we can see exactly which step inside
// hasFinishedOnBoarding() is slow. Remove once the bottleneck is identified.
Future<T> _timedStep<T>(String label, Future<T> Function() op) async {
  final sw = Stopwatch()..start();
  debugPrint('[STARTUP-PERF] $label START at ${DateTime.now().toIso8601String()}');
  try {
    final result = await op();
    sw.stop();
    debugPrint('[STARTUP-PERF] $label END — elapsed ${sw.elapsedMilliseconds}ms');
    return result;
  } catch (e) {
    sw.stop();
    debugPrint('[STARTUP-PERF] $label FAILED after ${sw.elapsedMilliseconds}ms — $e');
    rethrow;
  }
}

class OnBoarding extends StatefulWidget {
  const OnBoarding({Key? key}) : super(key: key);

  @override
  State createState() {
    return OnBoardingState();
  }
}

class OnBoardingState extends State<OnBoarding> {

  bool _navigated = false;

  void _safeNavigate(VoidCallback navigate) {
    if (_navigated || !mounted) return;
    _navigated = true;
    navigate();
  }

  // ── Firebase routing ───────────────────────────────────────────────────
  Future hasFinishedOnBoarding() async {
    // TEMPORARY: total wall-clock time for the whole routing decision, plus
    // which path it exited through — see _timedStep for per-step timings.
    final totalStopwatch = Stopwatch()..start();
    String completionPath = 'normal';
    try {
      SharedPreferences prefs = await _timedStep(
          'SharedPreferences.getInstance', () => SharedPreferences.getInstance());
      bool finishedOnBoarding = (prefs.getBool(FINISHED_ON_BOARDING) ?? false);

      if (finishedOnBoarding) {
        // .currentUser is a synchronous getter (cached in memory by the
        // native SDK, no I/O) — logged mainly to establish a t=0 reference
        // point for the token/query breakdown below.
        auth.User? firebaseUser = auth.FirebaseAuth.instance.currentUser;
        debugPrint(
            '[STARTUP-PERF] FirebaseAuth.currentUser (sync) — uid=${firebaseUser?.uid ?? "null"} '
            'at ${DateTime.now().toIso8601String()}');
        if (firebaseUser != null) {
          // TEMPORARY: isolate ID-token acquisition from the Firestore query
          // itself. getIdToken() returns the cached token instantly if it
          // hasn't expired, or makes a network round trip to Google's
          // token-refresh endpoint if it has expired — this tells us whether
          // the ~5.7s delay we measured is Auth refreshing the token, or
          // Firestore's own connection/query time. Firestore's internal
          // AuthTokenProvider reads from this same cached-token state, so
          // this call also pre-warms whatever getCurrentUser() below would
          // have had to wait on internally.
          final idToken = await _timedStep(
              'FirebaseAuth.getIdToken (cached, or refreshed if expired)',
              () => firebaseUser.getIdToken());
          debugPrint(
              '[STARTUP-PERF] ID token acquired — length=${idToken?.length ?? 0}, '
              'at ${DateTime.now().toIso8601String()}');
          User? user = await _timedStep(
              'getCurrentUser (auth branch) [Firestore .get() only, token already warm]',
              () => FireStoreUtils.getCurrentUser(firebaseUser.uid));
          if (user != null && user.role == USER_ROLE_CUSTOMER) {
            if (user.active) {
              user.active = true;
              user.role = USER_ROLE_CUSTOMER;
              user.fcmToken = await _timedStep(
                      'FirebaseMessaging.getToken (auth branch)',
                      () => FireStoreUtils.firebaseMessaging.getToken()) ??
                  '';
              // Fire-and-forget: this only persists the refreshed
              // fcmToken/active flag to Firestore. MyAppState.currentUser is
              // set from this in-memory `user` object immediately below, so
              // navigation doesn't need to wait on the write's round trip
              // (measured at ~1.5s, the single biggest chunk of this path).
              unawaited(_timedStep('updateCurrentUser (auth branch, active)',
                  () => FireStoreUtils.updateCurrentUser(user)));
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
                final sections = await _timedStep('getSections (auth branch)',
                    () => FireStoreUtils.getSections());
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
                  // run in the background while we navigate to Home
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
                  // fcmToken was already fetched and written above —
                  // no need to re-fetch and re-write it here.
                }

                // Push to HomeScreen with drawer support
                _safeNavigate(() => pushReplacement(
                    context,
                    ContainerScreen(
                      user: MyAppState.currentUser!,
                      currentWidget: HomeScreen(user: MyAppState.currentUser!),
                      appBarTitle: 'Home',
                      drawerSelection: DrawerSelection.Home,
                    )));
                // --- End ---
              } else {
                _safeNavigate(() =>
                    pushAndRemoveUntil(context, LocationPermissionScreen()));
              }
            } else {
              user.lastOnlineTimestamp = Timestamp.now();
              user.fcmToken = "";
              await _timedStep(
                  'updateCurrentUser (auth branch, inactive/signout)',
                  () => FireStoreUtils.updateCurrentUser(user));
              await auth.FirebaseAuth.instance.signOut();
              MyAppState.currentUser = null;
              _safeNavigate(
                  () => pushReplacement(context, const LoginScreen()));
            }

            //UserPreference.setUserId(userID: user.userID);
            //
          } else {
            _safeNavigate(() => pushReplacement(context, const LoginScreen()));
          }
        } else {
          // No Firebase Auth session — try to restore a MSG91 phone user's session
          final savedPhoneUid = prefs.getString(PHONE_AUTH_USER_ID);
          if (savedPhoneUid != null && savedPhoneUid.isNotEmpty) {
            User? user = await _timedStep('getCurrentUser (msg91 branch)',
                () => FireStoreUtils.getCurrentUser(savedPhoneUid));
            if (user != null && user.role == USER_ROLE_CUSTOMER && user.active) {
              user.fcmToken = await _timedStep(
                      'FirebaseMessaging.getToken (msg91 branch)',
                      () => FireStoreUtils.firebaseMessaging.getToken()) ??
                  '';
              // Fire-and-forget — see the identical comment in the auth
              // branch above.
              unawaited(_timedStep('updateCurrentUser (msg91 branch)',
                  () => FireStoreUtils.updateCurrentUser(user)));
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
                final sections = await _timedStep('getSections (msg91 branch)',
                    () => FireStoreUtils.getSections());
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
                _safeNavigate(() => pushReplacement(
                    context,
                    ContainerScreen(
                      user: MyAppState.currentUser!,
                      currentWidget: HomeScreen(user: MyAppState.currentUser!),
                      appBarTitle: 'Home',
                      drawerSelection: DrawerSelection.Home,
                    )));
              } else {
                _safeNavigate(() =>
                    pushAndRemoveUntil(context, LocationPermissionScreen()));
              }
            } else {
              // Stored session is invalid or user deactivated — clear it
              await prefs.remove(PHONE_AUTH_USER_ID);
              _safeNavigate(
                  () => pushReplacement(context, const LoginScreen()));
            }
          } else {
            _safeNavigate(() => pushReplacement(context, const LoginScreen()));
          }
        }
      } else {
        _safeNavigate(() => pushReplacement(context, const OnBoardingScreen()));
      }
    } catch (e, st) {
      completionPath = 'error';
      debugPrint('hasFinishedOnBoarding failed: $e\n$st');
      // Any failure above (network blip, FCM token fetch, malformed user
      // data, etc.) must not leave the user stuck on this splash screen.
      _safeNavigate(() => pushReplacement(context, const LoginScreen()));
    } finally {
      totalStopwatch.stop();
      // TEMPORARY: if this prints with elapsed >15000ms and the timeout log
      // below already fired, the timeout path won the race — the UI already
      // moved on to LoginScreen before this finished computing in the
      // background. If it prints under 15000ms with path "normal"/"error",
      // hasFinishedOnBoarding itself resolved before the timeout.
      debugPrint(
          '[STARTUP-PERF] hasFinishedOnBoarding TOTAL: ${totalStopwatch.elapsedMilliseconds}ms (completion path: $completionPath)');
    }
  }

  @override
  void initState() {
    super.initState();
    hasFinishedOnBoarding().timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        debugPrint(
            '[STARTUP-PERF] hasFinishedOnBoarding TIMEOUT PATH fired at 15000ms — navigating to LoginScreen as fallback (hasFinishedOnBoarding keeps running in the background; watch for its TOTAL log line afterward)');
        _safeNavigate(() => pushReplacement(context, const LoginScreen()));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: const Color(0xFF7C3AED),
      body: Center(
        child: Image.asset(
          'assets/images/quickdash_logo_white.png',
          width: screenWidth * 0.72,
        ),
      ),
    );
  }
}

// ── Global friendly error screen ─────────────────────────────────────────────
// Replaces Flutter's default red/yellow crash screen for any widget build error.

class _AppErrorScreen extends StatelessWidget {
  final FlutterErrorDetails details;
  const _AppErrorScreen({required this.details});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEEEB),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline_rounded,
                    size: 40, color: Color(0xFFE53935)),
              ),
              const SizedBox(height: 24),
              const Text(
                'Something went wrong. Please try again later.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
