import 'package:cached_network_image/cached_network_image.dart';
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
import 'package:emartconsumer/services/behavior/behavior_counters.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:emartconsumer/services/behavior/behavior_event_types.dart';
import 'package:emartconsumer/services/behavior/behavior_tracker.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/services/perf_diagnostic_file_service.dart';
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
import 'package:flutter_google_maps_webservices/places.dart' show Component;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_place_picker_mb/google_maps_place_picker.dart';
import 'package:location/location.dart' as loc;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'dart:async';

import 'dart:ui' as ui;

// ── TEMPORARY HOME-SCREEN PERF LOGGING ──────────────────────────────────────
// Instrumentation only, no behavior change. Wraps an awaited operation with
// start/end/elapsed logging. Remove once the startup bottleneck is found.
Future<T> _timedStep<T>(String label, Future<T> Function() op) async {
  final sw = Stopwatch()..start();
  debugPrint('[HOME-PERF] $label START at ${DateTime.now().toIso8601String()}');
  try {
    final result = await op();
    sw.stop();
    debugPrint('[HOME-PERF] $label END — elapsed ${sw.elapsedMilliseconds}ms');
    return result;
  } catch (e) {
    sw.stop();
    debugPrint('[HOME-PERF] $label FAILED after ${sw.elapsedMilliseconds}ms — $e');
    rethrow;
  }
}

// TEMPORARY image-load perf logging — same idea as _timedStep, but for
// network images, which don't have a single awaitable Future we can wrap
// (CachedNetworkImage manages its own request lifecycle internally). Keyed
// by "label|url" so a widget rebuild re-showing the same URL doesn't
// double-log a start with no matching end.
final Map<String, Stopwatch> _imageLoadStopwatches = {};

void _logImageLoadStart(String label, String url, {required String section}) {
  if (url.isEmpty) return;
  // Tag BEFORE anything else — this is what lets the network-layer log
  // (perf_diagnostic_file_service.dart) compute real queue-wait time and
  // show which Home-screen section this URL belongs to. Must happen even on
  // a widget rebuild (unlike the stopwatch below) since tagImageRequest()
  // itself is idempotent (putIfAbsent) and cheap.
  tagImageRequest(url, section: section, trigger: 'widget-build');
  final key = '$label|$url';
  if (_imageLoadStopwatches.containsKey(key)) return;
  _imageLoadStopwatches[key] = Stopwatch()..start();
  debugPrint('[HOME-PERF][IMG][$section] $label START — $url');
}

