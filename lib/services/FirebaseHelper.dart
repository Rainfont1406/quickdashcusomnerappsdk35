import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/AddressModel.dart';
import 'package:emartconsumer/model/AttributesModel.dart';
import 'package:emartconsumer/model/BannerModel.dart';
import 'package:emartconsumer/model/BlockUserModel.dart';
import 'package:emartconsumer/model/BookTableModel.dart';
import 'package:emartconsumer/model/BrandsModel.dart';
import 'package:emartconsumer/model/CabOrderModel.dart';
import 'package:emartconsumer/model/ChatVideoContainer.dart';
import 'package:emartconsumer/model/CodModel.dart';
import 'package:emartconsumer/model/CurrencyModel.dart';
import 'package:emartconsumer/model/DeliveryChargeModel.dart';
import 'package:emartconsumer/model/FavouriteItemModel.dart';
import 'package:emartconsumer/model/FavouriteModel.dart';
import 'package:emartconsumer/model/MercadoPagoSettingsModel.dart';
import 'package:emartconsumer/model/OrderModel.dart';
import 'package:emartconsumer/model/PayFastSettingData.dart';
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/model/Ratingmodel.dart';
import 'package:emartconsumer/model/RentalVehicleType.dart';
import 'package:emartconsumer/model/ReviewAttributeModel.dart';
import 'package:emartconsumer/model/SectionModel.dart';
import 'package:emartconsumer/model/TaxModel.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/model/VehicleType.dart';
import 'package:emartconsumer/model/VendorCategoryModel.dart';
import 'package:emartconsumer/model/LocalOfferModel.dart';
import 'package:emartconsumer/model/LocalOfferCategoryModel.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/model/conversation_model.dart';
import 'package:emartconsumer/model/email_template_model.dart';
import 'package:emartconsumer/model/favorite_ondemand_service_model.dart';
import 'package:emartconsumer/model/gift_cards_model.dart';
import 'package:emartconsumer/model/gift_cards_order_model.dart';
import 'package:emartconsumer/model/inbox_model.dart';
import 'package:emartconsumer/model/notification_model.dart';
import 'package:emartconsumer/model/offer_model.dart';
import 'package:emartconsumer/model/on_boarding_model.dart';
import 'package:emartconsumer/model/PhonePaySettingData.dart';
import 'package:emartconsumer/model/payment_model/mid_trans.dart';
import 'package:emartconsumer/model/payment_model/orange_money.dart';
import 'package:emartconsumer/model/payment_model/xendit.dart';
import 'package:emartconsumer/model/paypalSettingData.dart';
import 'package:emartconsumer/model/paytmSettingData.dart';
import 'package:emartconsumer/model/popular_destination.dart';
import 'package:emartconsumer/model/razorpayKeyModel.dart';
import 'package:emartconsumer/model/referral_model.dart';
import 'package:emartconsumer/model/story_model.dart';
import 'package:emartconsumer/model/stripeKey.dart';
import 'package:emartconsumer/model/stripeSettingData.dart';
import 'package:emartconsumer/model/topupTranHistory.dart';
import 'package:emartconsumer/services/behavior/behavior_event_types.dart';
import 'package:emartconsumer/services/behavior/behavior_tracker.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/recommendation/behavior_summary_snapshot.dart';
import 'package:emartconsumer/services/recommendation/recommendation_config.dart';
import 'package:emartconsumer/services/recommendation/recommendation_engine.dart';
import 'package:emartconsumer/ui/reauthScreen/reauth_user_screen.dart';
import 'package:emartconsumer/userPrefrence.dart';
import 'package:emartconsumer/widget/geoflutterfire/src/geoflutterfire.dart';
import 'package:emartconsumer/widget/geoflutterfire/src/models/point.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../constants.dart';
import '../model/FlutterWaveSettingDataModel.dart';
import '../model/PayStackSettingsModel.dart';
import 'bunny_storage.dart';

// Base URL of the QuickDash admin/API server.
const _kApiBase = 'https://admin.quickdash.co.in';

// Both windows come from ONE Firestore read of dailyProductSales (see
// _fetchRollingSalesWindow) - last7Days is a subset bucketed by date, not a
// second query. Stays local to this file (never imported by
// recommendation_engine.dart, which is deliberately Firebase-free).
class RollingSalesWindow {
  final Map<String, int> last90Days;
  final Map<String, int> last7Days;
  // Distinct-order counters (2026-07-23, Trending/Popular Choice confidence
  // rework) - DIFFERENT from last90Days/last7Days above, which are
  // quantity-sold sums. productOrders* counts how many distinct orders
  // included each product; totalOrders* is the restaurant-wide distinct
  // order count for the same window. Both come from the same 'dailyProductSales'
  // read as everything else here - no second query. Day-buckets written
  // before this field existed simply contribute 0 (see _fetchRollingSalesWindow).
  final Map<String, int> productOrders90;
  final Map<String, int> productOrders7;
  final int totalOrders90;
  final int totalOrders7;
  const RollingSalesWindow({
    required this.last90Days,
    required this.last7Days,
    this.productOrders90 = const {},
    this.productOrders7 = const {},
    this.totalOrders90 = 0,
    this.totalOrders7 = 0,
  });
}

// Transport struct for FireStoreUtils._fetchBusinessContext's live-listener
// cache - RecommendationEngine never sees this type, only the two plain
// maps it carries (passed individually onto
// RestaurantRecommendationContext). Stays local to this file, same as
// RollingSalesWindow above.
class BusinessContextData {
  final Map<String, RestaurantTypeCategoryProfile> typeProfiles;
  final Map<String, Set<String>> cuisineAffinity;
  const BusinessContextData(
      {required this.typeProfiles, required this.cuisineAffinity});
}

// Real-time seat-availability snapshot - see
// FireStoreUtils.streamCurrentSeatAvailability below. Purely derived from
// currently-active Dining orders vs. the vendor's own seatCapacity setting;
// there is no separate vendor-set manual on/off value for this.
class SeatAvailability {
  final int occupiedGuests;
  final int maxCapacity;

  SeatAvailability({
    required this.occupiedGuests,
    required this.maxCapacity,
  });

  bool get isFull => maxCapacity > 0 && occupiedGuests >= maxCapacity;
}

// Thrown by FireStoreUtils.reserveBookingCapacity when a booking's slot (or,
// for a 'flexible' vendor, the whole date) has no remaining guest capacity.
class SlotCapacityExceededException implements Exception {
  final String message;
  SlotCapacityExceededException([this.message = 'This slot is fully booked. Please choose another.']);
  @override
  String toString() => message;
}

class FireStoreUtils {
  static FirebaseMessaging firebaseMessaging = FirebaseMessaging.instance;
  static FirebaseFirestore firestore = FirebaseFirestore.instance;
  static Reference storage = FirebaseStorage.instance.ref();

  static String getCurrentUid() {
    if (MyAppState.currentUser != null) return MyAppState.currentUser!.userID;
    return auth.FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  static DateTime? _cachedServerTime;
  static DateTime? _serverTimeFetchedAt;
  static const Duration _serverTimeTtl = Duration(minutes: 5);

  /// Returns the current time according to Firestore's server clock.
  /// Cached for 5 minutes — adjusted forward by elapsed wall-clock time so
  /// the returned value stays accurate within the TTL window.
  /// Falls back to device time if the write fails (e.g. offline).
  static Future<DateTime> getServerTime() async {
    final now = DateTime.now();
    if (_cachedServerTime != null && _serverTimeFetchedAt != null &&
        now.difference(_serverTimeFetchedAt!) < _serverTimeTtl) {
      return _cachedServerTime!.add(now.difference(_serverTimeFetchedAt!));
    }
    try {
      final ref = firestore.collection('_serverPing').doc('ping');
      await ref.set({'t': FieldValue.serverTimestamp()});
      final snap = await ref.get();
      final ts = snap.data()?['t'] as Timestamp?;
      final serverTime = ts?.toDate() ?? DateTime.now();
      _cachedServerTime = serverTime;
      _serverTimeFetchedAt = DateTime.now();
      return serverTime;
    } catch (_) {
      return DateTime.now();
    }
  }

  static Future<bool> userExistOrNot(String uid) async {
    bool isExist = false;

    await firestore.collection(USERS).doc(uid).get().then(
      (value) {
        if (value.exists) {
          isExist = true;
        } else {
          isExist = false;
        }
      },
    ).catchError((error) {
      log("Failed to check user exist: $error");
      isExist = false;
    });
    return isExist;
  }

  static Future<User?> getUserProfile(String uuid) async {
    User? userModel;
    await firestore.collection(USERS).doc(uuid).get().then((value) {
      if (value.exists) {
        userModel = User.fromJson(value.data()!);
        MyAppState.currentUser = userModel;
      }
    }).catchError((error) {
      log("Failed to update user: $error");
      userModel = null;
    });
    return userModel;
  }

  static Future<List<OnBoardingModel>> getOnBoardingList() async {
    List<OnBoardingModel> onBoardingModel = [];
    await firestore.collection(ONBoarding).where("type",isEqualTo: "customer").get().then((value) {
      for (var element in value.docs) {
        OnBoardingModel documentModel = OnBoardingModel.fromJson(element.data());
        onBoardingModel.add(documentModel);
      }
    }).catchError((error) {
      log(error.toString());
    });
    return onBoardingModel;
  }


  static Future<List<FavouriteItemModel>> getFavouriteItem() async {
    List<FavouriteItemModel> favouriteList = [];
    await firestore.collection(FavouriteItem).where('user_id', isEqualTo: getCurrentUid()).get().then(
      (value) {
        for (var element in value.docs) {
          FavouriteItemModel favouriteModel = FavouriteItemModel.fromJson(element.data());
          favouriteList.add(favouriteModel);
        }
      },
    );
    return favouriteList;
  }

  static Future<bool?> checkReferralCodeValidOrNot(String referralCode) async {
    bool? isExit;
    try {
      await firestore.collection(REFERRAL).where("referralCode", isEqualTo: referralCode).get().then((value) {
        if (value.size > 0) {
          isExit = true;
        } else {
          isExit = false;
        }
      });
    } catch (e, s) {
      print('FireStoreUtils.firebaseCreateNewUser $e $s');
      return false;
    }
    return isExit;
  }

  static Future<ReferralModel?> getReferralUserByCode(String referralCode) async {
    ReferralModel? referralModel;
    try {
      await firestore.collection(REFERRAL).where("referralCode", isEqualTo: referralCode).get().then((value) {
        if (value.docs.isNotEmpty) {
          referralModel = ReferralModel.fromJson(value.docs.first.data());
        }
      });
    } catch (e, s) {
      print('FireStoreUtils.firebaseCreateNewUser $e $s');
      return null;
    }
    return referralModel;
  }

  static Future<ReferralModel?> getReferralUserBy() async {
    ReferralModel? referralModel;
    try {
      await firestore.collection(REFERRAL).doc(MyAppState.currentUser!.userID).get().then((value) {
        if (value.exists) referralModel = ReferralModel.fromJson(value.data()!);
      });
    } catch (e, s) {
      print('FireStoreUtils.firebaseCreateNewUser $e $s');
      return null;
    }
    return referralModel;
  }

  List<BlockUserModel> blockedList = [];

  static List<StoryModel>? _storyCache;
  static DateTime? _storyCachedAt;
  static const Duration _storyCacheTtl = Duration(minutes: 10);

  static void clearStoryCache() {
    _storyCache = null;
    _storyCachedAt = null;
  }

  Future<List<StoryModel>> getStory() async {
    final now = DateTime.now();
    if (_storyCache != null && _storyCachedAt != null &&
        now.difference(_storyCachedAt!) < _storyCacheTtl) {
      return _storyCache!;
    }
    List<StoryModel> story = [];
    // Must filter approved==true server-side, not just client-side in
    // HomeScreen._filterStories() - the Firestore rule for story/{id} only
    // allows reads where resource.data.approved == true (or owner/admin).
    // A query without this filter can match unapproved docs from OTHER
    // vendors in the same section, which Firestore can't prove are
    // readable, so it denies the ENTIRE query with permission-denied -
    // silently hiding every story in the section, approved or not.
    QuerySnapshot<Map<String, dynamic>> storyQuery = await firestore.collection(STORY).where('sectionID', isEqualTo: sectionConstantModel!.id).where('approved', isEqualTo: true).get();
    await Future.forEach(storyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        story.add(StoryModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getAllProducts Parse error $e');
      }
    });
    _storyCache = story;
    _storyCachedAt = now;
    return story;
  }

