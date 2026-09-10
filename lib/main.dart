import 'dart:async';
import 'dart:convert';
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
import 'package:emartconsumer/services/behavior/behavior_tracker.dart';
import 'package:emartconsumer/services/behavior/purchase_completion_listener.dart';
import 'package:emartconsumer/services/connectivity_gate.dart';
import 'package:emartconsumer/services/force_update_gate.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/services/notification_service.dart';
import 'package:emartconsumer/services/shared_orders_watcher.dart';
import 'package:emartconsumer/services/shared_vendors_watcher.dart';
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

import 'model/SectionModel.dart';
import 'model/User.dart';
import 'services/app_cache_config.dart';
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

  // On-device cache ceilings (in-memory image cache + Firestore persistence).
  // Must run before the first Firestore call — Settings can only be assigned
  // while the client is untouched, and the warm-up read below is deliberately
  // the first one. See app_cache_config.dart for why each number was chosen.
  AppCacheConfig.applyRuntimeLimits();

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

  // Signals that OnBoardingState's own auth-based routing has actually
  // navigated away from the splash screen (see OnBoardingState._safeNavigate
  // below, which completes this). NotificationService._handleNotificationTap
  // waits on this before pushing a deep-link route on cold start - both
  // MyAppState.initState (notificationInit, below) and OnBoardingState.
  // initState (hasFinishedOnBoarding) fire in the same initial frame, so
  // without this a fast deep-link push could land on top of the splash
  // screen moments before the splash's own pushReplacement fires - and
  // pushReplacement silently swaps out whatever's currently on top (the
  // pushed deep-link route, not the splash) instead (found 2026-08-23: a
  // tapped Bill Pay notification briefly showed BillPayRequestScreen, then
  // was clobbered back to Home within about a second).
  static final Completer<void> _initialRoutingCompleter = Completer<void>();
  static void markInitialRoutingDone() {
    if (!_initialRoutingCompleter.isCompleted) {
      _initialRoutingCompleter.complete();
    }
  }

  static Future<void> get initialRoutingDone => _initialRoutingCompleter.future;

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
              builder: (context, child) => ConnectivityGate(
                  child: ForceUpdateGate(child: EasyLoading.init()(context, child))),
              home: const OnBoarding());
        },
      ),
    );
  }

  late StreamSubscription eventBusStream;

  // Purchase-preference completion listener lifecycle (2026-07-22) - tied
  // to Firebase Auth's own canonical session-state stream rather than any
  // particular login call site, so every login path (fresh interactive
  // login, auto-restored session, MSG91 phone auth now minting a real
  // Firebase Auth session) is covered uniformly, and logout reliably tears
  // it down. See PurchaseCompletionListener's own doc comment for why this
  // exists and why it's global rather than screen-owned.
  late StreamSubscription<auth.User?> _authStateStream;

  @override
  void initState() {
    notificationInit();
    initializeFlutterFire();
    WidgetsBinding.instance.addObserver(this);
    getCurrentAppTheme();
    _configureEasyLoading();
    // Hydrates the pending-behavior-event queue from local storage (crash/
    // kill recovery) — not a flush trigger itself, just a load.
    BehaviorTracker.init();
    // Recommendation Configuration (2026-07-22, moved 2026-07-23) — no
    // longer triggered here. This initState runs before the onboarding/
    // splash screen has even painted its first frame, and even though this
    // call was already fire-and-forget (unawaited), it still competed for
    // the same Firestore network channel/connection setup as onboarding's
    // own AWAITED calls (globalSettings, getOnBoardingList) during that
    // exact critical window, adding real latency to what the customer
    // perceives as "the app taking longer to start." RecommendationConfig
    // is only ever needed once a customer opens a restaurant page, which is
    // always well after Home has loaded - so the load is now triggered from
    // HomeScreen.initState instead (see HomeScreen.dart), not app startup.
    // RecommendationConfig.current still holds production-identical
    // defaults synchronously in the meantime.
    _authStateStream = auth.FirebaseAuth.instance.authStateChanges().listen((user) {
      FireStoreUtils.onAuthUidChanged(user?.uid);
      if (user != null) {
        PurchaseCompletionListener.start(user.uid);
      } else {
        PurchaseCompletionListener.stop();
        SharedOrdersWatcher.stop();
      }
    });
    super.initState();
  }

  void _configureEasyLoading() {
    EasyLoading.instance
      ..displayDuration = const Duration(milliseconds: 2500)
      // Switched from threeBounce (2026-08-27, vendor request) - a plain
      // spinning ring is the one loading pattern every phone user already
      // recognizes from iOS/Android's own native indicators, unlike
      // bouncing dots which can read as ambiguous (e.g. a chat "typing…"
      // indicator). This is the app-wide loader used everywhere
      // ShowToastDialog.showLoader() is called, not just login/signup.
      ..indicatorType = EasyLoadingIndicatorType.ring
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
    _authStateStream.cancel();
    PurchaseCompletionListener.stop();
    SharedOrdersWatcher.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-sync lightweight global settings (theme colour, wallet, currency)
      // so they reflect any admin changes made while the app was backgrounded.
      initializeFlutterFire();
      FireStoreUtils.getWalletSettingData();
      // Belt-and-suspenders restart for PurchaseCompletionListener: its own
      // doc comment claimed a resumed cycle would restart it, but nothing
      // here actually did until now. start() calls stop() first, so this
      // is safe/idempotent to call on every resume, logged in or not.
      final uid = FireStoreUtils.getCurrentUid();
      if (uid.isNotEmpty) PurchaseCompletionListener.start(uid);
      // Same rationale, for the shared Orders watcher (2026-09-06) - a
      // listener idle across days of backgrounding can silently lose its
      // live connection with no error and no local signal to reconnect,
      // which is exactly what let the original per-screen-listener bug's
      // stale snapshot go unnoticed for so long. restartIfActive() is a
      // no-op for a customer who has never opened Orders this session, so
      // this never costs a read nobody asked for.
      SharedOrdersWatcher.restartIfActive();
      // Same reasoning, for the shared Home vendor-list watcher (2026-09-06).
      SharedVendorsWatcher.restartIfActive();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // Flush any pending behavior events before the app is backgrounded/
      // killed — this is one of BehaviorTracker's three flush triggers
      // (queue threshold, background, reconnect), never a periodic timer.
      // MyAppState is the only single, non-recreated observer for the whole
      // process lifetime (unlike ContainerScreen's own observer, which is
      // torn down and recreated on every re-navigation), so this is the
      // correct home for this hook.
      BehaviorTracker.onAppBackgrounded();
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

// ── Cached user profile (instant login on reopen) ───────────────────────────
// User.toJson()/fromJson() are shaped for Firestore, which accepts Timestamp
// and GeoPoint objects natively — neither is JSON-string-encodable as-is.
// These two helpers swap them for plain markers on the way into
// SharedPreferences and reconstruct the real objects (which fromJson expects)
// on the way out, at the encode/decode level rather than per-model, so it
// works regardless of which nested model (AddressModel, GeoFireData, etc.)
// happens to hold one.
Object? _cacheEncodeFallback(Object? obj) {
  if (obj is Timestamp) return {'__ts': obj.millisecondsSinceEpoch};
  if (obj is GeoPoint) return {'__geo_lat': obj.latitude, '__geo_lng': obj.longitude};
  throw UnsupportedError('Cannot cache field of type ${obj.runtimeType}');
}

Object? _cacheDecodeReviver(Object? key, Object? value) {
  if (value is Map && value.containsKey('__ts')) {
    return Timestamp.fromMillisecondsSinceEpoch(value['__ts'] as int);
  }
  if (value is Map && value.containsKey('__geo_lat')) {
    return GeoPoint(
        (value['__geo_lat'] as num).toDouble(), (value['__geo_lng'] as num).toDouble());
  }
  return value;
}

const String _cachedUserProfilePrefix = 'cached_user_profile_';

Future<User?> _loadCachedUserProfile(String uid) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_cachedUserProfilePrefix$uid');
    if (raw == null) return null;
    final decoded = json.decode(raw, reviver: _cacheDecodeReviver);
    return User.fromJson(decoded as Map<String, dynamic>);
  } catch (e) {
    debugPrint('[STARTUP-PERF] _loadCachedUserProfile failed, ignoring cache: $e');
    return null;
  }
}

