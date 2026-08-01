import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/AttributesModel.dart';
import 'package:emartconsumer/model/BrandsModel.dart';
import 'package:emartconsumer/model/FavouriteItemModel.dart';
import 'package:emartconsumer/model/ItemAttributes.dart';
import 'package:emartconsumer/model/NutritionInfo.dart';
import 'package:emartconsumer/model/ProductAttributeConfig.dart';
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/model/Ratingmodel.dart';
import 'package:emartconsumer/model/ReviewAttributeModel.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/model/variant_info.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/Indicator.dart';
import 'package:emartconsumer/services/behavior/behavior_counters.dart';
import 'package:emartconsumer/services/behavior/behavior_event_types.dart';
import 'package:emartconsumer/services/behavior/behavior_tracker.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/theme/responsive.dart';
import 'package:emartconsumer/theme/round_button_fill.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';

import 'package:emartconsumer/ui/cartScreen/CartScreen.dart';
import 'package:emartconsumer/ui/container/ContainerScreen.dart';
import 'package:emartconsumer/ui/vendorProductsScreen/review.dart';
import 'package:emartconsumer/services/app_dialog.dart';
import 'package:emartconsumer/widget/coming_soon_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../vendorProductsScreen/newVendorProductsScreen.dart';

class ProductDetailsScreen extends StatefulWidget {
  final ProductModel productModel;
  final VendorModel vendorModel;

  const ProductDetailsScreen(
      {Key? key, required this.productModel, required this.vendorModel})
      : super(key: key);

  @override
  _ProductDetailsScreenState createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  
  late CartDatabase cartDatabase;

  String radioItem = '';
  int id = -1;
  List<AddAddonsDemo> lstAddAddonsCustom = [];
  List<AddAddonsDemo> lstTemp = [];
  double priceTemp = 0.0, lastPrice = 0.0;
  int productQnt = 0;

  List<String> productImage = [];

  List<Attributes>? attributes = [];
  List<Variants>? variants = [];

  // Variant selection
  List<String> selectedVariants = [];
  List<String> selectedIndexVariants = [];
  List<String> selectedIndexArray = [];

  bool isOpen = false;

  String? selectedOrderType;

  // Interest-duration signal, same pattern as the restaurant screens: a
  // single bounded Timer per screen visit, fired once, cancelled on
  // dispose() if left early - never a repeating/continuous timer. This
  // screen had no dispose() override before this addition.
  Timer? _dwellTimer;

  // Restaurant-visit session state (2026-07-24 fix) - this screen can be
  // reached DIRECTLY (Home's "Popular near you", Favourites), bypassing
  // NewVendorProductsScreen entirely, which previously meant its
  // product_viewed/product_added_to_cart events carried no restaurant-
  // session context at all and could never influence any
  // restaurantEngagement doc's productViewCount/addToCartCount. This makes
  // the screen a first-class session entry point, same mechanism
  // NewVendorProductsScreen already uses.
  String _restaurantSessionId = '';
  String _sessionEntrySource = 'Direct';
  String _sessionSearchKeyword = '';
  String _sessionSearchType = '';
  DateTime? _sessionStartedAt;

  statusCheck() {
    final now = DateTime.now();
    final day = DateFormat('EEEE', 'en_US').format(now);
    final date = DateFormat('dd-MM-yyyy').format(now);
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayDay = DateFormat('EEEE', 'en_US').format(yesterday);
    final yesterdayDate = DateFormat('dd-MM-yyyy').format(yesterday);
    bool scheduleOpen = false;

    // Mirrors VendorModel.isOpen() (home screen card) and the fixed
    // statusCheck() in newVendorProductsScreen.dart. The previous version
    // here had three separate bugs: (1) no midnight-crossing adjustment, so
    // an overnight slot like 22:00-02:00 produced an inverted range that
    // could never match; (2) no check of yesterday's slot extending into
    // today, so an overnight slot already in progress from the day before
    // was invisible; (3) it never looked at vendorModel.reststatus at all,
    // so this screen's "Add to Cart" button stayed enabled even when the
    // vendor had manually paused orders.
    for (var element in widget.vendorModel.workingHours) {
      if (day == element.day.toString()) {
        for (var slot in (element.timeslot ?? [])) {
          if (slot.from == null || slot.to == null) continue;
          final start =
              DateFormat("dd-MM-yyyy HH:mm").parse("$date ${slot.from}");
          var end = DateFormat("dd-MM-yyyy HH:mm").parse("$date ${slot.to}");
          if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
          if (isCurrentDateInRange(start, end)) scheduleOpen = true;
        }
      }
    }
    if (!scheduleOpen) {
      for (var element in widget.vendorModel.workingHours) {
        if (yesterdayDay == element.day.toString()) {
          for (var slot in (element.timeslot ?? [])) {
            if (slot.from == null || slot.to == null) continue;
            final start = DateFormat("dd-MM-yyyy HH:mm")
                .parse("$yesterdayDate ${slot.from}");
            var end = DateFormat("dd-MM-yyyy HH:mm")
                .parse("$yesterdayDate ${slot.to}");
            if (end.isAfter(start)) continue; // doesn't cross midnight
            end = end.add(const Duration(days: 1));
            if (isCurrentDateInRange(start, end)) scheduleOpen = true;
          }
        }
      }
    }

    // No working hours configured → treat as always schedulable (admin
    // toggle alone decides availability).
    if (widget.vendorModel.workingHours.isEmpty) scheduleOpen = true;

    setState(() {
      isOpen = widget.vendorModel.reststatus && scheduleOpen;
    });
  }

  bool isCurrentDateInRange(DateTime startDate, DateTime endDate) {
    final currentDate = DateTime.now();
    return currentDate.isAfter(startDate) && currentDate.isBefore(endDate);
  }

  @override
  void initState() {
    super.initState();

    print("product Id ---->${widget.productModel.id}");
    // productQnt = widget.productModel.quantity;

    print(widget.productModel.price);

    getAddOnsData();
    statusCheck();
    loadOrderType();
    if (widget.productModel.itemAttributes != null) {
      attributes = widget.productModel.itemAttributes!.attributes;
      variants = widget.productModel.itemAttributes!.variants;

      if (attributes!.isNotEmpty) {
        for (var element in attributes!) {
          if (element.attributeOptions!.isNotEmpty) {
            selectedVariants.add(attributes![attributes!.indexOf(element)]
                .attributeOptions![0]
                .toString());
            selectedIndexVariants.add(
                '${attributes!.indexOf(element)} _${attributes![0].attributeOptions![0].toString()}');
            selectedIndexArray.add('${attributes!.indexOf(element)}_0');
          }
        }
      }

      if (variants!
          .where((element) => element.variant_sku == selectedVariants.join('-'))
          .isNotEmpty) {
        widget.productModel.price = variants!
                .where((element) =>
                    element.variant_sku == selectedVariants.join('-'))
                .first
                .variant_price ??
            '0';
        widget.productModel.disPrice = '0';
      }
    }
    getData();
    _initAttributeSelections();

    // Reuse an already-active session for this exact vendor if one exists
    // (the "more from this store" chain: ProductDetailsScreen ->
    // ProductDetailsScreen) so one continuous visit produces one
    // restaurantEngagement doc, not several orphaned ones. Otherwise this
    // screen is itself the visit's entry point - mint a fresh session.
    _sessionStartedAt = DateTime.now();
    final existingSession =
        BehaviorTracker.recentRestaurantSessionFor(widget.vendorModel.id);
    if (existingSession != null) {
      _restaurantSessionId = existingSession.sessionId;
      _sessionEntrySource = existingSession.entrySource;
      _sessionSearchKeyword = existingSession.searchKeyword;
      _sessionSearchType = existingSession.searchType;
      _sessionStartedAt = existingSession.startedAt;
    } else {
      final session =
          BehaviorTracker.startRestaurantSession(widget.vendorModel.id);
      _restaurantSessionId = session.sessionId;
      _sessionEntrySource = session.entrySource;
      _sessionSearchKeyword = session.searchKeyword;
      _sessionSearchType = session.searchType;
    }

    // ignore: unawaited_futures
    _trackProductViewed();
    _dwellTimer = Timer(const Duration(seconds: kDwellThresholdSeconds), () {
      BehaviorTracker.track(kEvtProductInterest, {
        'productId': widget.productModel.id,
        'vendorId': widget.vendorModel.id,
      });
    });
  }

  Future<void> _trackProductViewed() async {
    final viewCount =
        await BehaviorCounters.increment('product_view', widget.productModel.id);
    BehaviorTracker.track(kEvtProductViewed, {
      'productId': widget.productModel.id,
      'vendorId': widget.vendorModel.id,
      'categoryId': widget.productModel.categoryID,
      'viewCount': viewCount,
      // Cuisine preference signal (2026-07-27) - vendor object already in
      // memory here, no new Firestore read. See BehaviorTracker's
      // kEvtProductViewed case for the weighting.
      'cuisineIds': widget.vendorModel.cuisineIds,
    });
    BehaviorTracker.bumpSessionProductView(_restaurantSessionId,
        categoryId: widget.productModel.categoryID);
  }

  @override
  void dispose() {
    _dwellTimer?.cancel();
    BehaviorTracker.endRestaurantSession(
      _restaurantSessionId,
      vendorId: widget.vendorModel.id,
      entrySource: _sessionEntrySource,
      searchKeyword: _sessionSearchKeyword,
      searchType: _sessionSearchType,
      startedAt: _sessionStartedAt ?? DateTime.now(),
    );
    super.dispose();
  }

  void loadOrderType() async {
    SharedPreferences sp = await SharedPreferences.getInstance();
    setState(() {
      selectedOrderType =
          sp.getString("foodType") == "" || sp.getString("foodType") == null
              ? "Delivery".tr()
              : sp.getString("foodType");
    });
  }

  List<ReviewAttributeModel> reviewAttributeList = [];

  List<ProductModel> productList = [];
  List<ProductModel> storeProductList = [];
  bool showLoader = true;
  BrandsModel? brandModel;
  List<FavouriteItemModel> lstFav = [];

  List<AttributesModel> attributesList = [];
  List<RatingModel> reviewList = [];

  // SS/MS attribute selections
  // Key: attributeId, Value: list of selected ProductAttributeOption ids
  final Map<String, List<String>> _selectedAttrOptions = {};
  double _attrAddOnTotal = 0.0;

  getData() async {
    if (MyAppState.currentUser != null) {
      await FireStoreUtils()
          .getFavouritesProductList(MyAppState.currentUser!.userID)
          .then((value) {
        setState(() {
          lstFav = value;
        });
      });
    }

    if (widget.productModel.photos.isEmpty) {
      productImage.add(widget.productModel.photo);
    }
    for (var element in widget.productModel.photos) {
      productImage.add(element);
    }

    for (var element in variants!) {
      productImage.add(element.variant_image.toString());
    }

    await FireStoreUtils.getAttributes().then((value) {
      setState(() {
        attributesList = value;
      });
    });

    await FireStoreUtils.getAllReviewAttributes().then((value) {
      reviewAttributeList = value;
    });

    await FireStoreUtils().getReviewList(widget.productModel.id).then((value) {
      setState(() {
        reviewList = value;
      });
    });

    await FireStoreUtils.getProductListByCategoryId(
            widget.productModel.categoryID.toString())
        .then((value) {
      for (var element in value) {
        if (element.id != widget.productModel.id) {
          productList.add(element);
        }
      }
      setState(() {});
    });

    await FireStoreUtils.getStoreProduct(
            widget.productModel.vendorID.toString())
        .then((value) {
      for (var element in value) {
        if (element.id != widget.productModel.id) {
          storeProductList.add(element);
        }
      }
      setState(() {});
    });

    await FireStoreUtils.getBrands().then((value) {
      for (var element in value) {
        if (element.id == widget.productModel.brandID) {
          brandModel = element;
        }
      }
      setState(() {});
    });
    setState(() {});
  }

  void _initAttributeSelections() {
    final configs = widget.productModel.productAttributes;
    if (configs.isEmpty) return;
    setState(() {
      for (final cfg in configs) {
        _selectedAttrOptions[cfg.attributeId] = [];
        // For SS, pre-select first enabled option
        if (cfg.type == 'SS') {
          final firstEnabled = cfg.options.where((o) => o.enabled).firstOrNull;
          if (firstEnabled != null) {
            _selectedAttrOptions[cfg.attributeId] = [firstEnabled.id];
          }
        }
      }
      _recalcAttrTotal();
    });
  }

  void _recalcAttrTotal() {
    double total = 0.0;
    for (final cfg in widget.productModel.productAttributes) {
      final selectedIds = _selectedAttrOptions[cfg.attributeId] ?? [];
      for (final opt in cfg.options) {
        if (opt.enabled && selectedIds.contains(opt.id)) {
          total += opt.effectivePrice;
        }
      }
    }
    _attrAddOnTotal = total;
  }

  bool get _hasVariantPricing {
    return widget.productModel.productAttributes.isNotEmpty &&
        widget.productModel.productAttributes.any((cfg) => cfg.options.any((o) => o.enabled && o.price > 0));
  }

  double get _startsFromPrice {
    double minPrice = double.infinity;
    for (final cfg in widget.productModel.productAttributes) {
      for (final opt in cfg.options) {
        if (opt.enabled && opt.price > 0) {
          final ep = opt.effectivePrice;
          if (ep < minPrice) minPrice = ep;
        }
      }
    }
    return minPrice == double.infinity ? 0 : minPrice;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    cartDatabase = Provider.of<CartDatabase>(context, listen: false);

    cartDatabase.allCartProducts.then((value) {
      final bool _productIsInList = value.any((product) =>
          product.id ==
          widget.productModel.id +
              "~" +
              (variants!
                      .where((element) =>
                          element.variant_sku == selectedVariants.join('-'))
                      .isNotEmpty
                  ? variants!
                      .where((element) =>
                          element.variant_sku == selectedVariants.join('-'))
                      .first
                      .variant_id
                      .toString()
                  : ""));
      if (_productIsInList) {
        CartProduct element = value.firstWhere((product) =>
            product.id ==
            widget.productModel.id +
                "~" +
                (variants!
                        .where((element) =>
                            element.variant_sku == selectedVariants.join('-'))
                        .isNotEmpty
                    ? variants!
                        .where((element) =>
                            element.variant_sku == selectedVariants.join('-'))
                        .first
                        .variant_id
                        .toString()
                    : ""));

        setState(() {
          productQnt = element.quantity;
        });
      } else {
        setState(() {
          productQnt = 0;
        });
      }
    });
  }

