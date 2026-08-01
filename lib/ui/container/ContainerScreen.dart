import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/device_session_service.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/Language/language_choose_screen.dart';
import 'package:emartconsumer/ui/QrCodeScanner/QrCodeScanner.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';

import 'package:emartconsumer/ui/cartScreen/CartScreen.dart';
import 'package:emartconsumer/ui/cuisinesScreen/CuisinesScreen.dart';
import 'package:emartconsumer/ui/dineInScreen/dine_in_screen.dart';
import 'package:emartconsumer/ui/dineInScreen/my_booking_screen.dart';
import 'package:emartconsumer/ui/home/HomeScreen.dart';
import 'package:emartconsumer/ui/home/favourite_item.dart';
import 'package:emartconsumer/ui/home/favourite_store.dart';
import 'package:emartconsumer/ui/mapView/MapViewScreen.dart';
import 'package:emartconsumer/ui/ordersScreen/OrdersScreen.dart';
import 'package:emartconsumer/ui/privacy_policy/privacy_policy.dart';
import 'package:emartconsumer/ui/profile/ProfileScreen.dart';
import 'package:emartconsumer/ui/referral_screen/referral_screen.dart';
import 'package:emartconsumer/ui/searchScreen/SearchScreen.dart';
import 'package:emartconsumer/ui/termsAndCondition/terms_and_codition.dart';
import 'package:emartconsumer/ui/wallet/walletScreen.dart';
import 'package:emartconsumer/userPrefrence.dart';
import 'package:emartconsumer/widget/userAvatar.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

enum DrawerSelection {
  Dashboard,
  Home,
  Wallet,
  dineIn,
  Cuisines,
  Search,
  Cart,
  referral,
  Profile,
  Orders,
  MyBooking,
  chooseLanguage,
  inbox,
  driver,
  Logout,
  termsCondition,
  privacyPolicy,
  LikedStore,
  LikedProduct,
  giftCard
}

class ContainerScreen extends StatefulWidget {
  final User? user;
  final Widget currentWidget;
  final String vendorId;
  final String appBarTitle;
  final DrawerSelection drawerSelection;

  ContainerScreen(
      {Key? key,
      required this.user,
      currentWidget,
      vendorId,
      appBarTitle,
      this.drawerSelection = DrawerSelection.Home})
      : appBarTitle = appBarTitle ?? 'Home'.tr(),
        vendorId = vendorId ?? "",
        currentWidget = currentWidget ??
            HomeScreen(
              user: MyAppState.currentUser,
              vendorId: vendorId,
            ),
        super(key: key);

  @override
  _ContainerScreen createState() {
    return _ContainerScreen();
  }
}

class _ContainerScreen extends State<ContainerScreen> with WidgetsBindingObserver {
  var key = GlobalKey<ScaffoldState>();

  late CartDatabase cartDatabase;
  late String _appBarTitle;
  final fireStoreUtils = FireStoreUtils();

  late Widget _currentWidget;
  late DrawerSelection _drawerSelection;

  int cartCount = 0;
  bool? isWalletEnable;
  late User user;
  late StreamSubscription eventBusStream;

