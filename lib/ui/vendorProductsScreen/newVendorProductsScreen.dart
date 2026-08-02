import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/FavouriteItemModel.dart';
import 'package:emartconsumer/model/FavouriteModel.dart';
import 'package:emartconsumer/model/NutritionInfo.dart';
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/model/VendorCategoryModel.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/model/WorkingHoursModel.dart';
import 'package:emartconsumer/model/offer_model.dart';
import 'package:emartconsumer/model/variant_info.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/behavior/behavior_counters.dart';
import 'package:emartconsumer/services/behavior/behavior_event_types.dart';
import 'package:emartconsumer/services/behavior/behavior_tracker.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/recommendation/recommendation_engine.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/theme/responsive.dart';
import 'package:emartconsumer/ui/review_list_screen/review_list_screen.dart';
import 'package:emartconsumer/utils/network_image_widget.dart';
import 'package:emartconsumer/widget/coming_soon_view.dart';
import 'package:emartconsumer/widget/shimmer_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:provider/provider.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/services/perf_diagnostic_file_service.dart';
import 'package:collection/collection.dart';
import 'package:emartconsumer/ui/cartScreen/CartScreen.dart';
import 'package:emartconsumer/ui/container/ContainerScreen.dart';
import 'package:emartconsumer/ui/discovery/WhatShouldITryScreen.dart';
import 'package:emartconsumer/services/app_dialog.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/ui/vendorProductsScreen/vendor_products_skeleton.dart';
import 'package:emartconsumer/ui/vendorProductsScreen/vendor_location_screen.dart';
import 'package:emartconsumer/widget/product_options_dialog.dart';
import 'package:emartconsumer/widget/recommendation_confidence_badge.dart';

class NewVendorProductsScreen extends StatefulWidget {
  final VendorModel vendorModel;

  const NewVendorProductsScreen({Key? key, required this.vendorModel})
      : super(key: key);

  @override
  State<NewVendorProductsScreen> createState() =>
      _NewVendorProductsScreenState();
}

// One rung of the "maximum rupee saving" ladder banner: a single minimum
// order amount and the real rupee saving a customer actually gets there —
// coupon and/or special discount already combined, conflict-resolved, and
// 70%-capped using the exact same math CartScreen uses at checkout (see
// _recomputeOfferLadder). offerCode is null when the saving comes purely
// from the automatic special discount (no coupon to redeem).
class _OfferLadderRung {
  final double thresholdAmount;
  final double savingAmount;
  final String? offerCode;
  const _OfferLadderRung({
    required this.thresholdAmount,
    required this.savingAmount,
    this.offerCode,
  });
}

// One of today's active special-discount time slots, pre-filtered by
// day/time-window/order-type — only the amount check is left to do per
// candidate threshold (see _bestSpecialValueAt).
class _SpecialSlotCandidate {
  final double minAmount;
  final double rawDiscount;
  final bool isPercent;
  const _SpecialSlotCandidate({
    required this.minAmount,
    required this.rawDiscount,
    required this.isPercent,
  });
}