Future<void> _cacheUserProfile(User user) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final encoded = json.encode(user.toJson(), toEncodable: _cacheEncodeFallback);
    await prefs.setString('$_cachedUserProfilePrefix${user.userID}', encoded);
  } catch (e) {
    debugPrint('[STARTUP-PERF] _cacheUserProfile failed, skipping: $e');
  }
}

Future<void> _clearCachedUserProfile(String uid) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_cachedUserProfilePrefix$uid');
  } catch (_) {}
}

// ── Cached sections (global app config, not per-user) ───────────────────────
// getSections() was the single largest remaining cost on a warm reopen
// (~2-2.5s) even after the user-profile cache-hit fast path — same
// cache-then-refresh-in-background treatment closes that gap. SectionModel
// has no Timestamp/GeoPoint fields, so plain json.encode/decode is safe here
// without the reviver machinery the user-profile cache needs.
const String _cachedSectionsKey = 'cached_sections_list';
const String _cachedSectionsAtKey = 'cached_sections_at';
// 2026-09-08: sections holds admin-configured policy (nearByRadius, delivery
// commission tiers, etc.) that in practice changes at most a handful of
// times a year, not per-app-open - the background refresh below used to
// fire unconditionally on every single app open regardless of how recently
// it last ran, which is a real, avoidable Firestore read every time. Gated
// to once per this window instead; a genuinely urgent admin change (e.g.
// fixing the nearByRadius unit bug found today) still reaches users within
// this window, same as any other admin-set config elsewhere in this app.
const Duration _cachedSectionsTtl = Duration(hours: 24);

