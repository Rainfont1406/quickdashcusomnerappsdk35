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
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/theme/responsive.dart';
import 'package:emartconsumer/ui/productDetailsScreen/ProductDetailsScreen.dart';
import 'package:emartconsumer/ui/review_list_screen/review_list_screen.dart';
import 'package:emartconsumer/utils/network_image_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:collection/collection.dart';
import 'package:emartconsumer/ui/cartScreen/CartScreen.dart';
import 'package:emartconsumer/ui/container/ContainerScreen.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/ui/vendorProductsScreen/vendor_products_skeleton.dart';
import 'package:emartconsumer/widget/product_options_dialog.dart';

class NewVendorProductsScreen extends StatefulWidget {
  final VendorModel vendorModel;

  const NewVendorProductsScreen({Key? key, required this.vendorModel})
      : super(key: key);

  @override
  State<NewVendorProductsScreen> createState() =>
      _NewVendorProductsScreenState();
}

class _NewVendorProductsScreenState extends State<NewVendorProductsScreen>
    with SingleTickerProviderStateMixin {
  final FireStoreUtils fireStoreUtils = FireStoreUtils();
  late CartDatabase cartDatabase;
  bool _cartReady = false;
  List<CartProduct> cartProducts = [];
  StreamSubscription<List<CartProduct>>? _cartSubscription;

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    getFoodType();
    statusCheck();
    animateSlider();
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

  String? foodType;

  List a = [];
  List<ProductModel> allProductList = [];
  List<ProductModel> productList = [];

  void getFoodType() async {
    SharedPreferences sp = await SharedPreferences.getInstance();
    foodType = sp.getString("foodType") ?? "Delivery".tr();

    print("------->${foodType}");
    if (foodType == "Takeaway") {
      await fireStoreUtils
          .getVendorProductsTakeAWay(widget.vendorModel.id)
          .then((value) {
        allProductList = value;
        productList = value;
        getVendorCategoryById();
        setState(() {});
      });
    } else {
      await fireStoreUtils
          .getVendorProductsDelivery(widget.vendorModel.id)
          .then((value) {
        allProductList = value;
        productList = value;
        getVendorCategoryById();
        setState(() {});
      });
    }
  }

  List<VendorCategoryModel> vendorCategoryList = [];
  List<OfferModel> offerList = [];
  List<FavouriteItemModel> favouriteItemList = <FavouriteItemModel>[];

  getVendorCategoryById() async {
    vendorCategoryList.clear();

    for (var element in productList) {
      FireStoreUtils.getVendorCategoryById(element.categoryID.toString()).then(
        (value) {
          if (value != null) {
            if (vendorCategoryList
                .where((element) => element.id == value.id)
                .isEmpty) {
              vendorCategoryList.add(value);
            }
          }
        },
      );
    }

    var seen = <String>{};
    vendorCategoryList = vendorCategoryList
        .where((element) => seen.add(element.id.toString()))
        .toList();

    await FireStoreUtils()
        .getOfferByVendorID(widget.vendorModel.id)
        .then((value) {
      setState(() {
        offerList = value;
      });
    });

    if (MyAppState.currentUser != null) {
      await FireStoreUtils.getFavouriteStore(FireStoreUtils.getCurrentUid())
          .then(
        (value) {
          setState(() {
            favouriteList = value;
          });
        },
      );

      await FireStoreUtils.getFavouriteItem().then(
        (value) {
          setState(() {
            favouriteItemList = value;
          });
        },
      );
    }
    setState(() {
      isLoading = false;
    });
  }

  @override
  void dispose() {
    _sliderTimer?.cancel();
    _closingCountdownTimer?.cancel();
    _cartSubscription?.cancel();
    super.dispose();
  }

  List<FavouriteModel> favouriteList = [];
  PageController pageController = PageController();
  int currentPage = 0;
  Timer? _sliderTimer;

  void animateSlider() {
    if (widget.vendorModel.photos.isNotEmpty) {
      _sliderTimer = Timer.periodic(const Duration(seconds: 2), (Timer timer) {
        if (currentPage < widget.vendorModel.photos.length - 1) {
          currentPage++;
        } else {
          currentPage = 0;
        }

        if (pageController.hasClients) {
          pageController.animateToPage(
            currentPage,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeIn,
          );
        }
        setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    double cartTotal = 0;
    for (final cartProduct in cartProducts) {
      double price = double.tryParse(cartProduct.price) ?? 0;
      double extras = double.tryParse(cartProduct.extras_price ?? '0') ?? 0;
      cartTotal += (price + extras) * cartProduct.quantity;
    }
    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? AppThemeData.surfaceDark : AppThemeData.surface,
      body: isLoading == true
          ? const VendorProductsSkeletonLoader()
          : NestedScrollView(
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
                          onTap: () async {
                            // Check if user is logged in
                            if (MyAppState.currentUser == null) {
                              push(context, const LoginScreen());
                              return;
                            }

                            if (favouriteList
                                .where((p0) =>
                                    p0.store_id == widget.vendorModel.id)
                                .isNotEmpty) {
                              FavouriteModel favouriteModel = FavouriteModel(
                                  section_id: sectionConstantModel!.id,
                                  store_id: widget.vendorModel.id,
                                  user_id: MyAppState.currentUser!.userID);
                              favouriteList.removeWhere((item) =>
                                  item.store_id == widget.vendorModel.id);
                              await FireStoreUtils.removeFavouriteStore(
                                  favouriteModel);
                            } else {
                              FavouriteModel favouriteModel = FavouriteModel(
                                  section_id: sectionConstantModel!.id,
                                  store_id: widget.vendorModel.id,
                                  user_id: MyAppState.currentUser!.userID);
                              await FireStoreUtils.setFavouriteStore(
                                  favouriteModel);
                              favouriteList.add(favouriteModel);
                            }
                            setState(() {});
                          },
                          child: favouriteList
                                  .where((p0) =>
                                      p0.store_id == widget.vendorModel.id)
                                  .isNotEmpty
                              ? SvgPicture.asset(
                                  "assets/icons/ic_like_fill.svg",
                                  colorFilter: const ColorFilter.mode(
                                      AppThemeData.grey50, BlendMode.srcIn),
                                )
                              : SvgPicture.asset(
                                  "assets/icons/ic_like.svg",
                                ),
                        ),
                        const SizedBox(
                          width: 10,
                        ),
                      ],
                    ),
                    flexibleSpace: FlexibleSpaceBar(
                      background: Stack(
                        children: [
                          widget.vendorModel.photos.isEmpty
                              ? Stack(
                                  children: [
                                    NetworkImageWidget(
                                      imageUrl:
                                          widget.vendorModel.photo.toString(),
                                      fit: BoxFit.cover,
                                      width: Responsive.width(100, context),
                                      height: Responsive.height(40, context),
                                    ),
                                    Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: const Alignment(0.00, -1.00),
                                          end: const Alignment(0, 1),
                                          colors: [
                                            Colors.black.withOpacity(0),
                                            Colors.black
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
                                  itemCount: widget.vendorModel.photos.length,
                                  padEnds: false,
                                  pageSnapping: true,
                                  itemBuilder:
                                      (BuildContext context, int index) {
                                    String image =
                                        widget.vendorModel.photos[index];
                                    return Stack(
                                      children: [
                                        NetworkImageWidget(
                                          imageUrl: image.toString(),
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
                                                Colors.black
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
                                widget.vendorModel.photos.length,
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
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Restaurant Name and Rating Section
                            InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _showRestaurantInfoSheet(context),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: isDarkMode(context)
                                      ? AppThemeData.darkBgTertiary
                                      : Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(
                                          isDarkMode(context) ? 0.2 : 0.06),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                                    color:
                                                        AppThemeData.primary500,
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Expanded(
                                                    child: Text(
                                                      widget.vendorModel
                                                          .location
                                                          .toString(),
                                                      textAlign: TextAlign.start,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontFamily:
                                                            AppThemeData.medium,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        color:
                                                            isDarkMode(context)
                                                                ? AppThemeData
                                                                    .grey400
                                                                : AppThemeData
                                                                    .grey500,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
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
                                                vendorId: widget.vendorModel.id,
                                              ),
                                            );
                                          },
                                          child: Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  isDarkMode(context)
                                                      ? const Color(0xFF2E3F5C)
                                                      : const Color(0xFFFFF8E1),
                                                  isDarkMode(context)
                                                      ? const Color(0xFF1F2B42)
                                                      : const Color(0xFFFFECB3),
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 7),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                SvgPicture.asset(
                                                  "assets/icons/ic_star.svg",
                                                  colorFilter:
                                                      const ColorFilter.mode(
                                                          Color(0xFFFFB300),
                                                          BlendMode.srcIn),
                                                  height: 15,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  "${calculateReview(reviewCount: widget.vendorModel.reviewsCount.toStringAsFixed(0), reviewSum: widget.vendorModel.reviewsSum.toString())} (${widget.vendorModel.reviewsCount.toStringAsFixed(0)})",
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                    color: isDarkMode(context)
                                                        ? const Color(
                                                            0xFFFFB300)
                                                        : const Color(
                                                            0xFFE65100),
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
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.info_outline_rounded,
                                          size: 13,
                                          color: isDarkMode(context)
                                              ? AppThemeData.grey500
                                              : AppThemeData.grey400,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Tap for more details'.tr(),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDarkMode(context)
                                                ? AppThemeData.grey500
                                                : AppThemeData.grey400,
                                            fontFamily: AppThemeData.regular,
                                          ),
                                        ),
                                        const Spacer(),
                                        Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          size: 16,
                                          color: isDarkMode(context)
                                              ? AppThemeData.grey500
                                              : AppThemeData.grey400,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Open/Close Status Section
                            sectionConstantModel!.serviceTypeFlag ==
                                    "ecommerce-service"
                                ? const SizedBox()
                                : Builder(builder: (context) {
                                    final isClosingSoon = isOpen &&
                                        _closingIn != null &&
                                        _closingIn!.inSeconds > 0;
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
                                        ? _closingIn!.inMinutes
                                            .remainder(60)
                                            .toString()
                                            .padLeft(2, '0')
                                        : '00';
                                    final secs = _closingIn != null
                                        ? _closingIn!.inSeconds
                                            .remainder(60)
                                            .toString()
                                            .padLeft(2, '0')
                                        : '00';
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 12),
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
                                              padding: const EdgeInsets.all(4),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: statusColor,
                                              ),
                                              child: Icon(
                                                isOpen
                                                    ? Icons.access_time_filled
                                                    : Icons
                                                        .access_time_outlined,
                                                color: Colors.white,
                                                size: 12,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            isClosingSoon
                                                ? RichText(
                                                    text: TextSpan(
                                                      children: [
                                                        TextSpan(
                                                          text: 'Closing in ',
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            fontFamily:
                                                                AppThemeData
                                                                    .semiBold,
                                                            color: statusColor,
                                                          ),
                                                        ),
                                                        TextSpan(
                                                          text: '$mins:$secs',
                                                          style: TextStyle(
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            fontFamily:
                                                                AppThemeData
                                                                    .bold,
                                                            color: statusColor,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  )
                                                : Text(
                                                    isOpen
                                                        ? "Open Now".tr()
                                                        : "Currently Closed"
                                                            .tr(),
                                                    textAlign: TextAlign.start,
                                                    maxLines: 1,
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      fontFamily:
                                                          AppThemeData.semiBold,
                                                      color: statusColor,
                                                    ),
                                                  ),
                                            const Spacer(),
                                            InkWell(
                                              onTap: () {
                                                if (widget.vendorModel
                                                    .workingHours.isEmpty) {
                                                  ShowToastDialog.showToast(
                                                      "Timing is not added by restaurant");
                                                } else {
                                                  timeShowBottomSheet(context);
                                                }
                                              },
                                              child: Text(
                                                "View Hours".tr(),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color:
                                                      AppThemeData.secondary300,
                                                  fontFamily:
                                                      AppThemeData.semiBold,
                                                  decoration:
                                                      TextDecoration.underline,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }),

                            // Offers Section
                            offerList.isEmpty
                                ? const SizedBox()
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.local_offer,
                                            color: AppThemeData.primary500,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            "Offers".tr(),
                                            textAlign: TextAlign.start,
                                            maxLines: 1,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              overflow: TextOverflow.ellipsis,
                                              fontFamily: AppThemeData.semiBold,
                                              color: isDarkMode(context)
                                                  ? AppThemeData.grey50
                                                  : AppThemeData.grey900,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      CouponListView(offerList: offerList),
                                    ],
                                  ),

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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Search Bar
                                  Container(
                                    decoration: BoxDecoration(
                                      color: isDarkMode(context)
                                          ? AppThemeData.grey800
                                          : AppThemeData.grey100,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isDarkMode(context)
                                            ? AppThemeData.grey700
                                            : AppThemeData.grey200,
                                        width: 1,
                                      ),
                                    ),
                                    child: TextField(
                                      onChanged: searchProduct,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: isDarkMode(context)
                                            ? AppThemeData.grey50
                                            : AppThemeData.grey900,
                                        fontFamily: AppThemeData.regular,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'Search dishes...'.tr(),
                                        hintStyle: TextStyle(
                                          color: isDarkMode(context)
                                              ? AppThemeData.grey500
                                              : AppThemeData.grey400,
                                          fontFamily: AppThemeData.regular,
                                          fontSize: 14,
                                        ),
                                        prefixIcon: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 13),
                                          child: SvgPicture.asset(
                                            "assets/icons/ic_search.svg",
                                            colorFilter: ColorFilter.mode(
                                              isDarkMode(context)
                                                  ? AppThemeData.grey400
                                                  : AppThemeData.grey500,
                                              BlendMode.srcIn,
                                            ),
                                            height: 18,
                                            width: 18,
                                          ),
                                        ),
                                        prefixIconConstraints:
                                            const BoxConstraints(
                                                minWidth: 46, minHeight: 46),
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                vertical: 14, horizontal: 4),
                                      ),
                                    ),
                                  ),

                                  // Veg/Non-Veg Filter
                                  if (sectionConstantModel!.isProductDetails ==
                                      true)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 14),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: GestureDetector(
                                              onTap: () {
                                                setState(
                                                    () => isVag = !isVag);
                                                filterRecord();
                                              },
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                    milliseconds: 200),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 10,
                                                        horizontal: 8),
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(24),
                                                  color: isVag
                                                      ? AppThemeData.success400
                                                      : isDarkMode(context)
                                                          ? AppThemeData.grey800
                                                          : AppThemeData
                                                              .grey100,
                                                  border: Border.all(
                                                    color: isVag
                                                        ? AppThemeData.success400
                                                        : isDarkMode(context)
                                                            ? AppThemeData
                                                                .grey700
                                                            : AppThemeData
                                                                .grey300,
                                                    width: 1.5,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    SvgPicture.asset(
                                                      "assets/icons/ic_veg.svg",
                                                      height: 16,
                                                      width: 16,
                                                      colorFilter: isVag
                                                          ? const ColorFilter
                                                              .mode(Colors.white,
                                                              BlendMode.srcIn)
                                                          : null,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      'Veg'.tr(),
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: isVag
                                                            ? Colors.white
                                                            : isDarkMode(context)
                                                                ? AppThemeData
                                                                    .grey300
                                                                : AppThemeData
                                                                    .grey700,
                                                        fontFamily: AppThemeData
                                                            .semiBold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: GestureDetector(
                                              onTap: () {
                                                setState(() =>
                                                    isNonVag = !isNonVag);
                                                filterRecord();
                                              },
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                    milliseconds: 200),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 10,
                                                        horizontal: 8),
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(24),
                                                  color: isNonVag
                                                      ? AppThemeData.danger300
                                                      : isDarkMode(context)
                                                          ? AppThemeData.grey800
                                                          : AppThemeData
                                                              .grey100,
                                                  border: Border.all(
                                                    color: isNonVag
                                                        ? AppThemeData.danger300
                                                        : isDarkMode(context)
                                                            ? AppThemeData
                                                                .grey700
                                                            : AppThemeData
                                                                .grey300,
                                                    width: 1.5,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    SvgPicture.asset(
                                                      "assets/icons/ic_nonveg.svg",
                                                      height: 16,
                                                      width: 16,
                                                      colorFilter: isNonVag
                                                          ? const ColorFilter
                                                              .mode(Colors.white,
                                                              BlendMode.srcIn)
                                                          : null,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      'Non Veg'.tr(),
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: isNonVag
                                                            ? Colors.white
                                                            : isDarkMode(context)
                                                                ? AppThemeData
                                                                    .grey300
                                                                : AppThemeData
                                                                    .grey700,
                                                        fontFamily: AppThemeData
                                                            .semiBold,
                                                      ),
                                                    ),
                                                  ],
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
                          ],
                        ),
                      ),

                      // Nutrition Filter
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: _buildNutritionFilterSection(context),
                      ),

                      const SizedBox(height: 16),

                      // Product List View
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(24),
                            topRight: Radius.circular(24),
                          ),
                          color: isDarkMode(context)
                              ? AppThemeData.grey900
                              : AppThemeData.grey50,
                        ),
                        child: productListView(),
                      ),
                    ],
                  ),
                ),
              )),
      bottomNavigationBar: cartProducts.isNotEmpty
          ? Container(
              color: AppThemeData.primary500,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 30),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Item Total".tr(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontFamily: AppThemeData.medium,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          amountShow(amount: cartTotal.toString()),
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

  static const _nutritionMetrics = ['Calories', 'Protein', 'Carbs', 'Fat', 'Fiber'];
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
        return p.nutritionInfo!.classifyMetric(_nutritionFilterType!) == _nutritionFilterLevel;
      }).toList();
    }

    productList = base;
    setState(() {});
  }

  searchProduct(String name) {
    if (name.isEmpty) {
      productList.clear();
      productList.addAll(allProductList);
    } else {
      isVag = false;
      isNonVag = false;
      _nutritionFilterType = null;
      _nutritionFilterLevel = null;
      productList = allProductList
          .where((p0) => p0.name.toLowerCase().contains(name.toLowerCase()))
          .toList();
    }
    setState(() {});
  }

  Widget _buildNutritionFilterSection(BuildContext context) {
    final isDark = isDarkMode(context);
    final hasFilter = _nutritionFilterType != null && _nutritionFilterLevel != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.monitor_heart_outlined,
              size: 14,
              color: isDark ? AppThemeData.grey400 : AppThemeData.grey600,
            ),
            const SizedBox(width: 6),
            Text(
              'Nutrition Filter'.tr(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? AppThemeData.grey300 : AppThemeData.grey700,
                fontFamily: AppThemeData.semiBold,
                letterSpacing: 0.2,
              ),
            ),
            if (hasFilter) ...[
              const Spacer(),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _nutritionFilterType = null;
                    _nutritionFilterLevel = null;
                  });
                  filterRecord();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppThemeData.primary500.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close, size: 11, color: AppThemeData.primary500),
                      const SizedBox(width: 3),
                      Text(
                        'Clear'.tr(),
                        style: TextStyle(
                          fontSize: 11,
                          color: AppThemeData.primary500,
                          fontFamily: AppThemeData.medium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildNutritionDropdown(
                context: context,
                hint: 'Nutrition Type'.tr(),
                value: _nutritionFilterType,
                items: _nutritionMetrics,
                onChanged: (val) {
                  setState(() => _nutritionFilterType = val);
                  if (_nutritionFilterLevel != null) filterRecord();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildNutritionDropdown(
                context: context,
                hint: 'Level'.tr(),
                value: _nutritionFilterLevel,
                items: _nutritionLevels,
                onChanged: (val) {
                  setState(() => _nutritionFilterLevel = val);
                  if (_nutritionFilterType != null) filterRecord();
                },
              ),
            ),
          ],
        ),
        if (hasFilter) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1B3A28) : const Color(0xFFE8F5EE),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? const Color(0xFF2D6A4F) : const Color(0xFF95D5B2),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.filter_alt_outlined, size: 14, color: const Color(0xFF2D9A5E)),
                const SizedBox(width: 6),
                Text(
                  '$_nutritionFilterLevel $_nutritionFilterType dishes — ${productList.length} found'.tr(),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? const Color(0xFF81C995) : const Color(0xFF1B6B3A),
                    fontFamily: AppThemeData.medium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNutritionDropdown({
    required BuildContext context,
    required String hint,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final isDark = isDarkMode(context);
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: isDark ? AppThemeData.grey800 : AppThemeData.grey100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value != null
              ? AppThemeData.primary500
              : (isDark ? AppThemeData.grey700 : AppThemeData.grey200),
          width: value != null ? 1.5 : 1,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              hint,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppThemeData.grey500 : AppThemeData.grey400,
                fontFamily: AppThemeData.regular,
              ),
            ),
          ),
          icon: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: value != null
                  ? AppThemeData.primary500
                  : (isDark ? AppThemeData.grey500 : AppThemeData.grey400),
            ),
          ),
          isExpanded: true,
          dropdownColor: isDark ? AppThemeData.grey800 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          items: items.map((item) => DropdownMenuItem<String>(
            value: item,
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                item,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppThemeData.grey100 : AppThemeData.grey800,
                  fontFamily: AppThemeData.medium,
                ),
              ),
            ),
          )).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  bool isOpen = false;
  Duration? _closingIn;
  Timer? _closingCountdownTimer;

  statusCheck() {
    final now = DateTime.now();
    var day = DateFormat('EEEE', 'en_US').format(now);
    var date = DateFormat('dd-MM-yyyy').format(now);
    DateTime? activeEnd;
    for (var element in widget.vendorModel.workingHours ?? []) {
      if (day == element.day.toString()) {
        if (element.timeslot!.isNotEmpty) {
          for (var slot in element.timeslot!) {
            var start =
                DateFormat("dd-MM-yyyy HH:mm").parse("$date ${slot.from}");
            var end =
                DateFormat("dd-MM-yyyy HH:mm").parse("$date ${slot.to}");
            if (isCurrentDateInRange(start, end)) {
              activeEnd = end;
              setState(() {
                isOpen = true;
              });
            }
          }
        }
      }
    }
    if (activeEnd != null) {
      _startClosingCountdown(activeEnd);
    }
  }

  void _startClosingCountdown(DateTime closingTime) {
    _closingCountdownTimer?.cancel();
    final remaining = closingTime.difference(DateTime.now());
    if (remaining.inMinutes < 60 && remaining.inSeconds > 0) {
      setState(() => _closingIn = remaining);
      _closingCountdownTimer =
          Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        final r = closingTime.difference(DateTime.now());
        if (r.inSeconds <= 0) {
          timer.cancel();
          setState(() {
            isOpen = false;
            _closingIn = null;
          });
        } else {
          setState(() => _closingIn = r);
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

  productListView() {
    return Container(
      color: isDarkMode(context) ? AppThemeData.grey900 : AppThemeData.grey50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: vendorCategoryList.length,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          VendorCategoryModel vendorCategoryModel = vendorCategoryList[index];
          return Card(
            elevation: 0,
            color: Colors.transparent,
            margin: const EdgeInsets.only(bottom: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                childrenPadding: EdgeInsets.zero,
                tilePadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                initiallyExpanded: true,
                collapsedBackgroundColor: isDarkMode(context)
                    ? AppThemeData.grey800.withOpacity(0.5)
                    : AppThemeData.grey100,
                backgroundColor: isDarkMode(context)
                    ? AppThemeData.grey800.withOpacity(0.3)
                    : AppThemeData.grey50,
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
                            "${productList.where((p0) => p0.categoryID == vendorCategoryModel.id).toList().length} items",
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
                children: [
                  ListView.separated(
                    itemCount: productList
                        .where((p0) => p0.categoryID == vendorCategoryModel.id)
                        .toList()
                        .length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    separatorBuilder: (context, index) => Divider(
                      height: 20,
                      thickness: 1,
                      color: isDarkMode(context)
                          ? AppThemeData.grey800.withOpacity(0.5)
                          : AppThemeData.grey200.withOpacity(0.5),
                      indent: 70,
                      endIndent: 10,
                    ),
                    itemBuilder: (context, index) {
                      ProductModel productModel = productList
                          .where(
                              (p0) => p0.categoryID == vendorCategoryModel.id)
                          .toList()[index];

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
                          final _match = _variants.where(
                              (e) => e.variant_sku == selectedVariants.join('-'));
                          if (_match.isNotEmpty) {
                            price = productCommissionPrice(
                                _match.first.variant_price ?? '0');
                            disPrice = "0";
                          }
                        }
                      } else {
                        price = productCommissionPrice(
                            productModel.price.toString());
                        disPrice =
                            double.parse(productModel.disPrice.toString()) <= 0
                                ? "0"
                                : productCommissionPrice(
                                    productModel.disPrice.toString());
                      }

                      final bool _pHasRestrictions = productModel.deliveryOption ||
                          productModel.dineAwayTakeaway || productModel.dineIn;
                      final bool _pIsDineaway = foodType == "Takeaway".tr() ||
                          foodType == "Dineaway".tr();

                      bool showAddButton = !_pHasRestrictions ||
                          (_pIsDineaway && productModel.dineAwayTakeaway) ||
                          (foodType == "Delivery".tr() && productModel.deliveryOption);

                      bool hasVariants = productModel.itemAttributes != null &&
                          productModel.itemAttributes!.attributes!.isNotEmpty;
                      bool hasAddOns = productModel.addOnsTitle.isNotEmpty;

                      String unavailabilityMessage = "";
                      if (_pHasRestrictions) {
                        if (_pIsDineaway && !productModel.dineAwayTakeaway) {
                          unavailabilityMessage = "Not available for DineAway/Takeaway";
                        } else if (foodType == "Delivery".tr() &&
                            !productModel.deliveryOption) {
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
                        cartProduct =
                            cartProducts.firstWhereOrNull((p) => p.id == cartId);
                      } else {
                        // Exact match first (no-variant products stored as "id~")
                        final exactId = "${productModel.id}~";
                        cartProduct =
                            cartProducts.firstWhereOrNull((p) => p.id == exactId);
                        // Fallback: variant was auto-assigned on add — match by prefix
                        cartProduct ??= cartProducts.firstWhereOrNull(
                            (p) => p.id.startsWith("${productModel.id}~"));
                      }

                      return Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              push(
                                context,
                                ProductDetailsScreen(
                                  productModel: productModel,
                                  vendorModel: widget.vendorModel,
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // ── LEFT: Details ──────────────────────
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Veg / Non-veg badge
                                        if (sectionConstantModel != null &&
                                            sectionConstantModel!
                                                    .isProductDetails ==
                                                true)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SvgPicture.asset(
                                                productModel.nonveg
                                                    ? "assets/icons/ic_nonveg.svg"
                                                    : "assets/icons/ic_veg.svg",
                                                height: 15,
                                                width: 15,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                productModel.nonveg
                                                    ? "Non Veg".tr()
                                                    : "Veg".tr(),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: productModel.nonveg
                                                      ? AppThemeData.danger300
                                                      : AppThemeData.success400,
                                                  fontFamily:
                                                      AppThemeData.medium,
                                                ),
                                              ),
                                            ],
                                          ),
                                        if (sectionConstantModel != null &&
                                            sectionConstantModel!
                                                    .isProductDetails ==
                                                true)
                                          const SizedBox(height: 5),
                                        // Item name
                                        Text(
                                          productModel.name.toString(),
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: isDarkMode(context)
                                                ? AppThemeData.grey50
                                                : AppThemeData.grey900,
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
                                            padding: const EdgeInsets.only(
                                                bottom: 4),
                                            child: Text(
                                              productModel.description!,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                height: 1.4,
                                                color: isDarkMode(context)
                                                    ? AppThemeData.grey400
                                                    : AppThemeData.grey600,
                                                fontFamily:
                                                    AppThemeData.regular,
                                              ),
                                            ),
                                          ),
                                        // Price
                                        Row(
                                          children: [
                                            disPrice == "" || disPrice == "0"
                                                ? Text(
                                                    amountShow(amount: price),
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: AppThemeData
                                                          .primary500,
                                                    ),
                                                  )
                                                : Row(
                                                    children: [
                                                      Text(
                                                        amountShow(
                                                            amount: disPrice),
                                                        style: TextStyle(
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: AppThemeData
                                                              .primary500,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 5),
                                                      Text(
                                                        amountShow(
                                                            amount: price),
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: isDarkMode(
                                                                  context)
                                                              ? AppThemeData
                                                                  .grey400
                                                              : AppThemeData
                                                                  .grey500,
                                                          decoration:
                                                              TextDecoration
                                                                  .lineThrough,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                            if (disPrice != "" &&
                                                disPrice != "0")
                                              Container(
                                                margin: const EdgeInsets.only(
                                                    left: 5),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 5,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppThemeData.success400
                                                      .withOpacity(0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  "${calculateDiscount(price, disPrice)}% OFF",
                                                  style: TextStyle(
                                                    color:
                                                        AppThemeData.success400,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        // Unavailability badge
                                        if (unavailabilityMessage.isNotEmpty)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 6),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 3,
                                                      horizontal: 6),
                                              decoration: BoxDecoration(
                                                color: AppThemeData.danger300
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: AppThemeData.danger300
                                                      .withOpacity(0.5),
                                                  width: 0.5,
                                                ),
                                              ),
                                              child: Text(
                                                unavailabilityMessage.tr(),
                                                style: TextStyle(
                                                  color: AppThemeData.danger300,
                                                  fontFamily:
                                                      AppThemeData.medium,
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
                                    width: 110,
                                    child: Stack(
                                      alignment: Alignment.bottomCenter,
                                      children: [
                                        Padding(
                                          padding: EdgeInsets.only(
                                            bottom: (showAddButton &&
                                                    (isOpen ||
                                                        sectionConstantModel!
                                                                .serviceTypeFlag ==
                                                            "ecommerce-service") &&
                                                    (MyAppState.currentUser !=
                                                            null ||
                                                        sectionConstantModel!
                                                                .serviceTypeFlag ==
                                                            "ecommerce-service"))
                                                ? 18
                                                : 0,
                                          ),
                                          child: Stack(
                                            children: [
                                              Hero(
                                                tag:
                                                    "product_${productModel.id}",
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  child: NetworkImageWidget(
                                                    imageUrl: productModel.photo
                                                        .toString(),
                                                    fit: BoxFit.cover,
                                                    height: 110,
                                                    width: 110,
                                                  ),
                                                ),
                                              ),
                                              // Favorite button
                                              Positioned(
                                                top: 6,
                                                right: 6,
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: isDarkMode(context)
                                                        ? AppThemeData.grey800
                                                            .withOpacity(0.8)
                                                        : Colors.black
                                                            .withOpacity(0.55),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Material(
                                                    color: Colors.transparent,
                                                    child: InkWell(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              50),
                                                      onTap: () async {
                                                        if (favouriteItemList
                                                            .where((p0) =>
                                                                p0.product_id ==
                                                                productModel.id)
                                                            .isNotEmpty) {
                                                          FavouriteItemModel
                                                              favouriteModel =
                                                              FavouriteItemModel(
                                                                  product_id:
                                                                      productModel
                                                                          .id,
                                                                  store_id: widget
                                                                      .vendorModel
                                                                      .id,
                                                                  user_id: FireStoreUtils
                                                                      .getCurrentUid(),
                                                                  section_id:
                                                                      sectionConstantModel!
                                                                          .id);
                                                          favouriteItemList
                                                              .removeWhere(
                                                                  (item) =>
                                                                      item.product_id ==
                                                                      productModel
                                                                          .id);
                                                          await FireStoreUtils
                                                              .removeFavouriteItem(
                                                                  favouriteModel);
                                                        } else {
                                                          FavouriteItemModel
                                                              favouriteModel =
                                                              FavouriteItemModel(
                                                                  product_id:
                                                                      productModel
                                                                          .id,
                                                                  store_id: widget
                                                                      .vendorModel
                                                                      .id,
                                                                  user_id: FireStoreUtils
                                                                      .getCurrentUid(),
                                                                  section_id:
                                                                      sectionConstantModel!
                                                                          .id);
                                                          favouriteItemList.add(
                                                              favouriteModel);
                                                          await FireStoreUtils
                                                              .setFavouriteItem(
                                                                  favouriteModel);
                                                        }
                                                        setState(() {});
                                                      },
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(5),
                                                        child: favouriteItemList
                                                                .where((p0) =>
                                                                    p0.product_id ==
                                                                    productModel
                                                                        .id)
                                                                .isNotEmpty
                                                            ? SvgPicture.asset(
                                                                "assets/icons/ic_like_fill.svg",
                                                                height: 12,
                                                                width: 12,
                                                              )
                                                            : SvgPicture.asset(
                                                                "assets/icons/ic_like.svg",
                                                                height: 12,
                                                                width: 12,
                                                              ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // ADD button or stepper pill
                                        if (showAddButton &&
                                            (isOpen ||
                                                sectionConstantModel!
                                                        .serviceTypeFlag ==
                                                    "ecommerce-service") &&
                                            (MyAppState.currentUser != null ||
                                                sectionConstantModel!
                                                        .serviceTypeFlag ==
                                                    "ecommerce-service"))
                                          AnimatedSwitcher(
                                            duration: const Duration(
                                                milliseconds: 200),
                                            transitionBuilder:
                                                (child, animation) =>
                                                    ScaleTransition(
                                                        scale: animation,
                                                        child: child),
                                            child: cartProduct == null ||
                                                    cartProduct.quantity == 0
                                                ? _AnimatedAddButton(
                                                    key: ValueKey(
                                                        'add_${productModel.id}'),
                                                    hasOptions: hasVariants ||
                                                        hasAddOns,
                                                    onTap: () =>
                                                        _handleAddToCart(
                                                            productModel),
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
                          ));
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
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
          Container(width: 1, height: 18, color: Colors.white.withValues(alpha: 0.3)),
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
          Container(width: 1, height: 18, color: Colors.white.withValues(alpha: 0.3)),
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

    print(
        'Decrementing quantity for product: ${cartProduct.id}, current quantity: ${cartProduct.quantity}');

    // Find the cart product in the list
    final index = cartProducts.indexWhere((p) => p.id == cartProduct.id);
    if (index == -1) {
      print('Cart product not found in list');
      return;
    }

    // Immediate UI update
    setState(() {
      if (cartProducts[index].quantity > 1) {
        cartProducts[index].quantity = cartProducts[index].quantity - 1;
      } else {
        // Remove from local list immediately
        cartProducts.removeAt(index);
      }
    });

    try {
      if (cartProducts.length > index && cartProducts[index].quantity > 1) {
        // Update in database
        await cartDatabase.updateProduct(cartProducts[index]);
        print('Quantity updated successfully in database');
      } else {
        // Remove from database
        await cartDatabase.removeProduct(cartProduct.id);
        print('Product removed successfully from database');
      }
    } catch (e) {
      print('Error in _decrementQuantity: $e');
      // Revert UI changes on error
      setState(() {
        if (cartProducts.length <= index) {
          // Re-add the product if it was removed
          cartProducts.add(cartProduct.copyWith(quantity: 1));
        } else {
          cartProducts[index].quantity = cartProducts[index].quantity + 1;
        }
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
  Future<void> _handleAddToCart(ProductModel productModel) async {
    if (MyAppState.currentUser == null) {
      ShowToastDialog.showToast("Please login to add to cart".tr());
      return;
    }

    // Check if product has variants or add-ons
    bool hasVariants = productModel.itemAttributes != null &&
        productModel.itemAttributes!.attributes!.isNotEmpty;
    bool hasAddOns = productModel.addOnsTitle.isNotEmpty;

    if (hasVariants || hasAddOns) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        useSafeArea: true,
        builder: (BuildContext ctx) {
          return ProductOptionsDialog(
            productModel: productModel,
            onAddToCart: (ProductModel updatedProduct, double totalPrice) async {
              Navigator.of(ctx).pop();
              await _addProductToCart(updatedProduct);
            },
          );
        },
      );
    } else {
      // No variants or add-ons, add directly to cart
      await _addProductToCart(productModel);
    }
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
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24)),
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
                              height: (MediaQuery.of(context).size.width * 0.47).clamp(150.0, 220.0),
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
                                    children: [
                                      Icon(Icons.location_on,
                                          size: 14,
                                          color: AppThemeData.primary500),
                                      const SizedBox(width: 3),
                                      Expanded(
                                        child: Text(
                                          widget.vendorModel.location
                                              .toString(),
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
                                    ],
                                  ),
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
                                    ? AppThemeData.grey800
                                    : const Color(0xFFFFF8E1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: const Color(0xFFFFB300)
                                        .withOpacity(0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SvgPicture.asset(
                                    "assets/icons/ic_star.svg",
                                    colorFilter: const ColorFilter.mode(
                                        Color(0xFFFFB300), BlendMode.srcIn),
                                    height: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    "${calculateReview(reviewCount: widget.vendorModel.reviewsCount.toStringAsFixed(0), reviewSum: widget.vendorModel.reviewsSum.toString())}",
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFFFB300),
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
                                      ? AppThemeData.success400
                                          .withOpacity(0.1)
                                      : AppThemeData.danger300
                                          .withOpacity(0.1),
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
                                              .map((t) =>
                                                  "${t.from} – ${t.to}")
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
    if (productModel.deliveryOption || productModel.dineAwayTakeaway || productModel.dineIn) {
      final isDineawayMode = foodType == 'Dineaway' || foodType == 'Takeaway';
      if (!isDineawayMode && !productModel.deliveryOption) {
        ShowToastDialog.showToast('Delivery order is not available.'.tr());
        return;
      }
      if (isDineawayMode && !productModel.dineAwayTakeaway) {
        ShowToastDialog.showToast('DineAway order is not available.'.tr());
        return;
      }
    }

    try {
      // Check if cart contains products from a different vendor
      if (cartProducts.isNotEmpty) {
        String cartVendorID = cartProducts[0].vendorID;
        if (cartVendorID != widget.vendorModel.id) {
          // Show a dialog to confirm if user wants to clear cart and add new product
          bool? confirmClear = await showDialog<bool>(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text("Replace Cart Items?".tr()),
                content: Text(
                  "Your cart contains items from a different store. Would you like to clear your cart and add this item?"
                      .tr(),
                  style: TextStyle(
                    fontFamily: AppThemeData.regular,
                    fontSize: 14,
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    child: Text(
                      "Cancel".tr(),
                      style: TextStyle(
                        color: isDarkMode(context)
                            ? AppThemeData.grey400
                            : AppThemeData.grey700,
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop(false);
                    },
                  ),
                  TextButton(
                    child: Text(
                      "Clear & Add".tr(),
                      style: TextStyle(
                        color: AppThemeData.primary500,
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop(true);
                    },
                  ),
                ],
              );
            },
          );

          // If user cancels, return without adding to cart
          if (confirmClear == null || !confirmClear) {
            return;
          }

          // User confirmed, so clear cart before adding new product
          await cartDatabase.deleteAllProducts();
          // Also clear local cart products list to update UI immediately
          setState(() {
            cartProducts.clear();
          });
        }
      }

      // Handle product variants if not already set
      if (productModel.itemAttributes != null &&
          productModel.itemAttributes!.attributes!.isNotEmpty &&
          productModel.variant_info == null) {
        List<String> selectedVariants = [];
        for (var element in productModel.itemAttributes!.attributes!) {
          if (element.attributeOptions!.isNotEmpty) {
            selectedVariants.add(element.attributeOptions![0].toString());
          }
        }

        final matchingVariants = productModel.itemAttributes!.variants!
            .where((element) => element.variant_sku == selectedVariants.join('-'));

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
      bool success = await cartDatabase.addProduct(productModel, cartDatabase, true);

      if (success) {
        final sp = await SharedPreferences.getInstance();
        await sp.setString(
          'service_perm_${productModel.id}',
          jsonEncode({
            'delivery': productModel.deliveryOption,
            'dineaway': productModel.takeaway,
            'dineIn': productModel.dineIn,
            'takeaway': productModel.dineAwayTakeaway,
          }),
        );
        await sp.remove('dineaway_perm_${productModel.id}');
      }

      if (!success) {
        // If addProduct returned false, it means there's a different vendor conflict
        ShowToastDialog.showToast(
            "Items from only one restaurant can be added to cart at a time".tr());
        return;
      }

      if (mounted) {
        await _refreshCartData();
      }
    } catch (e) {
      print("Error adding to cart: $e");
      ShowToastDialog.showToast(
          "Failed to add product to cart. Please try again.".tr());
    }
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
    _scale = Tween<double>(begin: 1.0, end: 0.92).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
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
                            offerModel.descriptionOffer.toString(),
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