class _NewVendorProductsScreenState extends State<NewVendorProductsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final FireStoreUtils fireStoreUtils = FireStoreUtils();
  late CartDatabase cartDatabase;
  bool _cartReady = false;
  List<CartProduct> cartProducts = [];
  StreamSubscription<List<CartProduct>>? _cartSubscription;

  bool isLoading = true;

  List<_OfferLadderRung> _offerLadderRungs = [];
  final PageController _offerLadderPageController = PageController();
  // ValueNotifier instead of a plain field + setState() — this page's
  // ticks every 2s and a bare setState() here would rebuild the entire
  // ~5000-line screen State just to move a page-view dot indicator.
  final ValueNotifier<int> _offerLadderCurrentPageNotifier =
      ValueNotifier<int>(0);
  int get _offerLadderCurrentPage => _offerLadderCurrentPageNotifier.value;
  set _offerLadderCurrentPage(int v) => _offerLadderCurrentPageNotifier.value = v;
  Timer? _offerLadderTimer;
  // Fires once at the next moment today's special-discount schedule actually
  // changes (a slot starting, a slot ending, or midnight rolling over to
  // tomorrow's day-of-week config) so the ladder never keeps showing a rung
  // past its real valid window just because the customer left the page open.
  Timer? _offerLadderBoundaryTimer;

  // Interest-duration signal: a single bounded Timer per screen visit,
  // fired once after kDwellThresholdSeconds, cancelled in dispose() if the
  // customer leaves early — never a repeating/continuous timer.
  Timer? _dwellTimer;

  // ── Restaurant Engagement session (Phase 2, 2026-07-24, collection-only)
  // ─────────────────────────────────────────────────────────────────────
  // Screen-local counters are the single source of truth for this visit's
  // totals - kEvtRestaurantSessionEnded (fired once, in dispose()) just
  // carries them to Firestore. See BehaviorTracker.startRestaurantSession's
  // own doc comment for the entry-source/search-context handshake.
  String _restaurantSessionId = '';
  String _sessionEntrySource = 'Direct';
  String _sessionSearchKeyword = '';
  String _sessionSearchType = '';
  DateTime? _sessionStartedAt;
  int _sessionProductViewCount = 0;
  int _sessionAddToCartCount = 0;
  final Set<String> _sessionCategoriesBrowsed = {};
  bool _sessionEndFired = false; // guards against a double dispose() firing

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    getFoodType();
    statusCheck();
    animateSlider();
    _dishSearchFocusNode.addListener(() {
      if (_dishSearchFocusNode.hasFocus) _enterDishSearch();
    });
    _pageScrollController.addListener(() {
      if (!_searchModeActive || !_pageScrollController.hasClients) return;
      final pos = _pageScrollController.position;
      if (pos.pixels >= pos.maxScrollExtent - 400 &&
          _visibleDishCount < productList.length) {
        setState(() => _visibleDishCount = _visibleDishCount + _dishPageSize);
      }
    });
    _pageScrollController.addListener(_updateCategoryExpansionWindow);

    _sessionStartedAt = DateTime.now();
    final session = BehaviorTracker.startRestaurantSession(widget.vendorModel.id);
    _restaurantSessionId = session.sessionId;
    _sessionEntrySource = session.entrySource;
    _sessionSearchKeyword = session.searchKeyword;
    _sessionSearchType = session.searchType;

    // ignore: unawaited_futures
    _trackRestaurantOpened();
    _dwellTimer = Timer(const Duration(seconds: kDwellThresholdSeconds), () {
      BehaviorTracker.track(
          kEvtRestaurantInterest, {'vendorId': widget.vendorModel.id});
    });
  }

  Future<void> _trackRestaurantOpened() async {
    final visitCount =
        await BehaviorCounters.increment('restaurant_visit', widget.vendorModel.id);
    BehaviorTracker.track(kEvtRestaurantOpened, {
      'vendorId': widget.vendorModel.id,
      'cuisineIds': widget.vendorModel.cuisineIds,
      'visitCount': visitCount,
    });
  }

  /// Fires the Restaurant Engagement session-summary event with this
  /// visit's final totals - called once, from dispose(). orderPlaced/
  /// orderCompleted are NOT included here (both default false server-side
  /// and are flipped true by separate, later merge-writes - see
  /// BehaviorTracker._addRestaurantEngagementWrites and
  /// PurchaseCompletionListener) since neither is knowable yet at the
  /// moment a customer merely navigates away from the menu.
  void _trackRestaurantSessionEnded() {
    if (_sessionEndFired || _restaurantSessionId.isEmpty) return;
    _sessionEndFired = true;
    final startedAt = _sessionStartedAt ?? DateTime.now();
    final durationSeconds = DateTime.now().difference(startedAt).inSeconds;
    BehaviorTracker.track(kEvtRestaurantSessionEnded, {
      'vendorId': widget.vendorModel.id,
      'sessionId': _restaurantSessionId,
      'entrySource': _sessionEntrySource,
      'searchKeyword': _sessionSearchKeyword,
      'searchType': _sessionSearchType,
      'startedAt': startedAt.toIso8601String(),
      'menuDurationSeconds': durationSeconds,
      'productViewCount': _sessionProductViewCount,
      'categoriesBrowsedCount': _sessionCategoriesBrowsed.length,
      'addToCartCount': _sessionAddToCartCount,
    });
  }

  // Auto-advances the single-slot offer banner through every ladder rung, one
  // at a time — mirrors animateSlider()'s vendor-photo-carousel pattern above.
  void _animateOfferLadder() {
    _offerLadderTimer?.cancel();
    if (_offerLadderRungs.length > 1) {
      _offerLadderTimer =
          Timer.periodic(const Duration(seconds: 2), (Timer timer) {
        if (_offerLadderCurrentPage < _offerLadderRungs.length - 1) {
          _offerLadderCurrentPage++;
        } else {
          _offerLadderCurrentPage = 0;
        }
        if (_offerLadderPageController.hasClients) {
          _offerLadderPageController.animateToPage(
            _offerLadderCurrentPage,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeIn,
          );
        }
      });
    }
  }

  // A time-slot-based special discount (e.g. a 6-8pm happy hour) can start or
  // expire purely because the clock moved while the app was backgrounded, with
  // no data change to react to — so the ladder must be recomputed on resume,
  // not just when offerList/specialDiscount data changes.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recomputeOfferLadder();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final db = Provider.of<CartDatabase>(context, listen: false);
    // Safely capture the previous instance without touching the late field if not ready
    final prev = _cartReady ? cartDatabase : null;
    // Always initialize — eliminates any window where the late field is unset
    cartDatabase = db;
    _cartReady = true;
    if (_cartSubscription == null || prev != db) {
      _cartSubscription?.cancel();
      _cartSubscription = cartDatabase.watchProducts.listen((products) {
        if (mounted) setState(() => cartProducts = products);
      });
    }
  }

  // Precaches a list of network image URLs concurrently. Individual failures
  // are swallowed; a 5-second hard timeout ensures the skeleton never blocks
  // indefinitely on slow or unavailable images.
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

  // Refresh cart data — kept for explicit call sites; stream handles most cases
  Future<void> _refreshCartData() async {
    if (!_cartReady) return;
    try {
      final products = await cartDatabase.allCartProducts;
      if (mounted) setState(() => cartProducts = products);
    } catch (e) {
      debugPrint('Error refreshing cart data: $e');
    }
  }

  // Manual pull-to-refresh rate limiting — at most once per minute per
  // vendor, independent of the 10-minute automatic cache TTL in
  // FireStoreUtils._productsCacheTtl.
  DateTime? _lastManualRefreshAt;
  static const Duration _manualRefreshCooldown = Duration(minutes: 1);

  bool _isManualRefreshing = false;

  Future<void> _onManualRefresh() async {
    final now = DateTime.now();
    final last = _lastManualRefreshAt;
    if (last != null) {
      final elapsed = now.difference(last);
      if (elapsed < _manualRefreshCooldown) {
        final remainingSeconds = (_manualRefreshCooldown - elapsed).inSeconds;
        ShowToastDialog.showToast(
          remainingSeconds <= 3
              ? "You refreshed recently. Please wait a moment.".tr()
              : "Refresh available in $remainingSeconds seconds.".tr(),
        );
        return;
      }
    }
    _lastManualRefreshAt = now;
    if (mounted) setState(() => _isManualRefreshing = true);
    FireStoreUtils.clearVendorProductsCache(widget.vendorModel.id);
    FireStoreUtils.clearAllCouponsCache();
    FireStoreUtils.clearRollingSalesCache(widget.vendorModel.id);
    final currentUid = FireStoreUtils.getCurrentUid();
    if (currentUid.isNotEmpty) {
      FireStoreUtils.clearBehaviorSummaryCache(currentUid);
    }
    await getFoodType();
    if (mounted) setState(() => _isManualRefreshing = false);
  }

  String? foodType;

  List a = [];
  List<ProductModel> allProductList = [];
  List<ProductModel> productList = [];
  List<ProductModel> _rawDineAwayProducts = [];
  String _dineAwaySubMode = 'Dining'; // 'Takeaway' or 'Dining' - Dining is the default (2026-07-26)

  // Id of the product whose "pairs well with" panel is currently expanded
  // inline below its card, right after it was added to cart.
  String? _pairsWellWithProductId;

  // True when _pairsWellWithProductId was set from a top carousel (today,
  // only Recommended For You) rather than the main menu list (2026-07-26).
  // The main list's own per-item loop only renders the panel when this is
  // false; a dedicated render point right below the carousels only renders
  // it when true - so a carousel-triggered add doesn't rely on the user
  // scrolling down to wherever that product happens to sit in the main
  // list, while a main-list-triggered add keeps its existing inline spot.
  bool _pairsWellWithFromCarousel = false;

  // Stable session order for the pairs-well-with panel (2026-07-20, explicit
  // product request). Without this, adding a suggested item makes it
  // disappear from the panel the instant the card rebuilds - _resolvedPairsWellWith
  // (unchanged, still correctly excludes cart items from fresh candidate
  // ranking) would no longer return it, and a NEW backfilled suggestion
  // takes its place. That reads as "it got removed/failed", not "it got
  // added", even though the add itself succeeded. Fix is purely
  // presentational: once an id has been shown in the CURRENT panel session,
  // it stays visible for the rest of that session (its card naturally
  // switches to the same quantity stepper _buildRecoProductCard already
  // shows for any in-cart product - no card-level change needed), while
  // _resolvedPairsWellWithDisplay below still lets a genuinely new
  // recommendation backfill the slot that opened up - so the total shown
  // grows by exactly 1 per newly-added distinct item, never on a repeat
  // tap of one already showing (that just increments its own stepper).
  // Reset to [] every time the panel opens for a (possibly new) product -
  // see _showPairsWellWith.
  List<String> _pairsWellWithDisplayOrder = [];

  // Phase 2 recommendation engine (2026-07-17) - loaded once per restaurant
  // page visit right after allProductList populates, then reused by every
  // new section, the reordered menu, and the pairs-well-with panel. Null
  // until the async load completes (or if it fails) - every reader must
  // treat that as "no signal yet", not an error.
  RestaurantRecommendationContext? _recoContext;

  // Green recommendation-confidence bar (2026-07-18) - computed once
  // alongside _recoContext, for every product on the menu (not just the
  // curated top-5 sections), so every card widget does a cheap map lookup
  // by product id instead of recomputing per card.
  Map<String, ProductRecommendationConfidence> _confidenceScores = {};

  // Order-count badge (2026-07-20) - shown ALONGSIDE the confidence badge
  // above, not replacing it (explicit product decision). See
  // RecommendationEngine.orderCounts' doc comment for exactly what this
  // represents (real 30-day order count per product, restaurant-wide).
  Map<String, int> _orderCounts = {};

  // Hidden from the UI for now (2026-07-20, explicit follow-up request) -
  // _orderCounts above is still loaded and kept up to date so the data
  // (and the "N orders" row below) is ready to switch back on later; only
  // the rendering is suppressed.
  static const bool _showOrderCountBadge = false;

  // Restaurant Must Try / Most Loved Here hidden from this screen
  // (2026-07-21, explicit request) - this per-restaurant menu screen keeps
  // only Recommended For You / Explore the Menu (mutually exclusive, see
  // the render site's own comment) followed straight by the menu list; the
  // other two carousels have their own screen elsewhere in the Customer
  // App. Getters/RecommendationEngine calls are untouched - only these two
  // sections' rendering here is suppressed, same reversible pattern as
  // _showOrderCountBadge above.
  static const bool _showRestaurantMustTry = false;
  static const bool _showMostLovedHere = false;

  Future<void> _loadRecoContext() async {
    try {
      final ctx = await FireStoreUtils.loadRecommendationContext(
          widget.vendorModel, allProductList);
      final confidence = RecommendationEngine.recommendationConfidenceScores(ctx);
      final orderCounts = RecommendationEngine.orderCounts(ctx);
      if (mounted) {
        setState(() {
          _recoContext = ctx;
          _confidenceScores = confidence;
          _orderCounts = orderCounts;
        });
      }
    } catch (_) {
      // Non-critical - sections relying on this simply stay hidden.
    }
  }

  // Dynamic multi-source blend (2026-07-17 rewrite) - the ONLY section that
  // uses the full cross-source merge (RecommendationEngine.recommendForYou);
  // every other automatic section reads one named source's own ranking
  // instead, so they keep their distinct identity. Diversity/dedup/cold-
  // start handling all live inside recommendForYou now. Also hidden
  // entirely on small menus (2026-07-18) - hasEnoughProductsForSections.
  List<ProductModel> get _recommendedForYouProducts {
    final ctx = _recoContext;
    if (ctx == null ||
        !RecommendationEngine.hasEnoughProductsForSections(ctx) ||
        RecommendationEngine.shouldShowExploreMenuFallback(ctx)) {
      // Below the restaurant-confidence floor (but menu big enough for a
      // section), Explore the Menu (below) replaces this - not shown
      // alongside it, even if _sourcePreference/_sourceSimilar would
      // otherwise have something real to say.
      return const [];
    }
    return RecommendationEngine.recommendForYou(
        ctx, limit: RecommendationEngine.sectionLimitFor(ctx));
  }

  // "Explore the Menu" (2026-07-18) - NOT a recommendation, see
  // RecommendationEngine.exploreMenuSelection's doc comment. Fills the gap
  // between "menu big enough for a section" and "restaurant has enough
  // sales history for a real signal", so this screen never shows a run of
  // empty section-shaped gaps for a growing restaurant.
  List<ProductModel> get _exploreMenuProducts {
    final ctx = _recoContext;
    if (ctx == null || !RecommendationEngine.shouldShowExploreMenuFallback(ctx)) {
      return const [];
    }
    return RecommendationEngine.exploreMenuSelection(
        ctx, limit: RecommendationEngine.sectionLimitFor(ctx));
  }

  // Restaurant Must Try (renamed from "Restaurant Specialities", fully
  // redesigned 2026-07-17) - fully automatic, NOT vendor-configured. Ranks
  // by the 'mustTry' source's own score alone (rolling 30-day sales +
  // recent-trend boost - see RecommendationEngine._sourceMustTry).
  // Deliberately does NOT use per-product ratings anywhere - see
  // recommendation_engine.dart's file header for why ProductModel.
  // reviewsCount/reviewsSum can never be trusted as a per-product signal.
  List<ProductModel> get _restaurantMustTryProducts {
    final ctx = _recoContext;
    if (ctx == null || !RecommendationEngine.hasEnoughProductsForSections(ctx)) {
      return const [];
    }
    // No separate check needed here - _sourceMustTry already returns []
    // below RecommendationEngine.minimumRestaurantConfidenceOrders.
    return RecommendationEngine.topBySource(ctx, 'mustTry',
        n: RecommendationEngine.defaultSectionLimit);
  }

  // Delegates to RecommendationEngine.mostLovedHere (2026-07-19 -
  // consolidated from a locally-duplicated raw-sales sort into the shared
  // engine function, now also Business-Context-aware). Small-menu gate
  // stays here since mostLovedHere itself only knows about the sales-
  // confidence gate, not the section-visibility one.
  List<ProductModel> get _mostLovedHereProducts {
    final ctx = _recoContext;
    if (ctx == null || !RecommendationEngine.hasEnoughProductsForSections(ctx)) {
      return const [];
    }
    return RecommendationEngine.mostLovedHere(ctx,
        limit: RecommendationEngine.defaultSectionLimit);
  }


  // Dish search takeover (Zomato-style): tapping the search box swaps the
  // categorized menu for a photo grid of every dish, live-filtered as the
  // vendor types — see _buildDishSearchGrid. Closed explicitly via the
  // leading chevron, not just by clearing the text.
  final TextEditingController _dishSearchCtrl = TextEditingController();
  final FocusNode _dishSearchFocusNode = FocusNode();
  bool _searchModeActive = false;

  // Windowed rendering for the dish-search grid/list — only the first
  // _dishPageSize items are built (and so only their images requested) up
  // front; scrolling near the bottom reveals the next page instead of every
  // photo firing its network request at once.
  static const int _dishPageSize = 10;
  int _visibleDishCount = _dishPageSize;
  final ScrollController _pageScrollController = ScrollController();

  void _enterDishSearch() {
    if (_searchModeActive) return;
    setState(() {
      _searchModeActive = true;
      _visibleDishCount = _dishPageSize;
    });
  }

  void _exitDishSearch() {
    _dishSearchCtrl.clear();
    searchProduct('');
    _dishSearchFocusNode.unfocus();
    setState(() => _searchModeActive = false);
  }

  bool get _isDineAwayMode =>
      foodType == 'Takeaway' ||
      foodType == 'Dineaway' ||
      foodType == 'Takeaway'.tr() ||
      foodType == 'Dineaway'.tr();

  Widget _buildServicePausedBanner({required bool isDineaway}) {
    final label = isDineaway ? 'Dineaway' : 'Delivery';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300, width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.pause_circle_outline_rounded,
                color: Colors.orange.shade700, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label Paused'.tr(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange.shade800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'This store has temporarily paused $label orders.'.tr(),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _applyDineAwaySubMode() {
    if (_dineAwaySubMode == 'Takeaway') {
      allProductList = _rawDineAwayProducts.where((p) => p.takeaway).toList();
    } else {
      allProductList = _rawDineAwayProducts.where((p) => p.dineIn).toList();
    }
    productList = List.from(allProductList);
  }

  Future<void> getFoodType() async {
    SharedPreferences sp = await SharedPreferences.getInstance();
    foodType = sp.getString("foodType") ?? "Delivery".tr();

    print("------->${foodType}");
    if (_isDineAwayMode) {
      await fireStoreUtils
          .getVendorProductsTakeAWay(widget.vendorModel.id)
          .then((value) {
        _rawDineAwayProducts =
            value.where((p) => p.takeaway || p.dineIn).toList();
        _applyDineAwaySubMode();
        getVendorCategoryById();
        // ignore: unawaited_futures
        _loadRecoContext();
        setState(() {});
      });
    } else {
      await fireStoreUtils
          .getVendorProductsDelivery(widget.vendorModel.id)
          .then((value) {
        // Firestore's deliveryOption filter is commented out server-side
        // (see FireStoreUtils.getVendorProductsDelivery), so it must be
        // filtered here too — otherwise delivery-unavailable items show as
        // addable here and only get caught later by CartScreen's validation.
        final filtered = value.where((p) => p.deliveryOption).toList();
        allProductList = filtered;
        productList = filtered;
        getVendorCategoryById();
        // ignore: unawaited_futures
        _loadRecoContext();
        setState(() {});
      });
    }
  }

  List<VendorCategoryModel> vendorCategoryList = [];
  List<OfferModel> offerList = [];
  List<FavouriteItemModel> favouriteItemList = <FavouriteItemModel>[];

  // Windowed category auto-expand/collapse (2026-07-31) - expanding every
  // category on load (the old `initiallyExpanded: true` on all of them)
  // forces Flutter to build every product card - and fire every product's
  // image request - across every category at once, regardless of scroll
  // position. Instead only a small window of categories around whatever's
  // actually on screen auto-expands/collapses as the user scrolls. A
  // category the user manually taps is left alone forever after (its own
  // ExpansionTile state, never touched by the scroll-driven window again).
  static const int _categoryExpandBuffer = 2;
  final Map<String, GlobalKey> _categoryKeys = {};
  final Map<String, int> _categoryGeneration = {};
  final Map<String, bool> _categoryExpandedAtGeneration = {};
  final Set<String> _manuallyToggledCategoryIds = {};
  Timer? _categoryWindowDebounce;

  GlobalKey _categoryKeyFor(String id) =>
      _categoryKeys.putIfAbsent(id, () => GlobalKey());

  bool _isCategoryExpanded(String id, {required bool defaultValue}) {
    return _categoryExpandedAtGeneration.putIfAbsent(id, () => defaultValue);
  }

  Key _categoryTileKey(String id) =>
      ValueKey('cat_tile_${id}_gen${_categoryGeneration[id] ?? 0}');

  void _applyAutoExpansion(String id, bool shouldExpand) {
    if (_manuallyToggledCategoryIds.contains(id)) return;
    if (_categoryExpandedAtGeneration[id] == shouldExpand) return;
    _categoryGeneration[id] = (_categoryGeneration[id] ?? 0) + 1;
    _categoryExpandedAtGeneration[id] = shouldExpand;
  }

  // Debounced so a fling doesn't recompute (and measure every category's
  // RenderBox) on every single scroll frame.
  void _updateCategoryExpansionWindow() {
    if (!_pageScrollController.hasClients || vendorCategoryList.isEmpty) {
      return;
    }
    _categoryWindowDebounce?.cancel();
    _categoryWindowDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      final screenHeight = MediaQuery.of(context).size.height;
      int? minVisible;
      int? maxVisible;
      for (var i = 0; i < vendorCategoryList.length; i++) {
        final id = vendorCategoryList[i].id.toString();
        final renderObject =
            _categoryKeys[id]?.currentContext?.findRenderObject();
        if (renderObject is! RenderBox || !renderObject.attached) continue;
        final top = renderObject.localToGlobal(Offset.zero).dy;
        final bottom = top + renderObject.size.height;
        if (bottom < 0 || top > screenHeight) continue;
        minVisible = (minVisible == null || i < minVisible) ? i : minVisible;
        maxVisible = (maxVisible == null || i > maxVisible) ? i : maxVisible;
      }
      if (minVisible == null || maxVisible == null) return;
      final windowStart =
          (minVisible - _categoryExpandBuffer).clamp(0, vendorCategoryList.length - 1);
      final windowEnd =
          (maxVisible + _categoryExpandBuffer).clamp(0, vendorCategoryList.length - 1);

      var changed = false;
      for (var i = 0; i < vendorCategoryList.length; i++) {
        final id = vendorCategoryList[i].id.toString();
        if (_manuallyToggledCategoryIds.contains(id)) continue;
        final shouldExpand = i >= windowStart && i <= windowEnd;
        final before = _categoryGeneration[id];
        _applyAutoExpansion(id, shouldExpand);
        if (_categoryGeneration[id] != before) changed = true;
      }
      if (changed) setState(() {});
    });
  }

  getVendorCategoryById() async {
    vendorCategoryList.clear();

    // Many products share the same category — fetch each *distinct* category
    // ID once instead of once per product (e.g. 40 products across 5
    // categories means 5 reads instead of 40). Fetched in parallel, then
    // de-dup once all results are in: the old fire-and-forget .then() pattern
    // caused a race where two futures completing simultaneously could both
    // pass the "already in list?" check and add the same category twice.
    final uniqueCategoryIds =
        productList.map((e) => e.categoryID.toString()).toSet();
    final futures = uniqueCategoryIds
        .map((id) => FireStoreUtils.getVendorCategoryById(id))
        .toList();
    final results = await Future.wait(futures);
    final seen = <String>{};
    for (final value in results) {
      if (value != null && seen.add(value.id.toString())) {
        vendorCategoryList.add(value);
      }
    }

    // Seed a reasonable guess (first few categories open) before anything
    // has actually laid out, so there's no flash-of-all-collapsed before
    // the post-frame callback below measures real positions and corrects
    // it against wherever the user has actually scrolled to.
    for (var i = 0; i < vendorCategoryList.length; i++) {
      _categoryExpandedAtGeneration.putIfAbsent(
          vendorCategoryList[i].id.toString(),
          () => i <= _categoryExpandBuffer);
    }
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _updateCategoryExpansionWindow());

    // Same eligibility rule CartScreen's own offers sheet uses (vendor-
    // specific OR global coupon, isPublic != false so legacy coupons with a
    // missing isPublic field stay visible) — getOfferByVendorID() excludes
    // global coupons and treats a missing isPublic as private, which would
    // silently make this ladder disagree with what checkout actually offers.
    // getAllCoupons() is the same cached call CartScreen/HomeScreen use, so
    // this adds no extra Firestore read.
    await FireStoreUtils().getAllCoupons().then((allCoupons) {
      setState(() {
        offerList = allCoupons
            .where((c) =>
                (c.storeId == widget.vendorModel.id ||
                    c.storeId == null ||
                    (c.storeId?.isEmpty ?? true)) &&
                c.isPublic != false)
            .toList();
      });
      _recomputeOfferLadder();
    });

    // Favorite store/item fetches hidden for now along with the heart
    // toggle UI above — no point doing these reads while nothing displays
    // their result. Re-enable alongside the commented-out InkWell.
    // if (MyAppState.currentUser != null) {
    //   FireStoreUtils.getFavouriteStore(FireStoreUtils.getCurrentUid()).then(
    //     (value) {
    //       if (mounted) setState(() => favouriteList = value);
    //     },
    //   );
    //
    //   FireStoreUtils.getFavouriteItem().then(
    //     (value) {
    //       if (mounted) setState(() => favouriteItemList = value);
    //     },
    //   );
    // }
    // Warm the image cache for the vendor banner and first page of product
    // photos in the background — not awaited, so slow images no longer hold
    // up hiding the skeleton. Each card still shows its own placeholder until
    // its image individually loads.
    if (mounted) {
      _precacheBatch([
        if (widget.vendorModel.photo.isNotEmpty) widget.vendorModel.photo,
        ...widget.vendorModel.photos
            .take(3)
            .map((p) => VendorModel.coverPhotoUrl(p))
            .where((s) => s.isNotEmpty && s != 'null'),
        ...allProductList
            .take(15)
            .where((p) => p.photo.isNotEmpty)
            .map((p) => p.photo),
      ]);
    }
    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _trackRestaurantSessionEnded();
    WidgetsBinding.instance.removeObserver(this);
    _sliderTimer?.cancel();
    _offerLadderTimer?.cancel();
    _offerLadderBoundaryTimer?.cancel();
    _offerLadderPageController.dispose();
    _offerLadderCurrentPageNotifier.dispose();
    _closingCountdownTimer?.cancel();
    _closingInNotifier.dispose();
    _categoryWindowDebounce?.cancel();
    _dwellTimer?.cancel();
    _cartSubscription?.cancel();
    _dishSearchCtrl.dispose();
    _dishSearchFocusNode.dispose();
    _pageScrollController.dispose();
    super.dispose();
  }

  List<FavouriteModel> favouriteList = [];
  PageController pageController = PageController();
  int currentPage = 0;
  Timer? _sliderTimer;
  // Which _cardPhotos indices have actually finished decoding at least once
  // (via NetworkImageWidget's onLoaded/onError below) — animateSlider()
  // only auto-advances to an index once it's in here, and proactively
  // precaches the upcoming index the moment the current one settles, so the
  // image is normally already decoded well before the timer wants to move
  // to it. Fixes a brief shimmer/white flash that showed on the incoming
  // photo when the carousel advanced to one that hadn't loaded yet.
  final Set<int> _heroSettledPages = {};

  // photos[0] = logo, photos[1..n] = card gallery images.
  List<String> get _cardPhotos {
    final all = widget.vendorModel.photos
        .map((e) => VendorModel.coverPhotoUrl(e))
        .where((s) => s.isNotEmpty && s != 'null')
        .toList();
    return all.length > 1 ? all.sublist(1) : <String>[];
  }

  void animateSlider() {
    if (_cardPhotos.length > 1) {
      _sliderTimer = Timer.periodic(const Duration(seconds: 2), (Timer timer) {
        final next = currentPage >= _cardPhotos.length - 1 ? 0 : currentPage + 1;
        // Skip this tick (don't advance) if the upcoming photo hasn't
        // finished decoding yet — advancing to it would show a shimmer/
        // white flash instead of the actual image. It was already
        // proactively precached when the current page settled, so this
        // normally only skips a tick right after the very first photo
        // loads, never afterward.
        if (!_heroSettledPages.contains(next)) return;
        // Wrapping last -> first: a plain PageView isn't circular, so
        // animateToPage(0) from the last page scrolls backward through
        // every intermediate photo instead of cutting straight to the
        // first. jumpToPage snaps instantly for just this one wrap-around
        // step; every other advance still uses the normal smooth animation.
        final wrapping = currentPage >= _cardPhotos.length - 1;
        currentPage = wrapping ? 0 : currentPage + 1;

        if (pageController.hasClients) {
          if (wrapping) {
            pageController.jumpToPage(currentPage);
          } else {
            pageController.animateToPage(
              currentPage,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeIn,
            );
          }
        }
        setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDeliveryActiveNotifier,
      builder: (context, deliveryActive, _) {
        if (currentOrderTypeGlobal == 'Delivery'.tr() && !deliveryActive) {
          return ComingSoonScreen(message: deliveryOffMessageNotifier.value);
        }
        return _buildScreen(context);
      },
    );
  }

  Widget _buildScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: isDarkMode(context)
          ? AppThemeData.surfaceDark
          : const Color(0xFFF2F0F8),
      body: isLoading == true
          ? const VendorProductsSkeletonLoader()
          : RefreshIndicator(
              onRefresh: _onManualRefresh,
              color: AppThemeData.primary500,
              // Without this, the indicator's default position is measured
              // from the very top of this RefreshIndicator's box (edgeOffset
              // 0), which is the top of the huge SliverAppBar image — it ends
              // up drawn inside/behind the header where it's effectively
              // invisible. Pushing it down by the pinned app bar height puts
              // it just below the header, over the visible white card area.
              edgeOffset: kToolbarHeight + MediaQuery.of(context).padding.top,
              child: NestedScrollView(
                  controller: _pageScrollController,
                  headerSliverBuilder:
                      (BuildContext context, bool innerBoxIsScrolled) {
                    return <Widget>[
                      SliverAppBar(
                        expandedHeight: Responsive.height(30, context),
                        floating: true,
                        pinned: true,
                        automaticallyImplyLeading: false,
                        backgroundColor: AppThemeData.primary500,
                        title: Row(
                          children: [
                            InkWell(
                              onTap: () {
                                Navigator.pop(context);
                              },
                              child: Icon(
                                Icons.arrow_back,
                                color: isDarkMode(context)
                                    ? AppThemeData.grey50
                                    : AppThemeData.grey50,
                              ),
                            ),
                            const Expanded(child: SizedBox()),
                            InkWell(
                              onTap:
                                  _isManualRefreshing ? null : _onManualRefresh,
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: _isManualRefreshing
                                    ? const CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                AppThemeData.grey50),
                                      )
                                    : const Icon(
                                        Icons.refresh_rounded,
                                        color: AppThemeData.grey50,
                                      ),
                              ),
                            ),
                            // Phase 2 recommendation engine (2026-07-17) -
                            // "What Should I Try?" discovery page entry
                            // point. Only shown once _recoContext has
                            // loaded (needs real data to be worth opening),
                            // and (2026-07-18) hidden on small menus - a
                            // customer can already see everything at a
                            // glance, so a discovery page adds nothing.
                            if (_recoContext != null &&
                                RecommendationEngine.hasEnoughProductsForSections(
                                    _recoContext!)) ...[
                              const SizedBox(width: 14),
                              InkWell(
                                onTap: () => push(
                                  context,
                                  WhatShouldITryScreen(
                                    recoContext: _recoContext!,
                                    confidenceScores: _confidenceScores,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.auto_awesome_rounded,
                                  color: AppThemeData.grey50,
                                  size: 22,
                                ),
                              ),
                            ],
                            const SizedBox(
                              width: 14,
                            ),
                            // Favorite/heart toggle hidden for now, per
                            // request — re-enable by restoring this InkWell.
                            // InkWell(
                            //   onTap: () async {
                            //     // Check if user is logged in
                            //     if (MyAppState.currentUser == null) {
                            //       push(context, const LoginScreen());
                            //       return;
                            //     }
                            //
                            //     if (favouriteList
                            //         .where((p0) =>
                            //             p0.store_id == widget.vendorModel.id)
                            //         .isNotEmpty) {
                            //       FavouriteModel favouriteModel =
                            //           FavouriteModel(
                            //               section_id: sectionConstantModel!.id,
                            //               store_id: widget.vendorModel.id,
                            //               user_id:
                            //                   MyAppState.currentUser!.userID);
                            //       favouriteList.removeWhere((item) =>
                            //           item.store_id == widget.vendorModel.id);
                            //       await FireStoreUtils.removeFavouriteStore(
                            //           favouriteModel);
                            //     } else {
                            //       FavouriteModel favouriteModel =
                            //           FavouriteModel(
                            //               section_id: sectionConstantModel!.id,
                            //               store_id: widget.vendorModel.id,
                            //               user_id:
                            //                   MyAppState.currentUser!.userID);
                            //       await FireStoreUtils.setFavouriteStore(
                            //           favouriteModel);
                            //       favouriteList.add(favouriteModel);
                            //     }
                            //     setState(() {});
                            //   },
                            //   child: favouriteList
                            //           .where((p0) =>
                            //               p0.store_id == widget.vendorModel.id)
                            //           .isNotEmpty
                            //       ? SvgPicture.asset(
                            //           "assets/icons/ic_like_fill.svg",
                            //           colorFilter: const ColorFilter.mode(
                            //               AppThemeData.grey50, BlendMode.srcIn),
                            //         )
                            //       : SvgPicture.asset(
                            //           "assets/icons/ic_like.svg",
                            //         ),
                            // ),
                            // const SizedBox(
                            //   width: 10,
                            // ),
                          ],
                        ),
                        flexibleSpace: FlexibleSpaceBar(
                          background: Stack(
                            children: [
                              _cardPhotos.isEmpty
                                  ? Stack(
                                      children: [
                                        NetworkImageWidget(
                                          imageUrl: widget.vendorModel.photo
                                              .toString(),
                                          fit: BoxFit.cover,
                                          width: Responsive.width(100, context),
                                          height:
                                              Responsive.height(40, context),
                                        ),
                                        Container(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin:
                                                  const Alignment(0.00, -1.00),
                                              end: const Alignment(0, 1),
                                              colors: [
                                                Colors.black.withOpacity(0),
                                                Colors.black.withOpacity(0.55),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : PageView.builder(
                                      physics: const BouncingScrollPhysics(),
                                      controller: pageController,
                                      scrollDirection: Axis.horizontal,
                                      itemCount: _cardPhotos.length,
                                      padEnds: false,
                                      pageSnapping: true,
                                      itemBuilder:
                                          (BuildContext context, int index) {
                                        String image = _cardPhotos[index];
                                        final heroWidth =
                                            Responsive.width(100, context);
                                        void onSettled() {
                                          _heroSettledPages.add(index);
                                          final next =
                                              (index + 1) % _cardPhotos.length;
                                          if (!_heroSettledPages.contains(next)) {
                                            precacheCarouselImage(
                                                context, _cardPhotos[next],
                                                width: heroWidth);
                                          }
                                        }

                                        return Stack(
                                          children: [
                                            NetworkImageWidget(
                                              imageUrl: image,
                                              fit: BoxFit.cover,
                                              width: heroWidth,
                                              height: Responsive.height(
                                                  40, context),
                                              onLoaded: onSettled,
                                              onError: (_) => onSettled(),
                                            ),
                                            Container(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: const Alignment(
                                                      0.00, -1.00),
                                                  end: const Alignment(0, 1),
                                                  colors: [
                                                    Colors.black.withOpacity(0),
                                                    Colors.black.withOpacity(0.55),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                              Positioned(
                                bottom: 10,
                                right: 0,
                                left: 0,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: List.generate(
                                    _cardPhotos.length,
                                    (index) {
                                      return Container(
                                        margin: const EdgeInsets.only(right: 5),
                                        alignment: Alignment.centerLeft,
                                        height: 9,
                                        width: 9,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: currentPage == index
                                              ? AppThemeData.primary500
                                              : AppThemeData.grey300,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ];
                  },
                  body: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_isDineAwayMode &&
                              !widget.vendorModel.vendorDineawayOpen)
                            _buildServicePausedBanner(isDineaway: true),
                          if (!_isDineAwayMode &&
                              !widget.vendorModel.vendorDeliveryOpen)
                            _buildServicePausedBanner(isDineaway: false),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Restaurant Name and Rating Section
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    color: isDarkMode(context)
                                        ? AppThemeData.darkBgTertiary
                                        : Colors.white,
                                    border: isDarkMode(context)
                                        ? null
                                        : Border.all(
                                            color: const Color(0xFFE5E1FF),
                                            width: 1,
                                          ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(
                                            isDarkMode(context) ? 0.2 : 0.05),
                                        blurRadius: 12,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  widget.vendorModel.title
                                                      .toString(),
                                                  textAlign: TextAlign.start,
                                                  maxLines: 1,
                                                  style: TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.bold,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    fontFamily:
                                                        AppThemeData.semiBold,
                                                    color: isDarkMode(context)
                                                        ? AppThemeData.grey50
                                                        : AppThemeData.grey900,
                                                  ),
                                                ),
                                                const SizedBox(height: 5),
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.location_on_rounded,
                                                      size: 14,
                                                      color: AppThemeData
                                                          .primary500,
                                                    ),
                                                    const SizedBox(width: 3),
                                                    Expanded(
                                                      child: Text(
                                                        () {
                                                          final loc = widget
                                                              .vendorModel
                                                              .locality
                                                              .trim();
                                                          final lm = widget
                                                              .vendorModel
                                                              .landmark
                                                              .trim();
                                                          if (loc.isEmpty)
                                                            return widget
                                                                .vendorModel
                                                                .location;
                                                          if (lm.isEmpty)
                                                            return loc;
                                                          return '$loc, $lm';
                                                        }(),
                                                        textAlign:
                                                            TextAlign.start,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontFamily:
                                                              AppThemeData
                                                                  .medium,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color: isDarkMode(
                                                                  context)
                                                              ? AppThemeData
                                                                  .grey400
                                                              : AppThemeData
                                                                  .grey500,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if (widget.vendorModel
                                                    .cuisineNames.isNotEmpty) ...[
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    widget.vendorModel
                                                        .cuisineNames
                                                        .join(' · '),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontFamily:
                                                          AppThemeData.medium,
                                                      color: isDarkMode(context)
                                                          ? AppThemeData.grey400
                                                          : AppThemeData.grey500,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          InkWell(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            onTap: () {
                                              push(
                                                context,
                                                ReviewListScreen(
                                                  vendorId:
                                                      widget.vendorModel.id,
                                                ),
                                              );
                                            },
                                            child: Container(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    isDarkMode(context)
                                                        ? const Color(
                                                            0xFF052E16)
                                                        : const Color(
                                                            0xFFDCFCE7),
                                                    isDarkMode(context)
                                                        ? const Color(
                                                            0xFF14532D)
                                                        : const Color(
                                                            0xFFBBF7D0),
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 7),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  SvgPicture.asset(
                                                    "assets/icons/ic_star.svg",
                                                    colorFilter:
                                                        const ColorFilter.mode(
                                                            Color(0xFF16A34A),
                                                            BlendMode.srcIn),
                                                    height: 15,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    "${calculateReview(reviewCount: widget.vendorModel.reviewsCount.toStringAsFixed(0), reviewSum: widget.vendorModel.reviewsSum.toString())} (${widget.vendorModel.reviewsCount.toStringAsFixed(0)})",
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: isDarkMode(context)
                                                          ? const Color(
                                                              0xFF4ADE80)
                                                          : const Color(
                                                              0xFF15803D),
                                                      fontFamily:
                                                          AppThemeData.semiBold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // Open/Close Status Section
                                sectionConstantModel!.serviceTypeFlag ==
                                        "ecommerce-service"
                                    ? const SizedBox()
                                    // ValueListenableBuilder instead of Builder — this
                                    // ticks every 1s while the countdown is active and
                                    // a bare setState() on the shared State would rebuild
                                    // the entire ~5000-line screen just for this badge.
                                    : ValueListenableBuilder<Duration?>(
                                        valueListenable: _closingInNotifier,
                                        builder: (context, _closingIn, __) {
                                        final isClosingSoon = isOpen &&
                                            _closingIn != null &&
                                            _closingIn.inSeconds > 0;
                                        final statusColor = isClosingSoon
                                            ? const Color(0xFFBF6000)
                                            : isOpen
                                                ? AppThemeData.success400
                                                : AppThemeData.danger300;
                                        final bgColor = isClosingSoon
                                            ? const Color(0xFFFFF3CD)
                                            : isOpen
                                                ? AppThemeData.success400
                                                    .withOpacity(0.1)
                                                : AppThemeData.danger300
                                                    .withOpacity(0.1);
                                        final darkBgColor = isClosingSoon
                                            ? const Color(0xFF3D2B00)
                                            : isOpen
                                                ? AppThemeData.success400
                                                    .withOpacity(0.1)
                                                : AppThemeData.danger300
                                                    .withOpacity(0.1);
                                        final mins = _closingIn != null
                                            ? _closingIn.inMinutes
                                                .remainder(60)
                                                .toString()
                                                .padLeft(2, '0')
                                            : '00';
                                        final secs = _closingIn != null
                                            ? _closingIn.inSeconds
                                                .remainder(60)
                                                .toString()
                                                .padLeft(2, '0')
                                            : '00';
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(top: 12),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 8, horizontal: 12),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              color: isDarkMode(context)
                                                  ? darkBgColor
                                                  : bgColor,
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.all(4),
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: statusColor,
                                                  ),
                                                  child: Icon(
                                                    isOpen
                                                        ? Icons
                                                            .access_time_filled
                                                        : Icons
                                                            .access_time_outlined,
                                                    color: Colors.white,
                                                    size: 12,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      isClosingSoon
                                                          ? RichText(
                                                              text: TextSpan(
                                                                children: [
                                                                  TextSpan(
                                                                    text:
                                                                        'Closing in ',
                                                                    style:
                                                                        TextStyle(
                                                                      fontSize:
                                                                          13,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                      fontFamily:
                                                                          AppThemeData
                                                                              .semiBold,
                                                                      color:
                                                                          statusColor,
                                                                    ),
                                                                  ),
                                                                  TextSpan(
                                                                    text:
                                                                        '$mins:$secs',
                                                                    style:
                                                                        TextStyle(
                                                                      fontSize:
                                                                          14,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w800,
                                                                      fontFamily:
                                                                          AppThemeData
                                                                              .bold,
                                                                      color:
                                                                          statusColor,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            )
                                                          : Text(
                                                              isOpen
                                                                  ? "Open Now"
                                                                      .tr()
                                                                  : "Currently Closed"
                                                                      .tr(),
                                                              textAlign:
                                                                  TextAlign
                                                                      .start,
                                                              maxLines: 1,
                                                              style: TextStyle(
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                fontFamily:
                                                                    AppThemeData
                                                                        .semiBold,
                                                                color:
                                                                    statusColor,
                                                              ),
                                                            ),
                                                      if (!isClosingSoon &&
                                                          isOpen &&
                                                          _closingAtLabel !=
                                                              null)
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(top: 2),
                                                          child: Text(
                                                            _closingAtLabel!,
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color: statusColor
                                                                  .withOpacity(
                                                                      0.75),
                                                              fontFamily:
                                                                  AppThemeData
                                                                      .regular,
                                                            ),
                                                          ),
                                                        ),
                                                      // Closed subtitle — two cases:
                                                      // • toggle OFF → "not accepting orders"
                                                      // • toggle ON + outside schedule → next opening time
                                                      if (!isOpen) ...[
                                                        if (!widget.vendorModel
                                                            .reststatus)
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .only(
                                                                    top: 2),
                                                            child: Text(
                                                              'Restaurant is not accepting orders right now'
                                                                  .tr(),
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color: statusColor
                                                                    .withOpacity(
                                                                        0.75),
                                                                fontFamily:
                                                                    AppThemeData
                                                                        .regular,
                                                              ),
                                                            ),
                                                          )
                                                        else if (_nextOpenLabel !=
                                                            null)
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .only(
                                                                    top: 2),
                                                            child: Text(
                                                              _nextOpenLabel!,
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color: statusColor
                                                                    .withOpacity(
                                                                        0.75),
                                                                fontFamily:
                                                                    AppThemeData
                                                                        .regular,
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }),

                                // Offer Banner — coupons have no order-type restriction
                                // (unlike the special discount, which does), so unlike
                                // that banner this one applies in both Delivery and
                                // Dineaway mode. _buildOfferBanner already no-ops via
                                // an empty rung list when there's nothing to show.
                                _buildOfferBanner(context),

                                // Menu Section
                                const SizedBox(height: 16),
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    color: isDarkMode(context)
                                        ? AppThemeData.darkBgTertiary
                                        : Colors.white,
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      // Closes dish-search mode and returns to the
                                      // categorized menu — only shown once search
                                      // is active (tapped in or has text).
                                      if (_searchModeActive) ...[
                                        InkWell(
                                          onTap: _exitDishSearch,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          child: Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: isDarkMode(context)
                                                  ? AppThemeData.grey800
                                                  : AppThemeData.grey100,
                                            ),
                                            child: Icon(
                                              Icons.keyboard_arrow_down_rounded,
                                              color: isDarkMode(context)
                                                  ? AppThemeData.grey300
                                                  : AppThemeData.grey700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Expanded(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: isDarkMode(context)
                                                ? AppThemeData.grey800
                                                : AppThemeData.grey100,
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            border: Border.all(
                                              color: isDarkMode(context)
                                                  ? AppThemeData.grey700
                                                  : AppThemeData.grey200,
                                              width: 1,
                                            ),
                                          ),
                                          child: TextField(
                                            controller: _dishSearchCtrl,
                                            focusNode: _dishSearchFocusNode,
                                            onTap: _enterDishSearch,
                                            onChanged: searchProduct,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: isDarkMode(context)
                                                  ? AppThemeData.grey50
                                                  : AppThemeData.grey900,
                                              fontFamily: AppThemeData.regular,
                                            ),
                                            decoration: InputDecoration(
                                              hintText:
                                                  '${'Search in'.tr()} ${widget.vendorModel.title}',
                                              // Purple (2026-07-18, was grey)
                                              // per explicit request - hint
                                              // text and search icon only,
                                              // box styling unchanged.
                                              hintStyle: const TextStyle(
                                                color: AppThemeData.primary500,
                                                fontFamily:
                                                    AppThemeData.regular,
                                                fontSize: 14,
                                              ),
                                              prefixIcon: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 14,
                                                        vertical: 13),
                                                child: SvgPicture.asset(
                                                  "assets/icons/ic_search.svg",
                                                  colorFilter:
                                                      const ColorFilter.mode(
                                                    AppThemeData.primary500,
                                                    BlendMode.srcIn,
                                                  ),
                                                  height: 18,
                                                  width: 18,
                                                ),
                                              ),
                                              prefixIconConstraints:
                                                  const BoxConstraints(
                                                      minWidth: 46,
                                                      minHeight: 46),
                                              suffixIcon: _dishSearchCtrl
                                                      .text.isNotEmpty
                                                  ? IconButton(
                                                      icon: Icon(
                                                          Icons.close_rounded,
                                                          size: 18,
                                                          color: isDarkMode(
                                                                  context)
                                                              ? AppThemeData
                                                                  .grey400
                                                              : AppThemeData
                                                                  .grey500),
                                                      onPressed: () {
                                                        _dishSearchCtrl.clear();
                                                        searchProduct('');
                                                      },
                                                    )
                                                  : null,
                                              border: InputBorder.none,
                                              enabledBorder: InputBorder.none,
                                              focusedBorder: InputBorder.none,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 14,
                                                      horizontal: 4),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Compact single-row filter bar — hidden during dish
                          // search, which takes over this whole area instead.
                          if (!_searchModeActive) ...[
                            const SizedBox(height: 10),
                            _buildFilterBar(context),
                          ],
                          const SizedBox(height: 12),

                          // Phase 2 recommendation sections (2026-07-17) -
                          // fully automatic/data-driven, no vendor
                          // configuration anywhere (Vendor Featured reverted
                          // 2026-07-17 per explicit product direction - see
                          // RECOMMENDATION_SYSTEM_ARCHITECTURE.html Section
                          // 12). Hidden during dish search (same gate as the
                          // filter bar above) and each individually hidden
                          // if it has nothing to show (cold start). "Explore
                          // the Menu" (2026-07-18) is NOT a recommendation -
                          // it only ever appears INSTEAD OF the 3 sections
                          // above (never alongside), whenever the menu is
                          // big enough for a section but the restaurant
                          // doesn't yet have enough sales history for a real
                          // one - see shouldShowExploreMenuFallback. All 4
                          // getters below already self-gate correctly so
                          // at most the right one(s) ever render.
                          if (!_searchModeActive) ...[
                            _buildHorizontalProductSection(
                              titleText: '❤️ ' + 'Recommended For You'.tr(),
                              products: _recommendedForYouProducts,
                              enablePairsWellWith: true,
                            ),
                            if (_pairsWellWithProductId != null &&
                                _pairsWellWithFromCarousel)
                              _buildCarouselPairsWellWithPanel(),
                            if (_showRestaurantMustTry)
                              _buildHorizontalProductSection(
                                titleText: '⭐ ' + 'Restaurant Must Try'.tr(),
                                products: _restaurantMustTryProducts,
                              ),
                            if (_showMostLovedHere)
                              _buildHorizontalProductSection(
                                titleText: '🔥 ' + 'Most Loved Here'.tr(),
                                products: _mostLovedHereProducts,
                              ),
                            _buildHorizontalProductSection(
                              titleText: '✨ ' + 'Explore the Menu'.tr(),
                              products: _exploreMenuProducts,
                              suppressBadge: true,
                            ),
                          ],

                          // Product List View
                          _searchModeActive
                              ? _buildDishSearchArea()
                              : productListView(),
                        ],
                      ),
                    ),
                  ))),
      bottomNavigationBar: cartProducts.isNotEmpty
          ? Container(
              color: AppThemeData.primary500,
              padding: EdgeInsets.fromLTRB(
                  30, 10, 30, 10 + MediaQuery.of(context).padding.bottom),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      // "X item(s) added" (2026-07-20, was a static "Item
                      // Total" label). Price removed (2026-07-26, product
                      // request) - a raw pre-checkout total here discouraged
                      // adding more items, when the final price after
                      // discounts is often lower than what showed here.
                      () {
                        final count = cartProducts.fold<int>(
                            0, (sum, c) => sum + c.quantity);
                        return count == 1
                            ? '1 ${'item added'.tr()}'
                            : '$count ${'items added'.tr()}';
                      }(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontFamily: AppThemeData.semiBold,
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          if (MyAppState.currentUser == null) {
                            ShowToastDialog.showToast(
                                "Please login to view cart".tr());
                            // You may want to add push(context, const LoginScreen()); here if you have the import
                          } else {
                            pushAndRemoveUntil(
                              context,
                              ContainerScreen(
                                user: MyAppState.currentUser!,
                                drawerSelection: DrawerSelection.Cart,
                                currentWidget: const CartScreen(),
                                appBarTitle: 'Your Cart',
                              ),
                            );
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 20),
                          child: Row(
                            children: [
                              Text(
                                "View Cart".tr(),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: AppThemeData.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.shopping_cart_outlined,
                                color: Colors.white,
                                size: 17,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  bool isVag = false;
  bool isNonVag = false;
  String? _nutritionFilterType;
  String? _nutritionFilterLevel;

  static const _nutritionMetrics = [
    'Calories',
    'Protein',
    'Carbs',
    'Fat',
    'Fiber'
  ];
  static const _nutritionLevels = ['High', 'Medium', 'Low'];

  filterRecord() {
    List<ProductModel> base = allProductList;

    if (isVag == true && isNonVag == false) {
      base = base.where((p0) => p0.nonveg == false).toList();
    } else if (isVag == false && isNonVag == true) {
      base = base.where((p0) => p0.nonveg == true).toList();
    }

    if (_nutritionFilterType != null && _nutritionFilterLevel != null) {
      base = base.where((p) {
        if (!p.nutritionEnabled || p.nutritionInfo == null) return false;
        return p.nutritionInfo!.classifyMetric(_nutritionFilterType!) ==
            _nutritionFilterLevel;
      }).toList();
    }

    productList = base;
    setState(() {});
  }

  // Vendor Product Screen dish search only — case-insensitive,
  // whitespace-normalized (trim + lowercase + collapse internal whitespace
  // to a single space), so "Burger", "burger", "BURGER", "BuRgEr" and
  // partial input like "burg" all match identically. Scoped to this screen
  // only; does not touch SearchScreen.dart or any other search flow.
  String _normalizeDishSearchText(String input) {
    return input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  // Normalized once per product (keyed by the stable product id, so it
  // survives allProductList being reassigned/re-filtered elsewhere on this
  // screen — takeaway/dine-in toggles, tab switches, etc.) rather than
  // re-normalized on every keystroke.
  final Map<String, String> _normalizedDishNameCache = {};
  String _normalizedDishName(ProductModel p) => _normalizedDishNameCache
      .putIfAbsent(p.id, () => _normalizeDishSearchText(p.name));

  searchProduct(String name) {
    _visibleDishCount = _dishPageSize;
    final query = _normalizeDishSearchText(name);
    if (query.isEmpty) {
      productList.clear();
      productList.addAll(allProductList);
    } else {
      isVag = false;
      isNonVag = false;
      _nutritionFilterType = null;
      _nutritionFilterLevel = null;
      productList = allProductList
          .where((p0) => _normalizedDishName(p0).contains(query))
          .toList();
    }
    setState(() {});
  }

  // ── Dish search results (Zomato-style takeover) ─────────────────────────
  // Empty query → photo grid browse of every dish. Typed query → a flat
  // list with category context, highlighted match, description, and an ADD
  // button — closer to how a filtered result actually reads. Both windows
  // are capped at _visibleDishCount so only currently-visible rows' images
  // are ever requested (see the scroll listener in initState).

  Widget _buildDishSearchArea() {
    final query = _dishSearchCtrl.text.trim();
    return query.isEmpty
        ? _buildDishPhotoGrid(productList)
        : _buildDishSearchResultsList(productList, query);
  }

  Widget _buildSearchEmptyState() {
    final isDark = isDarkMode(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.search_off_rounded,
                size: 48,
                color: isDark ? AppThemeData.grey700 : AppThemeData.grey300),
            const SizedBox(height: 12),
            Text(
              'No dishes found'.tr(),
              style: TextStyle(
                fontSize: 14,
                fontFamily: AppThemeData.medium,
                color: isDark ? AppThemeData.grey400 : AppThemeData.grey600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vegDot(ProductModel p, {double size = 7}) {
    final color = p.nonveg ? AppThemeData.error500 : const Color(0xFF10B981);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: color, width: 1.2),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }

  // Bolds the first matching substring so a typed "sp" visibly highlights
  // inside "Special Thali" — falls back to plain text when there's no query
  // or no match (e.g. the dish matched on category, not name).
  Widget _highlightedName(String name, String query, TextStyle baseStyle) {
    final idx =
        query.isEmpty ? -1 : name.toLowerCase().indexOf(query.toLowerCase());
    if (idx < 0) {
      return Text(name,
          maxLines: 2, overflow: TextOverflow.ellipsis, style: baseStyle);
    }
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: baseStyle, children: [
        TextSpan(text: name.substring(0, idx)),
        TextSpan(
          text: name.substring(idx, idx + query.length),
          style: baseStyle.copyWith(
              fontWeight: FontWeight.w800, color: AppThemeData.primary500),
        ),
        TextSpan(text: name.substring(idx + query.length)),
      ]),
    );
  }

  String _categoryTitleFor(String categoryID) {
    final match =
        vendorCategoryList.firstWhereOrNull((c) => c.id == categoryID);
    return match?.title.toString() ?? '';
  }

  Widget _dishTile(ProductModel p) {
    final isDark = isDarkMode(context);
    return GestureDetector(
      onTap: () => _showProductQuickView(p),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        // Matches the vendor's fixed 16:9 upload crop exactly — see
        // image_crop_16x9.dart and QUICKDASH_CHANGELOG.html — so this grid
        // never re-crops an already-cropped photo.
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              p.photo.isNotEmpty
                  ? NetworkImageWidget(
                      imageUrl: getImageVAlidUrl(p.photo),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    )
                  : Container(
                      color:
                          isDark ? AppThemeData.grey800 : AppThemeData.grey100,
                      child: Icon(Icons.restaurant_menu,
                          color: AppThemeData.grey400, size: 28),
                    ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 22, 8, 7),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC000000)],
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (p.veg || p.nonveg) ...[
                        _vegDot(p, size: 8),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
  }

  // 2-up grid, with every 4th row promoted to a single full-width "feature"
  // tile (same true 16:9 crop, just rendered bigger) for the visual rhythm
  // in the Zomato reference — no extra cropping introduced.
  Widget _buildDishPhotoGrid(List<ProductModel> items) {
    if (items.isEmpty) return _buildSearchEmptyState();
    final windowed = items.take(_visibleDishCount).toList();
    final rows = <Widget>[];
    int i = 0;
    int rowIndex = 0;
    while (i < windowed.length) {
      if (rowIndex % 4 == 3) {
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _dishTile(windowed[i]),
        ));
        i += 1;
      } else {
        final a = windowed[i];
        final b = i + 1 < windowed.length ? windowed[i + 1] : null;
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _dishTile(a)),
              const SizedBox(width: 10),
              Expanded(
                  child: b != null ? _dishTile(b) : const SizedBox.shrink()),
            ],
          ),
        ));
        i += b != null ? 2 : 1;
      }
      rowIndex++;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: rows),
    );
  }

  // Flat (non-grouped) results, but every card is the exact same
  // _buildProductCard used in the normal categorized menu — same price/
  // discount badge, 130x130 photo, ADD button ↔ quantity-stepper pill, and
  // "pairs well with" panel on add. Only addition: a small "In {category}"
  // label above each card, since results span multiple categories at once
  // and there's no ExpansionTile header here to supply that context.
  Widget _buildDishSearchResultsList(List<ProductModel> items, String query) {
    if (items.isEmpty) return _buildSearchEmptyState();
    final windowed = items.take(_visibleDishCount).toList();
    final isDark = isDarkMode(context);
    return Column(
      children: [
        for (int i = 0; i < windowed.length; i++) ...[
          _searchResultCard(windowed[i], query, isDark),
          if (i != windowed.length - 1)
            Divider(
              height: 1,
              thickness: 1,
              indent: 16,
              endIndent: 16,
              color: isDark ? AppThemeData.grey800 : AppThemeData.grey200,
            ),
        ],
      ],
    );
  }

  Widget _searchResultCard(ProductModel p, String query, bool isDark) {
    final categoryTitle = _categoryTitleFor(p.categoryID);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (categoryTitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              '${'In'.tr()} $categoryTitle',
              style: TextStyle(
                fontSize: 11.5,
                fontFamily: AppThemeData.regular,
                color: isDark ? AppThemeData.grey500 : AppThemeData.grey500,
              ),
            ),
          ),
        _buildProductCard(p, highlightQuery: query),
      ],
    );
  }

  // ── Compact horizontal filter bar ───────────────────────────────────────────

  Widget _buildFilterBar(BuildContext context) {
    final isDark = isDarkMode(context);
    final hasNutrition =
        _nutritionFilterType != null && _nutritionFilterLevel != null;

    return SizedBox(
      // 40 (was 34) - chips are now 36 tall plus a small shadow on the
      // active one, which was getting clipped at the old height.
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        children: [
          // Dining / Takeaway chips (DineAway mode only) - Dining shown
          // first and selected by default (2026-07-26, explicit request).
          if (_isDineAwayMode) ...[
            _filterChip(
              context: context,
              label: 'Dining'.tr(),
              icon: Icons.chair_outlined,
              isActive: _dineAwaySubMode == 'Dining',
              activeColor: AppThemeData.primary500,
              onTap: () {
                if (_dineAwaySubMode != 'Dining') {
                  setState(() {
                    _dineAwaySubMode = 'Dining';
                    isVag = false;
                    isNonVag = false;
                    _nutritionFilterType = null;
                    _nutritionFilterLevel = null;
                    allProductList =
                        _rawDineAwayProducts.where((p) => p.dineIn).toList();
                    productList = List.from(allProductList);
                  });
                  getVendorCategoryById();
                }
              },
            ),
            const SizedBox(width: 8),
            _filterChip(
              context: context,
              label: 'Takeaway'.tr(),
              icon: Icons.takeout_dining_outlined,
              isActive: _dineAwaySubMode == 'Takeaway',
              activeColor: AppThemeData.primary500,
              onTap: () {
                if (_dineAwaySubMode != 'Takeaway') {
                  setState(() {
                    _dineAwaySubMode = 'Takeaway';
                    isVag = false;
                    isNonVag = false;
                    _nutritionFilterType = null;
                    _nutritionFilterLevel = null;
                    allProductList =
                        _rawDineAwayProducts.where((p) => p.takeaway).toList();
                    productList = List.from(allProductList);
                  });
                  getVendorCategoryById();
                }
              },
            ),
            _filterDivider(isDark),
          ],

          // Veg / Non-Veg chips
          if (sectionConstantModel!.isProductDetails == true) ...[
            _filterChip(
              context: context,
              label: 'Veg'.tr(),
              svgIcon: 'assets/icons/ic_veg.svg',
              isActive: isVag,
              activeColor: AppThemeData.success400,
              onTap: () {
                setState(() => isVag = !isVag);
                filterRecord();
              },
            ),
            const SizedBox(width: 8),
            _filterChip(
              context: context,
              label: 'Non-Veg'.tr(),
              svgIcon: 'assets/icons/ic_nonveg.svg',
              isActive: isNonVag,
              activeColor: AppThemeData.danger300,
              onTap: () {
                setState(() => isNonVag = !isNonVag);
                filterRecord();
              },
            ),
            _filterDivider(isDark),
          ],

          // Nutrition chip
          _filterChip(
            context: context,
            label: hasNutrition
                ? '$_nutritionFilterType · $_nutritionFilterLevel'
                : 'Nutrition'.tr(),
            icon: Icons.monitor_heart_outlined,
            isActive: hasNutrition,
            activeColor: AppThemeData.primary500,
            showDropdownArrow: !hasNutrition,
            showClear: hasNutrition,
            onClear: () {
              setState(() {
                _nutritionFilterType = null;
                _nutritionFilterLevel = null;
              });
              filterRecord();
            },
            onTap: () => _showNutritionSheet(context),
          ),
        ],
      ),
    );
  }

  Widget _filterDivider(bool isDark) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: VerticalDivider(
          width: 1,
          thickness: 1,
          color: isDark ? AppThemeData.grey700 : AppThemeData.grey200,
          indent: 5,
          endIndent: 5,
        ),
      );

  Widget _filterChip({
    required BuildContext context,
    required String label,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
    IconData? icon,
    String? svgIcon,
    bool showDropdownArrow = false,
    bool showClear = false,
    VoidCallback? onClear,
  }) {
    final isDark = isDarkMode(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isActive
              ? activeColor
              : (isDark ? AppThemeData.grey800 : Colors.white),
          border: isActive
              ? null
              : Border.all(
                  color: isDark ? AppThemeData.grey700 : AppThemeData.grey200,
                  width: 1,
                ),
          // Active chip gets a small lift matching the search bar's own
          // shadow treatment (2026-07-18) - selected state should feel
          // "raised", not just recolored.
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: activeColor.withOpacity(0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (svgIcon != null)
              Padding(
                padding: const EdgeInsets.only(right: 5),
                child: SvgPicture.asset(
                  svgIcon,
                  height: 13,
                  width: 13,
                  colorFilter: isActive
                      ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
                      : null,
                ),
              )
            else if (icon != null)
              Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Icon(
                  icon,
                  size: 13,
                  color: isActive
                      ? Colors.white
                      : (isDark ? AppThemeData.grey400 : AppThemeData.grey500),
                ),
              ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontFamily: AppThemeData.medium,
                color: isActive
                    ? Colors.white
                    : (isDark ? AppThemeData.grey300 : AppThemeData.grey700),
              ),
            ),
            if (showClear && onClear != null) ...[
              const SizedBox(width: 5),
              GestureDetector(
                onTap: onClear,
                behavior: HitTestBehavior.opaque,
                child: const Icon(Icons.close_rounded,
                    size: 13, color: Colors.white),
              ),
            ] else if (showDropdownArrow) ...[
              const SizedBox(width: 3),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 14,
                color: isDark ? AppThemeData.grey400 : AppThemeData.grey500,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showNutritionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (ctx) {
        String? selectedType = _nutritionFilterType;
        String? selectedLevel = _nutritionFilterLevel;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final isDark = isDarkMode(context);
            return Container(
              decoration: BoxDecoration(
                color: isDark ? AppThemeData.grey900 : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, MediaQuery.of(context).padding.bottom + 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppThemeData.grey700
                            : AppThemeData.grey200,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Title row
                  Row(
                    children: [
                      Icon(Icons.monitor_heart_outlined,
                          size: 18, color: AppThemeData.primary500),
                      const SizedBox(width: 8),
                      Text(
                        'Nutrition Filter'.tr(),
                        style: TextStyle(
                          fontSize: 15,
                          fontFamily: AppThemeData.semiBold,
                          color: isDark ? Colors.white : AppThemeData.grey900,
                        ),
                      ),
                      const Spacer(),
                      if (selectedType != null || selectedLevel != null)
                        GestureDetector(
                          onTap: () {
                            setSheet(() {
                              selectedType = null;
                              selectedLevel = null;
                            });
                            setState(() {
                              _nutritionFilterType = null;
                              _nutritionFilterLevel = null;
                            });
                            filterRecord();
                          },
                          child: Text(
                            'Clear'.tr(),
                            style: TextStyle(
                              fontSize: 13,
                              color: AppThemeData.primary500,
                              fontFamily: AppThemeData.medium,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // Type label
                  Text(
                    'Type'.tr(),
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: AppThemeData.medium,
                      letterSpacing: 0.6,
                      color:
                          isDark ? AppThemeData.grey400 : AppThemeData.grey500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _nutritionMetrics.map((type) {
                      final sel = selectedType == type;
                      return GestureDetector(
                        onTap: () {
                          setSheet(() => selectedType = type);
                          setState(() => _nutritionFilterType = type);
                          if (selectedLevel != null) filterRecord();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: sel
                                ? AppThemeData.primary500
                                : (isDark
                                    ? AppThemeData.grey800
                                    : AppThemeData.grey100),
                            border: Border.all(
                              color: sel
                                  ? AppThemeData.primary500
                                  : (isDark
                                      ? AppThemeData.grey700
                                      : AppThemeData.grey200),
                            ),
                          ),
                          child: Text(
                            type,
                            style: TextStyle(
                              fontSize: 13,
                              fontFamily: AppThemeData.medium,
                              color: sel
                                  ? Colors.white
                                  : (isDark
                                      ? AppThemeData.grey300
                                      : AppThemeData.grey700),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  // Level label
                  Text(
                    'Level'.tr(),
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: AppThemeData.medium,
                      letterSpacing: 0.6,
                      color:
                          isDark ? AppThemeData.grey400 : AppThemeData.grey500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: _nutritionLevels.map((level) {
                      final sel = selectedLevel == level;
                      final levelColor = level == 'High'
                          ? AppThemeData.error500
                          : level == 'Medium'
                              ? AppThemeData.accent500
                              : AppThemeData.success400;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () {
                            setSheet(() => selectedLevel = level);
                            setState(() => _nutritionFilterLevel = level);
                            if (selectedType != null) filterRecord();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: sel
                                  ? levelColor
                                  : (isDark
                                      ? AppThemeData.grey800
                                      : AppThemeData.grey100),
                              border: Border.all(
                                color: sel
                                    ? levelColor
                                    : (isDark
                                        ? AppThemeData.grey700
                                        : AppThemeData.grey200),
                              ),
                            ),
                            child: Text(
                              level,
                              style: TextStyle(
                                fontSize: 13,
                                fontFamily: AppThemeData.medium,
                                color: sel
                                    ? Colors.white
                                    : (isDark
                                        ? AppThemeData.grey300
                                        : AppThemeData.grey700),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  bool isOpen = false;
  final ValueNotifier<Duration?> _closingInNotifier =
      ValueNotifier<Duration?>(null);
  Timer? _closingCountdownTimer;
  String? _closingAtLabel;
  String? _nextOpenLabel;

  statusCheck() {
    final now = DateTime.now();
    final day = DateFormat('EEEE', 'en_US').format(now);
    final date = DateFormat('dd-MM-yyyy').format(now);
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayDay = DateFormat('EEEE', 'en_US').format(yesterday);
    final yesterdayDate = DateFormat('dd-MM-yyyy').format(yesterday);
    DateTime? activeEnd;
    bool scheduleOpen = false;
    isOpen = false;
    _closingAtLabel = null;
    _nextOpenLabel = null;

    // Step 1: Derive schedule-based status from working hours.
    //
    // Mirrors VendorModel.isOpen() (used by the home screen restaurant
    // card) so both screens agree on overnight hours. The previous version
    // here parsed both ends of a slot against the *same* calendar date with
    // no midnight-crossing adjustment at all, so an overnight slot like
    // 22:00–02:00 produced an inverted (end before start) range that could
    // never match — that slot could never show as "open", even minutes
    // after it started. It also never checked yesterday's slots, so a
    // currently-active overnight slot that began the day before (e.g. it's
    // 1am and the slot opened at 10pm yesterday) was invisible here even
    // though the home screen correctly recognized it as open.
    for (var element in widget.vendorModel.workingHours) {
      if (day == element.day.toString()) {
        for (var slot in (element.timeslot ?? [])) {
          if (slot.from == null || slot.to == null) continue;
          final start =
              DateFormat("dd-MM-yyyy HH:mm").parse("$date ${slot.from}");
          var end = DateFormat("dd-MM-yyyy HH:mm").parse("$date ${slot.to}");
          if (!end.isAfter(start)) {
            // Slot crosses midnight — it actually ends tomorrow.
            end = end.add(const Duration(days: 1));
          }
          if (isCurrentDateInRange(start, end)) {
            activeEnd = end;
            scheduleOpen = true;
            _closingAtLabel = 'Closes at ${DateFormat('h:mm a').format(end)}';
          }
        }
      }
    }
    if (!scheduleOpen) {
      // Check yesterday's slots that cross midnight into today.
      for (var element in widget.vendorModel.workingHours) {
        if (yesterdayDay == element.day.toString()) {
          for (var slot in (element.timeslot ?? [])) {
            if (slot.from == null || slot.to == null) continue;
            final start = DateFormat("dd-MM-yyyy HH:mm")
                .parse("$yesterdayDate ${slot.from}");
            var end = DateFormat("dd-MM-yyyy HH:mm")
                .parse("$yesterdayDate ${slot.to}");
            if (end.isAfter(start)) {
              // Doesn't cross midnight, so it never reaches today.
              continue;
            }
            end = end.add(const Duration(days: 1));
            if (isCurrentDateInRange(start, end)) {
              activeEnd = end;
              scheduleOpen = true;
              _closingAtLabel = 'Closes at ${DateFormat('h:mm a').format(end)}';
            }
          }
        }
      }
    }

    // No working hours configured → treat as always schedulable (admin toggle
    // alone decides availability).
    final bool hasSchedule = widget.vendorModel.workingHours.isNotEmpty;
    if (!hasSchedule) scheduleOpen = true;

    // Step 2: Final open state = admin toggle AND within schedule.
    //
    // Case 1 – inside hours  + toggle ON  → isOpen = true  ("Open • Closes at X")
    // Case 2 – inside hours  + toggle OFF → isOpen = false ("Currently Closed" + "not accepting orders")
    // Case 3 – outside hours + toggle ON  → isOpen = false ("Currently Closed" + "Opens at X")
    // Case 4 – outside hours + toggle OFF → isOpen = false ("Currently Closed" + "not accepting orders")
    isOpen = widget.vendorModel.reststatus && scheduleOpen;

    // Step 3: Compute the subtitle shown beneath "Currently Closed".
    if (!isOpen) {
      _closingAtLabel = null;
      activeEnd = null;
      if (widget.vendorModel.reststatus && hasSchedule) {
        // Case 3: admin ON but outside schedule → tell user when it next opens.
        _nextOpenLabel = _findNextOpenLabel(now, day, date);
      }
      // Cases 2 & 4: _nextOpenLabel stays null; UI shows "not accepting orders".
    }

    setState(() {});
    if (activeEnd != null && isOpen) {
      _startClosingCountdown(activeEnd);
    }
  }

  String? _findNextOpenLabel(
      DateTime now, String todayName, String todayDateStr) {
    // Check remaining slots today (start time still in the future)
    for (var element in widget.vendorModel.workingHours) {
      if (element.day == todayName) {
        for (var slot in element.timeslot ?? []) {
          if (slot.from == null) continue;
          try {
            final start = DateFormat("dd-MM-yyyy HH:mm")
                .parse("$todayDateStr ${slot.from}");
            if (start.isAfter(now)) {
              return 'Opens today at ${DateFormat('h:mm a').format(start)}';
            }
          } catch (_) {}
        }
      }
    }
    // Check the next 7 days
    for (int offset = 1; offset <= 7; offset++) {
      final nextDate = now.add(Duration(days: offset));
      final nextDayName = DateFormat('EEEE', 'en_US').format(nextDate);
      final nextDateStr = DateFormat('dd-MM-yyyy').format(nextDate);
      for (var element in widget.vendorModel.workingHours) {
        if (element.day == nextDayName) {
          final slots = (element.timeslot ?? [])
              .where((s) => s.from != null)
              .toList()
            ..sort((a, b) => (a.from ?? '').compareTo(b.from ?? ''));
          if (slots.isNotEmpty) {
            try {
              final start = DateFormat("dd-MM-yyyy HH:mm")
                  .parse("$nextDateStr ${slots.first.from}");
              final dayLabel = offset == 1 ? 'tomorrow' : nextDayName;
              return 'Opens $dayLabel at ${DateFormat('h:mm a').format(start)}';
            } catch (_) {}
          }
        }
      }
    }
    return null;
  }

  void _startClosingCountdown(DateTime closingTime) {
    _closingCountdownTimer?.cancel();
    final remaining = closingTime.difference(DateTime.now());
    if (remaining.inMinutes < 60 && remaining.inSeconds > 0) {
      _closingInNotifier.value = remaining;
      _closingCountdownTimer =
          Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        final r = closingTime.difference(DateTime.now());
        if (r.inSeconds <= 0) {
          timer.cancel();
          // isOpen flips at most once per countdown (rare) — this stays a
          // real setState so the many other isOpen-reading sections update.
          setState(() {
            isOpen = false;
          });
          _closingInNotifier.value = null;
        } else {
          _closingInNotifier.value = r;
        }
      });
    }
  }

  timeShowBottomSheet(BuildContext context) {
    return showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        isDismissible: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(30),
          ),
        ),
        clipBehavior: Clip.antiAliasWithSaveLayer,
        builder: (context) => FractionallySizedBox(
              heightFactor: 0.70,
              child: StatefulBuilder(builder: (context1, setState) {
                return Scaffold(
                  backgroundColor: isDarkMode(context)
                      ? AppThemeData.surfaceDark
                      : AppThemeData.surface,
                  body: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Center(
                            child: Container(
                              width: 134,
                              height: 5,
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: ShapeDecoration(
                                color: isDarkMode(context)
                                    ? AppThemeData.grey50
                                    : AppThemeData.grey800,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            shrinkWrap: true,
                            physics: const BouncingScrollPhysics(),
                            itemCount: widget.vendorModel.workingHours.length,
                            itemBuilder: (context, dayIndex) {
                              WorkingHoursModel workingHours =
                                  widget.vendorModel.workingHours[dayIndex];
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "${workingHours.day}",
                                      textAlign: TextAlign.start,
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: 16,
                                        overflow: TextOverflow.ellipsis,
                                        fontFamily: AppThemeData.semiBold,
                                        color: isDarkMode(context)
                                            ? AppThemeData.grey50
                                            : AppThemeData.grey900,
                                      ),
                                    ),
                                    const SizedBox(
                                      height: 10,
                                    ),
                                    workingHours.timeslot == null ||
                                            workingHours.timeslot!.isEmpty
                                        ? const SizedBox()
                                        : ListView.builder(
                                            shrinkWrap: true,
                                            physics:
                                                const NeverScrollableScrollPhysics(),
                                            itemCount:
                                                workingHours.timeslot!.length,
                                            itemBuilder: (context, timeIndex) {
                                              Timeslot timeSlotModel =
                                                  workingHours
                                                      .timeslot![timeIndex];
                                              return Padding(
                                                padding:
                                                    const EdgeInsets.all(8.0),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Expanded(
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                vertical: 10),
                                                        decoration: BoxDecoration(
                                                            borderRadius:
                                                                const BorderRadius
                                                                    .all(Radius
                                                                        .circular(
                                                                            12)),
                                                            border: Border.all(
                                                                color: isDarkMode(
                                                                        context)
                                                                    ? AppThemeData
                                                                        .grey400
                                                                    : AppThemeData
                                                                        .grey200)),
                                                        child: Center(
                                                          child: Text(
                                                            timeSlotModel.from
                                                                .toString(),
                                                            style: TextStyle(
                                                              fontFamily:
                                                                  AppThemeData
                                                                      .medium,
                                                              fontSize: 14,
                                                              color: isDarkMode(
                                                                      context)
                                                                  ? AppThemeData
                                                                      .grey400
                                                                  : AppThemeData
                                                                      .grey500,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(
                                                      width: 10,
                                                    ),
                                                    Expanded(
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                vertical: 10),
                                                        decoration: BoxDecoration(
                                                            borderRadius:
                                                                const BorderRadius
                                                                    .all(Radius
                                                                        .circular(
                                                                            12)),
                                                            border: Border.all(
                                                                color: isDarkMode(
                                                                        context)
                                                                    ? AppThemeData
                                                                        .grey400
                                                                    : AppThemeData
                                                                        .grey200)),
                                                        child: Center(
                                                          child: Text(
                                                            timeSlotModel.to
                                                                .toString(),
                                                            style: TextStyle(
                                                              fontFamily:
                                                                  AppThemeData
                                                                      .medium,
                                                              fontSize: 14,
                                                              color: isDarkMode(
                                                                      context)
                                                                  ? AppThemeData
                                                                      .grey400
                                                                  : AppThemeData
                                                                      .grey500,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    )
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ));
  }

  bool isCurrentDateInRange(DateTime startDate, DateTime endDate) {
    print(startDate);
    print(endDate);
    final currentDate = DateTime.now();
    print(currentDate);
    return currentDate.isAfter(startDate) && currentDate.isBefore(endDate);
  }

  // Dynamic multi-source blend (2026-07-17 rewrite) - single source of
  // truth for "this category's products, in display order", used by both
  // the item count and the itemBuilder below. Uses the same cross-source
  // merged score as _recommendedForYouProducts (computeMergedScores) -
  // deliberately NOT split into separate "Stage 0"/"Stage 1" code paths:
  // for a new/signed-out user the 'preference' source contributes nothing,
  // so the remaining sources (bestSeller/mustTry/similar/discovery) alone
  // already produce a sensible bias; once the user has real history,
  // preference blends back in automatically via the same merge.
  // reorderByScore's own cold-start guard (all-zero -> untouched natural
  // order) still applies for a genuinely brand-new restaurant with no
  // signal at all.
  List<ProductModel> _productsForCategory(String? categoryId) {
    final base =
        productList.where((p0) => p0.categoryID == categoryId).toList();
    final ctx = _recoContext;
    if (ctx == null) return base;
    final scores = RecommendationEngine.computeMergedScores(ctx);
    return RecommendationEngine.reorderByScore(base, scores);
  }

  productListView() {
    return Container(
      color: isDarkMode(context) ? AppThemeData.grey900 : Colors.transparent,
      padding: EdgeInsets.zero,
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: vendorCategoryList.length,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          VendorCategoryModel vendorCategoryModel = vendorCategoryList[index];
          final categoryId = vendorCategoryModel.id.toString();
          return Card(
            key: _categoryKeyFor(categoryId),
            elevation: isDarkMode(context) ? 0 : 1,
            shadowColor: isDarkMode(context)
                ? Colors.transparent
                : Colors.black.withOpacity(0.05),
            color: isDarkMode(context)
                ? AppThemeData.grey800.withOpacity(0.3)
                : Colors.white,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: isDarkMode(context)
                  ? BorderSide.none
                  : const BorderSide(color: Color(0xFFEEEEEE), width: 0.5),
            ),
            child: Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: _categoryTileKey(categoryId),
                onExpansionChanged: (_) =>
                    _manuallyToggledCategoryIds.add(categoryId),
                childrenPadding: EdgeInsets.zero,
                tilePadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero),
                initiallyExpanded:
                    _isCategoryExpanded(categoryId, defaultValue: false),
                collapsedBackgroundColor: isDarkMode(context)
                    ? AppThemeData.grey800.withOpacity(0.5)
                    : Colors.white,
                backgroundColor: isDarkMode(context)
                    ? AppThemeData.grey800.withOpacity(0.3)
                    : Colors.white,
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDarkMode(context)
                            ? AppThemeData.primary500.withOpacity(0.2)
                            : AppThemeData.primary500.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.restaurant_menu,
                        size: 20,
                        color: AppThemeData.primary500,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vendorCategoryModel.title.toString(),
                            style: TextStyle(
                              fontSize: 18,
                              fontFamily: AppThemeData.semiBold,
                              color: isDarkMode(context)
                                  ? AppThemeData.grey50
                                  : AppThemeData.grey900,
                            ),
                          ),
                          Text(
                            "${_productsForCategory(vendorCategoryModel.id).length} items",
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: AppThemeData.regular,
                              color: isDarkMode(context)
                                  ? AppThemeData.grey400
                                  : AppThemeData.grey600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // ExpansionTile builds `children` unconditionally regardless
                // of collapsed/expanded visual state - the windowed
                // auto-expand system above (_updateCategoryExpansionWindow,
                // _categoryExpandBuffer) only ever controlled the animation,
                // never whether this category's product cards (and their
                // images) actually got built. On a large menu that meant
                // EVERY category's ListView.separated - and every product
                // card's image request - fired immediately on load, in list
                // order, regardless of scroll position: scrolling straight to
                // item ~180 still queued images 1-179 first. Gating on the
                // same expansion state the window already maintains means
                // only categories within the ±_categoryExpandBuffer window
                // (or manually expanded) ever build their product cards.
                children: _isCategoryExpanded(categoryId, defaultValue: false)
                    ? [
                        Builder(builder: (context) {
                          final categoryProducts =
                              _productsForCategory(vendorCategoryModel.id);
                          return ListView.separated(
                            itemCount: categoryProducts.length,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(top: 4, bottom: 4),
                            separatorBuilder: (context, index) => Divider(
                              height: 1,
                              thickness: 1,
                              color: isDarkMode(context)
                                  ? AppThemeData.grey800.withOpacity(0.5)
                                  : AppThemeData.grey200,
                              indent: 16,
                              endIndent: 16,
                            ),
                            itemBuilder: (context, index) {
                              return _buildProductCard(categoryProducts[index]);
                            },
                          );
                        }),
                      ]
                    : const <Widget>[],
              ),
            ),
          );
        },
      ),
    );
  }

  // The single per-dish card used everywhere a product is listed: the
  // categorized menu (productListView above) and the dish-search results
  // list (_buildDishSearchResultsList) both render through here, so the two
  // never visually drift apart. highlightQuery bolds a matched substring in
  // the name for search results only — normal menu callers omit it.
  Widget _buildProductCard(ProductModel productModel,
      {String? highlightQuery}) {
    String price = "0.0";
    String disPrice = "0.0";
    List<String> selectedVariants = [];
    List<String> selectedIndexVariants = [];
    List<String> selectedIndexArray = [];
    final _ia = productModel.itemAttributes;
    if (_ia != null) {
      final _attrs = _ia.attributes ?? [];
      for (int _ai = 0; _ai < _attrs.length; _ai++) {
        final _opts = _attrs[_ai].attributeOptions;
        if (_opts != null && _opts.isNotEmpty) {
          selectedVariants.add(_opts[0].toString());
          selectedIndexVariants.add('$_ai _${_opts[0]}');
          selectedIndexArray.add('${_ai}_0');
        }
      }
      final _variants = _ia.variants;
      if (_variants != null) {
        final _match =
            _variants.where((e) => e.variant_sku == selectedVariants.join('-'));
        if (_match.isNotEmpty) {
          price = productCommissionPrice(_match.first.variant_price ?? '0');
          disPrice = "0";
        }
      }
    } else {
      price = productCommissionPrice(productModel.price.toString());
      disPrice = double.parse(productModel.disPrice.toString()) <= 0
          ? "0"
          : productCommissionPrice(productModel.disPrice.toString());
    }

    final bool _pHasRestrictions = productModel.deliveryOption ||
        productModel.takeaway ||
        productModel.dineIn;

    bool showAddButton = !_pHasRestrictions ||
        (_isDineAwayMode &&
            _dineAwaySubMode == 'Takeaway' &&
            productModel.takeaway) ||
        (_isDineAwayMode &&
            _dineAwaySubMode == 'Dining' &&
            productModel.dineIn) ||
        (!_isDineAwayMode && productModel.deliveryOption);

    bool hasVariants = productModel.itemAttributes != null &&
        productModel.itemAttributes!.attributes!.isNotEmpty;
    bool hasAddOns = productModel.addOnsTitle.isNotEmpty;
    bool hasProductAttr = productModel.productAttributes.isNotEmpty &&
        productModel.productAttributes
            .any((c) => c.options.any((o) => o.enabled));

    String unavailabilityMessage = "";
    if (_pHasRestrictions) {
      if (_isDineAwayMode &&
          _dineAwaySubMode == 'Takeaway' &&
          !productModel.takeaway) {
        unavailabilityMessage = "Not available for Takeaway";
      } else if (_isDineAwayMode &&
          _dineAwaySubMode == 'Dining' &&
          !productModel.dineIn) {
        unavailabilityMessage = "Not available for Dining";
      } else if (!_isDineAwayMode && !productModel.deliveryOption) {
        unavailabilityMessage = "Not available for Delivery";
      }
    }

    // Build the lookup id.
    // Variant products may be stored as "id~variantId" even when
    // the listing-level productModel still has variant_info==null
    // (before the user explicitly selects a variant). We fall back
    // to a prefix search so the quantity badge always shows.
    CartProduct? cartProduct;
    if (productModel.variant_info != null) {
      final cartId = productModel.id +
          "~" +
          productModel.variant_info!.variant_id.toString();
      cartProduct = cartProducts.firstWhereOrNull((p) => p.id == cartId);
    } else {
      // Exact match first (no-variant products stored as "id~")
      final exactId = "${productModel.id}~";
      cartProduct = cartProducts.firstWhereOrNull((p) => p.id == exactId);
      // Fallback: variant was auto-assigned on add — match by prefix
      cartProduct ??= cartProducts
          .firstWhereOrNull((p) => p.id.startsWith("${productModel.id}~"));
    }

    return Column(children: [
      Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            _showProductQuickView(productModel);
          },
          child: Padding(
            // vertical 16 (2026-07-20, was 10) - explicit request: with the
            // confidence badge/order-count block removed from this card,
            // rows read as too congested/cramped against each other; more
            // breathing room per row here directly grows every list item's
            // height.
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── LEFT: Details ──────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Veg / Non-veg indicator (icon only)
                      if (sectionConstantModel != null &&
                          sectionConstantModel!.isProductDetails == true)
                        SvgPicture.asset(
                          productModel.nonveg
                              ? "assets/icons/ic_nonveg.svg"
                              : "assets/icons/ic_veg.svg",
                          height: 18,
                          width: 18,
                        ),
                      if (sectionConstantModel != null &&
                          sectionConstantModel!.isProductDetails == true)
                        const SizedBox(height: 5),
                      // Item name
                      (highlightQuery != null && highlightQuery.isNotEmpty)
                          ? _highlightedName(
                              productModel.name.toString(),
                              highlightQuery,
                              TextStyle(
                                // 18 (2026-07-20, was 16) - explicit
                                // readability request, kept in sync with
                                // the non-highlighted Text below.
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: isDarkMode(context)
                                    ? AppThemeData.grey50
                                    : const Color(0xFF1A1A1A),
                                fontFamily: AppThemeData.semiBold,
                              ),
                            )
                          : Text(
                              productModel.name.toString(),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: isDarkMode(context)
                                    ? AppThemeData.grey50
                                    : const Color(0xFF1A1A1A),
                                fontFamily: AppThemeData.semiBold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                      const SizedBox(height: 4),
                      // Description
                      if (productModel.description != null &&
                          productModel.description!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            productModel.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              // 14 (2026-07-20, was 12) - explicit
                              // readability request.
                              fontSize: 14,
                              height: 1.4,
                              color: isDarkMode(context)
                                  ? AppThemeData.grey400
                                  : AppThemeData.grey600,
                              fontFamily: AppThemeData.regular,
                            ),
                          ),
                        ),
                      // Confidence badge (green bar + label) restored here
                      // (2026-07-22, explicit requirement) - reversing the
                      // 2026-07-20 removal. This card is the full
                      // category-grouped menu list (and dish search
                      // results, via the same shared _buildProductCard).
                      // Reads the exact same _confidenceScores map the
                      // carousel cards use - no new computation, no new
                      // Firestore reads, same null-safe widget (renders
                      // nothing when this product has no qualifying
                      // signal, same as everywhere else it's used).
                      RecommendationConfidenceBadge(
                        confidence: _confidenceScores[productModel.id],
                      ),
                      // Price
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (productModel.productAttributes.isNotEmpty &&
                              productModel.productAttributes.any((c) => c
                                  .options
                                  .any((o) => o.enabled && o.price > 0)))
                            Text(
                              'Starts From'.tr(),
                              style: TextStyle(
                                fontSize: 10,
                                color: isDarkMode(context)
                                    ? AppThemeData.grey400
                                    : AppThemeData.grey500,
                              ),
                            ),
                          Row(
                            children: [
                              disPrice == "" || disPrice == "0"
                                  ? Text(
                                      amountShow(amount: price),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: AppThemeData.primary500,
                                      ),
                                    )
                                  : Row(
                                      children: [
                                        Text(
                                          amountShow(amount: disPrice),
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: AppThemeData.primary500,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          amountShow(amount: price),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isDarkMode(context)
                                                ? AppThemeData.grey400
                                                : AppThemeData.grey500,
                                            decoration:
                                                TextDecoration.lineThrough,
                                          ),
                                        ),
                                      ],
                                    ),
                              if (disPrice != "" && disPrice != "0")
                                Container(
                                  margin: const EdgeInsets.only(left: 5),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppThemeData.primary500
                                        .withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    "${calculateDiscount(price, disPrice)}% OFF",
                                    style: TextStyle(
                                      color: AppThemeData.primary500,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      // Unavailability badge
                      if (unavailabilityMessage.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 3, horizontal: 6),
                            decoration: BoxDecoration(
                              color: AppThemeData.danger300.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: AppThemeData.danger300.withOpacity(0.5),
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              unavailabilityMessage.tr(),
                              style: TextStyle(
                                color: AppThemeData.danger300,
                                fontFamily: AppThemeData.medium,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // ── RIGHT: Image + ADD ─────────────────
                SizedBox(
                  width: 150,
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: (showAddButton &&
                                  (isOpen ||
                                      sectionConstantModel!.serviceTypeFlag ==
                                          "ecommerce-service") &&
                                  (MyAppState.currentUser != null ||
                                      sectionConstantModel!.serviceTypeFlag ==
                                          "ecommerce-service"))
                              ? 20
                              : 0,
                        ),
                        child: Hero(
                          tag: "product_${productModel.id}",
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            // Bigger square (2026-07-20, explicit product
                            // request - stays square, NOT portrait) - was
                            // 130x130, now 150x150. Bigger image also grows
                            // the row's own height to match, since the
                            // Row's crossAxisAlignment.start sizes itself
                            // to its tallest child.
                            child: _LazyDishImage(
                              cacheKey: productModel.id,
                              imageUrl: productModel.photo.toString(),
                              height: 150,
                              width: 150,
                            ),
                          ),
                        ),
                      ),
                      // ADD button or stepper pill
                      if (showAddButton &&
                          (isOpen ||
                              sectionConstantModel!.serviceTypeFlag ==
                                  "ecommerce-service") &&
                          (MyAppState.currentUser != null ||
                              sectionConstantModel!.serviceTypeFlag ==
                                  "ecommerce-service"))
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(scale: animation, child: child),
                          child: cartProduct == null ||
                                  cartProduct.quantity == 0
                              ? _AnimatedAddButton(
                                  key: ValueKey('add_${productModel.id}'),
                                  hasOptions: hasVariants ||
                                      hasAddOns ||
                                      hasProductAttr,
                                  onTap: () => _handleAddToCart(productModel),
                                )
                              : _buildHorizontalQuantityPill(
                                  context, cartProduct),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      if (_pairsWellWithProductId == productModel.id &&
          !_pairsWellWithFromCarousel)
        _buildPairsWellWithPanel(context, productModel),
    ]);
  }

  Widget _buildHorizontalQuantityPill(
      BuildContext context, CartProduct cartProduct) {
    return Container(
      key: const ValueKey('qty_pill'),
      height: 34,
      decoration: BoxDecoration(
        color: AppThemeData.primary500,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: AppThemeData.primary500.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Minus button
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                bottomLeft: Radius.circular(10),
              ),
              onTap: () => _decrementQuantity(cartProduct),
              child: SizedBox(
                width: 34,
                height: 34,
                child: const Icon(Icons.remove_rounded,
                    color: Colors.white, size: 15),
              ),
            ),
          ),
          // Divider
          Container(
              width: 1, height: 18, color: Colors.white.withValues(alpha: 0.3)),
          // Quantity label
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: child,
            ),
            child: SizedBox(
              key: ValueKey(cartProduct.quantity),
              width: 34,
              height: 34,
              child: Center(
                child: Text(
                  cartProduct.quantity.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontFamily: AppThemeData.bold,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
          // Divider
          Container(
              width: 1, height: 18, color: Colors.white.withValues(alpha: 0.3)),
          // Plus button
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(10),
                bottomRight: Radius.circular(10),
              ),
              onTap: () => _incrementQuantity(cartProduct),
              child: SizedBox(
                width: 34,
                height: 34,
                child: const Icon(Icons.add_rounded,
                    color: Colors.white, size: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to calculate discount percentage
  String calculateDiscount(String originalPrice, String discountedPrice) {
    double original = double.tryParse(originalPrice) ?? 0;
    double discounted = double.tryParse(discountedPrice) ?? 0;
    if (original <= 0 || discounted <= 0) return "0";

    double discount = ((original - discounted) / original) * 100;
    return discount.toStringAsFixed(0);
  }

  // Different approach: Local state management with immediate UI updates
  Future<void> _decrementQuantity(CartProduct cartProduct) async {
    if (!mounted || !_cartReady) return;

    final index = cartProducts.indexWhere((p) => p.id == cartProduct.id);
    if (index == -1) return;

    // Decide the operation BEFORE mutating the list so the DB call matches.
    final wasLastItem = cartProducts[index].quantity <= 1;

    setState(() {
      if (!wasLastItem) {
        cartProducts[index].quantity = cartProducts[index].quantity - 1;
      } else {
        cartProducts.removeAt(index);
        // Item fully removed from cart — close its "pairs well with" panel
        // too, if it was the one currently expanded.
        final removedProductId = cartProduct.id.split('~').first;
        if (_pairsWellWithProductId == removedProductId) {
          _pairsWellWithProductId = null;
          _pairsWellWithFromCarousel = false;
        }
        // Un-pin it from the sticky "added" list too (2026-07-26) - this is
        // the one and only place an id leaves _pairsWellWithDisplayOrder now.
        _pairsWellWithDisplayOrder.remove(removedProductId);
      }
    });

    try {
      if (!wasLastItem) {
        await cartDatabase.updateProduct(cartProducts[index]);
      } else {
        await cartDatabase.removeProduct(cartProduct.id);
      }
    } catch (e) {
      // Revert: restore item at its original position, not appended at the end.
      setState(() {
        if (wasLastItem) {
          cartProducts.insert(index, cartProduct.copyWith(quantity: 1));
        } else {
          cartProducts[index].quantity = cartProducts[index].quantity + 1;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update cart. Please try again.'.tr()),
            backgroundColor: AppThemeData.primary500,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // Different approach: Local state management with immediate UI updates
  Future<void> _incrementQuantity(CartProduct cartProduct) async {
    if (!mounted || !_cartReady) return;

    print(
        'Incrementing quantity for product: ${cartProduct.id}, current quantity: ${cartProduct.quantity}');

    // Find the cart product in the list
    final index = cartProducts.indexWhere((p) => p.id == cartProduct.id);
    if (index == -1) {
      print('Cart product not found in list');
      return;
    }

    // Immediate UI update
    setState(() {
      cartProducts[index].quantity = cartProducts[index].quantity + 1;
    });

    try {
      // Update in database
      await cartDatabase.updateProduct(cartProducts[index]);
      print('Quantity updated successfully in database');
    } catch (e) {
      print('Error in _incrementQuantity: $e');
      // Revert UI changes on error
      setState(() {
        cartProducts[index].quantity = cartProducts[index].quantity - 1;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update cart. Please try again.'.tr()),
            backgroundColor: AppThemeData.primary500,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // Method to handle adding product to cart with options dialog
  Future<void> _handleAddToCart(ProductModel productModel,
      {bool showPairsWellWith = true}) async {
    if (MyAppState.currentUser == null) {
      ShowToastDialog.showToast("Please login to add to cart".tr());
      return;
    }

    // Check if product has variants or add-ons
    bool hasVariants = productModel.itemAttributes != null &&
        productModel.itemAttributes!.attributes!.isNotEmpty;
    bool hasAddOns = productModel.addOnsTitle.isNotEmpty;
    bool hasProductAttributes = productModel.productAttributes.isNotEmpty &&
        productModel.productAttributes
            .any((c) => c.options.any((o) => o.enabled));

    if (hasVariants || hasAddOns || hasProductAttributes) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        useSafeArea: true,
        builder: (BuildContext ctx) {
          return ProductOptionsDialog(
            productModel: productModel,
            onAddToCart: (ProductModel updatedProduct, double totalPrice,
                int quantity) async {
              Navigator.of(ctx).pop();
              await _addProductToCart(updatedProduct);
              if (showPairsWellWith) _showPairsWellWith(productModel);
            },
          );
        },
      );
    } else {
      // No variants or add-ons, add directly to cart
      await _addProductToCart(productModel);
      if (showPairsWellWith) _showPairsWellWith(productModel);
    }
  }

  // Tapping a product card opens this quick-view sheet (image, name, price,
  // description, then any variants/add-ons, then a quantity stepper) instead
  // of pushing the full ProductDetailsScreen page. Viewing doesn't require
  // login — only the actual add does, matching _handleAddToCart below.
  void _showProductQuickView(ProductModel productModel,
      {bool fromCarousel = false}) {
    // Wired 2026-07-20 - same payload shape as the legacy
    // ProductDetailsScreen's _trackProductViewed, which is the only place
    // kEvtProductViewed was ever fired from before this - this screen
    // (the one every "tap a product" path on the actual menu/recommendation
    // cards opens) never recorded a single view, so productViewCounts
    // stayed permanently 0 for every real customer using the current UI.
    BehaviorTracker.track(kEvtProductViewed, {
      'productId': productModel.id,
      'vendorId': productModel.vendorID,
      'categoryId': productModel.categoryID,
      // Cuisine preference signal (2026-07-27) - vendor object already in
      // memory here, no new Firestore read. See BehaviorTracker's
      // kEvtProductViewed case for the weighting.
      'cuisineIds': widget.vendorModel.cuisineIds,
    });
    // Restaurant Engagement session counters (Phase 2, 2026-07-24) - see
    // _trackRestaurantSessionEnded's own doc comment. Every real "tap a
    // product" path on this screen funnels through this one method (same
    // choke point kEvtProductViewed above already relies on), so this is
    // the single place both counters need to live.
    _sessionProductViewCount++;
    if (productModel.categoryID.isNotEmpty) {
      _sessionCategoriesBrowsed.add(productModel.categoryID);
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (BuildContext ctx) {
        return ProductOptionsDialog(
          productModel: productModel,
          showProductInfo: true,
          onAddToCart: (ProductModel updatedProduct, double totalPrice,
              int quantity) async {
            if (MyAppState.currentUser == null) {
              ShowToastDialog.showToast("Please login to add to cart".tr());
              return;
            }
            Navigator.of(ctx).pop();
            for (int i = 0; i < quantity; i++) {
              await _addProductToCart(updatedProduct);
            }
            _showPairsWellWith(productModel, fromCarousel: fromCarousel);
          },
        );
      },
    );
  }

  // Expands the "pairs well with" panel inline below the just-added product's
  // card. Only one panel is open at a time. Quick-adding a suggested item
  // from within the panel does not chain into another panel for that item.
  //
  // Switching the anchor product (e.g. adding a second, different item from
  // the main menu list while a panel is already open) does NOT reset
  // _pairsWellWithDisplayOrder (2026-07-26, was a hard reset here) - that
  // list is now sticky-added-items-only (see _resolvedPairsWellWithDisplay),
  // so clearing it here would silently un-track anything the user already
  // added from the panel being replaced.
  void _showPairsWellWith(ProductModel productModel, {bool fromCarousel = false}) {
    if (!mounted) return;
    // Combo Recommendation Rules (2026-07-19): a combo already represents a
    // complete meal - showing another combo, or re-suggesting products
    // already bundled inside this one, adds little value and risks reducing
    // conversion. Add to Cart simply completes with no pairing popup.
    if (productModel.isCombo) return;
    if (_resolvedPairsWellWith(productModel).isEmpty) return;
    setState(() {
      _pairsWellWithProductId = productModel.id;
      _pairsWellWithFromCarousel = fromCarousel;
    });
  }

  // Resolves productModel.recommendedProductIds against allProductList (the
  // restaurant's already-loaded, unfiltered product list) — zero extra
  // Firestore reads. Anything no longer approved/published/same-vendor is
  // dropped automatically.
  //
  // Phase 2 enhancement (2026-07-17): the vendor-configured subset is
  // reordered by score (vendor's own order as the tie-break, so vendor
  // intent still wins between equally-scored items), and if that leaves
  // fewer than 5 suggestions - including zero vendor-configured pairs - the
  // remainder is filled from the rest of the menu via
  // RecommendationEngine.fillPairsWellWith (cross-sell frequency ->
  // preference -> best-sellers). Falls back to the plain vendor-configured
  // list, unreordered/unfilled, whenever _recoContext hasn't loaded yet -
  // same behavior Phase 1 always had.
  // Shared by _resolvedPairsWellWith and _pairsWellWithVendorConfiguredIds
  // so the "which products are the vendor's own configured picks for this
  // product" filter is defined exactly once.
  List<ProductModel> _vendorConfiguredPairsFor(ProductModel productModel) {
    final byId = {for (final p in allProductList) p.id: p};
    final vendorConfigured = <ProductModel>[];
    for (final id in productModel.recommendedProductIds) {
      final p = byId[id];
      if (p == null) continue;
      if (p.id == productModel.id) continue;
      if (p.vendorID != productModel.vendorID) continue;
      if (p.productStatus != 'approved') continue;
      if (p.publish != true) continue;
      vendorConfigured.add(p);
    }
    return vendorConfigured;
  }

  // Category-Based Pairing Configuration (2026-07-21) - admin-configured
  // per-category candidate GENERATION, deliberately isolated from candidate
  // RANKING (RecommendationEngine.fillPairsWellWith, untouched below) so a
  // future AI/data-driven pairing generator (see TODO further down) can
  // replace just this step without redesigning the engine or this call site.
  //
  // Priority per category (NOT a global switch): if the triggering
  // product's own category has admin-configured pairingCategoryIds, THIS
  // takes over as the sole eligibility gate for both candidatePool and the
  // vendor's own manual picks, and the existing Business Context pairing
  // signal (pairingContextScore) is skipped entirely for this request. If
  // the category has nothing configured yet, this falls through to
  // TODAY'S EXACT existing behavior, byte-for-byte - zero regression for
  // every restaurant until an admin explicitly opts a category in. Once
  // every category across every restaurant is eventually configured, the
  // Business Context fallback branch can be retired in a future release.
  //
  // Same-category suggestions (2026-07-22, opt-in): pairingCategoryIds can
  // now include the category's own ID (admin panel no longer blocks
  // selecting it) - `allowed.contains(p.categoryID)` below then naturally
  // includes same-category products with zero extra code here. Off by
  // default for every category; an admin has to explicitly check their own
  // category in its own Pairing Categories list to enable it.
  ({List<ProductModel> candidatePool, List<ProductModel> vendorConfigured, Map<String, double> pairingContextScores})
      _pairsWellWithCandidates(ProductModel productModel, List<ProductModel> candidatePool,
          List<ProductModel> vendorConfigured, RestaurantRecommendationContext ctx) {
    final sourceCategory = productCategoryById[productModel.categoryID];
    final pairingCategoryIds = sourceCategory?.pairingCategoryIds ?? const [];

    if (pairingCategoryIds.isNotEmpty) {
      final allowed = pairingCategoryIds.toSet();
      return (
        candidatePool: candidatePool.where((p) => allowed.contains(p.categoryID)).toList(),
        // Vendor Recommendation Preference must never bypass the admin
        // gate - filtered here too, before fillPairsWellWith ever sees it,
        // so it can only rank within the allowed categories, never around them.
        vendorConfigured: vendorConfigured.where((p) => allowed.contains(p.categoryID)).toList(),
        pairingContextScores: const {},
      );
    }

    // Fallback: existing Business Context pairing signal, unchanged.
    final pairingContextScores = {
      for (final p in candidatePool)
        p.id: RecommendationEngine.pairingContextScore(p, productModel, ctx)
    };
    return (candidatePool: candidatePool, vendorConfigured: vendorConfigured, pairingContextScores: pairingContextScores);
  }

  List<ProductModel> _resolvedPairsWellWith(ProductModel productModel) {
    var vendorConfigured = _vendorConfiguredPairsFor(productModel);

    final ctx = _recoContext;
    if (ctx == null) return vendorConfigured;

    var candidatePool = allProductList
        .where((p) =>
            p.id != productModel.id &&
            p.vendorID == productModel.vendorID &&
            p.productStatus == 'approved' &&
            p.publish == true)
        .toList();

    final pairingResolution = _pairsWellWithCandidates(productModel, candidatePool, vendorConfigured, ctx);
    candidatePool = pairingResolution.candidatePool;
    vendorConfigured = pairingResolution.vendorConfigured;

    // normalizedMergedScores (2026-07-18, was computeMergedScores) - the
    // score that RANKS vendor-configured items here must be the exact same
    // score the confidence badge on those same cards DISPLAYS
    // (_buildPairsWellWithPanel below), or "Product A above Product B" and
    // "B shows higher confidence" could both be simultaneously true. See
    // RecommendationEngine.normalizedMergedScores' doc comment.
    final mergedScores = RecommendationEngine.normalizedMergedScores(ctx);
    final preferenceScores = RecommendationEngine.scoreBySource(ctx, 'preference');
    final bestSellerScores = RecommendationEngine.scoreBySource(ctx, 'bestSeller');

    // Cart Awareness (2026-07-19) - the triggering product (productModel)
    // stays the PRIMARY context via vendorConfigured above; the rest of
    // the cart is SECONDARY, read straight off the already-live
    // `cartProducts` field (populated by the existing watchProducts
    // stream in didChangeDependencies - no new subscription, no new
    // Firestore/DB read). By the time this runs the just-added product is
    // already IN cartProducts too (onAddToCart calls _addProductToCart
    // before _showPairsWellWith), so excluding "everything in cart" also
    // naturally excludes it, on top of the existing p.id != productModel.id
    // filter above. Cart row ids are "<productId>~<variantId>" (see
    // CartDatabase.addProduct) - split on '~' to recover the base product
    // id fillPairsWellWith/candidatePool/vendorConfigured actually use.
    final cartProductIds = cartProducts
        .where((c) => c.vendorID == productModel.vendorID)
        .map((c) => c.id.split('~').first)
        .toSet();
    final cartCategoryCounts = <String, int>{};
    for (final c in cartProducts) {
      if (c.vendorID != productModel.vendorID) continue;
      final catId = c.category_id;
      if (catId != null && catId.isNotEmpty) {
        cartCategoryCounts[catId] = (cartCategoryCounts[catId] ?? 0) + 1;
      }
      // Combo Content Awareness (2026-07-19) - a combo already in the cart
      // "contains" its child products: suppress recommending them again
      // (duplicate suppression) and count their categories toward
      // saturation too, exactly as if each child were its own cart row.
      // Resolved against allProductList (already loaded for this vendor
      // page, zero new Firestore/DB reads) - CartProduct itself has no
      // isCombo/comboProducts fields, only the full ProductModel does.
      final baseId = c.id.split('~').first;
      final cartProductModel =
          allProductList.firstWhereOrNull((p) => p.id == baseId);
      if (cartProductModel != null && cartProductModel.isCombo) {
        for (final child in cartProductModel.comboProducts) {
          cartProductIds.add(child.productId);
          final childProduct =
              allProductList.firstWhereOrNull((p) => p.id == child.productId);
          if (childProduct != null) {
            cartCategoryCounts[childProduct.categoryID] =
                (cartCategoryCounts[childProduct.categoryID] ?? 0) + 1;
          }
        }
      }
    }

    // Product Context (2026-07-19) - meal-context relevance of each FILLER
    // candidate relative to the triggering product (productModel) alone,
    // via RecommendationEngine.pairingContextScore - the only place in the
    // app that narrows Business Context's cuisine term to the triggering
    // product's own cuisine(s) rather than the restaurant's full cuisine
    // list. Now resolved by _pairsWellWithCandidates above: populated only
    // on the Business-Context-fallback path (category not yet admin-
    // configured); empty on the admin-pairing path, since the admin's own
    // category gate replaces this signal's job for that category.
    // fillPairsWellWith itself stays free of any Firebase/ctx dependency.
    final pairingContextScores = pairingResolution.pairingContextScores;

    return RecommendationEngine.fillPairsWellWith(
      vendorConfigured: vendorConfigured,
      candidatePool: candidatePool,
      mergedScores: mergedScores,
      preferenceScores: preferenceScores,
      bestSellerScores: bestSellerScores,
      crossSellFrequency: ctx.crossSellFrequency,
      pairingContextScores: pairingContextScores,
      cartProductIds: cartProductIds,
      cartCategoryCounts: cartCategoryCounts,
      // Dynamic (2026-07-19), capped at 8 regardless of menu size - see
      // RecommendationEngine.pairingSectionLimitFor's doc comment. This is
      // the ONE place _resolvedPairsWellWith's limit is decided - every
      // caller (tapping a product card on the menu AND the "Add Item"
      // options-dialog flow in _handleAddToCart/_showProductQuickView,
      // both of which call _showPairsWellWith -> this function) shares it,
      // so "Add Product" always shows the exact same ranked suggestions as
      // the normal menu view, never a second computation.
      maxItems: RecommendationEngine.pairingSectionLimitFor(ctx),
    );
  }

  // Presentational wrapper around _resolvedPairsWellWith - see
  // _pairsWellWithDisplayOrder's doc comment for why this exists.
  //
  // _pairsWellWithDisplayOrder now tracks ADDED items only (2026-07-26, was
  // "everything ever shown"). An unadded suggestion is never carried across
  // a switch to a different anchor product - it's always exactly the
  // current anchor's fresh list, so it can neither go stale nor duplicate
  // against that fresh list. Only something the user actually added stays
  // pinned. Tracked ids are added/removed EXPLICITLY only - by onItemAdded
  // (add) and _decrementQuantity's last-unit-removed branch (remove) - never
  // inferred here from [cartProducts] (2026-07-26, was "drop any tracked id
  // no longer in cartProducts", checked on every build). cartProducts is
  // populated by an async DB stream that lags one or more frames behind the
  // optimistic add, so that reactive check was pruning the just-added id
  // right back out before the stream had caught up - the exact bug reported
  // ("product added to cart but invisible from the pairing list"):
  //   1. Render the tracked (added) ids first, in their existing order.
  //   2. Append the current anchor's fresh unadded suggestions, skipping
  //      anything already tracked in step 1.
  List<ProductModel> _resolvedPairsWellWithDisplay(ProductModel productModel) {
    final fresh = _resolvedPairsWellWith(productModel);
    final byId = {for (final p in fresh) p.id: p};

    final result = <ProductModel>[];
    for (final id in _pairsWellWithDisplayOrder) {
      final p = byId[id] ?? allProductList.firstWhereOrNull((x) => x.id == id);
      if (p != null) result.add(p);
    }
    for (final p in fresh) {
      if (!_pairsWellWithDisplayOrder.contains(p.id)) {
        result.add(p);
      }
    }
    return result;
  }

  // The badge-eligible subset of _resolvedPairsWellWith's output - only
  // the vendor's own manually-configured picks, whose display order is now
  // guaranteed to match their displayed confidence (see the mergedScores
  // comment above). Filler/backfilled items (candidatePool entries added
  // when the vendor's own list runs short) are ranked by a fixed PRIORITY
  // chain (cross-sell frequency -> preference -> best-seller, see
  // fillPairsWellWith) rather than a single confidence score, so there is
  // no honest single number to show for them - suppressing their badge
  // entirely (rather than showing an unrelated score) is what keeps
  // "never show A above B while B displays higher confidence" true for
  // every badge that IS shown, everywhere on this panel.
  Set<String> _pairsWellWithVendorConfiguredIds(ProductModel productModel) =>
      _vendorConfiguredPairsFor(productModel).map((p) => p.id).toSet();

  // Renders the panel directly below the top carousels (2026-07-26) for a
  // carousel-triggered add (_pairsWellWithFromCarousel) - see that field's
  // doc comment for why this exists alongside, not instead of,
  // _buildPairsWellWithPanel's own inline spot in the main menu list.
  // Resolves the anchor id against every list this screen might have
  // sourced it from, since a Recommended For You pick isn't guaranteed to
  // also be in allProductList's currently-filtered view (e.g. a different
  // Dining/Takeaway sub-mode).
  Widget _buildCarouselPairsWellWithPanel() {
    final id = _pairsWellWithProductId;
    if (id == null) return const SizedBox.shrink();
    final productModel = allProductList.firstWhereOrNull((p) => p.id == id) ??
        _recommendedForYouProducts.firstWhereOrNull((p) => p.id == id);
    if (productModel == null) return const SizedBox.shrink();
    return _buildPairsWellWithPanel(context, productModel,
        onPageBackground: true);
  }

  // 2026-07-18: this panel renders INSIDE the category's own white/grey800
  // Card (it's inserted as a sibling right below the tapped product card,
  // still inside productListView's per-category Card/ExpansionTile), unlike
  // Explore the Menu / Recommended For You / etc., which sit directly on
  // the page's own background. _buildHorizontalProductSection's subtle
  // gradient alone isn't enough contrast against an already-white parent to
  // read as a distinct card the way it does elsewhere - so this gets its
  // own explicit border/shadow/background, independent of whatever it's
  // nested inside.
  //
  // [onPageBackground] (2026-07-26): true when this instead renders directly
  // on the page's own lavender Scaffold background (below the top
  // carousels, via _buildCarouselPairsWellWithPanel) - the white/bordered/
  // shadowed card above reads as a mismatched floating box there (reported
  // UI issue), so this drops the card decoration entirely and matches
  // Explore the Menu/Recommended For You's own "no card, just floats on the
  // page" look instead. The horizontal inset those sections get from their
  // own internal padding is replicated here with explicit Padding, since
  // this variant isn't nested inside anything that already provides it.
  Widget _buildPairsWellWithPanel(
      BuildContext context, ProductModel productModel,
      {bool onPageBackground = false}) {
    final isDark = isDarkMode(context);
    final suggestions = _resolvedPairsWellWithDisplay(productModel);
    final vendorConfiguredIds = _pairsWellWithVendorConfiguredIds(productModel);
    final panel = Container(
      margin: const EdgeInsets.fromLTRB(0, 6, 0, 12),
      // Container asserts decoration != null whenever clipBehavior != none
      // (the clip path is derived from the decoration's shape) - onPageBackground
      // has no decoration at all, so clipping must be off in that case or
      // this throws at build time (the exact crash reported 2026-07-26).
      clipBehavior: onPageBackground ? Clip.none : Clip.antiAlias,
      decoration: onPageBackground
          ? null
          : BoxDecoration(
              color: isDark ? AppThemeData.grey900 : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppThemeData.grey700 : AppThemeData.grey200,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.3 : 0.07),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
      child: _buildHorizontalProductSection(
        titleText: "You will love pairing it with".tr(),
        products: suggestions,
        onClose: () => setState(() {
          _pairsWellWithProductId = null;
          _pairsWellWithFromCarousel = false;
          _pairsWellWithDisplayOrder = [];
        }),
        // Badge only where display order and displayed confidence are
        // guaranteed to be the same score (vendor-configured items) - see
        // _pairsWellWithVendorConfiguredIds' doc comment.
        suppressBadgeFor: (p) => !vendorConfiguredIds.contains(p.id),
        onItemAdded: (p) {
          if (!_pairsWellWithDisplayOrder.contains(p.id)) {
            setState(() => _pairsWellWithDisplayOrder.add(p.id));
          }
        },
      ),
    );
    // No extra horizontal Padding here even for onPageBackground (2026-07-26,
    // was wrapped in one) - _buildHorizontalProductSection already applies
    // its own left:16 inset internally (title Row + the ListView's own
    // padding), the exact same mechanism Recommended For You's own card row
    // relies on. Adding another 16 on top of that stacked to 32px total,
    // visibly starting this section's images further right than Recommended
    // For You's - the reported misalignment.
    return panel;
  }

  // Phase 2 recommendation engine (2026-07-17) - shared horizontal
  // product-card row, generalized from the pairs-well-with panel above so
  // every new restaurant-page section (Recommended For You / Restaurant
  // Specialities / Most Loved Here) and the panel itself all render through
  // one widget. Empty [products] hides the whole section - callers never
  // need their own empty-check.
  Widget _buildHorizontalProductSection({
    required String titleText,
    required List<ProductModel> products,
    VoidCallback? onClose,
    // Explore the Menu (2026-07-18) is NOT a recommendation - it must never
    // show a recommendation-confidence badge/label on its cards, regardless
    // of what _confidenceScores happens to hold for those products.
    bool suppressBadge = false,
    // Per-card override (2026-07-18) - Pairs Well With uses this to
    // suppress the badge only for filler/backfilled items (see
    // _pairsWellWithVendorConfiguredIds), not the whole section. Falls
    // back to the flat [suppressBadge] above when not provided.
    bool Function(ProductModel)? suppressBadgeFor,
    // Recommended For You only (2026-07-26, explicit product request) -
    // adding from this section now opens/updates the "pairs well with"
    // panel same as the main menu list's own Add button. Left false
    // (default, unchanged) for every other section, including this
    // function's use for the pairs-well-with panel itself, which must
    // never chain into re-triggering another panel.
    bool enablePairsWellWith = false,
    // Pairs Well With panel only (2026-07-26) - records that this specific
    // suggestion card was actually added, so _resolvedPairsWellWithDisplay
    // keeps it pinned in the panel even once it drops out of the anchor
    // product's fresh ranking (see that function's doc comment).
    void Function(ProductModel)? onItemAdded,
  }) {
    if (products.isEmpty) return const SizedBox.shrink();
    final isDark = isDarkMode(context);
    // Transparent (2026-07-18, was AppThemeData.grey100/grey900) - this
    // screen's actual Scaffold background is a warm lavender-white
    // (0xFFF2F0F8, see build()'s Scaffold), NOT the neutral grey100
    // (0xFFF3F4F6) that was here. Close, but visibly a different color -
    // the whole point of a section backdrop is to be indistinguishable
    // from the page around it, letting the white cards be the only
    // contrast, so this must inherit the real page background rather than
    // approximate it with a different named grey.
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    titleText,
                    style: TextStyle(
                      fontFamily: AppThemeData.bold,
                      fontSize: 18,
                      color:
                          isDark ? AppThemeData.grey50 : AppThemeData.grey900,
                    ),
                  ),
                ),
                if (onClose != null)
                  GestureDetector(
                    onTap: onClose,
                    child: Icon(Icons.close,
                        size: 18,
                        color: isDark
                            ? AppThemeData.grey400
                            : AppThemeData.grey600),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            // 228 (2026-07-26, was 250) - 250 reserved room for an
            // order-count line under the badge (_showOrderCountBadge), but
            // that flag is hardcoded false and has been for a while now -
            // nothing ever actually renders in that reserved space, so
            // every card in every section using this row (Recommended For
            // You, Pairs Well With, ...) left ~22px of dead space below its
            // real content, reported as a visibly vacant gap. Sized to the
            // real content now: 137 (image+button) + 16 (text padding) +
            // ~19 (name) + 4 (spacer) + ~19 (price) + ~19 (badge, compact) +
            // a small buffer. Re-enabling _showOrderCountBadge later would
            // need this raised again.
            height: 228,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.only(left: 16),
              itemCount: products.length,
              itemBuilder: (context, index) => Padding(
                key: ValueKey(products[index].id),
                padding: const EdgeInsets.only(right: 14),
                child: _buildRecoProductCard(context, products[index],
                    suppressBadge: suppressBadgeFor?.call(products[index]) ??
                        suppressBadge,
                    enablePairsWellWith: enablePairsWellWith,
                    onItemAdded: onItemAdded),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Same lookup used by the main list's itemBuilder, so the recommendation
  // card reflects real cart state instead of always showing a static ADD button.
  CartProduct? _cartProductFor(ProductModel productModel) {
    if (productModel.variant_info != null) {
      final cartId = productModel.id +
          "~" +
          productModel.variant_info!.variant_id.toString();
      return cartProducts.firstWhereOrNull((p) => p.id == cartId);
    }
    final exactId = "${productModel.id}~";
    CartProduct? match = cartProducts.firstWhereOrNull((p) => p.id == exactId);
    match ??= cartProducts
        .firstWhereOrNull((p) => p.id.startsWith("${productModel.id}~"));
    return match;
  }

  Widget _buildRecoProductCard(
      BuildContext context, ProductModel productModel,
      {bool suppressBadge = false,
      bool enablePairsWellWith = false,
      void Function(ProductModel)? onItemAdded}) {
    final isDark = isDarkMode(context);
    final cartProduct = _cartProductFor(productModel);

    // Same price/disPrice + variant resolution used by the main list's itemBuilder.
    String price = "0.0";
    String disPrice = "0.0";
    List<String> selectedVariants = [];
    final _ia = productModel.itemAttributes;
    if (_ia != null) {
      final _attrs = _ia.attributes ?? [];
      for (final attr in _attrs) {
        final _opts = attr.attributeOptions;
        if (_opts != null && _opts.isNotEmpty) {
          selectedVariants.add(_opts[0].toString());
        }
      }
      final _variants = _ia.variants;
      if (_variants != null) {
        final _match =
            _variants.where((e) => e.variant_sku == selectedVariants.join('-'));
        if (_match.isNotEmpty) {
          price = productCommissionPrice(_match.first.variant_price ?? '0');
          disPrice = "0";
        }
      }
    } else {
      price = productCommissionPrice(productModel.price.toString());
      disPrice = double.parse(productModel.disPrice.toString()) <= 0
          ? "0"
          : productCommissionPrice(productModel.disPrice.toString());
    }

    // No card box (2026-07-18, was a white/grey800 rounded Container behind
    // the whole thing) - per explicit reference comparison, product entries
    // in a horizontal row should float directly on the section/page
    // background (image + button + text, no card wrapper), not sit inside
    // their own nested card. The image now rounds all 4 corners (was only
    // the top 2, matching the card box it used to sit flush against) since
    // it's the only element with a visible boundary now.
    // Sized up 15% across the board (2026-07-20, explicit product request)
    // from the original 128-wide compact card - width, image height, icon
    // sizes, padding AND text sizes all scaled by the same ~1.15 factor
    // together, not just the container, so nothing looks squeezed/
    // out-of-proportion against the now-bigger image. _buildHorizontalProductSection's
    // outer SizedBox(height: ...) was widened to match this card's new
    // total intrinsic height.
    // Tapping the card (image/name/price) opens the same quick-view sheet
    // the main menu row opens (2026-07-20, explicit product request) -
    // previously only the ADD button did anything on these cards, across
    // ALL sections that share this card (Recommended For You / Explore the
    // Menu / Restaurant Must Try / Most Loved Here / Pairs Well With), so a
    // customer had no way to read the full description or see a larger
    // image from any of them. Wrapping the whole card in Material+InkWell
    // (same pattern _buildProductCard's main menu row already uses) rather
    // than the image alone - the ADD button/quantity pill further down is
    // its own nested InkWell and still wins on a direct tap, exactly like
    // it already does on the main menu row.
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showProductQuickView(productModel,
            fromCarousel: enablePairsWellWith),
        child: SizedBox(
      width: 148,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Explicit height (image + the button's hang-below space) so the
          // Stack's own hit-test box actually covers the button — a Positioned
          // child that overflows the Stack's box (via clipBehavior: Clip.none)
          // paints fine but is NOT hit-testable outside that box, since the
          // parent Column only forwards taps to a child within its allocated
          // slot. Without this, the button looks right but never receives taps.
          SizedBox(
            height: 137,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  // Lazy (2026-07-20): the recommendation-section rows
                  // (Recommended For You / Explore the Menu / Restaurant Must
                  // Try / Most Loved Here / Pairs Well With, all rendered
                  // through this same card) sit inside a horizontal
                  // ListView.builder, but its default cacheExtent is wide
                  // enough to pre-build every card in a short 5-8 item row
                  // regardless of scroll position - firing a network request
                  // for every card's photo the instant the page opens, on
                  // top of the main menu below. Reuses the same
                  // VisibilityDetector-gated widget the main menu list
                  // already uses (see _LazyDishImage's doc comment) so only
                  // photos actually scrolled into view fire a request.
                  child: _LazyDishImage(
                    cacheKey: 'reco_${productModel.id}',
                    imageUrl: getImageVAlidUrl(productModel.photo),
                    height: 109,
                    width: double.infinity,
                  ),
                ),
                Positioned(
                  left: 9,
                  top: 9,
                  child: SvgPicture.asset(
                    productModel.nonveg
                        ? "assets/icons/ic_nonveg.svg"
                        : "assets/icons/ic_veg.svg",
                    height: 16,
                    width: 16,
                  ),
                ),
                Positioned(
                  right: 9,
                  bottom: 0,
                  child: (cartProduct == null || cartProduct.quantity == 0)
                      ? Material(
                          color: AppThemeData.primary500,
                          borderRadius: BorderRadius.circular(11),
                          elevation: 2,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(11),
                            onTap: () async {
                              // Recommended For You (2026-07-26, explicit
                              // product request): the pairs-well-with panel
                              // only ever renders inline inside the main
                              // menu list's own per-item loop, so setting
                              // _pairsWellWithProductId from a carousel add
                              // had nothing to actually show. Routing
                              // through the same quick-view sheet the main
                              // list itself uses (_showProductQuickView,
                              // whose own onAddToCart already calls
                              // _showPairsWellWith) sidesteps that gap
                              // entirely instead of teaching the carousel a
                              // second render location.
                              if (enablePairsWellWith) {
                                _showProductQuickView(productModel,
                                    fromCarousel: true);
                                return;
                              }
                              await _handleAddToCart(productModel,
                                  showPairsWellWith: enablePairsWellWith);
                              onItemAdded?.call(productModel);
                            },
                            child: Container(
                              constraints: const BoxConstraints(
                                  minWidth: 46, minHeight: 35),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 7),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "ADD".tr(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.add,
                                      color: Colors.white, size: 15),
                                ],
                              ),
                            ),
                          ),
                        )
                      : _buildHorizontalQuantityPill(context, cartProduct),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 7, 9, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productModel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : AppThemeData.grey900,
                  ),
                ),
                const SizedBox(height: 4),
                (disPrice == "" || disPrice == "0")
                    ? Text(
                        amountShow(amount: price),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppThemeData.grey300
                              : AppThemeData.grey700,
                        ),
                      )
                    : Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          Text(
                            amountShow(amount: disPrice),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppThemeData.primary500,
                            ),
                          ),
                          Text(
                            amountShow(amount: price),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppThemeData.grey400
                                  : AppThemeData.grey500,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                      ),
                RecommendationConfidenceBadge(
                  confidence:
                      suppressBadge ? null : _confidenceScores[productModel.id],
                  compact: true,
                ),
                if (_showOrderCountBadge && _orderCounts[productModel.id] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      '${_orderCounts[productModel.id]} ${'orders'.tr()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? AppThemeData.grey400
                            : AppThemeData.grey600,
                      ),
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
  }

  void _showRestaurantInfoSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: isDarkMode(context)
                    ? AppThemeData.surfaceDark
                    : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Handle bar
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDarkMode(context)
                            ? AppThemeData.grey600
                            : AppThemeData.grey300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [
                        // Photo
                        if (widget.vendorModel.photo.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: NetworkImageWidget(
                              imageUrl: widget.vendorModel.photo,
                              fit: BoxFit.cover,
                              height: (MediaQuery.of(context).size.width * 0.47)
                                  .clamp(150.0, 220.0),
                              width: double.infinity,
                            ),
                          ),
                        const SizedBox(height: 16),
                        // Name + rating row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.vendorModel.title.toString(),
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: AppThemeData.bold,
                                      color: isDarkMode(context)
                                          ? AppThemeData.grey50
                                          : AppThemeData.grey900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Icon(Icons.location_on,
                                          size: 14,
                                          color: AppThemeData.primary500),
                                      const SizedBox(width: 3),
                                      Expanded(
                                        child: Text(
                                          () {
                                            final locality = widget
                                                .vendorModel.locality
                                                .trim();
                                            final landmark = widget
                                                .vendorModel.landmark
                                                .trim();
                                            if (locality.isEmpty)
                                              return widget
                                                  .vendorModel.location;
                                            if (landmark.isEmpty)
                                              return locality;
                                            return '$locality, $landmark';
                                          }(),
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: isDarkMode(context)
                                                ? AppThemeData.grey400
                                                : AppThemeData.grey600,
                                            fontFamily: AppThemeData.regular,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      // Map button
                                      GestureDetector(
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                VendorLocationScreen(
                                              vendorModel: widget.vendorModel,
                                            ),
                                          ),
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: AppThemeData.primary500
                                                .withOpacity(0.10),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: const Icon(
                                            Icons.map_rounded,
                                            size: 16,
                                            color: AppThemeData.primary500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (widget.vendorModel.cuisineNames
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      widget.vendorModel.cuisineNames
                                          .join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontFamily: AppThemeData.medium,
                                        color: isDarkMode(context)
                                            ? AppThemeData.grey400
                                            : AppThemeData.grey600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Rating badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isDarkMode(context)
                                    ? const Color(0xFF052E16)
                                    : const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: const Color(0xFF16A34A)
                                        .withOpacity(0.35)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SvgPicture.asset(
                                    "assets/icons/ic_star.svg",
                                    colorFilter: const ColorFilter.mode(
                                        Color(0xFF16A34A), BlendMode.srcIn),
                                    height: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    "${calculateReview(reviewCount: widget.vendorModel.reviewsCount.toStringAsFixed(0), reviewSum: widget.vendorModel.reviewsSum.toString())}",
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF15803D),
                                      fontFamily: AppThemeData.semiBold,
                                    ),
                                  ),
                                  Text(
                                    " (${widget.vendorModel.reviewsCount.toStringAsFixed(0)})",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDarkMode(context)
                                          ? AppThemeData.grey400
                                          : AppThemeData.grey600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Status chip
                        sectionConstantModel?.serviceTypeFlag ==
                                "ecommerce-service"
                            ? const SizedBox()
                            : Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8, horizontal: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: isOpen
                                      ? AppThemeData.success400.withOpacity(0.1)
                                      : AppThemeData.danger300.withOpacity(0.1),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isOpen
                                            ? AppThemeData.success400
                                            : AppThemeData.danger300,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isOpen
                                          ? "Open Now".tr()
                                          : "Currently Closed".tr(),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: isOpen
                                            ? AppThemeData.success400
                                            : AppThemeData.danger300,
                                        fontFamily: AppThemeData.semiBold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                        // Description
                        if (widget.vendorModel.description != null &&
                            widget.vendorModel.description!.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            "About".tr(),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              fontFamily: AppThemeData.semiBold,
                              color: isDarkMode(context)
                                  ? AppThemeData.grey50
                                  : AppThemeData.grey900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.vendorModel.description!,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: isDarkMode(context)
                                  ? AppThemeData.grey400
                                  : AppThemeData.grey700,
                              fontFamily: AppThemeData.regular,
                            ),
                          ),
                        ],
                        // Working hours
                        if (widget.vendorModel.workingHours.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Icon(Icons.access_time_rounded,
                                  size: 18, color: AppThemeData.primary500),
                              const SizedBox(width: 6),
                              Text(
                                "Working Hours".tr(),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: AppThemeData.semiBold,
                                  color: isDarkMode(context)
                                      ? AppThemeData.grey50
                                      : AppThemeData.grey900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ...widget.vendorModel.workingHours.map((wh) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 90,
                                    child: Text(
                                      wh.day ?? "",
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: isDarkMode(context)
                                            ? AppThemeData.grey300
                                            : AppThemeData.grey700,
                                        fontFamily: AppThemeData.medium,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      wh.timeslot == null ||
                                              wh.timeslot!.isEmpty
                                          ? "Closed".tr()
                                          : wh.timeslot!
                                              .map((t) => "${t.from} – ${t.to}")
                                              .join(", "),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDarkMode(context)
                                            ? AppThemeData.grey400
                                            : AppThemeData.grey600,
                                        fontFamily: AppThemeData.regular,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Method to actually add product to cart
  Future<void> _addProductToCart(ProductModel productModel) async {
    if (!_cartReady) return;

    // ── Service compatibility gate — hard-block before any cart work ──────────
    if (productModel.deliveryOption ||
        productModel.takeaway ||
        productModel.dineIn) {
      if (!_isDineAwayMode && !productModel.deliveryOption) {
        ShowToastDialog.showToast('Delivery order is not available.'.tr());
        return;
      }
      if (_isDineAwayMode) {
        final allowed =
            (_dineAwaySubMode == 'Takeaway' && productModel.takeaway) ||
                (_dineAwaySubMode == 'Dining' && productModel.dineIn);
        if (!allowed) {
          ShowToastDialog.showToast('DineAway order is not available.'.tr());
          return;
        }
      }
    }

    try {
      // Check if cart contains products from a different vendor
      if (cartProducts.isNotEmpty) {
        String cartVendorID = cartProducts[0].vendorID;
        if (cartVendorID != widget.vendorModel.id) {
          // Show a dialog to confirm if user wants to clear cart and add new product
          final confirmed = await AppDialog.showConfirm(
            context,
            title: 'Replace Cart Items?',
            message:
                'Your cart contains items from a different store. Would you like to clear your cart and add this item?',
            confirmLabel: 'Clear & Add',
            cancelLabel: 'Cancel',
            destructive: true,
          );

          // If user cancels, return without adding to cart
          if (!confirmed) {
            return;
          }

          // User confirmed, so clear cart before adding new product
          await cartDatabase.deleteAllProducts();
          // Also clear local cart products list to update UI immediately
          setState(() {
            cartProducts.clear();
            // Whole cart wiped — nothing is "added" anymore, so the sticky
            // pairing list has nothing left to keep pinned.
            _pairsWellWithDisplayOrder.clear();
            _pairsWellWithProductId = null;
            _pairsWellWithFromCarousel = false;
          });
        }
      }

      // Handle product variants if not already set.
      // Save originals so we can restore the shared productModel after use —
      // mutating it directly would corrupt the displayed price in the listing.
      final originalPrice = productModel.price;
      final originalDisPrice = productModel.disPrice;
      final originalVariantInfo = productModel.variant_info;

      try {
        if (productModel.itemAttributes != null &&
            productModel.itemAttributes!.attributes!.isNotEmpty &&
            productModel.variant_info == null) {
          List<String> selectedVariants = [];
          for (var element in productModel.itemAttributes!.attributes!) {
            if (element.attributeOptions!.isNotEmpty) {
              selectedVariants.add(element.attributeOptions![0].toString());
            }
          }

          final matchingVariants = productModel.itemAttributes!.variants!.where(
              (element) => element.variant_sku == selectedVariants.join('-'));

          if (matchingVariants.isNotEmpty) {
            final selectedVariant = matchingVariants.first;
            productModel.price = selectedVariant.variant_price.toString();
            productModel.disPrice = '0';
            productModel.variant_info = VariantInfo(
              variant_id: selectedVariant.variant_id,
              variant_price: selectedVariant.variant_price,
              variant_image: selectedVariant.variant_image,
              variant_sku: selectedVariant.variant_sku,
              variant_options: {},
            );
          }
        }

        // Add product to cart
        bool success =
            await cartDatabase.addProduct(productModel, cartDatabase, true);

        if (success) {
          final sp = await SharedPreferences.getInstance();
          await sp.setString(
            'service_perm_${productModel.id}',
            jsonEncode({
              'delivery': productModel.deliveryOption,
              'dineaway': productModel.dineIn || productModel.takeaway,
              'dineIn': productModel.dineIn,
              'takeaway': productModel.takeaway,
            }),
          );
          await sp.remove('dineaway_perm_${productModel.id}');
          // Wired 2026-07-20 - this is the single choke point every
          // add-to-cart path on this screen already goes through (quick
          // ADD on a card, the "Add Item" quick-view sheet, Pairs Well
          // With suggestions), but until now none of them ever recorded
          // kEvtProductAddedToCart - only the separate, legacy
          // ProductDetailsScreen.dart did. Same payload shape as that
          // screen's own tracking call.
          BehaviorTracker.track(kEvtProductAddedToCart, {
            'productId': productModel.id,
            'vendorId': productModel.vendorID,
            'quantity': 1,
            'categoryId': productModel.categoryID,
            // Cuisine preference signal (2026-07-27) - vendor object already
            // in memory here, no new Firestore read. Feeds
            // cuisineInteractionCounts alongside categoryId above - see
            // BehaviorTracker's kEvtProductAddedToCart case for the
            // weighting.
            'cuisineIds': widget.vendorModel.cuisineIds,
            // Veg/Non-Veg preference signal (2026-07-25) - captured HERE,
            // not at order completion, because ProductModel (which alone
            // carries .veg/.nonveg) is only in scope at add-to-cart time;
            // CartProduct (what survives to checkout/order completion) has
            // no veg field, and adding one would need a CartProducts
            // schema migration this codebase deliberately avoids (moor/
            // SQLite has no migration strategy here - see
            // BehaviorQueueStore's own doc comment). Cart-add is an
            // honest, slightly coarser proxy than a completed order, at
            // zero extra reads and zero schema risk.
            'isVeg': productModel.veg,
            'isNonVeg': productModel.nonveg,
          });
          // Combo metadata cache (2026-07-24) - see
          // BehaviorTracker.rememberComboMetadata's own doc comment. A
          // no-op for every non-combo product (the vast majority).
          if (productModel.isCombo) {
            BehaviorTracker.rememberComboMetadata(
              productModel.id,
              comboProductIds:
                  productModel.comboProducts.map((c) => c.productId).toList(),
              comboCategoryIds: productModel.comboCategoryIds,
              price: productModel.price,
            );
          }
          // Restaurant Engagement session counter (Phase 2, 2026-07-24) -
          // same choke point comment as kEvtProductAddedToCart above.
          _sessionAddToCartCount++;
        }

        if (!success) {
          ShowToastDialog.showToast(
              "Items from only one restaurant can be added to cart at a time"
                  .tr());
          return;
        }

        if (mounted) {
          await _refreshCartData();
        }
      } finally {
        // Always restore so the listing continues to show the original price.
        productModel.price = originalPrice;
        productModel.disPrice = originalDisPrice;
        productModel.variant_info = originalVariantInfo;
      }
    } catch (e) {
      print("Error adding to cart: $e");
      ShowToastDialog.showToast(
          "Failed to add product to cart. Please try again.".tr());
    }
  }

  // ── Offer banner & sheet ────────────────────────────────────────────────────
  // "Maximum rupee saving" ladder — every rung shows the exact ₹ saving a
  // customer gets at that minimum spend, computed with the identical
  // eligibility/combination/cap rules CartScreen uses at checkout (coupon
  // validation, special-discount selection, conflict resolution, and the
  // maxCombinedDiscountPercent cap) — never a percentage, never a theoretical
  // merged figure that isn't actually achievable at checkout.

  // Today's active special-discount time slots (day + time-window + current
  // Delivery/Dineaway mode already filtered) — only the minimum-order check
  // is left to do per candidate amount, in _bestSpecialValueAt.
  List<_SpecialSlotCandidate> _todaysSpecialSlots() {
    if (!widget.vendorModel.specialDiscountEnable ||
        widget.vendorModel.specialDiscount.isEmpty) {
      return [];
    }
    final now = DateTime.now();
    final currentDay = DateFormat('EEEE', 'en_US').format(now);
    final dateStr = DateFormat('dd-MM-yyyy').format(now);
    // Stored value in Firestore is "Takeaway" for the non-delivery mode even
    // though the vendor app's UI label reads "Dineaway" — CartScreen's own
    // special-discount filter already matches against "Takeaway"; this must
    // stay consistent with that or active discounts silently vanish here.
    final orderType = _isDineAwayMode ? 'Takeaway' : 'Delivery';
    final List<_SpecialSlotCandidate> active = [];

    for (final dayDiscount in widget.vendorModel.specialDiscount) {
      if (dayDiscount.day != currentDay) continue;
      if (dayDiscount.timeslot == null || dayDiscount.timeslot!.isEmpty)
        continue;
      for (final slot in dayDiscount.timeslot!) {
        if ((slot.from?.isEmpty ?? true) || (slot.to?.isEmpty ?? true))
          continue;
        try {
          final start =
              DateFormat('dd-MM-yyyy HH:mm').parse('$dateStr ${slot.from}');
          var end = DateFormat('dd-MM-yyyy HH:mm').parse('$dateStr ${slot.to}');
          if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
          if (!widget.vendorModel.isCurrentDateInRange(start, end)) continue;
        } catch (_) {
          continue;
        }
        if (slot.orderType != null && slot.orderType!.isNotEmpty) {
          if (slot.orderType != orderType) continue;
        }
        active.add(_SpecialSlotCandidate(
          minAmount: double.tryParse(slot.applicableAmount ?? '0') ?? 0,
          rawDiscount: double.tryParse(slot.discount ?? '0') ?? 0,
          isPercent: slot.type == 'percentage',
        ));
      }
    }
    return active;
  }

  // What a coupon is actually worth at [amount] — identical formula to
  // CartScreen's _doApplyCoupon: percentage of the amount, or the flat value
  // capped at the amount itself (a flat coupon can never discount more than
  // the order is worth).
  double _couponValueAt(OfferModel coupon, double amount) {
    final isPercent = coupon.discountTypeOffer == 'Percentage' ||
        coupon.discountTypeOffer == 'Percent';
    final raw = double.tryParse(coupon.discountOffer ?? '0') ?? 0;
    return isPercent ? amount * raw / 100 : (raw > amount ? amount : raw);
  }

  // Best special discount at [amount] among today's active slots — eligible
  // exactly like coupons below (any slot whose own minimum is <= this
  // milestone, not just an exact match), and CartScreen picks whichever
  // eligible slot has the highest actual rupee value at the real subtotal
  // (never by raw stored percentage/flat number), so this mirrors that
  // exactly. An older or smaller-minimum special discount can still win at a
  // bigger milestone if it's genuinely worth more there — never assume the
  // newest one is best.
  double _bestSpecialValueAt(double amount, List<_SpecialSlotCandidate> slots) {
    double best = 0;
    for (final slot in slots) {
      if (amount < slot.minAmount) continue;
      final actual = slot.isPercent
          ? amount * slot.rawDiscount / 100
          : (slot.rawDiscount > amount ? amount : slot.rawDiscount);
      if (actual > best) best = actual;
    }
    return best;
  }

  // Combines a coupon value and a special-discount value at [amount] using
  // CartScreen's exact two-stage resolution:
  //   1. Together they can't discount more than the order itself (physically
  //      impossible) — keep only the larger, special wins a tie (matches
  //      CartScreen's build-time conflict resolution).
  //   2. Even within that, combined they can't exceed
  //      maxCombinedDiscountPercent% of the order (default 70, see
  //      constants.dart) — coupon is trusted first, special discount trimmed
  //      to whatever room remains.
  ({double coupon, double special}) _combineAndCap(
      double amount, double couponValue, double specialValue) {
    double coupon = couponValue;
    double special = specialValue;

    if (coupon > 0 && special > 0 && coupon + special > amount) {
      if (coupon <= special) {
        coupon = 0;
      } else {
        special = 0;
      }
    }

    final double maxCombined = amount * maxCombinedDiscountPercent / 100;
    if (coupon + special > maxCombined) {
      final double cappedCoupon = coupon > maxCombined ? maxCombined : coupon;
      final double remaining =
          (maxCombined - cappedCoupon).clamp(0.0, double.infinity);
      special = special > remaining ? remaining : special;
      coupon = cappedCoupon;
    }
    return (coupon: coupon, special: special);
  }

  // Builds the "maximum rupee saving" ladder: one row for every unique
  // minimum order amount coming from any coupon or any active special-
  // discount slot. For each milestone, the best coupon and the best special
  // discount are each chosen independently (comparing every offer unlocked
  // at that amount — an older or smaller offer can still win at a bigger
  // milestone, so this never just assumes the newest one is best), then only
  // those two winners are handed to _combineAndCap — the same combine/cap
  // resolution CartScreen uses at checkout — which alone decides whether the
  // final saving is the coupon, the special discount, or both together.
  // Every milestone with a positive saving is kept; none are dropped just
  // because a different milestone happens to save more; each one answers
  // "if I spend at least this much, what's the most I can save?" on its own.
  // Called once whenever the underlying offer data or mode changes — never
  // from the widget build path — see call sites in getVendorCategoryById and
  // didChangeAppLifecycleState.
  void _recomputeOfferLadder() {
    final specialSlots = _todaysSpecialSlots();

    // Every candidate minimum order amount worth evaluating: each coupon's
    // own threshold, plus each active special slot's own threshold.
    final Set<double> candidateAmounts = {
      for (final c in offerList)
        double.tryParse(c.applicableAmount ?? '0') ?? 0,
      for (final s in specialSlots) s.minAmount,
    };

    final List<_OfferLadderRung> rungs = [];
    for (final amount in candidateAmounts) {
      if (amount <= 0) continue;

      // Best coupon at this amount, chosen on its own merit — every coupon
      // unlocked here is compared, not just the most recently created one.
      OfferModel? bestCoupon;
      double bestCouponValue = 0;
      for (final coupon in offerList) {
        final minAmt = double.tryParse(coupon.applicableAmount ?? '0') ?? 0;
        if (amount < minAmt) continue;
        final value = _couponValueAt(coupon, amount);
        if (value > bestCouponValue) {
          bestCouponValue = value;
          bestCoupon = coupon;
        }
      }
      final bestSpecialValue = _bestSpecialValueAt(amount, specialSlots);

      final combo = _combineAndCap(amount, bestCouponValue, bestSpecialValue);
      final totalSaving = combo.coupon + combo.special;
      if (totalSaving <= 0) continue;

      rungs.add(_OfferLadderRung(
        thresholdAmount: amount,
        savingAmount: totalSaving,
        offerCode: combo.coupon > 0 ? bestCoupon?.offerCode : null,
      ));
    }

    rungs.sort((a, b) => a.thresholdAmount.compareTo(b.thresholdAmount));

    if (mounted) {
      setState(() {
        _offerLadderRungs = rungs;
        _offerLadderCurrentPage = 0;
      });
      if (_offerLadderPageController.hasClients) {
        _offerLadderPageController.jumpToPage(0);
      }
      _animateOfferLadder();
      _scheduleNextOfferLadderBoundary();
    }
  }

  // Schedules a one-shot recompute at the next moment something about
  // today's special-discount schedule actually changes — a slot's start
  // time, a slot's end time, or midnight rolling over to tomorrow's
  // day-of-week config (a different set of slots entirely). Mirrors
  // _startClosingCountdown's pattern for the restaurant open/closed timer.
  // Re-arms itself after firing, via _recomputeOfferLadder calling this
  // again, so the ladder keeps following the schedule for as long as the
  // customer stays on this page.
  void _scheduleNextOfferLadderBoundary() {
    _offerLadderBoundaryTimer?.cancel();
    if (!widget.vendorModel.specialDiscountEnable ||
        widget.vendorModel.specialDiscount.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final currentDay = DateFormat('EEEE', 'en_US').format(now);
    final dateStr = DateFormat('dd-MM-yyyy').format(now);

    DateTime? nextBoundary;
    void consider(DateTime t) {
      if (t.isAfter(now) &&
          (nextBoundary == null || t.isBefore(nextBoundary!))) {
        nextBoundary = t;
      }
    }

    for (final dayDiscount in widget.vendorModel.specialDiscount) {
      if (dayDiscount.day != currentDay) continue;
      for (final slot in dayDiscount.timeslot ?? const []) {
        if ((slot.from?.isEmpty ?? true) || (slot.to?.isEmpty ?? true)) {
          continue;
        }
        try {
          final start =
              DateFormat('dd-MM-yyyy HH:mm').parse('$dateStr ${slot.from}');
          var end = DateFormat('dd-MM-yyyy HH:mm').parse('$dateStr ${slot.to}');
          if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
          consider(start);
          consider(end);
        } catch (_) {}
      }
    }

    // Always also wake up at midnight — tomorrow is a different day-of-week
    // with its own (possibly empty, possibly different) set of slots.
    final midnight =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    consider(midnight);

    if (nextBoundary == null) return;
    final delay = nextBoundary!.difference(now);
    _offerLadderBoundaryTimer = Timer(delay, () {
      if (!mounted) return;
      _recomputeOfferLadder();
    });
  }

  Widget _buildOfferBanner(BuildContext context) {
    if (_offerLadderRungs.isEmpty) return const SizedBox();
    final dark = isDarkMode(context);
    return Column(
      children: [
        SizedBox(
          // Was 56 for the old single-line card; the new "Save ₹X on ₹Y" +
          // "Use: CODE"/"Applied automatically" card is two lines and
          // overflowed the old fixed height by ~11px.
          height: 76,
          child: PageView.builder(
            controller: _offerLadderPageController,
            physics: const BouncingScrollPhysics(),
            itemCount: _offerLadderRungs.length,
            onPageChanged: (index) {
              _offerLadderCurrentPage = index;
            },
            itemBuilder: (context, index) => _buildOfferLadderRungCard(
                context, _offerLadderRungs[index], dark),
          ),
        ),
        if (_offerLadderRungs.length > 1) ...[
          const SizedBox(height: 6),
          // Scoped to just the dot row via ValueListenableBuilder — the page
          // ticks every 2s and this avoids rebuilding the whole ~5000-line
          // screen State just to recolor these dots.
          ValueListenableBuilder<int>(
            valueListenable: _offerLadderCurrentPageNotifier,
            builder: (context, currentPage, _) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_offerLadderRungs.length, (index) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index == currentPage
                        ? AppThemeData.primary500
                        : (dark
                            ? AppThemeData.darkBorderSecondary
                            : AppThemeData.neutral300),
                  ),
                );
              }),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOfferLadderRungCard(
      BuildContext context, _OfferLadderRung rung, bool dark) {
    final savingsLine =
        "${'Save'.tr()} ${amountShow(amount: rung.savingAmount.toStringAsFixed(2))} ${'on orders above'.tr()} ${amountShow(amount: rung.thresholdAmount.toStringAsFixed(2))}";

    return GestureDetector(
      onTap: () => _showOffersSheet(context),
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: dark ? AppThemeData.darkBgSecondary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral200,
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Left accent bar
              Container(
                width: 4,
                decoration: const BoxDecoration(
                  color: AppThemeData.primary500,
                  borderRadius:
                      BorderRadius.horizontal(left: Radius.circular(12)),
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Icon(Icons.savings_rounded,
                    size: 20, color: AppThemeData.primary500),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        savingsLine,
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: AppThemeData.semiBold,
                          color: dark
                              ? AppThemeData.darkTextPrimary
                              : AppThemeData.neutral800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // Only ever a coupon code — never "Applied
                      // automatically" or any other explanation. A pure
                      // special-discount rung is a single line.
                      if (rung.offerCode != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          "${'Use'.tr()}: ${rung.offerCode}",
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: AppThemeData.medium,
                            color: AppThemeData.primary500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppThemeData.primary500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOffersSheet(BuildContext context) {
    final dark = isDarkMode(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: dark ? AppThemeData.darkBgSecondary : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: dark
                      ? AppThemeData.darkBorderSecondary
                      : AppThemeData.neutral300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                "Your savings at ${widget.vendorModel.title}",
                style: TextStyle(
                  fontSize: 18,
                  fontFamily: AppThemeData.semiBold,
                  color: dark
                      ? AppThemeData.darkTextPrimary
                      : AppThemeData.neutral900,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Divider(
                height: 1,
                color: dark
                    ? AppThemeData.darkBorderSecondary
                    : AppThemeData.neutral200),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _offerLadderRungs
                      .map((rung) => _offerLadderRungSheetCard(rung, dark))
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // One row per savings-ladder rung, in the sheet — same "Save ₹X on ₹Y"
  // framing as the top banner/carousel, so the sheet is a full list of the
  // exact same tiers. The coupon code (needed to redeem at checkout) shows
  // as a chip only when the rung's saving involves one; a rung resolved
  // purely from the special discount shows just the saving line — never
  // "Applied automatically" or any other explanation of how it was reached.
  Widget _offerLadderRungSheetCard(_OfferLadderRung rung, bool dark) {
    final savingsLine =
        "${'Save'.tr()} ${amountShow(amount: rung.savingAmount.toStringAsFixed(2))} ${'on orders above'.tr()} ${amountShow(amount: rung.thresholdAmount.toStringAsFixed(2))}";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgTertiary : AppThemeData.neutral50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              dark ? AppThemeData.darkBorderSecondary : AppThemeData.primary200,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppThemeData.primary500.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.savings_rounded,
                size: 18, color: AppThemeData.primary500),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  savingsLine,
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: AppThemeData.semiBold,
                    color: dark
                        ? AppThemeData.darkTextPrimary
                        : AppThemeData.neutral800,
                  ),
                ),
                if (rung.offerCode != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppThemeData.primary500.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "${'Use'.tr()}: ${rung.offerCode}",
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppThemeData.primary500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// productListView()'s category ListView.builder and each category's
// ListView.separated are both shrinkWrap + NeverScrollableScrollPhysics (so
// they can size themselves inside the page's outer SingleChildScrollView),
// which forces Flutter to build every item up front to compute intrinsic
// height — every dish card across every category, regardless of whether
// it's ever scrolled to. That eagerly kicks off a network request for every
// dish photo the moment the screen opens, same anti-pattern as the original
// Home-screen bug. Rather than re-architecting the nested-scrollables layout,
// this gates just the image request behind actual on-screen visibility
// (same VisibilityDetector approach already used for Home's restaurant
// cards) — the card itself still builds eagerly, but no network request
// fires until the image is actually scrolled into view.
class _LazyDishImage extends StatefulWidget {
  final String cacheKey;
  final String imageUrl;
  final double width;
  final double height;

  const _LazyDishImage({
    required this.cacheKey,
    required this.imageUrl,
    required this.width,
    required this.height,
  });

  @override
  State<_LazyDishImage> createState() => _LazyDishImageState();
}

class _LazyDishImageState extends State<_LazyDishImage> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    if (_visible) {
      // TEMPORARY diagnostic: routes through the same instrumented cache
      // manager as the Home-screen investigation so real network-layer
      // dispatch timing for this screen can be verified on-device, not
      // assumed from the VisibilityDetector gate alone.
      tagImageRequest(widget.imageUrl,
          section: 'VendorProductDish', trigger: 'widget-build');
      debugPrint(
          '[VENDORPROD-PERF][IMG] dish START — ${widget.cacheKey} — ${widget.imageUrl}');
      return NetworkImageWidget(
        imageUrl: widget.imageUrl,
        fit: BoxFit.cover,
        height: widget.height,
        width: widget.width,
        cacheManager: perfDiagnosticCacheManager,
        onLoaded: () => debugPrint(
            '[VENDORPROD-PERF][IMG] dish LOADED — ${widget.cacheKey}'),
        onError: (e) => debugPrint(
            '[VENDORPROD-PERF][IMG] dish FAILED — ${widget.cacheKey} — $e'),
      );
    }
    return VisibilityDetector(
      key: ValueKey('dishImg_${widget.cacheKey}'),
      onVisibilityChanged: (info) {
        if (!_visible && info.visibleFraction > 0 && mounted) {
          setState(() => _visible = true);
        }
      },
      child: ShimmerBox(
        width: widget.width,
        height: widget.height,
        borderRadius: 0, // outer ClipRRect at the call site already clips this
      ),
    );
  }
}

class _AnimatedAddButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool hasOptions;

  const _AnimatedAddButton(
      {Key? key, required this.onTap, this.hasOptions = false})
      : super(key: key);

  @override
  State<_AnimatedAddButton> createState() => _AnimatedAddButtonState();
}

class _AnimatedAddButtonState extends State<_AnimatedAddButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween<double>(begin: 1.0, end: 0.92)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTap() {
    _ctrl.forward().then((_) => _ctrl.reverse());
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        key: const ValueKey('add_btn'),
        onTap: _onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppThemeData.primary500, AppThemeData.primary600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: AppThemeData.primary500.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, color: Colors.white, size: 15),
              const SizedBox(width: 4),
              Text(
                widget.hasOptions ? 'ADD'.tr() : 'ADD'.tr(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  fontFamily: AppThemeData.bold,
                  letterSpacing: 0.4,
                ),
              ),
              if (widget.hasOptions) ...[
                const SizedBox(width: 3),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    color: Colors.white, size: 14),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class CouponListView extends StatelessWidget {
  final List<OfferModel> offerList;

  const CouponListView({super.key, required this.offerList});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Responsive.height(9, context),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: offerList.length,
        itemBuilder: (BuildContext context, int index) {
          OfferModel offerModel = offerList[index];
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: ShapeDecoration(
                color: isDarkMode(context)
                    ? AppThemeData.grey900
                    : AppThemeData.grey50,
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                      width: 1,
                      color: isDarkMode(context)
                          ? AppThemeData.grey800
                          : AppThemeData.grey100),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: SizedBox(
                  width: Responsive.width(80, context),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 60,
                        decoration: const BoxDecoration(
                            image: DecorationImage(
                                image:
                                    AssetImage("assets/images/offer_gif.gif"),
                                fit: BoxFit.fill)),
                        child: Center(
                            child: Text(
                          offerModel.discountTypeOffer == "Fix Price"
                              ? amountShow(amount: offerModel.discountOffer)
                              : "${offerModel.discountOffer}%",
                          style: TextStyle(
                              color: isDarkMode(context)
                                  ? AppThemeData.grey50
                                  : AppThemeData.grey50,
                              fontFamily: AppThemeData.semiBold,
                              fontSize: 12),
                        )),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            offerModel.discountTypeOffer == "Fix Price"
                                ? "${amountShow(amount: offerModel.discountOffer)} OFF"
                                : "${offerModel.discountOffer}% OFF",
                            style: TextStyle(
                              fontSize: 16,
                              color: isDarkMode(context)
                                  ? AppThemeData.grey50
                                  : AppThemeData.grey900,
                              fontFamily: AppThemeData.semiBold,
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(
                                      text: offerModel.offerCode.toString()))
                                  .then(
                                (value) {
                                  ShowToastDialog.showToast("Copied".tr());
                                },
                              );
                            },
                            child: Row(
                              children: [
                                Text(
                                  offerModel.offerCode.toString(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDarkMode(context)
                                        ? AppThemeData.grey400
                                        : AppThemeData.grey500,
                                    fontFamily: AppThemeData.semiBold,
                                  ),
                                ),
                                const SizedBox(
                                  width: 5,
                                ),
                                SvgPicture.asset("assets/icons/ic_copy.svg"),
                                const SizedBox(
                                    height: 10, child: VerticalDivider()),
                                const SizedBox(
                                  width: 5,
                                ),
                                Text(
                                  timestampToDateTime(
                                      offerModel.expireOfferDate!),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDarkMode(context)
                                        ? AppThemeData.grey400
                                        : AppThemeData.grey500,
                                    fontFamily: AppThemeData.semiBold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
}
