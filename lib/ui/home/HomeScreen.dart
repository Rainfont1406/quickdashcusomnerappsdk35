import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/AddressModel.dart';
import 'package:emartconsumer/model/BannerModel.dart';
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/model/VendorCategoryModel.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/model/offer_model.dart';
import 'package:emartconsumer/model/story_model.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/theme/responsive.dart';
import 'package:emartconsumer/ui/QrCodeScanner/QrCodeScanner.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/ui/cartScreen/CartScreen.dart';
import 'package:emartconsumer/ui/categoryDetailsScreen/CategoryDetailsScreen.dart';
import 'package:emartconsumer/ui/container/ContainerScreen.dart';
import 'package:emartconsumer/ui/cuisinesScreen/CuisinesScreen.dart';
import 'package:emartconsumer/ui/deliveryAddressScreen/DeliveryAddressScreen.dart';
import 'package:emartconsumer/ui/home/story_view.dart';
import 'package:emartconsumer/ui/mapView/MapViewScreen.dart';
import 'package:emartconsumer/ui/productDetailsScreen/ProductDetailsScreen.dart';
import 'package:emartconsumer/ui/searchScreen/SearchScreen.dart';
import 'package:emartconsumer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:emartconsumer/widget/coming_soon_view.dart';
import 'package:emartconsumer/widget/delivery_type_selector.dart';
import 'package:emartconsumer/widget/road_distance_text.dart';
import 'package:emartconsumer/ui/home/home_skeleton.dart';

import 'package:emartconsumer/utils/network_image_widget.dart';
import 'package:emartconsumer/widget/place_picker_osm.dart';
import 'package:emartconsumer/widget/story_view/controller/story_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_place_picker_mb/google_maps_place_picker.dart';
import 'package:location/location.dart' as loc;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

class HomeScreen extends StatefulWidget {
  final User? user;
  final String vendorId;
  final VoidCallback? onOpenDrawer;

  HomeScreen({
    Key? key,
    required this.user,
    vendorId,
    this.onOpenDrawer,
  })  : vendorId = vendorId ?? "",
        super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late CartDatabase cartDatabase;
  int cartCount = 0;