  @override
  void initState() {
    FireStoreUtils.getWalletSettingData();
    if (widget.user != null) {
      user = widget.user!;
    } else {
      user = User();
    }
    super.initState();
    _appBarTitle = widget.appBarTitle;
    _drawerSelection = widget.drawerSelection;
    // If the initial widget is a HomeScreen (constructed before the key was
    // available), rebuild it with the openDrawer callback wired to the key.
    if (widget.currentWidget is HomeScreen) {
      final hs = widget.currentWidget as HomeScreen;
      _currentWidget = HomeScreen(
        user: hs.user,
        vendorId: hs.vendorId,
        onOpenDrawer: () => key.currentState?.openDrawer(),
      );
    } else {
      _currentWidget = widget.currentWidget;
    }
    FireStoreUtils.firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    getTaxList();
    _listenDeliveryGate();
    WidgetsBinding.instance.addObserver(this);

    // A cold start (app fully relaunched, not just resumed from background)
    // never fires didChangeAppLifecycleState(resumed) below — Firebase Auth
    // restores the session locally and lands the user straight here with no
    // device-session check at all until the next background/resume cycle or
    // gated action. Closes that gap, especially relevant for a device that
    // was force-killed while offline and relaunched later.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) DeviceSessionService.enforceActive(context);
    });
  }

  // A login-time device-session check alone misses the case where this
  // device gets switched out by another login while the app is backgrounded
  // or offline and never receives the FCM force-logout push. Re-checking on
  // every resume closes that gap (see DeviceSessionService.checkActive).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      DeviceSessionService.enforceActive(context);
    }
  }

  // Single, app-wide live listener for the Delivery on/off toggle, feeding
  // the global isDeliveryActiveNotifier/deliveryOffMessageNotifier (see
  // constants.dart) — ContainerScreen is the persistent shell for the whole
  // logged-in session, so this stays alive regardless of which screen is
  // currently shown, instead of every gated screen running its own listener.
  StreamSubscription<DocumentSnapshot>? _deliveryGateSub;

  void _listenDeliveryGate() {
    final sectionId = sectionConstantModel?.id;
    if (sectionId == null || sectionId.isEmpty) return;
    isDeliveryActiveNotifier.value = sectionConstantModel?.deliveryActive ?? true;
    deliveryOffMessageNotifier.value = sectionConstantModel?.deliveryOffMessage ?? '';
    _deliveryGateSub = FireStoreUtils.firestore
        .collection(SECTION)
        .doc(sectionId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) return;
      final data = snap.data();
      if (data == null) return;
      isDeliveryActiveNotifier.value = data['delivery_active'] ?? true;
      deliveryOffMessageNotifier.value = data['delivery_off_message'] ?? '';
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deliveryGateSub?.cancel();
    super.dispose();
  }

  getTaxList() async {
    if (sectionConstantModel == null) return;
    try {
      await FireStoreUtils().getTaxList(sectionConstantModel!.id).then((value) {
        if (value != null) taxList = value;
      });
    } catch (e) {
      debugPrint('getTaxList error: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    cartDatabase = Provider.of<CartDatabase>(context);
  }

  // ── Navigation helpers ────────────────────────────────────────────────
  void _navigate(DrawerSelection sel, String title, Widget widget) {
    Navigator.pop(context);
    setState(() {
      _drawerSelection = sel;
      _appBarTitle = title;
      _currentWidget = widget;
    });
  }

  void _navigateAuth(DrawerSelection sel, String title, Widget widget) {
    Navigator.pop(context);
    if (MyAppState.currentUser == null) {
      push(context, const LoginScreen());
    } else {
      setState(() {
        _drawerSelection = sel;
        _appBarTitle = title;
        _currentWidget = widget;
      });
    }
  }

  // ── Drawer builder ────────────────────────────────────────────────────
  Drawer _buildDrawer(BuildContext context, User user) {
    final dark = isDarkMode(context);
    final bg = dark ? const Color(0xFF0F0F0F) : const Color(0xFFFAFAFA);

    return Drawer(
      backgroundColor: bg,
      width: MediaQuery.of(context).size.width * 0.82,
      elevation: 0,
      child: Column(
        children: [
          // ── Header ────────────────────────────────────────────────
          _DrawerHeader(
            user: user,
            dark: dark,
            onEditTap: () => _navigateAuth(
              DrawerSelection.Profile,
              'My Profile'.tr(),
              const ProfileScreen(),
            ),
          ),

          // ── Scrollable menu ───────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 6, bottom: 8),
              children: [
                _sectionLabel('Explore', dark),
                _drawerItem(
                  sel: DrawerSelection.Home,
                  icon: Icons.storefront_rounded,
                  label: 'Stores',
                  dark: dark,
                  onTap: () => _navigate(
                    DrawerSelection.Home,
                    'Stores'.tr(),
                    HomeScreen(
                      user: MyAppState.currentUser,
                      onOpenDrawer: () => key.currentState?.openDrawer(),
                    ),
                  ),
                ),
                // Categories hidden from drawer for now

                if (sectionConstantModel?.dineInActive == true)
                  _drawerItem(
                    sel: DrawerSelection.dineIn,
                    icon: Icons.restaurant_menu_rounded,
                    label: 'Dine-In',
                    dark: dark,
                    onTap: () => _navigate(
                      DrawerSelection.dineIn,
                      'Dine-In'.tr(),
                      DineInScreen(user: MyAppState.currentUser ?? User()),
                    ),
                  ),

                _sectionGap(dark),

                _sectionLabel('My Account', dark),
                _drawerItem(
                  sel: DrawerSelection.Profile,
                  icon: Icons.person_outline_rounded,
                  label: 'My Profile',
                  dark: dark,
                  onTap: () => _navigateAuth(
                    DrawerSelection.Profile,
                    'My Profile'.tr(),
                    const ProfileScreen(),
                  ),
                ),
                _drawerItem(
                  sel: DrawerSelection.Orders,
                  icon: Icons.receipt_long_rounded,
                  label: 'Orders',
                  dark: dark,
                  onTap: () => _navigateAuth(
                    DrawerSelection.Orders,
                    'Orders'.tr(),
                    OrdersScreen(),
                  ),
                ),
                _drawerCartItem(dark),
                if (UserPreference.getWalletData() ?? false)
                  _drawerItem(
                    sel: DrawerSelection.Wallet,
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Wallet',
                    dark: dark,
                    onTap: () => _navigateAuth(
                      DrawerSelection.Wallet,
                      'Wallet'.tr(),
                      const WalletScreen(),
                    ),
                  ),
                if (sectionConstantModel?.dineInActive == true)
                  _drawerItem(
                    sel: DrawerSelection.MyBooking,
                    icon: Icons.book_online_rounded,
                    label: 'Dine-In Bookings',
                    dark: dark,
                    onTap: () => _navigateAuth(
                      DrawerSelection.MyBooking,
                      'Dine-In Bookings'.tr(),
                      const MyBookingScreen(),
                    ),
                  ),

                // Favourites section (Favourite Stores / Favourite Items)
                // hidden from the drawer for now, per request — re-enable
                // by restoring this block.
                // _sectionGap(dark),
                // _sectionLabel('Favourites', dark),
                // _drawerItem(
                //   sel: DrawerSelection.LikedStore,
                //   icon: Icons.favorite_border_rounded,
                //   label: 'Favourite Stores',
                //   dark: dark,
                //   onTap: () => _navigateAuth(
                //     DrawerSelection.LikedStore,
                //     'Favourite Stores'.tr(),
                //     const FavouriteStoreScreen(),
                //   ),
                // ),
                // _drawerItem(
                //   sel: DrawerSelection.LikedProduct,
                //   icon: Icons.bookmark_border_rounded,
                //   label: 'Favourite Items',
                //   dark: dark,
                //   onTap: () => _navigateAuth(
                //     DrawerSelection.LikedProduct,
                //     'Favourite Item'.tr(),
                //     const FavouriteItemScreen(),
                //   ),
                // ),

                _sectionGap(dark),

                _sectionLabel('More', dark),
                _drawerItem(
                  sel: DrawerSelection.referral,
                  icon: Icons.card_giftcard_rounded,
                  label: 'Refer a Friend',
                  dark: dark,
                  badge: 'NEW',
                  onTap: () {
                    Navigator.pop(context);
                    if (MyAppState.currentUser == null) {
                      push(context, const LoginScreen());
                    } else {
                      push(context, const ReferralScreen());
                    }
                  },
                ),
                _drawerItem(
                  sel: DrawerSelection.chooseLanguage,
                  icon: Icons.language_rounded,
                  label: 'Language',
                  dark: dark,
                  onTap: () => _navigate(
                    DrawerSelection.chooseLanguage,
                    'Language'.tr(),
                    LanguageChooseScreen(isContainer: true),
                  ),
                ),

                _sectionGap(dark),

                _sectionLabel('Support & Legal', dark),
                _drawerItem(
                  sel: DrawerSelection.termsCondition,
                  icon: Icons.gavel_rounded,
                  label: 'Terms & Conditions',
                  dark: dark,
                  onTap: () => push(context, const TermsAndCondition()),
                ),
                _drawerItem(
                  sel: DrawerSelection.privacyPolicy,
                  icon: Icons.privacy_tip_outlined,
                  label: 'Privacy Policy',
                  dark: dark,
                  onTap: () => push(context, const PrivacyPolicyScreen()),
                ),

                const SizedBox(height: 12),
                _logoutItem(dark),
                const SizedBox(height: 8),
              ],
            ),
          ),

          // ── Version footer ─────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
                20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: dark
                      ? const Color(0xFF1E1E1E)
                      : const Color(0xFFEEEEEE),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 13,
                  color: dark
                      ? const Color(0xFF3A3A3A)
                      : const Color(0xFFCCCCCC),
                ),
                const SizedBox(width: 6),
                Text(
                  'Version $appVersion',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: AppThemeData.regular,
                    color: dark
                        ? const Color(0xFF3A3A3A)
                        : const Color(0xFFCCCCCC),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Cart item with live badge ──────────────────────────────────────
  Widget _drawerCartItem(bool dark) {
    final isActive = _drawerSelection == DrawerSelection.Cart;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () {
            Navigator.pop(context);
            if (MyAppState.currentUser == null) {
              push(context, const LoginScreen());
            } else {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ContainerScreen(
                  user: MyAppState.currentUser,
                  currentWidget: const CartScreen(),
                  appBarTitle: 'Your Cart'.tr(),
                  drawerSelection: DrawerSelection.Cart,
                ),
              ));
            }
          },
          borderRadius: BorderRadius.circular(14),
          splashColor: AppThemeData.primary500.withValues(alpha: 0.08),
          highlightColor: AppThemeData.primary500.withValues(alpha: 0.04),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: isActive
                  ? AppThemeData.primary500.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: isActive
                        ? LinearGradient(
                            colors: [
                              AppThemeData.primary500,
                              AppThemeData.primary600,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isActive
                        ? null
                        : (dark
                            ? const Color(0xFF1C1C1C)
                            : const Color(0xFFF0F0F0)),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    Icons.shopping_cart_outlined,
                    size: 20,
                    color: isActive
                        ? Colors.white
                        : (dark
                            ? const Color(0xFF888888)
                            : const Color(0xFF666666)),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    'Cart'.tr(),
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: isActive
                          ? AppThemeData.semiBold
                          : AppThemeData.medium,
                      color: isActive
                          ? AppThemeData.primary500
                          : (dark
                              ? const Color(0xFFE0E0E0)
                              : const Color(0xFF222222)),
                    ),
                  ),
                ),
                StreamBuilder<List<CartProduct>>(
                  stream: cartDatabase.watchProducts,
                  builder: (context, snapshot) {
                    int count = 0;
                    if (snapshot.hasData) {
                      for (var p in snapshot.data!) {
                        count += p.quantity;
                      }
                    }
                    if (count == 0) return const SizedBox.shrink();
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppThemeData.primary500,
                            AppThemeData.primary600,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        count <= 99 ? '$count' : '99+',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: AppThemeData.bold,
                          color: Colors.white,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Menu item tile ─────────────────────────────────────────────────
  Widget _drawerItem({
    required DrawerSelection sel,
    required IconData icon,
    required String label,
    required bool dark,
    required VoidCallback onTap,
    String? badge,
  }) {
    final isActive = _drawerSelection == sel;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          splashColor: AppThemeData.primary500.withValues(alpha: 0.08),
          highlightColor: AppThemeData.primary500.withValues(alpha: 0.04),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: isActive
                  ? AppThemeData.primary500.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                // Icon with gradient when active
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: isActive
                        ? LinearGradient(
                            colors: [
                              AppThemeData.primary500,
                              AppThemeData.primary600,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isActive
                        ? null
                        : (dark
                            ? const Color(0xFF1C1C1C)
                            : const Color(0xFFF0F0F0)),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: isActive
                        ? Colors.white
                        : (dark
                            ? const Color(0xFF888888)
                            : const Color(0xFF666666)),
                  ),
                ),
                const SizedBox(width: 13),
                // Label
                Expanded(
                  child: Text(
                    label.tr(),
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: isActive
                          ? AppThemeData.semiBold
                          : AppThemeData.medium,
                      color: isActive
                          ? AppThemeData.primary500
                          : (dark
                              ? const Color(0xFFE0E0E0)
                              : const Color(0xFF222222)),
                    ),
                  ),
                ),
                // Text badge (e.g. "NEW")
                if (badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        fontSize: 9,
                        fontFamily: AppThemeData.bold,
                        color: Color(0xFF16A34A),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Logout / Login item ────────────────────────────────────────────
  Widget _logoutItem(bool dark) {
    final isLoggedIn = MyAppState.currentUser != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () async {
            if (!isLoggedIn) {
              pushAndRemoveUntil(context, const LoginScreen());
            } else {
              ShowToastDialog.showLoader('Please wait');
              if (MyAppState.currentUser != null) {
                MyAppState.currentUser!.lastOnlineTimestamp = Timestamp.now();
                MyAppState.currentUser!.fcmToken = '';
                await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!);
              }
              await auth.FirebaseAuth.instance.signOut();
              // Clear persisted phone user session
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove(PHONE_AUTH_USER_ID);
              MyAppState.currentUser = null;
              Provider.of<CartDatabase>(context, listen: false)
                  .deleteAllProducts();
              ShowToastDialog.closeLoader();
              pushAndRemoveUntil(context, const LoginScreen());
            }
          },
          borderRadius: BorderRadius.circular(14),
          splashColor: const Color(0xFFEF4444).withValues(alpha: 0.08),
          highlightColor: const Color(0xFFEF4444).withValues(alpha: 0.04),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFEF4444).withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isLoggedIn ? Icons.logout_rounded : Icons.login_rounded,
                    size: 19,
                    color: const Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    isLoggedIn ? 'Log Out'.tr() : 'Log In'.tr(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontFamily: AppThemeData.semiBold,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                ),
                Icon(
                  isLoggedIn
                      ? Icons.arrow_forward_ios_rounded
                      : Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: const Color(0xFFEF4444).withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Section label ──────────────────────────────────────────────────
  Widget _sectionLabel(String label, bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 12,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppThemeData.primary500,
                  AppThemeData.primary500.withValues(alpha: 0.3),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.2,
              fontFamily: AppThemeData.bold,
              fontWeight: FontWeight.w700,
              color: dark ? const Color(0xFF4A4A4A) : const Color(0xFFAAAAAA),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section gap (replaces divider) ────────────────────────────────
  Widget _sectionGap(bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 2),
      child: Divider(
        height: 1,
        thickness: 1,
        color: dark ? const Color(0xFF1A1A1A) : const Color(0xFFEDEDED),
      ),
    );
  }

  // ── Main build ─────────────────────────────────────────────────────
  DateTime? currentBackPressTime;
  bool canPopNow = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _drawerSelection == DrawerSelection.Cart ? true : canPopNow,
      onPopInvoked: (didPop) {
        if (_drawerSelection == DrawerSelection.Cart) {
          return;
        }
        final now = DateTime.now();
        if (currentBackPressTime == null ||
            now.difference(currentBackPressTime!) >
                const Duration(seconds: 2)) {
          currentBackPressTime = now;
          setState(() {
            canPopNow = false;
          });
          ShowToastDialog.showToast("Double press to exit");
          return;
        } else {
          setState(() {
            canPopNow = true;
          });
        }
      },
      child: ChangeNotifierProvider.value(
        value: user,
        child: Consumer<User>(builder: (context, user, _) {
          return Scaffold(
            backgroundColor: isDarkMode(context)
                ? AppThemeData.surfaceDark
                : AppThemeData.surface,
            key: key,
            drawer: _buildDrawer(context, user),
            // Disable edge-drag so the left-side drag zone (0–20dp) no longer
            // competes with the hamburger InkWell tap gesture. The hamburger
            // button sits at x≈16px, inside that zone, causing intermittent
            // missed taps when the finger has any horizontal drift.
            drawerEnableOpenDragGesture: false,
            appBar: _drawerSelection == DrawerSelection.Home
                ? null
                : AppBar(
                    elevation:
                        _drawerSelection == DrawerSelection.Wallet ? 0 : 0,
                    centerTitle: _drawerSelection == DrawerSelection.Wallet
                        ? true
                        : false,
                    backgroundColor: isDarkMode(context)
                        ? AppThemeData.primary600
                        : AppThemeData.primary500,
                    leading: (_drawerSelection == DrawerSelection.Cart)
                        ? IconButton(
                            icon: const Icon(Icons.arrow_back,
                                color: Colors.white),
                            onPressed: () {
                              if (Navigator.of(context).canPop()) {
                                Navigator.of(context).pop();
                              } else {
                                setState(() {
                                  _drawerSelection = DrawerSelection.Home;
                                  _appBarTitle = 'Stores'.tr();
                                  _currentWidget = HomeScreen(
                                    user: MyAppState.currentUser,
                                    onOpenDrawer: () => key.currentState?.openDrawer(),
                                  );
                                });
                              }
                            },
                          )
                        : Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: InkWell(
                              onTap: () {
                                key.currentState!.openDrawer();
                              },
                              child: ClipOval(
                                child: Container(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  child: const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: Icon(Icons.menu, color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          ),
                    title: Text(
                      _appBarTitle,
                      style: const TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                          fontWeight: FontWeight.normal),
                    ),
                    actions: _drawerSelection == DrawerSelection.Wallet ||
                            _drawerSelection == DrawerSelection.MyBooking ||
                            _drawerSelection == DrawerSelection.dineIn
                        ? []
                        : [
                                IconButton(
                                    visualDensity:
                                        const VisualDensity(horizontal: -4),
                                    padding: const EdgeInsets.only(right: 10),
                                    icon: Image(
                                      image: const AssetImage(
                                          "assets/images/search.png"),
                                      width: 20,
                                      color: Colors.white,
                                    ),
                                    onPressed: () {
                                      push(context, const SearchScreen());
                                    }),
                                if (_currentWidget is! CartScreen ||
                                    _currentWidget is! ProfileScreen)
                                  IconButton(
                                      padding: const EdgeInsets.only(right: 20),
                                      visualDensity:
                                          const VisualDensity(horizontal: -4),
                                      tooltip: 'Cart'.tr(),
                                      icon: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Image(
                                            image: const AssetImage(
                                                "assets/images/cart.png"),
                                            width: 20,
                                            color: Colors.white,
                                          ),
                                          StreamBuilder<List<CartProduct>>(
                                            stream: cartDatabase.watchProducts,
                                            builder: (context, snapshot) {
                                              cartCount = 0;
                                              if (snapshot.hasData) {
                                                for (var element
                                                    in snapshot.data!) {
                                                  cartCount += element.quantity;
                                                }
                                              }
                                              return Visibility(
                                                visible: cartCount >= 1,
                                                child: Positioned(
                                                  right: -6,
                                                  top: -8,
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.all(4),
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: Colors.white.withValues(alpha: 0.9),
                                                    ),
                                                    constraints:
                                                        const BoxConstraints(
                                                      minWidth: 12,
                                                      minHeight: 12,
                                                    ),
                                                    child: Center(
                                                      child: Text(
                                                        cartCount <= 99
                                                            ? '$cartCount'
                                                            : '+99',
                                                        style: TextStyle(
                                                          fontSize: 9,
                                                          fontFamily: AppThemeData.bold,
                                                          color: AppThemeData.primary600,
                                                          fontWeight: FontWeight.w700,
                                                        ),
                                                        textAlign:
                                                            TextAlign.center,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          )
                                        ],
                                      ),
                                      onPressed: () {
                                        if (MyAppState.currentUser == null) {
                                          push(context, const LoginScreen());
                                        } else {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  ContainerScreen(
                                                user: MyAppState.currentUser!,
                                                currentWidget: CartScreen(),
                                                appBarTitle: 'Your Cart'.tr(),
                                                drawerSelection:
                                                    DrawerSelection.Cart,
                                              ),
                                            ),
                                          );
                                        }
                                      }),
                              ],
                  ),
            // Android 15 (targetSdkVersion 35) enforces edge-to-edge: the app
            // window now extends under the system nav bar / gesture strip by
            // default, so screens must explicitly pad for it or content (and,
            // during route transitions, whatever's visible behind/around it)
            // can render into that area. top:false because every non-Home
            // selection already gets its top inset from the AppBar above, and
            // HomeScreen pads its own top manually (MediaQuery.viewPadding.top)
            // — only bottom needs a shell-level catch-all. Safe to nest: any
            // screen below (e.g. CartScreen) that already wraps itself in its
            // own SafeArea just sees zero remaining padding here, no double-pad.
            body: SafeArea(
              top: false,
              child: _currentWidget,
            ),
          );
        }),
      ),
    );
  }
}

// ── Drawer header widget ──────────────────────────────────────────────────
class _DrawerHeader extends StatelessWidget {
  final User user;
  final bool dark;
  final VoidCallback onEditTap;

  const _DrawerHeader({
    required this.user,
    required this.dark,
    required this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    final contact = user.email.isNotEmpty ? user.email : user.phoneNumber;
    final name =
        user.fullName().isNotEmpty ? user.fullName() : 'Welcome';
    final topPad = MediaQuery.of(context).padding.top;

    return GestureDetector(
      onTap: onEditTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppThemeData.primary600,
              AppThemeData.primary500,
              Color(0xFF9F67F5), // fixed light-purple endpoint — never overwritten
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Decorative background circle — top right
            Positioned(
              top: -30,
              right: -30,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
            ),
            // Decorative background circle — bottom left
            Positioned(
              bottom: -20,
              left: -20,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            // Decorative dot ring — mid right
            Positioned(
              top: topPad + 10,
              right: 16,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 12,
                  ),
                ),
              ),
            ),
            // Content
            Padding(
              padding: EdgeInsets.only(
                top: topPad + 22,
                left: 20,
                right: 20,
                bottom: 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar row with edit chip
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Avatar with white ring + shadow
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.50),
                            width: 2.5,
                          ),
                        ),
                        child: UserAvatar(
                          name: name,
                          imageUrl: user.profilePictureURL.isNotEmpty
                              ? user.profilePictureURL
                              : null,
                          radius: 34,
                        ),
                      ),
                      const Spacer(),
                      // Edit profile chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.30),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.edit_outlined,
                              size: 12,
                              color: Colors.white.withValues(alpha: 0.90),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Edit',
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: AppThemeData.medium,
                                color: Colors.white.withValues(alpha: 0.90),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Name
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontFamily: AppThemeData.bold,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Contact row
                  if (contact.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(
                          contact.contains('@')
                              ? Icons.mail_outline_rounded
                              : Icons.phone_outlined,
                          size: 12,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            contact,
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: AppThemeData.regular,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  // "View full profile" subtle row
                  Row(
                    children: [
                      Text(
                        'View full profile',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: AppThemeData.medium,
                          color: Colors.white.withValues(alpha: 0.60),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 9,
                        color: Colors.white.withValues(alpha: 0.50),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