  final PageController _controller =
      PageController(viewportFraction: 1, keepPage: true);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDeliveryActiveNotifier,
      builder: (context, deliveryActive, _) {
        if (selectedOrderType == 'Delivery'.tr() && !deliveryActive) {
          return ComingSoonScreen(message: deliveryOffMessageNotifier.value);
        }
        return _buildScreen(context);
      },
    );
  }

  Widget _buildScreen(BuildContext context) {
    // A product has explicit order-type restrictions only when at least one flag is set.
    // Legacy products (all flags false) are treated as unrestricted.
    final bool _hasRestrictions = widget.productModel.deliveryOption ||
        widget.productModel.takeaway ||
        widget.productModel.dineIn;
    final bool _isDineaway = selectedOrderType == "Takeaway".tr() ||
        selectedOrderType == "Dineaway".tr();

    final bool productSupportsDineaway =
        widget.productModel.dineIn || widget.productModel.takeaway;
    bool showAddButton = !_hasRestrictions ||
        (_isDineaway && productSupportsDineaway) ||
        (selectedOrderType == "Delivery".tr() && widget.productModel.deliveryOption);

    String unavailabilityMessage = "";
    if (_hasRestrictions) {
      if (_isDineaway && !productSupportsDineaway) {
        unavailabilityMessage = "This product is not available for DineAway";
      } else if (selectedOrderType == "Delivery".tr() &&
          !widget.productModel.deliveryOption) {
        unavailabilityMessage = "This product is not available for Delivery";
      }
    }

    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? AppThemeData.surfaceDark : const Color(0xFFF2F0F8),
      body: SingleChildScrollView(
        child: Column(children: [
          Stack(children: [
            // Hero image carousel
            SizedBox(
                height: (MediaQuery.of(context).size.height * 0.40).clamp(240.0, 380.0),
                width: MediaQuery.of(context).size.width,
                child: PageView.builder(
                    itemCount: productImage.length,
                    scrollDirection: Axis.horizontal,
                    controller: _controller,
                    onPageChanged: (value) {
                      setState(() {});
                    },
                    allowImplicitScrolling: true,
                    itemBuilder: (context, index) => CachedNetworkImage(
                          imageUrl: getImageVAlidUrl(productImage[index]),
                          imageBuilder: (context, imageProvider) => Container(
                            decoration: BoxDecoration(
                              image: DecorationImage(
                                  image: imageProvider, fit: BoxFit.cover),
                            ),
                          ),
                          placeholder: (context, url) => Center(
                              child: CircularProgressIndicator.adaptive(
                                valueColor: AlwaysStoppedAnimation(
                                    AppThemeData.primary500),
                              )),
                          errorWidget: (context, url, error) => Image.network(
                            placeholderImage,
                            fit: BoxFit.fitWidth,
                          ),
                          fit: BoxFit.cover,
                        ))),
            // Bottom gradient fade
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 100,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      (isDarkMode(context) ? AppThemeData.surfaceDark : AppThemeData.surface)
                          .withValues(alpha: 0.9),
                    ],
                  ),
                ),
              ),
            ),
            // Back button
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
            // Favorite button
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: GestureDetector(
                onTap: () {
                  if (MyAppState.currentUser == null) {
                    push(context, const LoginScreen());
                  } else {
                    setState(() {
                      final isFav = lstFav.any((e) => e.product_id == widget.productModel.id);
                      if (isFav) {
                        final m = FavouriteItemModel(
                            product_id: widget.productModel.id,
                            section_id: sectionConstantModel!.id,
                            store_id: widget.vendorModel.id,
                            user_id: MyAppState.currentUser!.userID);
                        lstFav.removeWhere((item) => item.product_id == widget.productModel.id);
                        FireStoreUtils.removeFavouriteItem(m);
                      } else {
                        final m = FavouriteItemModel(
                            product_id: widget.productModel.id,
                            section_id: sectionConstantModel!.id,
                            store_id: widget.vendorModel.id,
                            user_id: MyAppState.currentUser!.userID);
                        FireStoreUtils().setFavouriteStoreItem(m);
                        lstFav.add(m);
                      }
                    });
                  }
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    lstFav.any((e) => e.product_id == widget.productModel.id)
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: lstFav.any((e) => e.product_id == widget.productModel.id)
                        ? Colors.redAccent
                        : Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
            // Page indicator dots
            if (productImage.length > 1)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Indicator(
                  controller: _controller,
                  itemCount: productImage.length,
                ),
              ),
          ]),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: isDarkMode(context) ? AppThemeData.surfaceDark : Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            margin: const EdgeInsets.only(top: 0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.productModel.name,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontFamily: AppThemeData.bold,
                                      color: isDarkMode(context)
                                          ? AppThemeData.grey50
                                          : AppThemeData.grey900,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Builder(builder: (ctx) {
                                    if (_hasVariantPricing) {
                                      final displayPrice = _attrAddOnTotal > 0 ? _attrAddOnTotal : _startsFromPrice;
                                      return Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _attrAddOnTotal > 0 ? 'Selected Price'.tr() : 'Starts From'.tr(),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontFamily: AppThemeData.regular,
                                                  color: isDarkMode(ctx) ? AppThemeData.grey500 : AppThemeData.grey400,
                                                ),
                                              ),
                                              Text(
                                                amountShow(amount: productCommissionPrice(displayPrice.toStringAsFixed(2))),
                                                style: const TextStyle(
                                                  fontSize: 24,
                                                  letterSpacing: 0.5,
                                                  fontFamily: AppThemeData.bold,
                                                  color: AppThemeData.primary500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      );
                                    }
                                    return Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          (widget.productModel.disPrice == "" || widget.productModel.disPrice == "0")
                                              ? amountShow(amount: productCommissionPrice(widget.productModel.price))
                                              : amountShow(amount: productCommissionPrice(widget.productModel.disPrice.toString())),
                                          style: const TextStyle(
                                            fontSize: 24,
                                            letterSpacing: 0.5,
                                            fontFamily: AppThemeData.bold,
                                            color: AppThemeData.primary500,
                                          ),
                                        ),
                                        if (widget.productModel.disPrice != null &&
                                            widget.productModel.disPrice != "" &&
                                            widget.productModel.disPrice != "0") ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            amountShow(amount: productCommissionPrice(widget.productModel.price)),
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontFamily: AppThemeData.regular,
                                              color: isDarkMode(ctx) ? AppThemeData.grey500 : AppThemeData.grey400,
                                              decoration: TextDecoration.lineThrough,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Builder(builder: (_) {
                                            final orig = double.tryParse(widget.productModel.price) ?? 0;
                                            final disc = double.tryParse(widget.productModel.disPrice ?? '0') ?? 0;
                                            final pct = orig > 0 ? ((orig - disc) / orig * 100).round() : 0;
                                            if (pct <= 0) return const SizedBox.shrink();
                                            return Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: AppThemeData.primary500.withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '$pct% OFF',
                                                style: const TextStyle(
                                                  color: AppThemeData.primary500,
                                                  fontSize: 11,
                                                  fontFamily: AppThemeData.semiBold,
                                                ),
                                              ),
                                            );
                                          }),
                                        ],
                                      ],
                                    );
                                  }),
                                  if (widget.productModel.nutritionEnabled &&
                                      widget.productModel.nutritionInfo != null) ...[
                                    const SizedBox(height: 10),
                                    _buildNutritionHighlightChips(context, widget.productModel.nutritionInfo!),
                                  ],
                               //--
                                ],
                              ),
                            ),
                            sectionConstantModel!.serviceTypeFlag ==
                                    "ecommerce-service"
                                ? productQnt == 0
                                    ? Visibility(
                                        visible: showAddButton,
                                        child: RoundedButtonFill(
                                          title: "Add".tr(),
                                          width: 22,
                                          height: 4,
                                          color: isDarkMode(context)
                                              ? AppThemeData.primary500
                                              : AppThemeData.primary500,
                                          textColor: AppThemeData.grey50,
                                          isRight: true,
                                          icon: Icon(
                                            Icons.add,
                                            color: AppThemeData.grey50,
                                          ),
                                          onPress: () async {
                                            if (MyAppState.currentUser ==
                                                null) {
                                              push(
                                                  context, const LoginScreen());
                                            } else {
                                              setState(() {
                                                print(
                                                    "Variant---->${variants}");
                                                print(
                                                    "Variant---->${selectedVariants}");
                                                if (variants!
                                                    .where((element) =>
                                                        element.variant_sku ==
                                                        selectedVariants
                                                            .join('-'))
                                                    .isNotEmpty) {
                                                  if (int.parse(variants!
                                                              .where((element) =>
                                                                  element
                                                                      .variant_sku ==
                                                                  selectedVariants
                                                                      .join(
                                                                          '-'))
                                                              .first
                                                              .variant_quantity
                                                              .toString()) >=
                                                          1 ||
                                                      int.parse(variants!
                                                              .where((element) =>
                                                                  element
                                                                      .variant_sku ==
                                                                  selectedVariants
                                                                      .join(
                                                                          '-'))
                                                              .first
                                                              .variant_quantity
                                                              .toString()) ==
                                                          -1) {
                                                    VariantInfo? variantInfo =
                                                        VariantInfo();
                                                    widget.productModel
                                                        .price = variants!
                                                            .where((element) =>
                                                                element
                                                                    .variant_sku ==
                                                                selectedVariants
                                                                    .join('-'))
                                                            .first
                                                            .variant_price ??
                                                        '0';
                                                    widget.productModel
                                                        .disPrice = '0';

                                                    Map<String, String>
                                                        mapData = Map();
                                                    for (var element
                                                        in attributes!) {
                                                      mapData.addEntries([
                                                        MapEntry(
                                                            attributesList
                                                                .where((element1) =>
                                                                    element
                                                                        .attributesId ==
                                                                    element1.id)
                                                                .first
                                                                .title
                                                                .toString(),
                                                            selectedVariants[
                                                                attributes!
                                                                    .indexOf(
                                                                        element)])
                                                      ]);
                                                      setState(() {});
                                                    }

                                                    variantInfo = VariantInfo(
                                                        variant_price: variants!
                                                                .where((element) =>
                                                                    element.variant_sku ==
                                                                    selectedVariants.join(
                                                                        '-'))
                                                                .first
                                                                .variant_price ??
                                                            '0',
                                                        variant_sku:
                                                            selectedVariants
                                                                .join('-'),
                                                        variant_options:
                                                            mapData,
                                                        variant_image: variants!
                                                                .where((element) =>
                                                                    element.variant_sku ==
                                                                    selectedVariants.join(
                                                                        '-'))
                                                                .first
                                                                .variant_image ??
                                                            '',
                                                        variant_id: variants!
                                                                .where((element) => element.variant_sku == selectedVariants.join('-'))
                                                                .first
                                                                .variant_id ??
                                                            '0');

                                                    widget.productModel
                                                            .variant_info =
                                                        variantInfo;

                                                    setState(() {
                                                      productQnt = 1;
                                                    });
                                                    addtocard(
                                                        widget.productModel,
                                                        true);
                                                  } else {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                            const SnackBar(
                                                      content: Text(
                                                          "Product is out of Stock"),
                                                    ));
                                                  }
                                                } else {
                                                  if (widget.productModel
                                                              .quantity >
                                                          productQnt ||
                                                      widget.productModel
                                                              .quantity ==
                                                          -1) {
                                                    setState(() {
                                                      productQnt = 1;
                                                    });
                                                    addtocard(
                                                        widget.productModel,
                                                        true);
                                                  } else {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                            const SnackBar(
                                                      content: Text(
                                                          "Product is out of Stock"),
                                                    ));
                                                  }
                                                }
                                              });
                                            }
                                          },
                                        ),
                                      )
                                    : Container(
                                        width: Responsive.width(24, context),
                                        height: Responsive.height(5, context),
                                        decoration: ShapeDecoration(
                                          color: isDarkMode(context)
                                              ? AppThemeData.grey900
                                              : AppThemeData.grey100,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(200),
                                            side: isDarkMode(context)
                                                ? BorderSide.none
                                                : const BorderSide(
                                                    color: Color(0xFFE5E1FF),
                                                    width: 1),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            InkWell(
                                                onTap: () {
                                                  setState(() {
                                                    if (productQnt != 0) {
                                                      productQnt--;
                                                    }
                                                    if (productQnt >= 0) {
                                                      removetocard(
                                                          widget.productModel,
                                                          true);
                                                    }
                                                  });
                                                },
                                                child:
                                                    const Icon(Icons.remove)),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 14),
                                              child: Text(
                                                productQnt.toString(),
                                                textAlign: TextAlign.start,
                                                maxLines: 1,
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  fontFamily:
                                                      AppThemeData.medium,
                                                  fontWeight: FontWeight.w500,
                                                  color: isDarkMode(context)
                                                      ? AppThemeData.grey100
                                                      : AppThemeData.grey800,
                                                ),
                                              ),
                                            ),
                                            InkWell(
                                                onTap: () {
                                                  setState(() {
                                                    if (variants!
                                                        .where((element) =>
                                                            element
                                                                .variant_sku ==
                                                            selectedVariants
                                                                .join('-'))
                                                        .isNotEmpty) {
                                                      if (int.parse(variants!
                                                                  .where((element) =>
                                                                      element
                                                                          .variant_sku ==
                                                                      selectedVariants
                                                                          .join(
                                                                              '-'))
                                                                  .first
                                                                  .variant_quantity
                                                                  .toString()) >
                                                              productQnt ||
                                                          int.parse(variants!
                                                                  .where((element) =>
                                                                      element
                                                                          .variant_sku ==
                                                                      selectedVariants
                                                                          .join(
                                                                              '-'))
                                                                  .first
                                                                  .variant_quantity
                                                                  .toString()) ==
                                                              -1) {
                                                        VariantInfo?
                                                            variantInfo =
                                                            VariantInfo();
                                                        Map<String, String>
                                                            mapData = Map();
                                                        for (var element
                                                            in attributes!) {
                                                          mapData.addEntries([
                                                            MapEntry(
                                                                attributesList
                                                                    .where((element1) =>
                                                                        element
                                                                            .attributesId ==
                                                                        element1
                                                                            .id)
                                                                    .first
                                                                    .title
                                                                    .toString(),
                                                                selectedVariants[
                                                                    attributes!
                                                                        .indexOf(
                                                                            element)])
                                                          ]);
                                                          setState(() {});
                                                        }

                                                        variantInfo = VariantInfo(
                                                            variant_price: variants!
                                                                    .where((element) =>
                                                                        element.variant_sku ==
                                                                        selectedVariants.join(
                                                                            '-'))
                                                                    .first
                                                                    .variant_price ??
                                                                '0',
                                                            variant_sku: selectedVariants
                                                                .join('-'),
                                                            variant_options:
                                                                mapData,
                                                            variant_image: variants!
                                                                    .where((element) =>
                                                                        element.variant_sku ==
                                                                        selectedVariants.join(
                                                                            '-'))
                                                                    .first
                                                                    .variant_image ??
                                                                '',
                                                            variant_id: variants!
                                                                    .where((element) => element.variant_sku == selectedVariants.join('-'))
                                                                    .first
                                                                    .variant_id ??
                                                                '0');

                                                        widget.productModel
                                                                .variant_info =
                                                            variantInfo;
                                                        if (productQnt != 0) {
                                                          productQnt++;
                                                        }
                                                        // widget.productModel.price = widget.productModel.disPrice == "" || widget.productModel.disPrice == "0" ? (widget.productModel.price) : (widget.productModel.disPrice!);
                                                        addtocard(
                                                            widget.productModel,
                                                            true);
                                                      } else {
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(
                                                                const SnackBar(
                                                          content: Text(
                                                              "Product is out of Stock"),
                                                        ));
                                                      }
                                                    } else {
                                                      if (widget.productModel
                                                                  .quantity >
                                                              productQnt ||
                                                          widget.productModel
                                                                  .quantity ==
                                                              -1) {
                                                        if (productQnt != 0) {
                                                          productQnt++;
                                                        }
                                                        // widget.productModel.price = widget.productModel.disPrice == "" || widget.productModel.disPrice == "0" ? (widget.productModel.price) : (widget.productModel.disPrice!);
                                                        addtocard(
                                                            widget.productModel,
                                                            true);
                                                      } else {
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(
                                                                const SnackBar(
                                                          content: Text(
                                                              "Product is out of Stock"),
                                                        ));
                                                      }
                                                    }
                                                  });
                                                },
                                                child: const Icon(Icons.add)),
                                          ],
                                        ),
                                      )
                                : Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                        productQnt == 0
                                            ? isOpen == false
                                                ? const Center()
                                                : Visibility(
                                                    visible: showAddButton,
                                                    child: RoundedButtonFill(
                                                      title: "Add".tr(),
                                                      width: 22,
                                                      height: 4,
                                                      color: isDarkMode(context)
                                                          ? AppThemeData.grey700
                                                          : AppThemeData
                                                              .grey200,
                                                      textColor:
                                                          isDarkMode(context)
                                                              ? AppThemeData
                                                                  .grey50
                                                              : AppThemeData
                                                                  .grey900,
                                                      isRight: true,
                                                      icon: Icon(
                                                        Icons.add,
                                                        color:
                                                            isDarkMode(context)
                                                                ? AppThemeData
                                                                    .grey50
                                                                : AppThemeData
                                                                    .grey900,
                                                      ),
                                                      onPress: () async {
                                                        if (MyAppState
                                                                .currentUser ==
                                                            null) {
                                                          push(context,
                                                              const LoginScreen());
                                                        } else {
                                                          setState(() {
                                                            print(
                                                                "Variant---->${variants}");
                                                            print(
                                                                "Variant---->${selectedVariants}");
                                                            if (variants!
                                                                .where((element) =>
                                                                    element
                                                                        .variant_sku ==
                                                                    selectedVariants
                                                                        .join(
                                                                            '-'))
                                                                .isNotEmpty) {
                                                              if (int.parse(variants!
                                                                          .where((element) =>
                                                                              element.variant_sku ==
                                                                              selectedVariants.join(
                                                                                  '-'))
                                                                          .first
                                                                          .variant_quantity
                                                                          .toString()) >=
                                                                      1 ||
                                                                  int.parse(variants!
                                                                          .where((element) =>
                                                                              element.variant_sku ==
                                                                              selectedVariants.join('-'))
                                                                          .first
                                                                          .variant_quantity
                                                                          .toString()) ==
                                                                      -1) {
                                                                VariantInfo?
                                                                    variantInfo =
                                                                    VariantInfo();
                                                                widget
                                                                    .productModel
                                                                    .price = variants!
                                                                        .where((element) =>
                                                                            element.variant_sku ==
                                                                            selectedVariants.join('-'))
                                                                        .first
                                                                        .variant_price ??
                                                                    '0';
                                                                widget
                                                                    .productModel
                                                                    .disPrice = '0';

                                                                Map<String,
                                                                        String>
                                                                    mapData =
                                                                    Map();
                                                                for (var element
                                                                    in attributes!) {
                                                                  mapData
                                                                      .addEntries([
                                                                    MapEntry(
                                                                        attributesList
                                                                            .where((element1) =>
                                                                                element.attributesId ==
                                                                                element1.id)
                                                                            .first
                                                                            .title
                                                                            .toString(),
                                                                        selectedVariants[attributes!.indexOf(element)])
                                                                  ]);
                                                                  setState(
                                                                      () {});
                                                                }

                                                                variantInfo = VariantInfo(
                                                                    variant_price: variants!
                                                                            .where((element) =>
                                                                                element.variant_sku ==
                                                                                selectedVariants.join(
                                                                                    '-'))
                                                                            .first
                                                                            .variant_price ??
                                                                        '0',
                                                                    variant_sku:
                                                                        selectedVariants.join(
                                                                            '-'),
                                                                    variant_options:
                                                                        mapData,
                                                                    variant_image:
                                                                        variants!.where((element) => element.variant_sku == selectedVariants.join('-')).first.variant_image ??
                                                                            '',
                                                                    variant_id: variants!
                                                                            .where((element) =>
                                                                                element.variant_sku ==
                                                                                selectedVariants.join('-'))
                                                                            .first
                                                                            .variant_id ??
                                                                        '0');

                                                                widget.productModel
                                                                        .variant_info =
                                                                    variantInfo;

                                                                setState(() {
                                                                  productQnt =
                                                                      1;
                                                                });
                                                                addtocard(
                                                                    widget
                                                                        .productModel,
                                                                    true);
                                                              } else {
                                                                ScaffoldMessenger.of(
                                                                        context)
                                                                    .showSnackBar(
                                                                        const SnackBar(
                                                                  content: Text(
                                                                      "Product is out of Stock"),
                                                                ));
                                                              }
                                                            } else {
                                                              if (widget.productModel
                                                                          .quantity >
                                                                      productQnt ||
                                                                  widget.productModel
                                                                          .quantity ==
                                                                      -1) {
                                                                setState(() {
                                                                  productQnt =
                                                                      1;
                                                                });
                                                                addtocard(
                                                                    widget
                                                                        .productModel,
                                                                    true);
                                                              } else {
                                                                ScaffoldMessenger.of(
                                                                        context)
                                                                    .showSnackBar(
                                                                        const SnackBar(
                                                                  content: Text(
                                                                      "Product is out of Stock"),
                                                                ));
                                                              }
                                                            }
                                                          });
                                                        }
                                                      },
                                                    ),
                                                  )
                                            : isOpen == false
                                                ? Container()
                                                : Container(
                                                    width: Responsive.width(
                                                        24, context),
                                                    height: Responsive.height(
                                                        5, context),
                                                    decoration: ShapeDecoration(
                                                      color: isDarkMode(context)
                                                          ? AppThemeData.grey900
                                                          : AppThemeData.grey100,
                                                      shape:
                                                          RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(200),
                                                        side: isDarkMode(context)
                                                            ? BorderSide.none
                                                            : const BorderSide(
                                                                color: Color(0xFFE5E1FF),
                                                                width: 1),
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .center,
                                                      children: [
                                                        InkWell(
                                                            onTap: () {
                                                              setState(() {
                                                                if (productQnt !=
                                                                    0) {
                                                                  productQnt--;
                                                                }
                                                                if (productQnt >=
                                                                    0) {
                                                                  removetocard(
                                                                      widget
                                                                          .productModel,
                                                                      true);
                                                                }
                                                              });
                                                            },
                                                            child: const Icon(
                                                                Icons.remove)),
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      14),
                                                          child: Text(
                                                            productQnt
                                                                .toString(),
                                                            textAlign:
                                                                TextAlign.start,
                                                            maxLines: 1,
                                                            style: TextStyle(
                                                              fontSize: 16,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              fontFamily:
                                                                  AppThemeData
                                                                      .medium,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                              color: isDarkMode(
                                                                      context)
                                                                  ? AppThemeData
                                                                      .grey100
                                                                  : AppThemeData
                                                                      .grey800,
                                                            ),
                                                          ),
                                                        ),
                                                        InkWell(
                                                            onTap: () {
                                                              setState(() {
                                                                if (variants!
                                                                    .where((element) =>
                                                                        element
                                                                            .variant_sku ==
                                                                        selectedVariants
                                                                            .join('-'))
                                                                    .isNotEmpty) {
                                                                  if (int.parse(variants!.where((element) => element.variant_sku == selectedVariants.join('-')).first.variant_quantity.toString()) >
                                                                          productQnt ||
                                                                      int.parse(variants!
                                                                              .where((element) => element.variant_sku == selectedVariants.join('-'))
                                                                              .first
                                                                              .variant_quantity
                                                                              .toString()) ==
                                                                          -1) {
                                                                    VariantInfo?
                                                                        variantInfo =
                                                                        VariantInfo();
                                                                    Map<String,
                                                                            String>
                                                                        mapData =
                                                                        Map();
                                                                    for (var element
                                                                        in attributes!) {
                                                                      mapData
                                                                          .addEntries([
                                                                        MapEntry(
                                                                            attributesList.where((element1) => element.attributesId == element1.id).first.title.toString(),
                                                                            selectedVariants[attributes!.indexOf(element)])
                                                                      ]);
                                                                      setState(
                                                                          () {});
                                                                    }

                                                                    variantInfo = VariantInfo(
                                                                        variant_price:
                                                                            variants!.where((element) => element.variant_sku == selectedVariants.join('-')).first.variant_price ??
                                                                                '0',
                                                                        variant_sku:
                                                                            selectedVariants.join(
                                                                                '-'),
                                                                        variant_options:
                                                                            mapData,
                                                                        variant_image:
                                                                            variants!.where((element) => element.variant_sku == selectedVariants.join('-')).first.variant_image ??
                                                                                '',
                                                                        variant_id:
                                                                            variants!.where((element) => element.variant_sku == selectedVariants.join('-')).first.variant_id ??
                                                                                '0');

                                                                    widget.productModel
                                                                            .variant_info =
                                                                        variantInfo;
                                                                    if (productQnt !=
                                                                        0) {
                                                                      productQnt++;
                                                                    }
                                                                    // widget.productModel.price = widget.productModel.disPrice == "" || widget.productModel.disPrice == "0" ? (widget.productModel.price) : (widget.productModel.disPrice!);
                                                                    addtocard(
                                                                        widget
                                                                            .productModel,
                                                                        true);
                                                                  } else {
                                                                    ScaffoldMessenger.of(
                                                                            context)
                                                                        .showSnackBar(
                                                                            const SnackBar(
                                                                      content: Text(
                                                                          "Product is out of Stock"),
                                                                    ));
                                                                  }
                                                                } else {
                                                                  if (widget.productModel
                                                                              .quantity >
                                                                          productQnt ||
                                                                      widget.productModel
                                                                              .quantity ==
                                                                          -1) {
                                                                    if (productQnt != 0) {
                                                                      productQnt++;
                                                                    }
                                                                    // widget.productModel.price = widget.productModel.disPrice == "" || widget.productModel.disPrice == "0" ? (widget.productModel.price) : (widget.productModel.disPrice!);
                                                                    addtocard(
                                                                        widget
                                                                            .productModel,
                                                                        true);
                                                                  } else {
                                                                    ScaffoldMessenger.of(
                                                                            context)
                                                                        .showSnackBar(
                                                                            const SnackBar(
                                                                      content: Text(
                                                                          "Product is out of Stock"),
                                                                    ));
                                                                  }
                                                                }
                                                              });
                                                            },
                                                            child: const Icon(
                                                                Icons.add)),
                                                      ],
                                                    ),
                                                  ),
                                      ]),
                          ],
                        ),
                        const SizedBox(
                          height: 10,
                      
                      
                      
                        ),
                        if (unavailabilityMessage.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Container(
                              width: double.infinity,
                              padding: EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 12),
                              decoration: BoxDecoration(
                                  color:
                                      AppThemeData.danger300.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: AppThemeData.danger300
                                          .withOpacity(0.5))),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      color: AppThemeData.danger300, size: 20),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      unavailabilityMessage.tr(),
                                      style: TextStyle(
                                        color: AppThemeData.danger300,
                                        fontFamily: AppThemeData.medium,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                           const SizedBox(
                          height: 10,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isDarkMode(context)
                                      ? AppThemeData.grey900
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: isDarkMode(context)
                                      ? null
                                      : Border.all(
                                          color: const Color(0xFFE5E1FF),
                                          width: 1,
                                        ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0x0A000000),
                                      blurRadius: 8,
                                      offset: Offset(0, 2),
                                      spreadRadius: 0,
                                    )
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: AppThemeData.primary500.withOpacity(0.2),
                                          width: 2,
                                        ),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: CachedNetworkImage(
                                          height: 40,
                                          width: 40,
                                          imageUrl: getImageVAlidUrl(widget.vendorModel.photo),
                                          imageBuilder: (context, imageProvider) => Container(
                                            decoration: BoxDecoration(
                                              image: DecorationImage(
                                                image: imageProvider,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          ),
                                          placeholder: (context, url) => Container(
                                            padding: EdgeInsets.all(8),
                                            child: CircularProgressIndicator.adaptive(
                                              valueColor: AlwaysStoppedAnimation(AppThemeData.primary500),
                                              strokeWidth: 2,
                                            ),
                                          ),
                                          errorWidget: (context, url, error) => Container(
                                            padding: EdgeInsets.all(8),
                                            child: Icon(
                                              Icons.store,
                                              color: AppThemeData.primary500,
                                            ),
                                          ),
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "Store",
                                            style: TextStyle(
                                              fontFamily: AppThemeData.regular,
                                              fontSize: 12,
                                              color: isDarkMode(context)
                                                  ? AppThemeData.grey300
                                                  : AppThemeData.grey600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            widget.vendorModel.title,
                                            style: TextStyle(
                                              fontFamily: AppThemeData.medium,
                                              fontSize: 14,
                                              color: isDarkMode(context)
                                                  ? AppThemeData.grey100
                                                  : AppThemeData.grey900,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () async {
                                          BehaviorTracker.setNextEntrySource('ProductDetails');
                                          push(
                                            context,
                                            NewVendorProductsScreen(vendorModel: widget.vendorModel),
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(20),
                                        child: Container(
                                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: AppThemeData.primary500.withOpacity(0.17),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            "Visit Store",
                                            style: TextStyle(
                                              fontFamily: AppThemeData.medium,
                                              color: AppThemeData.primary500,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                         
                            brandModel == null
                                ? Container()
                                : Expanded(
                                    child: Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(2),
                                          child: CachedNetworkImage(
                                            height: 40,
                                            width: 40,
                                            imageUrl: getImageVAlidUrl(
                                                brandModel!.photo.toString()),
                                            imageBuilder:
                                                (context, imageProvider) =>
                                                    Container(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                image: DecorationImage(
                                                    image: imageProvider,
                                                    fit: BoxFit.cover),
                                              ),
                                            ),
                                            placeholder: (context, url) => Center(
                                              child: CircularProgressIndicator.adaptive(
                                                valueColor: AlwaysStoppedAnimation(
                                                  AppThemeData.primary500
                                                ),
                                              )
                                            ),
                                            errorWidget: (context, url, error) => ClipRRect(
                                              borderRadius: BorderRadius.circular(15),
                                              child: Image.network(
                                                placeholderImage,
                                                fit: BoxFit.cover,
                                              )
                                            ),
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        const SizedBox(
                                          width: 10,
                                        ),
                                        InkWell(
                                            onTap: null,
                                            child: Text(
                                                brandModel != null
                                                    ? brandModel!.title
                                                        .toString()
                                                    : "",
                                                style: TextStyle(
                                                    color: AppThemeData
                                                        .primary500))),
                                      ],
                                    ),
                                  ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 15, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Details".tr(),
                              textAlign: TextAlign.start,
                              style: TextStyle(
                                fontFamily: AppThemeData.bold,
                                fontSize: 18,
                                color: isDarkMode(context)
                                    ? AppThemeData.grey50
                                    : AppThemeData.grey900,
                              ),
                            ),
                            Icon(
                              Icons.info_outline,
                              color: AppThemeData.primary500,
                              size: 20,
                            ),
                          ],
                        ),
                        const SizedBox(
                          height: 10,
                        ),
                        Container(
                          width: Responsive.width(100, context),
                          decoration: BoxDecoration(
                            color: isDarkMode(context)
                                ? AppThemeData.grey900
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: isDarkMode(context)
                                ? null
                                : Border.all(
                                    color: const Color(0xFFE5E1FF),
                                    width: 1,
                                  ),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x0A000000),
                                blurRadius: 16,
                                offset: Offset(0, 4),
                                spreadRadius: 0,
                              )
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.productModel.description,
                                  style: TextStyle(
                                    fontFamily: AppThemeData.regular,
                                    fontSize: 14,
                                    height: 1.5,
                                    color: isDarkMode(context)
                                        ? AppThemeData.grey200
                                        : AppThemeData.grey700,
                                  ),
                                ),
                                sectionConstantModel!.isProductDetails == false
                                    ? SizedBox()
                                    : Column(
                                        children: [
                                          // Padding(
                                          //   padding: const EdgeInsets.symmetric(
                                          //       vertical: 16),
                                          //   child: Divider(thickness: 1),
                                          // ),
                                          // Row(
                                          //   children: [
                                          //     Expanded(
                                          //       child: Container(
                                          //         padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                          //         decoration: BoxDecoration(
                                          //           color: isDarkMode(context) 
                                          //               ? AppThemeData.grey800.withOpacity(0.5)
                                          //               : AppThemeData.primary500.withOpacity(0.08),
                                          //           borderRadius: BorderRadius.circular(10),
                                          //         ),
                                          //         child: Column(
                                          //           crossAxisAlignment: CrossAxisAlignment.start,
                                          //           children: [
                                          //             Text(
                                          //               "Calories",
                                          //               style: TextStyle(
                                          //                 fontFamily: AppThemeData.regular,
                                          //                 fontSize: 12,
                                          //                 color: isDarkMode(context)
                                          //                     ? AppThemeData.grey300
                                          //                     : AppThemeData.grey600,
                                          //               ),
                                          //             ),
                                          //             SizedBox(height: 4),
                                          //             Text(
                                          //               "${widget.productModel.calories}",
                                          //               style: TextStyle(
                                          //                 fontFamily: AppThemeData.bold,
                                          //                 fontSize: 15,
                                          //                 color: isDarkMode(context)
                                          //                     ? AppThemeData.grey100
                                          //                     : AppThemeData.grey900,
                                          //               ),
                                          //             ),
                                          //           ],
                                          //         ),
                                          //       ),
                                          //     ),
                                          //     SizedBox(width: 8),
                                          //     Expanded(
                                          //       child: Container(
                                          //         padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                          //         decoration: BoxDecoration(
                                          //           color: isDarkMode(context) 
                                          //               ? AppThemeData.grey800.withOpacity(0.5)
                                          //               : AppThemeData.primary500.withOpacity(0.08),
                                          //           borderRadius: BorderRadius.circular(10),
                                          //         ),
                                          //         child: Column(
                                          //           crossAxisAlignment: CrossAxisAlignment.start,
                                          //           children: [
                                          //             Text(
                                          //               "Fats",
                                          //               style: TextStyle(
                                          //                 fontFamily: AppThemeData.regular,
                                          //                 fontSize: 12,
                                          //                 color: isDarkMode(context)
                                          //                     ? AppThemeData.grey300
                                          //                     : AppThemeData.grey600,
                                          //               ),
                                          //             ),
                                          //             SizedBox(height: 4),
                                          //             Text(
                                          //               "${widget.productModel.fats}",
                                          //               style: TextStyle(
                                          //                 fontFamily: AppThemeData.bold,
                                          //                 fontSize: 15,
                                          //                 color: isDarkMode(context)
                                          //                     ? AppThemeData.grey100
                                          //                     : AppThemeData.grey900,
                                          //               ),
                                          //             ),
                                          //           ],
                                          //         ),
                                          //       ),
                                          //     ),
                                          //   ],
                                          // ),
                                      
                                      
                                          // SizedBox(
                                          //   height: 5,
                                          // ),
                                          // SizedBox(
                                          //   height: 5,
                                          // ),
                                          // SizedBox(height: 10),
                                          // Row(
                                          //   children: [
                                          //     Expanded(
                                          //       child: Container(
                                          //         padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                          //         decoration: BoxDecoration(
                                          //           color: isDarkMode(context) 
                                          //               ? AppThemeData.grey800.withOpacity(0.5)
                                          //               : AppThemeData.primary500.withOpacity(0.08),
                                          //           borderRadius: BorderRadius.circular(10),
                                          //         ),
                                          //         child: Column(
                                          //           crossAxisAlignment: CrossAxisAlignment.start,
                                          //           children: [
                                          //             Text(
                                          //               "Proteins",
                                          //               style: TextStyle(
                                          //                 fontFamily: AppThemeData.regular,
                                          //                 fontSize: 12,
                                          //                 color: isDarkMode(context)
                                          //                     ? AppThemeData.grey300
                                          //                     : AppThemeData.grey600,
                                          //               ),
                                          //             ),
                                          //             SizedBox(height: 4),
                                          //             Text(
                                          //               "${widget.productModel.proteins}",
                                          //               style: TextStyle(
                                          //                 fontFamily: AppThemeData.bold,
                                          //                 fontSize: 15,
                                          //                 color: isDarkMode(context)
                                          //                     ? AppThemeData.grey100
                                          //                     : AppThemeData.grey900,
                                          //               ),
                                          //             ),
                                          //           ],
                                          //         ),
                                          //       ),
                                          //     ),
                                          //     SizedBox(width: 8),
                                          //     Expanded(
                                          //       child: Container(
                                          //         padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                          //         decoration: BoxDecoration(
                                          //           color: isDarkMode(context) 
                                          //               ? AppThemeData.grey800.withOpacity(0.5)
                                          //               : AppThemeData.primary500.withOpacity(0.08),
                                          //           borderRadius: BorderRadius.circular(10),
                                          //         ),
                                          //         child: Column(
                                          //           crossAxisAlignment: CrossAxisAlignment.start,
                                          //           children: [
                                          //             Text(
                                          //               "Grams",
                                          //               style: TextStyle(
                                          //                 fontFamily: AppThemeData.regular,
                                          //                 fontSize: 12,
                                          //                 color: isDarkMode(context)
                                          //                     ? AppThemeData.grey300
                                          //                     : AppThemeData.grey600,
                                          //               ),
                                          //             ),
                                          //             SizedBox(height: 4),
                                          //             Text(
                                          //               "${widget.productModel.grams}",
                                          //               style: TextStyle(
                                          //                 fontFamily: AppThemeData.bold,
                                          //                 fontSize: 15,
                                          //                 color: isDarkMode(context)
                                          //                     ? AppThemeData.grey100
                                          //                     : AppThemeData.grey900,
                                          //               ),
                                          //             ),
                                          //           ],
                                          //         ),
                                          //       ),
                                          //     ),
                                          //   ],
                                          // ),
                                       
                                       
                                        ],
                                      ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // NEW: SS/MS dynamic attribute section
                  if (widget.productModel.productAttributes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: _buildDynamicAttributeSection(context),
                    ),
                  if (widget.productModel.productAttributes.isEmpty && attributes != null && attributes!.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Variants".tr(),
                                    textAlign: TextAlign.start,
                                    style: TextStyle(
                                      fontFamily: AppThemeData.bold,
                                      fontSize: 18,
                                      color: isDarkMode(context)
                                          ? AppThemeData.grey50
                                          : AppThemeData.grey900,
                                    ),
                                  ),
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppThemeData.primary500.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      "${attributes!.length} ${attributes!.length > 1 ? 'options' : 'option'}",
                                      style: TextStyle(
                                        fontFamily: AppThemeData.medium,
                                        fontSize: 12,
                                        color: AppThemeData.primary500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(
                                height: 16,
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  color: isDarkMode(context)
                                      ? AppThemeData.grey900
                                      : AppThemeData.grey100,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0x0A000000),
                                      blurRadius: 16,
                                      offset: Offset(0, 4),
                                      spreadRadius: 0,
                                    )
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: ListView.builder(
                                    itemCount: attributes!.length,
                                    shrinkWrap: true,
                                    padding: EdgeInsets.zero,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemBuilder: (context, index) {
                                      String title = "";
                                      for (var element in attributesList) {
                                        if (attributes![index].attributesId ==
                                            element.id) {
                                          title = element.title.toString();
                                        }
                                      }
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 5),
                                            child: Text(
                                              title.tr(),
                                              textAlign: TextAlign.start,
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontFamily:
                                                    AppThemeData.regular,
                                                color: isDarkMode(context)
                                                    ? AppThemeData.grey200
                                                    : AppThemeData.grey700,
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 15),
                                            child: Wrap(
                                              spacing: 6.0,
                                              runSpacing: 6.0,
                                              children: List.generate(
                                                attributes![index]
                                                    .attributeOptions!
                                                    .length,
                                                (i) {
                                                  return InkWell(
                                                      onTap: () async {
                                                        print("------------->" +
                                                            widget.productModel
                                                                .id +
                                                            "~" +
                                                            variants!
                                                                .where((element) =>
                                                                    element
                                                                        .variant_sku ==
                                                                    selectedVariants
                                                                        .join(
                                                                            '-'))
                                                                .first
                                                                .variant_id
                                                                .toString());

                                                        setState(() {
                                                          if (selectedIndexVariants
                                                              .where((element) =>
                                                                  element.contains(
                                                                      '$index _'))
                                                              .isEmpty) {
                                                            selectedVariants.insert(
                                                                index,
                                                                attributes![
                                                                        index]
                                                                    .attributeOptions![
                                                                        i]
                                                                    .toString());
                                                            selectedIndexVariants
                                                                .add(
                                                                    '$index _${attributes![index].attributeOptions![i].toString()}');
                                                            selectedIndexArray.add(
                                                                '${index}_$i');
                                                          } else {
                                                            selectedIndexArray
                                                                .remove(
                                                                    '${index}_${attributes![index].attributeOptions?.indexOf(selectedIndexVariants.where((element) => element.contains('$index _')).first.replaceAll('$index _', ''))}');
                                                            selectedVariants
                                                                .removeAt(
                                                                    index);
                                                            selectedIndexVariants.remove(
                                                                selectedIndexVariants
                                                                    .where((element) =>
                                                                        element.contains(
                                                                            '$index _'))
                                                                    .first);
                                                            selectedVariants.insert(
                                                                index,
                                                                attributes![
                                                                        index]
                                                                    .attributeOptions![
                                                                        i]
                                                                    .toString());
                                                            selectedIndexVariants
                                                                .add(
                                                                    '$index _${attributes![index].attributeOptions![i].toString()}');
                                                            selectedIndexArray.add(
                                                                '${index}_$i');
                                                          }
                                                        });
                                                        print(
                                                            'object ==> ${selectedVariants.toString()}');
                                                        print(
                                                            'object ==> ${selectedIndexVariants.toString()}');
                                                        print(
                                                            'object ==> ${selectedIndexArray.toString()}');

                                                        await cartDatabase
                                                            .allCartProducts
                                                            .then((value) {
                                                          final bool _productIsInList = value.any((product) =>
                                                              product.id ==
                                                              widget.productModel
                                                                      .id +
                                                                  "~" +
                                                                  (variants!
                                                                          .where((element) =>
                                                                              element.variant_sku ==
                                                                              selectedVariants.join(
                                                                                  '-'))
                                                                          .isNotEmpty
                                                                      ? variants!
                                                                          .where((element) =>
                                                                              element.variant_sku ==
                                                                              selectedVariants.join('-'))
                                                                          .first
                                                                          .variant_id
                                                                          .toString()
                                                                      : ""));
                                                          if (_productIsInList) {
                                                            CartProduct element = value.firstWhere((product) =>
                                                                product.id ==
                                                                widget.productModel
                                                                        .id +
                                                                    "~" +
                                                                    (variants!
                                                                            .where((element) =>
                                                                                element.variant_sku ==
                                                                                selectedVariants.join(
                                                                                    '-'))
                                                                            .isNotEmpty
                                                                        ? variants!
                                                                            .where((element) =>
                                                                                element.variant_sku ==
                                                                                selectedVariants.join('-'))
                                                                            .first
                                                                            .variant_id
                                                                            .toString()
                                                                        : ""));

                                                            setState(() {
                                                              productQnt =
                                                                  element
                                                                      .quantity;
                                                            });
                                                          } else {
                                                            setState(() {
                                                              productQnt = 0;
                                                            });
                                                          }
                                                        });

                                                        if (variants!
                                                            .where((element) =>
                                                                element
                                                                    .variant_sku ==
                                                                selectedVariants
                                                                    .join('-'))
                                                            .isNotEmpty) {
                                                          widget.productModel
                                                              .price = variants!
                                                                  .where((element) =>
                                                                      element
                                                                          .variant_sku ==
                                                                      selectedVariants
                                                                          .join(
                                                                              '-'))
                                                                  .first
                                                                  .variant_price ??
                                                              '0';
                                                          widget.productModel
                                                              .disPrice = '0';
                                                        }
                                                      },
                                                      child: _buildChip(
                                                          attributes![index]
                                                              .attributeOptions![
                                                                  i]
                                                              .toString(),
                                                          i,
                                                          selectedVariants.contains(
                                                                  attributes![
                                                                          index]
                                                                      .attributeOptions![
                                                                          i]
                                                                      .toString())
                                                              ? true
                                                              : false));
                                                },
                                              ).toList(),
                                            ),
                                          )
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                  lstAddAddonsCustom.isEmpty
                      ? Container()
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(
                                height: 16,
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Add Ons".tr(),
                                    textAlign: TextAlign.start,
                                    style: TextStyle(
                                      fontFamily: AppThemeData.bold,
                                      fontSize: 18,
                                      color: isDarkMode(context)
                                          ? AppThemeData.grey50
                                          : AppThemeData.grey900,
                                    ),
                                  ),
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppThemeData.primary500.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      "${lstAddAddonsCustom.length} ${lstAddAddonsCustom.length > 1 ? 'items' : 'item'}",
                                      style: TextStyle(
                                        fontFamily: AppThemeData.medium,
                                        fontSize: 12,
                                        color: AppThemeData.primary500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(
                                height: 16,
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  color: isDarkMode(context)
                                      ? AppThemeData.grey900
                                      : AppThemeData.grey100,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0x0A000000),
                                      blurRadius: 16,
                                      offset: Offset(0, 4),
                                      spreadRadius: 0,
                                    )
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10, horizontal: 10),
                                  child: ListView.builder(
                                      itemCount: lstAddAddonsCustom.length,
                                      physics: const NeverScrollableScrollPhysics(),
                                      shrinkWrap: true,
                                      padding: EdgeInsets.zero,
                                      itemBuilder: (context, index) {
                                        return Column(
                                          children: [
                                            Container(
                                              margin: const EdgeInsets.only(top: 5),
                                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                                              decoration: BoxDecoration(
                                                color: isDarkMode(context)
                                                    ? AppThemeData.grey800
                                                    : Colors.white,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: lstAddAddonsCustom[index].isCheck
                                                      ? AppThemeData.primary500.withOpacity(0.3)
                                                      : const Color(0xFFE8E4FF),
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  // Left side: Attractive food icon
                                                  Container(
                                                    width: 48,
                                                    height: 48,
                                                    decoration: BoxDecoration(
                                                      color: AppThemeData.primary500.withOpacity(0.1),
                                                      borderRadius: BorderRadius.circular(10),
                                                    ),
                                                    child: Icon(
                                                      _getAddonIcon(lstAddAddonsCustom[index].name!),
                                                      color: AppThemeData.primary500,
                                                      size: 24,
                                                    ),
                                                  ),
                                                  SizedBox(width: 14),
                                                  // Add-on name and price
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          lstAddAddonsCustom[index].name!,
                                                          style: TextStyle(
                                                            fontSize: 16,
                                                            fontFamily: AppThemeData.medium,
                                                            color: isDarkMode(context)
                                                                ? AppThemeData.grey100
                                                                : AppThemeData.grey900,
                                                          ),
                                                        ),
                                                        SizedBox(height: 4),
                                                        Text(
                                                          amountShow(
                                                              amount: productCommissionPrice(
                                                                  lstAddAddonsCustom[index].price!)),
                                                          style: TextStyle(
                                                            fontFamily: AppThemeData.regular,
                                                            fontSize: 14,
                                                            color: AppThemeData.primary500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  SizedBox(width: 12),
                                                  // Right side: + / - button
                                                  GestureDetector(
                                                    onTap: () {
                                                      // Check if main product is in cart before allowing add-on selection
                                                      if (productQnt == 0 && !lstAddAddonsCustom[index].isCheck) {
                                                        // Show alert that main item must be added first
                                                        AppDialog.showInfo(
                                                          context,
                                                          title: 'Add Main Item First',
                                                          message: 'Please add the main item to your cart before selecting add-ons.',
                                                        );
                                                        return; // Exit early, don't toggle add-on
                                                      }
                                                      
                                                      setState(() {
                                                        lstAddAddonsCustom[index].isCheck =
                                                            !lstAddAddonsCustom[index].isCheck;
                                                        if (variants!
                                                            .where((element) =>
                                                                element.variant_sku ==
                                                                selectedVariants.join('-'))
                                                            .isNotEmpty) {
                                                          VariantInfo? variantInfo = VariantInfo();
                                                          Map<String, String> mapData = Map();
                                                          for (var element in attributes!) {
                                                            mapData.addEntries([
                                                              MapEntry(
                                                                  attributesList
                                                                      .where((element1) =>
                                                                          element.attributesId ==
                                                                          element1.id)
                                                                      .first
                                                                      .title
                                                                      .toString(),
                                                                  selectedVariants[attributes!
                                                                      .indexOf(element)])
                                                            ]);
                                                            setState(() {});
                                                          }

                                                          variantInfo = VariantInfo(
                                                              variant_price: variants!
                                                                      .where((element) =>
                                                                          element.variant_sku ==
                                                                          selectedVariants.join('-'))
                                                                      .first
                                                                      .variant_price ??
                                                                  '0',
                                                              variant_sku: selectedVariants.join('-'),
                                                              variant_options: mapData,
                                                              variant_image: variants!
                                                                      .where((element) =>
                                                                          element.variant_sku ==
                                                                          selectedVariants.join('-'))
                                                                      .first
                                                                      .variant_image ??
                                                                  '',
                                                              variant_id: variants!
                                                                      .where((element) =>
                                                                          element.variant_sku ==
                                                                          selectedVariants.join('-'))
                                                                      .first
                                                                      .variant_id ??
                                                                  '0');

                                                          widget.productModel.variant_info =
                                                              variantInfo;
                                                        }

                                                        if (lstAddAddonsCustom[index].isCheck ==
                                                            true) {
                                                          AddAddonsDemo addAddonsDemo = AddAddonsDemo(
                                                              name: widget.productModel
                                                                  .addOnsTitle[index],
                                                              index: index,
                                                              isCheck: true,
                                                              categoryID: widget.productModel.id,
                                                              price: productCommissionPrice(
                                                                  lstAddAddonsCustom[index]
                                                                      .price!));
                                                          lstTemp.add(addAddonsDemo);
                                                          saveAddOns(lstTemp);
                                                          addtocard(widget.productModel, false);
                                                        } else {
                                                          var removeIndex = -1;
                                                          for (int a = 0; a < lstTemp.length; a++) {
                                                            if (lstTemp[a].index == index &&
                                                                lstTemp[a].categoryID ==
                                                                    lstAddAddonsCustom[index]
                                                                        .categoryID) {
                                                              removeIndex = a;
                                                              break;
                                                            }
                                                          }
                                                          lstTemp.removeAt(removeIndex);
                                                          saveAddOns(lstTemp);
                                                          addtocard(widget.productModel, false);
                                                        }
                                                      });
                                                    },
                                                    child: Container(
                                                      width: 44,
                                                      height: 44,
                                                      decoration: BoxDecoration(
                                                        color: lstAddAddonsCustom[index].isCheck
                                                            ? AppThemeData.primary500
                                                            : AppThemeData.primary500.withOpacity(0.1),
                                                        borderRadius: BorderRadius.circular(12),
                                                      ),
                                                      child: Icon(
                                                        lstAddAddonsCustom[index].isCheck
                                                            ? Icons.remove
                                                            : Icons.add,
                                                        color: lstAddAddonsCustom[index].isCheck
                                                            ? Colors.white
                                                            : AppThemeData.primary500,
                                                        size: 24,
                                                      ),
                                                    ),
                                                  )
                                                ],
                                              ),
                                            ),
                                            // Add divider between items, but not after the last item
                                            if (index < lstAddAddonsCustom.length - 1)
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                                child: Divider(
                                                  color: isDarkMode(context) 
                                                      ? AppThemeData.grey800.withOpacity(0.5) 
                                                      : AppThemeData.grey200,
                                                  thickness: 0.5,
                                                  height: 1,
                                                ),
                                              ),
                                          ],
                                        );
                                      }),
                                ),
                              )
                            ],
                          ),
                        ),
                  Visibility(
                    visible: widget.productModel.specification.isNotEmpty,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Specifications".tr(),
                                textAlign: TextAlign.start,
                                style: TextStyle(
                                  fontFamily: AppThemeData.bold,
                                  fontSize: 18,
                                  color: isDarkMode(context)
                                      ? AppThemeData.grey50
                                      : AppThemeData.grey900,
                                ),
                              ),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppThemeData.primary500.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  "${widget.productModel.specification.length} items",
                                  style: TextStyle(
                                    fontFamily: AppThemeData.medium,
                                    fontSize: 12,
                                    color: AppThemeData.primary500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            decoration: BoxDecoration(
                              color: isDarkMode(context)
                                  ? AppThemeData.grey900
                                  : AppThemeData.grey100,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x0A000000),
                                  blurRadius: 16,
                                  offset: Offset(0, 4),
                                  spreadRadius: 0,
                                )
                              ],
                            ),
                            child: widget.productModel.specification.isNotEmpty
                                ? ListView.builder(
                                    itemCount: widget.productModel.specification.length,
                                    shrinkWrap: true,
                                    padding: EdgeInsets.zero,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemBuilder: (context, index) {
                                      final key = widget.productModel.specification.keys.elementAt(index);
                                      final value = widget.productModel.specification.values.elementAt(index);
                                      
                                      return Container(
                                        decoration: BoxDecoration(
                                          border: index < widget.productModel.specification.length - 1 
                                              ? Border(
                                                  bottom: BorderSide(
                                                    color: isDarkMode(context) 
                                                        ? AppThemeData.grey800.withOpacity(0.5) 
                                                        : AppThemeData.grey200,
                                                    width: 0.5,
                                                  ),
                                                )
                                              : null,
                                        ),
                                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 24,
                                              height: 24,
                                              decoration: BoxDecoration(
                                                color: AppThemeData.primary500.withOpacity(0.1),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Center(
                                                child: Icon(
                                                  Icons.info_outline,
                                                  size: 14,
                                                  color: AppThemeData.primary500,
                                                ),
                                              ),
                                            ),
                                            SizedBox(width: 12),
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                key,
                                                style: TextStyle(
                                                  fontFamily: AppThemeData.medium,
                                                  fontSize: 14,
                                                  color: isDarkMode(context)
                                                      ? AppThemeData.grey300
                                                      : AppThemeData.grey700,
                                                ),
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            Expanded(
                                              flex: 3,
                                              child: Text(
                                                value,
                                                style: TextStyle(
                                                  fontFamily: AppThemeData.regular,
                                                  fontSize: 14,
                                                  color: isDarkMode(context)
                                                      ? AppThemeData.grey100
                                                      : AppThemeData.grey900,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  )
                                : Container(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Visibility(
                      visible: storeProductList.isNotEmpty,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(
                              height: 10,
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      "More From the store".tr(),
                                      textAlign: TextAlign.start,
                                      style: TextStyle(
                                        fontFamily: AppThemeData.bold,
                                        fontSize: 16,
                                        color: isDarkMode(context)
                                            ? AppThemeData.grey50
                                            : AppThemeData.grey900,
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () {
                                      Navigator.pop(context);
                                    },
                                    child: Text(
                                      "See All".tr(),
                                      style: TextStyle(
                                          fontSize: 16,
                                          color: isDarkMode(context)
                                              ? const Color(0xffffffff)
                                              : AppThemeData.primary500),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(
                              height: 10,
                            ),
                            SizedBox(
                                width: MediaQuery.of(context).size.width,
                                height:
                                    MediaQuery.of(context).size.height * 0.24,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                  child: ListView.builder(
                                    shrinkWrap: true,
                                    scrollDirection: Axis.horizontal,
                                    physics: const BouncingScrollPhysics(),
                                    itemCount: storeProductList.length > 6
                                        ? 6
                                        : storeProductList.length,
                                    itemBuilder: (context, index) {
                                      ProductModel productModel =
                                          storeProductList[index];
                                      String price = "0.0";
                                      String disPrice = "0.0";
                                      List<String> selectedVariants = [];
                                      List<String> selectedIndexVariants = [];
                                      List<String> selectedIndexArray = [];
                                      if (productModel.itemAttributes != null) {
                                        if (productModel.itemAttributes!
                                            .attributes!.isNotEmpty) {
                                          for (var element in productModel
                                              .itemAttributes!.attributes!) {
                                            if (element
                                                .attributeOptions!.isNotEmpty) {
                                              selectedVariants.add(productModel
                                                  .itemAttributes!
                                                  .attributes![productModel
                                                      .itemAttributes!
                                                      .attributes!
                                                      .indexOf(element)]
                                                  .attributeOptions![0]
                                                  .toString());
                                              selectedIndexVariants.add(
                                                  '${productModel.itemAttributes!.attributes!.indexOf(element)} _${productModel.itemAttributes!.attributes![0].attributeOptions![0].toString()}');
                                              selectedIndexArray.add(
                                                  '${productModel.itemAttributes!.attributes!.indexOf(element)}_0');
                                            }
                                          }
                                        }
                                        if (productModel
                                            .itemAttributes!.variants!
                                            .where((element) =>
                                                element.variant_sku ==
                                                selectedVariants.join('-'))
                                            .isNotEmpty) {
                                          price = productCommissionPrice(
                                              productModel
                                                      .itemAttributes!.variants!
                                                      .where((element) =>
                                                          element.variant_sku ==
                                                          selectedVariants
                                                              .join('-'))
                                                      .first
                                                      .variant_price ??
                                                  '0');
                                          disPrice =
                                              productCommissionPrice('0');
                                        }
                                      } else {
                                        price = productCommissionPrice(
                                            productModel.price);
                                        disPrice = productCommissionPrice(
                                            productModel.disPrice.toString());
                                      }
                                      return Container(
                                        margin:
                                            const EdgeInsets.only(right: 10),
                                        child: GestureDetector(
                                          onTap: () async {
                                            VendorModel? vendorModel =
                                                await FireStoreUtils.getVendor(
                                                    storeProductList[index]
                                                        .vendorID);
                                            if (vendorModel != null) {
                                              push(
                                                context,
                                                ProductDetailsScreen(
                                                  vendorModel: vendorModel,
                                                  productModel: productModel,
                                                ),
                                              );
                                            }
                                          },
                                          child: SizedBox(
                                            width: MediaQuery.of(context)
                                                    .size
                                                    .width *
                                                0.38,
                                            child: Container(
                                              decoration: ShapeDecoration(
                                                color: isDarkMode(context)
                                                    ? AppThemeData.grey900
                                                    : AppThemeData.grey100,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                                shadows: [
                                                  BoxShadow(
                                                    color: Color(0x05000000),
                                                    blurRadius: 32,
                                                    offset: Offset(0, 0),
                                                    spreadRadius: 0,
                                                  )
                                                ],
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(8.0),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Expanded(
                                                        child:
                                                            CachedNetworkImage(
                                                      imageUrl:
                                                          getImageVAlidUrl(
                                                              productModel
                                                                  .photo),
                                                      imageBuilder: (context,
                                                              imageProvider) =>
                                                          Container(
                                                        decoration:
                                                            BoxDecoration(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(20),
                                                          image: DecorationImage(
                                                              image:
                                                                  imageProvider,
                                                              fit: BoxFit
                                                                  .contain),
                                                        ),
                                                      ),
                                                      placeholder: (context,
                                                              url) =>
                                                          Center(
                                                              child:
                                                                  CircularProgressIndicator
                                                                      .adaptive(
                                                        valueColor:
                                                            AlwaysStoppedAnimation(
                                                                AppThemeData
                                                                    .primary500),
                                                      )),
                                                      errorWidget: (context,
                                                              url, error) =>
                                                          ClipRRect(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(20),
                                                        child: Image.network(
                                                          placeholderImage,
                                                          fit: BoxFit.cover,
                                                        ),
                                                      ),
                                                      fit: BoxFit.contain,
                                                    )),
                                                    const SizedBox(height: 8),
                                                    Text(productModel.name,
                                                        maxLines: 1,
                                                        style: const TextStyle(
                                                          letterSpacing: 0.5,
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        )).tr(),
                                                    const SizedBox(
                                                      height: 5,
                                                    ),
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      children: [
                                                        disPrice == "" ||
                                                                disPrice ==
                                                                    productCommissionPrice(
                                                                        '0')
                                                            ? Text(
                                                                "${amountShow(amount: price)}",
                                                                style: TextStyle(
                                                                    letterSpacing:
                                                                        0.5,
                                                                    color: AppThemeData
                                                                        .primary500),
                                                              )
                                                            : Column(
                                                                children: [
                                                                  Text(
                                                                    "${amountShow(amount: disPrice)}",
                                                                    style:
                                                                        TextStyle(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                      fontSize:
                                                                          14,
                                                                      color: AppThemeData
                                                                          .primary500,
                                                                    ),
                                                                  ),
                                                                  Text(
                                                                    '${amountShow(amount: price)}',
                                                                    style: const TextStyle(
                                                                        fontWeight:
                                                                            FontWeight
                                                                                .bold,
                                                                        fontSize:
                                                                            12,
                                                                        color: Colors
                                                                            .grey,
                                                                        decoration:
                                                                            TextDecoration.lineThrough),
                                                                  ),
                                                                ],
                                                              ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ))
                          ],
                        ),
                      )),
                  Visibility(
                      visible: productList.isNotEmpty,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(
                              height: 10,
                            ),
                            Text(
                              "Related Products".tr(),
                              textAlign: TextAlign.start,
                              style: TextStyle(
                                fontFamily: AppThemeData.bold,
                                fontSize: 16,
                                color: isDarkMode(context)
                                    ? AppThemeData.grey50
                                    : AppThemeData.grey900,
                              ),
                            ),
                            const SizedBox(
                              height: 10,
                            ),
                            SizedBox(
                                width: MediaQuery.of(context).size.width,
                                height:
                                    MediaQuery.of(context).size.height * 0.24,
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: productList.length > 6
                                      ? 6
                                      : productList.length,
                                  itemBuilder: (context, index) {
                                    ProductModel productModel =
                                        productList[index];
                                    String price = "0.0";
                                    String disPrice = "0.0";
                                    List<String> selectedVariants = [];
                                    List<String> selectedIndexVariants = [];
                                    List<String> selectedIndexArray = [];
                                    if (productModel.itemAttributes != null) {
                                      if (productModel.itemAttributes!
                                          .attributes!.isNotEmpty) {
                                        for (var element in productModel
                                            .itemAttributes!.attributes!) {
                                          if (element
                                              .attributeOptions!.isNotEmpty) {
                                            selectedVariants.add(productModel
                                                .itemAttributes!
                                                .attributes![productModel
                                                    .itemAttributes!.attributes!
                                                    .indexOf(element)]
                                                .attributeOptions![0]
                                                .toString());
                                            selectedIndexVariants.add(
                                                '${productModel.itemAttributes!.attributes!.indexOf(element)} _${productModel.itemAttributes!.attributes![0].attributeOptions![0].toString()}');
                                            selectedIndexArray.add(
                                                '${productModel.itemAttributes!.attributes!.indexOf(element)}_0');
                                          }
                                        }
                                      }
                                      if (productModel.itemAttributes!.variants!
                                          .where((element) =>
                                              element.variant_sku ==
                                              selectedVariants.join('-'))
                                          .isNotEmpty) {
                                        price = productCommissionPrice(
                                            productModel
                                                    .itemAttributes!.variants!
                                                    .where((element) =>
                                                        element.variant_sku ==
                                                        selectedVariants
                                                            .join('-'))
                                                    .first
                                                    .variant_price ??
                                                '0');
                                        disPrice = productCommissionPrice('0');
                                      }
                                    } else {
                                      price = productCommissionPrice(
                                          productModel.price);
                                      disPrice = productCommissionPrice(
                                          productModel.disPrice.toString());
                                    }
                                    return Container(
                                      margin: const EdgeInsets.only(right: 10),
                                      child: GestureDetector(
                                        onTap: () async {
                                          VendorModel? vendorModel =
                                              await FireStoreUtils.getVendor(
                                                  productModel.vendorID);
                                          if (vendorModel != null) {
                                            push(
                                              context,
                                              ProductDetailsScreen(
                                                vendorModel: vendorModel,
                                                productModel: productModel,
                                              ),
                                            );
                                          }
                                        },
                                        child: SizedBox(
                                          width: MediaQuery.of(context)
                                                  .size
                                                  .width *
                                              0.38,
                                          child: Container(
                                            decoration: ShapeDecoration(
                                              color: isDarkMode(context)
                                                  ? AppThemeData.grey900
                                                  : AppThemeData.grey100,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              shadows: [
                                                BoxShadow(
                                                  color: Color(0x05000000),
                                                  blurRadius: 32,
                                                  offset: Offset(0, 0),
                                                  spreadRadius: 0,
                                                )
                                              ],
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.all(8.0),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(
                                                      child: CachedNetworkImage(
                                                    imageUrl: getImageVAlidUrl(
                                                        productModel.photo),
                                                    imageBuilder: (context,
                                                            imageProvider) =>
                                                        Container(
                                                      decoration: BoxDecoration(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(20),
                                                        image: DecorationImage(
                                                            image:
                                                                imageProvider,
                                                            fit: BoxFit.cover),
                                                      ),
                                                    ),
                                                    placeholder: (context,
                                                            url) =>
                                                        Center(
                                                            child:
                                                                CircularProgressIndicator
                                                                    .adaptive(
                                                      valueColor:
                                                          AlwaysStoppedAnimation(
                                                              AppThemeData
                                                                  .primary500),
                                                    )),
                                                    errorWidget:
                                                        (context, url, error) =>
                                                            ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              20),
                                                      child: Image.network(
                                                        placeholderImage,
                                                        fit: BoxFit.cover,
                                                      ),
                                                    ),
                                                    fit: BoxFit.cover,
                                                  )),
                                                  const SizedBox(height: 8),
                                                  Text(productModel.name,
                                                      maxLines: 1,
                                                      style: const TextStyle(
                                                        letterSpacing: 0.5,
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      )).tr(),
                                                  const SizedBox(
                                                    height: 5,
                                                  ),
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      disPrice == "" ||
                                                              disPrice == "0" ||
                                                              disPrice ==
                                                                  productCommissionPrice(
                                                                      '0')
                                                          ? Text(
                                                              "${amountShow(amount: price)}",
                                                              style: TextStyle(
                                                                  letterSpacing:
                                                                      0.5,
                                                                  color: AppThemeData
                                                                      .primary500),
                                                            )
                                                          : Column(
                                                              children: [
                                                                Text(
                                                                  "${amountShow(amount: disPrice)}",
                                                                  style:
                                                                      TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    fontSize:
                                                                        14,
                                                                    color: AppThemeData
                                                                        .primary500,
                                                                  ),
                                                                ),
                                                                Text(
                                                                  amountShow(
                                                                      amount:
                                                                          price),
                                                                  style: const TextStyle(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                      fontSize:
                                                                          12,
                                                                      color: Colors
                                                                          .grey,
                                                                      decoration:
                                                                          TextDecoration
                                                                              .lineThrough),
                                                                ),
                                                              ],
                                                            ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ))
                          ],
                        ),
                      )),
                  Visibility(
                    visible: widget.productModel.reviewAttributes!.isNotEmpty,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(
                            height: 10,
                          ),
                          Text(
                            "By Feature".tr(),
                            textAlign: TextAlign.start,
                            style: TextStyle(
                              fontFamily: AppThemeData.bold,
                              fontSize: 16,
                              color: isDarkMode(context)
                                  ? AppThemeData.grey50
                                  : AppThemeData.grey900,
                            ),
                          ),
                          const SizedBox(
                            height: 5,
                          ),
                          widget.productModel.reviewAttributes != null
                              ? Container(
                                  decoration: ShapeDecoration(
                                    color: isDarkMode(context)
                                        ? AppThemeData.grey900
                                        : AppThemeData.grey100,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    shadows: [
                                      BoxShadow(
                                        color: Color(0x05000000),
                                        blurRadius: 32,
                                        offset: Offset(0, 0),
                                        spreadRadius: 0,
                                      )
                                    ],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: ListView.builder(
                                      itemCount: widget.productModel
                                          .reviewAttributes!.length,
                                      shrinkWrap: true,
                                      padding: EdgeInsets.zero,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemBuilder: (context, index) {
                                        ReviewAttributeModel reviewAttribute =
                                            ReviewAttributeModel();
                                        for (var element
                                            in reviewAttributeList) {
                                          if (element.id ==
                                              widget.productModel
                                                  .reviewAttributes!.keys
                                                  .elementAt(index)) {
                                            reviewAttribute = element;
                                          }
                                        }
                                        ReviewsAttribute reviewsAttributeModel =
                                            ReviewsAttribute.fromJson(widget
                                                .productModel
                                                .reviewAttributes!
                                                .values
                                                .elementAt(index));
                                        return Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Expanded(
                                                  child: Text(
                                                      reviewAttribute.title
                                                          .toString(),
                                                      style: TextStyle(
                                                          color: isDarkMode(
                                                                  context)
                                                              ? Colors.white
                                                              : Colors.black
                                                                  .withOpacity(
                                                                      0.60),
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          letterSpacing: 0.5,
                                                          fontSize: 14))),
                                              RatingBar.builder(
                                                ignoreGestures: true,
                                                initialRating:
                                                    (reviewsAttributeModel
                                                            .reviewsSum!
                                                            .toDouble() /
                                                        reviewsAttributeModel
                                                            .reviewsCount!
                                                            .toDouble()),
                                                minRating: 1,
                                                itemSize: 20,
                                                direction: Axis.horizontal,
                                                allowHalfRating: true,
                                                itemCount: 5,
                                                itemBuilder: (context, _) =>
                                                    Icon(
                                                  Icons.star,
                                                  color:
                                                      AppThemeData.primary500,
                                                ),
                                                onRatingUpdate: (double rate) {
                                                  // ratings = rate;
                                                  // print(ratings);
                                                },
                                              ),
                                              const SizedBox(
                                                width: 8,
                                              ),
                                              Text(
                                                (reviewsAttributeModel
                                                            .reviewsSum!
                                                            .toDouble() /
                                                        reviewsAttributeModel
                                                            .reviewsCount!
                                                            .toDouble())
                                                    .toStringAsFixed(1),
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                    color: isDarkMode(context)
                                                        ? Colors.white
                                                        : Colors.black,
                                                    fontWeight:
                                                        FontWeight.w400),
                                              )
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                )
                              : Container(),
                        ],
                      ),
                    ),
                  ),
                  Visibility(
                    visible: reviewList.isNotEmpty,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(
                          height: 10,
                        ),
                        Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: ListView.builder(
                            itemCount:
                                reviewList.length > 10 ? 10 : reviewList.length,
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            physics: const NeverScrollableScrollPhysics(),
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Container(
                                  decoration: ShapeDecoration(
                                    color: isDarkMode(context)
                                        ? AppThemeData.grey900
                                        : AppThemeData.grey100,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    shadows: [
                                      BoxShadow(
                                        color: Color(0x05000000),
                                        blurRadius: 32,
                                        offset: Offset(0, 0),
                                        spreadRadius: 0,
                                      )
                                    ],
                                  ), // Change this
                                  child: Padding(
                                    padding: const EdgeInsets.all(10.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            CachedNetworkImage(
                                              height: 45,
                                              width: 45,
                                              imageUrl: getImageVAlidUrl(
                                                  reviewList[index]
                                                      .profile
                                                      .toString()),
                                              imageBuilder:
                                                  (context, imageProvider) =>
                                                      Container(
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(35),
                                                  image: DecorationImage(
                                                      image: imageProvider,
                                                      fit: BoxFit.cover),
                                                ),
                                              ),
                                              placeholder: (context, url) =>
                                                  Center(
                                                      child:
                                                          CircularProgressIndicator
                                                              .adaptive(
                                                valueColor:
                                                    AlwaysStoppedAnimation(
                                                        AppThemeData
                                                            .primary500),
                                              )),
                                              errorWidget: (context, url,
                                                      error) =>
                                                  ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              35),
                                                      child: Image.network(
                                                        placeholderImage,
                                                        fit: BoxFit.cover,
                                                      )),
                                              fit: BoxFit.cover,
                                            ),
                                            const SizedBox(
                                              width: 10,
                                            ),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    reviewList[index]
                                                        .uname
                                                        .toString(),
                                                    style: const TextStyle(
                                                        color: Colors.black,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        letterSpacing: 1,
                                                        fontSize: 16),
                                                  ),
                                                  RatingBar.builder(
                                                    ignoreGestures: true,
                                                    initialRating:
                                                        reviewList[index]
                                                                .rating ??
                                                            0.0,
                                                    minRating: 1,
                                                    itemSize: 22,
                                                    direction: Axis.horizontal,
                                                    allowHalfRating: true,
                                                    itemCount: 5,
                                                    itemPadding:
                                                        const EdgeInsets.only(
                                                            top: 5.0),
                                                    itemBuilder: (context, _) =>
                                                        Icon(
                                                      Icons.star,
                                                      color: AppThemeData
                                                          .primary500,
                                                    ),
                                                    onRatingUpdate:
                                                        (double rate) {
                                                      // ratings = rate;
                                                      // print(ratings);
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Text(
                                                orderDate(reviewList[index]
                                                    .createdAt),
                                                style: TextStyle(
                                                    color: isDarkMode(context)
                                                        ? Colors.grey.shade200
                                                        : const Color(
                                                            0XFF555353))),
                                          ],
                                        ),
                                        // const Padding(
                                        //   padding: EdgeInsets.symmetric(vertical: 8),
                                        //   child: Divider(
                                        //     thickness: 2,
                                        //   ),
                                        // ),
                                        Text(
                                            reviewList[index]
                                                .comment
                                                .toString(),
                                            style: TextStyle(
                                                color: Colors.black
                                                    .withOpacity(0.70),
                                                fontWeight: FontWeight.w400,
                                                letterSpacing: 1,
                                                fontSize: 14)),
                                        const SizedBox(
                                          height: 10,
                                        ),
                                        reviewList[index].photos!.isNotEmpty
                                            ? SizedBox(
                                                height: 75,
                                                child: ListView.builder(
                                                  itemCount: reviewList[index]
                                                      .photos!
                                                      .length,
                                                  shrinkWrap: true,
                                                  scrollDirection:
                                                      Axis.horizontal,
                                                  itemBuilder:
                                                      (context, index1) {
                                                    return Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              6.0),
                                                      child: CachedNetworkImage(
                                                        height: 65,
                                                        width: 65,
                                                        imageUrl:
                                                            getImageVAlidUrl(
                                                                reviewList[index]
                                                                        .photos![
                                                                    index1]),
                                                        imageBuilder: (context,
                                                                imageProvider) =>
                                                            Container(
                                                          decoration:
                                                              BoxDecoration(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        10),
                                                            image: DecorationImage(
                                                                image:
                                                                    imageProvider,
                                                                fit: BoxFit
                                                                    .cover),
                                                          ),
                                                        ),
                                                        placeholder: (context,
                                                                url) =>
                                                            Center(
                                                                child:
                                                                    CircularProgressIndicator
                                                                        .adaptive(
                                                          valueColor:
                                                              AlwaysStoppedAnimation(
                                                                  AppThemeData
                                                                      .primary500),
                                                        )),
                                                        errorWidget: (context,
                                                                url, error) =>
                                                            ClipRRect(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            10),
                                                                child: Image
                                                                    .network(
                                                                  placeholderImage,
                                                                  fit: BoxFit
                                                                      .cover,
                                                                )),
                                                        fit: BoxFit.cover,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              )
                                            : Container()
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        RoundedButtonFill(
                          title: "See All Reviews".tr(),
                          color: AppThemeData.primary500,
                          textColor: AppThemeData.grey50,
                          onPress: () async {
                            push(
                              context,
                              Review(
                                productModel: widget.productModel,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ]),
      ),
      bottomNavigationBar: sectionConstantModel!.serviceTypeFlag ==
              "ecommerce-service"
          ? Container(
              color: AppThemeData.primary500,
              // bottom: 20 was a fixed offset that didn't account for the
              // system nav-bar/gesture inset (edge-to-edge on API 35).
              padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  bottom: 20 + MediaQuery.of(context).padding.bottom,
                  top: 20),

              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "Item Total".tr() +
                          " " +
                          amountShow(amount: priceTemp.toString()),
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ).tr(),
                  ),
                  GestureDetector(
                    onTap: () {
                      if (MyAppState.currentUser == null) {
                        push(context, const LoginScreen());
                      } else {
                        pushAndRemoveUntil(
                            context,
                            ContainerScreen(
                              user: MyAppState.currentUser!,
                              drawerSelection: DrawerSelection.Cart,
                              currentWidget: const CartScreen(),
                              appBarTitle: 'Your Cart',
                            ));
                      }
                    },
                    child: Text(
                      "VIEW CART".tr(),
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ).tr(),
                  )
                ],
              ),
            )
          : isOpen && showAddButton
              ? 
              Container(
                decoration: BoxDecoration(
                  color: AppThemeData.primary500,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(30, 10, 30, 10 + MediaQuery.of(context).padding.bottom),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Item Total".tr(),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 14,
                              fontFamily: AppThemeData.medium,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            amountShow(amount: priceTemp.toString()),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: AppThemeData.bold,
                            ),
                          ),
                        ],
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
                              push(context, const LoginScreen());
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
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
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
  addtocard(ProductModel productModel, bool isIncerementQuantity) async {
    // ── Service compatibility gate — hard-block before any cart work ──────────
    if (productModel.deliveryOption || productModel.takeaway || productModel.dineIn) {
      final orderType = selectedOrderType ?? 'Delivery';
      final isDineawayMode = orderType == 'Takeaway' || orderType == 'Dineaway';
      if (!isDineawayMode && !productModel.deliveryOption) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delivery order is not available.'.tr())));
        return;
      }
      if (isDineawayMode && !productModel.dineIn && !productModel.takeaway) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('DineAway order is not available.'.tr())));
        return;
      }
    }

    // Using isAddOnApplied properly to track if any add-ons are applied
    double AddOnVal = 0;
    bool isAddOnApplied = false;
    for (int i = 0; i < lstTemp.length; i++) {
      AddAddonsDemo addAddonsDemo = lstTemp[i];
      if (addAddonsDemo.categoryID == widget.productModel.id) {
        isAddOnApplied = true;
        AddOnVal = AddOnVal +
            double.parse(productCommissionPrice(addAddonsDemo.price!));
      }
    }
    List<CartProduct> cartProducts = await cartDatabase.allCartProducts;
    
    // Check if cart contains products from a different vendor
    if (cartProducts.isNotEmpty) {
      String cartVendorID = cartProducts[0].vendorID;
      if (cartVendorID != widget.vendorModel.id) {
        // Show a dialog to confirm if user wants to clear cart and add new product
        final confirmed = await AppDialog.showConfirm(
          context,
          title: 'Replace Cart Items?',
          message: 'Your cart contains items from a different store. Would you like to clear your cart and add this item?',
          confirmLabel: 'Clear & Add',
          cancelLabel: 'Cancel',
          destructive: true,
        );

        // If user cancels, return without adding to cart
        if (!confirmed) {
          setState(() {
            productQnt = 0; // Reset quantity as we're not adding to cart
          });
          return;
        }
        
        // User confirmed, so clear cart before adding new product
        await cartDatabase.deleteAllProducts();
      }
    }
    
    // Continue with adding to cart logic
    if (productQnt > 1) {
      var joinTitleString = "";
      String mainPrice = "";
      List<AddAddonsDemo> lstAddOns = [];
      List<String> lstAddOnsTemp = [];
      double extras_price = 0.0;

      SharedPreferences sp = await SharedPreferences.getInstance();
      String addOns =
          sp.getString("musics_key") != null ? sp.getString('musics_key')! : "";

      bool isAddSame = false;
      if (!isAddSame) {
        if (productModel.disPrice != null &&
            productModel.disPrice!.isNotEmpty &&
            double.parse(productModel.disPrice!) != 0) {
          mainPrice = productModel.disPrice!;
        } else {
          mainPrice = productModel.price;
        }
      }

      if (addOns.isNotEmpty) {
        lstAddOns = AddAddonsDemo.decode(addOns);
        for (int a = 0; a < lstAddOns.length; a++) {
          AddAddonsDemo newAddonsObject = lstAddOns[a];
          if (newAddonsObject.categoryID == widget.productModel.id) {
            if (newAddonsObject.isCheck == true) {
              lstAddOnsTemp.add(newAddonsObject.name!);
              extras_price += (double.parse(newAddonsObject.price!));
            }
          }
        }

        joinTitleString = lstAddOnsTemp.join(",");
      }

      final bool _productIsInList = cartProducts.any((product) =>
          product.id ==
          productModel.id +
              "~" +
              (productModel.variant_info != null
                  ? productModel.variant_info!.variant_id.toString()
                  : ""));
      if (_productIsInList) {
        CartProduct element = cartProducts.firstWhere((product) =>
            product.id ==
            productModel.id +
                "~" +
                (productModel.variant_info != null
                    ? productModel.variant_info!.variant_id.toString()
                    : ""));

        await cartDatabase.updateProduct(CartProduct(
            id: element.id,
            name: element.name,
            photo: element.photo,
            price: element.price,
            vendorID: element.vendorID,
            quantity:
                isIncerementQuantity ? element.quantity + 1 : element.quantity,
            category_id: element.category_id,
            extras_price: extras_price.toString(),
            extras: joinTitleString,
            discountPrice: element.discountPrice!));
      } else {
        await cartDatabase.updateProduct(CartProduct(
            id: productModel.id +
                "~" +
                (productModel.variant_info != null
                    ? productModel.variant_info!.variant_id.toString()
                    : ""),
            name: productModel.name,
            photo: productModel.photo,
            price: mainPrice,
            discountPrice: productModel.disPrice,
            vendorID: productModel.vendorID,
            quantity: productQnt,
            extras_price: extras_price.toString(),
            extras: joinTitleString,
            category_id: productModel.categoryID,
            variant_info: productModel.variant_info));
      }
      setState(() {});
    } else {
      // Save full service permissions for CartScreen validation
      {
        final sp = await SharedPreferences.getInstance();
        await sp.setString(
          'service_perm_${widget.productModel.id}',
          jsonEncode({
            'delivery': widget.productModel.deliveryOption,
            'dineaway': widget.productModel.dineIn || widget.productModel.takeaway,
            'dineIn': widget.productModel.dineIn,
            'takeaway': widget.productModel.takeaway,
          }),
        );
        // Remove old schema key if present
        await sp.remove('dineaway_perm_${widget.productModel.id}');
      }

      // Save selected attribute options for cart display
      if (widget.productModel.productAttributes.isNotEmpty) {
        final sp = await SharedPreferences.getInstance();
        final selectionMap = <String, dynamic>{};
        for (final cfg in widget.productModel.productAttributes) {
          final selectedIds = _selectedAttrOptions[cfg.attributeId] ?? [];
          final selectedOpts = cfg.options
              .where((o) => o.enabled && selectedIds.contains(o.id))
              .map((o) => {'id': o.id, 'name': o.name, 'price': o.price})
              .toList();
          if (selectedOpts.isNotEmpty) {
            selectionMap[cfg.attributeId] = {
              'title': cfg.attributeTitle,
              'type': cfg.type,
              'options': selectedOpts,
            };
          }
        }
        await sp.setString('attr_sel_${widget.productModel.id}', jsonEncode(selectionMap));
        // When product has variant pricing, the selected option price replaces the base price entirely
        if (_hasVariantPricing && _attrAddOnTotal > 0) {
          widget.productModel.price = _attrAddOnTotal.toStringAsFixed(2);
          widget.productModel.disPrice = '0';
        }
      }

      if (cartProducts.isEmpty) {
        cartDatabase.addProduct(
            productModel, cartDatabase, isIncerementQuantity);
      } else {
        // Since we already checked for different vendors and handled it above,
        // we can simply add the product to the cart here
        cartDatabase.addProduct(
            productModel, cartDatabase, isIncerementQuantity);

        if (isAddOnApplied && AddOnVal > 0) {
          priceTemp += (AddOnVal * productQnt);
        }
      }
    }
    BehaviorTracker.track(kEvtProductAddedToCart, {
      'productId': productModel.id,
      'vendorId': productModel.vendorID,
      'quantity': productQnt,
      'categoryId': productModel.categoryID,
      // Cuisine preference signal (2026-07-27) - vendor object already in
      // memory here, no new Firestore read. Feeds cuisineInteractionCounts
      // alongside categoryId above - see BehaviorTracker's
      // kEvtProductAddedToCart case for the weighting.
      'cuisineIds': widget.vendorModel.cuisineIds,
      // Veg/Non-Veg preference signal (2026-07-25) - see
      // newVendorProductsScreen.dart's identical call site for why this is
      // captured at add-to-cart rather than order completion.
      'isVeg': productModel.veg,
      'isNonVeg': productModel.nonveg,
    });
    // Combo metadata cache (2026-07-24) - see
    // BehaviorTracker.rememberComboMetadata's own doc comment. A no-op for
    // every non-combo product (the vast majority).
    if (productModel.isCombo) {
      BehaviorTracker.rememberComboMetadata(
        productModel.id,
        comboProductIds:
            productModel.comboProducts.map((c) => c.productId).toList(),
        comboCategoryIds: productModel.comboCategoryIds,
        price: productModel.price,
      );
    }
    BehaviorTracker.bumpSessionAddToCart(_restaurantSessionId);
    updatePrice();
  }

  removetocard(ProductModel productModel, bool isIncerementQuantity) async {
    // We're setting isAddOnApplied but using it later in the method
    bool isAddOnApplied = false;
    double AddOnVal = 0;
    for (int i = 0; i < lstTemp.length; i++) {
      AddAddonsDemo addAddonsDemo = lstTemp[i];
      isAddOnApplied = true;
      AddOnVal = AddOnVal + double.parse(addAddonsDemo.price!);
    }
    // Print to use the variable (this will prevent the unused variable warning)
    print("Add-ons applied: ${isAddOnApplied ? 'Yes' : 'No'}, Total add-on value: $AddOnVal");
    List<CartProduct> cartProducts = await cartDatabase.allCartProducts;

    print("---->${productQnt}");
    if (productQnt >= 1) {
      //setState(() async {

      var joinTitleString = "";
      String mainPrice = "";
      List<AddAddonsDemo> lstAddOns = [];
      List<String> lstAddOnsTemp = [];
      double extras_price = 0.0;

      SharedPreferences sp = await SharedPreferences.getInstance();
      String addOns =
          sp.getString("musics_key") != null ? sp.getString('musics_key')! : "";

      bool isAddSame = false;
      if (!isAddSame) {
        if (productModel.disPrice != null &&
            productModel.disPrice!.isNotEmpty &&
            double.parse(productModel.disPrice!) != 0) {
          mainPrice = productModel.disPrice!;
        } else {
          mainPrice = productModel.price;
        }
      }

      if (addOns.isNotEmpty) {
        lstAddOns = AddAddonsDemo.decode(addOns);
        for (int a = 0; a < lstAddOns.length; a++) {
          AddAddonsDemo newAddonsObject = lstAddOns[a];
          if (newAddonsObject.categoryID == widget.productModel.id) {
            if (newAddonsObject.isCheck == true) {
              lstAddOnsTemp.add(newAddonsObject.name!);
              extras_price += (double.parse(newAddonsObject.price!));
            }
          }
        }

        joinTitleString = lstAddOnsTemp.join(",");
      }

      final bool _productIsInList = cartProducts.any((product) =>
          product.id ==
          productModel.id +
              "~" +
              (variants!
                      .where((element) =>
                          element.variant_sku == selectedVariants.join('-'))
                      .isNotEmpty
                  ? variants!
                      .where((element) =>
                          element.variant_sku == selectedVariants.join('-'))
                      .first
                      .variant_id
                      .toString()
                  : ""));
      if (_productIsInList) {
        CartProduct element = cartProducts.firstWhere((product) =>
            product.id ==
            productModel.id +
                "~" +
                (variants!
                        .where((element) =>
                            element.variant_sku == selectedVariants.join('-'))
                        .isNotEmpty
                    ? variants!
                        .where((element) =>
                            element.variant_sku == selectedVariants.join('-'))
                        .first
                        .variant_id
                        .toString()
                    : ""));
        print("------------>${element.quantity}");
        await cartDatabase.updateProduct(CartProduct(
            id: element.id,
            name: element.name,
            photo: element.photo,
            price: element.price,
            vendorID: element.vendorID,
            quantity:
                isIncerementQuantity ? element.quantity - 1 : element.quantity,
            category_id: element.category_id,
            extras_price: extras_price.toString(),
            extras: joinTitleString,
            discountPrice: element.discountPrice!));
      } else {
        await cartDatabase.updateProduct(CartProduct(
            id: productModel.id +
                "~" +
                (variants!
                        .where((element) =>
                            element.variant_sku == selectedVariants.join('-'))
                        .isNotEmpty
                    ? variants!
                        .where((element) =>
                            element.variant_sku == selectedVariants.join('-'))
                        .first
                        .variant_id
                        .toString()
                    : ""),
            name: productModel.name,
            photo: productModel.photo,
            price: mainPrice,
            discountPrice: productModel.disPrice,
            vendorID: productModel.vendorID,
            quantity: productQnt,
            extras_price: extras_price.toString(),
            extras: joinTitleString,
            category_id: productModel.categoryID,
            variant_info: productModel.variant_info));
      }
      BehaviorTracker.track(kEvtProductQuantityChanged, {
        'productId': productModel.id,
        'vendorId': productModel.vendorID,
        'categoryId': productModel.categoryID,
        'direction': 'dec',
        'newQuantity': productQnt,
      });
    } else {
      cartDatabase.removeProduct(productModel.id +
          "~" +
          (variants!
                  .where((element) =>
                      element.variant_sku == selectedVariants.join('-'))
                  .isNotEmpty
              ? variants!
                  .where((element) =>
                      element.variant_sku == selectedVariants.join('-'))
                  .first
                  .variant_id
                  .toString()
              : ""));
      BehaviorTracker.track(kEvtProductRemovedFromCart, {
        'productId': productModel.id,
        'vendorId': productModel.vendorID,
        'categoryId': productModel.categoryID,
      });
      setState(() {
        productQnt = 0;
      });
    }
    updatePrice();
  }

  void getAddOnsData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final String musicsString = prefs.getString('musics_key') != null
        ? prefs.getString('musics_key')!
        : "";

    if (musicsString.isNotEmpty) {
      setState(() {
        lstTemp = AddAddonsDemo.decode(musicsString);
      });
    }

    if (productQnt > 0) {
      lastPrice = widget.productModel.disPrice == "" ||
              widget.productModel.disPrice == "0"
          ? double.parse(widget.productModel.price)
          : double.parse(widget.productModel.disPrice!) * productQnt;
    }

    if (lstTemp.isEmpty) {
      setState(() {
        if (widget.productModel.addOnsTitle.isNotEmpty) {
          for (int a = 0; a < widget.productModel.addOnsTitle.length; a++) {
            AddAddonsDemo addAddonsDemo = AddAddonsDemo(
                name: widget.productModel.addOnsTitle[a],
                index: a,
                isCheck: false,
                categoryID: widget.productModel.id,
                price: widget.productModel.addOnsPrice[a]);
            lstAddAddonsCustom.add(addAddonsDemo);
            //saveAddonData(lstAddAddonsCustom);
          }
        }
      });
    } else {
      var tempArray = [];

      for (int d = 0; d < lstTemp.length; d++) {
        if (lstTemp[d].categoryID == widget.productModel.id) {
          AddAddonsDemo addAddonsDemo = AddAddonsDemo(
              name: lstTemp[d].name,
              index: lstTemp[d].index,
              isCheck: true,
              categoryID: lstTemp[d].categoryID,
              price: lstTemp[d].price);
          tempArray.add(addAddonsDemo);
        }
      }
      for (int a = 0; a < widget.productModel.addOnsTitle.length; a++) {
        var isAddonSelected = false;

        for (int temp = 0; temp < tempArray.length; temp++) {
          if (tempArray[temp].name == widget.productModel.addOnsTitle[a]) {
            isAddonSelected = true;
          }
        }
        if (isAddonSelected) {
          AddAddonsDemo addAddonsDemo = AddAddonsDemo(
              name: widget.productModel.addOnsTitle[a],
              index: a,
              isCheck: true,
              categoryID: widget.productModel.id,
              price: widget.productModel.addOnsPrice[a]);
          lstAddAddonsCustom.add(addAddonsDemo);
        } else {
          AddAddonsDemo addAddonsDemo = AddAddonsDemo(
              name: widget.productModel.addOnsTitle[a],
              index: a,
              isCheck: false,
              categoryID: widget.productModel.id,
              price: widget.productModel.addOnsPrice[a]);
          lstAddAddonsCustom.add(addAddonsDemo);
        }
      }
    }
    updatePrice();
  }

  void saveAddOns(List<AddAddonsDemo> lstTempDemo) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final String encodedData = AddAddonsDemo.encode(lstTempDemo);
    await prefs.setString('musics_key', encodedData);
  }

  void clearAddOnData() {
    bool isAddOnApplied = false;
    double AddOnVal = 0;

    for (int i = 0; i < lstTemp.length; i++) {
      if (lstTemp[i].categoryID == widget.productModel.id) {
        AddAddonsDemo addAddonsDemo = lstTemp[i];
        isAddOnApplied = true;
        AddOnVal = AddOnVal + double.parse(addAddonsDemo.price!);
      }
    }
    if (isAddOnApplied && AddOnVal > 0 && productQnt > 0) {
      priceTemp -= (AddOnVal * productQnt);
    }
  }

  void updatePrice() {
    double AddOnVal = 0;
    for (int i = 0; i < lstTemp.length; i++) {
      AddAddonsDemo addAddonsDemo = lstTemp[i];
      if (addAddonsDemo.categoryID == widget.productModel.id) {
        AddOnVal = AddOnVal + double.parse(addAddonsDemo.price!);
      }
    }
    List<CartProduct> cartProducts = [];
    Future.delayed(const Duration(milliseconds: 500), () {
      cartProducts.clear();

      cartDatabase.allCartProducts.then((value) {
        priceTemp = 0;
        cartProducts.addAll(value);
        for (int i = 0; i < cartProducts.length; i++) {
          CartProduct e = cartProducts[i];
          if (e.extras_price != null &&
              e.extras_price != "" &&
              double.parse(e.extras_price!) != 0) {
            priceTemp += double.parse(e.extras_price!) * e.quantity;
          }
          priceTemp += double.parse(e.price) * e.quantity;
        }
        setState(() {});
      });
    });
  }

  Widget _buildNutritionHighlightChips(BuildContext context, NutritionInfo info) {
    final highlights = info.getHighlights();
    if (highlights.isEmpty) return const SizedBox.shrink();
    final isDark = isDarkMode(context);
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: highlights.map((h) {
        final icon = _nutritionIcon(h['metric']!);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1B3A28) : const Color(0xFFE8F5EE),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? const Color(0xFF2D6A4F) : const Color(0xFF95D5B2),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: const Color(0xFF2D9A5E)),
              const SizedBox(width: 5),
              Text(
                'High ${h['metric']} • ${h['value']}${h['unit']}',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: AppThemeData.semiBold,
                  color: isDark ? const Color(0xFF81C995) : const Color(0xFF1B6B3A),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  IconData _nutritionIcon(String metric) {
    switch (metric) {
      case 'Calories': return Icons.local_fire_department_outlined;
      case 'Protein': return Icons.fitness_center_outlined;
      case 'Carbs': return Icons.grain_outlined;
      case 'Fat': return Icons.water_drop_outlined;
      case 'Fiber': return Icons.eco_outlined;
      default: return Icons.local_dining_outlined;
    }
  }

  Widget _buildDynamicAttributeSection(BuildContext context) {
    final isDark = isDarkMode(context);
    final configs = widget.productModel.productAttributes;
    final enabledConfigs = configs.where((c) => c.options.any((o) => o.enabled)).toList();
    if (enabledConfigs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                color: AppThemeData.primary500,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Customize Your Order'.tr(),
              style: TextStyle(
                fontSize: 16,
                fontFamily: AppThemeData.bold,
                color: isDark ? AppThemeData.grey50 : AppThemeData.grey900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...enabledConfigs.map((cfg) => _buildAttrGroupCard(cfg, isDark)),
        if (_attrAddOnTotal > 0) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark
                  ? AppThemeData.primary500.withOpacity(0.15)
                  : AppThemeData.primary500.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppThemeData.primary500.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, size: 14, color: AppThemeData.primary500),
                const SizedBox(width: 8),
                Text(
                  'Variant Total: '.tr(),
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: AppThemeData.medium,
                    color: isDark ? AppThemeData.grey300 : AppThemeData.grey600,
                  ),
                ),
                Text(
                  amountShow(amount: _attrAddOnTotal.toStringAsFixed(2)),
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: AppThemeData.bold,
                    color: AppThemeData.primary500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAttrGroupCard(ProductAttributeConfig cfg, bool isDark) {
    final isMS = cfg.type == 'MS';
    final enabledOptions = cfg.options.where((o) => o.enabled).toList();
    final selectedIds = _selectedAttrOptions[cfg.attributeId] ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF374151) : const Color(0xFFF3F4F6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  cfg.attributeTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: AppThemeData.semiBold,
                    color: isDark ? AppThemeData.grey50 : AppThemeData.grey900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isMS
                      ? const Color(0xFF3B82F6).withOpacity(0.1)
                      : const Color(0xFF10B981).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isMS ? 'Choose multiple'.tr() : 'Choose one'.tr(),
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: AppThemeData.medium,
                    color: isMS ? const Color(0xFF2563EB) : const Color(0xFF059669),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (isMS)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: enabledOptions.map((opt) {
                final isSelected = selectedIds.contains(opt.id);
                return _buildMSChip(opt, isSelected, cfg.attributeId, isDark);
              }).toList(),
            )
          else
            Column(
              children: enabledOptions.map((opt) {
                final isSelected = selectedIds.contains(opt.id);
                return _buildSSRadioRow(opt, isSelected, cfg.attributeId, isDark);
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildSSRadioRow(ProductAttributeOption opt, bool isSelected, String attrId, bool isDark) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedAttrOptions[attrId] = [opt.id];
          _recalcAttrTotal();
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppThemeData.primary500.withOpacity(0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppThemeData.primary500.withOpacity(0.5)
                : (isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB)),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppThemeData.primary500 : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppThemeData.primary500,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                opt.name,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: isSelected ? AppThemeData.semiBold : AppThemeData.regular,
                  color: isSelected
                      ? (isDark ? AppThemeData.grey50 : AppThemeData.grey900)
                      : (isDark ? AppThemeData.grey300 : AppThemeData.grey600),
                ),
              ),
            ),
            if (opt.price > 0 || opt.discountedPrice > 0)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amountShow(amount: opt.effectivePrice.toStringAsFixed(2)),
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: AppThemeData.semiBold,
                      color: isSelected ? AppThemeData.primary500 : Colors.grey.shade500,
                    ),
                  ),
                  if (opt.discountedPrice > 0 && opt.price > 0)
                    Text(
                      amountShow(amount: opt.price.toStringAsFixed(2)),
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: AppThemeData.regular,
                        color: Colors.grey.shade400,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                ],
              )
            else
              Text(
                'Free'.tr(),
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: AppThemeData.medium,
                  color: const Color(0xFF10B981),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMSChip(ProductAttributeOption opt, bool isSelected, String attrId, bool isDark) {
    return GestureDetector(
      onTap: () {
        setState(() {
          final current = List<String>.from(_selectedAttrOptions[attrId] ?? []);
          if (isSelected) {
            current.remove(opt.id);
          } else {
            current.add(opt.id);
          }
          _selectedAttrOptions[attrId] = current;
          _recalcAttrTotal();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppThemeData.primary500.withOpacity(0.1)
              : (isDark ? const Color(0xFF2D3748) : const Color(0xFFF9FAFB)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppThemeData.primary500.withOpacity(0.6)
                : (isDark ? const Color(0xFF4B5563) : const Color(0xFFE5E7EB)),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              Icon(Icons.check_circle, size: 14, color: AppThemeData.primary500),
              const SizedBox(width: 5),
            ],
            Text(
              opt.name,
              style: TextStyle(
                fontSize: 13,
                fontFamily: isSelected ? AppThemeData.semiBold : AppThemeData.regular,
                color: isSelected
                    ? AppThemeData.primary500
                    : (isDark ? AppThemeData.grey300 : AppThemeData.grey700),
              ),
            ),
            if (opt.price > 0 || opt.discountedPrice > 0) ...[
              const SizedBox(width: 5),
              Text(
                amountShow(amount: opt.effectivePrice.toStringAsFixed(2)),
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: AppThemeData.semiBold,
                  color: isSelected ? AppThemeData.primary500 : Colors.grey.shade500,
                ),
              ),
              if (opt.discountedPrice > 0 && opt.price > 0) ...[
                const SizedBox(width: 3),
                Text(
                  amountShow(amount: opt.price.toStringAsFixed(2)),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade400,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label, int attributesOptionIndex, bool isSelected) {
    return Chip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black,
            ),
          ),
        ],
      ),
      backgroundColor: isSelected ? AppThemeData.primary500 : Colors.white,
      elevation: 6.0,
      shadowColor: Colors.grey[60],
      padding: const EdgeInsets.all(8.0),
    );

    // Container(
    //   decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), border: Border.all(color: const Color(0xffABBCC8), width: 0.5)),
    //   child: Padding(
    //     padding: const EdgeInsets.all(2.0),
    //     child: Container(
    //       decoration: BoxDecoration(
    //         color: isSelected ? AppThemeData.primary500 : Colors.white,
    //         borderRadius: BorderRadius.circular(30),
    //       ),
    //       child: Center(
    //         child: Text(
    //           label,
    //           style: TextStyle(
    //             color: isSelected ? Colors.white : Colors.black,
    //           ),
    //         ),
    //       ),
    //       // child: Chip(
    //       //   label: Text(
    //       //     label,
    //       //     style: const TextStyle(
    //       //       color: Colors.white,
    //       //     ),
    //       //   ),
    //       //   backgroundColor: colors,
    //       //   elevation: 6.0,
    //       //   shadowColor: Colors.grey[60],
    //       //   padding: const EdgeInsets.all(8.0),
    //       // ),
    //     ),
    //   ),
    // );
  }
}

class AddAddonsDemo {
  String? name;
  int? index;
  String? price;
  bool isCheck;
  String? categoryID;

  AddAddonsDemo(
      {this.name,
      this.index,
      this.price,
      this.isCheck = false,
      this.categoryID});

  static Map<String, dynamic> toMap(AddAddonsDemo music) => {
        'index': music.index,
        'name': music.name,
        'price': music.price,
        'isCheck': music.isCheck,
        "categoryID": music.categoryID
      };

  factory AddAddonsDemo.fromJson(Map<String, dynamic> jsonData) {
    return AddAddonsDemo(
        index: jsonData['index'],
        name: jsonData['name'],
        price: jsonData['price'],
        isCheck: jsonData['isCheck'],
        categoryID: jsonData["categoryID"]);
  }

  static String encode(List<AddAddonsDemo> item) => json.encode(
        item
            .map<Map<String, dynamic>>((item) => AddAddonsDemo.toMap(item))
            .toList(),
      );

  static List<AddAddonsDemo> decode(String item) =>
      (json.decode(item) as List<dynamic>)
          .map<AddAddonsDemo>((item) => AddAddonsDemo.fromJson(item))
          .toList();

  @override
  String toString() {
    return '{name: $name, index: $index, price: $price, isCheck: $isCheck, categoryID: $categoryID}';
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'index': index,
      'price': price,
      'isCheck': isCheck,
      'categoryID': categoryID
    };
  }
}

  /// Get an appropriate icon for add-on items based on name
  IconData _getAddonIcon(String addonName) {
    String lowerName = addonName.toLowerCase();

    // Food related icons
    if (lowerName.contains('cheese') || lowerName.contains('paneer')) {
      return Icons.fastfood_rounded;
    } else if (lowerName.contains('chicken') || lowerName.contains('meat')) {
      return Icons.dinner_dining;
    } else if (lowerName.contains('egg')) {
      return Icons.egg_rounded;
    } else if (lowerName.contains('onion') || lowerName.contains('pepper')) {
      return Icons.circle_rounded;
    } else if (lowerName.contains('tomato')) {
      return Icons.circle_rounded;
    } else if (lowerName.contains('lettuce') || lowerName.contains('salad') || lowerName.contains('leaf')) {
      return Icons.eco_rounded;
    } else if (lowerName.contains('sauce') || lowerName.contains('dip')) {
      return Icons.water_drop_rounded;
    } else if (lowerName.contains('bread') || lowerName.contains('bun')) {
      return Icons.bakery_dining_rounded;
    } else if (lowerName.contains('fries') || lowerName.contains('potato')) {
      return Icons.tapas_rounded;
    } else if (lowerName.contains('drink') || lowerName.contains('beverage') || lowerName.contains('coke')) {
      return Icons.local_drink_rounded;
    } else if (lowerName.contains('ice cream') || lowerName.contains('dessert')) {
      return Icons.icecream_rounded;
    } else if (lowerName.contains('coffee')) {
      return Icons.coffee_rounded;
    } else if (lowerName.contains('pizza')) {
      return Icons.local_pizza_rounded;
    } else if (lowerName.contains('burger')) {
      return Icons.lunch_dining_rounded;
    } else if (lowerName.contains('salt') || lowerName.contains('spicy')) {
      return Icons.whatshot_rounded;
    } else {
      // Default icon for generic add-ons
      return Icons.restaurant_rounded;
    }
  }

class SharedData {
  bool? isCheckedValue;
  String? categoryId;

  SharedData({this.categoryId, this.isCheckedValue});
}