  // Tracks when the app was last sent to background so we only refresh
  // if the user was away long enough for data to go stale.
  DateTime? _pausedAt;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    cartDatabase = Provider.of<CartDatabase>(context);
  }

  final fireStoreUtils = FireStoreUtils();

  // Nullable: deliberately unassigned until just after the skeleton is
  // dismissed — see _startProductsFetchIfNeeded(). The whole-catalog query
  // it triggers is too big to fire during the critical loading window.
  Future<List<ProductModel>>? productsFuture;
  bool _productsFetchStarted = false;
  List<VendorModel> vendors = [];
  List<VendorModel> popularRestaurantLst = [];
  List<VendorModel> newArrivalRestaurantList = [];
  Stream<List<VendorModel>>? lstAllRestaurant;
  StreamSubscription<List<VendorModel>>? _vendorSub;
  // Live admin toggle: when false, the Delivery section shows a Coming Soon
  // message instead of categories/banners/restaurants. Listened in realtime
  // (not just read from sectionConstantModel at startup) so it applies
  // instantly for users already on the Home screen.
  List<ProductModel> lstNearByFood = [];
  List<ProductModel> recommendedProducts = [];
  bool islocationGet = false;

  // Manual restaurant-feed sort chosen by the user — 'offer' | 'nearest' |
  // 'rating', or null for the default recommended order. Re-sorts the
  // already-loaded `vendors` list in place (no new Firestore fetch); ties
  // fall through to the same recommended priority order used by default.
  String? _manualSortMode;

  // Restaurant-card offer badge text, keyed by vendor id — computed once per
  // _sortRestaurants() pass (same normal/special offer evaluation used for
  // ranking, so the badge can never contradict why a restaurant is ranked
  // where it is). Never a merged normal+special number — just the single
  // bigger real offer's own amount, "Up to ₹X off", no minimum stated.
  Map<String, String> _offerBadgeByVendorId = {};

  // Global coupon-style ("normal") offers used by the feed-ranking algorithm
  // below. Includes vendor-specific and global (storeId null/empty) coupons —
  // same eligibility rule CartScreen uses at checkout. Refreshed once per
  // getData() call by _loadNormalOffersForRanking().
  List<OfferModel> _normalOffersForRanking = [];

  void _loadNormalOffersForRanking() {
    fireStoreUtils.getAllCoupons().then((value) {
      _normalOffersForRanking = value;
      _sortRestaurants();
      if (mounted) setState(() {});
    });
  }

  bool _isPercentageOfferType(String? type) =>
      type == 'Percentage' || type == 'Percent' || type == 'percentage';

  // Best "normal" (coupon-style) offer for [vendor] — OfferModel has no
  // section field, so these apply to both Delivery and Dineaway alike.
  // There's no live cart while browsing the feed, so each offer's own
  // applicableAmount is used as the comparison order amount for converting
  // a percentage offer into a monetary saving — this also means the
  // "satisfies minimum order amount" validity rule is met by construction.
  ({double amount, double percent}) _bestNormalOffer(VendorModel vendor) {
    double bestAmount = 0;
    double bestPercent = 0;
    double bestRate = -1;
    final now = DateTime.now();

    for (final offer in _normalOffersForRanking) {
      final appliesToVendor = offer.storeId == vendor.id ||
          offer.storeId == null ||
          (offer.storeId?.isEmpty ?? true);
      if (!appliesToVendor) continue;
      if (offer.isEnableOffer != true) continue;
      // Private coupons (isPublic == false) need a manual code the browsing
      // customer doesn't have — they're excluded from the cart's tap-to-
      // apply offers sheet too, so they must not influence ranking or what
      // gets advertised on the card.
      if (offer.isPublic == false) continue;
      final expiry = offer.expireOfferDate?.toDate();
      if (expiry == null || !expiry.isAfter(now)) continue;

      final minAmt = double.tryParse(offer.applicableAmount ?? '') ?? 0;
      final raw = double.tryParse(offer.discountOffer ?? '') ?? 0;
      final isPercent = _isPercentageOfferType(offer.discountTypeOffer);

      final amount = isPercent ? (minAmt * raw / 100) : raw;
      final percent = isPercent ? raw : 0.0;
      // Rank by effective rate (discount ÷ minimum spend), not raw amount —
      // a big-looking flat discount that needs a huge minimum order isn't
      // actually a better deal than a small discount with a low minimum.
      // Percentage offers reduce to their own percent value (the minimum
      // cancels out algebraically); a no-minimum offer is unconditionally
      // attainable, so it always wins the comparison.
      final rate =
          isPercent ? (raw / 100) : (minAmt > 0 ? raw / minAmt : double.infinity);

      if (rate > bestRate) {
        bestRate = rate;
        bestAmount = amount;
        bestPercent = percent;
      }
    }
    return (amount: bestAmount, percent: bestPercent);
  }

  // Best section-specific special offer for [vendor]. [orderType] is
  // "Delivery" or "Takeaway" — matching Timeslot.orderType's convention
  // (same as CartScreen's special-discount evaluation).
  ({double amount, double percent}) _bestSpecialOffer(
      VendorModel vendor, String orderType) {
    double bestAmount = 0;
    double bestPercent = 0;
    double bestRate = -1;
    if (!vendor.specialDiscountEnable) return (amount: 0, percent: 0);

    final now = DateTime.now();
    final todayName = DateFormat('EEEE', 'en_US').format(now);
    final todayDate = DateFormat('dd-MM-yyyy').format(now);

    for (final dayDiscount in vendor.specialDiscount) {
      if (dayDiscount.day != todayName) continue;
      for (final slot in dayDiscount.timeslot ?? []) {
        if (slot.from == null || slot.to == null) continue;
        if (slot.orderType != null &&
            slot.orderType!.isNotEmpty &&
            slot.orderType != orderType) {
          continue;
        }

        DateTime start, end;
        try {
          start = DateFormat('dd-MM-yyyy HH:mm')
              .parse('$todayDate ${slot.from}');
          end =
              DateFormat('dd-MM-yyyy HH:mm').parse('$todayDate ${slot.to}');
        } catch (_) {
          continue;
        }
        if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
        if (!vendor.isCurrentDateInRange(start, end)) continue;

        final minAmt = double.tryParse(slot.applicableAmount ?? '') ?? 0;
        final raw = double.tryParse(slot.discount ?? '') ?? 0;
        final isPercent = _isPercentageOfferType(slot.type);

        final amount = isPercent ? (minAmt * raw / 100) : raw;
        final percent = isPercent ? raw : 0.0;
        // Same effective-rate ranking as _bestNormalOffer — see comment there.
        final rate = isPercent
            ? (raw / 100)
            : (minAmt > 0 ? raw / minAmt : double.infinity);

        if (rate > bestRate) {
          bestRate = rate;
          bestAmount = amount;
          bestPercent = percent;
        }
      }
    }
    return (amount: bestAmount, percent: bestPercent);
  }

  /// BY AK
  /// Restaurant feed ranking. Priority order: OPEN status, eligibility,
  /// effective discount, effective offer percentage, rating, distance, then
  /// CLOSED status — i.e. OPEN+eligible, OPEN+non-eligible, CLOSED+eligible,
  /// CLOSED+non-eligible, each sub-group ordered by discount/percent/
  /// rating/distance. Re-evaluated per current screen's order type
  /// (Delivery vs Dineaway), since thresholds and special-offer matching
  /// both depend on which section is active.
  void _sortRestaurants() {
    if (MyAppState.selectedPosotion.location == null) {
      return;
    }

    final double userLat = MyAppState.selectedPosotion.location!.latitude;
    final double userLng = MyAppState.selectedPosotion.location!.longitude;

    final bool isDineaway = selctedOrderTypeValue == "Dineaway".tr() ||
        selctedOrderTypeValue == "Takeaway".tr();
    final String orderType = isDineaway ? "Takeaway" : "Delivery";
    final double threshold = isDineaway ? 200 : 50;
    final double strongOfferMin = isDineaway ? 100 : 30;

    final Map<String, String> newBadges = {};

    final ranked = vendors.map((v) {
      final bool open = v.isAcceptingOrders;

      final normal = _bestNormalOffer(v);
      final special = _bestSpecialOffer(v, orderType);

      final double effectiveDiscount = normal.amount + special.amount;
      final double effectivePercent = normal.percent + special.percent;

      // Card badge: never the merged normal+special sum above (that number
      // can correspond to no real, single order size when the two offers
      // have different minimums) — just the single bigger real offer,
      // shown as its own genuine "Up to ₹X off" ceiling.
      final bool normalWins = normal.amount >= special.amount;
      final double featuredAmount = normalWins ? normal.amount : special.amount;
      final double featuredPercent = normalWins ? normal.percent : special.percent;

      if (featuredAmount > 0) {
        // Whichever framing looks more compelling: a small ₹ amount reads
        // better as a percentage ("Up to 20% off" > "Up to ₹18 off"), while
        // a large amount reads better as a flat figure ("Up to ₹250 off" >
        // "Up to 12% off") — only applies when the winning offer is
        // actually percentage-type (featuredPercent > 0); flat-type offers
        // have no percentage to fall back to. No decimals either way.
        final bool showAsPercent = featuredPercent > 0 && featuredAmount < 100;
        newBadges[v.id] = showAsPercent
            ? 'Up to ${featuredPercent.round()}% off'.tr()
            : 'Up to ${amountShow(amount: featuredAmount.toStringAsFixed(0), decimals: 0)} off'
                .tr();
      }

      final bool meetsThreshold = effectiveDiscount >= threshold;
      final bool hasStrongOffer = normal.amount >= strongOfferMin ||
          special.amount >= strongOfferMin;
      final bool eligible = meetsThreshold && hasStrongOffer;

      final double rating =
          v.reviewsCount > 0 ? v.reviewsSum / v.reviewsCount : 0.0;
      final double distance = Geolocator.distanceBetween(
          userLat, userLng, v.latitude, v.longitude);

      return (
        vendor: v,
        isOpen: open,
        effectiveDiscount: effectiveDiscount,
        effectivePercent: effectivePercent,
        isEligible: eligible,
        rating: rating,
        distance: distance,
      );
    }).toList();

    ranked.sort((a, b) {
      // 1. OPEN before CLOSED — absolute priority, regardless of everything else.
      if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;

      // Manual user-selected sort (Offer / Nearest / Rating), if active —
      // takes priority within the open/closed group. If values tie, fall
      // through to the same recommended priority order used by default.
      if (_manualSortMode == 'offer' &&
          a.effectiveDiscount != b.effectiveDiscount) {
        return b.effectiveDiscount.compareTo(a.effectiveDiscount);
      }
      if (_manualSortMode == 'nearest' && a.distance != b.distance) {
        return a.distance.compareTo(b.distance);
      }
      if (_manualSortMode == 'rating' && a.rating != b.rating) {
        return b.rating.compareTo(a.rating);
      }

      // 2. Eligible before non-eligible, within the same open/closed group.
      if (a.isEligible != b.isEligible) return a.isEligible ? -1 : 1;
      // 3. Higher effective discount first.
      if (a.effectiveDiscount != b.effectiveDiscount) {
        return b.effectiveDiscount.compareTo(a.effectiveDiscount);
      }
      // 4. Higher effective offer percentage first.
      if (a.effectivePercent != b.effectivePercent) {
        return b.effectivePercent.compareTo(a.effectivePercent);
      }
      // 5. Higher rating first.
      if (a.rating != b.rating) return b.rating.compareTo(a.rating);
      // 6. Closer distance first.
      return a.distance.compareTo(b.distance);
    });

    vendors = ranked.map((r) => r.vendor).toList();
    _offerBadgeByVendorId = newBadges;
  }

  void _tryHideSkeleton() {
    if (isLoading && _bannerReady && _firstVendorReceived && mounted) {
      setState(() => isLoading = false);
    }
  }

  // Called every time the user picks a new delivery location.
  // Shows the skeleton immediately so stale distances aren't visible,
  // then lets getData() + _tryHideSkeleton() reveal the page once fresh
  // vendor data has arrived.
  void _onLocationChanged() {
    clearRoadDistanceCache();
    setState(() {
      isLoading = true;
      _firstVendorReceived = false;
      _precachingVendors = false;
    });
    getData();
  }

  // Precaches a list of network image URLs concurrently. Individual failures
  // are swallowed; a 5-second hard timeout prevents the skeleton from blocking
  // forever when images are slow or unavailable.
  Future<void> _precacheBatch(List<String> urls) async {
    if (!mounted || urls.isEmpty) return;
    final futures = urls
        .where((u) => u.isNotEmpty)
        .map((url) =>
            precacheImage(NetworkImage(url), context).catchError((_) {}))
        .toList();
    if (futures.isEmpty) return;
    await Future.wait(futures).timeout(
      const Duration(seconds: 5),
      onTimeout: () => [],
    );
  }

  // Called on the first vendor batch: precaches vendor card images then signals
  // the skeleton to hide. Separated from the stream listener so it can await.
  Future<void> _precacheVendorsAndShow() async {
    final images = vendors
        .take(8)
        .where((v) => v.photo.isNotEmpty)
        .map((v) => v.photo)
        .toList();
    await _precacheBatch(images);
    if (!mounted) return;
    _firstVendorReceived = true;
    _tryHideSkeleton();
    // Now that the page is visible, it's safe to start the whole-catalog
    // product fetch without it competing for bandwidth with first paint.
    _startProductsFetchIfNeeded();
  }

  // Starts the (large, unscoped) product catalog fetch used for card menu
  // previews, and wires up processing of its result. Only fires once per
  // getData() cycle — see the reset in getData() — and only after the
  // skeleton has already been dismissed.
  void _startProductsFetchIfNeeded() {
    if (_productsFetchStarted) return;
    _productsFetchStarted = true;
    final future = (selctedOrderTypeValue == "Takeaway".tr() ||
            selctedOrderTypeValue == "Dineaway".tr())
        ? fireStoreUtils.getAllTakeAWayProducts()
        : fireStoreUtils.getAllDelevryProducts();
    productsFuture = future;
    future.then(_handleProducts);
  }

  String? name = "";

  String? selctedOrderTypeValue = "Delivery".tr();

  bool isLoading = true;
  // Skeleton is hidden only when both banner data AND the first vendor batch
  // have arrived. Setting either flag early (via stream or banner completion)
  // is safe — _tryHideSkeleton checks both before acting.
  bool _bannerReady = false;
  bool _firstVendorReceived = false;
  bool _precachingVendors = false;

  getLocationData() async {
    try {
      await getData();
    } catch (e) {
      getPermission();
    }
  }

  getPermission() async {
    // Keep skeleton visible while requesting permission; getData() will hide it
    loc.PermissionStatus _permissionGranted = await location.hasPermission();
    if (_permissionGranted == PermissionStatus.denied) {
      _permissionGranted = await location.requestPermission();
      if (_permissionGranted != PermissionStatus.granted) {
        getData();
        return;
      }
    }
    getData();
  }

  loc.Location location = loc.Location();

  bool? storyEnable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    print("AK DEBUG: HomeScreen initState");
    // The live listener itself lives in ContainerScreen (one listener for the
    // whole app); this screen just rebuilds when the shared notifiers change.
    isDeliveryActiveNotifier.addListener(_onDeliveryGateChanged);
    deliveryOffMessageNotifier.addListener(_onDeliveryGateChanged);
    getLocationData();
    getBanner();
  }

  void _onDeliveryGateChanged() {
    if (mounted) setState(() {});
  }

  List<BannerModel> bannerTopHome = [];
  List<BannerModel> bannerMiddleHome = [];

  bool isListView = true;
  bool isHomeBannerLoading = true;
  bool isHomeBannerMiddleLoading = true;
  List<VendorCategoryModel> vendorCategoryModel = [];

  getBanner() async {
    await fireStoreUtils.getCuisines().then((value) {
      vendorCategoryModel = value;
    });
    await fireStoreUtils.getHomeTopBanner().then((value) {
      setState(() {
        bannerTopHome = value;
        isHomeBannerLoading = false;
      });
    });
    await FireStoreUtils.firestore
        .collection(Setting)
        .doc('story')
        .get()
        .then((value) {
      setState(() {
        storyEnable = value.data()?['isEnabled'] ?? false;
      });
    });
    // Precache category and top-banner images so they are painted before the
    // skeleton disappears. A 5-second timeout (inside _precacheBatch) ensures
    // we never block indefinitely on a slow network.
    if (mounted) {
      await _precacheBatch([
        ...vendorCategoryModel
            .where((c) => (c.photo ?? '').isNotEmpty)
            .map((c) => c.photo!),
        ...bannerTopHome
            .where((b) => (b.photo ?? '').isNotEmpty)
            .map((b) => b.photo!),
      ]);
    }
    // Categories + top banner + story flag are everything visible at first
    // paint — signal and try to dismiss skeleton without waiting on the
    // middle banner, which is below the fold.
    _bannerReady = true;
    _tryHideSkeleton();

    // Middle banner renders after "New Arrivals" — load it independently so
    // it never delays the skeleton.
    _loadMiddleBanner();
  }

  void _loadMiddleBanner() {
    fireStoreUtils.getHomeMiddleBanner().then((value) {
      if (!mounted) return;
      setState(() {
        bannerMiddleHome = value;
        isHomeBannerMiddleLoading = false;
      });
      _precacheBatch(value
          .where((b) => (b.photo ?? '').isNotEmpty)
          .map((b) => b.photo!)
          .toList());
    });
  }

  @override
  Widget build(BuildContext context) {
    /// BY AK
    final isDelivery = selctedOrderTypeValue == "Delivery";
    ///

    return Scaffold(
      backgroundColor:
      isDarkMode(context) ? AppThemeData.surfaceDark : AppThemeData.surface,
      body: isLoading == true
          ? HomeSkeletonLoader(orderType: selctedOrderTypeValue ?? 'Delivery')
          : Padding(
        padding: EdgeInsets.only(
            top: MediaQuery.of(context).viewPadding.top),
        child: isListView == false
            ? MapViewScreen(isShowAppBar: false)
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ═══════════════════════════════════════════════════
            // HEADER SECTION — CHANGED
            // ═══════════════════════════════════════════════════
            Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),

                      // ── Top Row: Hamburger | Greeting+Location | Cart ──
                      Row(
                        crossAxisAlignment:
                        CrossAxisAlignment.center,
                        children: [
                          // ── Hamburger button ──────────────────
                          InkWell(
                            onTap: () =>
                                widget.onOpenDrawer?.call(),
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isDarkMode(context)
                                    ? AppThemeData.grey700
                                    : AppThemeData.grey200,
                              ),
                              child: const Icon(Icons.menu,
                                  size: 20),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // ── Greeting + Location ───────────────
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // "Hello, Rahul 👋" or "Login"
                                MyAppState.currentUser == null
                                    ? InkWell(
                                  onTap: () =>
                                      pushAndRemoveUntil(
                                          context,
                                          LoginScreen()),
                                  child: Text(
                                    "Login".tr(),
                                    style: TextStyle(
                                      fontFamily:
                                      AppThemeData
                                          .regular,
                                      fontSize: 12,
                                      color:
                                      isDarkMode(context)
                                          ? AppThemeData
                                          .grey400
                                          : AppThemeData
                                          .grey600,
                                    ),
                                  ),
                                )
                                    : Text(
                                  "Hello, ${MyAppState.currentUser!.firstName} 👋",
                                  style: TextStyle(
                                    fontFamily:
                                    AppThemeData.regular,
                                    fontSize: 12,
                                    color:
                                    isDarkMode(context)
                                        ? AppThemeData
                                        .grey400
                                        : AppThemeData
                                        .grey600,
                                  ),
                                ),
                                const SizedBox(height: 2),

                                // 📍 Address + chevron
                                InkWell(
                                  onTap: () async {
                                    if (MyAppState.currentUser !=
                                        null) {
                                      await Navigator.of(context)
                                          .push(MaterialPageRoute(
                                          builder: (context) =>
                                              DeliveryAddressScreen()))
                                          .then((value) {
                                        if (value != null) {
                                          AddressModel
                                          addressModel = value;
                                          MyAppState
                                              .selectedPosotion =
                                              addressModel;
                                          _onLocationChanged();
                                        }
                                      });
                                    } else {
                                      checkPermission(() async {
                                        await showProgress(
                                            "Please wait...".tr(),
                                            false);
                                        AddressModel addressModel =
                                        AddressModel();
                                        try {
                                          await Geolocator
                                              .requestPermission();
                                          await Geolocator
                                              .getCurrentPosition();
                                          await hideProgress();
                                          if (selectedMapType ==
                                              'osm') {
                                            Navigator.of(context)
                                                .push(MaterialPageRoute(
                                                builder: (context) =>
                                                    LocationPicker()))
                                                .then(
                                                    (value) async {
                                                  if (value != null) {
                                                    AddressModel
                                                    addressModel =
                                                    AddressModel();
                                                    addressModel
                                                        .addressAs =
                                                    "Home";
                                                    addressModel
                                                        .locality =
                                                        value.displayName!
                                                            .toString();
                                                    addressModel
                                                        .location =
                                                        UserLocation(
                                                            latitude:
                                                            value
                                                                .lat,
                                                            longitude:
                                                            value
                                                                .lon);
                                                    MyAppState
                                                        .selectedPosotion =
                                                        addressModel;
                                                    _onLocationChanged();
                                                  }
                                                });
                                          } else {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    PlacePicker(
                                                      apiKey:
                                                      GOOGLE_API_KEY,
                                                      onPlacePicked:
                                                          (result) async {
                                                        AddressModel
                                                        addressModel =
                                                        AddressModel();
                                                        addressModel
                                                            .addressAs =
                                                        "Home";
                                                        addressModel
                                                            .locality =
                                                            result
                                                                .formattedAddress!
                                                                .toString();
                                                        addressModel.location = UserLocation(
                                                            latitude: result
                                                                .geometry!
                                                                .location
                                                                .lat,
                                                            longitude: result
                                                                .geometry!
                                                                .location
                                                                .lng);
                                                        MyAppState
                                                            .selectedPosotion =
                                                            addressModel;
                                                        _onLocationChanged();
                                                        Navigator.pop(
                                                            context);
                                                      },
                                                      initialPosition:
                                                      const LatLng(
                                                          -33.8567844,
                                                          151.213108),
                                                      useCurrentLocation:
                                                      true,
                                                      selectInitialPosition:
                                                      true,
                                                      usePinPointingSearch:
                                                      true,
                                                      usePlaceDetailSearch:
                                                      true,
                                                      zoomGesturesEnabled:
                                                      true,
                                                      zoomControlsEnabled:
                                                      true,
                                                      resizeToAvoidBottomInset:
                                                      false,
                                                    ),
                                              ),
                                            );
                                          }
                                        } catch (e) {
                                          // GPS failed — do not set a
                                          // hardcoded location; the user
                                          // must pick their address manually.
                                          await hideProgress();
                                          getData();
                                        }
                                      }, context);
                                    }
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.location_on,
                                        color: AppThemeData.primary500,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 3),
                                      Flexible(
                                        child: Text(
                                          MyAppState
                                              .selectedPosotion
                                              .getFullAddress(),
                                          maxLines: 1,
                                          overflow:
                                          TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontFamily: AppThemeData
                                                .semiBold,
                                            fontSize: 14,
                                            color: isDarkMode(
                                                context)
                                                ? AppThemeData
                                                .grey50
                                                : AppThemeData
                                                .grey900,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Icon(
                                        Icons
                                            .keyboard_arrow_down_rounded,
                                        size: 18,
                                        color: isDarkMode(context)
                                            ? AppThemeData.grey50
                                            : AppThemeData.grey900,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 8),

                          // ── Cart icon in circle with badge ────
                          InkWell(
                            onTap: () {
                              if (MyAppState.currentUser == null) {
                                push(context,
                                    const LoginScreen());
                              } else {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        ContainerScreen(
                                          user: MyAppState
                                              .currentUser!,
                                          currentWidget: CartScreen(),
                                          appBarTitle:
                                          'Your Cart'.tr(),
                                          drawerSelection:
                                          DrawerSelection.Cart,
                                        ),
                                  ),
                                );
                              }
                            },
                            child: StreamBuilder<List<CartProduct>>(
                              stream: cartDatabase.watchProducts,
                              builder: (context, snapshot) {
                                cartCount = 0;
                                if (snapshot.hasData) {
                                  for (var element
                                  in snapshot.data!) {
                                    cartCount += element.quantity;
                                  }
                                }
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isDarkMode(context)
                                            ? AppThemeData.grey700
                                            : AppThemeData.grey200,
                                      ),
                                      child: Icon(
                                        Icons
                                            .shopping_cart_outlined,
                                        color:
                                        AppThemeData.primary500,
                                        size: 20,
                                      ),
                                    ),
                                    if (cartCount >= 1)
                                      Positioned(
                                        right: -4,
                                        top: -4,
                                        child: Container(
                                          padding:
                                          const EdgeInsets.all(
                                              4),
                                          decoration:
                                          const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: AppThemeData
                                                .primary500,
                                          ),
                                          constraints:
                                          const BoxConstraints(
                                            minWidth: 18,
                                            minHeight: 18,
                                          ),
                                          child: Center(
                                            child: Text(
                                              cartCount <= 99
                                                  ? '$cartCount'
                                                  : '+99',
                                              style:
                                              const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight:
                                                FontWeight.bold,
                                              ),
                                              textAlign:
                                              TextAlign.center,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // ── Search bar with mic icon ──────────────
                      InkWell(
                        onTap: () =>
                            push(context, const SearchScreen()),
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: isDarkMode(context)
                                ? AppThemeData.grey800
                                : AppThemeData.grey100,
                            borderRadius:
                            BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 14),
                              Icon(
                                Icons.search,
                                color: isDarkMode(context)
                                    ? AppThemeData.grey400
                                    : AppThemeData.grey500,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "Search dishes, restaurants, meals..."
                                      .tr(),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontFamily:
                                    AppThemeData.regular,
                                    color: isDarkMode(context)
                                        ? AppThemeData.grey400
                                        : AppThemeData.grey500,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.mic_none_rounded,
                                color: isDarkMode(context)
                                    ? AppThemeData.grey400
                                    : AppThemeData.grey500,
                                size: 20,
                              ),
                              const SizedBox(width: 14),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 5),
                    ],
                  ),
                ),
              ],
            ),
            // ═══════════════════════════════════════════════════
            // END HEADER SECTION
            // ═══════════════════════════════════════════════════

            Expanded(
              child: RefreshIndicator(
                onRefresh: _onRefresh,
                color: AppThemeData.primary500,
                backgroundColor:
                    isDarkMode(context) ? AppThemeData.surfaceDark : Colors.white,
                displacement: 50,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                  children: (isDelivery && !isDeliveryActiveNotifier.value)
                      ? [
                          ComingSoonView(message: deliveryOffMessageNotifier.value),
                        ]
                      : [
                    storyList.isEmpty || storyEnable == false
                        ? const SizedBox()
                        : storyList.isNotEmpty &&
                          ((selctedOrderTypeValue ==
                              "Takeaway".tr() ||
                              selctedOrderTypeValue ==
                                  "Dineaway".tr()) &&
                              storyList.any((story) =>
                              story.takeaway &&
                                  (story.hasVideo || story.hasImage))) ||
                          (selctedOrderTypeValue ==
                              "Delivery".tr() &&
                              storyList.any((story) =>
                              story.delivery &&
                                  story.hasImage))
                          ? Column(
                        mainAxisAlignment:
                        MainAxisAlignment.start,
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: titleView("Today's Specials", () {}),
                          ),
                          const SizedBox(height: 10),
                          StoryView(
                            storyList: storyList,
                            orderType:
                            selctedOrderTypeValue ??
                                "Delivery".tr(),
                            vendors: vendors,
                            deliveryProductsByVendor: _deliveryProductsByVendor,
                          ),
                        ],
                      )
                          : const SizedBox(),
                    SizedBox(
                      height: storyList.isEmpty ? 0 : 20,
                    ),
                    if (selctedOrderTypeValue == "Delivery") ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: titleView("Eat What Makes You Happy", () {
                          push(context, const CuisinesScreen(isPageCallFromHomeScreen: true));
                        }),
                      ),
                      const SizedBox(height: 10),
                      CategoryView(vendorCategoryList: vendorCategoryModel),
                    ],
                    const SizedBox(height: 32),
                    bannerTopHome.isEmpty
                        ? const SizedBox()
                        : BannerView(bannerList: bannerTopHome),

                    /// BY AK
                    if (isDelivery && lstNearByFood.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16),
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            _sectionTitle("Top Selling"),
                            const SizedBox(height: 10),
                            TopSellingView(
                              vendors: vendors,
                              lstNearByFood: lstNearByFood,
                            ),
                          ],
                        ),
                      )
                    else
                      const SizedBox(),

                    // if (isDelivery &&
                    //     recommendedProducts.isNotEmpty)
                    //   Padding(
                    //     padding: const EdgeInsets.symmetric(
                    //         horizontal: 16),
                    //     child: Column(
                    //       crossAxisAlignment:
                    //       CrossAxisAlignment.start,
                    //       children: [
                    //         titleView("Recommend for you", () {}),
                    //         const SizedBox(height: 10),
                    //         RecommendForYouView(
                    //           vendors: vendors,
                    //           recommendedProducts:
                    //           recommendedProducts,
                    //         ),
                    //       ],
                    //     ),
                    //   )
                    // else
                    //   const SizedBox(),
                    ///

                    Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _sectionTitle("New Arrivals"),
                        ),
                        const SizedBox(height: 10),
                        NewArrival(
                            newArrivalRestaurantList:
                            newArrivalRestaurantList,
                            isDelivery: isDelivery,
                            productsByVendor: _deliveryProductsByVendor)
                      ],
                    ),
                    const SizedBox(height: 32),
                    bannerMiddleHome.isEmpty
                        ? const SizedBox()
                        : BannerView(bannerList: bannerMiddleHome),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          _sectionTitle("${vendors.length} Restaurants Around You"),
                          const SizedBox(height: 10),
                          _restaurantSortBar(),
                          const SizedBox(height: 10),
                          AllStore(
                              allStoreList: vendors,
                              offerBadges: _offerBadgeByVendorId,
                              isDelivery: isDelivery,
                              productsByVendor: _deliveryProductsByVendor)
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            )
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        // lift above system nav bar when present
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom > 0 ? 0 : 8,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          clipBehavior: Clip.antiAliasWithSaveLayer,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: isDarkMode(context)
                    ? Colors.black.withValues(alpha: 0.58)
                    : Colors.white.withValues(alpha: 0.90),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: isDarkMode(context)
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.black.withValues(alpha: 0.06),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 28,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── List view toggle ────────────────────────────────
                  _FabIconButton(
                    isActive: isListView,
                    isDark: isDarkMode(context),
                    onTap: () => setState(() => isListView = true),
                    child: SvgPicture.asset(
                      'assets/icons/ic_view_grid_list.svg',
                      width: 18,
                      height: 18,
                      colorFilter: ColorFilter.mode(
                        isListView
                            ? Colors.white
                            : (isDarkMode(context)
                                ? AppThemeData.grey400
                                : AppThemeData.grey500),
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                  // ── Map view toggle ─────────────────────────────────
                  _FabIconButton(
                    isActive: !isListView,
                    isDark: isDarkMode(context),
                    onTap: () => setState(() => isListView = false),
                    child: SvgPicture.asset(
                      'assets/icons/ic_map_draw.svg',
                      width: 18,
                      height: 18,
                      colorFilter: ColorFilter.mode(
                        !isListView
                            ? Colors.white
                            : (isDarkMode(context)
                                ? AppThemeData.grey400
                                : AppThemeData.grey500),
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                  // ── QR Scanner — slides in/out with AnimatedSize ────
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    child: (selctedOrderTypeValue == 'Takeaway'.tr() ||
                            selctedOrderTypeValue == 'Dineaway'.tr())
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _FabDivider(isDark: isDarkMode(context)),
                              _FabIconButton(
                                isActive: false,
                                isDark: isDarkMode(context),
                                onTap: () => push(context,
                                    const QrCodeScanner(presectionList: [])),
                                child: SvgPicture.asset(
                                  'assets/icons/ic_scan_code.svg',
                                  width: 18,
                                  height: 18,
                                  colorFilter: ColorFilter.mode(
                                    isDarkMode(context)
                                        ? AppThemeData.grey300
                                        : AppThemeData.grey600,
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                  // ── Divider + delivery type selector ────────────────
                  _FabDivider(isDark: isDarkMode(context)),
                  DeliveryTypeSelector(
                    selectedValue: selctedOrderTypeValue!,
                    isDarkMode: isDarkMode(context),
                    onValueChanged: (String newValue) async {
                      // Switching Delivery/Dineaway changes special-offer
                      // matching, eligibility thresholds, and ranking — show
                      // the skeleton immediately so stale results from the
                      // old section aren't visible while the new section's
                      // data loads, same pattern as _onLocationChanged().
                      setState(() {
                        selctedOrderTypeValue = newValue;
                        currentOrderTypeGlobal = newValue;
                        isLoading = true;
                        _firstVendorReceived = false;
                        _precachingVendors = false;
                        saveFoodTypeValue();
                      });
                      getData();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  titleView(String name, Function()? onPress) {
    return Row(
      children: [
        Expanded(
          child: Text(
            name.tr(),
            textAlign: TextAlign.start,
            style: TextStyle(
              fontSize: 18,
              fontFamily: AppThemeData.bold,
              color: isDarkMode(context)
                  ? AppThemeData.grey50
                  : AppThemeData.grey900,
            ),
          ),
        ),
        InkWell(
          onTap: () {
            onPress!();
          },
          child: Text(
            "View all".tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppThemeData.regular,
              color: isDarkMode(context)
                  ? AppThemeData.primary500
                  : AppThemeData.primary500,
            ),
          ),
        )
      ],
    );
  }

  // Manual sort chips for the "Restaurants Around You" feed — re-sorts the
  // already-loaded `vendors` list in place (_sortRestaurants), no new fetch.
  Widget _restaurantSortBar() {
    return Row(
      children: [
        _sortChip('offer', 'Offers'.tr(), Icons.local_offer_rounded),
        const SizedBox(width: 8),
        _sortChip('nearest', 'Nearest'.tr(), Icons.near_me_rounded),
        const SizedBox(width: 8),
        _sortChip('rating', 'Rating'.tr(), Icons.star_rounded),
      ],
    );
  }

  Widget _sortChip(String mode, String label, IconData icon) {
    final bool selected = _manualSortMode == mode;
    final dark = isDarkMode(context);
    return GestureDetector(
      onTap: () {
        setState(() {
          _manualSortMode = selected ? null : mode;
          _sortRestaurants();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppThemeData.primary500
              : (dark ? AppThemeData.grey800 : AppThemeData.grey100),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppThemeData.primary500
                : (dark ? AppThemeData.grey700 : AppThemeData.grey200),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: selected
                    ? Colors.white
                    : (dark ? Colors.white : Colors.black)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontFamily: AppThemeData.semiBold,
                color: selected
                    ? Colors.white
                    : (dark ? Colors.white : Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String name) {
    return Text(
      name.tr(),
      textAlign: TextAlign.start,
      style: TextStyle(
        fontSize: 18,
        fontFamily: AppThemeData.bold,
        color: isDarkMode(context) ? AppThemeData.grey50 : AppThemeData.grey900,
      ),
    );
  }

  Future<void> _onRefresh() async {
    // Pull-to-refresh: keep isLoading = false (no skeleton during refresh).
    // Reset story state so they re-fetch from Firestore.
    _storiesLoaded = false;
    allStories.clear();
    storyList.clear();
    // Banners, coupons, categories: await so the indicator stays visible
    // while the most prominent content reloads. _bannerReady / _firstVendorReceived
    // don't need to be reset because isLoading stays false, so _tryHideSkeleton
    // is already a no-op.
    await getBanner();
    // Restaurants arrive via stream — fire-and-forget; UI updates live.
    getData();
  }

  @override
  void dispose() {
    _vendorSub?.cancel();
    isDeliveryActiveNotifier.removeListener(_onDeliveryGateChanged);
    deliveryOffMessageNotifier.removeListener(_onDeliveryGateChanged);
    WidgetsBinding.instance.removeObserver(this);
    fireStoreUtils.closeOfferStream();
    fireStoreUtils.closeVendorStream();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _pausedAt = DateTime.now();
        break;
      case AppLifecycleState.resumed:
        if (_pausedAt != null &&
            DateTime.now().difference(_pausedAt!) >=
                const Duration(seconds: 30)) {
          _pausedAt = null;
          _onRefresh();
        }
        break;
      default:
        break;
    }
  }

  Future<void> saveFoodTypeValue() async {
    SharedPreferences sp = await SharedPreferences.getInstance();
    sp.setString('foodType', selctedOrderTypeValue!);
  }

  getFoodType() async {
    SharedPreferences sp = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        String? savedFoodType = sp.getString("foodType");
        List<String> validOptions = ['Delivery'.tr(), 'Dineaway'.tr()];
        selctedOrderTypeValue = (savedFoodType == null ||
            savedFoodType == "" ||
            !validOptions.contains(savedFoodType))
            ? "Delivery".tr()
            : savedFoodType;
        currentOrderTypeGlobal = selctedOrderTypeValue!;
      });
    }
    // The actual product-catalog fetch is started later, by
    // _startProductsFetchIfNeeded() — see _precacheVendorsAndShow().
  }

  List<StoryModel> storyList = [];
  List<StoryModel> allStories = [];
  bool _storiesLoaded = false;

  Map<String, List<ProductModel>> _productsByVendor = {};

  // All of each vendor's published, delivery-eligible products (unlike
  // _productsByVendor above, not capped to the first 20 app-wide) — the
  // pool AllStore/NewArrival's delivery menu carousels rank/select from.
  Map<String, List<ProductModel>> _deliveryProductsByVendor = {};

  void _filterStories() {
    print('\n🎬 ===== STORY FILTERING START =====');
    print('📊 Total stories to filter: ${allStories.length}');
    print('📦 Total vendors available: ${vendors.length}');
    print('🔄 Current order type: $selctedOrderTypeValue');

    storyList.clear();
    Set<String> addedStoryIDs = {};

    allStories.forEach((element1) {
      if (!element1.approved) {
        print(
            '\n📍 Skipping story (not approved) for vendorID: ${element1.vendorID}');
        return;
      }

      if (element1.isExpired) {
        print(
            '\n📍 Skipping story (expired) for vendorID: ${element1.vendorID}');
        return;
      }

      bool vendorFound = false;
      vendors.forEach((element) {
        if (element1.vendorID == element.id) {
          vendorFound = true;

          if (!element.isAcceptingOrders) {
            print(
                '\n📍 Skipping story (vendor offline) for vendor: ${element.title}');
            return;
          }

          bool shouldAdd = false;

          if (selctedOrderTypeValue == "Delivery".tr() && element1.delivery) {
            if (element1.hasImage) {
              shouldAdd = true;
            }
          } else if ((selctedOrderTypeValue == "Dineaway".tr() ||
              selctedOrderTypeValue == "Takeaway".tr()) &&
              element1.takeaway) {
            if (element1.hasVideo || element1.hasImage) {
              shouldAdd = true;
            }
          }

          if (shouldAdd) {
            String uniqueKey;
            if (element1.storyID != null && element1.storyID!.isNotEmpty) {
              uniqueKey = element1.storyID!;
            } else {
              String createdAtStr = element1.createdAt != null
                  ? element1.createdAt!.millisecondsSinceEpoch.toString()
                  : DateTime.now().millisecondsSinceEpoch.toString();
              String contentHash = '';
              if (element1.hasVideo && element1.videoUrl.isNotEmpty) {
                contentHash =
                    element1.videoUrl[0].toString().hashCode.toString();
              } else if (element1.hasImage && element1.imageUrl.isNotEmpty) {
                contentHash =
                    element1.imageUrl[0].toString().hashCode.toString();
              }
              uniqueKey =
              '${element1.vendorID}_${createdAtStr}_$contentHash';
            }

            if (!addedStoryIDs.contains(uniqueKey)) {
              addedStoryIDs.add(uniqueKey);
              storyList.add(element1);
            }
          }
        }
      });

      if (!vendorFound) {
        print(
            '\n⚠️ Story with vendorID ${element1.vendorID} has no matching vendor in the list!');
      }
    });

    print('\n📋 Final filtered story count: ${storyList.length}');
    print('🎬 ===== STORY FILTERING END =====\n');
    setState(() {});
  }

  Future<void> getData() async {
    print("AK DEBUG: getData called");
    // Cancel any previous subscription so stale Firestore events from an old
    // location cannot fire after a new location has been selected.
    await _vendorSub?.cancel();
    _vendorSub = null;
    _productsFetchStarted = false;
    getFoodType();
    lstNearByFood.clear();
    _loadNormalOffersForRanking();
    lstAllRestaurant =
        fireStoreUtils.getAllStores().asBroadcastStream();

    if (MyAppState.currentUser != null) {
      name = toBeginningOfSentenceCase(widget.user!.firstName);
    }

    _vendorSub = lstAllRestaurant!.listen((event) {
      print("AK DEBUG: Firestore vendors = ${event.length}");

      popularRestaurantLst.clear();
      vendors.clear();
      newArrivalRestaurantList.clear();
      vendors.addAll(event);

      print("AK DEBUG: vendors count = ${vendors.length}");

      _sortRestaurants();

      allstoreList.clear();
      allstoreList.addAll(vendors);

      // Only processes if the fetch has already been started (it deliberately
      // hasn't been, on the very first batch — see _startProductsFetchIfNeeded).
      productsFuture?.then(_handleProducts);

      popularRestaurantLst.addAll(event);
      newArrivalRestaurantList.addAll(event);

      newArrivalRestaurantList.sort(
            (a, b) => (b.createdAt ?? Timestamp.now())
            .toDate()
            .compareTo((a.createdAt ?? Timestamp.now()).toDate()),
      );

      List<VendorModel> temp5 = popularRestaurantLst
          .where((element) =>
      num.parse(
          (element.reviewsSum / element.reviewsCount).toString()) ==
          5)
          .toList();
      List<VendorModel> temp5_ = popularRestaurantLst
          .where((element) =>
      num.parse(
          (element.reviewsSum / element.reviewsCount).toString()) >
          4 &&
          num.parse(
              (element.reviewsSum / element.reviewsCount).toString()) <
              5)
          .toList();
      List<VendorModel> temp4 = popularRestaurantLst
          .where((element) =>
      num.parse(
          (element.reviewsSum / element.reviewsCount).toString()) >
          3 &&
          num.parse(
              (element.reviewsSum / element.reviewsCount).toString()) <
              4)
          .toList();
      List<VendorModel> temp3 = popularRestaurantLst
          .where((element) =>
      num.parse(
          (element.reviewsSum / element.reviewsCount).toString()) >
          2 &&
          num.parse(
              (element.reviewsSum / element.reviewsCount).toString()) <
              3)
          .toList();
      List<VendorModel> temp2 = popularRestaurantLst
          .where((element) =>
      num.parse(
          (element.reviewsSum / element.reviewsCount).toString()) >
          1 &&
          num.parse(
              (element.reviewsSum / element.reviewsCount).toString()) <
              2)
          .toList();
      List<VendorModel> temp1 = popularRestaurantLst
          .where((element) =>
      num.parse(
          (element.reviewsSum / element.reviewsCount).toString()) ==
          1)
          .toList();
      List<VendorModel> temp0 = popularRestaurantLst
          .where((element) =>
      num.parse(
          (element.reviewsSum / element.reviewsCount).toString()) ==
          0)
          .toList();
      List<VendorModel> temp0_ = popularRestaurantLst
          .where((element) =>
      element.reviewsSum == 0 && element.reviewsCount == 0)
          .toList();

      popularRestaurantLst.clear();
      popularRestaurantLst.addAll(temp5);
      popularRestaurantLst.addAll(temp5_);
      popularRestaurantLst.addAll(temp4);
      popularRestaurantLst.addAll(temp3);
      popularRestaurantLst.addAll(temp2);
      popularRestaurantLst.addAll(temp1);
      popularRestaurantLst.addAll(temp0);
      popularRestaurantLst.addAll(temp0_);

      // All synchronous vendor processing is done. On the first batch, kick off
      // image precaching; the skeleton hides only after that completes. For
      // subsequent stream events (live updates / order-type change), just rebuild.
      if (!_firstVendorReceived && !_precachingVendors) {
        _precachingVendors = true;
        _precacheVendorsAndShow();
      } else if (mounted && _firstVendorReceived) {
        setState(() {});
      }

      if (_storiesLoaded && allStories.isNotEmpty) {
        _filterStories();
      }

      if (!_storiesLoaded) {
        FireStoreUtils().getStory().then((value) {
          allStories = value;
          _storiesLoaded = true;
          _filterStories();
        });
      }
    });
  }

  // Processes the whole-catalog product fetch's result into the per-vendor
  // lookup maps the card menu carousels read from. Called once the fetch
  // resolves, and again on every later vendor-stream event so live updates
  // (new vendor, order-type toggle) stay reflected — uses `vendors` (the
  // current list) rather than a stream-event snapshot, since this can run
  // well after the event that originally triggered the fetch.
  void _handleProducts(List<ProductModel> value) {
    _productsByVendor.clear();
    for (var product in value.take(20)) {
      _productsByVendor.putIfAbsent(product.vendorID, () => []).add(product);
    }

    _deliveryProductsByVendor.clear();
    for (var product in value) {
      if (!product.publish || !product.deliveryOption) continue;
      if (product.productStatus != 'approved') continue;
      _deliveryProductsByVendor
          .putIfAbsent(product.vendorID, () => [])
          .add(product);
    }
    if (mounted) setState(() {});

    for (var vendor in vendors) {
      if (vendor.isAcceptingOrders) {
        final vendorProducts = _productsByVendor[vendor.id];
        if (vendorProducts != null) {
          for (var product in vendorProducts) {
            if (!lstNearByFood.contains(product)) {
              lstNearByFood.add(product);
            }
          }
        }
      }
    }

    recommendedProducts.clear();
    List<ProductModel> shuffledProducts = List.from(lstNearByFood);
    shuffledProducts.shuffle();
    recommendedProducts = shuffledProducts.take(20).toList();
  }

  final StoryController controller = StoryController();
}

// ─────────────────────────────────────────────────────────────────────────────
// StoryView
// ─────────────────────────────────────────────────────────────────────────────
class StoryView extends StatefulWidget {
  final List<StoryModel> storyList;
  final String orderType;
  // Vendors are already loaded by HomeScreen's getData() — every story here
  // was already matched to one of these by _filterStories(), so looking
  // vendors up here instead of re-fetching by ID is always safe.
  final List<VendorModel> vendors;
  final Map<String, List<ProductModel>> deliveryProductsByVendor;

  const StoryView({
    super.key,
    required this.storyList,
    required this.orderType,
    required this.vendors,
    required this.deliveryProductsByVendor,
  });

  @override
  State<StoryView> createState() => _StoryViewState();
}

class _StoryViewState extends State<StoryView> {
  late ScrollController _scrollController;

  final Map<String, String?> _thumbnailCache = {};

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  Future<String?> _generateVideoThumbnail(String videoUrl) async {
    if (_thumbnailCache.containsKey(videoUrl)) {
      return _thumbnailCache[videoUrl];
    }
    try {
      final tempDir = await getTemporaryDirectory();
      final thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: videoUrl,
        thumbnailPath: tempDir.path,
        imageFormat: ImageFormat.PNG,
        timeMs: 1000,
        quality: 75,
      );
      if (thumbnailPath != null) {
        final file = File(thumbnailPath);
        if (await file.exists()) {
          _thumbnailCache[videoUrl] = thumbnailPath;
          return thumbnailPath;
        }
      }
    } catch (e) {
      print('❌ Error generating video thumbnail: $e');
    }
    _thumbnailCache[videoUrl] = null;
    return null;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double _sw = MediaQuery.of(context).size.width;
    final double _storyH = (_sw * 0.40).clamp(130.0, 180.0);
    final double _storyExt = (_sw * 0.34).clamp(110.0, 155.0);
    final double _videoH = (_sw * 0.50).clamp(155.0, 220.0);
    final double _videoExt = (_sw * 0.40).clamp(130.0, 190.0);
    // Built once per build() (not per item) and reused for every story card
    // below — vendors are already in memory, no per-card Firestore reads.
    final Map<String, VendorModel> vendorsById = {
      for (final v in widget.vendors) v.id: v
    };
    if (widget.orderType == "Delivery".tr()) {
      return SizedBox(
        height: _storyH,
        child: ListView.builder(
          controller: _scrollController,
          physics: const ClampingScrollPhysics(),
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          itemCount: widget.storyList.length,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          itemExtent: _storyExt,
          itemBuilder: (context, index) =>
              _buildStoryItem(widget.storyList[index], index, vendorsById),
        ),
      );
    }

    return SizedBox(
      height: _videoH,
      child: ListView.builder(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        itemCount: widget.storyList.length,
        scrollDirection: Axis.horizontal,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        itemExtent: _videoExt,
        itemBuilder: (context, index) {
          StoryModel storyModel = widget.storyList[index];

          String thumbnailUrl = '';
          bool needsThumbnailGeneration = false;
          String? videoUrlForThumbnail;
          final bool isVideo = storyModel.hasVideo;

          if (widget.orderType == "Dineaway".tr() ||
              widget.orderType == "Takeaway".tr()) {
            if (storyModel.hasVideo &&
                storyModel.videoThumbnail != null &&
                storyModel.videoThumbnail!.isNotEmpty) {
              thumbnailUrl = storyModel.videoThumbnail.toString();
            } else if (storyModel.videoThumbnail != null &&
                storyModel.videoThumbnail!.isNotEmpty) {
              thumbnailUrl = storyModel.videoThumbnail.toString();
            } else if (storyModel.hasVideo &&
                storyModel.videoUrl.isNotEmpty) {
              needsThumbnailGeneration = true;
              videoUrlForThumbnail = storyModel.videoUrl[0].toString();
            } else if (storyModel.hasImage &&
                storyModel.imageUrl.isNotEmpty) {
              thumbnailUrl = storyModel.imageUrl[0].toString();
            }
          }

          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => MoreStories(
                          storyList: widget.storyList,
                          index: index,
                          orderType: widget.orderType,
                        )));
              },
              child: Container(
                width: _videoExt - 10,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isVideo
                        ? AppThemeData.primary500.withValues(alpha: 0.7)
                        : AppThemeData.neutral200,
                    width: isVideo ? 2.5 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 16,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Thumbnail
                      needsThumbnailGeneration &&
                              videoUrlForThumbnail != null
                          ? FutureBuilder<String?>(
                              future: _generateVideoThumbnail(
                                  videoUrlForThumbnail),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return _StoryShimmer();
                                } else if (snapshot.hasData &&
                                    snapshot.data != null) {
                                  return Image.file(
                                    File(snapshot.data!),
                                    fit: BoxFit.cover,
                                  );
                                } else {
                                  return Container(
                                      color: const Color(0xFF1A1A2E));
                                }
                              },
                            )
                          : thumbnailUrl.isNotEmpty
                              ? NetworkImageWidget(
                                  imageUrl: thumbnailUrl,
                                  fit: BoxFit.cover,
                                )
                              : Container(color: const Color(0xFF1A1A2E)),

                      // Gradient scrim
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.75),
                            ],
                            stops: const [0.4, 1.0],
                          ),
                        ),
                      ),

                      // Video play indicator (top-right)
                      if (isVideo)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  width: 1.5),
                            ),
                            child: const Icon(Icons.play_arrow_rounded,
                                color: Colors.white, size: 16),
                          ),
                        ),

                      // Vendor info overlay at bottom — looked up from the
                      // already-loaded vendor list, no per-card fetch.
                      if (vendorsById[storyModel.vendorID.toString()] != null)
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 8,
                          child: Builder(builder: (context) {
                            final VendorModel vm =
                                vendorsById[storyModel.vendorID.toString()]!;
                            return Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.center,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 1.5),
                                  ),
                                  child: ClipOval(
                                    child: NetworkImageWidget(
                                      imageUrl: vm.photo.toString(),
                                      width: 26,
                                      height: 26,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        vm.title.toString(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontFamily: AppThemeData.semiBold,
                                          shadows: [
                                            Shadow(
                                                color: Colors.black45,
                                                blurRadius: 4)
                                          ],
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          const Icon(Icons.star_rounded,
                                              color: Color(0xFFFBBC05),
                                              size: 10),
                                          const SizedBox(width: 2),
                                          Text(
                                            calculateReview(
                                                reviewCount: vm.reviewsCount
                                                    .toString(),
                                                reviewSum: vm.reviewsSum
                                                    .toStringAsFixed(0)),
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withValues(alpha: 0.85),
                                              fontSize: 9,
                                              fontFamily:
                                                  AppThemeData.medium,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStoryItem(StoryModel storyModel, int originalIndex,
      Map<String, VendorModel> vendorsById) {
    final double _sw = MediaQuery.of(context).size.width;
    final double _cardW = (_sw * 0.34).clamp(110.0, 155.0) - 10;
    final double _imgH = (_cardW * 0.80).clamp(85.0, 124.0);

    String thumbnailUrl = '';
    if (storyModel.hasImage && storyModel.imageUrl.isNotEmpty) {
      thumbnailUrl = storyModel.imageUrl[0].toString();
    } else if (storyModel.videoThumbnail != null &&
        storyModel.videoThumbnail!.isNotEmpty) {
      thumbnailUrl = storyModel.videoThumbnail.toString();
    }

    final dark = isDarkMode(context);

    // Both lookups are synchronous — the vendor is already in memory (every
    // story here was matched to one by _filterStories()), and so is its
    // delivery product list (_deliveryProductsByVendor), so no per-card
    // Firestore reads are needed here anymore.
    final VendorModel? vendorModel =
        vendorsById[storyModel.vendorID.toString()];
    if (vendorModel == null) {
      return const SizedBox();
    }
    double rating = 0.0;
    if (vendorModel.reviewsCount > 0) {
      rating = (vendorModel.reviewsSum / vendorModel.reviewsCount);
    }
    final List<ProductModel> vendorProducts =
        widget.deliveryProductsByVendor[vendorModel.id] ?? [];
    double highestDiscountPercent = 0.0;
    bool hasDiscount = false;
    for (var product in vendorProducts) {
      if (product.disPrice != null &&
          product.disPrice != "" &&
          product.disPrice != "0") {
        try {
          double originalPrice = double.parse(product.price);
          double discountedPrice = double.parse(product.disPrice ?? "0");
          if (originalPrice > discountedPrice && originalPrice > 0) {
            double discountPercent =
                ((originalPrice - discountedPrice) / originalPrice) * 100;
            if (discountPercent > highestDiscountPercent) {
              highestDiscountPercent = discountPercent;
              hasDiscount = true;
            }
          }
        } catch (e) {}
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Builder(
        builder: (context) {
          {
            return GestureDetector(
                  onTap: () {
                    if (widget.orderType == "Delivery".tr() &&
                        storyModel.hasImage) {
                      push(context,
                          NewVendorProductsScreen(vendorModel: vendorModel));
                    } else {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (context) => MoreStories(
                                storyList: widget.storyList,
                                index: originalIndex,
                                orderType: widget.orderType,
                              )));
                    }
                  },
                  child: Container(
                    width: _cardW,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: dark
                          ? AppThemeData.darkBgSecondary
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.09),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Image area with overlays
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(16),
                                topRight: Radius.circular(16),
                              ),
                              child: SizedBox(
                                width: double.infinity,
                                height: _imgH,
                                child: thumbnailUrl.isNotEmpty
                                    ? NetworkImageWidget(
                                        imageUrl: thumbnailUrl,
                                        fit: BoxFit.cover)
                                    : Container(
                                        color: dark
                                            ? const Color(0xFF2A2A3E)
                                            : const Color(0xFFE8ECF0)),
                              ),
                            ),
                            // Bottom image gradient
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              height: 40,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(16),
                                    topRight: Radius.circular(16),
                                  ),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.32),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Discount badge
                            if (hasDiscount && highestDiscountPercent > 0)
                              Positioned(
                                top: 7,
                                left: 7,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        AppThemeData.accent500,
                                        AppThemeData.accent600,
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppThemeData.accent500
                                            .withValues(alpha: 0.35),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    "${highestDiscountPercent.toStringAsFixed(0)}% OFF",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontFamily: AppThemeData.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        // Info area
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (rating > 0) ...[
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star_rounded,
                                        color: Color(0xFFFBBC05), size: 12),
                                    const SizedBox(width: 2),
                                    Text(
                                      rating.toStringAsFixed(1),
                                      style: TextStyle(
                                        color: dark
                                            ? AppThemeData.darkTextSecondary
                                            : AppThemeData.neutral600,
                                        fontSize: 10,
                                        fontFamily: AppThemeData.semiBold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                              ],
                              Text(
                                vendorModel.title.toString(),
                                textAlign: TextAlign.start,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.25,
                                  color: dark
                                      ? AppThemeData.darkTextPrimary
                                      : AppThemeData.neutral900,
                                  fontFamily: AppThemeData.semiBold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
          }
        },
      ),
    );
  }
}

class _StoryShimmer extends StatefulWidget {
  const _StoryShimmer({this.width, this.height = 105, this.borderRadius = 8});
  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<_StoryShimmer> createState() => _StoryShimmerState();
}

class _StoryShimmerState extends State<_StoryShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
          ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(
            dark ? const Color(0xFF2A2A2A) : const Color(0xFFE4E4E4),
            dark ? const Color(0xFF383838) : const Color(0xFFF5F5F5),
            _ctrl.value,
          ),
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Auto-sliding restaurant image carousel
// ─────────────────────────────────────────────────────────────────────────────
class _RestaurantCardImage extends StatefulWidget {
  final VendorModel vendorModel;
  final double height;
  final BorderRadius borderRadius;
  final bool showDots;

  const _RestaurantCardImage({
    required this.vendorModel,
    required this.height,
    required this.borderRadius,
    this.showDots = true,
  });

  @override
  State<_RestaurantCardImage> createState() => _RestaurantCardImageState();
}

class _RestaurantCardImageState extends State<_RestaurantCardImage> {
  late PageController _pageController;
  Timer? _timer;
  int _currentPage = 0;

  List<String> get _images {
    // photos[0] = logo (same as photo field), photos[1..n] = card gallery images.
    // Skip index 0 so only the actual card images appear in the carousel.
    // Entries may be a legacy URL string or a {original, cover} map — always
    // resolve through coverPhotoUrl() so the carousel shows the 16:9 cover.
    final allPhotos = widget.vendorModel.photos
        .map((e) => VendorModel.coverPhotoUrl(e))
        .where((s) => s.isNotEmpty && s != 'null')
        .toList();
    final cardImages = allPhotos.length > 1 ? allPhotos.sublist(1) : <String>[];
    if (cardImages.isNotEmpty) return cardImages;
    // Fallback: show the logo if no card images have been uploaded yet.
    final logo = widget.vendorModel.photo.toString();
    return logo.isNotEmpty && logo != 'null' ? [logo] : [''];
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    final imgs = _images;
    if (imgs.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!mounted) return;
        final next = (_currentPage + 1) % imgs.length;
        _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imgs = _images;
    return Stack(
      children: [
        ClipRRect(
          borderRadius: widget.borderRadius,
          child: imgs.length == 1
              ? NetworkImageWidget(
                  imageUrl: imgs[0],
                  fit: BoxFit.cover,
                  height: widget.height,
                  width: double.infinity,
                )
              : PageView.builder(
                  controller: _pageController,
                  itemCount: imgs.length,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemBuilder: (_, i) => NetworkImageWidget(
                    imageUrl: imgs[i],
                    fit: BoxFit.cover,
                    height: widget.height,
                    width: double.infinity,
                  ),
                ),
        ),
        if (widget.showDots && imgs.length > 1)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(imgs.length, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? Colors.white : Colors.white.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Delivery-mode menu carousel — replaces the restaurant photo with up to 5 of
// the vendor's own menu items (image, name, price), ranked by rolling 30-day
// sales with a sales → best-discount → lowest-price fallback chain.
// ─────────────────────────────────────────────────────────────────────────────
class _MenuCarousel extends StatefulWidget {
  final VendorModel vendorModel;
  final List<ProductModel> products;
  final double height;
  final BorderRadius borderRadius;
  final bool showDots;

  const _MenuCarousel({
    required this.vendorModel,
    required this.products,
    required this.height,
    required this.borderRadius,
    this.showDots = true,
  });

  @override
  State<_MenuCarousel> createState() => _MenuCarouselState();
}

class _MenuCarouselState extends State<_MenuCarousel> {
  late PageController _pageController;
  late Future<List<ProductModel>> _rankedFuture;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _rankedFuture =
        FireStoreUtils.getCarouselProducts(widget.vendorModel.id, widget.products);
  }

  @override
  void didUpdateWidget(covariant _MenuCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vendorModel.id != widget.vendorModel.id ||
        oldWidget.products != widget.products) {
      _rankedFuture =
          FireStoreUtils.getCarouselProducts(widget.vendorModel.id, widget.products);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool _hasVariants(ProductModel p) {
    final hasNewAttrs = p.productAttributes.isNotEmpty &&
        p.productAttributes.any((c) => c.options.any((o) => o.enabled));
    final hasLegacyVariants = p.itemAttributes != null &&
        (p.itemAttributes!.attributes?.isNotEmpty ?? false) &&
        (p.itemAttributes!.variants?.isNotEmpty ?? false);
    return hasNewAttrs || hasLegacyVariants;
  }

  double? _startingPrice(ProductModel p) {
    final List<double> prices = [];
    for (final cfg in p.productAttributes) {
      for (final o in cfg.options) {
        if (o.enabled && o.effectivePrice > 0) prices.add(o.effectivePrice);
      }
    }
    final variants = p.itemAttributes?.variants;
    if (variants != null) {
      for (final v in variants) {
        final vp = double.tryParse(v.variant_price ?? '');
        if (vp != null && vp > 0) prices.add(vp);
      }
    }
    if (prices.isEmpty) return null;
    return prices.reduce((a, b) => a < b ? a : b);
  }

  String _priceLabel(ProductModel p) {
    if (_hasVariants(p)) {
      final starting = _startingPrice(p);
      if (starting != null) {
        return '${'Starting'.tr()} ${amountShow(amount: starting.toStringAsFixed(2))}';
      }
    }
    final disPrice = double.tryParse(p.disPrice ?? '0') ?? 0;
    final price = double.tryParse(p.price) ?? 0;
    if (disPrice > 0 && disPrice < price) {
      return amountShow(amount: p.disPrice!);
    }
    return amountShow(amount: p.price);
  }

  Widget _menuTile(ProductModel p) {
    return Stack(
      fit: StackFit.expand,
      children: [
        NetworkImageWidget(
          imageUrl: p.photo.isNotEmpty && p.photo != 'null' ? p.photo : '',
          fit: BoxFit.cover,
          height: widget.height,
          width: double.infinity,
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 18, 10, 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.65)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontFamily: AppThemeData.semiBold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _priceLabel(p),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontFamily: AppThemeData.medium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _fallbackToRestaurantPhoto() {
    return _RestaurantCardImage(
      vendorModel: widget.vendorModel,
      height: widget.height,
      borderRadius: widget.borderRadius,
      showDots: widget.showDots,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.products.isEmpty) return _fallbackToRestaurantPhoto();
    return FutureBuilder<List<ProductModel>>(
      future: _rankedFuture,
      builder: (context, snapshot) {
        final items = snapshot.data ?? widget.products.take(5).toList();
        if (items.isEmpty) return _fallbackToRestaurantPhoto();
        return Stack(
          children: [
            ClipRRect(
              borderRadius: widget.borderRadius,
              child: items.length == 1
                  ? _menuTile(items[0])
                  : PageView.builder(
                      controller: _pageController,
                      itemCount: items.length,
                      onPageChanged: (i) => setState(() => _currentPage = i),
                      itemBuilder: (_, i) => _menuTile(items[i]),
                    ),
            ),
            if (widget.showDots && items.length > 1)
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(items.length, (i) {
                    final active = i == _currentPage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active ? Colors.white : Colors.white.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AllStore
// ─────────────────────────────────────────────────────────────────────────────
class AllStore extends StatelessWidget {
  final List<VendorModel> allStoreList;
  final Map<String, String> offerBadges;
  final bool isDelivery;
  final Map<String, List<ProductModel>> productsByVendor;

  const AllStore(
      {super.key,
      required this.allStoreList,
      this.offerBadges = const {},
      this.isDelivery = false,
      this.productsByVendor = const {}});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      scrollDirection: Axis.vertical,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: allStoreList.length >= 10 ? 10 : allStoreList.length,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: (BuildContext context, int index) {
        final VendorModel vendorModel = allStoreList[index];
        final bool open = vendorModel.isAcceptingOrders;
        final String rating = calculateReview(
          reviewCount: vendorModel.reviewsCount.toString(),
          reviewSum: vendorModel.reviewsSum.toString(),
        );
        final int listLen = allStoreList.length >= 10 ? 10 : allStoreList.length;

        return Padding(
          key: ValueKey(vendorModel.id),
          padding: EdgeInsets.only(bottom: index == listLen - 1 ? 90 : 24),
          child: InkWell(
            onTap: () =>
                push(context, NewVendorProductsScreen(vendorModel: vendorModel)),
            borderRadius: BorderRadius.circular(24),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFC),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.09),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Cinematic image area ─────────────────────────────────
                  Stack(
                    children: [
                      SizedBox(
                        height: Responsive.height(24, context),
                        width: double.infinity,
                        child: isDelivery
                            ? _MenuCarousel(
                                vendorModel: vendorModel,
                                products: productsByVendor[vendorModel.id] ?? [],
                                height: Responsive.height(24, context),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(24),
                                  topRight: Radius.circular(24),
                                ),
                              )
                            : _RestaurantCardImage(
                                vendorModel: vendorModel,
                                height: Responsive.height(24, context),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(24),
                                  topRight: Radius.circular(24),
                                ),
                              ),
                      ),
                      // Cinematic bottom gradient
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 70,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(24),
                            topRight: Radius.circular(24),
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.40),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (!open)
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFEEEE),
                              borderRadius: BorderRadius.circular(50),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFDC2626)
                                      .withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFDC2626),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  'Closed',
                                  style: TextStyle(
                                    color: Color(0xFFDC2626),
                                    fontSize: 11,
                                    height: 1.2,
                                    fontFamily: AppThemeData.semiBold,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (offerBadges[vendorModel.id] != null)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppThemeData.primary500,
                              borderRadius: BorderRadius.circular(50),
                              boxShadow: [
                                BoxShadow(
                                  color: AppThemeData.primary500
                                      .withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.local_offer_rounded,
                                    color: Colors.white, size: 11),
                                const SizedBox(width: 4),
                                Text(
                                  offerBadges[vendorModel.id]!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    height: 1.2,
                                    fontFamily: AppThemeData.semiBold,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  // ── Info section ─────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (open)
                              Container(
                                width: 7,
                                height: 7,
                                margin: const EdgeInsets.only(right: 7),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF16A34A),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            Expanded(
                              child: Text(
                                vendorModel.title.toString(),
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontFamily: AppThemeData.bold,
                                  color: Color(0xFF111111),
                                  overflow: TextOverflow.ellipsis,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 28,
                          height: 3,
                          decoration: BoxDecoration(
                            color: AppThemeData.primary500,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F1F5),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on_rounded,
                                  color: Color(0xFF7C3AED), size: 16),
                              const SizedBox(width: 4),
                              RoadDistanceText(
                                vendorLat: vendorModel.latitude,
                                vendorLon: vendorModel.longitude,
                                showAwaySuffix: true,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontFamily: AppThemeData.semiBold,
                                  color: Color(0xFF7C3AED),
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: const Color(0xFF16A34A)
                                          .withValues(alpha: 0.35),
                                      width: 1),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star_rounded,
                                        color: Color(0xFF16A34A), size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      rating,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        height: 1.2,
                                        fontFamily: AppThemeData.semiBold,
                                        color: Color(0xFF15803D),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NewArrival
// ─────────────────────────────────────────────────────────────────────────────
class NewArrival extends StatelessWidget {
  final List<VendorModel> newArrivalRestaurantList;
  final bool isDelivery;
  final Map<String, List<ProductModel>> productsByVendor;

  const NewArrival(
      {super.key,
      required this.newArrivalRestaurantList,
      this.isDelivery = false,
      this.productsByVendor = const {}});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Responsive.height(26, context),
      child: ListView.builder(
        physics: const ClampingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 16),
        itemCount: newArrivalRestaurantList.length >= 10
            ? 10
            : newArrivalRestaurantList.length,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        itemBuilder: (BuildContext context, int index) {
          VendorModel vendorModel = newArrivalRestaurantList[index];
          final bool open = vendorModel.isAcceptingOrders;
          final String rating = calculateReview(
            reviewCount: vendorModel.reviewsCount.toString(),
            reviewSum: vendorModel.reviewsSum.toString(),
          );
          return Padding(
            key: ValueKey(vendorModel.id),
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              onTap: () {
                push(context,
                    NewVendorProductsScreen(vendorModel: vendorModel));
              },
              child: Container(
                width: 155,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0x14000000),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        SizedBox(
                          height: Responsive.height(14, context),
                          width: double.infinity,
                          child: isDelivery
                              ? _MenuCarousel(
                                  vendorModel: vendorModel,
                                  products: productsByVendor[vendorModel.id] ?? [],
                                  height: Responsive.height(14, context),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(16),
                                    topRight: Radius.circular(16),
                                  ),
                                  showDots: false,
                                )
                              : _RestaurantCardImage(
                                  vendorModel: vendorModel,
                                  height: Responsive.height(14, context),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(16),
                                    topRight: Radius.circular(16),
                                  ),
                                  showDots: false,
                                ),
                        ),
                        if (!open)
                          Positioned(
                            bottom: 7,
                            left: 7,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFEEEE),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFDC2626),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  const Text(
                                    'Closed',
                                    style: TextStyle(
                                      fontSize: 10,
                                      height: 1.2,
                                      fontFamily: AppThemeData.semiBold,
                                      color: Color(0xFFDC2626),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vendorModel.title.toString(),
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 14,
                              overflow: TextOverflow.ellipsis,
                              fontFamily: AppThemeData.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 5),
                            child: Divider(
                              height: 1,
                              thickness: 0.5,
                              color: Color(0xFFF0F0F0),
                            ),
                          ),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 11,
                                color: Color(0xFF888888),
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  vendorModel.location.toString(),
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    overflow: TextOverflow.ellipsis,
                                    fontFamily: AppThemeData.medium,
                                    color: Color(0xFF888888),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFF16A34A)
                                        .withValues(alpha: 0.35),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star_rounded,
                                        color: Color(0xFF16A34A), size: 11),
                                    const SizedBox(width: 3),
                                    Text(
                                      rating,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontFamily: AppThemeData.bold,
                                        color: Color(0xFF15803D),
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      '(${vendorModel.reviewsCount})',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontFamily: AppThemeData.medium,
                                        color: Color(0xFF166534),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F0FF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: RoadDistanceText(
                                  vendorLat: vendorModel.latitude,
                                  vendorLon: vendorModel.longitude,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontFamily: AppThemeData.semiBold,
                                    color: Color(0xFF7C3AED),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TopSellingView
// ─────────────────────────────────────────────────────────────────────────────
class TopSellingView extends StatelessWidget {
  final List<VendorModel> vendors;
  final List<ProductModel> lstNearByFood;

  const TopSellingView(
      {super.key, required this.lstNearByFood, required this.vendors});

  String _discountLabel(ProductModel p) {
    try {
      final double orig = double.parse(p.price);
      final double disc = double.parse(p.disPrice ?? '0');
      if (orig > disc && disc > 0) {
        return '${(((orig - disc) / orig) * 100).round()}% OFF';
      }
    } catch (_) {}
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final double _cardH = (MediaQuery.of(context).size.width * 0.56).clamp(180.0, 250.0);
    final double _imgH = (_cardH * 0.524).roundToDouble();
    final double _bodyH = _cardH - _imgH;
    return SizedBox(
      height: _cardH,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: lstNearByFood.length >= 15 ? 15 : lstNearByFood.length,
        addAutomaticKeepAlives: false,
        // false: the card's own Clip.antiAliasWithSaveLayer is the compositing
        // boundary; a second RepaintBoundary per item causes BackdropFilter
        // to blur across layer boundaries → blurred/ghosted text.
        addRepaintBoundaries: false,
        itemBuilder: (context, index) {
          VendorModel? popularNearFoodVendorModel;
          if (vendors.isNotEmpty) {
            for (int a = 0; a < vendors.length; a++) {
              if (vendors[a].id == lstNearByFood[index].vendorID) {
                popularNearFoodVendorModel = vendors[a];
              }
            }
          }
          final ProductModel productModel = lstNearByFood[index];

          String orderType = '';
          SharedPreferences.getInstance().then((prefs) {
            orderType = prefs.getString('foodType') ?? 'Delivery'.tr();
          });

          final bool _hHasRestrictions = productModel.deliveryOption ||
              productModel.takeaway || productModel.dineIn;
          final bool _hIsDineaway = orderType == 'Takeaway'.tr() ||
              orderType == 'Dineaway'.tr();

          final bool _hProductSupportsDineaway =
              productModel.dineIn || productModel.takeaway;
          String unavailabilityMessage = '';
          if (_hHasRestrictions) {
            if (_hIsDineaway && !_hProductSupportsDineaway) {
              unavailabilityMessage = 'Not available for DineAway';
            } else if (orderType == 'Delivery'.tr() &&
                !productModel.deliveryOption) {
              unavailabilityMessage = 'Not available for Delivery';
            }
          }

          bool showItem = true;
          if (_hHasRestrictions) {
            if (_hIsDineaway && !_hProductSupportsDineaway) {
              showItem = false;
            } else if (orderType == 'Delivery'.tr() &&
                !productModel.deliveryOption) {
              showItem = false;
            }
          }

          if (!showItem) return const SizedBox.shrink();
          if (popularNearFoodVendorModel == null) return const SizedBox.shrink();

          final bool hasDiscount = productModel.disPrice != '' &&
              productModel.disPrice != '0' &&
              productModel.disPrice != null;
          final String discountLabel = hasDiscount ? _discountLabel(productModel) : '';

          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              onTap: () async {
                VendorModel? vendorModel =
                    await FireStoreUtils.getVendor(productModel.vendorID);
                if (vendorModel != null) {
                  push(context, ProductDetailsScreen(
                    vendorModel: vendorModel,
                    productModel: productModel,
                  ));
                }
              },
              borderRadius: BorderRadius.circular(16),
              // antiAliasWithSaveLayer creates a proper compositing boundary so
              // the BackdropFilter badge cannot leak blur into the text below.
              child: Container(
                width: 148,
                height: _cardH,
                clipBehavior: Clip.antiAliasWithSaveLayer,
                decoration: BoxDecoration(
                  color: isDarkMode(context)
                      ? AppThemeData.grey900
                      : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Image + discount badge ───────────────────────────
                    SizedBox(
                      height: _imgH,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(16)),
                            child: NetworkImageWidget(
                              imageUrl: productModel.photo.toString(),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: _imgH,
                            ),
                          ),
                          if (discountLabel.isNotEmpty)
                            Positioned(
                              top: 8,
                              left: 8,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                clipBehavior: Clip.antiAliasWithSaveLayer,
                                child: BackdropFilter(
                                  filter: ui.ImageFilter.blur(
                                      sigmaX: 8, sigmaY: 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black
                                          .withValues(alpha: 0.52),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.18),
                                        width: 0.5,
                                      ),
                                    ),
                                    child: Text(
                                      discountLabel,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        height: 1.2,
                                        fontFamily: AppThemeData.bold,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // ── Body ─────────────────────────────────────────────
                    SizedBox(
                      height: _bodyH,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Top group: name + vendor (min-size so spaceBetween works)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  productModel.name.capitalizeString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.2,
                                    fontFamily: AppThemeData.bold,
                                    color: isDarkMode(context)
                                        ? AppThemeData.grey50
                                        : const Color(0xFF1A1A1A),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  popularNearFoodVendorModel.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    height: 1.2,
                                    fontFamily: AppThemeData.medium,
                                    color: Color(0xFF888888),
                                  ),
                                ),
                              ],
                            ),
                            // Bottom group: price row pinned to bottom
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    // Main price — never shrinks
                                    Text(
                                      amountShow(
                                        amount: productCommissionPrice(
                                          hasDiscount
                                              ? productModel.disPrice ?? '0'
                                              : productModel.price,
                                        ),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.2,
                                        fontFamily: AppThemeData.bold,
                                        color: AppThemeData.primary500,
                                      ),
                                    ),
                                    if (hasDiscount) ...[
                                      const SizedBox(width: 5),
                                      // Strikethrough — shrinks when space is tight
                                      Flexible(
                                        child: Text(
                                          amountShow(
                                              amount: productCommissionPrice(
                                                  productModel.price)),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            height: 1.2,
                                            fontFamily: AppThemeData.medium,
                                            color: Color(0xFFAAAAAA),
                                            decoration:
                                                TextDecoration.lineThrough,
                                            decorationColor: Color(0xFFAAAAAA),
                                            decorationThickness: 1.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (unavailabilityMessage.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 3, horizontal: 6),
                                    decoration: BoxDecoration(
                                      color: AppThemeData.danger300
                                          .withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: AppThemeData.danger300
                                            .withValues(alpha: 0.50),
                                      ),
                                    ),
                                    child: Text(
                                      unavailabilityMessage.tr(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: AppThemeData.danger300,
                                        fontFamily: AppThemeData.medium,
                                        fontSize: 9,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// RecommendForYouView
/// ─────────────────────────────────────────────────────────────────────────────
// class RecommendForYouView extends StatefulWidget {
//   final List<VendorModel> vendors;
//   final List<ProductModel> recommendedProducts;
//
//   const RecommendForYouView({
//     super.key,
//     required this.recommendedProducts,
//     required this.vendors,
//   });
//
//   @override
//   State<RecommendForYouView> createState() => _RecommendForYouViewState();
// }
//
// class _RecommendForYouViewState extends State<RecommendForYouView> {
//   late ScrollController _scrollController1;
//   late ScrollController _scrollController2;
//   bool _isScrolling1 = false;
//   bool _isScrolling2 = false;
//
//   @override
//   void initState() {
//     super.initState();
//     _scrollController1 = ScrollController();
//     _scrollController2 = ScrollController();
//     _scrollController1.addListener(_syncScroll1);
//     _scrollController2.addListener(_syncScroll2);
//   }
//
//   void _syncScroll1() {
//     if (!_isScrolling2 &&
//         _scrollController1.hasClients &&
//         _scrollController2.hasClients) {
//       _isScrolling1 = true;
//       if ((_scrollController1.offset - _scrollController2.offset).abs() >
//           1.0) {
//         _scrollController2.jumpTo(_scrollController1.offset);
//       }
//       _isScrolling1 = false;
//     }
//   }
//
//   void _syncScroll2() {
//     if (!_isScrolling1 &&
//         _scrollController1.hasClients &&
//         _scrollController2.hasClients) {
//       _isScrolling2 = true;
//       if ((_scrollController2.offset - _scrollController1.offset).abs() >
//           1.0) {
//         _scrollController1.jumpTo(_scrollController2.offset);
//       }
//       _isScrolling2 = false;
//     }
//   }
//
//   @override
//   void dispose() {
//     _scrollController1.removeListener(_syncScroll1);
//     _scrollController2.removeListener(_syncScroll2);
//     _scrollController1.dispose();
//     _scrollController2.dispose();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     if (widget.recommendedProducts.isEmpty) {
//       return const SizedBox();
//     }
//
//     List<ProductModel> row1Products = [];
//     List<ProductModel> row2Products = [];
//     for (int i = 0; i < widget.recommendedProducts.length; i++) {
//       if (i % 2 == 0) {
//         row1Products.add(widget.recommendedProducts[i]);
//       } else {
//         row2Products.add(widget.recommendedProducts[i]);
//       }
//     }
//
//     return SizedBox(
//       height: 320,
//       child: Column(
//         children: [
//           SizedBox(
//             height: 155,
//             child: ListView.builder(
//               controller: _scrollController1,
//               scrollDirection: Axis.horizontal,
//               padding: EdgeInsets.zero,
//               itemCount: row1Products.length,
//               addAutomaticKeepAlives: false,
//               addRepaintBoundaries: true,
//               itemExtent: 130,
//               itemBuilder: (context, index) {
//                 return _buildProductItem(row1Products[index]);
//               },
//             ),
//           ),
//           const SizedBox(height: 10),
//           SizedBox(
//             height: 155,
//             child: ListView.builder(
//               controller: _scrollController2,
//               scrollDirection: Axis.horizontal,
//               padding: EdgeInsets.zero,
//               itemCount: row2Products.length,
//               addAutomaticKeepAlives: false,
//               addRepaintBoundaries: true,
//               itemExtent: 130,
//               itemBuilder: (context, index) {
//                 return _buildProductItem(row2Products[index]);
//               },
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildProductItem(ProductModel productModel) {
//     VendorModel? vendorModel;
//     if (widget.vendors.isNotEmpty) {
//       for (int a = 0; a < widget.vendors.length; a++) {
//         if (widget.vendors[a].id == productModel.vendorID) {
//           vendorModel = widget.vendors[a];
//           break;
//         }
//       }
//     }
//
//     if (vendorModel == null) {
//       return Container();
//     }
//
//     double rating = 0.0;
//     if (vendorModel.reviewsCount > 0) {
//       rating = (vendorModel.reviewsSum / vendorModel.reviewsCount);
//     }
//
//     double discountAmount = 0.0;
//     bool hasDiscount = false;
//     if (productModel.disPrice != null &&
//         productModel.disPrice != "" &&
//         productModel.disPrice != "0") {
//       try {
//         double originalPrice = double.parse(productModel.price);
//         double discountedPrice =
//         double.parse(productModel.disPrice ?? "0");
//         if (originalPrice > discountedPrice) {
//           discountAmount = originalPrice - discountedPrice;
//           hasDiscount = true;
//         }
//       } catch (e) {}
//     }
//
//     return InkWell(
//       onTap: () {
//         push(context,
//             NewVendorProductsScreen(vendorModel: vendorModel!));
//       },
//       child: Padding(
//         padding: const EdgeInsets.symmetric(horizontal: 5),
//         child: SizedBox(
//           width: 130,
//           child: Container(
//             clipBehavior: Clip.antiAlias,
//             decoration: ShapeDecoration(
//               color: isDarkMode(context)
//                   ? AppThemeData.grey900
//                   : AppThemeData.grey50,
//               shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(10)),
//               shadows: [
//                 BoxShadow(
//                     color: Color(0x0A000000),
//                     blurRadius: 32,
//                     offset: Offset(0, 0),
//                     spreadRadius: 0)
//               ],
//             ),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Stack(
//                   children: [
//                     Container(
//                       width: double.infinity,
//                       height: 75,
//                       child: ClipRRect(
//                         borderRadius: BorderRadius.only(
//                           topLeft: Radius.circular(10),
//                           topRight: Radius.circular(10),
//                         ),
//                         child: NetworkImageWidget(
//                             imageUrl: productModel.photo.toString(),
//                             fit: BoxFit.cover),
//                       ),
//                     ),
//                     if (hasDiscount)
//                       Positioned(
//                         top: 5,
//                         left: 5,
//                         child: Container(
//                           padding: EdgeInsets.symmetric(
//                               horizontal: 5, vertical: 2),
//                           decoration: BoxDecoration(
//                             color: Colors.grey[800]?.withOpacity(0.9) ??
//                                 Colors.grey[800]!,
//                             borderRadius: BorderRadius.circular(3),
//                           ),
//                           child: Text(
//                             "FLAT ${amountShow(amount: discountAmount.toStringAsFixed(0))} OFF",
//                             style: TextStyle(
//                                 color: Colors.white,
//                                 fontSize: 8,
//                                 fontFamily: AppThemeData.medium),
//                           ),
//                         ),
//                       ),
//                   ],
//                 ),
//                 Padding(
//                   padding: const EdgeInsets.all(6),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     mainAxisSize: MainAxisSize.min,
//                     children: [
//                       if (rating > 0)
//                         Container(
//                           padding: EdgeInsets.symmetric(
//                               horizontal: 4, vertical: 2),
//                           decoration: BoxDecoration(
//                               color: Colors.green,
//                               borderRadius: BorderRadius.circular(3)),
//                           child: Row(
//                             mainAxisSize: MainAxisSize.min,
//                             children: [
//                               Icon(Icons.star,
//                                   color: Colors.white, size: 10),
//                               SizedBox(width: 2),
//                               Text(rating.toStringAsFixed(1),
//                                   style: TextStyle(
//                                       color: Colors.white,
//                                       fontSize: 10,
//                                       fontFamily: AppThemeData.medium)),
//                             ],
//                           ),
//                         ),
//                       if (rating > 0) SizedBox(height: 4),
//                       Text(
//                         productModel.name.capitalizeString(),
//                         textAlign: TextAlign.start,
//                         maxLines: 1,
//                         overflow: TextOverflow.ellipsis,
//                         style: TextStyle(
//                           fontSize: 13,
//                           color: isDarkMode(context)
//                               ? AppThemeData.grey50
//                               : AppThemeData.grey900,
//                           fontFamily: AppThemeData.regular,
//                         ),
//                       ),
//                       SizedBox(height: 3),
//                       productModel.disPrice == "" ||
//                           productModel.disPrice == "0"
//                           ? Text(
//                         amountShow(
//                             amount: productCommissionPrice(
//                                 productModel.price)),
//                         style: TextStyle(
//                             fontSize: 13,
//                             letterSpacing: 0.5,
//                             color: AppThemeData.primary500,
//                             fontFamily: AppThemeData.medium),
//                       )
//                           : Row(
//                         children: [
//                           Text(
//                             "${amountShow(amount: productCommissionPrice(productModel.disPrice ?? "0"))}",
//                             style: TextStyle(
//                                 fontSize: 13,
//                                 fontWeight: FontWeight.bold,
//                                 color: AppThemeData.primary500,
//                                 fontFamily: AppThemeData.medium),
//                           ),
//                           const SizedBox(width: 5),
//                           Text(
//                             amountShow(
//                                 amount: productCommissionPrice(
//                                     productModel.price)),
//                             style: const TextStyle(
//                                 fontWeight: FontWeight.bold,
//                                 color: Colors.grey,
//                                 decoration:
//                                 TextDecoration.lineThrough,
//                                 fontSize: 11),
//                           ),
//                         ],
//                       ),
//                     ],
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

/// By AK
class RecommendForYouView extends StatefulWidget {
  final List<VendorModel> vendors;
  final List<ProductModel> recommendedProducts;

  const RecommendForYouView({
    super.key,
    required this.recommendedProducts,
    required this.vendors,
  });

  @override
  State<RecommendForYouView> createState() =>
      _RecommendForYouViewState();
}

class _RecommendForYouViewState
    extends State<RecommendForYouView> {

  late ScrollController _scrollController1;
  late ScrollController _scrollController2;

  bool _isScrolling1 = false;
  bool _isScrolling2 = false;

  @override
  void initState() {
    super.initState();

    _scrollController1 = ScrollController();
    _scrollController2 = ScrollController();

    _scrollController1.addListener(_syncScroll1);
    _scrollController2.addListener(_syncScroll2);
  }

  void _syncScroll1() {
    if (!_isScrolling2 &&
        _scrollController1.hasClients &&
        _scrollController2.hasClients) {

      _isScrolling1 = true;

      if ((_scrollController1.offset -
          _scrollController2.offset)
          .abs() >
          1) {
        _scrollController2.jumpTo(
          _scrollController1.offset,
        );
      }

      _isScrolling1 = false;
    }
  }

  void _syncScroll2() {
    if (!_isScrolling1 &&
        _scrollController1.hasClients &&
        _scrollController2.hasClients) {

      _isScrolling2 = true;

      if ((_scrollController2.offset -
          _scrollController1.offset)
          .abs() >
          1) {
        _scrollController1.jumpTo(
          _scrollController2.offset,
        );
      }

      _isScrolling2 = false;
    }
  }

  @override
  void dispose() {
    _scrollController1.dispose();
    _scrollController2.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.recommendedProducts.isEmpty) return const SizedBox();

    final double _rowH = (MediaQuery.of(context).size.width * 0.37).clamp(120.0, 160.0);

    final List<ProductModel> row1 = [];
    final List<ProductModel> row2 = [];
    for (int i = 0; i < widget.recommendedProducts.length; i++) {
      if (i % 2 == 0) {
        row1.add(widget.recommendedProducts[i]);
      } else {
        row2.add(widget.recommendedProducts[i]);
      }
    }

    return SizedBox(
      height: _rowH * 2 + 10,
      child: Column(
        children: [
          SizedBox(
            height: _rowH,
            child: ListView.builder(
              controller: _scrollController1,
              scrollDirection: Axis.horizontal,
              itemCount: row1.length,
              addAutomaticKeepAlives: false,
              // false: card's own antiAliasWithSaveLayer is the compositing
              // boundary; a per-item RepaintBoundary causes BackdropFilter
              // to bleed blur into adjacent layers → blurred/ghosted text.
              addRepaintBoundaries: false,
              itemBuilder: (context, index) => _buildProductItem(row1[index]),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: _rowH,
            child: ListView.builder(
              controller: _scrollController2,
              scrollDirection: Axis.horizontal,
              itemCount: row2.length,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: false,
              itemBuilder: (context, index) => _buildProductItem(row2[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductItem(ProductModel productModel) {
    final double _rowH = (MediaQuery.of(context).size.width * 0.37).clamp(120.0, 160.0);
    final double _imgH = (_rowH * 0.607).roundToDouble();

    VendorModel? vendorModel;
    for (var vendor in widget.vendors) {
      if (vendor.id == productModel.vendorID) {
        vendorModel = vendor;
        break;
      }
    }
    if (vendorModel == null) return const SizedBox.shrink();

    double rating = 0;
    if (vendorModel.reviewsCount > 0) {
      rating = vendorModel.reviewsSum / vendorModel.reviewsCount;
    }

    int offerPercent = 0;
    if (productModel.disPrice != null &&
        productModel.disPrice != '' &&
        productModel.disPrice != '0') {
      try {
        final double original = double.parse(productModel.price);
        final double discount = double.parse(productModel.disPrice ?? '0');
        if (original > discount) {
          offerPercent = (((original - discount) / original) * 100).round();
        }
      } catch (e) {}
    }

    return InkWell(
      onTap: () {
        push(context, NewVendorProductsScreen(vendorModel: vendorModel!));
      },
      borderRadius: BorderRadius.circular(14),
      // antiAliasWithSaveLayer gives the card its own compositing layer so the
      // BackdropFilter badge cannot leak blur into the text section below.
      child: Container(
        width: 148,
        height: _rowH,
        clipBehavior: Clip.antiAliasWithSaveLayer,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: isDarkMode(context) ? AppThemeData.grey900 : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Image + badges ───────────────────────────────────────
            SizedBox(
              height: _imgH,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(14)),
                    child: NetworkImageWidget(
                      imageUrl: productModel.photo.toString(),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: _imgH,
                    ),
                  ),
                  if (offerPercent > 0)
                    Positioned(
                      top: 7,
                      left: 7,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        // antiAliasWithSaveLayer confines blur to badge region
                        clipBehavior: Clip.antiAliasWithSaveLayer,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppThemeData.accent500,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$offerPercent% OFF',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              height: 1.2,
                              fontFamily: AppThemeData.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 7,
                    bottom: 7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded,
                              color: Color(0xFFFBBC05), size: 11),
                          const SizedBox(width: 2),
                          Text(
                            rating.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Color(0xFF1A1A1A),
                              fontSize: 10,
                              height: 1.2,
                              fontFamily: AppThemeData.semiBold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Body — fixed 55 px (140 - 85), no flex ambiguity ─────
            SizedBox(
              height: 55,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Product name
                    Text(
                      productModel.name.capitalizeString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.2,
                        fontFamily: AppThemeData.bold,
                        color: isDarkMode(context)
                            ? AppThemeData.grey50
                            : const Color(0xFF1A1A1A),
                      ),
                    ),
                    // Price row — baseline-aligned, main price never shrinks
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          amountShow(
                            amount: productCommissionPrice(
                              offerPercent > 0
                                  ? productModel.disPrice ?? '0'
                                  : productModel.price,
                            ),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.2,
                            fontFamily: AppThemeData.bold,
                            color: offerPercent > 0
                                ? AppThemeData.accent500
                                : AppThemeData.primary500,
                          ),
                        ),
                        if (offerPercent > 0) ...[
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              amountShow(
                                  amount: productCommissionPrice(
                                      productModel.price)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFAAAAAA),
                                fontSize: 9,
                                height: 1.2,
                                fontFamily: AppThemeData.medium,
                                decoration: TextDecoration.lineThrough,
                                decorationColor: Color(0xFFAAAAAA),
                                decorationThickness: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ],
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

// ─────────────────────────────────────────────────────────────────────────────
// CategoryView

class CategoryView extends StatelessWidget {
  final List<VendorCategoryModel> vendorCategoryList;

  const CategoryView({
    super.key,
    required this.vendorCategoryList,
  });

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    return SizedBox(
      height: 112,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: vendorCategoryList.length,
        itemBuilder: (context, index) {
          final vendorCategoryModel = vendorCategoryList[index];
          return Padding(
            padding: const EdgeInsets.only(right: 20),
            child: GestureDetector(
              onTap: () => push(
                context,
                CategoryDetailsScreen(
                  category: vendorCategoryModel,
                  isDineIn: false,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: NetworkImageWidget(
                      imageUrl: vendorCategoryModel.photo.toString(),
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 76,
                    child: Text(
                      vendorCategoryModel.title.toString(),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: dark ? Colors.white : const Color(0xFF1A1A1A),
                        fontFamily: AppThemeData.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}




// ─────────────────────────────────────────────────────────────────────────────
// BannerView
// ─────────────────────────────────────────────────────────────────────────────
class BannerView extends StatefulWidget {
  final List<BannerModel> bannerList;

  const BannerView({super.key, required this.bannerList});

  @override
  State<BannerView> createState() => _BannerViewState();
}

class _BannerViewState extends State<BannerView> {
  late final PageController _pageController;
  int _currentPage = 0;
  Timer? _autoScrollTimer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.92);
    _startAutoScroll();
  }

  void _startAutoScroll() {
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || widget.bannerList.length <= 1) return;
      final int next = (_currentPage + 1) % widget.bannerList.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: (MediaQuery.of(context).size.width * 0.44).clamp(140.0, 210.0),
          child: PageView.builder(
            physics: const ClampingScrollPhysics(),
            controller: _pageController,
            scrollDirection: Axis.horizontal,
            itemCount: widget.bannerList.length,
            padEnds: false,
            pageSnapping: true,
            onPageChanged: (value) {
              setState(() {
                _currentPage = value;
              });
            },
            itemBuilder: (BuildContext context, int index) {
              final BannerModel bannerModel = widget.bannerList[index];
              return InkWell(
                onTap: () async {
                  if (bannerModel.redirect_type == "store") {
                    ShowToastDialog.showLoader("Please wait");
                    VendorModel? vendorModel =
                        await FireStoreUtils.getVendor(
                            bannerModel.redirect_id.toString());
                    ShowToastDialog.closeLoader();
                    push(context,
                        NewVendorProductsScreen(vendorModel: vendorModel!));
                  } else if (bannerModel.redirect_type == "product") {
                    ShowToastDialog.showLoader("Please wait");
                    ProductModel? productModel =
                        await FireStoreUtils.getProductById(
                            bannerModel.redirect_id.toString());
                    VendorModel? vendorModel =
                        await FireStoreUtils.getVendor(
                            productModel!.vendorID.toString());
                    ShowToastDialog.closeLoader();
                    push(context,
                        NewVendorProductsScreen(vendorModel: vendorModel!));
                  } else if (bannerModel.redirect_type == "external_link") {
                    final uri =
                        Uri.parse(bannerModel.redirect_id.toString());
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    } else {
                      ShowToastDialog.showToast("Could not launch");
                    }
                  }
                },
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: EdgeInsets.only(left: index == 0 ? 12 : 0, right: 12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.13),
                          blurRadius: 18,
                          offset: const Offset(0, 7),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          NetworkImageWidget(
                            imageUrl: bannerModel.photo.toString(),
                            fit: BoxFit.cover,
                          ),
                          // Subtle depth gradient
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: 65,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.28),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Animated pill-dot indicators
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.bannerList.length, (index) {
              final bool active = _currentPage == index;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOut,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: 6,
                width: active ? 22 : 6,
                decoration: BoxDecoration(
                  color: active
                      ? AppThemeData.primary500
                      : Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAB helpers — shared between list/map and QR buttons
// ─────────────────────────────────────────────────────────────────────────────

class _FabIconButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isActive;
  final bool isDark;
  final Widget child;

  const _FabIconButton({
    required this.onTap,
    required this.isActive,
    required this.isDark,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: 40,
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isActive ? AppThemeData.primary500 : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppThemeData.primary500.withValues(alpha: 0.32),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _FabDivider extends StatelessWidget {
  final bool isDark;
  const _FabDivider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}