void _logImageLoadEnd(String label, String url, {String? error}) {
  if (url.isEmpty) return;
  final key = '$label|$url';
  final sw = _imageLoadStopwatches.remove(key);
  if (sw == null) return;
  sw.stop();
  final section = sectionLabelFor(url);
  if (error != null) {
    debugPrint(
        '[HOME-PERF][IMG][$section] $label FAILED after ${sw.elapsedMilliseconds}ms — $url — $error');
  } else {
    // This fires when imageBuilder receives a resolved ImageProvider, i.e.
    // decode is done — but the frame it's drawn into hasn't necessarily been
    // painted yet. Schedule a post-frame callback to see how much (if any)
    // extra time that takes.
    debugPrint(
        '[HOME-PERF][IMG][$section] $label DECODE-COMPLETE — elapsed ${sw.elapsedMilliseconds}ms — $url');
    final decodeElapsed = sw.elapsedMilliseconds;
    final paintSw = Stopwatch()..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint(
          '[HOME-PERF][IMG][$section] $label PAINTED — +${paintSw.elapsedMilliseconds}ms after decode, '
          'total ${decodeElapsed + paintSw.elapsedMilliseconds}ms — $url');
    });
  }
}

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
  // dismissed â€” see _startProductsFetchIfNeeded(). The whole-catalog query
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

  // Manual restaurant-feed sort chosen by the user â€” 'offer' | 'nearest' |
  // 'rating', or null for the default recommended order. Re-sorts the
  // already-loaded `vendors` list in place (no new Firestore fetch); ties
  // fall through to the same recommended priority order used by default.
  String? _manualSortMode;

  // Restaurant-card offer badge text, keyed by vendor id â€” computed once per
  // _sortRestaurants() pass (same normal/special offer evaluation used for
  // ranking, so the badge can never contradict why a restaurant is ranked
  // where it is). Never a merged normal+special number â€” just the single
  // bigger real offer's own amount, "Up to â‚¹X off", no minimum stated.
  Map<String, String> _offerBadgeByVendorId = {};

  // Global coupon-style ("normal") offers used by the feed-ranking algorithm
  // below. Includes vendor-specific and global (storeId null/empty) coupons â€”
  // same eligibility rule CartScreen uses at checkout. Refreshed once per
  // getData() call by _loadNormalOffersForRanking().
  List<OfferModel> _normalOffersForRanking = [];

  void _loadNormalOffersForRanking() {
    _timedStep('_loadNormalOffersForRanking -> getAllCoupons',
            () => fireStoreUtils.getAllCoupons())
        .then((value) {
      _normalOffersForRanking = value;
      _sortRestaurants();
      if (mounted) setState(() {});
    });
  }

  bool _isPercentageOfferType(String? type) =>
      type == 'Percentage' || type == 'Percent' || type == 'percentage';

  // Best "normal" (coupon-style) offer for [vendor] â€” OfferModel has no
  // section field, so these apply to both Delivery and Dineaway alike.
  // There's no live cart while browsing the feed, so each offer's own
  // applicableAmount is used as the comparison order amount for converting
  // a percentage offer into a monetary saving â€” this also means the
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
      // customer doesn't have â€” they're excluded from the cart's tap-to-
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
      // Rank by effective rate (discount Ã· minimum spend), not raw amount â€”
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
  // "Delivery" or "Takeaway" â€” matching Timeslot.orderType's convention
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
        // Same effective-rate ranking as _bestNormalOffer â€” see comment there.
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
  /// CLOSED status â€” i.e. OPEN+eligible, OPEN+non-eligible, CLOSED+eligible,
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
      // have different minimums) â€” just the single bigger real offer,
      // shown as its own genuine "Up to â‚¹X off" ceiling.
      final bool normalWins = normal.amount >= special.amount;
      final double featuredAmount = normalWins ? normal.amount : special.amount;
      final double featuredPercent = normalWins ? normal.percent : special.percent;

      if (featuredAmount > 0) {
        // Whichever framing looks more compelling: a small â‚¹ amount reads
        // better as a percentage ("Up to 20% off" > "Up to â‚¹18 off"), while
        // a large amount reads better as a flat figure ("Up to â‚¹250 off" >
        // "Up to 12% off") â€” only applies when the winning offer is
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
      // 1. OPEN before CLOSED â€” absolute priority, regardless of everything else.
      if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;

      // Manual user-selected sort (Offer / Nearest / Rating), if active â€”
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
    // Decoupled from _bannerReady: the restaurant list is the primary
    // content and shouldn't wait on the above-the-fold banner/categories/
    // stories row. CategoryView and the top banner both already render as
    // zero/reserved-height when their list is still empty (see build()), so
    // they simply pop in a moment later once getBanner() resolves — no
    // broken layout, no jump.
    if (isLoading && _firstVendorReceived && mounted) {
      setState(() => isLoading = false);
      if (!_skeletonHiddenLogged) {
        _skeletonHiddenLogged = true;
        // Skeleton hidden == first restaurant list rendered == Home
        // interactive, in one event: this app has no separate "list visible
        // but not yet interactive" state, the skeleton is swapped directly
        // for the live, scrollable list.
        debugPrint(
            '[HOME-PERF] MILESTONE: skeleton hidden / restaurant list rendered / Home interactive — '
            '${_homeInitStopwatch.elapsedMilliseconds}ms since initState '
            '(bannerReady=$_bannerReady, firstVendorReceived=$_firstVendorReceived)');
      }
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
  //
  // TEMPORARY diagnostic note: uses CachedNetworkImageProvider with
  // perfDiagnosticCacheManager instead of a plain NetworkImage specifically
  // so this path is visible to the network-layer instrumentation — a plain
  // precacheImage(NetworkImage(url)) uses a completely different HTTP path
  // that our FileService-based logging can't see at all, which was a real,
  // confirmed blind spot (see perf_diagnostic_file_service.dart's header).
  Future<void> _precacheBatch(List<String> urls, {required String section}) async {
    if (!mounted || urls.isEmpty) return;
    final futures = urls.where((u) => u.isNotEmpty).map((url) {
      tagImageRequest(url, section: section, trigger: 'precacheImage');
      debugPrint('[HOME-PERF][IMG][$section] precacheImage START — $url');
      final sw = Stopwatch()..start();
      return precacheImage(
        CachedNetworkImageProvider(url, cacheManager: perfDiagnosticCacheManager),
        context,
      ).then((_) {
        debugPrint(
            '[HOME-PERF][IMG][$section] precacheImage DONE — elapsed ${sw.elapsedMilliseconds}ms — $url');
      }).catchError((Object e) {
        debugPrint(
            '[HOME-PERF][IMG][$section] precacheImage FAILED after ${sw.elapsedMilliseconds}ms — $url — $e');
      });
    }).toList();
    if (futures.isEmpty) return;
    await Future.wait(futures).timeout(
      const Duration(seconds: 5),
      onTimeout: () => [],
    );
  }

  // Called on the first vendor batch: signals the skeleton to hide as soon as
  // data is ready. Deliberately does NOT precache the whole vendor list — an
  // earlier version blindly fetched the first 8 vendors' photos regardless of
  // scroll position (a root cause of the concurrent-image-request pileup
  // measured during the startup investigation). _RestaurantCardImage/
  // _MenuCarousel load their own image once the card is actually
  // scroll-visible (VisibilityDetector gating), and that's the only trigger
  // for every card except the first couple below.
  //
  // CONFIRMED ON-DEVICE (2026-07-15): with no eager precache at all, the
  // VisibilityDetector on the FIRST restaurant card (which is genuinely
  // on-screen without any scrolling — verified with the user holding the
  // screen still) still took ~26s to fire onVisibilityChanged, well after
  // Story/TopBanner had already loaded — a real responsiveness gap in the
  // package/framework's visibility polling under heavy concurrent image
  // decode load that wasn't pinned down further. Since these first cards are
  // confirmed always-visible content (same tier as Story/TopBanner per the
  // requested priority order), they get the same small-capped-precache
  // treatment as TopBanner instead of waiting on that signal.
  Future<void> _precacheVendorsAndShow() async {
    debugPrint(
        '[HOME-PERF] _precacheVendorsAndShow — ${_homeInitStopwatch.elapsedMilliseconds}ms since initState');
    if (!mounted) return;
    _firstVendorReceived = true;
    debugPrint(
        '[HOME-PERF] MILESTONE: _firstVendorReceived=true — ${_homeInitStopwatch.elapsedMilliseconds}ms since initState (bannerReady=$_bannerReady)');
    const int restaurantListPrecacheCount = 2; // confirmed always-visible cards only
    _precacheBatch(
      vendors
          .take(restaurantListPrecacheCount)
          .map((v) => v.photo.toString())
          .where((p) => p.isNotEmpty && p != 'null')
          .toList(),
      section: 'RestaurantList',
    );
    _tryHideSkeleton();
    // Now that the page is visible, it's safe to start the whole-catalog
    // product fetch without it competing for bandwidth with first paint.
    _startProductsFetchIfNeeded();
  }

  // Starts the (large, unscoped) product catalog fetch used for card menu
  // previews, and wires up processing of its result. Only fires once per
  // getData() cycle â€” see the reset in getData() â€” and only after the
  // skeleton has already been dismissed.
  void _startProductsFetchIfNeeded() {
    if (_productsFetchStarted) return;
    _productsFetchStarted = true;
    debugPrint(
        '[HOME-PERF] _startProductsFetchIfNeeded — fired after skeleton dismissal, '
        '${_homeInitStopwatch.elapsedMilliseconds}ms since initState (does not block interactivity)');
    final future = (selctedOrderTypeValue == "Takeaway".tr() ||
            selctedOrderTypeValue == "Dineaway".tr())
        ? _timedStep('_startProductsFetchIfNeeded -> getAllTakeAWayProducts',
            () => fireStoreUtils.getAllTakeAWayProducts())
        : _timedStep('_startProductsFetchIfNeeded -> getAllDelevryProducts',
            () => fireStoreUtils.getAllDelevryProducts());
    productsFuture = future;
    future.then(_handleProducts);
  }

  String? name = "";

  // Defaults to Dineaway, not Delivery: Delivery is currently gated behind
  // isDeliveryActiveNotifier and shows a "Coming Soon" block, so a fresh
  // Delivery default was the first thing every new/returning user saw.
  String? selctedOrderTypeValue = "Dineaway".tr();

  bool isLoading = true;
  // Skeleton is hidden only when both banner data AND the first vendor batch
  // have arrived. Setting either flag early (via stream or banner completion)
  // is safe â€” _tryHideSkeleton checks both before acting.
  bool _bannerReady = false;
  bool _firstVendorReceived = false;
  bool _precachingVendors = false;

  // TEMPORARY perf instrumentation state.
  final Stopwatch _homeInitStopwatch = Stopwatch();
  bool _firstStreamEventLogged = false;
  bool _skeletonHiddenLogged = false;

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
    _homeInitStopwatch.start();
    debugPrint(
        '[HOME-PERF] HomeScreen.initState START at ${DateTime.now().toIso8601String()}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint(
          '[HOME-PERF] MILESTONE: first frame rendered (skeleton) — ${_homeInitStopwatch.elapsedMilliseconds}ms since initState');
    });
    WidgetsBinding.instance.addObserver(this);
    print("AK DEBUG: HomeScreen initState");
    // The live listener itself lives in ContainerScreen (one listener for the
    // whole app); this screen just rebuilds when the shared notifiers change.
    isDeliveryActiveNotifier.addListener(_onDeliveryGateChanged);
    deliveryOffMessageNotifier.addListener(_onDeliveryGateChanged);
    getLocationData();
    getBanner();
    _loadStories();
    _loadViewedToday();
    // Recommendation Configuration (2026-07-22, moved here 2026-07-23) -
    // one read, once, fired from Home rather than app startup, so it never
    // competes with the onboarding/splash screen's own blocking Firestore
    // calls for the network channel. RecommendationConfig.current already
    // holds production-identical defaults synchronously, so nothing waits
    // on this - by the time a customer opens a restaurant page (always
    // after Home), this has had plenty of time to resolve in the
    // background. Safe to call more than once (e.g. Home revisited) -
    // FireStoreUtils.loadRecommendationConfig() only ever fetches once and
    // every later call just returns the same in-flight/completed future.
    // ignore: unawaited_futures
    FireStoreUtils.loadRecommendationConfig();
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
    final bannerStopwatch = Stopwatch()..start();
    debugPrint(
        '[HOME-PERF] getBanner START — ${_homeInitStopwatch.elapsedMilliseconds}ms since initState');
    // These three reads are independent of each other (categories, top
    // banner, story-enabled flag) — run them concurrently instead of
    // sequentially. Measured at ~2.2s sequential (roughly the sum of all
    // three); concurrently it should take about as long as the slowest one.
    await Future.wait([
      _timedStep('getBanner -> getCuisines', () => fireStoreUtils.getCuisines())
          .then((value) {
        vendorCategoryModel = value;
        // Shared globally so SearchScreen's Product Category search tier
        // can reuse this same fetch instead of querying again itself.
        allProductCategoriesList
          ..clear()
          ..addAll(value);
        // O(1) companion lookup (2026-07-21) - rebuilt in lockstep, same
        // source, so it's never stale relative to the list above.
        productCategoryById
          ..clear()
          ..addEntries(value.where((c) => (c.id ?? '').isNotEmpty).map((c) => MapEntry(c.id!, c)));
      }),
      _timedStep(
              'getBanner -> getHomeTopBanner', () => fireStoreUtils.getHomeTopBanner())
          .then((value) {
        setState(() {
          bannerTopHome = value;
          isHomeBannerLoading = false;
        });
      }),
      _timedStep(
              'getBanner -> story setting doc get',
              () => FireStoreUtils.firestore.collection(Setting).doc('story').get())
          .then((value) {
        setState(() {
          storyEnable = value.data()?['isEnabled'] ?? false;
        });
      }),
    ]);
    debugPrint(
        '[HOME-PERF] getBanner TOTAL (3 parallel calls above): ${bannerStopwatch.elapsedMilliseconds}ms');
    // Warm the image cache for top-banner images in the background — not
    // awaited, so slow images can no longer hold up the skeleton dismissal.
    // Each image still shows its own placeholder until it individually loads.
    //
    // Category icons are intentionally NOT precached here. Categories are a
    // lowest-priority, supporting section (not even shown in DineAway) and
    // CONFIRMED ON-DEVICE (2026-07-15) that any eager batch here — even a
    // capped one — still jumps ahead of Story/TopBanner/MiddleBanner/
    // NewArrival/RestaurantList in the shared image-download queue simply by
    // firing first. CategoryView (below) is a horizontal ListView.builder
    // with a small cacheExtent look-ahead, so it already requests only the
    // icons that are visible (+ ~1-2 items buffer) purely from being built —
    // exactly like New Arrivals/Restaurant List, with no precache needed.
    if (mounted) {
      _precacheBatch(
        bannerTopHome
            .where((b) => (b.photo ?? '').isNotEmpty)
            .map((b) => b.photo!)
            .toList(),
        section: 'TopBanner',
      );
    }
    // Categories + top banner + story flag are everything visible at first
    // paint â€” signal and try to dismiss skeleton without waiting on the
    // middle banner, which is below the fold.
    _bannerReady = true;
    debugPrint(
        '[HOME-PERF] MILESTONE: _bannerReady=true — ${_homeInitStopwatch.elapsedMilliseconds}ms since initState (firstVendorReceived=$_firstVendorReceived)');
    _tryHideSkeleton();

    // Middle banner renders after "New Arrivals" â€” load it independently so
    // it never delays the skeleton.
    _loadMiddleBanner();
  }

  void _loadMiddleBanner() {
    // No precache here: the middle banner renders below the fold (after
    // "New Arrivals"), so eagerly fetching it the moment the data resolves
    // would request images the user hasn't scrolled to yet. Its own
    // NetworkImageWidget loads normally once it's actually built/visible.
    _timedStep('_loadMiddleBanner -> getHomeMiddleBanner',
            () => fireStoreUtils.getHomeMiddleBanner())
        .then((value) {
      if (!mounted) return;
      setState(() {
        bannerMiddleHome = value;
        isHomeBannerMiddleLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    /// BY AK
    final isDelivery = selctedOrderTypeValue == "Delivery";
    ///

    return Scaffold(
      backgroundColor:
      isDarkMode(context) ? AppThemeData.surfaceDark : const Color(0xFFF1F2F7),
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
            // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
            // HEADER SECTION â€” CHANGED
            // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
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

                      // â”€â”€ Top Row: Hamburger | Greeting+Location | Cart â”€â”€
                      Row(
                        crossAxisAlignment:
                        CrossAxisAlignment.center,
                        children: [
                          // â”€â”€ Hamburger button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

                          // â”€â”€ Greeting + Location â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // "Hello, Rahul ðŸ‘‹" or "Login"
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

                                // ðŸ“ Address + chevron
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
                                                      // Hard filter: only
                                                      // Indian results are
                                                      // returned at all.
                                                      autocompleteComponents: [
                                                        Component(
                                                            Component.country,
                                                            'in'),
                                                      ],
                                                    ),
                                              ),
                                            );
                                          }
                                        } catch (e) {
                                          // GPS failed â€” do not set a
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

                          // â”€â”€ Cart icon in circle with badge â”€â”€â”€â”€
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

                      const SizedBox(height: 14),

                      // Search bar
                      InkWell(
                        onTap: () =>
                            push(context, const SearchScreen()),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          height: 54,
                          decoration: BoxDecoration(
                            color: isDarkMode(context)
                                ? AppThemeData.grey800
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDarkMode(context)
                                  ? AppThemeData.grey700
                                  : AppThemeData.primary500
                                      .withValues(alpha: 0.18),
                              width: 1.5,
                            ),
                            boxShadow: isDarkMode(context)
                                ? null
                                : [
                                    BoxShadow(
                                      color: AppThemeData.primary500
                                          .withValues(alpha: 0.07),
                                      blurRadius: 18,
                                      offset: const Offset(0, 4),
                                    ),
                                    BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.04),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 12),
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: isDarkMode(context)
                                      ? AppThemeData.grey700
                                      : const Color(0xFFEDE8FF),
                                  borderRadius:
                                      BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.search_rounded,
                                  color: AppThemeData.primary500,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Search dishes, restaurants, meals...'
                                      .tr(),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontFamily: AppThemeData.regular,
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
                                    : AppThemeData.primary500,
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
            // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
            // END HEADER SECTION
            // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

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
                            orderType: selctedOrderTypeValue ?? "Delivery".tr(),
                            vendors: vendors,
                            deliveryProductsByVendor: _deliveryProductsByVendor,
                            viewedIds: _viewedTodayIds,
                            onViewRecorded: (id) {
                              if (!mounted) return;
                              setState(() { _viewedTodayIds = {..._viewedTodayIds, id}; });
                              _saveViewedId(id);
                              _filterStories();
                            },
                          ),
                        ],
                      )
                          : const SizedBox(),
                    SizedBox(
                      height: storyList.isEmpty ? 0 : 8,
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
                    const SizedBox(height: 12),
                    bannerTopHome.isEmpty
                        ? const SizedBox()
                        : BannerView(bannerList: bannerTopHome, sectionLabel: 'TopBanner'),

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
                        : BannerView(bannerList: bannerMiddleHome, sectionLabel: 'MiddleBanner'),
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
                  // â”€â”€ List view toggle â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
                  // â”€â”€ Map view toggle â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
                  // â”€â”€ QR Scanner â€” slides in/out with AnimatedSize â”€â”€â”€â”€
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
                  // â”€â”€ Divider + delivery type selector â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  _FabDivider(isDark: isDarkMode(context)),
                  DeliveryTypeSelector(
                    selectedValue: selctedOrderTypeValue!,
                    isDarkMode: isDarkMode(context),
                    onValueChanged: (String newValue) async {
                      // Switching Delivery/Dineaway changes special-offer
                      // matching, eligibility thresholds, and ranking â€” show
                      // the skeleton immediately so stale results from the
                      // old section aren't visible while the new section's
                      // data loads, same pattern as _onLocationChanged().
                      final previousOrderType = currentOrderTypeGlobal;
                      setState(() {
                        selctedOrderTypeValue = newValue;
                        currentOrderTypeGlobal = newValue;
                        isLoading = true;
                        _firstVendorReceived = false;
                        _precachingVendors = false;
                        saveFoodTypeValue();
                      });
                      // High-level navigation only — this is the single
                      // user-driven mutation site for currentOrderTypeGlobal
                      // (not getFoodType()'s cold-start restore, which isn't
                      // a user action).
                      BehaviorTracker.track(kEvtNavOrderModeSwitched,
                          {'from': previousOrderType, 'to': newValue});
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

  // Manual sort chips for the "Restaurants Around You" feed â€” re-sorts the
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
    FireStoreUtils.clearStoryCache();
    _storiesLoaded = false;
    allStories.clear();
    storyList.clear();
    // Reload viewed IDs from SharedPreferences immediately so grey rings
    // persist across refresh without waiting for the Firestore round-trip.
    final sp = await SharedPreferences.getInstance();
    _viewedTodayIds = (sp.getStringList(_viewedTodayKey) ?? []).toSet();
    // Banners, coupons, categories, and stories: await so the indicator stays
    // visible while the most prominent content reloads. _bannerReady /
    // _firstVendorReceived don't need to be reset because isLoading stays
    // false, so _tryHideSkeleton is already a no-op.
    final bannerFuture = getBanner();
    final storiesFuture = _loadStories();
    await bannerFuture;
    await storiesFuture;
    // Restaurants arrive via stream â€” fire-and-forget; UI updates live.
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
    SharedPreferences sp = await _timedStep(
        'getFoodType -> SharedPreferences.getInstance', () => SharedPreferences.getInstance());
    if (mounted) {
      setState(() {
        String? savedFoodType = sp.getString("foodType");
        List<String> validOptions = ['Delivery'.tr(), 'Dineaway'.tr()];
        // No saved preference (new user, or nothing persisted yet) falls
        // back to Dineaway, not Delivery — see selctedOrderTypeValue's
        // field-level comment for why.
        final bool hadNoSavedPreference = savedFoodType == null ||
            savedFoodType == "" ||
            !validOptions.contains(savedFoodType);
        selctedOrderTypeValue =
            hadNoSavedPreference ? "Dineaway".tr() : savedFoodType;
        currentOrderTypeGlobal = selctedOrderTypeValue!;
        if (hadNoSavedPreference) {
          // Persist immediately — CartScreen/ProductDetailsScreen/
          // newVendorProductsScreen all read "foodType" from SharedPreferences
          // independently and default to "Delivery" when it's unset. Without
          // this, a fresh install shows Dineaway here (in-memory default) but
          // Cart falls back to Delivery the first time it's opened, since
          // saveFoodTypeValue() otherwise only runs when the user manually
          // taps the DeliveryTypeSelector.
          saveFoodTypeValue();
        }
      });
    }
  }

  List<StoryModel> storyList = [];
  List<StoryModel> allStories = [];
  bool _storiesLoaded = false;
  Set<String> _viewedTodayIds = {};

  static String get _viewedTodayKey =>
      'viewed_stories_${DateFormat('yyyy-MM-dd').format(DateTime.now())}';

  Future<void> _loadViewedToday() async {
    final sp = await _timedStep(
        '_loadViewedToday -> SharedPreferences.getInstance', () => SharedPreferences.getInstance());
    final ids = sp.getStringList(_viewedTodayKey) ?? [];
    if (mounted) {
      setState(() => _viewedTodayIds = ids.toSet());
      _filterStories();
    }
  }

  Future<void> _saveViewedId(String id) async {
    final sp = await SharedPreferences.getInstance();
    final current = sp.getStringList(_viewedTodayKey) ?? [];
    if (!current.contains(id)) {
      current.add(id);
      sp.setStringList(_viewedTodayKey, current);
    }
  }

  // Server-confirmed set of vendor IDs within the active section's
  // nearByRadius of the user's current location - null until the first
  // response lands, meaning "unknown, don't filter on distance yet".
  Set<String>? _nearbyVendorIds;
  String? _nearbyVendorIdsRequestKey;

  Map<String, List<ProductModel>> _productsByVendor = {};

  // All of each vendor's published, delivery-eligible products (unlike
  // _productsByVendor above, not capped to the first 20 app-wide) â€” the
  // pool AllStore/NewArrival's delivery menu carousels rank/select from.
  Map<String, List<ProductModel>> _deliveryProductsByVendor = {};

  void _filterStories() {
    print('\nðŸŽ¬ ===== STORY FILTERING START =====');
    print('ðŸ“Š Total stories to filter: ${allStories.length}');
    print('ðŸ“¦ Total vendors available: ${vendors.length}');
    print('ðŸ”„ Current order type: $selctedOrderTypeValue');

    storyList.clear();
    Set<String> addedStoryIDs = {};
    Set<String> candidateVendorIds = {};

    allStories.forEach((element1) {
      if (!element1.approved) {
        print(
            '\nðŸ“ Skipping story (not approved) for vendorID: ${element1.vendorID}');
        return;
      }

      if (element1.isExpired) {
        print(
            '\nðŸ“ Skipping story (expired) for vendorID: ${element1.vendorID}');
        return;
      }

      if (element1.isMediaFailed) {
        print(
            '\nðŸ“ Skipping story (Bunny transcode failed) for vendorID: ${element1.vendorID}');
        return;
      }

      bool vendorFound = false;
      vendors.forEach((element) {
        if (element1.vendorID == element.id) {
          vendorFound = true;

          // Dineaway/Takeaway shows stories regardless of vendor open status.
          if (selctedOrderTypeValue == "Delivery".tr() && !element.isAcceptingOrders) {
            print(
                '\nðŸ“ Skipping story (vendor offline) for vendor: ${element.title}');
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

          if (shouldAdd && element1.vendorID != null && element1.vendorID!.isNotEmpty) {
            candidateVendorIds.add(element1.vendorID!);

            // Radius filtering is server-confirmed (see _refreshNearbyVendorIds).
            // Until the first response lands, _nearbyVendorIds is null and
            // nothing is excluded on distance yet.
            if (_nearbyVendorIds != null &&
                !_nearbyVendorIds!.contains(element1.vendorID)) {
              shouldAdd = false;
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
            '\nâš ï¸ Story with vendorID ${element1.vendorID} has no matching vendor in the list!');
      }
    });

    // â”€â”€ Sort storyList â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final bool _sfIsDineaway = selctedOrderTypeValue == "Dineaway".tr() ||
        selctedOrderTypeValue == "Takeaway".tr();
    final String _sfOrderType = _sfIsDineaway ? "Takeaway" : "Delivery";
    final Map<String, VendorModel> _sfVendorById = {
      for (final v in vendors) v.id: v
    };
    final double _sfUserLat =
        MyAppState.selectedPosotion.location?.latitude ?? 0;
    final double _sfUserLng =
        MyAppState.selectedPosotion.location?.longitude ?? 0;
    final bool _sfHasLocation = MyAppState.selectedPosotion.location != null;

    storyList.sort((a, b) {
      final bool aViewed = _viewedTodayIds.contains(a.storyID);
      final bool bViewed = _viewedTodayIds.contains(b.storyID);

      // 1. Unviewed before viewed
      if (aViewed != bViewed) return aViewed ? 1 : -1;

      // 2. Lowest viewCount first
      if (a.viewCount != b.viewCount) return a.viewCount.compareTo(b.viewCount);

      final VendorModel? aV = _sfVendorById[a.vendorID];
      final VendorModel? bV = _sfVendorById[b.vendorID];

      if (aV != null && bV != null) {
        // 3. Highest effective discount (normal + special, section-aware)
        final aN = _bestNormalOffer(aV);
        final aS = _bestSpecialOffer(aV, _sfOrderType);
        final aDiscount = aN.amount + aS.amount;
        final bN = _bestNormalOffer(bV);
        final bS = _bestSpecialOffer(bV, _sfOrderType);
        final bDiscount = bN.amount + bS.amount;
        if (aDiscount != bDiscount) return bDiscount.compareTo(aDiscount);

        // 4. Better rating
        final double aRating =
            aV.reviewsCount > 0 ? aV.reviewsSum / aV.reviewsCount : 0.0;
        final double bRating =
            bV.reviewsCount > 0 ? bV.reviewsSum / bV.reviewsCount : 0.0;
        if (aRating != bRating) return bRating.compareTo(aRating);

        // 5. Nearest restaurant
        if (_sfHasLocation) {
          final double aDist = Geolocator.distanceBetween(
              _sfUserLat, _sfUserLng, aV.latitude, aV.longitude);
          final double bDist = Geolocator.distanceBetween(
              _sfUserLat, _sfUserLng, bV.latitude, bV.longitude);
          if (aDist != bDist) return aDist.compareTo(bDist);
        }
      }

      return 0;
    });
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    print('\nðŸ“‹ Final filtered story count: ${storyList.length}');
    print('ðŸŽ¬ ===== STORY FILTERING END =====\n');
    setState(() {});

    _refreshNearbyVendorIds(candidateVendorIds);
  }

  /// Loads stories + today's viewed-story ids. Fired at startup alongside
  /// getBanner() (priority: Top Banner, then Story) rather than nested inside
  /// the getAllStores() vendor-stream listener — that used to make Story wait
  /// on the restaurant list's first Firestore round trip before even starting
  /// its own fetch, which is why it visibly loaded last. Idempotent/safe to
  /// call more than once (e.g. pull-to-refresh) via the _storiesLoaded guard.
  Future<void> _loadStories() async {
    if (_storiesLoaded) return;
    final storiesStopwatch = Stopwatch()..start();
    debugPrint(
        '[HOME-PERF] Future.wait([getStory, _loadViewedTodayIds]) START — '
        '${_homeInitStopwatch.elapsedMilliseconds}ms since initState');
    await Future.wait([
      _timedStep('getData -> getStory', () => FireStoreUtils().getStory())
          .then((value) { allStories = value; }),
      _timedStep('getData -> _loadViewedTodayIds', () => _loadViewedTodayIds()),
    ]);
    debugPrint(
        '[HOME-PERF] Future.wait([getStory, _loadViewedTodayIds]) END — elapsed '
        '${storiesStopwatch.elapsedMilliseconds}ms');
    if (!mounted) return;
    _storiesLoaded = true;
    _filterStories();
  }

  /// Fetches today's story view records for the current user and populates
  /// [_viewedTodayIds] so the sort puts unviewed stories first.
  Future<void> _loadViewedTodayIds() async {
    // MyAppState.currentUser is populated from an async Firestore fetch
    // during login/session-restore, which can still be in flight right after
    // a fresh login following a data clear - Firebase Auth's own currentUser
    // is cached locally the instant sign-in completes, so fall back to it
    // rather than silently skipping this fetch (same race already fixed for
    // the write side in story_view.dart's _recordView()). Without this,
    // SharedPreferences' local "viewed today" cache is wiped by the data
    // clear AND this Firestore catch-up loses the race and never runs,
    // so already-watched stories permanently look unwatched until the next
    // calendar day.
    final userID = MyAppState.currentUser?.userID ??
        auth.FirebaseAuth.instance.currentUser?.uid;
    if (userID == null || userID.isEmpty) return;
    final now = DateTime.now();
    final dateKey =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('story_views')
          .where('userID', isEqualTo: userID)
          .where('dateKey', isEqualTo: dateKey)
          .get();
      final fromFirestore = snap.docs
          .map((d) => (d.data()['storyID'] as String?) ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      // Merge with whatever SharedPreferences already loaded — don't wipe local cache.
      _viewedTodayIds = {..._viewedTodayIds, ...fromFirestore};
    } catch (_) {
      // Non-fatal — sort degrades to viewCount/discount/rating/distance order.
    }
  }

  /// Asks the server which of [candidateVendorIds] are within radius of the
  /// user's current location, then re-runs _filterStories() once a fresh
  /// answer lands so the list tightens from "everything" to "in range"
  /// rather than blocking story display on this network round trip.
  /// De-duped per (location, candidate set) so it doesn't re-fire on every
  /// vendor-stream tick.
  Future<void> _refreshNearbyVendorIds(Set<String> candidateVendorIds) async {
    if (candidateVendorIds.isEmpty) return;
    if (MyAppState.selectedPosotion.location == null) return;

    final double lat = MyAppState.selectedPosotion.location!.latitude;
    final double lng = MyAppState.selectedPosotion.location!.longitude;

    final List<String> sortedIds = candidateVendorIds.toList()..sort();
    final String requestKey =
        '${lat.toStringAsFixed(3)}_${lng.toStringAsFixed(3)}_${sortedIds.join(',')}';
    if (requestKey == _nearbyVendorIdsRequestKey) return;
    _nearbyVendorIdsRequestKey = requestKey;

    // Background/stories-only — does not gate the skeleton or interactivity.
    final Set<String>? result = await _timedStep(
        '_refreshNearbyVendorIds -> getNearbyVendorIds (background, stories only)',
        () => FireStoreUtils().getNearbyVendorIds(
              lat: lat,
              lng: lng,
              vendorIds: sortedIds,
            ));

    // Treat an empty result the same as a null/failed response â€” a server that
    // returns zero matching vendors is almost certainly a data issue (vendors
    // without lat/lng, wrong radius) rather than a genuine "no nearby vendors".
    // Keeping _nearbyVendorIds null means stories stay visible rather than all
    // disappearing silently.
    if (result == null || result.isEmpty || !mounted) return;

    _nearbyVendorIds = result;
    _filterStories();
  }

  Future<void> getData() async {
    final getDataStopwatch = Stopwatch()..start();
    debugPrint(
        '[HOME-PERF] getData START — ${_homeInitStopwatch.elapsedMilliseconds}ms since initState');
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

    // getAllStores() is a Stream (geoflutterfire radius query), not a single
    // awaited call — the actual Firestore round trip happens after
    // .listen() below and is measured by the "first vendor stream event"
    // milestone log inside the listener, not by this function returning.
    final vendorStreamStopwatch = Stopwatch()..start();
    _vendorSub = lstAllRestaurant!.listen((event) {
      if (!_firstStreamEventLogged) {
        _firstStreamEventLogged = true;
        debugPrint(
            '[HOME-PERF] MILESTONE: first vendor stream event (getAllStores) — '
            '${vendorStreamStopwatch.elapsedMilliseconds}ms after subscribing, '
            '${_homeInitStopwatch.elapsedMilliseconds}ms since initState, '
            '${event.length} vendors');
      }
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
      // hasn't been, on the very first batch â€” see _startProductsFetchIfNeeded).
      productsFuture?.then(_handleProducts);

      popularRestaurantLst.addAll(event);
      newArrivalRestaurantList.addAll(event);

      newArrivalRestaurantList.sort((a, b) {
        // 1. Open before closed.
        final aOpen = a.isAcceptingOrders;
        final bOpen = b.isAcceptingOrders;
        if (aOpen != bOpen) return aOpen ? -1 : 1;
        // 2. Newest registered first within each group.
        final timeCmp = (b.createdAt ?? Timestamp.now())
            .toDate()
            .compareTo((a.createdAt ?? Timestamp.now()).toDate());
        if (timeCmp != 0) return timeCmp;
        // 3. Closest distance as tiebreaker.
        final loc = MyAppState.selectedPosotion.location;
        if (loc != null) {
          final aDist = Geolocator.distanceBetween(
              loc.latitude, loc.longitude, a.latitude, a.longitude);
          final bDist = Geolocator.distanceBetween(
              loc.latitude, loc.longitude, b.latitude, b.longitude);
          return aDist.compareTo(bDist);
        }
        return 0;
      });

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

      // Stories are now loaded independently (see _loadStories(), fired
      // alongside getBanner() at startup) rather than here — this just picks
      // up any change to the vendor list (e.g. viewed-today status) once
      // stories have already arrived.
      if (_storiesLoaded && allStories.isNotEmpty) {
        _filterStories();
      }
    });
    debugPrint(
        '[HOME-PERF] getData TOTAL (function return, NOT first vendor data): '
        '${getDataStopwatch.elapsedMilliseconds}ms — this only covers synchronous '
        'setup + opening the stream subscription; see the "first vendor stream event" '
        'milestone for when data actually arrives.');
  }

  // Processes the whole-catalog product fetch's result into the per-vendor
  // lookup maps the card menu carousels read from. Called once the fetch
  // resolves, and again on every later vendor-stream event so live updates
  // (new vendor, order-type toggle) stay reflected â€” uses `vendors` (the
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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// StoryView
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class StoryView extends StatefulWidget {
  final List<StoryModel> storyList;
  final String orderType;
  // Vendors are already loaded by HomeScreen's getData() â€” every story here
  // was already matched to one of these by _filterStories(), so looking
  // vendors up here instead of re-fetching by ID is always safe.
  final List<VendorModel> vendors;
  final Map<String, List<ProductModel>> deliveryProductsByVendor;
  final Set<String> viewedIds;
  // Called when a view is committed to Firestore so the ring colour updates
  // immediately without waiting for a full reload.
  final void Function(String storyID)? onViewRecorded;

  const StoryView({
    super.key,
    required this.storyList,
    required this.orderType,
    required this.vendors,
    required this.deliveryProductsByVendor,
    this.viewedIds = const {},
    this.onViewRecorded,
  });

  @override
  State<StoryView> createState() => _StoryViewState();
}

class _StoryViewState extends State<StoryView> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  // Stories published within the last 6 hours get a "NEW" badge.
  bool _isNewStory(StoryModel s) {
    if (s.createdAt == null) return false;
    return DateTime.now().difference(s.createdAt!.toDate()) <
        const Duration(hours: 6);
  }

  Widget _buildCircleItem(
      StoryModel story, int index, Map<String, VendorModel> vendorsById) {
    final vendor = vendorsById[story.vendorID?.toString() ?? ''];
    if (vendor == null) return const SizedBox(width: 66);

    final bool isViewed = widget.viewedIds.contains(story.storyID ?? '');
    final bool isVideo = story.hasVideo;
    final bool isNew = _isNewStory(story) && !isViewed;
    final bool dark = isDarkMode(context);

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MoreStories(
            storyList: widget.storyList,
            index: index,
            orderType: widget.orderType,
            onViewRecorded: widget.onViewRecorded,
          ),
        ),
      ),
      child: SizedBox(
        width: 66,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Outer gradient ring (unviewed) or grey ring (viewed).
                  // Padding creates the ring width; the inner white Container
                  // creates the visible gap between the ring and the logo.
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: isViewed
                          ? null
                          : const LinearGradient(
                              colors: [
                                Color(0xFFE23744),
                                Color(0xFFF06B2A),
                                Color(0xFFF5A623),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      color: isViewed ? const Color(0xFFC8C8CC) : null,
                    ),
                    padding: const EdgeInsets.all(2.5),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dark
                            ? AppThemeData.darkBgSecondary
                            : Colors.white,
                      ),
                      padding: const EdgeInsets.all(2.0),
                      child: ClipOval(
                        child: vendor.photo.toString().isNotEmpty
                            ? Builder(builder: (_) {
                                final url = vendor.photo.toString();
                                _logImageLoadStart('storyCircle', url, section: 'Story');
                                return NetworkImageWidget(
                                  imageUrl: url,
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.cover,
                                  cacheManager: perfDiagnosticCacheManager,
                                  onLoaded: () =>
                                      _logImageLoadEnd('storyCircle', url),
                                  onError: (e) => _logImageLoadEnd(
                                      'storyCircle', url, error: e.toString()),
                                );
                              })
                            : Container(
                                color: AppThemeData.primary500,
                                child: Center(
                                  child: Text(
                                    vendor.title.toString().isNotEmpty
                                        ? vendor.title
                                            .toString()[0]
                                            .toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontFamily: AppThemeData.bold,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),

                  // Video play badge â€” bottom-right corner of circle
                  if (isVideo)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppThemeData.primary500,
                          border: Border.all(
                            color: dark
                                ? AppThemeData.darkBgSecondary
                                : Colors.white,
                            width: 1.5,
                          ),
                        ),
                        child: const Center(
                          child: Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 11),
                        ),
                      ),
                    ),

                  // NEW badge â€” bottom-left, only for fresh unviewed stories
                  if (isNew)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppThemeData.primary500,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: dark
                                ? AppThemeData.darkBgSecondary
                                : Colors.white,
                            width: 1.5,
                          ),
                        ),
                        child: const Text(
                          'NEW',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 6.5,
                            fontFamily: AppThemeData.bold,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Text(
              vendor.title.toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontFamily: AppThemeData.semiBold,
                color: dark
                    ? AppThemeData.darkTextPrimary
                    : AppThemeData.neutral900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, VendorModel> vendorsById = {
      for (final v in widget.vendors) v.id: v
    };
    return SizedBox(
      height: 90,
      child: ListView.builder(
        controller: _scrollController,
        physics: const ClampingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: widget.storyList.length,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        itemExtent: 66,
        itemBuilder: (context, index) => _buildCircleItem(
          widget.storyList[index],
          index,
          vendorsById,
        ),
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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Auto-sliding restaurant image carousel
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _RestaurantCardImage extends StatefulWidget {
  final VendorModel vendorModel;
  final double height;
  final BorderRadius borderRadius;
  final bool showDots;
  // TEMPORARY diagnostic: which Home-screen section this instance belongs
  // to ("RestaurantList" for the main list, "NewArrival" for that carousel)
  // — this widget class is shared between both, so the label has to come
  // from the call site, not be inferred.
  final String sectionLabel;

  const _RestaurantCardImage({
    required this.vendorModel,
    required this.height,
    required this.borderRadius,
    this.showDots = true,
    required this.sectionLabel,
  });

  @override
  State<_RestaurantCardImage> createState() => _RestaurantCardImageState();
}

class _RestaurantCardImageState extends State<_RestaurantCardImage> {
  late PageController _pageController;
  Timer? _timer;
  int _currentPage = 0;
  // Progressive/viewport-based loading: this card's parent list (AllStore)
  // uses shrinkWrap, which forces Flutter to build every card up front
  // regardless of scroll position — without this gate, every card's image
  // fires its network request immediately, which is what caused the
  // 10-concurrent-request pileup measured during the startup investigation.
  // Latches true the first time the card is even 1px visible and never goes
  // back to false, so a card is never reloaded/flickered by scrolling away
  // and back.
  bool _isVisible = false;
  final Key _visibilityKey = UniqueKey();
  // Auto-slide must not advance to the next photo while the current one is
  // still loading — on a slow connection that stacks a fresh, expensive
  // request on top of one already in flight every 3 seconds, compounding
  // the exact contention problem this whole investigation started from.
  // "Settled" means loaded OR errored (an error still counts, so a
  // permanently-failing image doesn't stall the carousel forever) — only
  // genuinely still-in-flight pages block the advance.
  final Set<int> _settledPages = {};

  List<String> get _images {
    // photos[0] = logo (same as photo field), photos[1..n] = card gallery images.
    // Skip index 0 so only the actual card images appear in the carousel.
    // Entries may be a legacy URL string or a {original, cover} map â€” always
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
    // Auto-slide timer is started once the card is actually visible (see
    // _onBecomeVisible) — starting it here would fire animateToPage() before
    // this card's PageView has ever been built (it's still behind the
    // shimmer placeholder), which throws since the controller isn't
    // attached to any scroll position yet.
  }

  void _startAutoSlideIfNeeded() {
    final imgs = _images;
    if (imgs.length > 1 && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!mounted) return;
        // Skip this tick (don't advance) while the current photo is still
        // loading — the next tick will re-check once it settles.
        if (!_settledPages.contains(_currentPage)) return;
        // Wrapping last -> first: a plain PageView isn't circular, so
        // animateToPage(0) from the last page scrolls backward through
        // every intermediate photo instead of cutting straight to the
        // first. jumpToPage snaps instantly for just this one wrap-around
        // step; every other advance still uses the normal smooth animation.
        final wrapping = _currentPage >= imgs.length - 1;
        final next = wrapping ? 0 : _currentPage + 1;
        // Also skip if the UPCOMING photo itself hasn't decoded yet —
        // advancing to it would show a shimmer/white flash instead of the
        // actual image. It's proactively precached when the current page
        // settles (see onLoaded below), so this normally only matters right
        // after the very first photo loads.
        if (!_settledPages.contains(next)) return;
        if (wrapping) {
          _pageController.jumpToPage(next);
        } else {
          _pageController.animateToPage(
            next,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  void _onBecomeVisible(VisibilityInfo info) {
    if (info.visibleFraction > 0 && !_isVisible && mounted) {
      setState(() => _isVisible = true);
      _startAutoSlideIfNeeded();
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
    if (!_isVisible) {
      return VisibilityDetector(
        key: _visibilityKey,
        onVisibilityChanged: _onBecomeVisible,
        child: ClipRRect(
          borderRadius: widget.borderRadius,
          child: _StoryShimmer(
            width: double.infinity,
            height: widget.height,
            borderRadius: 0,
          ),
        ),
      );
    }
    if (imgs.length == 1) {
      _logImageLoadStart('vendorCard', imgs[0], section: widget.sectionLabel);
    }
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
                  cacheManager: perfDiagnosticCacheManager,
                  onLoaded: () => _logImageLoadEnd('vendorCard', imgs[0]),
                  onError: (e) =>
                      _logImageLoadEnd('vendorCard', imgs[0], error: e.toString()),
                )
              : PageView.builder(
                  controller: _pageController,
                  itemCount: imgs.length,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemBuilder: (context, i) {
                    _logImageLoadStart('vendorCard', imgs[i], section: widget.sectionLabel);
                    void onSettled() {
                      _settledPages.add(i);
                      final next = (i + 1) % imgs.length;
                      if (!_settledPages.contains(next)) {
                        precacheCarouselImage(context, imgs[next]);
                      }
                    }

                    return NetworkImageWidget(
                      imageUrl: imgs[i],
                      fit: BoxFit.cover,
                      height: widget.height,
                      width: double.infinity,
                      cacheManager: perfDiagnosticCacheManager,
                      onLoaded: () {
                        onSettled();
                        _logImageLoadEnd('vendorCard', imgs[i]);
                      },
                      onError: (e) {
                        onSettled();
                        _logImageLoadEnd('vendorCard', imgs[i], error: e.toString());
                      },
                    );
                  },
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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Delivery-mode menu carousel â€” replaces the restaurant photo with up to 5 of
// the vendor's own menu items (image, name, price), ranked by rolling 90-day
// (3-month) sales with a sales â†’ best-discount â†’ lowest-price fallback chain.
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _MenuCarousel extends StatefulWidget {
  final VendorModel vendorModel;
  final double height;
  final BorderRadius borderRadius;
  final bool showDots;
  // TEMPORARY diagnostic: see _RestaurantCardImage.sectionLabel.
  final String sectionLabel;

  const _MenuCarousel({
    required this.vendorModel,
    required this.height,
    required this.borderRadius,
    this.showDots = true,
    required this.sectionLabel,
  });

  @override
  State<_MenuCarousel> createState() => _MenuCarouselState();
}

class _MenuCarouselState extends State<_MenuCarousel> {
  late PageController _pageController;
  int _currentPage = 0;
  // Same progressive/viewport-based loading gate as _RestaurantCardImage —
  // see that class's field comment for why.
  bool _isVisible = false;
  final Key _visibilityKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _priceLabelFromMap(String price, String? disPrice) {
    final double? dis = double.tryParse(disPrice ?? '0');
    final double? orig = double.tryParse(price);
    if (dis != null && dis > 0 && orig != null && dis < orig) {
      return amountShow(amount: disPrice!);
    }
    return amountShow(amount: price);
  }

  Widget _menuTileFromMap(Map<String, dynamic> item) {
    final String photo = item['photo'] as String? ?? '';
    final String name = item['name'] as String? ?? '';
    final String price = item['price'] as String? ?? '';
    final String? disPrice = item['disPrice'] as String?;
    return Stack(
      fit: StackFit.expand,
      children: [
        NetworkImageWidget(
          imageUrl: photo.isNotEmpty && photo != 'null' ? photo : '',
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
                  name,
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
                  _priceLabelFromMap(price, disPrice),
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
      sectionLabel: widget.sectionLabel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.vendorModel.topProducts;
    if (items == null || items.isEmpty) return _fallbackToRestaurantPhoto();
    if (!_isVisible) {
      return VisibilityDetector(
        key: _visibilityKey,
        onVisibilityChanged: (info) {
          if (info.visibleFraction > 0 && !_isVisible && mounted) {
            setState(() => _isVisible = true);
          }
        },
        child: ClipRRect(
          borderRadius: widget.borderRadius,
          child: _StoryShimmer(
            width: double.infinity,
            height: widget.height,
            borderRadius: 0,
          ),
        ),
      );
    }
    return Stack(
      children: [
        ClipRRect(
          borderRadius: widget.borderRadius,
          child: items.length == 1
              ? _menuTileFromMap(items[0])
              : PageView.builder(
                  controller: _pageController,
                  itemCount: items.length,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemBuilder: (_, i) => _menuTileFromMap(items[i]),
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
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// AllStore
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
        final bool dark = isDarkMode(context);

        return Padding(
          key: ValueKey(vendorModel.id),
          padding: EdgeInsets.only(bottom: index == listLen - 1 ? 90 : 24),
          child: InkWell(
            onTap: () {
              BehaviorTracker.setNextEntrySource('Home');
              push(context, NewVendorProductsScreen(vendorModel: vendorModel));
            },
            borderRadius: BorderRadius.circular(24),
            child: Container(
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.30 : 0.11),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // â”€â”€ Cinematic image area â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  Stack(
                    children: [
                      SizedBox(
                        height: Responsive.height(24, context),
                        width: double.infinity,
                        child: isDelivery
                            ? _MenuCarousel(
                                vendorModel: vendorModel,
                                height: Responsive.height(24, context),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(24),
                                  topRight: Radius.circular(24),
                                ),
                                sectionLabel: 'RestaurantList',
                              )
                            : _RestaurantCardImage(
                                vendorModel: vendorModel,
                                height: Responsive.height(24, context),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(24),
                                  topRight: Radius.circular(24),
                                ),
                                sectionLabel: 'RestaurantList',
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
                  // â”€â”€ Info section â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
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
                                style: TextStyle(
                                  fontSize: 18,
                                  fontFamily: AppThemeData.bold,
                                  color: dark ? Colors.white : const Color(0xFF111111),
                                  overflow: TextOverflow.ellipsis,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: dark
                                ? Colors.white.withValues(alpha: 0.08)
                                : const Color(0xFFEDE8FF),
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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// NewArrival
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
                BehaviorTracker.setNextEntrySource('Home');
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
                      color: const Color(0x1A000000),
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
                                  height: Responsive.height(14, context),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(16),
                                    topRight: Radius.circular(16),
                                  ),
                                  showDots: false,
                                  sectionLabel: 'NewArrival',
                                )
                              : _RestaurantCardImage(
                                  vendorModel: vendorModel,
                                  height: Responsive.height(14, context),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(16),
                                    topRight: Radius.circular(16),
                                  ),
                                  showDots: false,
                                  sectionLabel: 'NewArrival',
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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// TopSellingView
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
        // to blur across layer boundaries â†’ blurred/ghosted text.
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
                    // â”€â”€ Image + discount badge â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
                    // â”€â”€ Body â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
                                    // Main price â€” never shrinks
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
                                      // Strikethrough â€” shrinks when space is tight
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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
/// RecommendForYouView
/// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
              // to bleed blur into adjacent layers â†’ blurred/ghosted text.
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
        BehaviorTracker.setNextEntrySource('Recommendation');
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
            // â”€â”€ Image + badges â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
            // â”€â”€ Body â€” fixed 55 px (140 - 85), no flex ambiguity â”€â”€â”€â”€â”€
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
                    // Price row â€” baseline-aligned, main price never shrinks
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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
        // Each item is ~92px wide (72 icon + 20 padding); ~180px caps the
        // build-ahead (and therefore image-request-ahead) window to roughly
        // 2 items past the visible edge instead of ListView's default ~250px
        // (~2.7 items) — categories are the lowest-priority section, so this
        // buffer is kept deliberately tight.
        cacheExtent: 180,
        itemBuilder: (context, index) {
          final vendorCategoryModel = vendorCategoryList[index];
          final categoryUrl = vendorCategoryModel.photo.toString();
          _logImageLoadStart('categoryIcon', categoryUrl, section: 'Category');
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
                      imageUrl: categoryUrl,
                      fit: BoxFit.contain,
                      // TEMPORARY diagnostic: shares the same instrumented
                      // cache manager as Story/Banner/NewArrival/
                      // RestaurantList so network-layer logs can verify
                      // Category requests never queue ahead of them.
                      cacheManager: perfDiagnosticCacheManager,
                      onLoaded: () => _logImageLoadEnd('categoryIcon', categoryUrl),
                      onError: (e) => _logImageLoadEnd('categoryIcon', categoryUrl, error: e.toString()),
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




// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// BannerView
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class BannerView extends StatefulWidget {
  final List<BannerModel> bannerList;
  // TEMPORARY diagnostic: this widget is used for both the top banner and
  // the middle banner — the label has to come from the call site.
  final String sectionLabel;

  const BannerView({super.key, required this.bannerList, required this.sectionLabel});

  @override
  State<BannerView> createState() => _BannerViewState();
}

class _BannerViewState extends State<BannerView> {
  late final PageController _pageController;
  int _currentPage = 0;
  Timer? _autoScrollTimer;
  // Same fix as _RestaurantCardImage's carousel — don't advance to the next
  // banner while the current one is still loading. "Settled" = loaded OR
  // errored, so a permanently-failing banner doesn't stall this forever.
  final Set<int> _settledPages = {};

  // Load-order fix (2026-07-20): viewportFraction 0.92 + padEnds:false means
  // the NEXT banner is always partially peeking on screen from the very
  // first frame, so PageView.builder's itemBuilder fires for BOTH the
  // current page and that peeking neighbor immediately - two concurrent
  // network requests with no ordering between them. Whichever response
  // happened to come back first would paint first, which is exactly what
  // looked like "banner 2 loading before banner 1". Only page 0 starts
  // unlocked; every other index's image is deliberately held behind a
  // shimmer for a short delay so the current page's request always gets a
  // head start - unless the customer swipes there first, in which case it
  // unlocks immediately (see onPageChanged below), so a fast swipe never
  // waits out the delay.
  final Set<int> _unlockedIndices = {0};

  // Banner Analytics (Phase 2, 2026-07-24, collection-only) - fired once
  // per bannerId the first time it's actually unlocked/rendered for this
  // widget instance (not on every rebuild), guarded by this set. Keyed by
  // bannerId, not index, so a rebuild that reorders bannerList can't
  // double-fire for the same banner under a new index.
  final Set<String> _impressedBannerIds = {};

  void _scheduleUnlock(int index) {
    if (_unlockedIndices.contains(index)) return;
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _unlockedIndices.add(index));
    });
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.92);
    _startAutoScroll();
  }

  void _precacheNextBanner(BuildContext context, int index) {
    if (widget.bannerList.length <= 1) return;
    final next = (index + 1) % widget.bannerList.length;
    if (_settledPages.contains(next)) return;
    precacheCarouselImage(context, widget.bannerList[next].photo.toString());
  }

  void _startAutoScroll() {
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || widget.bannerList.length <= 1) return;
      if (!_settledPages.contains(_currentPage)) return;
      // See the identical comment in the restaurant-card carousel above —
      // jumpToPage avoids scrolling backward through every banner on wrap.
      final wrapping = _currentPage >= widget.bannerList.length - 1;
      final int next = wrapping ? 0 : _currentPage + 1;
      // Also skip if the upcoming banner hasn't decoded yet — see the
      // identical comment in the restaurant-card carousel above.
      if (!_settledPages.contains(next)) return;
      if (wrapping) {
        _pageController.jumpToPage(next);
      } else {
        _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 550),
          curve: Curves.easeInOut,
        );
      }
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
                // A fast swipe shouldn't wait out _scheduleUnlock's delay -
                // whatever page the customer actually lands on unlocks
                // immediately, exactly like it would have before this fix.
                _unlockedIndices.add(value);
              });
            },
            itemBuilder: (BuildContext context, int index) {
              final BannerModel bannerModel = widget.bannerList[index];
              final bannerUrl = bannerModel.photo.toString();
              if (!_unlockedIndices.contains(index)) {
                _scheduleUnlock(index);
                return Padding(
                  padding: const EdgeInsets.only(left: 12, right: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: _StoryShimmer(
                      width: double.infinity,
                      height: (MediaQuery.of(context).size.width * 0.44)
                          .clamp(140.0, 210.0),
                      borderRadius: 0,
                    ),
                  ),
                );
              }
              _logImageLoadStart('banner', bannerUrl, section: widget.sectionLabel);
              // Banner impression (Phase 2, 2026-07-24, collection-only) -
              // fired once per bannerId per widget instance, the first time
              // it's actually unlocked/rendered (not on every rebuild of an
              // already-shown page).
              final String _bannerId = (bannerModel.id ?? '').toString();
              if (_bannerId.isNotEmpty && _impressedBannerIds.add(_bannerId)) {
                BehaviorTracker.track(kEvtBannerImpression, {
                  'bannerId': _bannerId,
                  'position': (bannerModel.position ?? '').toString(),
                  'slot': widget.sectionLabel,
                });
              }
              return InkWell(
                onTap: () async {
                  // Banner click (Phase 2, 2026-07-24, collection-only) -
                  // fired for EVERY redirect type, including external_link,
                  // before any of the existing redirect branching below (so
                  // a failed/aborted redirect still counts as a click).
                  // localClickCount is this DEVICE's own running total for
                  // (banner, device) via BehaviorCounters - ==1 means a
                  // genuinely new clicker from this doc's perspective, see
                  // BehaviorTracker._addBannerAnalyticsWrites for how it's
                  // used to derive uniqueClickCount with zero Firestore reads.
                  if (_bannerId.isNotEmpty) {
                    final localClickCount =
                        await BehaviorCounters.increment('banner_click', _bannerId);
                    BehaviorTracker.track(kEvtBannerClicked, {
                      'bannerId': _bannerId,
                      'position': (bannerModel.position ?? '').toString(),
                      'slot': widget.sectionLabel,
                      'redirectType': (bannerModel.redirect_type ?? '').toString(),
                      'localClickCount': localClickCount,
                    });
                    // Order attribution only makes sense for redirects that
                    // can actually lead to an in-app order - an
                    // external_link click leaves the app entirely, so it's
                    // deliberately excluded from setNextEntrySource/
                    // setNextBannerClick below (no restaurant session or
                    // order will ever follow it inside this app).
                    if (bannerModel.redirect_type == "store" ||
                        bannerModel.redirect_type == "product") {
                      BehaviorTracker.setNextEntrySource('Banner');
                      BehaviorTracker.setNextBannerClick(_bannerId);
                    }
                  }
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
                  padding: const EdgeInsets.only(left: 12, right: 8),
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
                            imageUrl: bannerUrl,
                            fit: BoxFit.cover,
                            cacheManager: perfDiagnosticCacheManager,
                            onLoaded: () {
                              _settledPages.add(index);
                              _precacheNextBanner(context, index);
                              _logImageLoadEnd('banner', bannerUrl);
                            },
                            onError: (e) {
                              _settledPages.add(index);
                              _precacheNextBanner(context, index);
                              _logImageLoadEnd('banner', bannerUrl, error: e.toString());
                            },
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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// FAB helpers â€” shared between list/map and QR buttons
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
