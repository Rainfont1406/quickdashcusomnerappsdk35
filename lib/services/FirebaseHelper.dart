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
import 'package:emartconsumer/services/helper.dart';
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
  // is a slow-changing 30-day rolling aggregate, so a short cache avoids
  // re-querying the dailyProductSales subcollection for the same vendor on
  // every live vendor-list update (cards rebuild often; sales data doesn't
  // change minute to minute). Cleared naturally on app restart.
  static final Map<String, (Future<Map<String, int>>, DateTime)>
      _rollingSalesCache = {};
  static const Duration _rollingSalesCacheTtl = Duration(minutes: 10);

  /// Sums a vendor's per-product delivery sales over the last 30 daily
  /// buckets (written by the vendor app at order-completion time — see
  /// FireStoreUtils.updateOrder there). Returns {productId: unitsSold},
  /// empty if the vendor has no sales data yet.
  static Future<Map<String, int>> getRolling30DaySales(String vendorId) {
    final cached = _rollingSalesCache[vendorId];
    if (cached != null &&
        DateTime.now().difference(cached.$2) < _rollingSalesCacheTtl) {
      return cached.$1;
    }
    final future = _fetchRolling30DaySales(vendorId);
    _rollingSalesCache[vendorId] = (future, DateTime.now());
    return future;
  }

  static Future<Map<String, int>> _fetchRolling30DaySales(
      String vendorId) async {
    final Map<String, int> totals = {};
    try {
      final snapshot = await firestore
          .collection(VENDORS)
          .doc(vendorId)
          .collection('dailyProductSales')
          .get();
      for (final doc in snapshot.docs) {
        final products = doc.data()['products'] as Map<String, dynamic>?;
        if (products == null) continue;
        products.forEach((productId, count) {
          final n = (count as num?)?.toInt() ?? 0;
          totals[productId] = (totals[productId] ?? 0) + n;
        });
      }
    } catch (_) {}
    return totals;
  }

  /// Up to [max] products to show in a vendor's delivery-card carousel.
  /// Priority: rolling-30-day sales ranking → best-discounted products →
  /// lowest-priced products. [vendorProducts] should already be filtered to
  /// this vendor's published, delivery-enabled products.
  static Future<List<ProductModel>> getCarouselProducts(
      String vendorId, List<ProductModel> vendorProducts,
      {int max = 5}) async {
    if (vendorProducts.isEmpty) return [];

    final salesCounts = await getRolling30DaySales(vendorId);
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

  static Future<VendorModel?> updateVendor(VendorModel vendor) async {
    return await firestore.collection(VENDORS).doc(vendor.id).set(vendor.toJson()).then((document) {
      return vendor;
    });
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
    // ignore: close_sinks
    firestore.collection(Setting).doc("razorpaySettings").get().then((user) {
      try {
        RazorPayModel userModel = RazorPayModel.fromJson(user.data() ?? {});
        UserPreference.setRazorPayData(userModel);
      } catch (e) {
        print('FireStoreUtils.getUserByID failed to parse user object ${user.id}');
      }
    });
  }

  static getPayFastSettingData() async {
    firestore.collection(Setting).doc("payFastSettings").get().then((payFastData) {
      try {
        PayFastSettingData payFastSettingData = PayFastSettingData.fromJson(payFastData.data() ?? {});
        UserPreference.setPayFastData(payFastSettingData);
      } catch (error) {
        print(error.toString());
      }
    });
  }

  static getPaypalSettingData() async {
    firestore.collection(Setting).doc("paypalSettings").get().then((paypalData) {
      try {
        PaypalSettingData payplaDataModel = PaypalSettingData.fromJson(paypalData.data() ?? {});
        UserPreference.setPayPalData(payplaDataModel);
      } catch (error) {
        print(error.toString());
      }
    });
  }

  static getMercadoPagoSettingData() async {
    firestore.collection(Setting).doc("MercadoPago").get().then((mercadoPago) {
      try {
        MercadoPagoSettingData mercadoPagoDataModel = MercadoPagoSettingData.fromJson(mercadoPago.data() ?? {});
        UserPreference.setMercadoPago(mercadoPagoDataModel);
      } catch (error) {
        print(error.toString());
      }
    });
  }

  static getStripeSettingData() async {
    firestore.collection(Setting).doc("stripeSettings").get().then((stripeData) {
      try {
        StripeSettingData stripeSettingData = StripeSettingData.fromJson(stripeData.data() ?? {});
        UserPreference.setStripeData(stripeSettingData);
      } catch (error) {
        print(error.toString());
      }
    });
  }

  static getFlutterWaveSettingData() async {
    firestore.collection(Setting).doc("flutterWave").get().then((flutterWaveData) {
      try {
        FlutterWaveSettingData flutterWaveSettingData = FlutterWaveSettingData.fromJson(flutterWaveData.data() ?? {});

        UserPreference.setFlutterWaveData(flutterWaveSettingData);
      } catch (error) {}
    });
  }

  static getPayStackSettingData() async {
    firestore.collection(Setting).doc("payStack").get().then((payStackData) {
      try {
        PayStackSettingData payStackSettingData = PayStackSettingData.fromJson(payStackData.data() ?? {});
        UserPreference.setPayStackData(payStackSettingData);
      } catch (error) {
        print(error.toString());
      }
    });
  }


  static getOrangeMoneySettingData() async {
    firestore.collection(Setting).doc("orange_money_settings").get().then((payStackData) {
      try {
        OrangeMoney payStackSettingData = OrangeMoney.fromJson(payStackData.data() ?? {});
        UserPreference.setOrangeData(payStackSettingData);
      } catch (error) {
        print(error.toString());
      }
    });
  }

  static getXenditSettingData() async {
    firestore.collection(Setting).doc("xendit_settings").get().then((payStackData) {
      try {
        Xendit payStackSettingData = Xendit.fromJson(payStackData.data() ?? {});

        UserPreference.setXenditData(payStackSettingData);
      } catch (error) {
        print(error.toString());
      }
    });
  }

  static getMidTransSettingData() async {
    firestore.collection(Setting).doc("midtrans_settings").get().then((payStackData) {
      try {
        MidTrans payStackSettingData = MidTrans.fromJson(payStackData.data() ?? {});
        UserPreference.setMidTransData(payStackSettingData);
      } catch (error) {
        print(error.toString());
      }
    });
  }

  static getPhonePaySettingData() async {
    firestore.collection(Setting).doc("phonepe_settings").get().then((data) {
      try {
        PhonePaySettingData settingData = PhonePaySettingData.fromJson(data.data() ?? {});
        UserPreference.setPhonePayData(settingData);
      } catch (error) {
        print(error.toString());
      }
    });
  }

  static getPaytmSettingData() async {
    firestore.collection(Setting).doc("PaytmSettings").get().then((paytmData) {
      try {
        PaytmSettingData paytmSettingData = PaytmSettingData.fromJson(paytmData.data() ?? {});
        UserPreference.setPaytmData(paytmSettingData);
      } catch (error) {
        print(error.toString());
      }
    });
  }

  static getWalletSettingData() {
    firestore.collection(Setting).doc('walletSettings').get().then((walletSetting) {
      try {
        bool walletEnable = walletSetting.data()!['isEnabled'];
        UserPreference.setWalletData(walletEnable);
      } catch (e) {
        print(e.toString());
      }
    });
  }

  static getRazorPayDemo() async {
    RazorPayModel userModel;
    firestore.collection(Setting).doc("razorpaySettings").get().then((user) {
      try {
        userModel = RazorPayModel.fromJson(user.data() ?? {});
        UserPreference.setRazorPayData(userModel);
        RazorPayModel fhg = UserPreference.getRazorPayData();
      } catch (e) {
        print('FireStoreUtils.getUserByID failed to parse user object ${user.id}');
      }
    });

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
  static const Duration _couponsCacheTtl = Duration(minutes: 30);

  // Lets manual pull-to-refresh force a fresh coupon fetch instead of
  // waiting out the 30-minute TTL, same pattern as clearVendorProductsCache.
  static void clearAllCouponsCache() {
    _allCouponsCache = null;
    _allCouponsCachedAt = null;
  }

  /// Returns all enabled, non-expired coupons. Cached for 30 minutes.
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

  static Future<int> getSlotBookingCount({
    required String vendorId,
    required String slotId,
    required DateTime date,
  }) async {
    // Use only equality filters (vendorID + slotId) to avoid the Firestore
    // composite-index requirement that mixing equality + range filters triggers.
    // The bookingDateKey equality path is preferred for new documents; for older
    // documents that lack the field, we fall back to Timestamp comparison in Dart.
    final dateKey =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final snapshot = await firestore
        .collection(ORDERS_TABLE)
        .where('vendorID', isEqualTo: vendorId)
        .where('slotId', isEqualTo: slotId)
        .get();

    return snapshot.docs.where((doc) {
      final data = doc.data();
      final status = data['status'] as String? ?? '';
      if (status == 'Cancelled' || status == 'Rejected') return false;

      // Fast path: bookingDateKey stored as 'yyyy-MM-dd' string
      final bdk = data['bookingDateKey'] as String?;
      if (bdk != null) return bdk == dateKey;

      // Legacy path: compare Timestamp stored in 'date' field
      final dateVal = data['date'];
      if (dateVal is! Timestamp) return false;
      final docDate = dateVal.toDate();
      return !docDate.isBefore(startOfDay) && docDate.isBefore(endOfDay);
    }).length;
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
    return orderModel;
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
    Query<Map<String, dynamic>> query = firestore
        .collection(Order_Rating)
        .where('VendorId', isEqualTo: vendorId)
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
