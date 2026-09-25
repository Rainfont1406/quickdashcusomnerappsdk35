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
import 'package:emartconsumer/services/behavior_summary_cache.dart';
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
import 'bunny_product_mirror.dart';
import 'bunny_reference_mirror.dart';
import 'bunny_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config_refresh_gate.dart';
import 'firestore_instrumentation.dart';
import 'story_cache.dart';

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
  // Server-computed worst-case estimate of when the soonest currently-
  // occupying walk-in order or table booking is due to auto-free
  // (2026-08-28, functions/dineOccupancy.js) - null when nothing is
  // currently occupying, or the field hasn't been computed yet. Advisory
  // only: a vendor's own "Mark Seat Free"/reject can free a seat earlier.
  final DateTime? nextFreeAt;

  SeatAvailability({
    required this.occupiedGuests,
    required this.maxCapacity,
    this.nextFreeAt,
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

class BookingDateBlockedException implements Exception {
  final String message;
  BookingDateBlockedException([this.message = 'This date is not available for booking. Please choose another date.']);
  @override
  String toString() => message;
}

class FireStoreUtils {
  static FirebaseMessaging firebaseMessaging = FirebaseMessaging.instance;
  static FirebaseFirestore firestore = FirebaseFirestore.instance;
  static Reference storage = FirebaseStorage.instance.ref();

  static void dumpFirestoreReadStats() => FirestoreReadStats.dumpSummary();
  static void dumpFirestoreWriteStats() => FirestoreWriteStats.dumpSummary();

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
      await ref.setLogged({'t': FieldValue.serverTimestamp()}, 'getServerTime:_serverPing');
      final snap = await ref.getLogged('getServerTime:_serverPing');
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

    await firestore.collection(USERS).doc(uid).getLogged('userExistOrNot:USERS').then(
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
    await firestore.collection(USERS).doc(uuid).getLogged('getUserProfile:USERS').then((value) {
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
    await firestore.collection(ONBoarding).where("type",isEqualTo: "customer").getLogged('getOnBoardingList:ONBoarding').then((value) {
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
    await firestore.collection(FavouriteItem).where('user_id', isEqualTo: getCurrentUid()).getLogged('getFavouriteItem:FavouriteItem').then(
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
      await firestore.collection(REFERRAL).where("referralCode", isEqualTo: referralCode).getLogged('checkReferralCodeValidOrNot:REFERRAL').then((value) {
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
      await firestore.collection(REFERRAL).where("referralCode", isEqualTo: referralCode).getLogged('getReferralUserByCode:REFERRAL').then((value) {
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
      await firestore.collection(REFERRAL).doc(MyAppState.currentUser!.userID).getLogged('getReferralUserBy:REFERRAL').then((value) {
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

    // 2026-09-15: on-device persistent layer behind the in-memory TTL above,
    // which dies with the app process and so never helped a cold start. See
    // StoryCache's doc comment for why stories need more than a plain TTL
    // (viewCount is shared server-side state that a cache cannot track).
    final sectionId = sectionConstantModel?.id ?? '';
    if (sectionId.isNotEmpty) {
      final cached = await StoryCache.read(sectionId);
      if (cached != null && cached.isNotEmpty) {
        final fullRefreshDue = !await ConfigRefreshGate.isFresh(
            StoryCache.gateKey(sectionId), StoryCache.fullRefreshInterval);
        if (!fullRefreshDue && !StoryCache.needsServerVerify(cached)) {
          // Cheap change-detection: ask only for stories NEWER than everything
          // we already hold, capped at 1 document. Returns empty on the common
          // path, which Firestore bills as its 1-read minimum - so a launch
          // with no new stories costs 1 read instead of the full list.
          // Expiry still resolves correctly offline: HomeScreen._filterStories
          // applies StoryModel.isExpired to whatever this returns, and both
          // time-based expiry factors are computable from the cached fields.
          final hasNew = await _hasNewStoriesSince(sectionId, cached);
          if (!hasNew) {
            _storyCache = cached;
            _storyCachedAt = now;
            debugPrint('[StoryCache] ${cached.length} stories served from '
                'on-device cache (no new stories) - full list not re-read');
            return cached;
          }
          debugPrint('[StoryCache] new story detected - re-fetching full list');
        }
      }
    }

    List<StoryModel> story = [];
    // Must filter approved==true server-side, not just client-side in
    // HomeScreen._filterStories() - the Firestore rule for story/{id} only
    // allows reads where resource.data.approved == true (or owner/admin).
    // A query without this filter can match unapproved docs from OTHER
    // vendors in the same section, which Firestore can't prove are
    // readable, so it denies the ENTIRE query with permission-denied -
    // silently hiding every story in the section, approved or not.
    QuerySnapshot<Map<String, dynamic>> storyQuery = await firestore.collection(STORY).where('sectionID', isEqualTo: sectionConstantModel!.id).where('approved', isEqualTo: true).getLogged('getStory:STORY');
    await Future.forEach(storyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        story.add(StoryModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getAllProducts Parse error $e');
      }
    });
    _storyCache = story;
    _storyCachedAt = now;
    // Persist for future cold starts. Only a non-empty result is stored: an
    // empty list here can also mean a transient failure, and caching that
    // would hide every story for the whole refresh window.
    if (sectionId.isNotEmpty && story.isNotEmpty) {
      await StoryCache.write(sectionId, story);
    }
    return story;
  }

  /// True when at least one approved story exists in [sectionId] that is newer
  /// than everything in [cached]. Capped at one document, so the common
  /// "nothing new" answer costs Firestore's 1-read query minimum instead of
  /// re-reading the whole list.
  ///
  /// Requires the composite index (sectionID ASC, approved ASC, createdAt ASC)
  /// created 2026-09-15 - two equality filters plus a range on a third field.
  /// Any failure returns true (fall back to the full fetch), so a missing
  /// index or permission problem degrades to exactly the old behaviour rather
  /// than silently showing a stale list.
  Future<bool> _hasNewStoriesSince(
      String sectionId, List<StoryModel> cached) async {
    final newest = StoryCache.newestCreatedAt(cached);
    if (newest == null) return true;
    try {
      final snap = await firestore
          .collection(STORY)
          .where('sectionID', isEqualTo: sectionId)
          .where('approved', isEqualTo: true)
          .where('createdAt', isGreaterThan: newest)
          .limit(1)
          .getLogged('getStory:STORY (new-story probe)');
      return snap.docs.isNotEmpty;
    } catch (e) {
      debugPrint('[StoryCache] new-story probe failed, falling back to a full '
          'fetch: $e');
      return true;
    }
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

  // Global, admin-managed, effectively-static reference data (2026-09-06) -
  // was refetched from Firestore on every product-customization dialog open
  // and every product detail page view with no caching at all. Same
  // 10-minute TTL / static-field pattern as _localOfferCategoriesCache below.
  static List<AttributesModel>? _attributesCache;
  static DateTime? _attributesCachedAt;
  static List<BrandsModel>? _brandsCache;
  static DateTime? _brandsCachedAt;
  static List<ReviewAttributeModel>? _reviewAttributesCache;
  static DateTime? _reviewAttributesCachedAt;
  static const Duration _referenceDataCacheTtl = Duration(minutes: 10);

  static Future<List<AttributesModel>> getAttributes() async {
    final now = DateTime.now();
    if (_attributesCache != null && _attributesCachedAt != null &&
        now.difference(_attributesCachedAt!) < _referenceDataCacheTtl) {
      return _attributesCache!;
    }
    List<AttributesModel> attributesList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(VENDOR_ATTRIBUTES).getLogged('getAttributes:VENDOR_ATTRIBUTES');
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        attributesList.add(AttributesModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    _attributesCache = attributesList;
    _attributesCachedAt = now;
    return attributesList;
  }

  static Future<List<BrandsModel>> getBrands() async {
    final now = DateTime.now();
    if (_brandsCache != null && _brandsCachedAt != null &&
        now.difference(_brandsCachedAt!) < _referenceDataCacheTtl) {
      return _brandsCache!;
    }
    List<BrandsModel> brandList = [];
    QuerySnapshot<Map<String, dynamic>> brandQuery = await firestore.collection(BRANDS).where('is_publish', isEqualTo: true).getLogged('getBrands:BRANDS');
    await Future.forEach(brandQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        brandList.add(BrandsModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    _brandsCache = brandList;
    _brandsCachedAt = now;
    return brandList;
  }

  static Future addRestaurantInbox(InboxModel inboxModel) async {
    return await firestore.collection("chat_store").doc(inboxModel.orderId).setLogged(inboxModel.toJson(), 'addRestaurantInbox:chat_store').then((document) {
      return inboxModel;
    });
  }

  static Future addRestaurantChat(ConversationModel conversationModel) async {
    return await firestore.collection("chat_store").doc(conversationModel.orderId).collection("thread").doc(conversationModel.id).setLogged(conversationModel.toJson(), 'addRestaurantChat:chat_store').then((document) {
      return conversationModel;
    });
  }

  static Future addDriverInbox(InboxModel inboxModel) async {
    return await firestore.collection("chat_driver").doc(inboxModel.orderId).setLogged(inboxModel.toJson(), 'addDriverInbox:chat_driver').then((document) {
      return inboxModel;
    });
  }

  static Future addDriverChat(ConversationModel conversationModel) async {
    return await firestore.collection("chat_driver").doc(conversationModel.orderId).collection("thread").doc(conversationModel.id).setLogged(conversationModel.toJson(), 'addDriverChat:chat_driver').then((document) {
      return conversationModel;
    });
  }

  // Bounded 2026-09-20 - was an unbounded fetch of every review a product
  // ever received, on every visit to its review list. Currently reached
  // only from two hidden UI surfaces (ContainerScreen's commented-out
  // Favourites drawer entries, HomeScreen's "Popular Near Food" card) so
  // today's live cost is zero, but a popular product's review count is
  // organically unbounded - the same class of landmine flagged and fixed
  // for getVendorReviews/getVendorReviewsPaginated (see that function's own
  // comment), just never applied here. 20 matches that same existing limit.
  // orderBy(createdAt) so "the 20 reviews you see" means the 20 most
  // recent, not an arbitrary Firestore-decided subset.
  Future<List<RatingModel>> getReviewList(String productId, {int limit = 20}) async {
    List<RatingModel> reviewList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore
        .collection(Order_Rating)
        .where('productId', isEqualTo: productId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .getLogged('getReviewList:Order_Rating');
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
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(PRODUCTS).where('categoryID', isEqualTo: categoryId).where('publish', isEqualTo: true).getLogged('getProductListByCategoryId:PRODUCTS');
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        productList.add(ProductModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return productList;
  }

  // "More from this store" on the product detail page (2026-09-06) - reused
  // _productsCache (populated by getVendorProducts/TakeAWay/Delivery, same
  // vendorID+publish==true filter, key "${vendorID}_vendor_all") instead of
  // its own separate query. If the customer already opened this vendor's
  // menu screen this session, that cache is almost always still warm here,
  // so this becomes a free in-memory slice instead of a fresh Firestore read.
  // Falls back to the original direct query on a genuine cache miss.
  static Future<List<ProductModel>> getStoreProduct(String storeId) async {
    final key = '${storeId}_vendor_all';
    final cached = _productsCache[key];
    final cachedAt = _productsCachedAt[key];
    if (cached != null && cachedAt != null &&
        DateTime.now().difference(cachedAt) < _productsCacheTtl) {
      return cached.take(6).toList();
    }
    List<ProductModel> productList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(PRODUCTS).where('vendorID', isEqualTo: storeId).where('publish', isEqualTo: true).limit(6).getLogged('getStoreProduct:PRODUCTS');
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
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(PRODUCTS).where('brandID', isEqualTo: brandId).where('publish', isEqualTo: true).getLogged('getProductListByBrandId:PRODUCTS');
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
    final now = DateTime.now();
    if (_reviewAttributesCache != null && _reviewAttributesCachedAt != null &&
        now.difference(_reviewAttributesCachedAt!) < _referenceDataCacheTtl) {
      return _reviewAttributesCache!;
    }
    List<ReviewAttributeModel> reviewAttributesList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(REVIEW_ATTRIBUTES).getLogged('getAllReviewAttributes:REVIEW_ATTRIBUTES');
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        reviewAttributesList.add(ReviewAttributeModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    _reviewAttributesCache = reviewAttributesList;
    _reviewAttributesCachedAt = now;
    return reviewAttributesList;
  }

  late StreamController<OrderModel> ordersByIdStreamController;
  late StreamSubscription ordersByIdStreamSub;

  Stream<OrderModel?> getOrderByID(String inProgressOrderID) async* {
    ordersByIdStreamController = StreamController();
    ordersByIdStreamSub = firestore.collection(ORDERS).doc(inProgressOrderID).snapshotsLogged('getOrderByID:ORDERS').listen((onData) async {
      if (onData.data() != null) {
        OrderModel? orderModel = OrderModel.fromJson(onData.data()!);
        ordersByIdStreamController.sink.add(orderModel);
      }
    });
    yield* ordersByIdStreamController.stream;
  }

  // Customer declines a pending vendor-initiated Bill Pay request.
  Future<void> declineBillPayRequest(String orderId) async {
    await firestore.collection(ORDERS).doc(orderId).updateLogged({
      'status': BILLPAY_STATUS_DECLINED,
      'billPayRespondedAt': Timestamp.now(),
    }, 'declineBillPayRequest:ORDERS');
  }

  // Opportunistic client-side expiry: only flips status if still pending,
  // so it never clobbers a decline/accept that raced it.
  Future<void> expireBillPayRequestIfPending(String orderId) async {
    final ref = firestore.collection(ORDERS).doc(orderId);
    await firestore.runTransaction((tx) async {
      final snap =
          await tx.getLogged(ref, 'expireBillPayRequestIfPending:ORDERS (tx)');
      if (snap.data()?['status'] == BILLPAY_STATUS_PENDING_APPROVAL) {
        tx.update(ref, {'status': BILLPAY_STATUS_EXPIRED});
      }
    });
  }

  // 2026-09-06: this was a raw, always-live Firestore .get() with no caching
  // at all, called from 12 different sites across the app (Home, Product
  // Details, Order Details, reviews, reorder, chat inbox, story view) - the
  // same vendor gets re-fetched fresh every single time any of these opens,
  // even seconds apart. Same 10-minute TTL as the other Home-screen caches
  // (products/categories/banners) - not mirrored to Bunny since a vendor
  // lookup by arbitrary id has no natural "whole list" shape to mirror.
  static final Map<String, (VendorModel?, DateTime)> _vendorByIdCache = {};
  static const Duration _vendorByIdCacheTtl = Duration(minutes: 10);

  static Future<VendorModel?> getVendor(String vid) async {
    final cached = _vendorByIdCache[vid];
    if (cached != null &&
        DateTime.now().difference(cached.$2) < _vendorByIdCacheTtl) {
      return cached.$1;
    }
    DocumentSnapshot<Map<String, dynamic>> userDocument = await firestore.collection(VENDORS).doc(vid).getLogged('getVendor:VENDORS');
    VendorModel? result;
    if (userDocument.data() != null && userDocument.exists) {
      result = VendorModel.fromJson(userDocument.data()!);
    } else {
      print("nulllll");
    }
    _vendorByIdCache[vid] = (result, DateTime.now());
    return result;
  }


  // vendorId -> (in-flight/resolved fetch, when it was started). Sales data
  // is a slow-changing rolling aggregate, so a short cache avoids
  // re-querying the same vendor's precomputed sales summary on every live
  // vendor-list update (cards rebuild often; sales data doesn't change
  // minute to minute). Cleared naturally on app restart.
  //
  // 6 hours, not 10 minutes (2026-09-04, widened alongside the switch to a
  // precomputed summary doc below) - the source of truth itself
  // (updateTopProducts, Cloud Functions) now only recomputes every 12
  // hours, so refreshing this client cache any faster than half that
  // interval can never observe newer data, only spend an extra read
  // getting the exact same answer back.
  static final Map<String, (Future<RollingSalesWindow>, DateTime)>
      _rollingSalesCache = {};
  static const Duration _rollingSalesCacheTtl = Duration(hours: 6);

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

  /// Reads the precomputed summary the updateTopProducts Cloud Function
  /// writes to vendors/{vendorId}/computed/salesSummary every 12 hours
  /// (2026-09-04 - was a direct client read of the whole dailyProductSales
  /// subcollection, up to ~90 documents; see functions/src/index.ts's
  /// computeSalesSummary, which reproduces the exact same date-cutoff
  /// bucketing this function used to do inline). One document read instead
  /// of up to 90, regardless of how many days of sales history exist.
  ///
  /// A vendor with no summary doc yet (created after the last scheduled
  /// run, or before this feature was deployed) returns an all-empty/zero
  /// window rather than falling back to the old full-subcollection read -
  /// it will have real data within one scheduled-run interval.
  static Future<RollingSalesWindow> _fetchRollingSalesWindow(
      String vendorId) async {
    try {
      final doc = await firestore
          .collection(VENDORS)
          .doc(vendorId)
          .collection('computed')
          .doc('salesSummary')
          .getLogged('_fetchRollingSalesWindow:computed');
      if (!doc.exists) {
        return const RollingSalesWindow(last90Days: {}, last7Days: {});
      }
      final data = doc.data()!;
      Map<String, int> toIntMap(String field) {
        final raw = data[field] as Map<String, dynamic>?;
        if (raw == null) return {};
        return raw.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));
      }
      return RollingSalesWindow(
        last90Days: toIntMap('last90Days'),
        last7Days: toIntMap('last7Days'),
        productOrders90: toIntMap('productOrders90'),
        productOrders7: toIntMap('productOrders7'),
        totalOrders90: (data['totalOrders90'] as num?)?.toInt() ?? 0,
        totalOrders7: (data['totalOrders7'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return const RollingSalesWindow(last90Days: {}, last7Days: {});
    }
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

  static List<String> _trailingYearMonths(int months) {
    final now = DateTime.now();
    return List.generate(months, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}';
    });
  }

  // Retention split (2026-09-20, see kBehaviorSummaryCoreRetentionMonths'
  // own comment in behavior_event_types.dart for the full why) - two
  // parallel queries instead of one:
  //   - behavior_summary, kBehaviorSummaryCoreRetentionMonths (3) back -
  //     everything RecommendationEngine's CURRENT-preference scoring uses.
  //   - behavior_summary_search, kBehaviorSummaryRetentionMonths (12) back -
  //     ONLY the ~5 search fields Cross-Session Search Interest needs the
  //     long window for.
  // The two collections' docs have disjoint field sets by construction (see
  // BehaviorTracker._flush's split write), so simply concatenating both doc
  // lists into one BehaviorSummarySnapshot.merge() call is correct as-is -
  // no change needed to the merge logic itself, same as before this split
  // it summed fields across N docs without caring which doc each came from.
  //
  // Persistent cache (2026-09-20, see BehaviorSummaryCache's own class doc
  // comment) - _behaviorSummaryCache above is memory-only and dies with the
  // app process, so before this every cold start's first restaurant visit
  // re-paid the FULL retention-window fetch (3 + 12 documents) even though
  // every month except the current one is immutable once written. Now:
  // read the on-device cache first, fetch ONLY months that are either the
  // current (always-mutable) month or genuinely missing from the cache
  // (first-ever open, or a month that just entered the retention window),
  // then merge and persist. A fresh install/first open still pays the full
  // seed fetch exactly as before - there is nothing to trim there, the
  // data genuinely does not exist locally yet.
  static Future<BehaviorSummarySnapshot> _loadBehaviorSummary(String uid) async {
    try {
      final currentYearMonth = _trailingYearMonths(1).first;
      final coreMonths = _trailingYearMonths(kBehaviorSummaryCoreRetentionMonths);
      final searchMonths = _trailingYearMonths(kBehaviorSummaryRetentionMonths);

      final (cachedCore, cachedSearch) = await BehaviorSummaryCache.read(uid);

      bool needsFetch(String month, Map<String, Map<String, dynamic>> cached) =>
          !BehaviorSummaryCache.isSealed(month, currentYearMonth) ||
          !cached.containsKey(month);
      final needCoreFetch =
          coreMonths.where((m) => needsFetch(m, cachedCore)).toList();
      final needSearchFetch =
          searchMonths.where((m) => needsFetch(m, cachedSearch)).toList();

      final userRef = firestore.collection(USERS).doc(uid);
      final freshCore = <String, Map<String, dynamic>>{};
      final freshSearch = <String, Map<String, dynamic>>{};
      final fetches = <Future<void>>[];
      if (needCoreFetch.isNotEmpty) {
        fetches.add(userRef
            .collection('behavior_summary')
            .where(FieldPath.documentId, whereIn: needCoreFetch)
            .getLogged('_loadBehaviorSummary:behavior_summary')
            .then((snap) {
          for (final d in snap.docs) freshCore[d.id] = d.data();
        }));
      }
      if (needSearchFetch.isNotEmpty) {
        fetches.add(userRef
            .collection('behavior_summary_search')
            .where(FieldPath.documentId, whereIn: needSearchFetch)
            .getLogged('_loadBehaviorSummary:behavior_summary_search')
            .then((snap) {
          for (final d in snap.docs) freshSearch[d.id] = d.data();
        }));
      }
      await Future.wait(fetches);

      // ignore: unawaited_futures
      BehaviorSummaryCache.write(uid,
          existingCore: cachedCore,
          existingSearch: cachedSearch,
          freshCore: freshCore,
          freshSearch: freshSearch);

      final mergedCore = {...cachedCore, ...freshCore};
      final mergedSearch = {...cachedSearch, ...freshSearch};
      // Only months still inside the current retention window feed the
      // snapshot - a previously-cached month that has since aged out (e.g.
      // month 13 for search) must not leak back in just because it's still
      // sitting in the on-device cache.
      final data = [
        for (final m in coreMonths)
          if (mergedCore.containsKey(m)) mergedCore[m]!,
        for (final m in searchMonths)
          if (mergedSearch.containsKey(m)) mergedSearch[m]!,
      ];
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
        .snapshotsLogged('_ensureBusinessContextListeners:BUSINESS_CONTEXT_TYPE_PROFILES')
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
        .snapshotsLogged('_ensureBusinessContextListeners:BUSINESS_CONTEXT_CUISINE_AFFINITY')
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
    _loadRecommendationConfigInternal().whenComplete(() {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  // 2026-09-15: same persisted-TTL treatment as the tax/gateway configs -
  // recommendation tuning is admin-managed and changes rarely, but this ran
  // on every cold start. Persists the RAW document map (not the model, which
  // has no toJson) and rehydrates through the same fromJson as the live path,
  // so a cached load is byte-identical to a fresh one.
  static const Duration _recommendationConfigTtl = Duration(days: 7);
  static const String _recommendationConfigCacheKey = 'recommendationConfig';

  static Future<void> _loadRecommendationConfigInternal() async {
    final cachedDoc = await ConfigRefreshGate.readDoc(
        _recommendationConfigCacheKey, _recommendationConfigTtl);
    if (cachedDoc != null) {
      RecommendationConfig.current = RecommendationConfig.fromJson(cachedDoc);
      debugPrint('[ConfigCache] recommendation_configuration served from '
          'on-device persisted copy - 0 Firestore reads');
      return;
    }
    try {
      final snap = await firestore
          .collection('recommendation_configuration')
          .doc('default')
          .getLogged('loadRecommendationConfig:recommendation_configuration');
      if (snap.exists) {
        final data = snap.data() ?? const <String, dynamic>{};
        RecommendationConfig.current = RecommendationConfig.fromJson(data);
        await ConfigRefreshGate.writeDoc(_recommendationConfigCacheKey, data);
      }
    } catch (_) {
      // Degrades to defaults - already identical to pre-feature behavior.
    }
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
    await documentReference.setLogged(sosMap, 'setSos:SOS');
  }

  Future<bool> getSOS(String orderId) async {
    bool isAdded = false;
    QuerySnapshot documentReference = await firestore.collection(SOS).where('orderId', isEqualTo: orderId).getLogged('getSOS:SOS');
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

    await documentReference.setLogged(sosMap, 'setRideComplain:complaints');
  }

  Future<bool> getRideComplain(String orderId) async {
    bool isAdded = false;
    QuerySnapshot documentReference = await firestore.collection(complaints).where('orderId', isEqualTo: orderId).getLogged('getRideComplain:complaints');
    documentReference.docs.forEach((element) {
      if (element['orderId'] == orderId) {
        isAdded = true;
      }
    });

    return isAdded;
  }

  Future<QueryDocumentSnapshot?> getRideComplainData(String orderId) async {
    QueryDocumentSnapshot? isAdded;
    QuerySnapshot documentReference = await firestore.collection(complaints).where('orderId', isEqualTo: orderId).getLogged('getRideComplainData:complaints');
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
    driverStreamSub = firestore.collection(USERS).doc(userId).snapshotsLogged('getDriver:USERS').listen((onData) async {
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
        await firestore.collection(VEHICLETYPE).where('sectionId', isEqualTo: sectionConstantModel!.id).where("isActive", isEqualTo: true).getLogged('getVehicleType:VEHICLETYPE');
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
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(POPULAR_DESTINATION).where('is_publish', isEqualTo: true).getLogged('getPopularDestination:POPULAR_DESTINATION');
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
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(RENTALVEHICLETYPE).where("isActive", isEqualTo: true).getLogged('getRentalVehicleType:RENTALVEHICLETYPE');
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        vehicleType.add(RentalVehicleType.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return vehicleType;
  }

  // Session cache for getCurrentUser(uid) - keyed by uid, NOT a single
  // shared slot, because this function is also used throughout the app to
  // look up OTHER users by id (chat participants, order authors/drivers,
  // vendor owners - see chat_screen.dart, OrderDetailsScreen.dart,
  // inbox_*_screen.dart), not just the logged-in user's own document. A
  // single-slot cache would return one uid's data for a different uid's
  // request. Cleared on any auth uid change via onAuthUidChanged so one
  // account's cached data can never leak into another account's session.
  static final Map<String, User> _userCache = {};
  static String? _lastAuthUid;

  // 2026-09-18: two callers invoking getCurrentUser(uid) concurrently before
  // either has populated _userCache both saw it empty and both fired their
  // own .get() - confirmed live (a single cold start logged
  // "getCurrentUser:USERS -> cache=2 docs=2 SLOW-CACHE=2", i.e. two separate
  // calls, both slow enough that the SDK's cache-fallback raced a real
  // in-flight server request that may still have been billed regardless of
  // the CACHE label - see firestore_instrumentation.dart's SLOW-CACHE doc
  // comment). Keyed per-uid, same reasoning as _userCache itself. A caller
  // who arrives after the fetch already completed just gets _userCache's
  // fast path above - this only matters for the narrow concurrent-callers
  // window.
  static final Map<String, Future<User?>> _userFetchInFlight = {};

  static void onAuthUidChanged(String? uid) {
    if (uid != _lastAuthUid) {
      _userCache.clear();
      _lastAuthUid = uid;
    }
  }

  static Future<User?> getCurrentUser(String uid) async {
    final cached = _userCache[uid];
    if (cached != null) return cached;

    final inFlight = _userFetchInFlight[uid];
    if (inFlight != null) return inFlight;

    final future = _fetchCurrentUser(uid);
    _userFetchInFlight[uid] = future;
    try {
      return await future;
    } finally {
      _userFetchInFlight.remove(uid);
    }
  }

  static Future<User?> _fetchCurrentUser(String uid) async {
    DocumentSnapshot<Map<String, dynamic>> userDocument = await firestore.collection(USERS).doc(uid).getLogged('getCurrentUser:USERS');
    if (userDocument.data() != null && userDocument.exists) {
      final user = User.fromJson(userDocument.data()!);
      _userCache[uid] = user;
      return user;
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
    await firestore.collection(dynamicNotification).where('type', isEqualTo: type).getLogged('getNotificationContent:dynamicNotification').then((value) {
      if (value.docs.isNotEmpty) {

        notificationModel = NotificationModel.fromJson(value.docs.first.data());
      } else {
        notificationModel = NotificationModel(id: "", message: "Notification setup is pending".tr(), subject: "setup notification".tr(), type: "");
      }
    });
    return notificationModel;
  }

  Future<TaxModel?> getTaxSetting() async {
    DocumentSnapshot<Map<String, dynamic>> taxQuery = await firestore.collection(Setting).doc('taxSetting').getLogged('getTaxSetting:Setting');
    if (taxQuery.data() != null) {
      return TaxModel.fromJson(taxQuery.data()!);
    }
    return null;
  }

  // 2026-09-06: bounded 10-minute TTL - tax rates are admin-configured and
  // change rarely, but Cart/Checkout must never go longer than this without
  // a real check (unlike price/vendor status, which stay fully live with no
  // cache at all). Previously this had no cache of its own at all;
  // ContainerScreen/CartScreen's "reuse the global taxList if non-empty"
  // logic effectively cached it forever within a session with no expiry -
  // this replaces that open-ended reuse with an actual bounded window.
  static final Map<String, (List<TaxModel>, DateTime)> _taxListCache = {};
  static const Duration _taxListCacheTtl = Duration(minutes: 10);

  // 2026-09-10: single-flight guard on top of the TTL cache above. The TTL
  // alone did not prevent duplicate queries, because the cache is only
  // written *after* the await resolves — two callers starting within the
  // same frame both saw an empty/expired cache and both issued the query.
  // Measured on-device: two identical `getTaxList:tax` reads (5 docs each)
  // logged in the SAME millisecond on a Cart open, and it reproduced even
  // with an empty cart, i.e. it was never item-dependent. The two racers are
  // ContainerScreen.getTaxList() (fired on app start) and CartScreen's own
  // fetch. Concurrent callers now await the one in-flight Future instead of
  // each starting their own — same pattern as ensurePaymentGatewaySettingsLoaded
  // and loadRecommendationConfig above.
  static final Map<String, Future<List<TaxModel>?>> _taxListInFlight = {};

  // 2026-09-15: SECOND-level, on-device persistent cache behind the 10-minute
  // in-memory one above. The in-memory cache dies with the app process, so
  // every cold start re-read all 5 of this section's tax documents - measured
  // as the single largest remaining chunk of a steady-state cold start once
  // the PurchaseCompletionListener fix landed. Tax rates are admin-configured
  // and change on the order of months (confirmed against the live collection:
  // GST/Transaction fee/cart charge, stable), so a 7-day on-device TTL
  // (explicit product decision, 2026-09-15) removes this read from
  // essentially every launch.
  //
  // NOT a correctness risk for what customers are actually charged: the
  // server recomputes tax independently on every order via
  // getVerifiedTaxSetting (functions/orderVerification.js, mirrored in
  // VerifiesOrderProducts.php) and charges its own figure, so a stale local
  // copy can never cause an undercharge. The bounded, accepted tradeoff is
  // display-only: for up to 7 days after an admin edits a rate, a customer
  // could see the old total on Cart before the server corrects it.
  static const Duration _taxListPersistentTtl = Duration(days: 7);
  static String _taxListPrefsKey(String key) => 'cached_tax_list_$key';
  static String _taxListGateKey(String key) => 'taxList_$key';

  Future<List<TaxModel>?> getTaxList(String? sectionId) {
    final key = sectionId ?? '';
    final cached = _taxListCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.$2) < _taxListCacheTtl) {
      return Future.value(cached.$1);
    }

    final inFlight = _taxListInFlight[key];
    if (inFlight != null) return inFlight;

    final future = _loadTaxList(sectionId, key);
    _taxListInFlight[key] = future;
    // Cleared whether it succeeded or failed, so a failed fetch never
    // pins a permanently-rejected Future for the rest of the session.
    future.whenComplete(() => _taxListInFlight.remove(key));
    return future;
  }

  /// Persistent-cache-aware path: tries the on-device copy first, and only
  /// falls through to a real Firestore query when there isn't a fresh one.
  Future<List<TaxModel>?> _loadTaxList(String? sectionId, String key) async {
    final persisted = await _readPersistedTaxList(key);
    if (persisted != null && persisted.isNotEmpty) {
      // Promote into the in-memory cache so the rest of this session's calls
      // don't even re-read SharedPreferences.
      _taxListCache[key] = (persisted, DateTime.now());
      // 2026-09-19: bytes were never passed here, so the summary showed
      // "docs=5 bytes=0B" - which reads as "5 documents of nothing" and
      // understated the total payload figure. Estimated from the parsed
      // models' own toJson() (the same data already in memory, so no extra
      // read or disk I/O). This is the size of the DATA the app consumed,
      // for consistency with every other cache-served label; the egress
      // for this read is genuinely zero either way (no network), and
      // that's carried by the fromCache=true flag, not by faking 0 bytes.
      // Approximate: toJson() can only emit the fields TaxModel models, so
      // a Firestore doc with extra unmodeled fields is slightly undercounted.
      final persistedBytes = estimateFirestoreValueBytes(
          persisted.map((t) => t.toJson()).toList());
      FirestoreReadStats.record('getTaxList:tax (persisted, 0 network)', true,
          persisted.length, null, persistedBytes);
      debugPrint('[FirestoreRead] getTaxList:tax served from on-device persisted cache '
          '- docs=${persisted.length} bytes=${FirestoreReadStats.fmtBytes(persistedBytes)}, '
          '0 Firestore reads');
      return persisted;
    }
    return _fetchTaxList(sectionId, key);
  }

  Future<List<TaxModel>?> _readPersistedTaxList(String key) async {
    try {
      if (!await ConfigRefreshGate.isFresh(
          _taxListGateKey(key), _taxListPersistentTtl)) {
        return null;
      }
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_taxListPrefsKey(key));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((e) => TaxModel.fromJson(e))
          .toList();
    } catch (_) {
      // Any corruption/decode failure falls back to a real fetch rather than
      // serving something we couldn't parse.
      return null;
    }
  }

  Future<void> _writePersistedTaxList(String key, List<TaxModel> taxList) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_taxListPrefsKey(key),
          jsonEncode(taxList.map((e) => e.toJson()).toList()));
      await ConfigRefreshGate.markRefreshed(_taxListGateKey(key));
    } catch (_) {
      // Best-effort - worst case the next cold start re-fetches as before.
    }
  }

  Future<List<TaxModel>?> _fetchTaxList(String? sectionId, String key) async {
    List<TaxModel> taxList = [];
    bool fetchFailed = false;
    await firestore.collection(tax).where('sectionId', isEqualTo: sectionId).where('enable', isEqualTo: true).getLogged('getTaxList:tax').then((value) {
      for (var element in value.docs) {
        TaxModel taxModel = TaxModel.fromJson(element.data());
        taxList.add(taxModel);
      }
    }).catchError((error) {
      fetchFailed = true;
      log(error.toString());
    });
    _taxListCache[key] = (taxList, DateTime.now());
    // Only persist a genuinely successful fetch - caching an empty list from a
    // failed/offline query would suppress tax display for the whole TTL.
    if (!fetchFailed && taxList.isNotEmpty) {
      await _writePersistedTaxList(key, taxList);
    }
    return taxList;
  }

  Future<String> uploadProductImage(File image, String progress) async {
    return uploadImageToBunny(image, 'store/products');
  }

  static Future<ProductModel?> getProductById(String productId) async {
    ProductModel? vendorCategoryModel;
    try {
      await firestore.collection(PRODUCTS).doc(productId).getLogged('getProductById:PRODUCTS').then((value) {
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
    return await firestore.collection(USERS).doc(user.userID).setLogged(json, 'updateCurrentUser:USERS', SetOptions(merge: true)).then((document) {
      MyAppState.currentUser = user;
      _userCache[user.userID] = user;
      return user;
    });
  }

  static Future<void> updateCurrentUserAddress(AddressModel userAddress) async {
    //UserPreference.setUserId(userID: user.userID);
    return await firestore.collection(USERS).doc(MyAppState.currentUser!.userID).updateLogged(
      {"shippingAddress": userAddress.toJson()}, 'updateCurrentUserAddress:USERS',
    ).then((document) {
      // Partial field update - we don't have the merged document in hand,
      // so invalidate rather than guess; next getCurrentUser() re-fetches.
      _userCache.remove(MyAppState.currentUser!.userID);
      print("AAADDDDDD");
    });
  }

  static Future<ProductModel?> updateProduct(ProductModel prodduct) async {
    return await firestore.collection(PRODUCTS).doc(prodduct.id).setLogged(prodduct.toJson(), 'updateProduct:PRODUCTS').then((document) {
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
        // Logged (2026-09-19): one read per line item per order, plus one
        // more for every transaction retry - see LoggedTransactionGet.
        final snap =
            await tx.getLogged(docRef, 'decrementProductStock:PRODUCTS (tx)');
        final data = snap.data();
        if (!snap.exists || data == null) return;

        // 2026-09-16: was `ProductModel.fromJson(...)` -> mutate ->
        // `tx.set(docRef, productModel.toJson())`, i.e. a decrement of ONE
        // number rewrote all 39 fields from a re-serialized Dart model.
        // Two real problems with that, both fixed here:
        //
        // 1. SILENT DATA LOSS. Any field Firestore holds that
        //    ProductModel.toJson() doesn't write back was deleted on every
        //    single order. Confirmed live 2026-09-16: all 8 of 8 most-recent
        //    products carry `proteins`/`fats`/`calories`, none of which are
        //    in toJson() - so every stock decrement was dropping them. The
        //    blast radius is open-ended: anything the Admin Panel or a future
        //    Cloud Function adds to a product doc would be wiped the next
        //    time that product is ordered.
        // 2. A ~1,230-byte write to change one number - and for the 33-of-40
        //    products with `quantity: -1` (unlimited), a full-document
        //    rewrite that changed NOTHING AT ALL, on every order.
        //
        // Now: read the raw snapshot map (no model round-trip that could drop
        // unknown fields), mutate only what's needed, and write only the
        // changed field path - or skip the write entirely when there's
        // nothing to decrement. Still inside the same transaction, so the
        // concurrency guarantee described above is unchanged.
        // variantId != null takes the variant branch only when the doc
        // actually has usable item_attribute.variants data; otherwise (missing
        // or malformed, e.g. a corrupted doc) it falls back to decrementing
        // the base `quantity` field below, same fallback the pre-2026-09-16
        // get-then-.set() version had - a variant order must still decrement
        // *something* rather than silently writing nothing.
        var tookVariantBranch = false;
        if (variantId != null) {
          final rawAttr = data['item_attribute'];
          final rawVariants = rawAttr is Map ? rawAttr['variants'] : null;
          if (rawVariants is List) {
            tookVariantBranch = true;
            var changed = false;
            final updatedVariants = rawVariants.map((v) {
              if (v is! Map) return v;
              if (v['variant_id']?.toString() != variantId) return v;
              final current = v['variant_quantity']?.toString();
              // '-1' is the unlimited-stock sentinel, same as the plain
              // `quantity` field below. int.tryParse (not int.parse) so a
              // malformed value skips this line instead of throwing and
              // aborting the whole stock update.
              if (current == null || current == '-1') return v;
              final parsed = int.tryParse(current);
              if (parsed == null) return v;
              changed = true;
              return {...v, 'variant_quantity': (parsed - quantity).toString()};
            }).toList();

            if (!changed) return;
            // Dot path: replaces only the variants array, leaving
            // item_attribute.attributes (and any other key in that map)
            // untouched.
            tx.update(docRef, {'item_attribute.variants': updatedVariants});
          }
        }
        if (!tookVariantBranch) {
          final rawQty = data['quantity'];
          final current = rawQty is num
              ? rawQty.toInt()
              : int.tryParse(rawQty?.toString() ?? '');
          if (current == null || current == -1) return;
          tx.update(docRef, {'quantity': current - quantity});
        }
      });
    } catch (stockErr) {
      print('Stock update error for $productId: $stockErr');
    }
  }

  static Future<VendorModel?> updateVendor(VendorModel vendor) async {
    return await firestore.collection(VENDORS).doc(vendor.id).setLogged(vendor.toJson(), 'updateVendor:VENDORS').then((document) {
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
    await firestore.collection(VENDORS).doc(vendorId).setLogged({
      'reviewsCount': FieldValue.increment(reviewsCountDelta),
      'reviewsSum': FieldValue.increment(reviewsSumDelta),
    }, 'updateVendorReviewStats:VENDORS', SetOptions(merge: true));
  }

  // Same reasoning as updateVendorReviewStats above, for the product doc.
  static Future<void> updateProductReviewStats(String productId, num reviewsCountDelta, num reviewsSumDelta, Map<String, dynamic> reviewAttributes) async {
    await firestore.collection(PRODUCTS).doc(productId).setLogged({
      'reviewsCount': FieldValue.increment(reviewsCountDelta),
      'reviewsSum': FieldValue.increment(reviewsSumDelta),
      'reviewAttributes': reviewAttributes,
    }, 'updateProductReviewStats:PRODUCTS', SetOptions(merge: true));
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
    firestore.collection(USERS).doc(id).snapshotsLogged('getUserByID:USERS').listen((user) {
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
    QuerySnapshot<Map<String, dynamic>> productsQuery = await firestore.collection(PRODUCTS).where('vendorID', isEqualTo: id).getLogged('getVendorCusions:PRODUCTS');
    await Future.forEach(productsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      if (document.data().containsKey("categoryID") && document.data()['categoryID'].toString().isNotEmpty) {
        prodtagList.add(document.data()['categoryID']);
      }
    });
    QuerySnapshot<Map<String, dynamic>> catQuery = await firestore.collection(CATEGORIES).where('publish', isEqualTo: true).getLogged('getVendorCusions:CATEGORIES');
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
    firestore.collection(Setting).doc(StripeSetting).snapshotsLogged('getStripe:Setting').listen((user) {
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
    firestore.collection(SettingPublic).doc("razorpaySettings").getLogged('getRazorPay:SettingPublic').then((user) {
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
      final payFastData = await firestore.collection(Setting).doc("payFastSettings").getLogged('getPayFastSettingData:Setting');
      final payFastSettingData = PayFastSettingData.fromJson(payFastData.data() ?? {});
      UserPreference.setPayFastData(payFastSettingData);
    } catch (error) {
      print(error.toString());
    }
  }

  static Future<void> getPaypalSettingData() async {
    try {
      final paypalData = await firestore.collection(Setting).doc("paypalSettings").getLogged('getPaypalSettingData:Setting');
      final payplaDataModel = PaypalSettingData.fromJson(paypalData.data() ?? {});
      UserPreference.setPayPalData(payplaDataModel);
    } catch (error) {
      print(error.toString());
    }
  }

  static Future<void> getMercadoPagoSettingData() async {
    try {
      final mercadoPago = await firestore.collection(Setting).doc("MercadoPago").getLogged('getMercadoPagoSettingData:Setting');
      final mercadoPagoDataModel = MercadoPagoSettingData.fromJson(mercadoPago.data() ?? {});
      UserPreference.setMercadoPago(mercadoPagoDataModel);
    } catch (error) {
      print(error.toString());
    }
  }

  static Future<void> getStripeSettingData() async {
    try {
      final stripeData = await firestore.collection(Setting).doc("stripeSettings").getLogged('getStripeSettingData:Setting');
      final stripeSettingData = StripeSettingData.fromJson(stripeData.data() ?? {});
      UserPreference.setStripeData(stripeSettingData);
    } catch (error) {
      print(error.toString());
    }
  }

  static Future<void> getFlutterWaveSettingData() async {
    try {
      final flutterWaveData = await firestore.collection(Setting).doc("flutterWave").getLogged('getFlutterWaveSettingData:Setting');
      final flutterWaveSettingData = FlutterWaveSettingData.fromJson(flutterWaveData.data() ?? {});
      UserPreference.setFlutterWaveData(flutterWaveSettingData);
    } catch (error) {}
  }

  static Future<void> getPayStackSettingData() async {
    try {
      final payStackData = await firestore.collection(Setting).doc("payStack").getLogged('getPayStackSettingData:Setting');
      final payStackSettingData = PayStackSettingData.fromJson(payStackData.data() ?? {});
      UserPreference.setPayStackData(payStackSettingData);
    } catch (error) {
      print(error.toString());
    }
  }

  static Future<void> getOrangeMoneySettingData() async {
    try {
      final orangeData = await firestore.collection(Setting).doc("orange_money_settings").getLogged('getOrangeMoneySettingData:Setting');
      final orangeMoneyData = OrangeMoney.fromJson(orangeData.data() ?? {});
      UserPreference.setOrangeData(orangeMoneyData);
    } catch (error) {
      print(error.toString());
    }
  }

  static Future<void> getXenditSettingData() async {
    try {
      final xenditData = await firestore.collection(Setting).doc("xendit_settings").getLogged('getXenditSettingData:Setting');
      final xenditModel = Xendit.fromJson(xenditData.data() ?? {});
      UserPreference.setXenditData(xenditModel);
    } catch (error) {
      print(error.toString());
    }
  }

  static Future<void> getMidTransSettingData() async {
    try {
      final midTransData = await firestore.collection(Setting).doc("midtrans_settings").getLogged('getMidTransSettingData:Setting');
      final midTransModel = MidTrans.fromJson(midTransData.data() ?? {});
      UserPreference.setMidTransData(midTransModel);
    } catch (error) {
      print(error.toString());
    }
  }

  static Future<void> getPhonePaySettingData() async {
    try {
      final data = await firestore.collection(Setting).doc("phonepe_settings").getLogged('getPhonePaySettingData:Setting');
      final settingData = PhonePaySettingData.fromJson(data.data() ?? {});
      UserPreference.setPhonePayData(settingData);
    } catch (error) {
      print(error.toString());
    }
  }

  static Future<void> getPaytmSettingData() async {
    try {
      final paytmData = await firestore.collection(Setting).doc("PaytmSettings").getLogged('getPaytmSettingData:Setting');
      final paytmSettingData = PaytmSettingData.fromJson(paytmData.data() ?? {});
      UserPreference.setPaytmData(paytmSettingData);
    } catch (error) {
      print(error.toString());
    }
  }

  // Called from 5 different startup/nav sites (main.dart splash flow x2,
  // ContainerScreen.initState, service_list_screen, location_permission_screen)
  // - the [FIRESTORE-PERF] instrumentation below confirmed 2+ of these fire
  // back-to-back on every cold start, each issuing its own Firestore read
  // for the same static walletSettings doc. Memoized to a single
  // in-flight/completed future so only the first caller in a session
  // actually reads Firestore; every other caller just awaits/ignores the
  // same result.
  static Future<void>? _walletSettingsLoad;

  // Same reasoning as _paymentConfigTtl above - the wallet on/off flag is
  // already persisted via UserPreference.setWalletData and read from there by
  // the rest of the app; this fetch only refreshed it.
  static const String _walletConfigCacheKey = 'walletSettings';

  static Future<void> getWalletSettingData() {
    final existing = _walletSettingsLoad;
    if (existing != null) return existing;
    final future = _loadWalletSettingData();
    _walletSettingsLoad = future;
    return future;
  }

  static Future<void> _loadWalletSettingData() async {
    bool hasLocalCopy;
    try {
      hasLocalCopy = UserPreference.getWalletData() != null;
    } catch (_) {
      hasLocalCopy = false;
    }
    if (await ConfigRefreshGate.canSkipFetch(
        key: _walletConfigCacheKey,
        ttl: _paymentConfigTtl,
        hasLocalValue: hasLocalCopy)) {
      return;
    }

    final sw = Stopwatch()..start();
    debugPrint('[FIRESTORE-PERF] getWalletSettingData() dispatched (${DateTime.now().toIso8601String()})');
    final walletSetting = await firestore.collection(Setting).doc('walletSettings').getLogged('getWalletSettingData:Setting');
    debugPrint('[FIRESTORE-PERF] getWalletSettingData() Firestore round-trip — '
        '${sw.elapsedMilliseconds}ms (${DateTime.now().toIso8601String()})');
    try {
      bool walletEnable = walletSetting.data()!['isEnabled'];
      UserPreference.setWalletData(walletEnable);
      await ConfigRefreshGate.markRefreshed(_walletConfigCacheKey);
    } catch (e) {
      print(e.toString());
    }
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

  // 2026-09-15: gateway settings change on the order of months, but this ran
  // on every cold start purely to overwrite an already-correct local copy
  // (UserPreference.setRazorPayData below has persisted it across app kills
  // for a long time, and PaymentScreen reads it from there, not from here).
  // See ConfigRefreshGate for the measured cold-start read breakdown.
  static const Duration _paymentConfigTtl = Duration(days: 7);

  // 2026-09-16: the Razorpay key itself (unlike the tax/recommendation
  // caches, or even the wallet on/off flag above) has no independent
  // server-side safety net - PaymentScreen opens the gateway SDK directly
  // with whatever key is cached locally, so a stale copy is a real, usable
  // credential, not just a UI hint. Deliberately a much shorter TTL than
  // _paymentConfigTtl so a rotated/disabled key propagates to devices within
  // a day instead of up to a week, while still cutting the cold-start read
  // for the common case where nothing changed.
  static const Duration _razorPayConfigTtl = Duration(days: 1);
  static const String _razorPayConfigCacheKey = 'razorpaySettings';

  static Future<void> getRazorPayDemo() async {
    // Skip entirely when a persisted copy exists and is still inside the TTL.
    // getRazorPayData() touches UserPreference.preferences, which is a `late`
    // field - if init() hasn't run yet it throws, so treat any throw as "no
    // usable local copy" and fall through to the real fetch.
    bool hasLocalCopy;
    try {
      hasLocalCopy = UserPreference.getRazorPayData() != null;
    } catch (_) {
      hasLocalCopy = false;
    }
    if (await ConfigRefreshGate.canSkipFetch(
        key: _razorPayConfigCacheKey,
        ttl: _razorPayConfigTtl,
        hasLocalValue: hasLocalCopy)) {
      return;
    }

    // Reads the safe-fields-only mirror, not the real (now admin-only)
    // settings doc - see getRazorPay()'s comment above.
    try {
      final user = await firestore.collection(SettingPublic).doc("razorpaySettings").getLogged('getRazorPayDemo:SettingPublic');
      final userModel = RazorPayModel.fromJson(user.data() ?? {});
      UserPreference.setRazorPayData(userModel);
      // Only after a genuine success - a failed fetch must not start a fresh
      // TTL window on top of a stale/absent local copy.
      await ConfigRefreshGate.markRefreshed(_razorPayConfigCacheKey);
    } catch (e) {
      print('FireStoreUtils.getUserByID failed to parse user object');
    }

    //yield* razorPayStreamController.stream;
  }

  // 2026-09-15: 7-day persisted cache, same bucket as Razorpay/wallet -
  // confirmed against the live production database that Setting/CODSettings
  // does not exist at all (404 on direct lookup), meaning every single call
  // here was a genuine, billed NOT_FOUND read for a feature that has never
  // been configured (this NOT_FOUND category is real and separately visible
  // in Cloud Monitoring's document/read_count breakdown, not just a doc-count
  // guess). A confirmed-absent result is cached too (as an explicit
  // "__absent__" marker, since ConfigRefreshGate.readDoc/writeDoc has nothing
  // to cache for a null result otherwise) - if COD is ever configured later,
  // the 7-day TTL still picks up the real document once it expires.
  static const String _codCacheKey = 'codSettings';
  static const Duration _codCacheTtl = Duration(days: 7);
  static const String _codAbsentMarker = '__absent__';

  Future<CodModel?> getCod() async {
    final cached = await ConfigRefreshGate.readDoc(_codCacheKey, _codCacheTtl);
    if (cached != null) {
      if (cached[_codAbsentMarker] == true) {
        debugPrint('[ConfigCache] CODSettings served from on-device cache '
            '(confirmed absent) - 0 Firestore reads');
        return null;
      }
      debugPrint('[ConfigCache] CODSettings served from on-device persisted '
          'copy - 0 Firestore reads');
      return CodModel.fromJson(cached);
    }

    DocumentSnapshot<Map<String, dynamic>> codQuery = await firestore.collection(Setting).doc('CODSettings').getLogged('getCod:Setting');
    final data = codQuery.data();
    if (data != null) {
      // ignore: unawaited_futures
      ConfigRefreshGate.writeDoc(_codCacheKey, data);
      return CodModel.fromJson(data);
    } else {
      // ignore: unawaited_futures
      ConfigRefreshGate.writeDoc(_codCacheKey, {_codAbsentMarker: true});
      return null;
    }
  }

  // 2026-09-06: bounded 10-minute TTL, same reasoning as getTaxList above -
  // this is admin-set delivery-charge policy (per-km rate, minimum charge),
  // not a live per-order fact like vendor open/closed status or price, which
  // stay fully live with no cache. One single global settings doc, so no
  // per-section/per-vendor keying needed.
  static DeliveryChargeModel? _deliveryChargeCache;
  static DateTime? _deliveryChargeCachedAt;
  static const Duration _deliveryChargeCacheTtl = Duration(minutes: 10);

  Future<DeliveryChargeModel?> getDeliveryCharges() async {
    final cachedAt = _deliveryChargeCachedAt;
    if (cachedAt != null &&
        DateTime.now().difference(cachedAt) < _deliveryChargeCacheTtl) {
      return _deliveryChargeCache;
    }
    DocumentSnapshot<Map<String, dynamic>> codQuery = await firestore.collection(Setting).doc('DeliveryCharge').getLogged('getDeliveryCharges:Setting');
    _deliveryChargeCache = codQuery.data() != null ? DeliveryChargeModel.fromJson(codQuery.data()!) : null;
    _deliveryChargeCachedAt = DateTime.now();
    return _deliveryChargeCache;
  }

  // 2026-09-25: the location screen and the service list both called this
  // uncached. Sections are admin config (changes rarely, but can change any
  // time) - 30-minute in-memory cache plus a shared in-flight read so two
  // callers racing on the same frame don't both query. In memory only:
  // SectionModel carries nested maps the on-device list cache would drop.
  static List<SectionModel>? _sectionsCache;
  static DateTime? _sectionsCachedAt;
  static Future<List<SectionModel>>? _sectionsInFlight;
  static const Duration _sectionsCacheTtl = Duration(minutes: 30);

  static Future<List<SectionModel>> getSections() {
    final cached = _sectionsCache;
    final at = _sectionsCachedAt;
    if (cached != null && at != null && DateTime.now().difference(at) < _sectionsCacheTtl) {
      debugPrint('[Cache] getSections served from memory - 0 Firestore reads');
      return Future.value(cached);
    }
    final inFlight = _sectionsInFlight;
    if (inFlight != null) return inFlight;
    final future = _fetchSections().then((list) {
      if (list.isNotEmpty) {
        _sectionsCache = list;
        _sectionsCachedAt = DateTime.now();
      }
      return list;
    }).whenComplete(() => _sectionsInFlight = null);
    _sectionsInFlight = future;
    return future;
  }

  static Future<List<SectionModel>> _fetchSections() async {
    List<SectionModel> sections = [];
    QuerySnapshot<Map<String, dynamic>> productsQuery = await firestore.collection(SECTION).where("isActive", isEqualTo: true).getLogged('getSections:SECTION');

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
    DocumentSnapshot<Map<String, dynamic>> userDocument = await firestore.collection(SECTION).doc(sectionId).getLogged('getSectionsById:SECTION');
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


  // [vendorIdForBunny] is only passed by the per-vendor menu queries
  // (getVendorProducts/TakeAWay/Delivery) - the Home section-wide catalog
  // query has no per-vendor mirror to try and always goes straight to
  // Firestore. Bunny is tried first and silently falls back to the original
  // Firestore query on any failure (see fetchVendorProductsFromBunny's own
  // doc comment) - a vendor with no mirror yet behaves exactly as before.
  Future<List<ProductModel>> _fetchProducts(String cacheKey, Query<Map<String, dynamic>> query, {String? vendorIdForBunny, String? sectionIdForBunny}) async {
    final now = DateTime.now();
    final cached = _productsCache[cacheKey];
    final cachedAt = _productsCachedAt[cacheKey];
    if (cached != null && cachedAt != null &&
        now.difference(cachedAt) < _productsCacheTtl) {
      return cached;
    }

    if (vendorIdForBunny != null) {
      final mirrored = await fetchVendorProductsFromBunny(vendorIdForBunny);
      if (mirrored != null) {
        _productsCache[cacheKey] = mirrored;
        _productsCachedAt[cacheKey] = now;
        return mirrored;
      }
    }

    if (sectionIdForBunny != null) {
      final mirrored = await fetchSectionProductsFromBunny(sectionIdForBunny);
      if (mirrored != null) {
        _productsCache[cacheKey] = mirrored;
        _productsCachedAt[cacheKey] = now;
        return mirrored;
      }
    }

    final List<ProductModel> products = [];
    final snapshot = await query.getLogged('_fetchProducts:query');
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
  //
  // (2026-09-11 fix) Same plain-TTL cache shape as the product-list mirror
  // cache right above (_productsCache) - deliberately not a conditional/ETag
  // revalidation scheme. The Bunny blobs behind this are already kept
  // instantly current server-side (functions/index.js's
  // syncLocalOffersToBunny / syncLocalOfferCategoriesToBunny fire on every
  // local_offers / local_offer_categories write and rebuild+purge the CDN
  // edge within seconds - see BunnyLocalOfferMirrorController), so the only
  // job left for this client-side cache is what the product cache already
  // does: avoid re-downloading the same unchanged blob on every screen open.
  //
  // TTL is deliberately much longer than the product cache's 10 minutes,
  // though - that value fits data that can plausibly change within a
  // session (stock, banners); local offers are set once by an admin and
  // just count down to their own validTill (commonly 2-3 days out), so
  // there's nothing to gain from re-checking every 10 minutes - a session
  // that reopens this screen repeatedly over a few idle hours/days would
  // otherwise re-download the exact same unchanged blob dozens of times for
  // no reason. 6 hours still means a genuine same-day admin edit shows up
  // the same day, with a small fraction of the request volume.
  static List<LocalOfferCategoryModel>? _localOfferCategoriesCache;
  static DateTime? _localOfferCategoriesCachedAt;
  static List<LocalOfferModel>? _localOffersCache;
  static DateTime? _localOffersCachedAt;
  static const Duration _localOffersCacheTtl = Duration(hours: 6);

  static void clearLocalOffersCache() {
    _localOfferCategoriesCache = null;
    _localOfferCategoriesCachedAt = null;
    _localOffersCache = null;
    _localOffersCachedAt = null;
  }

  static Future<List<LocalOfferCategoryModel>> getLocalOfferCategories() async {
    final now = DateTime.now();
    if (_localOfferCategoriesCache != null &&
        _localOfferCategoriesCachedAt != null &&
        now.difference(_localOfferCategoriesCachedAt!) < _localOffersCacheTtl) {
      return _localOfferCategoriesCache!;
    }
    final mirrored = await fetchLocalOfferCategoriesFromBunny();
    if (mirrored != null) {
      _localOfferCategoriesCache = mirrored;
      _localOfferCategoriesCachedAt = now;
      return mirrored;
    }
    final List<LocalOfferCategoryModel> categories = [];
    try {
      final snapshot = await firestore
          .collection(LOCAL_OFFER_CATEGORIES)
          .where('isActive', isEqualTo: true)
          .orderBy('sortOrder')
          .getLogged('getLocalOfferCategories:LOCAL_OFFER_CATEGORIES');
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
    // Only the unfiltered (whole-set) shape is cached - the only way
    // LocalOffersListScreen actually calls this (see its own doc comment on
    // _selectCategory). A categoryId-scoped call is a narrower result than
    // the cached whole set, so it can't safely reuse this cache entry;
    // falls through to a fresh Firestore query as before.
    final unfiltered = categoryId == null || categoryId.isEmpty;
    if (unfiltered) {
      final now = DateTime.now();
      if (_localOffersCache != null &&
          _localOffersCachedAt != null &&
          now.difference(_localOffersCachedAt!) < _localOffersCacheTtl) {
        return _localOffersCache!;
      }
      // Bunny mirror only covers the whole-set fetch (see
      // fetchLocalOffersFromBunny's own doc comment).
      final mirrored = await fetchLocalOffersFromBunny();
      if (mirrored != null) {
        _localOffersCache = mirrored;
        _localOffersCachedAt = now;
        return mirrored;
      }
    }
    List<LocalOfferModel> offers = [];
    try {
      Query<Map<String, dynamic>> query = firestore.collection(LOCAL_OFFERS).where('isActive', isEqualTo: true);
      if (categoryId != null && categoryId.isNotEmpty) {
        query = query.where('categoryId', isEqualTo: categoryId);
      }
      final snapshot = await query.limit(limit).getLogged('getAllActiveLocalOffers:LOCAL_OFFERS');
      // (2026-08-05) One document = one business now - every result here is
      // its own standalone business, nothing to filter out (previously a
      // business's extra offers were separate sibling documents that had to
      // be excluded from this feed; now they live inside the same doc's own
      // offers[] array instead - see LocalOfferModel.primary).
      offers = snapshot.docs.map((d) => LocalOfferModel.fromJson(d.data())).toList();
    } catch (e) {
      log('FireStoreUtils.getAllActiveLocalOffers $e');
    }
    if (unfiltered) {
      _localOffersCache = offers;
      _localOffersCachedAt = DateTime.now();
    }
    return offers;
  }


  // Safety cap on the whole-section product query below (2026-09-01 cost
  // fix), same pattern already established by getAllActiveLocalOffers'
  // limit: 300 - a ceiling, not a real page size. Found during a 2026-09-01
  // cost audit: this fetches a section's ENTIRE published product catalog
  // with no bound at all, filtered only by section_id + publish. It cannot
  // be lowered further than this, though - unlike the per-vendor menu
  // preview use (HomeScreen.dart's _handleProducts, which only actually
  // consumes a small slice), SearchScreen.dart uses this exact result as
  // its ENTIRE client-side search corpus (_searchableProducts) - a lower
  // cap would silently make products past the cutoff unfindable in search.
  // 500 is generous enough to change nothing at today's scale (a handful of
  // vendors/testers) while capping worst-case growth as the platform scales
  // - revisit with real server-side search/pagination if a section's real
  // published-product count ever approaches this cap.
  static const int _productsQueryLimit = 500;

  // getAllProducts / getAllDelevryProducts / getAllTakeAWayProducts all run
  // the IDENTICAL query (section_id + publish - the type-specific
  // deliveryOption/takeawayOption filters are commented out, dead) but used
  // to be cached under 3 SEPARATE keys (_all/_delivery/_takeaway) despite
  // returning byte-for-byte the same data (2026-09-02 fix, found while
  // investigating disproportionate Firestore reads). That meant visiting
  // e.g. Home (fires the delivery/takeaway variant depending on selected
  // order type) and then Search (fires the other variant) within the same
  // 10-minute cache window re-fetched the whole section catalog a SECOND
  // time for data already sitting in memory under a different key. All
  // three now share one cache entry, keyed purely by section - same
  // per-vendor-menu-preview and per-search-corpus correctness as before
  // (identical filtered result either way), just without the redundant
  // re-fetch. Kept as 3 separate public methods (not collapsed into one)
  // since HomeScreen/SearchScreen/favourite_item.dart call them by these
  // exact names expecting a plain product list back.
  Query<Map<String, dynamic>> _sectionProductsQuery() => firestore
      .collection(PRODUCTS)
      .where("section_id", isEqualTo: sectionConstantModel!.id)
      .where('publish', isEqualTo: true)
      .limit(_productsQueryLimit);

  Future<List<ProductModel>> getAllProducts() =>
      _fetchProducts('${sectionConstantModel!.id}_products', _sectionProductsQuery(), sectionIdForBunny: sectionConstantModel!.id);

  Future<List<ProductModel>> getAllDelevryProducts() =>
      _fetchProducts('${sectionConstantModel!.id}_products', _sectionProductsQuery(), sectionIdForBunny: sectionConstantModel!.id);

  Future<List<ProductModel>> getAllTakeAWayProducts() =>
      _fetchProducts('${sectionConstantModel!.id}_products', _sectionProductsQuery(), sectionIdForBunny: sectionConstantModel!.id);

  Future<bool> blockUser(User blockedUser, String type) async {
    bool isSuccessful = false;
    BlockUserModel blockUserModel = BlockUserModel(type: type, source: MyAppState.currentUser!.userID, dest: blockedUser.userID, createdAt: Timestamp.now());
    await firestore.collection(REPORTS).addLogged(blockUserModel.toJson(), 'blockUser:REPORTS').then((onValue) {
      isSuccessful = true;
    });
    return isSuccessful;
  }

  Stream<bool> getBlocks() async* {
    StreamController<bool> refreshStreamController = StreamController();
    firestore.collection(REPORTS).where('source', isEqualTo: MyAppState.currentUser!.userID).snapshotsLogged('getBlocks:REPORTS').listen((onData) {
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

  // Keyed by sectionConstantModel.id (not a single slot) - the app has
  // multiple verticals (food/grocery/parcel/rental/cab/services) and a
  // session can switch between them, so caching under one shared key would
  // serve one section's cuisines under another. Same 10-minute TTL as
  // getStory's existing cache above.
  static final Map<String, (List<VendorCategoryModel>, DateTime)> _cuisinesCache = {};
  static const Duration _cuisinesCacheTtl = Duration(minutes: 10);

  Future<List<VendorCategoryModel>> getCuisines() async {
    final sectionId = sectionConstantModel!.id ?? '';
    final cached = _cuisinesCache[sectionId];
    final now = DateTime.now();
    if (cached != null && now.difference(cached.$2) < _cuisinesCacheTtl) {
      return cached.$1;
    }

    // Read on every app cold start by every user - highest fan-out of any
    // Bunny mirror in this app, per the billing audit. Falls back to the
    // original Firestore query below on any failure (see
    // fetchCategoriesFromBunny's own doc comment).
    final mirrored = await fetchCategoriesFromBunny(sectionId);
    if (mirrored != null) {
      _cuisinesCache[sectionId] = (mirrored, now);
      return mirrored;
    }

    List<VendorCategoryModel> cuisines = [];
    QuerySnapshot<Map<String, dynamic>> cuisinesQuery =
        await firestore.collection(CATEGORIES).where("section_id", isEqualTo: sectionId).where('publish', isEqualTo: true).getLogged('getCuisines:CATEGORIES');
    await Future.forEach(cuisinesQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        cuisines.add(VendorCategoryModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCuisines Parse error $e');
      }
    });
    _cuisinesCache[sectionId] = (cuisines, now);
    return cuisines;
  }

  Future<List<VendorCategoryModel>> getHomePageShowCategory() async {
    List<VendorCategoryModel> cuisines = [];
    QuerySnapshot<Map<String, dynamic>> cuisinesQuery = await firestore
        .collection(CATEGORIES)
        .where("section_id", isEqualTo: sectionConstantModel!.id)
        .where("show_in_homepage", isEqualTo: true)
        .where('publish', isEqualTo: true)
        .getLogged('getHomePageShowCategory:CATEGORIES');
    await Future.forEach(cuisinesQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        cuisines.add(VendorCategoryModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCuisines Parse error $e');
      }
    });
    return cuisines;
  }

  // getAllDineInRestaurants()/closeDineInStream() removed 2026-09-11 - the
  // raw GeoFirestore .within() query here was invisible to .getLogged()'s
  // read-cost instrumentation and, at the section's admin-configured
  // 13,000km ("effectively unlimited") radius, read far more documents than
  // it ever displayed (confirmed live: ~179 reads for one Dine-In visit,
  // zero matching lines in the app's own read log). DineInScreen now reads
  // off SharedVendorsWatcher.watch() (the same Bunny-mirrored, shared
  // section vendor list HomeScreen already uses) and filters client-side
  // for enabledDiveInFuture, same as HomeScreen's own migration.

  late StreamSubscription vendorStreamSub;
  StreamController<List<VendorModel>>? vendorStreamController;

  Future<List<VendorModel>> getVendors() async {
    List<VendorModel> vendors = [];
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore.collection(VENDORS).where("section_id", isEqualTo: sectionConstantModel!.id).getLogged('getVendors:VENDORS');
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

  // 2026-08-30 fix: was 'author.id' (a nested field) while
  // firestore.rules' isOwner('authorID') check - and every other booking
  // query in the codebase (server-side deposit matching, CartScreen's
  // _hasEligibleBookingTonight, the auto-release sweep) - uses the flat
  // authorID field instead. That mismatch made this the one place where a
  // real customer's own My Bookings query could come back PERMISSION_DENIED.
  // Worse, .listen() here had no onError handler at all, so that denial (or
  // any other stream error) was silently swallowed - the StreamController
  // never got anything pushed to it, its stream never emitted, and
  // UpComingTableBooking/HistoryTableBooking's StreamBuilder stayed on
  // ConnectionState.waiting forever instead of resolving to "No Upcoming
  // Bookings". Also fixed: `orders` used to accumulate across every live
  // snapshot update instead of being rebuilt fresh each time, since
  // onData.docs is already the full current result set, not a delta - that
  // silently duplicated every booking on any real-time update.
  // Subscription/controller exposed on the instance (not local to the
  // method, which discarded the .listen() return value entirely) so a
  // caller can actually cancel this live listener - see closeBookingOrdersStream()
  // below. UpComingTableBooking/HistoryTableBooking each own a private
  // FireStoreUtils() instance, so one field pair per instance is enough;
  // previously every visit to either screen leaked a brand-new listener
  // that ran for the rest of the app process, since neither screen had a
  // dispose() that could cancel anything (nothing was ever exposed to cancel).
  StreamSubscription? bookingOrdersStreamSub;
  StreamController<List<BookTableModel>>? bookingOrdersStreamController;

  static const int _bookingHistoryLimit = 20;

  Stream<List<BookTableModel>> getBookingOrders(String userID, bool isUpComing) async* {
    bookingOrdersStreamController = StreamController<List<BookTableModel>>();
    final query = isUpComing
        ? firestore
            .collection(ORDERS_TABLE)
            .where('authorID', isEqualTo: userID)
            .where('date', isGreaterThan: Timestamp.now())
            .where("section_id", isEqualTo: sectionConstantModel!.id)
            .orderBy('date', descending: true)
            .orderBy('createdAt', descending: true)
        : firestore
            .collection(ORDERS_TABLE)
            .where('authorID', isEqualTo: userID)
            .where('date', isLessThan: Timestamp.now())
            .where("section_id", isEqualTo: sectionConstantModel!.id)
            .orderBy('date', descending: true)
            .orderBy('createdAt', descending: true)
            // 2026-09-25: history grows forever and was loaded whole, live,
            // on every open (~113 KB for the heaviest customer). Latest 20
            // past bookings only; upcoming (date > now) is unchanged.
            .limit(_bookingHistoryLimit);

    bookingOrdersStreamSub = query.snapshotsLogged('getBookingOrders:ORDERS_TABLE').listen((onData) async {
      final List<BookTableModel> orders = [];
      await Future.forEach(onData.docs, (QueryDocumentSnapshot<Map<String, dynamic>> element) {
        try {
          orders.add(BookTableModel.fromJson(element.data()));
        } catch (e, s) {
          print('booktable parse error ${element.id} $e $s');
        }
      });
      bookingOrdersStreamController?.sink.add(orders);
    }, onError: (e, s) {
      print('getBookingOrders (${isUpComing ? "upcoming" : "history"}) stream error: $e $s');
      bookingOrdersStreamController?.sink.add(<BookTableModel>[]);
    });
    yield* bookingOrdersStreamController!.stream;
  }

  void closeBookingOrdersStream() {
    bookingOrdersStreamSub?.cancel();
    bookingOrdersStreamController?.close();
  }

  // getOrders()/closeOrdersStream() removed (2026-09-06) - replaced by
  // SharedOrdersWatcher (lib/services/shared_orders_watcher.dart), a
  // session-scoped shared listener instead of a per-screen one. See that
  // file's own doc comment for why: OrdersScreen's per-visit listener here
  // only ever actually opened once per app session (ContainerScreen's
  // drawer reuses its Element/State across visits with no key), so a
  // customer's Orders list could stay frozen for days despite real new
  // orders that correctly matched this exact query.

  static setFavouriteStore(FavouriteModel favouriteModel) {
    firestore.collection(FavouriteStore).addLogged(favouriteModel.toJson(), 'setFavouriteStore:FavouriteStore').then((value) {
      print("===FAVOURITE ADDED===");
    });
  }

  static removeFavouriteStore(FavouriteModel favouriteModel) {
    FirebaseFirestore.instance
        .collection(FavouriteStore)
        .where("store_id", isEqualTo: favouriteModel.store_id)
        .where("section_id", isEqualTo: sectionConstantModel!.id)
        .getLogged('removeFavouriteStore:FavouriteStore')
        .then((value) {
      for (var element in value.docs) {
        FirebaseFirestore.instance.collection(FavouriteStore).doc(element.id).deleteLogged('removeFavouriteStore:FavouriteStore').then((value) {
          print("Success!");
        });
      }
    });
  }

  Future<List<FavouriteItemModel>> getFavouritesProductList(String userId) async {
    List<FavouriteItemModel> lstFavourites = [];

    QuerySnapshot<Map<String, dynamic>> favourites =
        await firestore.collection(FavouriteItem).where('user_id', isEqualTo: userId).where("section_id", isEqualTo: sectionConstantModel!.id).getLogged('getFavouritesProductList:FavouriteItem');
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
        await firestore.collection(FavouriteOndemandItem).where('user_id', isEqualTo: userId).where("section_id", isEqualTo: sectionConstantModel!.id).getLogged('getFavouritesServiceList:FavouriteOndemandItem');
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
    await firestore.collection(FavouriteItem).addLogged(favouriteModel.toJson(), 'setFavouriteStoreItem:FavouriteItem').then((value) {
      print("===FAVOURITE ADDED===");
    });
  }

  Future<void> setFavouriteOndemandSection(FavouriteOndemandServiceModel favouriteModel) async {
    await firestore.collection(FavouriteOndemandItem).addLogged(favouriteModel.toJson(), 'setFavouriteOndemandSection:FavouriteOndemandItem').then((value) {
      print("===FAVOURITE ADDED===");
    });
  }

  void removeFavouriteOndemandService(FavouriteOndemandServiceModel favouriteModel) {
    FirebaseFirestore.instance
        .collection(FavouriteOndemandItem)
        .where("user_id", isEqualTo: favouriteModel.user_id)
        .where("service_id", isEqualTo: favouriteModel.service_id)
        .getLogged('removeFavouriteOndemandService:FavouriteOndemandItem')
        .then((value) {
      for (var element in value.docs) {
        FirebaseFirestore.instance.collection(FavouriteOndemandItem).doc(element.id).deleteLogged('removeFavouriteOndemandService:FavouriteOndemandItem').then((value) {
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
  // Underlying geoflutterfire subscription behind allResaturantStreamController
  // (2026-09-01 fix - see its own doc comment on getAllStores below for why
  // this exists).
  StreamSubscription<List<DocumentSnapshot>>? _allStoresGeoSub;

  // geoflutterfire's within() fans one logical "nearby vendors" query out
  // into 9 separate live Firestore listeners (the center geohash cell + 8
  // neighbors), combined with rxdart's combineLatest. Every call to this
  // method starts a brand-new set of 9 listeners - previously nothing ever
  // cancelled the PREVIOUS call's 9 listeners (only HomeScreen's own
  // wrapper subscription got cancelled, via _vendorSub?.cancel()), so each
  // call to getData() (init, address change, pull-to-refresh, order-type
  // toggle, app resume) leaked 9 more permanently-open listeners against
  // the whole vendors collection - each one re-billing a Firestore read
  // and redoing real parsing work every time ANY vendor's document changes
  // anywhere, for the rest of the app session, invisibly (found during a
  // 2026-09-01 cost investigation: this was the dominant driver of
  // disproportionate Firestore read volume from just 2 testers).
  //
  // Fix: cancel the PREVIOUS call's underlying geo subscription before
  // starting a new one (covers repeated getAllStores() calls even if a
  // caller forgets to unsubscribe first), AND tear it down again the
  // instant the last listener on the wrapper stream unsubscribes (covers
  // HomeScreen's existing _vendorSub?.cancel() pattern, so a single call
  // per screen visit already cleans up correctly without any caller change).
  Stream<List<VendorModel>> getAllStores() async* {
    await _allStoresGeoSub?.cancel();
    _allStoresGeoSub = null;

    final controller = StreamController<List<VendorModel>>.broadcast();
    allResaturantStreamController = controller;
    controller.onCancel = () {
      _allStoresGeoSub?.cancel();
      _allStoresGeoSub = null;
    };

    try {
      var collectionReference = firestore.collection(VENDORS).where("section_id", isEqualTo: sectionConstantModel!.id);

      GeoFirePoint center = geo.point(latitude: MyAppState.selectedPosotion.location!.latitude, longitude: MyAppState.selectedPosotion.location!.longitude);

      Stream<List<DocumentSnapshot>> stream = geo
          .collection(collectionRef: collectionReference)
          .within(center: center, radius: double.parse(sectionConstantModel!.nearByRadius.toString()), field: 'g', strictMode: true);

      _allStoresGeoSub = stream.listen((List<DocumentSnapshot> documentList) {
        // 2026-09-20: getAllStores() is the ONLY remaining caller of the raw
        // geoflutterfire stream left in the app - MapView, ViewAllPopularStore,
        // and CategoryDetailsScreen were all migrated onto SharedVendorsWatcher
        // (which IS logged) between 2026-09-06 and 2026-09-19, but this one
        // (HomeScreen's main vendor grid, fired on every app open) was missed.
        // It had zero FirestoreReadStats/[FirestoreListener] trace despite
        // being the highest-traffic listener in the app - every document here
        // is a real, billed read (or a fromCache one that may still have hit
        // the server first, per this file's own SLOW-CACHE warning). Logged
        // manually (not via .snapshotsLogged()) because this stream's type is
        // the geo library's own Stream<List<DocumentSnapshot>>, not a
        // Query<T>/DocumentReference<T> the extension methods apply to. A
        // mixed event (some docs cache, some server) is conservatively
        // labeled SERVER, matching this file's "don't undercount" convention.
        final fromCache = documentList.isNotEmpty &&
            documentList.every((d) => d.metadata.isFromCache);
        final bytes = estimateSnapshotBytes(documentList);
        FirestoreReadStats.record('HomeScreen.getAllStores', fromCache,
            documentList.length, null, bytes);
        debugPrint('[FirestoreListener] HomeScreen.getAllStores '
            'source=${fromCache ? "CACHE" : "SERVER"} '
            'docs=${documentList.length} bytes=${FirestoreReadStats.fmtBytes(bytes)} '
            'at=${DateTime.now().toIso8601String()}');
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
        if (!controller.isClosed) {
          controller.add(vendors);
        }
      });
    } catch (e) {
      print('getAllStores setup error: $e');
    }

    yield* controller.stream;
  }

  closeVendorStream() {
    _allStoresGeoSub?.cancel();
    _allStoresGeoSub = null;
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

  // getVendorsByCuisineID() removed (2026-09-20 cost/instrumentation audit) -
  // CategoryDetailsScreen was its last caller and was migrated off it onto
  // SharedVendorsWatcher on 2026-09-19 (see that screen's own comment). Left
  // in place with zero callers anywhere in lib/, it was the exact same class
  // of live foot-gun as getViewAllOffer() below: a raw, UNLOGGED geoflutterfire
  // radius listener (found 2026-09-20 alongside the same gap in getAllStores(),
  // which IS still called and has now been instrumented instead of removed).
  // If per-cuisine nearby-vendor filtering is needed again, extend
  // SharedVendorsWatcher rather than reconnecting this - it already shares
  // one listener per visit and is properly logged.

  // getViewAllOffer() removed (2026-09-02 cost cleanup) - it ran the EXACT
  // same query as getAllCoupons() below (COUPONS where isEnabled == true,
  // identical client-side expiry filter), but with zero cache at all versus
  // getAllCoupons()'s 5-minute TTL, and had zero callers anywhere in lib/ -
  // a live foot-gun (same class of bug as getVendors1/getReviewsbyVendorID,
  // removed earlier this session): if ever reconnected, it would silently
  // re-fetch the whole coupons collection on every call instead of sharing
  // getAllCoupons()'s cache. Use getAllCoupons() instead - same result.

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
        .snapshotsLogged('getOfferStreamByVendorID:COUPONS')
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
    await firestore.collection(FavouriteItem).where("product_id", isEqualTo: favouriteModel.product_id).getLogged('removeFavouriteItem:FavouriteItem').then((value) {
      value.docs.forEach((element) async {
        await firestore.collection(FavouriteItem).doc(element.id).deleteLogged('removeFavouriteItem:FavouriteItem');
      });
    });
  }

  static Future<void> setFavouriteItem(FavouriteItemModel favouriteModel) async {
    await firestore.collection(FavouriteItem).addLogged(favouriteModel.toJson(), 'setFavouriteItem:FavouriteItem');
  }

  // Same section-keyed TTL pattern as _cuisinesCache above.
  static final Map<String, (List<BannerModel>, DateTime)> _homeTopBannerCache = {};
  static const Duration _homeTopBannerCacheTtl = Duration(minutes: 10);

  // 2026-09-15: banner lists have no date/scheduling fields at all (see
  // BannerModel - just is_publish/position/set_order/photo), so unlike stories
  // there is no time-based expiry that a cached copy could get wrong. Admin
  // changes them roughly weekly, so a 24-hour on-device TTL (explicit product
  // decision) is comfortably conservative.
  //
  // This sits in FRONT of the Bunny mirror, not behind it, and that ordering
  // is the actual fix. fetchTopBannerFromBunny has an 8-second timeout, and on
  // a slow network (measured on-device 2026-09-15: 9-12s Firestore round
  // trips, 4.7-5.5s OSRM calls) that timeout is genuinely reachable - when it
  // trips, the code below falls through to a real Firestore query. That is
  // exactly what was observed: a cold start logging
  // `getHomeTopBanner:MENU_ITEM docs=3` even though the mirror itself is
  // healthy (verified live: HTTP 200). Serving from disk first means a slow
  // network can no longer convert a working CDN mirror into billed Firestore
  // reads - and it skips the HTTP round trip entirely, so the banner paints
  // sooner too.
  static const Duration _bannerPersistentTtl = Duration(hours: 24);

  Future<List<BannerModel>> getHomeTopBanner() async {
    final sectionId = sectionConstantModel!.id ?? '';
    final cached = _homeTopBannerCache[sectionId];
    final now = DateTime.now();
    if (cached != null && now.difference(cached.$2) < _homeTopBannerCacheTtl) {
      return cached.$1;
    }

    final persisted =
        await ConfigRefreshGate.readList('topBanner_$sectionId', _bannerPersistentTtl);
    if (persisted != null) {
      final banners = persisted.map((e) => BannerModel.fromJson(e)).toList()
        ..sort((a, b) => (a.setOrder ?? 0).compareTo(b.setOrder ?? 0));
      _homeTopBannerCache[sectionId] = (banners, now);
      debugPrint('[ConfigCache] top banners (${banners.length}) from on-device '
          'cache - no Bunny call, 0 Firestore reads');
      return banners;
    }

    // Read on every app cold start by every user - same fan-out class as
    // getCuisines() above, per the 2026-09-06 billing audit. Falls back to
    // the original Firestore query below on any failure.
    final mirrored = await fetchTopBannerFromBunny(sectionId);
    if (mirrored != null) {
      _homeTopBannerCache[sectionId] = (mirrored, now);
      // ignore: unawaited_futures
      ConfigRefreshGate.writeList(
          'topBanner_$sectionId', mirrored.map((b) => b.toJson()).toList());
      return mirrored;
    }

    List<BannerModel> bannerHome = [];
    QuerySnapshot<Map<String, dynamic>> bannerHomeQuery = await firestore
        .collection(MENU_ITEM)
        .where("is_publish", isEqualTo: true)
        .where('sectionId', isEqualTo: sectionId)
        .where("position", isEqualTo: "top")
        .orderBy("set_order", descending: false)
        .getLogged('getHomeTopBanner:MENU_ITEM');

    await Future.forEach(bannerHomeQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        bannerHome.add(BannerModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCuisines Parse error $e');
      }
    });
    _homeTopBannerCache[sectionId] = (bannerHome, now);
    // ignore: unawaited_futures
    ConfigRefreshGate.writeList(
        'topBanner_$sectionId', bannerHome.map((b) => b.toJson()).toList());
    return bannerHome;
  }

  // Same section-keyed TTL pattern as _cuisinesCache above.
  static final Map<String, (List<BannerModel>, DateTime)> _homeMiddleBannerCache = {};
  static const Duration _homeMiddleBannerCacheTtl = Duration(minutes: 10);

  Future<List<BannerModel>> getHomeMiddleBanner() async {
    final sectionId = sectionConstantModel!.id ?? '';
    final cached = _homeMiddleBannerCache[sectionId];
    final now = DateTime.now();
    if (cached != null && now.difference(cached.$2) < _homeMiddleBannerCacheTtl) {
      return cached.$1;
    }

    // Unlike the top banner there is NO Bunny mirror for this one - verified
    // live 2026-09-15 that middle-banner-lists/{sectionId}.json returns 404,
    // so this always fell through to Firestore. Even with zero middle banners
    // configured that still costs Firestore's one-read query minimum on every
    // cold start, which this cache removes. An empty result is cached
    // deliberately here (unlike tax/stories): "this section has no middle
    // banners" is a legitimate, stable answer, not a symptom of failure.
    final persisted = await ConfigRefreshGate.readList(
        'middleBanner_$sectionId', _bannerPersistentTtl);
    if (persisted != null) {
      final banners = persisted.map((e) => BannerModel.fromJson(e)).toList()
        ..sort((a, b) => (a.setOrder ?? 0).compareTo(b.setOrder ?? 0));
      _homeMiddleBannerCache[sectionId] = (banners, now);
      debugPrint('[ConfigCache] middle banners (${banners.length}) from '
          'on-device cache - 0 Firestore reads');
      return banners;
    }

    List<BannerModel> bannerHome = [];
    QuerySnapshot<Map<String, dynamic>> bannerHomeQuery = await firestore
        .collection(MENU_ITEM)
        .where("is_publish", isEqualTo: true)
        .where('sectionId', isEqualTo: sectionId)
        .where("position", isEqualTo: "middle")
        .orderBy("set_order", descending: false)
        .getLogged('getHomeMiddleBanner:MENU_ITEM');

    await Future.forEach(bannerHomeQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        bannerHome.add(BannerModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCuisines Parse error $e');
      }
    });
    _homeMiddleBannerCache[sectionId] = (bannerHome, now);
    // ignore: unawaited_futures
    ConfigRefreshGate.writeList(
        'middleBanner_$sectionId', bannerHome.map((b) => b.toJson()).toList());
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
  // 2026-09-25: currency is admin config that essentially never changes,
  // but this ran a fresh query on every location selection / service-list
  // open. 7-day on-device cache (ConfigRefreshGate list - every currency
  // field is a plain value, so nothing is dropped); the original query runs
  // on a miss and refills it.
  static const String _currencyCacheKey = 'activeCurrency';
  static const Duration _currencyCacheTtl = Duration(days: 7);

  Future<CurrencyModel?> getCurrency() async {
    CurrencyModel? currency;
    final cachedCurrency = await ConfigRefreshGate.readList(_currencyCacheKey, _currencyCacheTtl);
    if (cachedCurrency != null && cachedCurrency.isNotEmpty) {
      try {
        debugPrint('[ConfigCache] currency served from on-device cache - 0 Firestore reads');
        return CurrencyModel.fromJson(cachedCurrency.first);
      } catch (_) {}
    }
    await firestore.collection(Currency).where("isActive", isEqualTo: true).getLogged('getCurrency:Currency').then((value) {
      if (value.docs.isNotEmpty) {
        currency = CurrencyModel.fromJson(value.docs.first.data());
      }
    });
    final fetched = currency;
    if (fetched != null) {
      // ignore: unawaited_futures
      ConfigRefreshGate.writeList(_currencyCacheKey, [fetched.toJson()]);
    }
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

    // Read on every app cold start by every user, per the billing audit.
    // Falls back to the original Firestore query below on any failure (see
    // fetchCouponsFromBunny's own doc comment) - already applies the same
    // expiry validity filter this function does today.
    final mirrored = await fetchCouponsFromBunny();
    if (mirrored != null) {
      _allCouponsCache = mirrored;
      _allCouponsCachedAt = now;
      return mirrored;
    }

    List<OfferModel> coupon = [];
    // Single-field filter only — avoids composite index on (isEnabled, expiresAt)
    // which may not exist. expiresAt validity is enforced client-side.
    final nowTs = Timestamp.now();
    QuerySnapshot<Map<String, dynamic>> couponsQuery =
        await firestore.collection(COUPONS).where('isEnabled', isEqualTo: true).getLogged('getAllCoupons:COUPONS');
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
        .getLogged('getOfferByCabCoupons:CAB_COUPONS');

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
        await firestore.collection(CAB_COUPONS).where('isEnabled', isEqualTo: true).where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now()).getLogged('getCabCoupons:CAB_COUPONS');
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
        .getLogged('getOfferByParcelID:PARCELCOUPONS');

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
        await firestore.collection(PARCELCOUPONS).where('isEnabled', isEqualTo: true).where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now()).getLogged('getParcelCoupan:PARCELCOUPONS');
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
        .getLogged('getOfferByRentalCoupons:RENTALCOUPONS');

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
        await firestore.collection(RENTALCOUPONS).where('isEnabled', isEqualTo: true).where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now()).getLogged('getRentalCoupons:RENTALCOUPONS');
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
      vendorIdForBunny: vendorID,
    );
  }

  // Reuses Home's already-fetched whole-section catalog
  // (getAllProducts/getAllDelevryProducts/getAllTakeAWayProducts, all three
  // now sharing one cache entry under '${sectionId}_products' since
  // 2026-09-02 - see that consolidation's own comment) when it's warm,
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
    final sectionKey = '${sectionConstantModel!.id}_products';
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
      vendorIdForBunny: vendorID,
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
      vendorIdForBunny: vendorID,
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
        .getLogged('getVendorCategoryById:CATEGORIES');
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
            .getLogged('getVendorCategoriesByIds:CATEGORIES');
        return query.docs
            .map((d) => VendorCategoryModel.fromJson(d.data()))
            .toList();
      } catch (e) {
        print('FireStoreUtils.getVendorCategoriesByIds Parse error $e');
        return <VendorCategoryModel>[];
      }
    }));
    final fetched = results.expand((r) => r).toList();

    // Seed the same session cache newVendorProductsScreen checks *before*
    // calling this (productCategoryById, constants.dart) so a second vendor
    // open never re-queries a category this one already paid for.
    //
    // Why this was needed at all: that cache's only other writer is Home's
    // getCuisines(), which HomeScreen gates behind
    // `selctedOrderTypeValue == "Delivery" && isDeliveryActiveNotifier.value`
    // (HomeScreen.dart:694). Production runs Dineaway with delivery off, so
    // in practice that map was never populated, every vendor open was a
    // guaranteed 100% miss, and this query ran on every single vendor screen
    // — measured on-device 2026-09-10: 4 docs on both a cold open AND an
    // immediate warm reopen of the same vendor.
    //
    // Additive only: entries are added, never cleared here, so Home's own
    // ..clear()..addEntries rebuild stays the authoritative full-set writer
    // whenever delivery is on. Same section_id + publish==true filters as
    // getCuisines(), so the values are the identical shape from the identical
    // source — this only changes *when* they're in the map, never what's in it.
    for (final category in fetched) {
      final id = category.id;
      if (id != null && id.isNotEmpty) {
        productCategoryById.putIfAbsent(id, () => category);
      }
    }

    return fetched;
  }

  Future<VendorCategoryModel?> getVendorCategoryByCategoryId(String vendorCategoryID) async {
    DocumentSnapshot<Map<String, dynamic>> documentReference = await firestore.collection(CATEGORIES).doc(vendorCategoryID).getLogged('getVendorCategoryByCategoryId:CATEGORIES');
    if (documentReference.data() != null && documentReference.exists) {
      return VendorCategoryModel.fromJson(documentReference.data()!);
    } else {
      print("nulllll");
      return null;
    }
  }

  Future<ReviewAttributeModel?> getVendorReviewAttribute(String attrubuteId) async {
    DocumentSnapshot<Map<String, dynamic>> documentReference = await firestore.collection(REVIEW_ATTRIBUTES).doc(attrubuteId).getLogged('getVendorReviewAttribute:REVIEW_ATTRIBUTES');
    if (documentReference.data() != null && documentReference.exists) {
      return ReviewAttributeModel.fromJson(documentReference.data()!);
    } else {
      print("nulllll");
      return null;
    }
  }

  // 2026-09-06: deliberately NOT cached, unlike getVendor() above - checked
  // every call site first: 3 of 5 (CheckoutScreen._placeOrder's live
  // service-type gate, PaymentScreen._loadSeatAvailability's dine-in seat
  // setup, PaymentScreen's pre-payment order-build step) are checkout-
  // critical, safety-sensitive reads where a stale vendor.vendorDeliveryOpen/
  // seatingMode/totalSeats could let an order through against a vendor that
  // just closed or changed its seating config. A cache here trades a small
  // egress saving for real staleness risk on the one path where freshness
  // actually matters - not worth it, unlike the passive browsing/display
  // call sites getVendor() covers (Home, Product Details, reviews, etc.).
  /// 2026-09-25: the tiny vendor_live/{vendorId} doc (written only by the
  /// syncVendorLive Cloud Function) - the vendor's service switches, open
  /// status, seat settings, cuisineIds and businessTypeId, ~0.4 KB instead
  /// of the full vendor doc (2-10 KB). Fresh (server) read, same as
  /// getVendorByVendorID, for the checkout-time gates that need current
  /// values but not the rest of the doc. Returns null if the doc is missing
  /// or the read fails - callers then fall back to getVendorByVendorID.
  Future<VendorModel?> getVendorLive(String vendorID) async {
    try {
      final doc = await firestore
          .collection('vendor_live')
          .doc(vendorID)
          .getLogged('getVendorLive:vendor_live');
      final data = doc.data();
      if (!doc.exists || data == null) return null;
      return VendorModel.fromJson(data);
    } catch (e) {
      debugPrint('getVendorLive($vendorID) failed, falling back to full doc: $e');
      return null;
    }
  }

  Future<VendorModel> getVendorByVendorID(String vendorID) async {
    late VendorModel vendor;
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore.collection(VENDORS).where('id', isEqualTo: vendorID).getLogged('getVendorByVendorID:VENDORS');
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
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore.collection(PRODUCTS).where('id', isEqualTo: productId).where('publish', isEqualTo: true).getLogged('getProductByProductID:PRODUCTS');
    try {
      if (vendorsQuery.docs.isNotEmpty) {
        productModel = ProductModel.fromJson(vendorsQuery.docs.first.data());
      }
    } catch (e) {
      print('FireStoreUtils.getVendorByVendorID Parse error $e');
    }
    return productModel;
  }

  // 2026-09-06: deliberately NOT cached - CartScreen calls this directly for
  // live line-item pricing (price must always be fresh, per explicit
  // instruction), so a shared cache here would risk serving a stale price at
  // checkout. Order Details (this function's other caller) already has its
  // own sufficient per-screen-visit memoization (_productByIdFutureCache),
  // so it didn't actually need a shared cache either.
  Future<ProductModel> getProductByID(String productId) async {
    late ProductModel productModel;
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore.collection(PRODUCTS).where('id', isEqualTo: productId).getLogged('getProductByID:PRODUCTS');
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
  // 2026-09-15: 10-minute per-product TTL (explicit product decision) - this
  // used to re-fetch every cart line's product data from scratch on every
  // single Cart open, with zero caching at all. Verified safe against
  // verifyProducts (orderVerification.js): for any product that still exists,
  // the server independently re-fetches its OWN copy from `vendor_products`
  // and uses that price, never whatever the client cached - so a stale
  // client-side price here can only affect the pre-checkout display, never
  // what's actually charged. The one pre-existing, narrower edge case (a
  // product deleted between fetch and checkout falls back to the client's
  // submitted price server-side) is unrelated to this cache - it already
  // existed with zero caching, just with a ~seconds instead of ~10-minute
  // window - and is being closed separately by the pre-payment blocking work
  // (orderPreflight.js).
  //
  // Cached per product id (not per call, since different Cart opens/reorders
  // request different id sets that often overlap) - each call only queries
  // Firestore for the ids that are missing or expired.
  static final Map<String, (ProductModel, DateTime)> _productByIdCache = {};
  static const Duration _productByIdCacheTtl = Duration(minutes: 10);

  Future<Map<String, ProductModel>> fetchProductsByIds(
      List<String> productIds) async {
    final result = <String, ProductModel>{};
    final now = DateTime.now();
    final uncachedIds = <String>[];
    for (final id in productIds.toSet()) {
      final cached = _productByIdCache[id];
      if (cached != null && now.difference(cached.$2) < _productByIdCacheTtl) {
        result[id] = cached.$1;
      } else {
        uncachedIds.add(id);
      }
    }
    if (uncachedIds.isEmpty) {
      debugPrint('[ConfigCache] fetchProductsByIds: all ${result.length} '
          'products served from cache - 0 Firestore reads');
      return result;
    }

    final chunks = dedupeAndChunkIds(uncachedIds);
    if (chunks.isEmpty) return result;

    await Future.wait(chunks.map((chunk) async {
      try {
        final snapshot =
            await firestore.collection(PRODUCTS).where('id', whereIn: chunk).getLogged('fetchProductsByIds:PRODUCTS');
        for (final doc in snapshot.docs) {
          try {
            final product = ProductModel.fromJson(doc.data());
            result[product.id] = product;
            _productByIdCache[product.id] = (product, now);
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
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore.collection(Order_Rating).where('orderid', isEqualTo: ordertId).getLogged('getReviewsbyID:Order_Rating');
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
        await firestore.collection(Order_Rating).where('orderid', isEqualTo: ordertId).where('VendorId', isEqualTo: providerId).getLogged('getReviewsbyProviderID:Order_Rating');
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
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore.collection(Order_Rating).where('orderid', isEqualTo: ordertId).where('driverId', isEqualTo: workerId).getLogged('getReviewsbyWorkerID:Order_Rating');
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
        await firestore.collection(Order_Rating).where('orderid', isEqualTo: ordertId).where('productId', isEqualTo: productId).getLogged('getOrderReviewsbyID:Order_Rating');
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

  // getReviewsbyVendorID / getReviewByDriverId removed (2026-09-01 cost
  // cleanup) - unbounded whole-Order_Rating-collection scans (filtered only
  // by VendorId/driverId, no .limit(), no cache) with zero callers anywhere
  // in lib/. Flagged in a 2026-09-01 cost audit as a live foot-gun: for a
  // long-lived popular vendor/driver this could grow into thousands of doc
  // reads re-scanned on every call if ever reconnected without a bound. If
  // this capability is needed again, rebuild it with a real .limit() (and
  // ideally .orderBy('createdAt', descending: true) + pagination) from the
  // start rather than restoring this version.

  static Future<RatingModel?> updateReviewbyId(RatingModel ratingproduct) async {
    return await firestore.collection(Order_Rating).doc(ratingproduct.id).setLogged(ratingproduct.toJson(), 'updateReviewbyId:Order_Rating').then((document) {
      return ratingproduct;
    });
  }

  static Future<List<FavouriteModel>> getFavouriteStore(String userId) async {
    List<FavouriteModel> favouriteItem = [];

    QuerySnapshot<Map<String, dynamic>> vendorsQuery =
        await firestore.collection(FavouriteStore).where('user_id', isEqualTo: userId).where("section_id", isEqualTo: sectionConstantModel!.id).getLogged('getFavouriteStore:FavouriteStore');
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
    await documentReference.setLogged(orderModel.toJson(), 'bookTable:ORDERS_TABLE');
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
    // 2026-09-25: was every booking this vendor ever had (then filtered to
    // one day in memory) - ~128 KB per dine-in details open for Rath, and
    // growing forever. Now only bookings whose `date` is within a day of the
    // chosen date: every booking has `date` (checked on all 53 in
    // production; 28 old ones have no bookingDateKey), and `date` is never
    // more than 5.5 h from bookingDateKey, so the +/-1 day window keeps
    // every booking the exact in-memory check below could match. Indexes:
    // booked_table (vendorID, date) and (vendorID, slotId, date).
    query = query
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay.subtract(const Duration(days: 1))))
        .where('date', isLessThan: Timestamp.fromDate(endOfDay.add(const Duration(days: 1))));
    final snapshot = await query.getLogged('getBookingCountForDate:ORDERS_TABLE');

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

  // A customer who already has an active table booking for this vendor
  // today already told us their party size at booking time - re-asking
  // "how many people?" on the Dining PaymentScreen is redundant (2026-08-28).
  // Sums totalGuest across every active booking this customer has for this
  // vendor today (rare, but a customer could have more than one), returning
  // null when there's none - the caller falls back to the normal picker in
  // that case, same "no default for an unconfigured/uninvolved case" rule
  // as effectiveSeatCapacity's own null fallback.
  static Future<int?> getExistingBookingGuestCountToday({
    required String vendorId,
    required String customerId,
  }) async {
    final today = DateTime.now();
    final dateKey = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    // 2026-09-25: was all of this customer's bookings at this vendor, ever
    // (~102 KB for the heaviest customer), filtered to today in memory. Same
    // +/-1 day `date` window as getBookingCountForDate - the in-memory
    // bookingDateKey == today check below is unchanged. Index: booked_table
    // (vendorID, authorID, date).
    final dayStart = DateTime(today.year, today.month, today.day);
    final snapshot = await firestore
        .collection(ORDERS_TABLE)
        .where('vendorID', isEqualTo: vendorId)
        .where('authorID', isEqualTo: customerId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart.subtract(const Duration(days: 1))))
        .where('date', isLessThan: Timestamp.fromDate(dayStart.add(const Duration(days: 2))))
        .getLogged('getExistingBookingGuestCountToday:ORDERS_TABLE');

    // Picks the single most recent matching booking's guest count rather
    // than summing across all of today's matches (2026-08-29 fix) - summing
    // never made sense (two separate same-day bookings aren't one party of
    // N), and became visibly wrong once a since-fixed gap let a customer
    // rack up several duplicate bookings for the same day: this returned
    // their combined guest count as if it were one party size.
    Timestamp? latestCreatedAt;
    int? guestsForLatest;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = data['status'] as String? ?? '';
      if (status == 'Cancelled' || status == 'Rejected') continue;
      if ((data['bookingDateKey'] as String?) != dateKey) continue;
      final createdAt = data['createdAt'];
      if (createdAt is! Timestamp) continue;
      if (latestCreatedAt == null || createdAt.compareTo(latestCreatedAt) > 0) {
        latestCreatedAt = createdAt;
        final guestVal = data['totalGuest'];
        guestsForLatest = (guestVal is num && guestVal > 0) ? guestVal.toInt() : 1;
      }
    }
    return guestsForLatest;
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
    // Reads the vendor's OWN blocked-dates list live, inside the same
    // transaction, rather than trusting a value the caller already had in
    // memory - the picker on dine_in_restaurant_details_screen.dart already
    // excludes a blocked date, but this is the actual enforcement point
    // (2026-08-28), same "guard at the write, not just the UI" pattern as
    // the capacity check right below it. Closes the gap where a vendor
    // blocks a date after the customer already has the booking screen open.
    final vendorRef = firestore.collection(VENDORS).doc(vendorId);
    // Walk-in Dining occupancy and table-booking capacity used to be two
    // blind, independent pools drawing from the same physical seats
    // (2026-08-28 fix) - a vendor could be genuinely full from walk-ins
    // alone while a new booking still sailed through because it only ever
    // checked its own dine_in_capacity doc. Only meaningful for 'flexible'
    // bookings: dine_in_occupancy is a per-vendor-per-day figure with no
    // slot granularity, so combining it into a single slot's own capacity
    // check wouldn't be dimensionally comparable (slot-based is hidden
    // from the Dine-In Settings UI as of 2026-08-27 anyway - see AddDineIn.
    // dart - but the underlying function still supports it, untouched).
    final occupancyRef =
        bookingType == 'flexible' ? firestore.collection(DINE_IN_OCCUPANCY).doc(vendorId) : null;
    await firestore.runTransaction((tx) async {
      // Logged (2026-09-19): up to THREE billed reads in this one
      // transaction, times every retry - see LoggedTransactionGet.
      final vendorSnap =
          await tx.getLogged(vendorRef, 'reserveBookingCapacity:VENDORS (tx)');
      final blockedDates = List<String>.from(vendorSnap.data()?['bookingBlockedDates'] ?? []);
      if (blockedDates.contains(dateKey)) {
        throw BookingDateBlockedException();
      }
      final snap = await tx.getLogged(
          ref, 'reserveBookingCapacity:DINE_IN_CAPACITY (tx)');
      final occupied = (snap.data()?['occupiedGuests'] as num?)?.toInt() ?? 0;
      int walkInOccupied = 0;
      if (occupancyRef != null) {
        final occupancySnap = await tx.getLogged(
            occupancyRef, 'reserveBookingCapacity:DINE_IN_OCCUPANCY (tx)');
        walkInOccupied = (occupancySnap.data()?['occupiedGuests'] as num?)?.toInt() ?? 0;
      }
      if (occupied + walkInOccupied + guestCount > maxCapacity) {
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
      final snap = await tx.getLogged(
          ref, 'releaseBookingCapacity:DINE_IN_CAPACITY (tx)');
      final occupied = (snap.data()?['occupiedGuests'] as num?)?.toInt() ?? 0;
      final next = occupied - guestCount;
      tx.set(ref, {'occupiedGuests': next < 0 ? 0 : next}, SetOptions(merge: true));
    });
  }

  // Real-time seat availability vs. the vendor's effective seat capacity -
  // seatCapacity if explicitly set, else guestCapacity (table booking) as a
  // single-source-of-truth fallback (2026-08-26) so a vendor doesn't have
  // to fill in the same number twice. Still allowed to diverge: a vendor
  // may reserve only some of their total seats for advance bookings,
  // leaving the rest for walk-ins - set seatCapacity explicitly via
  // SeatAvailabilityScreen to override the fallback.
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
    // seatAvailabilityOn (2026-08-27) is the vendor's own separate
    // pause/resume for the same banner - see its own VendorModel comment.
    if (!vendor.seatAvailabilityEnabled || !vendor.seatAvailabilityOn) return Stream.value(null);
    final capacity = vendor.effectiveSeatCapacity;
    if (capacity == null || capacity <= 0) return Stream.value(null);

    // Combines two previously-blind occupancy sources (2026-08-28 fix):
    // dine_in_occupancy (walk-in Dining orders, unchanged meaning - still
    // maintained server-side by functions/dineOccupancy.js) and today's
    // dine_in_capacity 'flexible' doc (table bookings). Before this, the
    // banner only ever showed the walk-in half, so a vendor already full
    // from table bookings alone could still show seats "vacant." Manual
    // dual-stream combine (no rxdart dependency) - tracks the latest value
    // from each source and re-emits occupiedGuests as their sum whenever
    // either one changes. Slot-based bookings aren't included here for the
    // same reason reserveBookingCapacity only combines for 'flexible' -
    // dine_in_occupancy has no slot granularity to compare against.
    final today = DateTime.now();
    final todayKey = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final bookingDocId = '${vendor.id}_flexible_$todayKey';

    late StreamController<SeatAvailability?> controller;
    StreamSubscription? occupancySub;
    StreamSubscription? bookingSub;
    int walkInGuests = 0;
    int bookingGuests = 0;
    DateTime? nextFreeAt;
    bool haveOccupancy = false;
    bool haveBooking = false;

    void emit() {
      // Wait for at least one snapshot from each source before the first
      // emission, so the banner never briefly flashes a wrong, half-summed
      // number on initial load.
      if (!haveOccupancy || !haveBooking) return;
      controller.add(SeatAvailability(
        occupiedGuests: walkInGuests + bookingGuests,
        maxCapacity: capacity,
        nextFreeAt: nextFreeAt,
      ));
    }

    // .broadcast() (2026-09-01 fix) - PaymentScreen now shows this banner
    // in two places at once for a brief overlap (the guest-count sheet's
    // own copy, still mid-dismiss-animation, and the payment page's copy
    // that just mounted underneath it the instant "Next" is tapped). A
    // plain single-subscription controller throws "Stream has already been
    // listened to" the moment the second StreamBuilder attaches - which
    // Flutter's build-time error handling then surfaces as a full-screen
    // "Something went wrong", wiping out the payment page entirely. Broadcast
    // also means the two listeners share one live Firestore subscription
    // instead of each spinning up their own (relevant to Firestore read cost).
    controller = StreamController<SeatAvailability?>.broadcast(
      onListen: () {
        occupancySub = firestore.collection(DINE_IN_OCCUPANCY).doc(vendor.id).snapshotsLogged('streamCurrentSeatAvailability:DINE_IN_OCCUPANCY').listen((doc) {
          // A vendor with no aggregate doc yet (no Dining orders ever, or
          // the trigger hasn't fired for them yet) is simply at zero
          // occupancy - not an error state, nothing to distinguish from
          // "quiet right now".
          walkInGuests = doc.exists ? (doc.data()?['occupiedGuests'] as num?)?.toInt() ?? 0 : 0;
          final nextFreeTs = doc.data()?['nextFreeAt'];
          nextFreeAt = nextFreeTs is Timestamp ? nextFreeTs.toDate() : null;
          haveOccupancy = true;
          emit();
        });
        bookingSub = firestore.collection(DINE_IN_CAPACITY).doc(bookingDocId).snapshotsLogged('streamCurrentSeatAvailability:DINE_IN_CAPACITY').listen((doc) {
          bookingGuests = doc.exists ? (doc.data()?['occupiedGuests'] as num?)?.toInt() ?? 0 : 0;
          haveBooking = true;
          emit();
        });
      },
      onCancel: () {
        occupancySub?.cancel();
        bookingSub?.cancel();
      },
    );
    return controller.stream;
  }

  // One-time combined-capacity snapshot for a specific booking date
  // (2026-08-28) - used by the "Select Date" step on the table-booking
  // screen itself, so a customer can be told a date is already fully
  // booked (with a "seats may free up around HH:MM" estimate, for today)
  // before they even pick a time and hit the SlotCapacityExceededException
  // rejection at Confirm. Deliberately NOT gated on seatAvailabilityEnabled/
  // seatAvailabilityOn - those control the separate, optional walk-in
  // crowding banner; this is core table-booking UX, always relevant
  // whenever a booking is being attempted, regardless of that toggle.
  // Only meaningful for 'flexible' bookingType (see reserveBookingCapacity's
  // own comment on why slot-based isn't combined this way).
  static Future<SeatAvailability?> getDateAvailabilitySnapshot({
    required VendorModel vendor,
    required String dateKey,
  }) async {
    if (vendor.bookingType != 'flexible') return null;
    final capacity = vendor.guestCapacity;
    // A null capacity means the vendor enabled table booking without ever
    // setting one (2026-08-29: guestCapacity no longer defaults to 50) -
    // treat exactly like "no availability info" rather than fabricating a
    // ceiling.
    if (capacity == null || capacity <= 0) return null;

    final bookingDoc = await firestore
        .collection(DINE_IN_CAPACITY)
        .doc(_capacityDocId(vendorId: vendor.id, bookingType: 'flexible', slotId: '', dateKey: dateKey))
        .getLogged('getDateAvailabilitySnapshot:DINE_IN_CAPACITY');
    final bookingGuests = (bookingDoc.data()?['occupiedGuests'] as num?)?.toInt() ?? 0;

    // Walk-in occupancy (and the nextFreeAt estimate) is inherently a live,
    // right-now concept - only relevant when checking today, never a
    // future date that hasn't started occupying anything yet.
    final today = DateTime.now();
    final todayKey = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    int walkInGuests = 0;
    DateTime? nextFreeAt;
    if (dateKey == todayKey) {
      final occDoc = await firestore.collection(DINE_IN_OCCUPANCY).doc(vendor.id).getLogged('getDateAvailabilitySnapshot:DINE_IN_OCCUPANCY');
      walkInGuests = (occDoc.data()?['occupiedGuests'] as num?)?.toInt() ?? 0;
      final nextFreeTs = occDoc.data()?['nextFreeAt'];
      nextFreeAt = nextFreeTs is Timestamp ? nextFreeTs.toDate() : null;
    }

    return SeatAvailability(
      occupiedGuests: bookingGuests + walkInGuests,
      maxCapacity: capacity,
      nextFreeAt: nextFreeAt,
    );
  }

  Future<OrderModel> placeOrder(OrderModel orderModel) async {
    DocumentReference documentReference = firestore.collection(ORDERS).doc(orderModel.id);
    orderModel.id = documentReference.id;
    // merge: true — if this order id was already written once (e.g. a retry
    // after an error that happened after the first write succeeded), a
    // plain overwrite would wipe server-added fields like walletCredited/
    // priceVerified, making Cloud Functions treat the order as freshly
    // completed again and pay the vendor a second time.
    await documentReference.setLogged(orderModel.toJson(), 'placeOrder:ORDERS', SetOptions(merge: true));
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
    await documentReference.setLogged(orderModel.toJson(), 'placeOrderWithTakeAWay:ORDERS', SetOptions(merge: true));
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
    QuerySnapshot<Map<String, dynamic>> documentReference = await firestore.collection(Wallet).where('user_id', isEqualTo: userId).orderBy('date', descending: true).limit(20).getLogged('getTopUpTransaction:Wallet');
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

    await firestore.collection("wallet").doc(id).setLogged(adminCommission.toJson(), 'topUpOtherWalletAmount:wallet').then((value) {
      firestore.collection("wallet").doc(id).getLogged('topUpOtherWalletAmount:wallet').then((value) {
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
      await firestore.collection(USERS).doc(userId).updateLogged({
        "wallet_amount": FieldValue.increment(double.parse(amount.toString())),
      }, 'updateOtherWalletAmount:USERS');
      // Atomic increment doesn't hand back the new value - invalidate rather
      // than guess, in case that uid is cached from an earlier lookup
      // (chat/order participant, etc).
      _userCache.remove(userId);
    } catch (error) {
      print('updateOtherWalletAmount error: $error');
    }
  }

  static Future updateWalletAmount({required amount}) async {
    final userId = MyAppState.currentUser!.userID;
    try {
      // Atomic increment — no read-before-write, eliminates double-spend race.
      // Pass a negative amount to deduct (e.g. amount = -orderTotal).
      await firestore.collection(USERS).doc(userId).updateLogged({
        "wallet_amount": FieldValue.increment(double.parse(amount.toString())),
      }, 'updateWalletAmount:USERS');
      // Re-read to sync local state with the server-committed balance.
      final updated = await firestore.collection(USERS).doc(userId).getLogged('updateWalletAmount:USERS');
      if (updated.data() != null) {
        MyAppState.currentUser = User.fromJson(updated.data()!);
        _userCache[userId] = MyAppState.currentUser!;
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
    // 2026-09-16: address is now null for Dineaway orders (no delivery
    // happening) - was orderModel.address!.getFullAddress(), a force-unwrap
    // that would have silently broken this email (caught by the
    // .catchError((_) {}) at its call site, PlaceOrderScreen.dart's
    // _sendNotificationsBackground, with no visible error to anyone) for
    // every Dineaway order the moment address could be null.
    newString = newString.replaceAll(
      "{address}",
      orderModel.address?.getFullAddress() ?? '',
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
    await firestore.collection(emailTemplates).where('type', isEqualTo: type).getLogged('getEmailTemplates:emailTemplates').then((value) {
      if (value.docs.isNotEmpty) {
        emailTemplateModel = EmailTemplateModel.fromJson(value.docs.first.data());
      }
    });
    return emailTemplateModel;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchOrderStatus(String orderID) async* {
    yield* firestore.collection(ORDERS).doc(orderID).snapshotsLogged('watchOrderStatus:ORDERS');
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

      await firestore.collection(USERS).doc(user.userID).setLogged(user.toJson(), 'firebaseCreateNewUser:USERS');
      _userCache[user.userID] = user;
    } catch (e, s) {
      print('FireStoreUtils.firebaseCreateNewUser $e $s');
      return "notSignUp".tr();
    }
    return null;
  }

  static Future<String?> referralAdd(ReferralModel ratingModel) async {
    try {
      await firestore.collection(REFERRAL).doc(ratingModel.id).setLogged(ratingModel.toJson(), 'referralAdd:REFERRAL');
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
      DocumentSnapshot<Map<String, dynamic>> documentSnapshot = await firestore.collection(USERS).doc(result.user?.uid ?? '').getLogged('loginWithEmailAndPassword:USERS');
      User? user;

      if (documentSnapshot.exists) {
        // if(user!.role != 'vendor'){
        user = User.fromJson(documentSnapshot.data() ?? {});
        // if(  USER_ROLE_CUSTOMER ==user.role)
        // {
        user.fcmToken = await firebaseMessaging.getToken() ?? '';

        //user.active = true;

        //      }
        _userCache[user.userID] = user;
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
      final uid = auth.FirebaseAuth.instance.currentUser!.uid;
      await firestore.collection(USERS).doc(uid).deleteLogged('deleteUser:USERS');
      _userCache.remove(uid);

      await auth.FirebaseAuth.instance.currentUser!.delete();
    } catch (e, s) {
      print('FireStoreUtils.deleteUser $e $s');
    }
  }

  Future<OrderModel?> getOrderById(String? orderId) async {
    DocumentSnapshot<Map<String, dynamic>> userDocument = await firestore.collection(ORDERS).doc(orderId).getLogged('getOrderById:ORDERS');
    if (userDocument.data() != null && userDocument.exists) {
      return OrderModel.fromJson(userDocument.data()!);
    } else {
      return null;
    }
  }

  getContactUs() async {
    Map<String, dynamic> contactData = {};
    await firestore.collection(Setting).doc(CONTACT_US).getLogged('getContactUs:Setting').then((value) {
      if (value.exists && value.data() != null) contactData = value.data()!;
    });

    return contactData;
  }

  Future<GiftCardsOrderModel> placeGiftCardOrder(GiftCardsOrderModel giftCardsOrderModel) async {
    await firestore.collection(GIFT_PURCHASES).doc(giftCardsOrderModel.id).setLogged(giftCardsOrderModel.toJson(), 'placeGiftCardOrder:GIFT_PURCHASES');
    return giftCardsOrderModel;
  }

  Future<List<GiftCardsOrderModel>> getGiftHistory() async {
    List<GiftCardsOrderModel> giftCardsOrderList = [];
    await firestore.collection(GIFT_PURCHASES).where("userid", isEqualTo: MyAppState.currentUser!.userID).getLogged('getGiftHistory:GIFT_PURCHASES').then((value) {
      for (var element in value.docs) {
        GiftCardsOrderModel giftCardsOrderModel = GiftCardsOrderModel.fromJson(element.data());
        giftCardsOrderList.add(giftCardsOrderModel);
      }
    });
    return giftCardsOrderList;
  }

  Future<GiftCardsOrderModel?> checkRedeemCode(String giftCode) async {
    GiftCardsOrderModel? giftCardsOrderModel;
    await firestore.collection(GIFT_PURCHASES).where("giftCode", isEqualTo: giftCode).getLogged('checkRedeemCode:GIFT_PURCHASES').then((value) {
      if (value.docs.isNotEmpty) {
        giftCardsOrderModel = GiftCardsOrderModel.fromJson(value.docs.first.data());
      }
    });
    return giftCardsOrderModel;
  }

  static Future<List<GiftCardsModel>> getGiftCard() async {
    List<GiftCardsModel> giftCardModelList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(GIFT_CARDS).where("isEnable", isEqualTo: true).getLogged('getGiftCard:GIFT_CARDS');
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

    QuerySnapshot<Map<String, dynamic>> reviewQuery = await firestore.collection(Order_Rating).where('productId', isEqualTo: serviceId).getLogged('getReviewByProviderServiceId:Order_Rating');
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
    return await firestore.collection("chat_provider").doc(inboxModel.orderId).setLogged(inboxModel.toJson(), 'addProviderInbox:chat_provider').then((document) {
      return inboxModel;
    });
  }

  static Future addProviderChat(ConversationModel conversationModel) async {
    return await firestore
        .collection("chat_provider")
        .doc(conversationModel.orderId)
        .collection("thread")
        .doc(conversationModel.id)
        .setLogged(conversationModel.toJson(), 'addProviderChat:chat_provider')
        .then((document) {
      return conversationModel;
    });
  }

  static Future addWorkerInbox(InboxModel inboxModel) async {
    return await firestore.collection("chat_worker").doc(inboxModel.orderId).setLogged(inboxModel.toJson(), 'addWorkerInbox:chat_worker').then((document) {
      return inboxModel;
    });
  }

  static Future addWorkerChat(ConversationModel conversationModel) async {
    return await firestore.collection("chat_worker").doc(conversationModel.orderId).collection("thread").doc(conversationModel.id).setLogged(conversationModel.toJson(), 'addWorkerChat:chat_worker').then((document) {
      return conversationModel;
    });
  }

  static Future<List<RatingModel>> getVendorReviews(String vendorId) async {
    List<RatingModel> ratingList = [];
    await firestore.collection(Order_Rating).where('VendorId', isEqualTo: vendorId).limit(20).getLogged('getVendorReviews:Order_Rating').then((value) {
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
    final snapshot = await query.getLogged('getVendorReviewsPaginated:Order_Rating');
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