  /// Asks the server which of [vendorIds] fall within the active section's
  /// nearByRadius of (lat, lng). Story-visibility radius filtering was
  /// asked to be computed server-side rather than via a client-side
  /// distance check, so this calls the admin panel instead of doing the
  /// math here. Returns null (meaning "unknown, don't filter yet") on any
  /// network/parse failure so a transient API hiccup never hides stories
  /// outright - callers should keep their previous result until this
  /// succeeds.
  Future<Set<String>?> getNearbyVendorIds({
    required double lat,
    required double lng,
    required List<String> vendorIds,
  }) async {
    if (vendorIds.isEmpty || sectionConstantModel?.id == null) return null;

    try {
      final idToken = await auth.FirebaseAuth.instance.currentUser?.getIdToken();
      if (idToken == null) return null;

      final resp = await http
          .post(
            Uri.parse('$_kApiBase/api/vendors/nearby'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'lat': lat,
              'lng': lng,
              'section_id': sectionConstantModel!.id,
              'vendor_ids': vendorIds,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) {
        print('getNearbyVendorIds failed (${resp.statusCode}): ${resp.body}');
        return null;
      }

      final decoded = jsonDecode(resp.body);
      final ids = (decoded['vendor_ids'] as List?)?.cast<String>();
      return ids == null ? null : Set<String>.from(ids);
    } catch (e) {
      print('getNearbyVendorIds skipped: $e');
      return null;
    }
  }

  static Future<List<AttributesModel>> getAttributes() async {
    List<AttributesModel> attributesList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(VENDOR_ATTRIBUTES).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        attributesList.add(AttributesModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return attributesList;
  }

  static Future<List<BrandsModel>> getBrands() async {
    List<BrandsModel> brandList = [];
    QuerySnapshot<Map<String, dynamic>> brandQuery = await firestore.collection(BRANDS).where('is_publish', isEqualTo: true).get();
    await Future.forEach(brandQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        brandList.add(BrandsModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return brandList;
  }

  static Future addRestaurantInbox(InboxModel inboxModel) async {
    return await firestore.collection("chat_store").doc(inboxModel.orderId).set(inboxModel.toJson()).then((document) {
      return inboxModel;
    });
  }

  static Future addRestaurantChat(ConversationModel conversationModel) async {
    return await firestore.collection("chat_store").doc(conversationModel.orderId).collection("thread").doc(conversationModel.id).set(conversationModel.toJson()).then((document) {
      return conversationModel;
    });
  }

  static Future addDriverInbox(InboxModel inboxModel) async {
    return await firestore.collection("chat_driver").doc(inboxModel.orderId).set(inboxModel.toJson()).then((document) {
      return inboxModel;
    });
  }

  static Future addDriverChat(ConversationModel conversationModel) async {
    return await firestore.collection("chat_driver").doc(conversationModel.orderId).collection("thread").doc(conversationModel.id).set(conversationModel.toJson()).then((document) {
      return conversationModel;
    });
  }

  Future<List<RatingModel>> getReviewList(String productId) async {
    List<RatingModel> reviewList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(Order_Rating).where('productId', isEqualTo: productId).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        reviewList.add(RatingModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return reviewList;
  }

  static Future<List<ProductModel>> getProductListByCategoryId(String categoryId) async {
    List<ProductModel> productList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(PRODUCTS).where('categoryID', isEqualTo: categoryId).where('publish', isEqualTo: true).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        productList.add(ProductModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return productList;
  }

  static Future<List<ProductModel>> getStoreProduct(String storeId) async {
    List<ProductModel> productList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(PRODUCTS).where('vendorID', isEqualTo: storeId).where('publish', isEqualTo: true).limit(6).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        productList.add(ProductModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return productList;
  }

  static Future<List<ProductModel>> getProductListByBrandId(String brandId) async {
    List<ProductModel> productList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(PRODUCTS).where('brandID', isEqualTo: brandId).where('publish', isEqualTo: true).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        productList.add(ProductModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return productList;
  }

  static Future<List<ReviewAttributeModel>> getAllReviewAttributes() async {
    List<ReviewAttributeModel> reviewAttributesList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(REVIEW_ATTRIBUTES).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        reviewAttributesList.add(ReviewAttributeModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return reviewAttributesList;
  }

  late StreamController<OrderModel> ordersByIdStreamController;
  late StreamSubscription ordersByIdStreamSub;

  Stream<OrderModel?> getOrderByID(String inProgressOrderID) async* {
    ordersByIdStreamController = StreamController();
    ordersByIdStreamSub = firestore.collection(ORDERS).doc(inProgressOrderID).snapshots().listen((onData) async {
      if (onData.data() != null) {
        OrderModel? orderModel = OrderModel.fromJson(onData.data()!);
        ordersByIdStreamController.sink.add(orderModel);
      }
    });
    yield* ordersByIdStreamController.stream;
  }

  // Customer declines a pending vendor-initiated Bill Pay request.
  Future<void> declineBillPayRequest(String orderId) async {
    await firestore.collection(ORDERS).doc(orderId).update({
      'status': BILLPAY_STATUS_DECLINED,
      'billPayRespondedAt': Timestamp.now(),
    });
  }

  // Opportunistic client-side expiry: only flips status if still pending,
  // so it never clobbers a decline/accept that raced it.
  Future<void> expireBillPayRequestIfPending(String orderId) async {
    final ref = firestore.collection(ORDERS).doc(orderId);
    await firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.data()?['status'] == BILLPAY_STATUS_PENDING_APPROVAL) {
        tx.update(ref, {'status': BILLPAY_STATUS_EXPIRED});
      }
    });
  }

  static Future<VendorModel?> getVendor(String vid) async {
    DocumentSnapshot<Map<String, dynamic>> userDocument = await firestore.collection(VENDORS).doc(vid).get();
    if (userDocument.data() != null && userDocument.exists) {
      return VendorModel.fromJson(userDocument.data()!);
    } else {
      print("nulllll");
      return null;
    }
  }


  // vendorId -> (in-flight/resolved fetch, when it was started). Sales data
  // is a slow-changing rolling aggregate, so a short cache avoids
  // re-querying the dailyProductSales subcollection for the same vendor on
  // every live vendor-list update (cards rebuild often; sales data doesn't
  // change minute to minute). Cleared naturally on app restart.
  static final Map<String, (Future<RollingSalesWindow>, DateTime)>
      _rollingSalesCache = {};
  static const Duration _rollingSalesCacheTtl = Duration(minutes: 10);

  /// Used by manual pull-to-refresh (restaurant page) alongside
  /// clearVendorProductsCache/clearBehaviorSummaryCache, so a refresh can't
  /// still show sales data up to 10 minutes stale (2026-07-17 fix - this
  /// cache was the one of the three restaurant-page caches manual refresh
  /// didn't already clear).
  static void clearRollingSalesCache(String vendorId) {
    _rollingSalesCache.remove(vendorId);
  }

  static Future<RollingSalesWindow> _getRollingSalesWindow(String vendorId) {
    final cached = _rollingSalesCache[vendorId];
    if (cached != null &&
        DateTime.now().difference(cached.$2) < _rollingSalesCacheTtl) {
      return cached.$1;
    }
    final future = _fetchRollingSalesWindow(vendorId);
    _rollingSalesCache[vendorId] = (future, DateTime.now());
    return future;
  }

  /// Sums a vendor's per-product delivery sales over the last 90 daily
  /// buckets (3 months, widened 2026-07-20 from 30 days - written by the
  /// vendor app at order-completion time — see FireStoreUtils.updateOrder
  /// there). Returns {productId: unitsSold}, empty if the vendor has no
  /// sales data yet. Thin wrapper kept for any caller that only needs the
  /// 90-day total (e.g. getCarouselProducts) - RecommendationEngine callers
  /// should use loadRecommendationContext, which populates both windows
  /// from the one shared fetch.
  static Future<Map<String, int>> getRolling90DaySales(String vendorId) async {
    return (await _getRollingSalesWindow(vendorId)).last90Days;
  }

  static DateTime? _parseBucketDate(String docId) {
    // docId format 'yyyy-MM-dd', see vendorApp's _dateBucketKey.
    final parts = docId.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  /// Both the 90-day total (3 months, widened 2026-07-20 from 30 days) and
  /// the 7-day total come from this ONE Firestore read - the subcollection
  /// is small (~90 daily docs, pruned vendor-side), so bucketing by date
  /// client-side is far cheaper than a second query.
  static Future<RollingSalesWindow> _fetchRollingSalesWindow(
      String vendorId) async {
    final Map<String, int> totals90 = {};
    final Map<String, int> totals7 = {};
    final Map<String, int> orderTotals90 = {};
    final Map<String, int> orderTotals7 = {};
    var totalOrders90 = 0;
    var totalOrders7 = 0;
    try {
      final snapshot = await firestore
          .collection(VENDORS)
          .doc(vendorId)
          .collection('dailyProductSales')
          .get();
      final cutoff7 = DateTime.now().subtract(const Duration(days: 7));
      final cutoff7Date = DateTime(cutoff7.year, cutoff7.month, cutoff7.day);
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final products = data['products'] as Map<String, dynamic>?;
        if (products == null) continue;
        final bucketDate = _parseBucketDate(doc.id);
        final within7 = bucketDate != null && !bucketDate.isBefore(cutoff7Date);
        products.forEach((productId, count) {
          final n = (count as num?)?.toInt() ?? 0;
          totals90[productId] = (totals90[productId] ?? 0) + n;
          if (within7) totals7[productId] = (totals7[productId] ?? 0) + n;
        });

        // Distinct-order counters - absent on buckets written before
        // 2026-07-23, treated as 0 (no products/no orders that day for
        // this field), never an error.
        final productOrders = data['productOrders'] as Map<String, dynamic>?;
        if (productOrders != null) {
          productOrders.forEach((productId, count) {
            final n = (count as num?)?.toInt() ?? 0;
            orderTotals90[productId] = (orderTotals90[productId] ?? 0) + n;
            if (within7) orderTotals7[productId] = (orderTotals7[productId] ?? 0) + n;
          });
        }
        final dayTotalOrders = (data['totalOrders'] as num?)?.toInt() ?? 0;
        totalOrders90 += dayTotalOrders;
        if (within7) totalOrders7 += dayTotalOrders;
      }
    } catch (_) {}
    return RollingSalesWindow(
      last90Days: totals90,
      last7Days: totals7,
      productOrders90: orderTotals90,
      productOrders7: orderTotals7,
      totalOrders90: totalOrders90,
      totalOrders7: totalOrders7,
    );
  }

  // ── Phase 2 recommendation data orchestration (2026-07-17) ────────────
  // uid -> (in-flight/resolved fetch, when it was started). Same TTL-cache
  // shape as _rollingSalesCache above, but keyed per-USER rather than
  // per-vendor: the merged 3-month behavior_summary is identical no matter
  // which restaurant page requests it, so one fetch per app session covers
  // every restaurant the user visits, not one per vendor visited.
  static final Map<String, (Future<BehaviorSummarySnapshot>, DateTime)>
      _behaviorSummaryCache = {};
  static const Duration _behaviorSummaryCacheTtl = Duration(minutes: 10);

  /// Used by manual pull-to-refresh (restaurant page) alongside the
  /// existing clearVendorProductsCache, so a fresh session's behavior can't
  /// be masked by a still-live 10-minute-old personalization snapshot.
  static void clearBehaviorSummaryCache(String uid) {
    _behaviorSummaryCache.remove(uid);
  }

  /// Reads the signed-in user's current + previous 2 months' behavior_summary
  /// docs (matching BehaviorTracker's own 3-month retention) and merges them
  /// into one snapshot. Never throws - any read failure yields an empty
  /// snapshot, same cold-start behavior as a genuinely new user.
  static Future<BehaviorSummarySnapshot> _fetchBehaviorSummary(String uid) {
    final cached = _behaviorSummaryCache[uid];
    if (cached != null &&
        DateTime.now().difference(cached.$2) < _behaviorSummaryCacheTtl) {
      return cached.$1;
    }
    final future = _loadBehaviorSummary(uid);
    _behaviorSummaryCache[uid] = (future, DateTime.now());
    return future;
  }

  static Future<BehaviorSummarySnapshot> _loadBehaviorSummary(String uid) async {
    try {
      final now = DateTime.now();
      // Retention extended 3 -> 12 months (2026-07-18, kBehaviorSummaryRetentionMonths)
      // for Cross-Session Search Interest - a deliberate, confirmed 4x
      // increase in document reads for this fetch (12 months instead of 3),
      // cached 10 minutes per user session via _behaviorSummaryCache below.
      // Must stay in sync with BehaviorTracker._pruneOldSummariesIfNeeded's
      // own retention window.
      final yearMonths = List.generate(kBehaviorSummaryRetentionMonths, (i) {
        final d = DateTime(now.year, now.month - i, 1);
        return '${d.year}-${d.month.toString().padLeft(2, '0')}';
      });
      // Single whereIn query instead of 12 individual .doc(id).get() calls -
      // same document-read cost (Firestore bills per document either way),
      // but one round trip instead of twelve competing for connection
      // bandwidth. whereIn supports up to 30 values; comfortably covers
      // kBehaviorSummaryRetentionMonths (12). A query only ever returns
      // existing docs, so no separate exists-check is needed here (unlike
      // the old per-doc-get version, where a missing month still produced a
      // non-existent snapshot that had to be filtered out).
      final snapshot = await firestore
          .collection(USERS)
          .doc(uid)
          .collection('behavior_summary')
          .where(FieldPath.documentId, whereIn: yearMonths)
          .get();
      final data = snapshot.docs.map((d) => d.data()).toList();
      return BehaviorSummarySnapshot.merge(data);
    } catch (_) {
      return BehaviorSummarySnapshot.empty();
    }
  }

  // ── Business Context (2026-07-19, admin-managed - revision 5) ──────────
  // Restaurant Type/Cuisine -> preferred Product Category IDs, stored in
  // Firestore (`business_context_type_profiles`/
  // `business_context_cuisine_affinity`, both admin-managed - see the
  // Admin Panel's Business Types/Cuisines edit pages) instead of hardcoded
  // in the app. GLOBAL, non-sensitive master data - contains no user-
  // specific or sensitive fields (just category IDs), so it's public-read
  // in firestore.rules exactly like every other reference list there
  // (sections/cuisines/business_types/vendor_categories), and every app
  // user (signed in or not) gets the same Business Context signal.
  //
  // Revision 5: replaced the fixed 30-minute TTL with a live Firestore
  // listener, the same "keep a cached config value fresh, pushed
  // automatically the instant it changes" pattern this file already uses
  // elsewhere (e.g. the Stripe settings .snapshots().listen() a few
  // hundred lines up) - there's no existing generic "master config
  // version" doc anywhere in this app to integrate with instead, so this
  // reuses the codebase's own established idiom for the same class of
  // problem rather than inventing a bespoke version-counter scheme. Two
  // long-lived subscriptions (started lazily on first
  // loadRecommendationContext call, held for the rest of the app session -
  // no per-screen disposal needed, same as this app's other global-config
  // subscriptions) keep _businessTypeProfiles/_cuisineCategoryAffinity
  // live in memory. The very first call pays for one real read per
  // collection (unavoidable); every call after that - for the rest of the
  // session - is a synchronous in-memory read. An admin's save in the
  // Admin Panel updates these in-memory maps in every open app instance
  // via the same push round-trip (not "eventually, within a TTL window"),
  // so the very next loadRecommendationContext call - this restaurant
  // reopened, a pull-to-refresh, or the next restaurant visited - always
  // sees fresh data. An already-rendered restaurant page does NOT
  // automatically re-render on its own when this happens (see
  // _ensureBusinessContextListeners' own doc comment) - deliberately kept
  // simple, since Business Context changes are rare.
  static Map<String, RestaurantTypeCategoryProfile> _businessTypeProfiles = {};
  static Map<String, Set<String>> _cuisineCategoryAffinity = {};
  static Completer<void>? _businessContextReady;

  static Future<BusinessContextData> _fetchBusinessContext() {
    _ensureBusinessContextListeners();
    return _businessContextReady!.future.then((_) => BusinessContextData(
        typeProfiles: _businessTypeProfiles,
        cuisineAffinity: _cuisineCategoryAffinity));
  }

  /// Starts both listeners exactly once per app session. [_businessContextReady]
  /// completes once BOTH collections have delivered their first snapshot (or
  /// failed - never throws, a failed listener just leaves that half of the
  /// data empty, the same "no evidence yet" no-op as any other gap in this
  /// engine) - every call to _fetchBusinessContext before that point awaits
  /// the same Completer rather than firing duplicate reads.
  ///
  /// Deliberately does NOT notify already-open restaurant pages when a
  /// later snapshot changes this data (an earlier revision added a
  /// broadcast stream + a subscription in newVendorProductsScreen for
  /// exactly that, since removed) - Business Context changes are rare
  /// admin actions, and the in-memory maps below are always current for
  /// the NEXT loadRecommendationContext call regardless (this restaurant's
  /// re-open, a pull-to-refresh, or the next restaurant visited all pick up
  /// the new data immediately, since the listener itself never stops
  /// updating). Simpler: no extra stream, no per-screen subscription
  /// lifecycle, no extra rebuild path to maintain for a signal that changes
  /// on the order of "admin edits a business type," not per-session.
  static void _ensureBusinessContextListeners() {
    if (_businessContextReady != null) return;
    _businessContextReady = Completer<void>();
    var typeReady = false, cuisineReady = false;
    void maybeComplete() {
      if (typeReady && cuisineReady && !_businessContextReady!.isCompleted) {
        _businessContextReady!.complete();
      }
    }

    // Fire-and-forget - both listeners are meant to live for the entire app
    // session with no disposal, same as this app's other global-config
    // subscriptions, so there's no caller that ever needs the
    // StreamSubscription object back.
    firestore
        .collection(BUSINESS_CONTEXT_TYPE_PROFILES)
        .snapshots()
        .listen((snap) {
      final map = <String, RestaurantTypeCategoryProfile>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        map[doc.id] = RestaurantTypeCategoryProfile(
          primaryCategoryIds:
              Set<String>.from(data['primaryCategoryIds'] ?? const []),
          secondaryCategoryIds:
              Set<String>.from(data['secondaryCategoryIds'] ?? const []),
          lowPriorityCategoryIds:
              Set<String>.from(data['lowPriorityCategoryIds'] ?? const []),
        );
      }
      _businessTypeProfiles = map;
      typeReady = true;
      maybeComplete();
    }, onError: (_) {
      typeReady = true;
      maybeComplete();
    });

    firestore
        .collection(BUSINESS_CONTEXT_CUISINE_AFFINITY)
        .snapshots()
        .listen((snap) {
      final map = <String, Set<String>>{};
      for (final doc in snap.docs) {
        map[doc.id] = Set<String>.from(doc.data()['categoryIds'] ?? const []);
      }
      _cuisineCategoryAffinity = map;
      cuisineReady = true;
      maybeComplete();
    }, onError: (_) {
      cuisineReady = true;
      maybeComplete();
    });
  }

  // Recommendation Configuration (2026-07-22) - unlike Business Context
  // above, this is a plain ONE-TIME read, not a live listener: the brief
  // explicitly wants "load once at startup, cache in memory, refresh only
  // on app restart" - a live snapshot listener would silently apply an
  // admin's mid-session edit to everyone's already-open app, which is
  // exactly what was asked NOT to happen. A Completer still guards against
  // duplicate concurrent calls, same technique as _ensureBusinessContextListeners,
  // just for a single get() instead of two subscriptions.
  static Completer<void>? _recommendationConfigLoadStarted;

  /// Fetches recommendation_configuration/default once and caches it on
  /// RecommendationConfig.current. Safe to call multiple times - every call
  /// after the first awaits the same in-flight fetch. Never throws: a
  /// missing document, offline device, or permission error simply leaves
  /// RecommendationConfig.current at its already-production-identical
  /// default values (see RecommendationConfig.defaults()).
  static Future<void> loadRecommendationConfig() {
    if (_recommendationConfigLoadStarted != null) {
      return _recommendationConfigLoadStarted!.future;
    }
    final completer = Completer<void>();
    _recommendationConfigLoadStarted = completer;
    firestore
        .collection('recommendation_configuration')
        .doc('default')
        .get()
        .then((snap) {
      if (snap.exists) {
        RecommendationConfig.current =
            RecommendationConfig.fromJson(snap.data() ?? const {});
      }
    }).catchError((_) {
      // Degrades to defaults - already identical to pre-feature behavior.
    }).whenComplete(() {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  /// Assembles everything RecommendationEngine needs for one restaurant
  /// page: the user's merged behavior summary (empty for signed-out users -
  /// no read attempted), the vendor's rolling 90-day (3-month) sales
  /// (existing, already TTL-cached), the in-memory cross-sell frequency tally (pure,
  /// computed from [allProductList], zero extra reads), and the admin-
  /// managed Business Context profiles (globally live-cached via a
  /// Firestore listener, see above).
  /// Callers should compute this ONCE per restaurant-page visit and reuse
  /// the result across every section/reorder/pairs-well-with call -
  /// nothing in RecommendationEngine re-fetches per section.
  static Future<RestaurantRecommendationContext> loadRecommendationContext(
      VendorModel vendor, List<ProductModel> allProductList) async {
    final uid = getCurrentUid();
    final summaryFuture = uid.isEmpty
        ? Future.value(BehaviorSummarySnapshot.empty())
        : _fetchBehaviorSummary(uid);
    final salesWindowFuture = _getRollingSalesWindow(vendor.id);
    final businessContextFuture = _fetchBusinessContext();
    final results = await Future.wait(
        [summaryFuture, salesWindowFuture, businessContextFuture]);
    final salesWindow = results[1] as RollingSalesWindow;
    final businessContext = results[2] as BusinessContextData;
    return RestaurantRecommendationContext(
      vendor: vendor,
      allProducts: allProductList,
      behaviorSummary: results[0] as BehaviorSummarySnapshot,
      rolling90DaySales: salesWindow.last90Days,
      rolling7DaySales: salesWindow.last7Days,
      productOrders90: salesWindow.productOrders90,
      productOrders7: salesWindow.productOrders7,
      totalOrders90: salesWindow.totalOrders90,
      totalOrders7: salesWindow.totalOrders7,
      crossSellFrequency: RecommendationEngine.computeCrossSellFrequency(allProductList),
      businessTypeProfiles: businessContext.typeProfiles,
      cuisineCategoryAffinity: businessContext.cuisineAffinity,
    );
  }

  /// Same merged/cached behavior summary as [loadRecommendationContext]
  /// uses internally, exposed directly for callers that only need the
  /// summary itself - e.g. SearchScreen's restaurant-ranking personalization
  /// term, which has no single vendor/product-list context to build a full
  /// RestaurantRecommendationContext around. Empty for signed-out users, no
  /// read attempted.
  static Future<BehaviorSummarySnapshot> getBehaviorSummary() {
    final uid = getCurrentUid();
    if (uid.isEmpty) return Future.value(BehaviorSummarySnapshot.empty());
    return _fetchBehaviorSummary(uid);
  }

  /// Up to [max] products to show in a vendor's delivery-card carousel.
  /// Priority: rolling-90-day (3-month) sales ranking → best-discounted products →
  /// lowest-priced products. [vendorProducts] should already be filtered to
  /// this vendor's published, delivery-enabled products.
  static Future<List<ProductModel>> getCarouselProducts(
      String vendorId, List<ProductModel> vendorProducts,
      {int max = 5}) async {
    if (vendorProducts.isEmpty) return [];

    final salesCounts = await getRolling90DaySales(vendorId);
    if (salesCounts.isNotEmpty) {
      final ranked = vendorProducts
          .where((p) => (salesCounts[p.id] ?? 0) > 0)
          .toList()
        ..sort((a, b) =>
            (salesCounts[b.id] ?? 0).compareTo(salesCounts[a.id] ?? 0));
      if (ranked.isNotEmpty) return ranked.take(max).toList();
    }

    double discountPercent(ProductModel p) {
      try {
        final double orig = double.parse(p.price);
        final double disc = double.parse(p.disPrice ?? '0');
        if (orig > 0 && disc > 0 && orig > disc) {
          return ((orig - disc) / orig) * 100;
        }
      } catch (_) {}
      return 0;
    }

    final discounted =
        vendorProducts.where((p) => discountPercent(p) > 0).toList()
          ..sort((a, b) => discountPercent(b).compareTo(discountPercent(a)));
    if (discounted.isNotEmpty) return discounted.take(max).toList();

    final byPrice = List<ProductModel>.from(vendorProducts)
      ..sort((a, b) =>
          (double.tryParse(a.price) ?? 0).compareTo(double.tryParse(b.price) ?? 0));
    return byPrice.take(max).toList();
  }

  final geo = Geoflutterfire();
  late StreamController<List<User>> nearestDriverStreamController;

  Future setSos(String orderId, UserLocation userLocation) async {
    DocumentReference documentReference = firestore.collection(SOS).doc();
    Map<String, dynamic> sosMap = {'id': documentReference.id, 'orderId': orderId, 'status': "Initiated", 'latLong': userLocation.toJson()};
    await documentReference.set(sosMap);
  }

  Future<bool> getSOS(String orderId) async {
    bool isAdded = false;
    QuerySnapshot documentReference = await firestore.collection(SOS).where('orderId', isEqualTo: orderId).get();
    documentReference.docs.forEach((element) {
      if (element['orderId'] == orderId) {
        isAdded = true;
      }
    });

    return isAdded;
  }

  Future setRideComplain(
      {required String orderId,
      required String title,
      required String description,
      required String driverID,
      required String driverName,
      required String customerID,
      required String customerName}) async {
    DocumentReference documentReference = firestore.collection(complaints).doc();
    Map<String, dynamic> sosMap = {
      'id': documentReference.id,
      'createdAt': Timestamp.now(),
      'description': description,
      'driverId': driverID,
      'driverName': driverName,
      'orderId': orderId,
      'customerName': customerName,
      'customerId': customerID,
      'status': "Initiated",
      'title': title,
    };

    await documentReference.set(sosMap);
  }

  Future<bool> getRideComplain(String orderId) async {
    bool isAdded = false;
    QuerySnapshot documentReference = await firestore.collection(complaints).where('orderId', isEqualTo: orderId).get();
    documentReference.docs.forEach((element) {
      if (element['orderId'] == orderId) {
        isAdded = true;
      }
    });

    return isAdded;
  }

  Future<QueryDocumentSnapshot?> getRideComplainData(String orderId) async {
    QueryDocumentSnapshot? isAdded;
    QuerySnapshot documentReference = await firestore.collection(complaints).where('orderId', isEqualTo: orderId).get();
    documentReference.docs.forEach((element) {
      if (element['orderId'] == orderId) {
        isAdded = element;
      }
    });
    return isAdded;
  }

  late StreamController<User> driverStreamController;
  late StreamSubscription driverStreamSub;

  Stream<User> getDriver(String userId) async* {
    driverStreamController = StreamController();
    driverStreamSub = firestore.collection(USERS).doc(userId).snapshots().listen((onData) async {
      if (onData.data() != null) {
        User? user = User.fromJson(onData.data()!);
        driverStreamController.sink.add(user);
      }
    });
    yield* driverStreamController.stream;
  }

  static Future<List<VehicleType>> getVehicleType() async {
    List<VehicleType> vehicleType = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery =
        await firestore.collection(VEHICLETYPE).where('sectionId', isEqualTo: sectionConstantModel!.id).where("isActive", isEqualTo: true).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        vehicleType.add(VehicleType.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return vehicleType;
  }

  static Future<List<PopularDestination>> getPopularDestination() async {
    List<PopularDestination> popularDestination = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(POPULAR_DESTINATION).where('is_publish', isEqualTo: true).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        popularDestination.add(PopularDestination.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return popularDestination;
  }

  static Future<List<RentalVehicleType>> getRentalVehicleType() async {
    List<RentalVehicleType> vehicleType = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(RENTALVEHICLETYPE).where("isActive", isEqualTo: true).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        vehicleType.add(RentalVehicleType.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return vehicleType;
  }

  static Future<User?> getCurrentUser(String uid) async {
    DocumentSnapshot<Map<String, dynamic>> userDocument = await firestore.collection(USERS).doc(uid).get();
    if (userDocument.data() != null && userDocument.exists) {
      return User.fromJson(userDocument.data()!);
    } else {
      return null;
    }
  }

  Future<User?> getNearestDriver(LatLng? sourceLateLong) async {
    User? user;
    var collectionReference = firestore.collection(USERS).where("role", isEqualTo: "driver");

    GeoFirePoint center = geo.point(latitude: sourceLateLong!.latitude, longitude: sourceLateLong.longitude);

    String field = 'g';

    Stream<List<DocumentSnapshot>> stream = geo
        .collection(collectionRef: collectionReference)
        .within(center: center, radius: double.parse(sectionConstantModel!.nearByRadius.toString()), field: field, strictMode: true);

    stream.listen((List<DocumentSnapshot> documentList) {
      for (var document in documentList) {
        final data = document.data() as Map<String, dynamic>;
        user = User.fromJson(data);
      }
    });

    return user;
  }

  static Future<NotificationModel?> getNotificationContent(String type) async {
    NotificationModel? notificationModel;
    await firestore.collection(dynamicNotification).where('type', isEqualTo: type).get().then((value) {
      if (value.docs.isNotEmpty) {

        notificationModel = NotificationModel.fromJson(value.docs.first.data());
      } else {
        notificationModel = NotificationModel(id: "", message: "Notification setup is pending".tr(), subject: "setup notification".tr(), type: "");
      }
    });
    return notificationModel;
  }

  Future<TaxModel?> getTaxSetting() async {
    DocumentSnapshot<Map<String, dynamic>> taxQuery = await firestore.collection(Setting).doc('taxSetting').get();
    if (taxQuery.data() != null) {
      return TaxModel.fromJson(taxQuery.data()!);
    }
    return null;
  }

  Future<List<TaxModel>?> getTaxList(String? sectionId) async {
    List<TaxModel> taxList = [];
    await firestore.collection(tax).where('sectionId', isEqualTo: sectionId).where('enable', isEqualTo: true).get().then((value) {
      for (var element in value.docs) {
        TaxModel taxModel = TaxModel.fromJson(element.data());
        taxList.add(taxModel);
      }
    }).catchError((error) {
      log(error.toString());
    });
    return taxList;
  }

  Future<String> uploadProductImage(File image, String progress) async {
    return uploadImageToBunny(image, 'store/products');
  }

  static Future<ProductModel?> getProductById(String productId) async {
    ProductModel? vendorCategoryModel;
    try {
      await firestore.collection(PRODUCTS).doc(productId).get().then((value) {
        if (value.exists) {
          vendorCategoryModel = ProductModel.fromJson(value.data()!);
        }
      });
    } catch (e, s) {
      log('FireStoreUtils.firebaseCreateNewUser $e $s');
      return null;
    }
    return vendorCategoryModel;
  }

  static Future<User?> updateCurrentUser(User user) async {
    // wallet_amount is server-authoritative now (Cloud Functions / Laravel
    // Admin SDK only) — firestore.rules rejects any customer-owned update
    // that touches it at all, even to write back the same value it already
    // has. A plain full-document .set() would include whatever value the
    // in-memory User object happens to be holding (which drifts from the
    // real server balance constantly — right after any order/payment), so
    // every ordinary profile edit would fail the moment that drift exists.
    // Strip the field entirely and merge instead of replacing outright, so
    // this write never touches wallet_amount and never deletes any field
    // this model doesn't know about.
    final json = user.toJson();
    json.remove('wallet_amount');
    return await firestore.collection(USERS).doc(user.userID).set(json, SetOptions(merge: true)).then((document) {
      MyAppState.currentUser = user;
      return user;
    });
  }

  static Future<void> updateCurrentUserAddress(AddressModel userAddress) async {
    //UserPreference.setUserId(userID: user.userID);
    return await firestore.collection(USERS).doc(MyAppState.currentUser!.userID).update(
      {"shippingAddress": userAddress.toJson()},
    ).then((document) {
      print("AAADDDDDD");
    });
  }

  static Future<ProductModel?> updateProduct(ProductModel prodduct) async {
    return await firestore.collection(PRODUCTS).doc(prodduct.id).set(prodduct.toJson()).then((document) {
      return prodduct;
    });
  }

  // Atomic replacement for the old get-then-.set()-the-whole-document stock
  // decrement duplicated in CheckoutScreen._placeOrder and
  // PaymentScreen._buildAndPlaceOrder. That pattern read the product,
  // decremented quantity/variant_quantity in memory, then wrote the whole
  // document back with a plain .set() - a read-modify-write race: two
  // concurrent orders on the same product could each read the same stale
  // quantity, both decrement from it, and the second write would silently
  // erase the first order's decrement (and overwrite whatever else - price,
  // publish, etc. - a vendor happened to be editing on that doc at the same
  // moment). Firestore transactions detect any conflicting write to the
  // document made during the transaction and retry the whole callback with
  // fresh data, so wrapping the exact same mutation logic in one makes it
  // safe under concurrency without changing what gets written or how the
  // -1 "unlimited stock" sentinel is handled.
  static Future<void> decrementProductStock({
    required String productId,
    required int quantity,
    String? variantId,
  }) async {
    final docRef = firestore.collection(PRODUCTS).doc(productId);
    try {
      await firestore.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists || snap.data() == null) return;
        final productModel = ProductModel.fromJson(snap.data()!);
        if (variantId != null && productModel.itemAttributes?.variants != null) {
          for (final v in productModel.itemAttributes!.variants!) {
            if (v.variant_id == variantId && v.variant_quantity != '-1') {
              v.variant_quantity = (int.parse(v.variant_quantity.toString()) - quantity).toString();
            }
          }
        } else if (productModel.quantity != -1) {
          productModel.quantity -= quantity;
        }
        tx.set(docRef, productModel.toJson());
      });
    } catch (stockErr) {
      print('Stock update error for $productId: $stockErr');
    }
  }

  static Future<VendorModel?> updateVendor(VendorModel vendor) async {
    return await firestore.collection(VENDORS).doc(vendor.id).set(vendor.toJson()).then((document) {
      return vendor;
    });
  }

  // Narrow, merge-only write for review submission (ReviewScreen.dart) -
  // deliberately NOT a full vendor.toJson() .set() like updateVendor above.
  // firestore.rules only lets a customer touch reviewsCount/reviewsSum on a
  // vendor doc they don't own, checked via diff().affectedKeys() - a full
  // re-serialized VendorModel can disagree with what's actually stored on
  // some unrelated field (Timestamp/GeoPoint/nested map round-tripping
  // differently) and make that diff check see more than just these two
  // keys, silently denying the write. Same class of bug already fixed once
  // in vendorApp's order-accept flow (see updateOrderFields there).
  // Atomic FieldValue.increment deltas, not absolute totals - a client-computed
  // absolute .set() here would lose concurrent reviewers' updates (classic
  // read-modify-write race: two customers reviewing the same vendor around the
  // same time each read a stale total and overwrite the other's contribution,
  // letting reviewsSum drift out of ratio with reviewsCount over time). Pass
  // the delta this single review adds (+1/+rating for a new review, 0/swing
  // for an edit) - firestore.rules' per-write bounds on vendors/{id} still
  // apply to the resulting document either way.
  static Future<void> updateVendorReviewStats(String vendorId, num reviewsCountDelta, num reviewsSumDelta) async {
    await firestore.collection(VENDORS).doc(vendorId).set({
      'reviewsCount': FieldValue.increment(reviewsCountDelta),
      'reviewsSum': FieldValue.increment(reviewsSumDelta),
    }, SetOptions(merge: true));
  }

  // Same reasoning as updateVendorReviewStats above, for the product doc.
  static Future<void> updateProductReviewStats(String productId, num reviewsCountDelta, num reviewsSumDelta, Map<String, dynamic> reviewAttributes) async {
    await firestore.collection(PRODUCTS).doc(productId).set({
      'reviewsCount': FieldValue.increment(reviewsCountDelta),
      'reviewsSum': FieldValue.increment(reviewsSumDelta),
      'reviewAttributes': reviewAttributes,
    }, SetOptions(merge: true));
  }

  static Future<String> uploadUserImageToFireStorage(File image, String userID) async {
    return uploadImageToBunny(image, 'profiles');
  }

  Future<Url> uploadChatImageToFireStorage(File image, BuildContext context) async {
    await showProgress("Please wait...".tr(), false);
    var uniqueID = const Uuid().v4();
    Reference upload = storage.child(STORAGE_ROOT + '/chat/images/$uniqueID.png');
    UploadTask uploadTask = upload.putFile(image);
    var storageRef = (await uploadTask.whenComplete(() {})).ref;
    var downloadUrl = await storageRef.getDownloadURL();
    var metaData = await storageRef.getMetadata();
    hideProgress();
    return Url(mime: metaData.contentType ?? 'image', url: downloadUrl.toString());
  }

  Future<ChatVideoContainer> uploadChatVideoToFireStorage(File video, BuildContext context) async {
    await showProgress("Please wait...".tr(), false);
    var uniqueID = const Uuid().v4();
    Reference upload = storage.child(STORAGE_ROOT + '/chat/videos/$uniqueID.mp4');
    File compressedVideo = await _compressVideo(video);
    SettableMetadata metadata = SettableMetadata(contentType: 'video');
    UploadTask uploadTask = upload.putFile(compressedVideo, metadata);
    var storageRef = (await uploadTask.whenComplete(() {})).ref;
    var downloadUrl = await storageRef.getDownloadURL();
    var metaData = await storageRef.getMetadata();
    final uint8list = await VideoThumbnail.thumbnailFile(video: downloadUrl, thumbnailPath: (await getTemporaryDirectory()).path, imageFormat: ImageFormat.PNG);
    final file = File(uint8list ?? '');
    String thumbnailDownloadUrl = await uploadVideoThumbnailToFireStorage(file);
    hideProgress();
    return ChatVideoContainer(videoUrl: Url(url: downloadUrl.toString(), mime: metaData.contentType ?? 'video'), thumbnailUrl: thumbnailDownloadUrl);
  }

  Future<String> uploadVideoThumbnailToFireStorage(File file) async {
    var uniqueID = const Uuid().v4();
    Reference upload = storage.child(STORAGE_ROOT + '/thumbnails/$uniqueID.png');
    UploadTask uploadTask = upload.putFile(file);
    var downloadUrl = await (await uploadTask.whenComplete(() {})).ref.getDownloadURL();
    return downloadUrl.toString();
  }

  Stream<User> getUserByID(String id) async* {
    StreamController<User> userStreamController = StreamController();
    firestore.collection(USERS).doc(id).snapshots().listen((user) {
      try {
        User userModel = User.fromJson(user.data() ?? {});
        userStreamController.sink.add(userModel);
      } catch (e) {
        print('FireStoreUtils.getUserByID failed to parse user object ${user.id}');
      }
    });
    yield* userStreamController.stream;
  }

  Future<List> getVendorCusions(String id) async {
    List tagList = [];
    List prodtagList = [];
    QuerySnapshot<Map<String, dynamic>> productsQuery = await firestore.collection(PRODUCTS).where('vendorID', isEqualTo: id).get();
    await Future.forEach(productsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      if (document.data().containsKey("categoryID") && document.data()['categoryID'].toString().isNotEmpty) {
        prodtagList.add(document.data()['categoryID']);
      }
    });
    QuerySnapshot<Map<String, dynamic>> catQuery = await firestore.collection(CATEGORIES).where('publish', isEqualTo: true).get();
    await Future.forEach(catQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      Map<String, dynamic> catDoc = document.data();
      if (catDoc.containsKey("id") &&
          catDoc['id'].toString().isNotEmpty &&
          catDoc.containsKey("title") &&
          catDoc['title'].toString().isNotEmpty &&
          prodtagList.contains(catDoc['id'])) {
        tagList.add(catDoc['title']);
      }
    });

    return tagList;
  }

  Stream<StripeKeyModel> getStripe() async* {
    // ignore: close_sinks
    StreamController<StripeKeyModel> stripeStreamController = StreamController();
    firestore.collection(Setting).doc(StripeSetting).snapshots().listen((user) {
      try {
        StripeKeyModel userModel = StripeKeyModel.fromJson(user.data() ?? {});
        stripeStreamController.sink.add(userModel);
      } catch (e) {
        print('FireStoreUtils.getUserByID failed to parse user object ${user.id}');
      }
    });
    yield* stripeStreamController.stream;
  }

  static getRazorPay() async {
    // Reads the safe-fields-only mirror (public key + enabled flags), not
    // the real settings/razorpaySettings doc, which is admin-only now that
    // its secret is no longer publicly readable (2026-07-16). Nothing
    // client-side legitimately needs razorpaySecret anymore - the model's
    // razorpaySecret field simply stays empty, matching its own default.
    // ignore: close_sinks
    firestore.collection(SettingPublic).doc("razorpaySettings").get().then((user) {
      try {
        RazorPayModel userModel = RazorPayModel.fromJson(user.data() ?? {});
        UserPreference.setRazorPayData(userModel);
      } catch (e) {
        print('FireStoreUtils.getUserByID failed to parse user object ${user.id}');
      }
    });
  }

  static Future<void> getPayFastSettingData() async {
    try {
      final payFastData = await firestore.collection(Setting).doc("payFastSettings").get();
      final payFastSettingData = PayFastSettingData.fromJson(payFastData.data() ?? {});
      UserPreference.setPayFastData(payFastSettingData);
    } catch (error) {
      print(error.toString());
    }
  }

  static Future<void> getPaypalSettingData() async {
    try {
      final paypalData = await firestore.collection(Setting).doc("paypalSettings").get();
      final payplaDataModel = PaypalSettingData.fromJson(paypalData.data() ?? {});
      UserPreference.setPayPalData(payplaDataModel);
    } catch (error) {
      print(error.toString());
    }
  }

  static Future<void> getMercadoPagoSettingData() async {
    try {
      final mercadoPago = await firestore.collection(Setting).doc("MercadoPago").get();
      final mercadoPagoDataModel = MercadoPagoSettingData.fromJson(mercadoPago.data() ?? {});
      UserPreference.setMercadoPago(mercadoPagoDataModel);
    } catch (error) {
      print(error.toString());
    }
  }

  static Future<void> getStripeSettingData() async {
    try {
      final stripeData = await firestore.collection(Setting).doc("stripeSettings").get();
      final stripeSettingData = StripeSettingData.fromJson(stripeData.data() ?? {});
      UserPreference.setStripeData(stripeSettingData);
    } catch (error) {
      print(error.toString());
    }
  }

  static Future<void> getFlutterWaveSettingData() async {
    try {
      final flutterWaveData = await firestore.collection(Setting).doc("flutterWave").get();
      final flutterWaveSettingData = FlutterWaveSettingData.fromJson(flutterWaveData.data() ?? {});
      UserPreference.setFlutterWaveData(flutterWaveSettingData);
    } catch (error) {}
  }

  static Future<void> getPayStackSettingData() async {
    try {
      final payStackData = await firestore.collection(Setting).doc("payStack").get();
      final payStackSettingData = PayStackSettingData.fromJson(payStackData.data() ?? {});
      UserPreference.setPayStackData(payStackSettingData);
    } catch (error) {
      print(error.toString());
    }
  }

  static Future<void> getOrangeMoneySettingData() async {
    try {
      final orangeData = await firestore.collection(Setting).doc("orange_money_settings").get();
      final orangeMoneyData = OrangeMoney.fromJson(orangeData.data() ?? {});
      UserPreference.setOrangeData(orangeMoneyData);
    } catch (error) {
      print(error.toString());
    }
  }

  static Future<void> getXenditSettingData() async {
    try {
      final xenditData = await firestore.collection(Setting).doc("xendit_settings").get();
      final xenditModel = Xendit.fromJson(xenditData.data() ?? {});
      UserPreference.setXenditData(xenditModel);
    } catch (error) {
      print(error.toString());
    }
  }

  static Future<void> getMidTransSettingData() async {
    try {
      final midTransData = await firestore.collection(Setting).doc("midtrans_settings").get();
      final midTransModel = MidTrans.fromJson(midTransData.data() ?? {});
      UserPreference.setMidTransData(midTransModel);
    } catch (error) {
      print(error.toString());
    }
  }

  static Future<void> getPhonePaySettingData() async {
    try {
      final data = await firestore.collection(Setting).doc("phonepe_settings").get();
      final settingData = PhonePaySettingData.fromJson(data.data() ?? {});
      UserPreference.setPhonePayData(settingData);
    } catch (error) {
      print(error.toString());
    }
  }

  static Future<void> getPaytmSettingData() async {
    try {
      final paytmData = await firestore.collection(Setting).doc("PaytmSettings").get();
      final paytmSettingData = PaytmSettingData.fromJson(paytmData.data() ?? {});
      UserPreference.setPaytmData(paytmSettingData);
    } catch (error) {
      print(error.toString());
    }
  }

  static getWalletSettingData() {
    // TEMPORARY [FIRESTORE-PERF] - round-trip timing for the app-open-speed
    // investigation. This is called from multiple sites (main.dart splash
    // flow, ContainerScreen.initState, service_list_screen,
    // location_permission_screen) — the absolute ISO8601 timestamp is what
    // lets a given call be matched back to its caller in the logs. Remove
    // once done.
    final sw = Stopwatch()..start();
    debugPrint('[FIRESTORE-PERF] getWalletSettingData() dispatched (${DateTime.now().toIso8601String()})');
    firestore.collection(Setting).doc('walletSettings').get().then((walletSetting) {
      debugPrint('[FIRESTORE-PERF] getWalletSettingData() Firestore round-trip — '
          '${sw.elapsedMilliseconds}ms (${DateTime.now().toIso8601String()})');
      try {
        bool walletEnable = walletSetting.data()!['isEnabled'];
        UserPreference.setWalletData(walletEnable);
      } catch (e) {
        print(e.toString());
      }
    });
  }

  // Only Razorpay is enabled in production (confirmed 2026-08-02) - Stripe/
  // Paypal/PayStack/FlutterWave/Paytm/PayFast/MercadoPago/OrangeMoney/
  // Xendit/MidTrans/PhonePe are NOT fetched here anymore, so their
  // UserPreference cache stays null and their payment tiles simply don't
  // render (same as if disabled in admin) wherever they're read
  // (PaymentScreen, walletScreen, gift_card_purchase_screen). Their fetch
  // functions are left intact below, unused - re-add a gateway to the
  // Future.wait list (or back to a plain await if it's the only other one)
  // the day it's actually turned on in production, rather than deleting the
  // integration entirely.
  //
  // Consumed by three payment-entry points that read UserPreference's local
  // cache directly: PaymentScreen (the food-order path, reached only via
  // CartScreen -> Place Order), walletScreen's topUpBalance() ("Add Money"
  // tap), and gift_card_purchase_screen (reached only after the user picks a
  // specific gift-card amount to buy). None of Cart/Wallet/GiftCard preload
  // this on screen-open anymore — many sessions open the cart or check
  // their wallet balance without ever paying. Splash/startup never calls
  // this either.
  //
  // Instead, HomeScreen.initState() fires this unawaited, in the
  // background, once Home's own critical fetches are already in flight
  // (see the identical reasoning on loadRecommendationConfig above) — since
  // virtually every session reaches Home, this is a one-time cost paid in
  // the background well before checkout, so the *first* real checkout of
  // the session still feels instant. The three payment-entry points above
  // still `await` this call themselves as a safety net for the rare case a
  // user reaches payment before Home's background call resolves — in
  // almost every session that await returns immediately, since the cache
  // is already warm by then.
  //
  // Memoized like loadRecommendationConfig above: the first caller in a
  // session kicks off the real fetch and returns the in-flight Future;
  // every caller after that — whether the fetch already finished or is
  // still running — awaits that SAME Future rather than re-firing it or
  // resolving instantly.
  static Completer<void>? _paymentGatewaySettingsLoad;
  static Future<void> ensurePaymentGatewaySettingsLoaded() {
    final existing = _paymentGatewaySettingsLoad;
    if (existing != null) return existing.future;
    final completer = Completer<void>();
    _paymentGatewaySettingsLoad = completer;
    getRazorPayDemo().whenComplete(() {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  static Future<void> getRazorPayDemo() async {
    // Reads the safe-fields-only mirror, not the real (now admin-only)
    // settings doc - see getRazorPay()'s comment above.
    try {
      final user = await firestore.collection(SettingPublic).doc("razorpaySettings").get();
      final userModel = RazorPayModel.fromJson(user.data() ?? {});
      UserPreference.setRazorPayData(userModel);
    } catch (e) {
      print('FireStoreUtils.getUserByID failed to parse user object');
    }

    //yield* razorPayStreamController.stream;
  }

  Future<CodModel?> getCod() async {
    DocumentSnapshot<Map<String, dynamic>> codQuery = await firestore.collection(Setting).doc('CODSettings').get();
    if (codQuery.data() != null) {
      return CodModel.fromJson(codQuery.data()!);
    } else {
      print("nulllll");
      return null;
    }
  }

  Future<DeliveryChargeModel?> getDeliveryCharges() async {
    DocumentSnapshot<Map<String, dynamic>> codQuery = await firestore.collection(Setting).doc('DeliveryCharge').get();
    if (codQuery.data() != null) {
      return DeliveryChargeModel.fromJson(codQuery.data()!);
    } else {
      return null;
    }
  }

  static Future<List<SectionModel>> getSections() async {
    List<SectionModel> sections = [];
    QuerySnapshot<Map<String, dynamic>> productsQuery = await firestore.collection(SECTION).where("isActive", isEqualTo: true).get();

    await Future.forEach(productsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        sections.add(SectionModel.fromJson(document.data()));
      } catch (e) {
        print('**-FireStoreUtils.getSection Parse error $e');
      }
    });

    return sections;
  }

  Future<SectionModel?> getSectionsById(String? sectionId) async {
    DocumentSnapshot<Map<String, dynamic>> userDocument = await firestore.collection(SECTION).doc(sectionId).get();
    if (userDocument.data() != null && userDocument.exists) {
      return SectionModel.fromJson(userDocument.data()!);
    } else {
      return null;
    }
  }

  // ── Product list cache ─────────────────────────────────────────────────────
  // Keyed by "${sectionId}_${type}" so A→B→A re-uses the cached A list.
  static final Map<String, List<ProductModel>> _productsCache = {};
  static final Map<String, DateTime> _productsCachedAt = {};
  static const Duration _productsCacheTtl = Duration(minutes: 10);

  static void clearProductsCache() {
    _productsCache.clear();
    _productsCachedAt.clear();
  }

  // Clears only one vendor's cached product list (key: "${vendorID}_vendor_all").
  // Used by manual pull-to-refresh so refreshing one restaurant doesn't evict
  // every other vendor's still-fresh cache.
  static void clearVendorProductsCache(String vendorID) {
    final key = '${vendorID}_vendor_all';
    _productsCache.remove(key);
    _productsCachedAt.remove(key);
  }

  Future<List<ProductModel>> _fetchProducts(String cacheKey, Query<Map<String, dynamic>> query) async {
    final now = DateTime.now();
    final cached = _productsCache[cacheKey];
    final cachedAt = _productsCachedAt[cacheKey];
    if (cached != null && cachedAt != null &&
        now.difference(cachedAt) < _productsCacheTtl) {
      return cached;
    }
    final List<ProductModel> products = [];
    final snapshot = await query.get();
    for (final doc in snapshot.docs) {
      try {
        products.add(ProductModel.fromJson(doc.data()));
      } catch (e) {
        print('FireStoreUtils.getAllProducts parse error $e');
      }
    }
    _productsCache[cacheKey] = products;
    _productsCachedAt[cacheKey] = now;
    return products;
  }

  // ── Offers & Discounts (2026-08-03) ────────────────────────────────────────
  // Categories are few and admin-curated, so a whole-list TTL cache is fine.
  // Offers are fetched in full per category (see getAllActiveLocalOffers
  // below, 2026-08-07) so no whole-list cache is kept for them - each
  // category switch is its own fresh query.
  static List<LocalOfferCategoryModel>? _localOfferCategoriesCache;
  static DateTime? _localOfferCategoriesCachedAt;
  static const Duration _localOffersCacheTtl = Duration(minutes: 10);

  static void clearLocalOffersCache() {
    _localOfferCategoriesCache = null;
    _localOfferCategoriesCachedAt = null;
  }

  static Future<List<LocalOfferCategoryModel>> getLocalOfferCategories() async {
    final now = DateTime.now();
    if (_localOfferCategoriesCache != null &&
        _localOfferCategoriesCachedAt != null &&
        now.difference(_localOfferCategoriesCachedAt!) < _localOffersCacheTtl) {
      return _localOfferCategoriesCache!;
    }
    final List<LocalOfferCategoryModel> categories = [];
    try {
      final snapshot = await firestore
          .collection(LOCAL_OFFER_CATEGORIES)
          .where('isActive', isEqualTo: true)
          .orderBy('sortOrder')
          .get();
      for (final doc in snapshot.docs) {
        categories.add(LocalOfferCategoryModel.fromJson(doc.data()));
      }
    } catch (e) {
      log('FireStoreUtils.getLocalOfferCategories $e');
    }
    _localOfferCategoriesCache = categories;
    _localOfferCategoriesCachedAt = now;
    return categories;
  }

  /// All currently-active offers, optionally filtered to one category.
  /// (2026-08-07) Replaced the old createdAt-cursor pagination - the list
  /// screen's sort now depends on distance (computed client-side from live
  /// GPS) and an admin-recommended flag, neither of which Firestore can
  /// order by server-side, so ordering has to happen after everything is
  /// fetched. [limit] is a safety cap, not a page size - at this app's
  /// current business count this pulls the whole active set in one call;
  /// revisit with real geo-bounded pagination if that count grows large.
  static Future<List<LocalOfferModel>> getAllActiveLocalOffers({
    String? categoryId,
    int limit = 300,
  }) async {
    List<LocalOfferModel> offers = [];
    try {
      Query<Map<String, dynamic>> query = firestore.collection(LOCAL_OFFERS).where('isActive', isEqualTo: true);
      if (categoryId != null && categoryId.isNotEmpty) {
        query = query.where('categoryId', isEqualTo: categoryId);
      }
      final snapshot = await query.limit(limit).get();
      // (2026-08-05) One document = one business now - every result here is
      // its own standalone business, nothing to filter out (previously a
      // business's extra offers were separate sibling documents that had to
      // be excluded from this feed; now they live inside the same doc's own
      // offers[] array instead - see LocalOfferModel.primary).
      offers = snapshot.docs.map((d) => LocalOfferModel.fromJson(d.data())).toList();
    } catch (e) {
      log('FireStoreUtils.getAllActiveLocalOffers $e');
    }
    return offers;
  }


  Future<List<ProductModel>> getAllProducts() async {
    final key = '${sectionConstantModel!.id}_all';
    return _fetchProducts(
      key,
      firestore
          .collection(PRODUCTS)
          .where("section_id", isEqualTo: sectionConstantModel!.id)
          .where('publish', isEqualTo: true),
    );
  }

  Future<List<ProductModel>> getAllDelevryProducts() async {
    final key = '${sectionConstantModel!.id}_delivery';
    return _fetchProducts(
      key,
      firestore
          .collection(PRODUCTS)
          // .where("deliveryOption", isEqualTo: true)
          .where("section_id", isEqualTo: sectionConstantModel!.id)
          .where('publish', isEqualTo: true),
    );
  }

  Future<List<ProductModel>> getAllTakeAWayProducts() async {
    final key = '${sectionConstantModel!.id}_takeaway';
    return _fetchProducts(
      key,
      firestore
          .collection(PRODUCTS)
          // .where("takeawayOption", isEqualTo: true)
          .where("section_id", isEqualTo: sectionConstantModel!.id)
          .where('publish', isEqualTo: true),
    );
  }

  Future<bool> blockUser(User blockedUser, String type) async {
    bool isSuccessful = false;
    BlockUserModel blockUserModel = BlockUserModel(type: type, source: MyAppState.currentUser!.userID, dest: blockedUser.userID, createdAt: Timestamp.now());
    await firestore.collection(REPORTS).add(blockUserModel.toJson()).then((onValue) {
      isSuccessful = true;
    });
    return isSuccessful;
  }

  Stream<bool> getBlocks() async* {
    StreamController<bool> refreshStreamController = StreamController();
    firestore.collection(REPORTS).where('source', isEqualTo: MyAppState.currentUser!.userID).snapshots().listen((onData) {
      List<BlockUserModel> list = [];
      for (DocumentSnapshot<Map<String, dynamic>> block in onData.docs) {
        list.add(BlockUserModel.fromJson(block.data() ?? {}));
      }
      blockedList = list;
      refreshStreamController.sink.add(true);
    });
    yield* refreshStreamController.stream;
  }

  bool validateIfUserBlocked(String userID) {
    for (BlockUserModel blockedUser in blockedList) {
      if (userID == blockedUser.dest) {
        return true;
      }
    }
    return false;
  }

  Future<Url> uploadAudioFile(File file, BuildContext context) async {
    await showProgress("Please wait...".tr(), false);
    var uniqueID = const Uuid().v4();
    Reference upload = storage.child(STORAGE_ROOT + '/audio/$uniqueID.mp3');
    SettableMetadata metadata = SettableMetadata(contentType: 'audio');
    UploadTask uploadTask = upload.putFile(file, metadata);
    uploadTask.whenComplete(() {}).catchError((onError) => print((onError as PlatformException).message));
    var storageRef = (await uploadTask.whenComplete(() {})).ref;
    var downloadUrl = await storageRef.getDownloadURL();
    var metaData = await storageRef.getMetadata();
    hideProgress();
    return Url(mime: metaData.contentType ?? 'audio', url: downloadUrl.toString());
  }

  Future<List<VendorCategoryModel>> getCuisines() async {
    List<VendorCategoryModel> cuisines = [];
    QuerySnapshot<Map<String, dynamic>> cuisinesQuery =
        await firestore.collection(CATEGORIES).where("section_id", isEqualTo: sectionConstantModel!.id).where('publish', isEqualTo: true).get();
    await Future.forEach(cuisinesQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        cuisines.add(VendorCategoryModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCuisines Parse error $e');
      }
    });
    return cuisines;
  }

  Future<List<VendorCategoryModel>> getHomePageShowCategory() async {
    List<VendorCategoryModel> cuisines = [];
    QuerySnapshot<Map<String, dynamic>> cuisinesQuery = await firestore
        .collection(CATEGORIES)
        .where("section_id", isEqualTo: sectionConstantModel!.id)
        .where("show_in_homepage", isEqualTo: true)
        .where('publish', isEqualTo: true)
        .get();
    await Future.forEach(cuisinesQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        cuisines.add(VendorCategoryModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCuisines Parse error $e');
      }
    });
    return cuisines;
  }

  StreamController<List<VendorModel>>? dineInStreamController;

  // Same geoflutterfire radius filter as getAllStores()/getVendorsByCuisineID()
  // - this previously queried the whole section with no distance check at
  // all, so the Dine In tab could show vendors far outside nearByRadius.
  Stream<List<VendorModel>> getAllDineInRestaurants() async* {
    dineInStreamController = StreamController<List<VendorModel>>.broadcast();

    try {
      var collectionReference = firestore
          .collection(VENDORS)
          .where("section_id", isEqualTo: sectionConstantModel!.id)
          .where("enabledDiveInFuture", isEqualTo: true);

      GeoFirePoint center = geo.point(
          latitude: MyAppState.selectedPosotion.location!.latitude,
          longitude: MyAppState.selectedPosotion.location!.longitude);

      Stream<List<DocumentSnapshot>> stream = geo
          .collection(collectionRef: collectionReference)
          .within(center: center, radius: double.parse(sectionConstantModel!.nearByRadius.toString()), field: 'g', strictMode: true);

      stream.listen((List<DocumentSnapshot> documentList) {
        final List<VendorModel> vendors = [];
        for (var doc in documentList) {
          try {
            vendors.add(VendorModel.fromJson(doc.data() as Map<String, dynamic>));
          } catch (e) {
            print('getAllDineInRestaurants parse error: $e');
          }
        }
        if (dineInStreamController?.isClosed == false) {
          dineInStreamController!.add(vendors);
        }
      });
    } catch (e) {
      print('getAllDineInRestaurants setup error: $e');
    }

    yield* dineInStreamController!.stream;
  }

  late StreamSubscription vendorStreamSub;
  StreamController<List<VendorModel>>? vendorStreamController;

  Stream<List<VendorModel>> getVendors1({String? path}) {
    final query = (path == null || path.isEmpty)
        ? firestore.collection(VENDORS).where("section_id", isEqualTo: sectionConstantModel!.id)
        : firestore.collection(VENDORS).where("section_id", isEqualTo: sectionConstantModel!.id).where("enabledDiveInFuture", isEqualTo: true);

    return query.snapshots().map((snapshot) {
      final List<VendorModel> vendors = [];
      for (var doc in snapshot.docs) {
        try {
          final data = doc.data();
          final storeStatus = data['store_status'] as String?;
          if ((storeStatus == null || storeStatus == 'approved') &&
              data['isActive'] != false) {
            vendors.add(VendorModel.fromJson(data));
          }
        } catch (e) {
          print('getVendors1 parse error: $e');
        }
      }
      return vendors;
    });
  }

  Future<List<VendorModel>> getVendors() async {
    List<VendorModel> vendors = [];
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore.collection(VENDORS).where("section_id", isEqualTo: sectionConstantModel!.id).get();
    await Future.forEach(vendorsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        final data = document.data();
        final storeStatus = data['store_status'] as String?;
        if ((storeStatus == null || storeStatus == 'approved') &&
            data['isActive'] != false) {
          vendors.add(VendorModel.fromJson(data));
        }
      } catch (e) {
        print('FireStoreUtils.getVendors Parse error $e');
      }
    });
    return vendors;
  }

  Stream<List<BookTableModel>> getBookingOrders(String userID, bool isUpComing) async* {
    List<BookTableModel> orders = [];

    if (isUpComing) {
      StreamController<List<BookTableModel>> upcomingordersStreamController = StreamController();
      firestore
          .collection(ORDERS_TABLE)
          .where('author.id', isEqualTo: userID)
          .where('date', isGreaterThan: Timestamp.now())
          .where("section_id", isEqualTo: sectionConstantModel!.id)
          .orderBy('date', descending: true)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen((onData) async {
        await Future.forEach(onData.docs, (QueryDocumentSnapshot<Map<String, dynamic>> element) {
          try {
            orders.add(BookTableModel.fromJson(element.data()));
          } catch (e, s) {
            print('booktable parse error ${element.id} $e $s');
          }
        });
        upcomingordersStreamController.sink.add(orders);
      });
      yield* upcomingordersStreamController.stream;
    } else {
      StreamController<List<BookTableModel>> bookedordersStreamController = StreamController();
      firestore
          .collection(ORDERS_TABLE)
          .where('author.id', isEqualTo: userID)
          .where('date', isLessThan: Timestamp.now())
          .where("section_id", isEqualTo: sectionConstantModel!.id)
          .orderBy('date', descending: true)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen((onData) async {
        await Future.forEach(onData.docs, (QueryDocumentSnapshot<Map<String, dynamic>> element) {
          try {
            orders.add(BookTableModel.fromJson(element.data()));
          } catch (e, s) {
            print('booktable parse error ${element.id} $e $s');
          }
        });
        bookedordersStreamController.sink.add(orders);
      });
      yield* bookedordersStreamController.stream;
    }
  }

  late StreamSubscription ordersStreamSub;
  late StreamController<List<OrderModel>> ordersStreamController;

  Stream<List<OrderModel>> getOrders(String userID) async* {
    List<OrderModel> orders = [];
    ordersStreamController = StreamController();
    ordersStreamSub = firestore
        .collection(ORDERS)
        .where('authorID', isEqualTo: userID)
        .where('section_id', isEqualTo: sectionConstantModel!.id)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .listen((onData) async {
      orders.clear();

      await Future.forEach(onData.docs, (QueryDocumentSnapshot<Map<String, dynamic>> element) {
        try {
          OrderModel orderModel = OrderModel.fromJson(element.data());
          if (!orders.contains(orderModel)) {
            orders.add(orderModel);
          }
        } catch (e, s) {
          print('watchOrdersStatus parse error ${element.id} $e $s');
        }
      });
      ordersStreamController.sink.add(orders);
    });
    yield* ordersStreamController.stream;
  }

  closeOrdersStream() {
    ordersStreamSub.cancel();
    ordersStreamController.close();
  }

  static setFavouriteStore(FavouriteModel favouriteModel) {
    firestore.collection(FavouriteStore).add(favouriteModel.toJson()).then((value) {
      print("===FAVOURITE ADDED===");
    });
  }

  static removeFavouriteStore(FavouriteModel favouriteModel) {
    FirebaseFirestore.instance
        .collection(FavouriteStore)
        .where("store_id", isEqualTo: favouriteModel.store_id)
        .where("section_id", isEqualTo: sectionConstantModel!.id)
        .get()
        .then((value) {
      for (var element in value.docs) {
        FirebaseFirestore.instance.collection(FavouriteStore).doc(element.id).delete().then((value) {
          print("Success!");
        });
      }
    });
  }

  Future<List<FavouriteItemModel>> getFavouritesProductList(String userId) async {
    List<FavouriteItemModel> lstFavourites = [];

    QuerySnapshot<Map<String, dynamic>> favourites =
        await firestore.collection(FavouriteItem).where('user_id', isEqualTo: userId).where("section_id", isEqualTo: sectionConstantModel!.id).get();
    await Future.forEach(favourites.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        lstFavourites.add(FavouriteItemModel.fromJson(document.data()));
      } catch (e) {
        print('FavouriteModel.getCurrencys Parse error $e');
      }
    });
    return lstFavourites;
  }

  Future<List<FavouriteOndemandServiceModel>> getFavouritesServiceList(
    String userId,
  ) async {
    List<FavouriteOndemandServiceModel> lstFavourites = [];

    QuerySnapshot<Map<String, dynamic>> favourites =
        await firestore.collection(FavouriteOndemandItem).where('user_id', isEqualTo: userId).where("section_id", isEqualTo: sectionConstantModel!.id).get();
    await Future.forEach(favourites.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        lstFavourites.add(FavouriteOndemandServiceModel.fromJson(document.data()));
      } catch (e) {
        print('FavouriteModel.getCurrencys Parse error $e');
      }
    });
    return lstFavourites;
  }

  Future<void> setFavouriteStoreItem(FavouriteItemModel favouriteModel) async {
    await firestore.collection(FavouriteItem).add(favouriteModel.toJson()).then((value) {
      print("===FAVOURITE ADDED===");
    });
  }

  Future<void> setFavouriteOndemandSection(FavouriteOndemandServiceModel favouriteModel) async {
    await firestore.collection(FavouriteOndemandItem).add(favouriteModel.toJson()).then((value) {
      print("===FAVOURITE ADDED===");
    });
  }

  void removeFavouriteOndemandService(FavouriteOndemandServiceModel favouriteModel) {
    FirebaseFirestore.instance
        .collection(FavouriteOndemandItem)
        .where("user_id", isEqualTo: favouriteModel.user_id)
        .where("service_id", isEqualTo: favouriteModel.service_id)
        .get()
        .then((value) {
      for (var element in value.docs) {
        FirebaseFirestore.instance.collection(FavouriteOndemandItem).doc(element.id).delete().then((value) {
          print("Remove Success!");
        });
      }
    });
  }

  /*closeFavouriteStream() {
    favouriteStreamSub.cancel();
    favouriteStreamControleer.close();
  }*/

  StreamController<List<VendorModel>>? allResaturantStreamController;

  Stream<List<VendorModel>> getAllStores() async* {
    allResaturantStreamController = StreamController<List<VendorModel>>.broadcast();

    try {
      var collectionReference = firestore.collection(VENDORS).where("section_id", isEqualTo: sectionConstantModel!.id);

      GeoFirePoint center = geo.point(latitude: MyAppState.selectedPosotion.location!.latitude, longitude: MyAppState.selectedPosotion.location!.longitude);

      Stream<List<DocumentSnapshot>> stream = geo
          .collection(collectionRef: collectionReference)
          .within(center: center, radius: double.parse(sectionConstantModel!.nearByRadius.toString()), field: 'g', strictMode: true);

      stream.listen((List<DocumentSnapshot> documentList) {
        // Rebuild fresh on every Geofire event — never accumulate, never close early
        final List<VendorModel> vendors = [];
        for (var document in documentList) {
          try {
            final data = document.data() as Map<String, dynamic>;
            final storeStatus = data['store_status'] as String?;
            if ((storeStatus == null || storeStatus == 'approved') &&
                data['isActive'] != false) {
              vendors.add(VendorModel.fromJson(data));
            }
          } catch (e) {
            print('getAllStores parse error: $e');
          }
        }
        if (allResaturantStreamController?.isClosed == false) {
          allResaturantStreamController!.add(vendors);
        }
      });
    } catch (e) {
      print('getAllStores setup error: $e');
    }

    yield* allResaturantStreamController!.stream;
  }

  closeVendorStream() {
    if (vendorStreamController != null) {
      vendorStreamController!.close();
    }
    if (allResaturantStreamController != null) {
      allResaturantStreamController!.close();
    }
    //newArrivalStreamController.close();
    //productStreamController123.close();
    //productStreamController.close();
  }

  late StreamController<List<VendorModel>> cusionStreamController;

  Stream<List<VendorModel>> getVendorsByCuisineID(String cuisineID, {bool? isDinein}) async* {
    cusionStreamController = StreamController<List<VendorModel>>.broadcast();
    var collectionReference = isDinein!
        ? firestore.collection(VENDORS).where('categoryID', isEqualTo: cuisineID).where("enabledDiveInFuture", isEqualTo: true)
        : firestore.collection(VENDORS).where('categoryID', isEqualTo: cuisineID);

    GeoFirePoint center = geo.point(latitude: MyAppState.selectedPosotion.location!.latitude, longitude: MyAppState.selectedPosotion.location!.longitude);
    Stream<List<DocumentSnapshot>> stream = geo
        .collection(collectionRef: collectionReference)
        .within(center: center, radius: double.parse(sectionConstantModel!.nearByRadius.toString()), field: 'g', strictMode: true);
    stream.listen((List<DocumentSnapshot> documentList) {
      // Rebuild fresh on every Geofire event — never accumulate, never close early
      final List<VendorModel> vendors = [];
      for (var element in documentList) {
        try {
          final data = element.data() as Map<String, dynamic>;
          final storeStatus = data['store_status'] as String?;
          if (storeStatus == null || storeStatus == 'approved') {
            vendors.add(VendorModel.fromJson(data));
          }
        } catch (e) {
          print('getVendorsByCuisineID parse error: $e');
        }
      }
      if (!cusionStreamController.isClosed) {
        cusionStreamController.add(vendors);
      }
    });

    yield* cusionStreamController.stream;
  }

  Future<List<OfferModel>> getViewAllOffer() async {
    List<OfferModel> offersData = [];
    // Single-field filter only — no composite index required.
    // expiresAt is checked client-side.
    final nowTs = Timestamp.now();
    QuerySnapshot<Map<String, dynamic>> vendorsQuery =
        await firestore.collection(COUPONS).where("isEnabled", isEqualTo: true).get();
    await Future.forEach(vendorsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        final offer = OfferModel.fromJson(document.data());
        if (offer.expireOfferDate == null || offer.expireOfferDate!.compareTo(nowTs) >= 0) {
          offersData.add(offer);
        }
      } catch (e) {
        print('FireStoreUtils.getViewAllOffer Parse error $e');
      }
    });
    return offersData;
  }

  // Stream<List<OfferModel>>? getOfferStream() async* {
  //   List<OfferModel> offers = [];
  //   offerStreamController = StreamController<List<OfferModel>>.broadcast();
  //   var date = DateTime.now();
  //
  //   offerStreamSub = firestore
  //       .collection(COUPONS)
  //       .where("isEnabled", isEqualTo: true)
  //       .where('expiresAt', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime.now()))
  //       .snapshots()
  //       .listen((event) async {
  //     offers.clear();
  //     if (event.docs.isEmpty) {
  //       offerStreamController!.add(offers);
  //     } else {
  //       await Future.forEach(event.docs, (QueryDocumentSnapshot<Map<String, dynamic>> element) {
  //         try {
  //           offers.add(OfferModel.fromJson(element.data()));
  //         } catch (e, s) {
  //           print('getOrder parse error ${element.id}$e $s');
  //         }
  //       });
  //       offerStreamController!.add(offers);
  //     }
  //
  //     print(offers.length.toString() + "{}{}====+++999");
  //   });
  //   yield* offerStreamController!.stream;
  // }

  StreamController<List<OfferModel>>? offerStreamController;
  StreamSubscription? offerStreamSub;

  Stream<List<OfferModel>> getOfferStreamByVendorID(String vendorID) async* {
    List<OfferModel> offers = [];
    offerStreamController = StreamController<List<OfferModel>>();
    offerStreamSub = firestore
        .collection(COUPONS)
        .where("vendorID", isEqualTo: vendorID)
        .where("isEnabled", isEqualTo: true)
        .where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now())
        .snapshots()
        .listen((event) async {
      offers.clear();
      await Future.forEach(event.docs, (QueryDocumentSnapshot<Map<String, dynamic>> element) {
        try {
          offers.add(OfferModel.fromJson(element.data()));
        } catch (e, s) {
          print('getProductsStream parse error ${element.id}$e $s');
        }
      });
      offerStreamController!.add(offers);
    });
    yield* offerStreamController!.stream;
  }

  Future<List<OfferModel>> getOfferByVendorID(String vendorID) async {
    // Reuse the cached getAllCoupons() result (same query the cart uses) and
    // filter client-side. The old multi-field Firestore query required a
    // composite index that may not exist, causing silent empty results.
    final all = await getAllCoupons();
    return all
        .where((c) => c.storeId == vendorID && (c.isPublic ?? false))
        .toList();
  }

  closeOfferStream() {
    if (offerStreamSub != null) {
      offerStreamSub!.cancel();
    }
    if (offerStreamController != null) {
      offerStreamController!.close();
    }
  }


  static Future removeFavouriteItem(FavouriteItemModel favouriteModel) async {
    await firestore.collection(FavouriteItem).where("product_id", isEqualTo: favouriteModel.product_id).get().then((value) {
      value.docs.forEach((element) async {
        await firestore.collection(FavouriteItem).doc(element.id).delete();
      });
    });
  }

  static Future<void> setFavouriteItem(FavouriteItemModel favouriteModel) async {
    await firestore.collection(FavouriteItem).add(favouriteModel.toJson());
  }

  Future<List<BannerModel>> getHomeTopBanner() async {
    List<BannerModel> bannerHome = [];
    QuerySnapshot<Map<String, dynamic>> bannerHomeQuery = await firestore
        .collection(MENU_ITEM)
        .where("is_publish", isEqualTo: true)
        .where('sectionId', isEqualTo: sectionConstantModel!.id)
        .where("position", isEqualTo: "top")
        .orderBy("set_order", descending: false)
        .get();

    await Future.forEach(bannerHomeQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        bannerHome.add(BannerModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCuisines Parse error $e');
      }
    });
    return bannerHome;
  }

  Future<List<BannerModel>> getHomeMiddleBanner() async {
    List<BannerModel> bannerHome = [];
    QuerySnapshot<Map<String, dynamic>> bannerHomeQuery = await firestore
        .collection(MENU_ITEM)
        .where("is_publish", isEqualTo: true)
        .where('sectionId', isEqualTo: sectionConstantModel!.id)
        .where("position", isEqualTo: "middle")
        .orderBy("set_order", descending: false)
        .get();

    await Future.forEach(bannerHomeQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        bannerHome.add(BannerModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCuisines Parse error $e');
      }
    });
    return bannerHome;
  }

  /*Future<List<CurrencyModel>> getCurrency() async {
    List<CurrencyModel> currency = [];

    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(Currency).where("isActive", isEqualTo: true).get();
    print(currencyQuery.docs);
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        currency.add(CurrencyModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return currency;
  }*/
  Future<CurrencyModel?> getCurrency() async {
    CurrencyModel? currency;
    await firestore.collection(Currency).where("isActive", isEqualTo: true).get().then((value) {
      if (value.docs.isNotEmpty) {
        currency = CurrencyModel.fromJson(value.docs.first.data());
      }
    });
    return currency;
  }

  static List<OfferModel>? _allCouponsCache;
  static DateTime? _allCouponsCachedAt;
  // 2026-08-05: shortened from 30 to 5 minutes at explicit request - coupons
  // are admin-editable (enable/disable, expiry) and a 30-minute window meant
  // a customer could keep seeing/applying a coupon the admin had already
  // disabled for up to half an hour after the change went live.
  static const Duration _couponsCacheTtl = Duration(minutes: 5);

  // Lets manual pull-to-refresh force a fresh coupon fetch instead of
  // waiting out the 5-minute TTL, same pattern as clearVendorProductsCache.
  static void clearAllCouponsCache() {
    _allCouponsCache = null;
    _allCouponsCachedAt = null;
  }

  /// Returns all enabled, non-expired coupons. Cached for 5 minutes.
  Future<List<OfferModel>> getAllCoupons() async {
    final now = DateTime.now();
    if (_allCouponsCache != null && _allCouponsCachedAt != null &&
        now.difference(_allCouponsCachedAt!) < _couponsCacheTtl) {
      return _allCouponsCache!;
    }
    List<OfferModel> coupon = [];
    // Single-field filter only — avoids composite index on (isEnabled, expiresAt)
    // which may not exist. expiresAt validity is enforced client-side.
    final nowTs = Timestamp.now();
    QuerySnapshot<Map<String, dynamic>> couponsQuery =
        await firestore.collection(COUPONS).where('isEnabled', isEqualTo: true).get();
    await Future.forEach(couponsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        final offer = OfferModel.fromJson(document.data());
        if (offer.expireOfferDate == null || offer.expireOfferDate!.compareTo(nowTs) >= 0) {
          coupon.add(offer);
        }
      } catch (e) {
        print('FireStoreUtils.getAllCoupons Parse error $e');
      }
    });
    _allCouponsCache = coupon;
    _allCouponsCachedAt = now;
    return coupon;
  }

  /// Returns only public-visible coupons. Uses cached getAllCoupons() result.
  Future<List<OfferModel>> getPublicCoupons() async {
    final all = await getAllCoupons();
    return all.where((c) => c.isPublic == true).toList();
  }

  Future<List<OfferModel>> getOfferByCabCoupons() async {
    List<OfferModel> offers = [];

    QuerySnapshot<Map<String, dynamic>> offerQuery = await firestore
        .collection(CAB_COUPONS)
        .where("isEnabled", isEqualTo: true)
        // .where("isPublic", isEqualTo: true)
        .where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now())
        .get();

    await Future.forEach(offerQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        offers.add(OfferModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCuisines Parse error $e');
      }
    });
    return offers;
  }

  Future<List<OfferModel>> getCabCoupons() async {
    List<OfferModel> coupon = [];

    QuerySnapshot<Map<String, dynamic>> couponsQuery =
        await firestore.collection(CAB_COUPONS).where('isEnabled', isEqualTo: true).where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now()).get();
    await Future.forEach(couponsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        coupon.add(OfferModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getAllProducts Parse error $e');
      }
    });
    return coupon;
  }

  Future<List<OfferModel>> getOfferByParcelID(String? parcelCategoryId) async {
    List<OfferModel> offers = [];

    QuerySnapshot<Map<String, dynamic>> offerQuery = await firestore
        .collection(PARCELCOUPONS)
        .where("isEnabled", isEqualTo: true)
        //  .where("isPublic", isEqualTo: true)
        .where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now())
        .get();

    await Future.forEach(offerQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        offers.add(OfferModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCuisines Parse error $e');
      }
    });
    return offers;
  }

  Future<List<OfferModel>> getParcelCoupan() async {
    List<OfferModel> coupon = [];

    QuerySnapshot<Map<String, dynamic>> couponsQuery =
        await firestore.collection(PARCELCOUPONS).where('isEnabled', isEqualTo: true).where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now()).get();
    await Future.forEach(couponsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        coupon.add(OfferModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getAllProducts Parse error $e');
      }
    });
    return coupon;
  }

  Future<List<OfferModel>> getOfferByRentalCoupons() async {
    List<OfferModel> offers = [];

    QuerySnapshot<Map<String, dynamic>> offerQuery = await firestore
        .collection(RENTALCOUPONS)
        .where("isEnabled", isEqualTo: true)
        //  .where("isPublic", isEqualTo: true)
        .where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now())
        .get();

    await Future.forEach(offerQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        offers.add(OfferModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCuisines Parse error $e');
      }
    });
    return offers;
  }

  Future<List<OfferModel>> getRentalCoupons() async {
    List<OfferModel> coupon = [];

    QuerySnapshot<Map<String, dynamic>> couponsQuery =
        await firestore.collection(RENTALCOUPONS).where('isEnabled', isEqualTo: true).where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now()).get();
    await Future.forEach(couponsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        coupon.add(OfferModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getAllProducts Parse error $e');
      }
    });
    return coupon;
  }

  Future<List<ProductModel>> getVendorProducts(String vendorID) async {
    // Shared cache key with getVendorProductsDelivery/TakeAWay — same query.
    final key = '${vendorID}_vendor_all';
    return _fetchProducts(
      key,
      firestore
          .collection(PRODUCTS)
          .where('vendorID', isEqualTo: vendorID)
          .where('publish', isEqualTo: true),
    );
  }

  // Reuses Home's already-fetched whole-section catalog
  // (getAllDelevryProducts/getAllTakeAWayProducts, cached under
  // '${sectionId}_delivery'/'${sectionId}_takeaway') when it's warm,
  // filtering client-side by vendorID instead of re-querying Firestore for
  // data Home already has in memory — this is the common case, since
  // reaching a vendor's product screen almost always means Home rendered
  // first. Falls back to the original per-vendor query
  // (getVendorProductsDelivery/TakeAWay, which populates its own
  // '${vendorID}_vendor_all' cache key) on a genuine cache miss — e.g. the
  // user reaches this screen before Home's background catalog fetch has
  // resolved, or the section-wide TTL already expired — so correctness
  // never depends on timing, only the read count does.
  Future<List<ProductModel>> getVendorProductsPreferSectionCache(
      String vendorID, {required bool takeAway}) async {
    final sectionKey =
        '${sectionConstantModel!.id}_${takeAway ? 'takeaway' : 'delivery'}';
    final cached = _productsCache[sectionKey];
    final cachedAt = _productsCachedAt[sectionKey];
    if (cached != null && cachedAt != null &&
        DateTime.now().difference(cachedAt) < _productsCacheTtl) {
      return cached.where((p) => p.vendorID == vendorID).toList();
    }
    return takeAway
        ? getVendorProductsTakeAWay(vendorID)
        : getVendorProductsDelivery(vendorID);
  }

  Future<List<ProductModel>> getVendorProductsTakeAWay(String vendorID) async {
    // Delivery/TakeAway filters are commented out server-side; filtering is
    // done client-side in newVendorProductsScreen. Same query → share cache.
    final key = '${vendorID}_vendor_all';
    return _fetchProducts(
      key,
      firestore
          .collection(PRODUCTS)
          .where('vendorID', isEqualTo: vendorID)
          // .where('takeaway', isEqualTo: true)
          .where('publish', isEqualTo: true),
    );
  }

  Future<List<ProductModel>> getVendorProductsDelivery(String vendorID) async {
    // Same query as getVendorProductsTakeAWay → shared cache key means
    // switching order type Delivery↔DineAway costs zero extra Firestore reads.
    final key = '${vendorID}_vendor_all';
    return _fetchProducts(
      key,
      firestore
          .collection(PRODUCTS)
          .where('vendorID', isEqualTo: vendorID)
          // .where('deliveryOption', isEqualTo: true)
          .where('publish', isEqualTo: true),
    );
  }

  //  Future<List<ProductModel>> updatevendorProduct(ProductModel productModel) async {
  //   return await firestore
  //       .collection(PRODUCTS)
  //       .doc(productModel.id).collection("quentity").doc(productModel.quantity)
  //       .set(user.toJson())
  //       .then((document) {
  //     return user;
  //   });
  // }