Future<List<SectionModel>?> _loadCachedSections() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cachedSectionsKey);
    if (raw == null) return null;
    final decoded = json.decode(raw) as List<dynamic>;
    return decoded
        .map((e) => SectionModel.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (e) {
    debugPrint('[STARTUP-PERF] _loadCachedSections failed, ignoring cache: $e');
    return null;
  }
}

// Whether the cached sections list is still within the TTL window - if so,
// the background refresh in _navigateWithUser is skipped entirely (zero
// Firestore cost) rather than firing on every app open regardless of age.
Future<bool> _cachedSectionsAreFresh() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final cachedAtMillis = prefs.getInt(_cachedSectionsAtKey);
    if (cachedAtMillis == null) return false;
    final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtMillis);
    return DateTime.now().difference(cachedAt) < _cachedSectionsTtl;
  } catch (_) {
    return false;
  }
}

Future<void> _cacheSections(List<SectionModel> sections) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final encoded = json.encode(sections.map((s) => s.toJson()).toList());
    await prefs.setString(_cachedSectionsKey, encoded);
    await prefs.setInt(_cachedSectionsAtKey, DateTime.now().millisecondsSinceEpoch);
  } catch (e) {
    debugPrint('[STARTUP-PERF] _cacheSections failed, skipping: $e');
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

  // Splash-screen display budget: never shorter than 800ms (so a fast
  // cache-hit doesn't flash by instantly) and — for the cache-hit path only,
  // see _kMaxCacheHitWait below — never blocked past 2s. Set the instant
  // this screen appears, in initState().
  DateTime? _flowStartedAt;
  static const _kMinSplashDisplay = Duration(milliseconds: 800);
  static const _kMaxCacheHitWait = Duration(seconds: 2);

  Future<void> _safeNavigate(VoidCallback navigate) async {
    if (_navigated || !mounted) return;
    _navigated = true;
    final startedAt = _flowStartedAt;
    if (startedAt != null) {
      final remaining = _kMinSplashDisplay - DateTime.now().difference(startedAt);
      if (remaining > Duration.zero) {
        await Future.delayed(remaining);
        if (!mounted) return;
      }
    }
    navigate();
    MyAppState.markInitialRoutingDone();
  }

  // Shared by both the cache-hit fast path and the real network path below —
  // decides Home vs LocationPermissionScreen from whatever User object it's
  // given (cached snapshot or freshly-fetched) and navigates. Was previously
  // duplicated almost verbatim between the auth and msg91 branches.
  Future<void> _navigateWithUser(User user) async {
    MyAppState.currentUser = user;
    if (user.shippingAddress != null && user.shippingAddress!.isNotEmpty) {
      if (user.shippingAddress!.where((element) => element.isDefault == true).isNotEmpty) {
        MyAppState.selectedPosotion =
            user.shippingAddress!.where((element) => element.isDefault == true).single;
      } else {
        MyAppState.selectedPosotion = user.shippingAddress!.first;
      }
      // --- Begin: Set section info as ServiceListScreen does ---
      // Cache-first, same pattern as the user profile above — sections
      // rarely change, so a stale-by-a-few-minutes copy navigating
      // instantly beats a fresh copy costing another ~2s network round
      // trip on every single reopen. Background refresh is gated by
      // _cachedSectionsTtl (2026-09-08) - it used to fire unconditionally on
      // every app open regardless of how recently it last ran, a real,
      // avoidable Firestore read for a value that changes at most a
      // handful of times a year.
      final cachedSections = await _timedStep(
          'loadCachedSections', () => _loadCachedSections());
      List<SectionModel> sections;
      if (cachedSections != null && cachedSections.isNotEmpty) {
        sections = cachedSections;
        if (!await _cachedSectionsAreFresh()) {
          unawaited(FireStoreUtils.getSections().then((fresh) {
            if (fresh.isNotEmpty) unawaited(_cacheSections(fresh));
          }));
        }
      } else {
        sections = await _timedStep('getSections', () => FireStoreUtils.getSections());
        if (sections.isNotEmpty) unawaited(_cacheSections(sections));
      }
      if (sections.isNotEmpty) {
        sectionConstantModel = sections.first;

        if (sectionConstantModel?.color != null) {
          AppThemeData.primary300 = Color(
            int.parse(sectionConstantModel!.color!.replaceFirst("#", "0xff")),
          );
        }

        // Payment gateway settings (Razorpay/Stripe/Paypal/Paytm/PhonePe/
        // FlutterWave/Xendit/OrangeMoney/PayStack/PayFast/MercadoPago/
        // MidTrans) are ONLY consumed by PaymentScreen.getPaymentSettingData()
        // — every browsing session that never reaches checkout was paying
        // for 12 Firestore reads it didn't need. Moved to CartScreen.initState
        // (see CartScreen.dart), which still gives them the whole
        // browse-cart-review lead time to resolve before PaymentScreen reads
        // them. Wallet stays here — ContainerScreen/HomeScreen need it for
        // the wallet drawer item regardless of whether the user ever checks out.
        FireStoreUtils.getWalletSettingData();
      }

      // Push to HomeScreen with drawer support
      await _safeNavigate(() => pushReplacement(
          context,
          ContainerScreen(
            user: MyAppState.currentUser!,
            currentWidget: HomeScreen(user: MyAppState.currentUser!),
            appBarTitle: 'Home',
            drawerSelection: DrawerSelection.Home,
          )));
      // --- End ---
    } else {
      await _safeNavigate(() => pushAndRemoveUntil(context, LocationPermissionScreen()));
    }
  }

  // Runs after a cache-hit fast path has already navigated — re-fetches the
  // real profile from Firestore, refreshes the cache and fcmToken, and (only
  // if the account turns out to no longer be a valid active customer) clears
  // the cache so a future open doesn't keep fast-pathing into a stale state.
  // Deliberately does not re-navigate — the user is already on Home.
  //
  // The delay below is deliberate: this was already fire-and-forget
  // (unawaited by both call sites) so it never blocked navigation, but
  // firing it in the same tick as navigation still meant it competed for
  // bandwidth with Home's own first-paint fetches (getAllStores, banners,
  // cuisines, etc.) during exactly the window the user is waiting on those.
  // A cached profile is already correct enough to browse with — there's no
  // reason this refresh needs to win that race. Delaying it gives Home's
  // own critical fetches a clear head start.
  static const _kProfileRefreshDelay = Duration(seconds: 8);

  Future<void> _refreshUserProfileInBackground(String uid) async {
    await Future.delayed(_kProfileRefreshDelay);
    try {
      final results = await Future.wait([
        FireStoreUtils.getCurrentUser(uid),
        FireStoreUtils.firebaseMessaging.getToken(),
      ]);
      final user = results[0] as User?;
      final fcmToken = results[1] as String?;
      if (user == null || user.role != USER_ROLE_CUSTOMER || !user.active) {
        unawaited(_clearCachedUserProfile(uid));
        return;
      }
      user.fcmToken = fcmToken ?? '';
      user.lastOnlineTimestamp = Timestamp.now();
      MyAppState.currentUser = user;
      unawaited(_cacheUserProfile(user));
      unawaited(FireStoreUtils.updateCurrentUser(user));
    } catch (e) {
      debugPrint('[STARTUP-PERF] _refreshUserProfileInBackground failed: $e');
    }
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
          // Cache-first fast path: if we have a valid cached profile for
          // this uid, navigate immediately without waiting on any network
          // call at all, then silently refresh in the background. Falls
          // through to the full network path below, untouched, if there's
          // no cache yet (first login on this device) or the cached
          // profile isn't in a navigable state.
          final cachedUser = await _timedStep(
              'loadCachedUserProfile (auth branch)',
              () => _loadCachedUserProfile(firebaseUser.uid));
          if (cachedUser != null &&
              cachedUser.role == USER_ROLE_CUSTOMER &&
              cachedUser.active) {
            completionPath = 'cache-hit (auth branch)';
            try {
              // This branch is pure local reads (no network) and normally
              // finishes in well under a second — the 2s cap is a safety
              // net for a genuine hang, not something the happy path should
              // ever hit. On timeout, fall through to the real network path
              // below rather than get stuck; _safeNavigate's _navigated
              // guard makes that safe even if this branch got partway
              // through navigating before timing out.
              await _navigateWithUser(cachedUser).timeout(_kMaxCacheHitWait);
              unawaited(_refreshUserProfileInBackground(firebaseUser.uid));
              return;
            } on TimeoutException {
              completionPath = 'cache-hit-timeout (auth branch)';
              debugPrint(
                  '[STARTUP-PERF] cache-hit fast path exceeded ${_kMaxCacheHitWait.inSeconds}s, falling through to network path');
            }
          }

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
          // getCurrentUser and the FCM token fetch are independent of each
          // other (the token fetch needs no data from the user doc) — run
          // them concurrently instead of paying for the token fetch strictly
          // after the Firestore query resolves.
          final authBranchResults = await Future.wait([
            _timedStep(
                'getCurrentUser (auth branch) [Firestore .get() only, token already warm]',
                () => FireStoreUtils.getCurrentUser(firebaseUser.uid)),
            _timedStep('FirebaseMessaging.getToken (auth branch)',
                () => FireStoreUtils.firebaseMessaging.getToken()),
          ]);
          User? user = authBranchResults[0] as User?;
          final authBranchFcmToken = authBranchResults[1] as String?;
          if (user != null && user.role == USER_ROLE_CUSTOMER) {
            if (user.active) {
              user.active = true;
              user.role = USER_ROLE_CUSTOMER;
              user.fcmToken = authBranchFcmToken ?? '';
              // Every prior write site for lastOnlineTimestamp only fired on
              // sign-out, so it never reflected actual usage — bump it here,
              // on every app open, alongside the fcmToken refresh below.
              user.lastOnlineTimestamp = Timestamp.now();
              // Fire-and-forget: this only persists the refreshed
              // fcmToken/active flag to Firestore. MyAppState.currentUser is
              // set from this in-memory `user` object immediately below, so
              // navigation doesn't need to wait on the write's round trip
              // (measured at ~1.5s, the single biggest chunk of this path).
              unawaited(_timedStep('updateCurrentUser (auth branch, active)',
                  () => FireStoreUtils.updateCurrentUser(user)));
              unawaited(_cacheUserProfile(user));
              await _navigateWithUser(user);
            } else {
              user.lastOnlineTimestamp = Timestamp.now();
              user.fcmToken = "";
              await _timedStep(
                  'updateCurrentUser (auth branch, inactive/signout)',
                  () => FireStoreUtils.updateCurrentUser(user));
              await auth.FirebaseAuth.instance.signOut();
              unawaited(_clearCachedUserProfile(user.userID));
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
            // Same cache-first fast path as the auth branch above.
            final cachedUser = await _timedStep(
                'loadCachedUserProfile (msg91 branch)',
                () => _loadCachedUserProfile(savedPhoneUid));
            if (cachedUser != null &&
                cachedUser.role == USER_ROLE_CUSTOMER &&
                cachedUser.active) {
              completionPath = 'cache-hit (msg91 branch)';
              try {
                // See the identical comment in the auth branch above.
                await _navigateWithUser(cachedUser).timeout(_kMaxCacheHitWait);
                unawaited(_refreshUserProfileInBackground(savedPhoneUid));
                return;
              } on TimeoutException {
                completionPath = 'cache-hit-timeout (msg91 branch)';
                debugPrint(
                    '[STARTUP-PERF] cache-hit fast path exceeded ${_kMaxCacheHitWait.inSeconds}s, falling through to network path');
              }
            }

            // Same concurrency fix as the auth branch above — getCurrentUser
            // and the FCM token fetch don't depend on each other.
            final msg91BranchResults = await Future.wait([
              _timedStep('getCurrentUser (msg91 branch)',
                  () => FireStoreUtils.getCurrentUser(savedPhoneUid)),
              _timedStep('FirebaseMessaging.getToken (msg91 branch)',
                  () => FireStoreUtils.firebaseMessaging.getToken()),
            ]);
            User? user = msg91BranchResults[0] as User?;
            final msg91BranchFcmToken = msg91BranchResults[1] as String?;
            if (user != null && user.role == USER_ROLE_CUSTOMER && user.active) {
              user.fcmToken = msg91BranchFcmToken ?? '';
              user.lastOnlineTimestamp = Timestamp.now();
              // Fire-and-forget — see the identical comment in the auth
              // branch above.
              unawaited(_timedStep('updateCurrentUser (msg91 branch)',
                  () => FireStoreUtils.updateCurrentUser(user)));
              unawaited(_cacheUserProfile(user));
              await _navigateWithUser(user);
            } else {
              // Stored session is invalid or user deactivated — clear it
              await prefs.remove(PHONE_AUTH_USER_ID);
              unawaited(_clearCachedUserProfile(savedPhoneUid));
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
    _flowStartedAt = DateTime.now();
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