//  static Future<VendorModel?> updateVendor(VendorModel vendor) async {
//     return await firestore
//         .collection(VENDORS)
//         .doc(vendor.id)
//         .set(vendor.toJson())
//         .then((document) {
//       return vendor;
//     });
//   }

  static Future<VendorCategoryModel?> getVendorCategoryById(String vendorCategoryID) async {
    VendorCategoryModel? vendorCategoryModel;
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore
        .collection(CATEGORIES)
        .where('id', isEqualTo: vendorCategoryID)
        .where("section_id", isEqualTo: sectionConstantModel!.id)
        .where('publish', isEqualTo: true)
        .get();
    try {
      if (vendorsQuery.docs.isNotEmpty) {
        vendorCategoryModel = VendorCategoryModel.fromJson(vendorsQuery.docs.first.data());
      }
    } catch (e) {
      print('FireStoreUtils.getVendorByVendorID Parse error $e');
    }
    return vendorCategoryModel;
  }

  // Batches newVendorProductsScreen.dart's category cache-miss fallback into
  // one query per chunk instead of one query per missing ID - same
  // document-read cost per matched category, fewer round trips. whereIn
  // caps at 30 values per Firestore's own limit; chunked defensively even
  // though a single vendor's distinct category count is realistically
  // always far below that, so this never silently drops categories if it
  // ever isn't.
  static Future<List<VendorCategoryModel>> getVendorCategoriesByIds(
      List<String> vendorCategoryIds) async {
    if (vendorCategoryIds.isEmpty) return [];
    const chunkSize = 30;
    final chunks = <List<String>>[];
    for (var i = 0; i < vendorCategoryIds.length; i += chunkSize) {
      final end = i + chunkSize < vendorCategoryIds.length
          ? i + chunkSize
          : vendorCategoryIds.length;
      chunks.add(vendorCategoryIds.sublist(i, end));
    }
    final results = await Future.wait(chunks.map((chunk) async {
      try {
        final query = await firestore
            .collection(CATEGORIES)
            .where('id', whereIn: chunk)
            .where('section_id', isEqualTo: sectionConstantModel!.id)
            .where('publish', isEqualTo: true)
            .get();
        return query.docs
            .map((d) => VendorCategoryModel.fromJson(d.data()))
            .toList();
      } catch (e) {
        print('FireStoreUtils.getVendorCategoriesByIds Parse error $e');
        return <VendorCategoryModel>[];
      }
    }));
    return results.expand((r) => r).toList();
  }

  Future<VendorCategoryModel?> getVendorCategoryByCategoryId(String vendorCategoryID) async {
    DocumentSnapshot<Map<String, dynamic>> documentReference = await firestore.collection(CATEGORIES).doc(vendorCategoryID).get();
    if (documentReference.data() != null && documentReference.exists) {
      return VendorCategoryModel.fromJson(documentReference.data()!);
    } else {
      print("nulllll");
      return null;
    }
  }

  Future<ReviewAttributeModel?> getVendorReviewAttribute(String attrubuteId) async {
    DocumentSnapshot<Map<String, dynamic>> documentReference = await firestore.collection(REVIEW_ATTRIBUTES).doc(attrubuteId).get();
    if (documentReference.data() != null && documentReference.exists) {
      return ReviewAttributeModel.fromJson(documentReference.data()!);
    } else {
      print("nulllll");
      return null;
    }
  }

  Future<VendorModel> getVendorByVendorID(String vendorID) async {
    late VendorModel vendor;
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore.collection(VENDORS).where('id', isEqualTo: vendorID).get();
    try {
      if (vendorsQuery.docs.isNotEmpty) {
        vendor = VendorModel.fromJson(vendorsQuery.docs.first.data());
      }
    } catch (e) {
      print('FireStoreUtils.getVendorByVendorID Parse error $e');
    }
    return vendor;
  }

  Future<ProductModel> getProductByProductID(String productId) async {
    late ProductModel productModel;
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore.collection(PRODUCTS).where('id', isEqualTo: productId).where('publish', isEqualTo: true).get();
    try {
      if (vendorsQuery.docs.isNotEmpty) {
        productModel = ProductModel.fromJson(vendorsQuery.docs.first.data());
      }
    } catch (e) {
      print('FireStoreUtils.getVendorByVendorID Parse error $e');
    }
    return productModel;
  }

  Future<ProductModel> getProductByID(String productId) async {
    late ProductModel productModel;
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore.collection(PRODUCTS).where('id', isEqualTo: productId).get();
    try {
      if (vendorsQuery.docs.isNotEmpty) {
        productModel = ProductModel.fromJson(vendorsQuery.docs.first.data());
      }
    } catch (e) {
      print('FireStoreUtils.getVendorByVendorID Parse error $e');
    }
    return productModel;
  }

  // Pure helper (2026-08-05, extracted for unit testing - see
  // test/services/fetch_products_by_ids_test.dart) - dedupes then splits
  // into chunks no larger than [chunkSize] (Firestore's whereIn limit,
  // default 30). No Firestore/Firebase dependency, so this is testable in
  // isolation from fetchProductsByIds' actual network calls, which this
  // project has no mocking infrastructure for.
  static List<List<String>> dedupeAndChunkIds(List<String> ids,
      {int chunkSize = 30}) {
    final uniqueIds = ids.toSet().toList();
    if (uniqueIds.isEmpty) return [];
    final chunks = <List<String>>[];
    for (var i = 0; i < uniqueIds.length; i += chunkSize) {
      final end =
          i + chunkSize > uniqueIds.length ? uniqueIds.length : i + chunkSize;
      chunks.add(uniqueIds.sublist(i, end));
    }
    return chunks;
  }

  // Batched product fetch (2026-08-05) - replaces N individual
  // getProductByID() calls (previously one per cart line, fired in
  // parallel via Future.wait but still N separate round-trips) with
  // ceil(distinct/30) `where('id', whereIn: ...)` queries, chunked to
  // Firestore's 30-value whereIn limit. IDs are deduplicated internally, so
  // two cart lines that are different variants of the SAME base product
  // (e.g. "Pizza - Large" and "Pizza - Medium", same id before the '~'
  // split) only fetch that product once instead of twice. Filters on the
  // 'id' field, not FieldPath.documentId(), to match getProductByID's own
  // existing query exactly - not assumed to always equal the document ID.
  //
  // Returns a map keyed by product id. An id with no matching document
  // (deleted product) is simply absent from the map - callers that already
  // null-check a missing entry (both existing call sites did, for
  // getProductByID's not-found-throws-then-caught-as-null behavior) need no
  // other change.
  Future<Map<String, ProductModel>> fetchProductsByIds(
      List<String> productIds) async {
    final result = <String, ProductModel>{};
    final chunks = dedupeAndChunkIds(productIds);
    if (chunks.isEmpty) return result;

    await Future.wait(chunks.map((chunk) async {
      try {
        final snapshot =
            await firestore.collection(PRODUCTS).where('id', whereIn: chunk).get();
        for (final doc in snapshot.docs) {
          try {
            final product = ProductModel.fromJson(doc.data());
            result[product.id] = product;
          } catch (e) {
            print('FireStoreUtils.fetchProductsByIds parse error $e');
          }
        }
      } catch (e) {
        print('FireStoreUtils.fetchProductsByIds chunk error $e');
      }
    }));

    return result;
  }

  Future<RatingModel?> getReviewsbyID(String ordertId) async {
    RatingModel? ratingproduct;
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore.collection(Order_Rating).where('orderid', isEqualTo: ordertId).get();
    if (vendorsQuery.docs.isNotEmpty) {
      try {
        if (vendorsQuery.docs.isNotEmpty) {
          ratingproduct = RatingModel.fromJson(vendorsQuery.docs.first.data());
        }
      } catch (e) {
        print('FireStoreUtils.getVendorByVendorID Parse error $e');
      }
    }
    return ratingproduct;
  }

  Future<RatingModel?> getReviewsbyProviderID(String ordertId, String providerId) async {
    RatingModel? ratingproduct;
    QuerySnapshot<Map<String, dynamic>> vendorsQuery =
        await firestore.collection(Order_Rating).where('orderid', isEqualTo: ordertId).where('VendorId', isEqualTo: providerId).get();
    if (vendorsQuery.docs.isNotEmpty) {
      try {
        if (vendorsQuery.docs.isNotEmpty) {
          ratingproduct = RatingModel.fromJson(vendorsQuery.docs.first.data());
        }
      } catch (e) {
        print('FireStoreUtils.getVendorByVendorID Parse error $e');
      }
    }
    return ratingproduct;
  }

  Future<RatingModel?> getReviewsbyWorkerID(String ordertId, String workerId) async {
    RatingModel? ratingproduct;
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore.collection(Order_Rating).where('orderid', isEqualTo: ordertId).where('driverId', isEqualTo: workerId).get();
    if (vendorsQuery.docs.isNotEmpty) {
      try {
        if (vendorsQuery.docs.isNotEmpty) {
          ratingproduct = RatingModel.fromJson(vendorsQuery.docs.first.data());
        }
      } catch (e) {
        print('FireStoreUtils.getVendorByVendorID Parse error $e');
      }
    }
    return ratingproduct;
  }

  Future<RatingModel?> getOrderReviewsbyID(String ordertId, String productId) async {
    RatingModel? ratingproduct;
    QuerySnapshot<Map<String, dynamic>> vendorsQuery =
        await firestore.collection(Order_Rating).where('orderid', isEqualTo: ordertId).where('productId', isEqualTo: productId).get();
    if (vendorsQuery.docs.isNotEmpty) {
      try {
        if (vendorsQuery.docs.isNotEmpty) {
          ratingproduct = RatingModel.fromJson(vendorsQuery.docs.first.data());
        }
      } catch (e) {
        print('FireStoreUtils.getVendorByVendorID Parse error $e');
      }
    }
    return ratingproduct;
  }

  // Future<RatingModel> getReviewsbyVendorID(String vendorId) async {
  //   late RatingModel ratingproduct;
  //   QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore
  //       .collection(Order_Rating)
  //       .where('VendorId', isEqualTo: vendorId)
  //       .get();
  //   try {
  //     ratingproduct = RatingModel.fromJson(vendorsQuery.docs.first.data());
  //   } catch (e) {
  //     print('FireStoreUtils.getVendorByVendorID Parse error $e');
  //   }
  //   return ratingproduct;
  // }

  Future<List<RatingModel>> getReviewsbyVendorID(String vendorId) async {
    List<RatingModel> vendorreview = [];

    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore
        .collection(Order_Rating)
        .where('VendorId', isEqualTo: vendorId)
        // .orderBy('createdAt', descending: true)
        .get();
    await Future.forEach(vendorsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        vendorreview.add(RatingModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getOrders Parse error ${document.id} $e');
      }
    });
    return vendorreview;
  }

  Future<List<RatingModel>> getReviewByDriverId(String driverId) async {
    List<RatingModel> vendorreview = [];

    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore
        .collection(Order_Rating)
        .where('driverId', isEqualTo: driverId)
        // .orderBy('createdAt', descending: true)
        .get();
    await Future.forEach(vendorsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        vendorreview.add(RatingModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getOrders Parse error ${document.id} $e');
      }
    });
    return vendorreview;
  }

  static Future<RatingModel?> updateReviewbyId(RatingModel ratingproduct) async {
    return await firestore.collection(Order_Rating).doc(ratingproduct.id).set(ratingproduct.toJson()).then((document) {
      return ratingproduct;
    });
  }

  static Future<List<FavouriteModel>> getFavouriteStore(String userId) async {
    List<FavouriteModel> favouriteItem = [];

    QuerySnapshot<Map<String, dynamic>> vendorsQuery =
        await firestore.collection(FavouriteStore).where('user_id', isEqualTo: userId).where("section_id", isEqualTo: sectionConstantModel!.id).get();
    await Future.forEach(vendorsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        favouriteItem.add(FavouriteModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getVendors Parse error $e');
      }
    });
    return favouriteItem;
  }

  Future<BookTableModel> bookTable(BookTableModel orderModel) async {
    // Respects a pre-generated id (e.g. the same one already used to key the
    // wallet payment intent for a paid booking) instead of always minting a
    // fresh one — same pattern as placeOrderWithTakeAWay.
    DocumentReference documentReference = orderModel.id.isNotEmpty
        ? firestore.collection(ORDERS_TABLE).doc(orderModel.id)
        : firestore.collection(ORDERS_TABLE).doc();
    orderModel.id = documentReference.id;
    await documentReference.set(orderModel.toJson());
    return orderModel;
  }

  // Display-only pre-check (2026-08-24, fixed - previously counted booking
  // *documents*, not guests: a party of 8 counted as "1" against slot
  // capacity, letting real overbooking through). This is no longer the
  // actual enforcement point - reserveBookingCapacity's transaction below is
  // - so a stale/wrong count here is a UX issue, not a security one.
  //
  // [slotId] omitted (or empty) sums every booking for the vendor+date
  // regardless of slot - used for a 'flexible' vendor, which has no
  // per-slot buckets at all.
  static Future<int> getBookingCountForDate({
    required String vendorId,
    String slotId = '',
    required DateTime date,
  }) async {
    // Use only equality filters (vendorID [+ slotId]) to avoid the Firestore
    // composite-index requirement that mixing equality + range filters triggers.
    // The bookingDateKey equality path is preferred for new documents; for older
    // documents that lack the field, we fall back to Timestamp comparison in Dart.
    final dateKey =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    Query<Map<String, dynamic>> query =
        firestore.collection(ORDERS_TABLE).where('vendorID', isEqualTo: vendorId);
    if (slotId.isNotEmpty) {
      query = query.where('slotId', isEqualTo: slotId);
    }
    final snapshot = await query.get();

    int occupiedGuests = 0;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = data['status'] as String? ?? '';
      if (status == 'Cancelled' || status == 'Rejected') continue;

      bool sameDate;
      final bdk = data['bookingDateKey'] as String?;
      if (bdk != null) {
        sameDate = bdk == dateKey;
      } else {
        // Legacy path: compare Timestamp stored in 'date' field
        final dateVal = data['date'];
        if (dateVal is! Timestamp) continue;
        final docDate = dateVal.toDate();
        sameDate = !docDate.isBefore(startOfDay) && docDate.isBefore(endOfDay);
      }
      if (!sameDate) continue;

      final guestVal = data['totalGuest'];
      // Legacy bookings predating totalGuest (or a corrupt value) still
      // occupy at least one seat - never let a missing field under-count.
      occupiedGuests += (guestVal is num && guestVal > 0) ? guestVal.toInt() : 1;
    }
    return occupiedGuests;
  }

  static String _capacityDocId({required String vendorId, required String bookingType, required String slotId, required String dateKey}) {
    final bucket = bookingType == 'slot_based' ? slotId : 'flexible';
    return '${vendorId}_${bucket}_$dateKey';
  }

  // Atomic reserve, closing the race window getBookingCountForDate's plain
  // read can't (two concurrent bookers could both read "room available" and
  // both write a booking). Also the first real capacity enforcement for
  // 'flexible' vendors, which previously had none at all - maxCapacity is
  // slot.maxCapacity for slot_based, vendor.guestCapacity for flexible.
  // Call BEFORE any payment - see _confirmBooking's ordering.
  static Future<void> reserveBookingCapacity({
    required String vendorId,
    required String bookingType,
    required String slotId,
    required String dateKey,
    required int guestCount,
    required int maxCapacity,
  }) async {
    final ref = firestore.collection(DINE_IN_CAPACITY).doc(
        _capacityDocId(vendorId: vendorId, bookingType: bookingType, slotId: slotId, dateKey: dateKey));
    await firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final occupied = (snap.data()?['occupiedGuests'] as num?)?.toInt() ?? 0;
      if (occupied + guestCount > maxCapacity) {
        throw SlotCapacityExceededException();
      }
      tx.set(ref, {'occupiedGuests': occupied + guestCount}, SetOptions(merge: true));
    });
  }

  // Releases a reservation made by reserveBookingCapacity - used when a
  // reservation succeeded but a later step (payment, the booking write
  // itself) failed, so the seats must go back rather than being permanently
  // stranded as "occupied" for no real booking. Safe to call even if
  // nothing was actually reserved (clamped at 0).
  static Future<void> releaseBookingCapacity({
    required String vendorId,
    required String bookingType,
    required String slotId,
    required String dateKey,
    required int guestCount,
  }) async {
    final ref = firestore.collection(DINE_IN_CAPACITY).doc(
        _capacityDocId(vendorId: vendorId, bookingType: bookingType, slotId: slotId, dateKey: dateKey));
    await firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final occupied = (snap.data()?['occupiedGuests'] as num?)?.toInt() ?? 0;
      final next = occupied - guestCount;
      tx.set(ref, {'occupiedGuests': next < 0 ? 0 : next}, SetOptions(merge: true));
    });
  }

  // Real-time seat availability vs. the vendor's own seatCapacity setting.
  // Only vendors who have explicitly set seatCapacity are included -
  // deliberately NOT the Phase-2 guestCapacity field, which always
  // defaults to 50 even for a vendor who never touched it (would silently
  // include every restaurant), and which can legitimately represent a
  // different number anyway (a vendor may reserve only some of their total
  // seats for advance bookings, leaving the rest for walk-ins - confirmed
  // with the user 2026-08-25 that these two capacities are allowed to
  // diverge).
  //
  // Reads the server-maintained dine_in_occupancy/{vendorId} aggregate
  // (2026-08-25) instead of querying vendor_orders directly - that direct
  // query (vendorID + orderType=='Dining', summing every matching order)
  // was PERMISSION_DENIED for every real customer, always: firestore.rules
  // only allows reading a vendor_orders doc if you're its authorID, the
  // vendor, staff, or admin, and an occupancy count needs every customer's
  // active order at that vendor, not just the requesting customer's own.
  // Confirmed live via logcat during an on-device test pass - the banner
  // had never actually worked in production. See functions/dineOccupancy.js
  // for the Cloud Functions trigger that keeps this aggregate in sync, and
  // for where the "occupying a seat" time-window logic that used to live
  // here (schedule-grace-window, per-order deadline) now lives instead.
  static Stream<SeatAvailability?> streamCurrentSeatAvailability(VendorModel vendor) {
    // seatAvailabilityEnabled is the admin-approval gate (2026-08-24) -
    // checked here too, not just on the vendor's own config screen, so a
    // customer stops seeing the crowding banner the instant an admin
    // revokes approval, even if seatCapacity is still sitting in Firestore.
    if (!vendor.seatAvailabilityEnabled) return Stream.value(null);
    if (vendor.seatCapacity == null || vendor.seatCapacity! <= 0) return Stream.value(null);

    return firestore.collection(DINE_IN_OCCUPANCY).doc(vendor.id).snapshots().map((doc) {
      // A vendor with no aggregate doc yet (no Dining orders ever, or the
      // trigger hasn't fired for them yet) is simply at zero occupancy -
      // not an error state, nothing to distinguish from "quiet right now".
      final occupied = doc.exists ? (doc.data()?['occupiedGuests'] as num?)?.toInt() ?? 0 : 0;
      return SeatAvailability(
        occupiedGuests: occupied,
        maxCapacity: vendor.seatCapacity!,
      );
    });
  }

  Future<OrderModel> placeOrder(OrderModel orderModel) async {
    DocumentReference documentReference = firestore.collection(ORDERS).doc(orderModel.id);
    orderModel.id = documentReference.id;
    // merge: true — if this order id was already written once (e.g. a retry
    // after an error that happened after the first write succeeded), a
    // plain overwrite would wipe server-added fields like walletCredited/
    // priceVerified, making Cloud Functions treat the order as freshly
    // completed again and pay the vendor a second time.
    await documentReference.set(orderModel.toJson(), SetOptions(merge: true));
    _trackOrderPlacedForEngagement(orderModel);
    return orderModel;
  }

  Future<OrderModel> placeOrderWithTakeAWay(OrderModel orderModel) async {
    DocumentReference documentReference;
    if (orderModel.id.isEmpty) {
      documentReference = firestore.collection(ORDERS).doc();
      orderModel.id = documentReference.id;
    } else {
      documentReference = firestore.collection(ORDERS).doc(orderModel.id);
    }
    // merge: true — see placeOrder() above; PlaceOrderScreen's "Try Again"
    // re-runs this exact write with the same order id if anything throws
    // after the first write already succeeded (e.g. the stock-update step
    // below), so this must not clobber server-added fields on retry.
    await documentReference.set(orderModel.toJson(), SetOptions(merge: true));
    _trackOrderPlacedForEngagement(orderModel);
    return orderModel;
  }

  // Restaurant Engagement / Search Conversion / Banner Analytics
  // "order placed" signal (Phase 2, 2026-07-24, collection-only) - the
  // single choke point both placeOrder() and placeOrderWithTakeAWay() above
  // funnel through, so CheckoutScreen/PaymentScreen/PlaceOrderScreen never
  // need to duplicate this call themselves. Gated on analyticsSnapshot
  // being present (not every order-creation path builds one, e.g. Bill Pay)
  // and fires only when restaurantSessionId/reachedViaBannerId actually
  // resolved to something - see BehaviorTracker._addRestaurantEngagementWrites/
  // _addBannerAnalyticsWrites for where this lands. Deliberately a
  // DIFFERENT event from kEvtOrderCompleted - see
  // kEvtOrderPlacedForEngagement's own doc comment for why a placed order
  // is not yet a completed one.
  void _trackOrderPlacedForEngagement(OrderModel orderModel) {
    final snapshot = orderModel.analyticsSnapshot;
    if (snapshot == null) return;
    BehaviorTracker.track(kEvtOrderPlacedForEngagement, {
      'orderId': orderModel.id,
      'vendorId': orderModel.vendorID,
      'amount': (snapshot['totalAmount'] as num?) ?? 0,
      'restaurantSessionId': (snapshot['restaurantSessionId'] ?? '').toString(),
      'reachedViaBannerId': (snapshot['reachedViaBannerId'] ?? '').toString(),
    });
  }

  static Future<List<TopupTranHistoryModel>> getTopUpTransaction() async {
    final userId = MyAppState.currentUser!.userID; //UserPreference.getUserId();
    List<TopupTranHistoryModel> topUpHistoryList = [];
    QuerySnapshot<Map<String, dynamic>> documentReference = await firestore.collection(Wallet).where('user_id', isEqualTo: userId).orderBy('date', descending: true).limit(20).get();
    await Future.forEach(documentReference.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        topUpHistoryList.add(TopupTranHistoryModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getAllProducts Parse error $e');
      }
    });
    // QuerySnapshot<Map<String, dynamic>> productsQuery = await firestore.collection(Wallet).get();
    // await Future.forEach(productsQuery.docs,
    //         (QueryDocumentSnapshot<Map<String, dynamic>> document) {
    //       try {
    //         products.add(TopupTranHistoryModel.fromJson(document.data()));
    //       } catch (e) {
    //         print('FireStoreUtils.getAllProducts Parse error $e');
    //       }
    //     });

    // final paymentId = documentReference;
    // UserPreference.setPaymentId(paymentId: paymentId);
    return topUpHistoryList;
  }

  // static Future topUpWalletAmount({String serviceType = "", String paymentMethod = "test", bool isTopup = true, required amount, required id, orderId = ""}) async {
  //   print("this is te payment id");
  //   print(id);
  //   print(MyAppState.currentUser!.userID);
  //
  //   await firestore.collection(Wallet).doc(id).set({
  //     "serviceType": serviceType,
  //     "user_id": MyAppState.currentUser!.userID,
  //     "payment_method": paymentMethod,
  //     "amount": amount,
  //     "id": id,
  //     "order_id": orderId,
  //     "isTopUp": isTopup,
  //     "payment_status": "success",
  //     "date": DateTime.now(),
  //   }).then((value) {
  //     firestore.collection(Wallet).doc(id).get().then((value) {
  //       DocumentSnapshot<Map<String, dynamic>> documentData = value;
  //       print("nato");
  //       print(documentData.data());
  //     });
  //   });
  //
  //   return "updated Amount".tr();
  // }

  static Future topUpOtherWalletAmount({required String userId, String paymentMethod = "test", bool isTopup = true, required amount, required id, orderId = ""}) async {
    TopupTranHistoryModel adminCommission = TopupTranHistoryModel(
        amount: amount,
        id: Uuid().v4(),
        order_id: orderId,
        user_id: userId,
        date: Timestamp.now(),
        isTopup: true,
        payment_method: "Wallet",
        payment_status: "success",
        transactionUser: "customer",
        note: paymentMethod,
        serviceType: 'ondemand-service');

    await firestore.collection("wallet").doc(id).set(adminCommission.toJson()).then((value) {
      firestore.collection("wallet").doc(id).get().then((value) {
        DocumentSnapshot<Map<String, dynamic>> documentData = value;
        print("nato");
        print(documentData.data());
      });
    });
    return "updated Amount".tr();
  }

  static Future updateOtherWalletAmount({required String userId, required amount}) async {
    try {
      // Atomic increment — no read needed, eliminates double-spend race condition.
      await firestore.collection(USERS).doc(userId).update({
        "wallet_amount": FieldValue.increment(double.parse(amount.toString())),
      });
    } catch (error) {
      print('updateOtherWalletAmount error: $error');
    }
  }

  static Future updateWalletAmount({required amount}) async {
    final userId = MyAppState.currentUser!.userID;
    try {
      // Atomic increment — no read-before-write, eliminates double-spend race.
      // Pass a negative amount to deduct (e.g. amount = -orderTotal).
      await firestore.collection(USERS).doc(userId).update({
        "wallet_amount": FieldValue.increment(double.parse(amount.toString())),
      });
      // Re-read to sync local state with the server-committed balance.
      final updated = await firestore.collection(USERS).doc(userId).get();
      if (updated.data() != null) {
        MyAppState.currentUser = User.fromJson(updated.data()!);
      }
    } catch (error) {
      print('updateWalletAmount error: $error');
    }
  }

  static sendTopUpMail({required String amount, required String paymentMethod, required String tractionId}) async {
    EmailTemplateModel? emailTemplateModel = await FireStoreUtils.getEmailTemplates(walletTopup);

    String newString = emailTemplateModel!.message.toString();
    newString = newString.replaceAll("{username}", MyAppState.currentUser!.firstName + " " + MyAppState.currentUser!.lastName);
    newString = newString.replaceAll("{date}", DateFormat('dd-MM-yyyy').format(Timestamp.now().toDate()));
    newString = newString.replaceAll("{amount}", amountShow(amount: amount));
    newString = newString.replaceAll("{paymentmethod}", paymentMethod.toString());
    newString = newString.replaceAll("{transactionid}", tractionId.toString());
    newString = newString.replaceAll("{newwalletbalance}.", amountShow(amount: MyAppState.currentUser!.wallet_amount.toString()));
    await sendMail(subject: emailTemplateModel.subject, isAdmin: emailTemplateModel.isSendToAdmin, body: newString, recipients: [MyAppState.currentUser!.email]);
  }

  static sendOrderEmail({required OrderModel orderModel}) async {
    String firstHTML = """
       <table style="width: 100%; border-collapse: collapse; border: 1px solid rgb(0, 0, 0);">
    <thead>
        <tr>
            <th style="text-align: left; border: 1px solid rgb(0, 0, 0);">Product Name<br></th>
            <th style="text-align: left; border: 1px solid rgb(0, 0, 0);">Quantity<br></th>
            <th style="text-align: left; border: 1px solid rgb(0, 0, 0);">Price<br></th>
            <th style="text-align: left; border: 1px solid rgb(0, 0, 0);">Extra Item Price<br></th>
            <th style="text-align: left; border: 1px solid rgb(0, 0, 0);">Total<br></th>
        </tr>
    </thead>
    <tbody>
    """;

    EmailTemplateModel? emailTemplateModel = await FireStoreUtils.getEmailTemplates(newOrderPlaced);

    String newString = emailTemplateModel!.message.toString();
    newString = newString.replaceAll("{username}", MyAppState.currentUser!.firstName + " " + MyAppState.currentUser!.lastName);
    newString = newString.replaceAll("{orderid}", orderModel.id);
    newString = newString.replaceAll("{date}", DateFormat('dd-MM-yyyy').format(orderModel.createdAt.toDate()));
    newString = newString.replaceAll(
      "{address}",
      '${orderModel.address!.getFullAddress()}',
    );
    newString = newString.replaceAll(
      "{paymentmethod}",
      orderModel.payment_method,
    );

    double deliveryCharge = 0.0;
    double total = 0.0;
    double specialDiscount = 0.0;
    double discount = 0.0;
    double taxAmount = 0.0;
    double tipValue = 0.0;
    String specialLabel = '';
    if (orderModel.specialDiscount != null && orderModel.specialDiscount!.isNotEmpty) {
      specialLabel = '(${orderModel.specialDiscount!['special_discount_label']}${orderModel.specialDiscount!['specialType'] == "amount" ? currencyData!.symbol : "%"})';
    }
    List<String> htmlList = [];

    if (orderModel.deliveryCharge != null) {
      deliveryCharge = double.parse(orderModel.deliveryCharge.toString());
    }
    if (orderModel.tipValue != null) {
      tipValue = double.parse(orderModel.tipValue.toString());
    }
    orderModel.products.forEach((element) {
      if (element.extras_price != null && element.extras_price!.isNotEmpty && double.parse(element.extras_price!) != 0.0) {
        total += element.quantity * double.parse(element.extras_price!);
      }
      total += element.quantity * double.parse(element.price);

      List<dynamic>? addon = element.extras;
      String extrasDisVal = '';
      for (int i = 0; i < addon!.length; i++) {
        extrasDisVal += '${addon[i].toString().replaceAll("\"", "")} ${(i == addon.length - 1) ? "" : ","}';
      }
      String product = """
        <tr>
            <td style="width: 20%; border-top: 1px solid rgb(0, 0, 0);">${element.name}</td>
            <td style="width: 20%; border: 1px solid rgb(0, 0, 0);" rowspan="2">${element.quantity}</td>
            <td style="width: 20%; border: 1px solid rgb(0, 0, 0);" rowspan="2">${amountShow(amount: element.price.toString())}</td>
            <td style="width: 20%; border: 1px solid rgb(0, 0, 0);" rowspan="2">${amountShow(amount: element.extras_price.toString())}</td>
            <td style="width: 20%; border: 1px solid rgb(0, 0, 0);" rowspan="2">${amountShow(amount: ((element.quantity * double.parse(element.extras_price!) + (element.quantity * double.parse(element.price)))).toString())}</td>
        </tr>
        <tr>
            <td style="width: 20%;">${extrasDisVal.isEmpty ? "" : "Extra Item : $extrasDisVal"}</td>
        </tr>
    """;
      htmlList.add(product);
    });

    if (orderModel.specialDiscount!.isNotEmpty) {
      specialDiscount = double.parse(orderModel.specialDiscount!['special_discount'].toString());
    }

    if (orderModel.couponId != null && orderModel.couponId!.isNotEmpty) {
      discount = double.parse(orderModel.discount.toString());
    }

    List<String> taxHtmlList = [];
    if (taxList != null) {
      for (var element in taxList!) {
        taxAmount = taxAmount + getTaxValue(amount: (total - discount - specialDiscount).toString(), taxModel: element);
        String taxHtml =
            """<span style="font-size: 1rem;">${element.title}: ${amountShow(amount: getTaxValue(amount: (total - discount - specialDiscount).toString(), taxModel: element).toString())}${taxList!.indexOf(element) == taxList!.length - 1 ? "</span>" : "<br></span>"}""";
        taxHtmlList.add(taxHtml);
      }
    }

    var totalamount = orderModel.deliveryCharge == null || orderModel.deliveryCharge!.isEmpty
        ? total + taxAmount - discount - specialDiscount
        : total + taxAmount + double.parse(orderModel.deliveryCharge!) + double.parse(orderModel.tipValue!) - discount - specialDiscount;

    newString = newString.replaceAll("{subtotal}", amountShow(amount: total.toString()));
    newString = newString.replaceAll("{coupon}", '(${orderModel.couponCode.toString()})');
    newString = newString.replaceAll("{discountamount}", amountShow(amount: orderModel.discount.toString()));
    newString = newString.replaceAll("{specialcoupon}", specialLabel);
    newString = newString.replaceAll("{specialdiscountamount}", amountShow(amount: specialDiscount.toString()));
    newString = newString.replaceAll("{shippingcharge}", amountShow(amount: deliveryCharge.toString()));
    newString = newString.replaceAll("{tipamount}", amountShow(amount: tipValue.toString()));
    newString = newString.replaceAll("{totalAmount}", amountShow(amount: totalamount.toString()));

    String tableHTML = htmlList.join();
    String lastHTML = "</tbody></table>";
    newString = newString.replaceAll("{productdetails}", firstHTML + tableHTML + lastHTML);
    newString = newString.replaceAll("{taxdetails}", taxHtmlList.join());
    newString = newString.replaceAll("{newwalletbalance}.", amountShow(amount: MyAppState.currentUser!.wallet_amount.toString()));

    String subjectNewString = emailTemplateModel.subject.toString();
    subjectNewString = subjectNewString.replaceAll("{orderid}", orderModel.id);
    await sendMail(subject: subjectNewString, isAdmin: emailTemplateModel.isSendToAdmin, body: newString, recipients: [MyAppState.currentUser!.email]);
  }

  static sendRideBookEmail({required CabOrderModel? orderModel}) async {
    EmailTemplateModel? emailTemplateModel = await FireStoreUtils.getEmailTemplates(newRideBook);

    var dt = DateTime.fromMillisecondsSinceEpoch(orderModel!.createdAt.seconds * 1000);

    String newString = emailTemplateModel!.message.toString();
    newString = newString.replaceAll("{passengername}", MyAppState.currentUser!.firstName + " " + MyAppState.currentUser!.lastName);
    newString = newString.replaceAll("{rideid}", orderModel.id);
    newString = newString.replaceAll("{date}", DateFormat('dd-MM-yyyy').format(orderModel.createdAt.toDate()));
    newString = newString.replaceAll("{time}", DateFormat("hh:mm:ss a").format(dt));
    newString = newString.replaceAll(
      "{pickuplocation}",
      orderModel.sourceLocationName.toString(),
    );
    newString = newString.replaceAll(
      "{dropofflocation}",
      orderModel.destinationLocationName.toString(),
    );
    newString = newString.replaceAll(
      "{drivername}",
      orderModel.driver!.firstName.toString() + orderModel.driver!.lastName.toString(),
    );
    newString = newString.replaceAll(
      "{vehicle}",
      orderModel.driver!.carName.toString(),
    );
    newString = newString.replaceAll(
      "{carnumber}",
      orderModel.driver!.carNumber.toString(),
    );
    newString = newString.replaceAll(
      "{driverphone}",
      orderModel.driver!.phoneNumber.toString(),
    );

    String subjectNewString = emailTemplateModel.subject.toString();
    subjectNewString = subjectNewString.replaceAll("{orderid}", orderModel.id);
    await sendMail(subject: subjectNewString, isAdmin: emailTemplateModel.isSendToAdmin, body: newString, recipients: [MyAppState.currentUser!.email]);
  }

  static Future<EmailTemplateModel?> getEmailTemplates(String type) async {
    EmailTemplateModel? emailTemplateModel;
    await firestore.collection(emailTemplates).where('type', isEqualTo: type).get().then((value) {
      if (value.docs.isNotEmpty) {
        emailTemplateModel = EmailTemplateModel.fromJson(value.docs.first.data());
      }
    });
    return emailTemplateModel;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchOrderStatus(String orderID) async* {
    yield* firestore.collection(ORDERS).doc(orderID).snapshots();
  }

  /// compress image file to make it load faster but with lower quality,
  /// change the quality parameter to control the quality of the image after
  /// being compressed(100 = max quality - 0 = low quality)
  /// @param file the image file that will be compressed
  /// @return File a new compressed file with smaller size
  Future<File> _compressVideo(File file) async => file;


  /// save a new user document in the USERS table in firebase firestore
  /// returns an error message on failure or null on success
  static Future<String?> firebaseCreateNewUser(User user, String referralCode) async {
    try {
      if (referralCode.isNotEmpty) {
        FireStoreUtils.getReferralUserByCode(referralCode.toString()).then((value) async {
          if (value != null) {
            ReferralModel ownReferralModel = ReferralModel(id: user.userID, referralBy: value.id, referralCode: getReferralCode());
            await referralAdd(ownReferralModel);
          } else {
            ReferralModel referralModel = ReferralModel(id: user.userID, referralBy: "", referralCode: getReferralCode());
            await referralAdd(referralModel);
          }
        });
      } else {
        ReferralModel referralModel = ReferralModel(id: user.userID, referralBy: "", referralCode: getReferralCode());
        await referralAdd(referralModel);
      }

      await firestore.collection(USERS).doc(user.userID).set(user.toJson());
    } catch (e, s) {
      print('FireStoreUtils.firebaseCreateNewUser $e $s');
      return "notSignUp".tr();
    }
    return null;
  }

  static Future<String?> referralAdd(ReferralModel ratingModel) async {
    try {
      await firestore.collection(REFERRAL).doc(ratingModel.id).set(ratingModel.toJson());
    } catch (e, s) {
      print('FireStoreUtils.firebaseCreateNewUser $e $s');
      return 'Couldn\'t review'.tr();
    }
    return null;
  }

  /// login with email and password with firebase
  /// @param email user email
  /// @param password user password
  static Future<dynamic> loginWithEmailAndPassword(String email, String password) async {
    try {
      print('FireStoreUtils.loginWithEmailAndPassword');
      auth.UserCredential result = await auth.FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      // result.user.
      DocumentSnapshot<Map<String, dynamic>> documentSnapshot = await firestore.collection(USERS).doc(result.user?.uid ?? '').get();
      User? user;

      if (documentSnapshot.exists) {
        // if(user!.role != 'vendor'){
        user = User.fromJson(documentSnapshot.data() ?? {});
        // if(  USER_ROLE_CUSTOMER ==user.role)
        // {
        user.fcmToken = await firebaseMessaging.getToken() ?? '';

        //user.active = true;

        //      }
      }
      return user;
    } on auth.FirebaseAuthException catch (exception, s) {
      print(exception.toString() + '$s');
      print(exception.toString() + '${exception.code.toString()}');
      switch ((exception).code) {
        case 'invalid-email':
          return "Email address is malformed.".tr();
        case 'wrong-password':
          return 'Wrong password.'.tr();
        case 'user-not-found':
          return 'No user corresponding to the given email address.'.tr();
        case 'user-disabled':
          return 'This user has been disabled.'.tr();
        case 'too-many-requests':
          return 'Too many attempts to sign in as this user.'.tr();
      }
      return 'Unexpected firebase error, Please try again.'.tr();
    } catch (e, s) {
      print(e.toString() + '$s');
      return 'Login failed, Please try again.'.tr();
    }
  }

  ///submit a phone number to firebase to receive a code verification, will
  ///be used later to login
  static firebaseSubmitPhoneNumber(
    String phoneNumber,
    auth.PhoneCodeAutoRetrievalTimeout? phoneCodeAutoRetrievalTimeout,
    auth.PhoneCodeSent? phoneCodeSent,
    auth.PhoneVerificationFailed? phoneVerificationFailed,
    auth.PhoneVerificationCompleted? phoneVerificationCompleted,
  ) {
    auth.FirebaseAuth.instance.verifyPhoneNumber(
      timeout: const Duration(minutes: 2),
      phoneNumber: phoneNumber,
      verificationCompleted: phoneVerificationCompleted!,
      verificationFailed: phoneVerificationFailed!,
      codeSent: phoneCodeSent!,
      codeAutoRetrievalTimeout: phoneCodeAutoRetrievalTimeout!,
    );
  }

  /// submit the received code to firebase to complete the phone number
  /// verification process
  static Future<dynamic> firebaseSubmitPhoneNumberCode(String verificationID, String code, String phoneNumber,
      {String firstName = 'Anonymous', String lastName = 'User', File? image, String referralCode = ''}) async {
    auth.AuthCredential authCredential = auth.PhoneAuthProvider.credential(verificationId: verificationID, smsCode: code);
    auth.UserCredential userCredential = await auth.FirebaseAuth.instance.signInWithCredential(authCredential);
    User? user = await getCurrentUser(userCredential.user?.uid ?? '');
    if (user != null && user.role == USER_ROLE_CUSTOMER) {
      user.fcmToken = await firebaseMessaging.getToken() ?? '';
      user.role = USER_ROLE_CUSTOMER;
      //user.active = true;
      await updateCurrentUser(user);
      return user;
    } else if (user == null) {
      /// create a new user from phone login
      String profileImageUrl = '';
      if (image != null) {
        profileImageUrl = await uploadUserImageToFireStorage(image, userCredential.user?.uid ?? '');
      }
      User user = User(
        firstName: firstName,
        lastName: lastName,
        fcmToken: await firebaseMessaging.getToken() ?? '',
        phoneNumber: phoneNumber,
        profilePictureURL: profileImageUrl,
        userID: userCredential.user?.uid ?? '',
        role: USER_ROLE_CUSTOMER,
        active: true,
        lastOnlineTimestamp: Timestamp.now(),
        settings: UserSettings(),
        email: '',
      );
      String? errorMessage = await firebaseCreateNewUser(user, referralCode);
      if (errorMessage == null) {
        return user;
      } else {
        return 'Couldn\'t create new user with phone number.'.tr();
      }
    }
  }

  static firebaseSignUpWithEmailAndPassword(String emailAddress, String password, File? image, String firstName, String lastName, String mobile, String referralCode) async {
    try {
      auth.UserCredential result = await auth.FirebaseAuth.instance.createUserWithEmailAndPassword(email: emailAddress, password: password);
      String profilePicUrl = '';
      if (image != null) {
        profilePicUrl = await uploadUserImageToFireStorage(image, result.user?.uid ?? '');
      }
      User user = User(
          email: emailAddress,
          settings: UserSettings(),
          lastOnlineTimestamp: Timestamp.now(),
          active: true,
          phoneNumber: mobile,
          firstName: firstName,
          role: USER_ROLE_CUSTOMER,
          userID: result.user?.uid ?? '',
          lastName: lastName,
          fcmToken: await firebaseMessaging.getToken() ?? '',
          createdAt: Timestamp.now(),
          profilePictureURL: profilePicUrl);
      String? errorMessage = await firebaseCreateNewUser(user, referralCode);
      if (errorMessage == null) {
        return user;
      } else {
        return 'Couldn\'t sign up for firebase, Please try again.';
      }
    } on auth.FirebaseAuthException catch (error) {
      print(error.toString() + '${error.stackTrace}');
      String message = 'Couldn\'t sign up'.tr();
      switch (error.code) {
        case 'email-already-in-use':
          message = 'Email already in use, Please pick another email!'.tr();
          break;
        case 'invalid-email':
          message = 'Enter valid e-mail'.tr();
          break;
        case 'operation-not-allowed':
          message = 'Email/password accounts are not enabled'.tr();
          break;
        case 'weak-password':
          message = 'Password must be more than 5 characters'.tr();
          break;
        case 'too-many-requests':
          message = 'Too many requests, Please try again later.'.tr();
          break;
      }
      return message;
    } catch (e) {
      return 'Couldn\'t sign up';
    }
  }

  static Future<auth.UserCredential?> reAuthUser(AuthProviders provider,
      {String? email, String? password, String? smsCode, String? verificationId}) async {
    late auth.AuthCredential credential;
    switch (provider) {
      case AuthProviders.PASSWORD:
        credential = auth.EmailAuthProvider.credential(email: email!, password: password!);
        break;
      case AuthProviders.PHONE:
        credential = auth.PhoneAuthProvider.credential(smsCode: smsCode!, verificationId: verificationId!);
        break;
    }
    return await auth.FirebaseAuth.instance.currentUser!.reauthenticateWithCredential(credential);
  }

  static resetPassword(String emailAddress) async => await auth.FirebaseAuth.instance.sendPasswordResetEmail(email: emailAddress);

  static deleteUser() async {
    try {
      await firestore.collection(USERS).doc(auth.FirebaseAuth.instance.currentUser!.uid).delete();

      await auth.FirebaseAuth.instance.currentUser!.delete();
    } catch (e, s) {
      print('FireStoreUtils.deleteUser $e $s');
    }
  }

  Future<OrderModel?> getOrderById(String? orderId) async {
    DocumentSnapshot<Map<String, dynamic>> userDocument = await firestore.collection(ORDERS).doc(orderId).get();
    if (userDocument.data() != null && userDocument.exists) {
      return OrderModel.fromJson(userDocument.data()!);
    } else {
      return null;
    }
  }

  getContactUs() async {
    Map<String, dynamic> contactData = {};
    await firestore.collection(Setting).doc(CONTACT_US).get().then((value) {
      if (value.exists && value.data() != null) contactData = value.data()!;
    });

    return contactData;
  }

  Future<GiftCardsOrderModel> placeGiftCardOrder(GiftCardsOrderModel giftCardsOrderModel) async {
    await firestore.collection(GIFT_PURCHASES).doc(giftCardsOrderModel.id).set(giftCardsOrderModel.toJson());
    return giftCardsOrderModel;
  }

  Future<List<GiftCardsOrderModel>> getGiftHistory() async {
    List<GiftCardsOrderModel> giftCardsOrderList = [];
    await firestore.collection(GIFT_PURCHASES).where("userid", isEqualTo: MyAppState.currentUser!.userID).get().then((value) {
      for (var element in value.docs) {
        GiftCardsOrderModel giftCardsOrderModel = GiftCardsOrderModel.fromJson(element.data());
        giftCardsOrderList.add(giftCardsOrderModel);
      }
    });
    return giftCardsOrderList;
  }

  Future<GiftCardsOrderModel?> checkRedeemCode(String giftCode) async {
    GiftCardsOrderModel? giftCardsOrderModel;
    await firestore.collection(GIFT_PURCHASES).where("giftCode", isEqualTo: giftCode).get().then((value) {
      if (value.docs.isNotEmpty) {
        giftCardsOrderModel = GiftCardsOrderModel.fromJson(value.docs.first.data());
      }
    });
    return giftCardsOrderModel;
  }

  static Future<List<GiftCardsModel>> getGiftCard() async {
    List<GiftCardsModel> giftCardModelList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(GIFT_CARDS).where("isEnable", isEqualTo: true).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        log(document.data().toString());
        giftCardModelList.add(GiftCardsModel.fromJson(document.data()));
      } catch (e) {
        debugPrint('FireStoreUtils.get Currency Parse error $e');
      }
    });
    return giftCardModelList;
  }

  Future<List<RatingModel>> getReviewByProviderServiceId(String serviceId) async {
    List<RatingModel> providerReview = [];

    QuerySnapshot<Map<String, dynamic>> reviewQuery = await firestore.collection(Order_Rating).where('productId', isEqualTo: serviceId).get();
    await Future.forEach(reviewQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      print(document);
      try {
        providerReview.add(RatingModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getReviewByProviderServiceId Parse error ${document.id} $e');
      }
    });
    return providerReview;
  }

  static Future addProviderInbox(InboxModel inboxModel) async {
    return await firestore.collection("chat_provider").doc(inboxModel.orderId).set(inboxModel.toJson()).then((document) {
      return inboxModel;
    });
  }

  static Future addProviderChat(ConversationModel conversationModel) async {
    return await firestore
        .collection("chat_provider")
        .doc(conversationModel.orderId)
        .collection("thread")
        .doc(conversationModel.id)
        .set(conversationModel.toJson())
        .then((document) {
      return conversationModel;
    });
  }

  static Future addWorkerInbox(InboxModel inboxModel) async {
    return await firestore.collection("chat_worker").doc(inboxModel.orderId).set(inboxModel.toJson()).then((document) {
      return inboxModel;
    });
  }

  static Future addWorkerChat(ConversationModel conversationModel) async {
    return await firestore.collection("chat_worker").doc(conversationModel.orderId).collection("thread").doc(conversationModel.id).set(conversationModel.toJson()).then((document) {
      return conversationModel;
    });
  }

  static Future<List<RatingModel>> getVendorReviews(String vendorId) async {
    List<RatingModel> ratingList = [];
    await firestore.collection(Order_Rating).where('VendorId', isEqualTo: vendorId).limit(20).get().then((value) {
      for (var element in value.docs) {
        RatingModel giftCardsOrderModel = RatingModel.fromJson(element.data());
        ratingList.add(giftCardsOrderModel);
      }
    });
    return ratingList;
  }

  /// Paginated vendor reviews. Pass [lastDoc] to fetch the next page.
  static Future<(List<RatingModel>, DocumentSnapshot?)> getVendorReviewsPaginated(
    String vendorId, {
    DocumentSnapshot? lastDoc,
    int limit = 20,
  }) async {
    // orderBy(createdAt) - the review's own submission timestamp (set via
    // Timestamp.now() at the moment the customer submits it in
    // OrderRatingScreen.dart), not the underlying order's date. There was
    // previously no orderBy at all here, so results came back in whatever
    // arbitrary order Firestore happened to return them in.
    Query<Map<String, dynamic>> query = firestore
        .collection(Order_Rating)
        .where('VendorId', isEqualTo: vendorId)
        .orderBy('createdAt', descending: true)
        .limit(limit);
    if (lastDoc != null) query = query.startAfterDocument(lastDoc);
    final snapshot = await query.get();
    final models = snapshot.docs
        .map((d) {
          try {
            return RatingModel.fromJson(d.data());
          } catch (_) {
            return null;
          }
        })
        .whereType<RatingModel>()
        .toList();
    final next = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
    return (models, next);
  }

}
