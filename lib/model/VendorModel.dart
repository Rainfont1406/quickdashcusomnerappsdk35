import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/model/BookingSlotModel.dart';
import 'package:emartconsumer/model/DeliveryChargeModel.dart';
import 'package:emartconsumer/model/SpecialDiscountModel.dart';
import 'package:emartconsumer/model/WorkingHoursModel.dart';

import '../constants.dart';

class VendorModel {
  String author;

  String authorName;

  String authorProfilePic;

  String categoryID;

  String fcmToken;

  String categoryPhoto;

  String categoryTitle;

  // Store-level Cuisine selection (North Indian, Chinese, Pizza, ...) -
  // deliberately separate from categoryID/categoryTitle above, which is the
  // vestigial store-level copy of the product-level food category (the
  // Vendor App/Web's Add Store screen never actually let a vendor pick it
  // through any real UI). cuisineNames is denormalized alongside cuisineIds
  // so search/display never need a second Firestore query.
  List<String> cuisineIds;
  List<String> cuisineNames;

  // Store-level Business Type selection (Cafe, Restaurant, Canteen, ...) -
  // single-select, unlike cuisineIds/cuisineNames above. businessTypeName is
  // denormalized alongside businessTypeId for the same reason cuisineNames is.
  String businessTypeId;
  String businessTypeName;

  Timestamp? createdAt;

  String description;

  String phonenumber;

  Map<String, dynamic> filters;

  String id;

  double latitude;

  double longitude;

  String photo; // vendor logo, square — unrelated to the 16:9 pipeline below

  // `photos` (restaurant gallery) and `vendorMenuPhotos` (Dine-In ambience/menu
  // photos) entries are {'original': url, 'cover': url} maps so the unmodified
  // master asset and the generated 16:9 cover (1600x900) are both kept. Older
  // entries saved before this change are plain URL strings — use coverPhotoUrl()
  // / originalPhotoUrl() below rather than reading entries directly, since both
  // shapes can appear in the same list.
  List<dynamic> photos;
  List<dynamic> vendorMenuPhotos;

  /// 16:9 cover URL for a photos/vendorMenuPhotos entry, regardless of whether
  /// it's a legacy plain-URL string or a {original, cover} map.
  static String coverPhotoUrl(dynamic entry) {
    if (entry is Map) return (entry['cover'] ?? entry['original'] ?? '').toString();
    return entry?.toString() ?? '';
  }

  /// Unmodified master-asset URL for a photos/vendorMenuPhotos entry.
  static String originalPhotoUrl(dynamic entry) {
    if (entry is Map) return (entry['original'] ?? entry['cover'] ?? '').toString();
    return entry?.toString() ?? '';
  }

  String location;
  String locality;
  String landmark;

  num reviewsCount, vendorCost;

  num reviewsSum;
  GeoFireData geoFireData;

  String title, section_id;

  String opentime, openDineTime;

  String closetime, closeDineTime;

  bool hidephotos;

  bool reststatus;
  bool isVendorOnline;
  bool enabledDiveInFuture;

  // Phase 1 real-time seat availability (see
  // TABLE_BOOKING_CAPACITY_AND_DEPOSIT_PLAN.html) - deliberately separate
  // from guestCapacity below, which is a Phase-2 booking-config field that
  // ALWAYS defaults to 50 even when the vendor never touched it. This field
  // must stay genuinely nullable: null means "vendor hasn't set this up,"
  // and that restaurant must be excluded from the feature entirely, not
  // silently treated as some default capacity.
  int? seatCapacity;

  // ── Dine-In Booking Configuration ──────────────────────────────
  String bookingType;              // 'flexible' | 'slot_based'
  String bookingOpenTime;
  String bookingCloseTime;
  int minBookingNoticeMinutes;
  int maxAdvanceBookingDays;
  int guestCapacity;
  int bufferTimeBetweenReservations;
  String bookingPricingModel;      // 'free' | 'per_person' | 'table_charge' | 'cover_charge'
  num bookingCharge;
  int minGuests;
  int maxGuests;
  String approvalMode;             // 'auto' | 'manual'
  List<BookingSlotModel> bookingSlots;
  String cuisineType;
  bool deliveryEnabled;
  bool takeawayEnabled;
  bool diningEnabled;
  bool billPayEnabled;

  // Store-level opt-in for a UI-only 7-minute countdown shown on the
  // customer's Order Details screen after a Bill Pay order — a visual cue
  // for crowded self-checkout stores that the screen is live, not a
  // screenshot. Not a security/expiry mechanism. See OrderDetailsScreen.
  bool enableBillPaymentTimer;

  // Derived — admin controls sub-types (takeaway / dining), not dineaway itself
  bool get dineAwayEnabled => takeawayEnabled || diningEnabled;

  // Vendor-controlled service pause flags
  bool vendorDeliveryOpen;
  bool vendorDineawayOpen;

  // Vendor's requested services (informational for admin only — not used for customer-facing control)
  bool wantsDelivery;
  bool wantsTakeaway;
  bool wantsDining;
  DeliveryChargeModel? deliveryCharge;
  List<WorkingHoursModel> workingHours;
  List<SpecialDiscountModel> specialDiscount;
  bool specialDiscountEnable;

  List<Map<String, dynamic>>? topProducts;

  VendorModel(
      {this.author = '',
      this.hidephotos = false,
      this.authorName = '',
      this.authorProfilePic = '',
      this.categoryID = '',
      this.categoryPhoto = '',
      this.categoryTitle = '',
      this.cuisineIds = const [],
      this.cuisineNames = const [],
      this.businessTypeId = '',
      this.businessTypeName = '',
      this.createdAt,
      this.filters = const {},
      this.description = '',
      this.phonenumber = '',
      this.fcmToken = '',
      this.id = '',
      this.section_id = '',
      this.latitude = 0.1,
      this.longitude = 0.1,
      this.photo = '',
      this.photos = const [],
      this.vendorMenuPhotos = const [],
      this.specialDiscount = const [],
      this.specialDiscountEnable = false,
      this.location = '',
      this.locality = '',
      this.landmark = '',
      this.reviewsCount = 0,
      this.reviewsSum = 0,
      this.vendorCost = 0,
      this.closetime = '',
      this.opentime = '',
      this.closeDineTime = '',
      this.openDineTime = '',
      this.title = '',
      this.workingHours = const [],
      this.reststatus = false,
      this.isVendorOnline = false,
      this.enabledDiveInFuture = false,
      this.seatCapacity,
      this.bookingType = 'flexible',
      this.bookingOpenTime = '',
      this.bookingCloseTime = '',
      this.minBookingNoticeMinutes = 30,
      this.maxAdvanceBookingDays = 7,
      this.guestCapacity = 50,
      this.bufferTimeBetweenReservations = 15,
      this.bookingPricingModel = 'free',
      this.bookingCharge = 0,
      this.minGuests = 1,
      this.maxGuests = 20,
      this.approvalMode = 'auto',
      this.bookingSlots = const [],
      this.cuisineType = '',
      this.deliveryEnabled = true,
      this.takeawayEnabled = true,
      this.diningEnabled = true,
      this.billPayEnabled = false,
      this.enableBillPaymentTimer = false,
      this.vendorDeliveryOpen = true,
      this.vendorDineawayOpen = true,
      this.wantsDelivery = true,
      this.wantsTakeaway = true,
      this.wantsDining = true,
      this.topProducts,
      geoFireData,
      this.deliveryCharge})
      : geoFireData = geoFireData ??
            GeoFireData(
              geohash: "",
              geoPoint: const GeoPoint(0.0, 0.0),
            );

  // ,this.filters = filters ?? Filters(cuisine: '');

  factory VendorModel.fromJson(Map<String, dynamic> parsedJson) {
    num restCost = 0;
    if (parsedJson.containsKey("vendorCost")) {
      if (parsedJson['vendorCost'] == null ||
          parsedJson['vendorCost'].toString().isEmpty) {
        restCost = 0;
      } else if (parsedJson['vendorCost'] is String) {
        restCost = num.parse(parsedJson['vendorCost']);
      } else if (parsedJson['vendorCost'] is num) {
        restCost = parsedJson['vendorCost'];
      }
    }
    List<SpecialDiscountModel> specialDiscount =
        parsedJson.containsKey('specialDiscount')
            ? List<SpecialDiscountModel>.from(
                (parsedJson['specialDiscount'] as List<dynamic>)
                    .map((e) => SpecialDiscountModel.fromJson(e))).toList()
            : [].cast<SpecialDiscountModel>();

    List<WorkingHoursModel> workingHours =
        parsedJson.containsKey('workingHours')
            ? List<WorkingHoursModel>.from(
                (parsedJson['workingHours'] as List<dynamic>)
                    .map((e) => WorkingHoursModel.fromJson(e))).toList()
            : [].cast<WorkingHoursModel>();
    return VendorModel(
      author: parsedJson['author'] ?? '',
      hidephotos: parsedJson['hidephotos'] ?? false,
      authorName: parsedJson['authorName'] ?? '',
      authorProfilePic: parsedJson['authorProfilePic'] ?? '',
      categoryID: parsedJson['categoryID'] ?? '',
      categoryPhoto: parsedJson['categoryPhoto'] ?? '',
      categoryTitle: parsedJson['categoryTitle'] ?? '',
      cuisineIds: parsedJson['cuisineIds'] != null ? List<String>.from(parsedJson['cuisineIds']) : [],
      cuisineNames: parsedJson['cuisineNames'] != null ? List<String>.from(parsedJson['cuisineNames']) : [],
      businessTypeId: parsedJson['businessTypeId'] ?? '',
      businessTypeName: parsedJson['businessTypeName'] ?? '',
      createdAt: parsedJson['createdAt'] ?? Timestamp.now(),
      deliveryCharge: (parsedJson.containsKey('deliveryCharge') &&
              parsedJson['deliveryCharge'] != null)
          ? DeliveryChargeModel.fromJson(parsedJson['deliveryCharge'])
          : null,
      description: parsedJson['description'] ?? '',
      phonenumber: parsedJson['phonenumber'] ?? '',
      id: parsedJson['id'] ?? '',
      section_id: parsedJson['section_id'] ?? '',
      geoFireData: parsedJson.containsKey('g')
          ? GeoFireData.fromJson(parsedJson['g'])
          : GeoFireData(
              geohash: "",
              geoPoint: const GeoPoint(0.0, 0.0),
            ),
      latitude: getDoubleVal(parsedJson['latitude']),
      longitude: getDoubleVal(parsedJson['longitude']),
      photo: parsedJson['photo'] ?? '',
      photos: parsedJson['photos'] ?? [],
      vendorMenuPhotos: parsedJson['vendorMenuPhotos'] ?? [],
      location: parsedJson['location'] ?? '',
      locality: parsedJson['locality'] ?? '',
      landmark: parsedJson['landmark'] ?? '',
      fcmToken: parsedJson['fcmToken'] ?? '',
      reviewsCount: parsedJson['reviewsCount'] ?? 0,
      reviewsSum: parsedJson['reviewsSum'] ?? 0,
      vendorCost: restCost,
      title: parsedJson['title'] ?? '',
      closetime: parsedJson['closetime'] ?? '',
      opentime: parsedJson['opentime'] ?? '',
      closeDineTime: parsedJson['closeDineTime'] ?? '',
      openDineTime: parsedJson['openDineTime'] ?? '',
      reststatus: parsedJson['reststatus'] ?? false,
      isVendorOnline: parsedJson['isVendorOnline'] ?? false,
      enabledDiveInFuture: parsedJson['enabledDiveInFuture'] ?? false,
      workingHours: workingHours,
      specialDiscountEnable: parsedJson['specialDiscountEnable'] ?? false,
      specialDiscount: specialDiscount,
      // No default - stays null when absent so an unconfigured vendor is
      // correctly excluded from Phase 1 seat availability, not treated as
      // some fallback capacity.
      seatCapacity: (parsedJson['seatCapacity'] is num) ? (parsedJson['seatCapacity'] as num).toInt() : null,
      bookingType: parsedJson['bookingType'] as String? ?? 'flexible',
      bookingOpenTime: parsedJson['bookingOpenTime'] as String? ?? '',
      bookingCloseTime: parsedJson['bookingCloseTime'] as String? ?? '',
      minBookingNoticeMinutes: (parsedJson['minBookingNoticeMinutes'] is num) ? (parsedJson['minBookingNoticeMinutes'] as num).toInt() : 30,
      maxAdvanceBookingDays: (parsedJson['maxAdvanceBookingDays'] is num) ? (parsedJson['maxAdvanceBookingDays'] as num).toInt() : 7,
      guestCapacity: (parsedJson['guestCapacity'] is num) ? (parsedJson['guestCapacity'] as num).toInt() : 50,
      bufferTimeBetweenReservations: (parsedJson['bufferTimeBetweenReservations'] is num) ? (parsedJson['bufferTimeBetweenReservations'] as num).toInt() : 15,
      bookingPricingModel: parsedJson['bookingPricingModel'] as String? ?? 'free',
      bookingCharge: parsedJson['bookingCharge'] is num ? parsedJson['bookingCharge'] as num : 0,
      minGuests: (parsedJson['minGuests'] is num) ? (parsedJson['minGuests'] as num).toInt() : 1,
      maxGuests: (parsedJson['maxGuests'] is num) ? (parsedJson['maxGuests'] as num).toInt() : 20,
      approvalMode: parsedJson['approvalMode'] as String? ?? 'auto',
      bookingSlots: parsedJson.containsKey('bookingSlots') && parsedJson['bookingSlots'] is List
          ? (parsedJson['bookingSlots'] as List).map((e) => BookingSlotModel.fromJson(e as Map<String, dynamic>)).toList()
          : [],
      cuisineType: parsedJson['cuisineType'] as String? ?? '',
      deliveryEnabled: parsedJson['deliveryEnabled'] as bool? ?? true,
      takeawayEnabled: parsedJson['takeawayEnabled'] as bool? ?? true,
      diningEnabled: parsedJson['diningEnabled'] as bool? ?? true,
      billPayEnabled: parsedJson['billPayEnabled'] as bool? ?? false,
      enableBillPaymentTimer: parsedJson['enableBillPaymentTimer'] as bool? ?? false,
      vendorDeliveryOpen: parsedJson['vendorDeliveryOpen'] as bool? ?? true,
      vendorDineawayOpen: parsedJson['vendorDineawayOpen'] as bool? ?? true,
      wantsDelivery: parsedJson['wantsDelivery'] as bool? ?? true,
      wantsTakeaway: parsedJson['wantsTakeaway'] as bool? ?? true,
      wantsDining: parsedJson['wantsDining'] as bool? ?? true,
      topProducts: parsedJson['topProducts'] != null
          ? List<Map<String, dynamic>>.from(
              (parsedJson['topProducts'] as List).map(
                (e) => Map<String, dynamic>.from(e as Map)))
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {
      'author': author,
      'hidephotos': hidephotos,
      'authorName': authorName,
      'authorProfilePic': authorProfilePic,
      'categoryID': categoryID,
      'categoryPhoto': categoryPhoto,
      'categoryTitle': categoryTitle,
      'cuisineIds': cuisineIds,
      'cuisineNames': cuisineNames,
      'businessTypeId': businessTypeId,
      'businessTypeName': businessTypeName,
      'createdAt': createdAt,
      'description': description,
      'phonenumber': phonenumber,
      'filters': filters,
      'vendorCost': vendorCost,
      'id': id,
      'section_id': section_id,
      "g": geoFireData.toJson(),
      'latitude': latitude,
      'longitude': longitude,
      'photo': photo,
      'photos': photos,
      'vendorMenuPhotos': vendorMenuPhotos,
      'location': location,
      'locality': locality,
      'landmark': landmark,
      'fcmToken': fcmToken,
      'reviewsCount': reviewsCount,
      'reviewsSum': reviewsSum,
      'title': title,
      'opentime': opentime,
      'closetime': closetime,
      'openDineTime': openDineTime,
      'closeDineTime': closeDineTime,
      'reststatus': reststatus,
      'isVendorOnline': isVendorOnline,
      'enabledDiveInFuture': enabledDiveInFuture,
      'specialDiscount': this.specialDiscount.map((e) => e.toJson()).toList(),
      'specialDiscountEnable': this.specialDiscountEnable,
      'workingHours': workingHours.map((e) => e.toJson()).toList(),
      'seatCapacity': seatCapacity,
      'bookingType': bookingType,
      'bookingOpenTime': bookingOpenTime,
      'bookingCloseTime': bookingCloseTime,
      'minBookingNoticeMinutes': minBookingNoticeMinutes,
      'maxAdvanceBookingDays': maxAdvanceBookingDays,
      'guestCapacity': guestCapacity,
      'bufferTimeBetweenReservations': bufferTimeBetweenReservations,
      'bookingPricingModel': bookingPricingModel,
      'bookingCharge': bookingCharge,
      'minGuests': minGuests,
      'maxGuests': maxGuests,
      'approvalMode': approvalMode,
      'bookingSlots': bookingSlots.map((e) => e.toJson()).toList(),
      'cuisineType': cuisineType,
      'deliveryEnabled': deliveryEnabled,
      'takeawayEnabled': takeawayEnabled,
      'diningEnabled': diningEnabled,
      'billPayEnabled': billPayEnabled,
      'enableBillPaymentTimer': enableBillPaymentTimer,
      'vendorDeliveryOpen': vendorDeliveryOpen,
      'vendorDineawayOpen': vendorDineawayOpen,
      'wantsDelivery': wantsDelivery,
      'wantsTakeaway': wantsTakeaway,
      'wantsDining': wantsDining,
    };
    if (deliveryCharge != null) {
      json.addAll({'deliveryCharge': deliveryCharge!.toJson()});
    }
    return json;
  }

  /// Single source of truth for "is this vendor currently accepting
  /// orders" — the vendor's manual toggle AND (no schedule configured OR
  /// currently within scheduled hours). Use this everywhere a restaurant
  /// card/badge/filter needs to decide open vs. closed, instead of each
  /// screen re-deriving its own formula (which is how several screens
  /// drifted out of sync with each other).
  bool get isAcceptingOrders => reststatus && (workingHours.isEmpty || isOpen());

  bool isOpen() {
    try {
      final now = DateTime.now();
      final todayName = DateFormat('EEEE', 'en_US').format(now);
      final yesterdayName = DateFormat('EEEE', 'en_US')
          .format(now.subtract(const Duration(days: 1)));
      final todayDate = DateFormat('dd-MM-yyyy').format(now);
      final yesterdayDate = DateFormat('dd-MM-yyyy')
          .format(now.subtract(const Duration(days: 1)));

      for (var element in workingHours) {
        final slots = element.timeslot;
        if (slots == null || slots.isEmpty) continue;

        final isToday = element.day.toString() == todayName;
        final isYesterday = element.day.toString() == yesterdayName;
        if (!isToday && !isYesterday) continue;

        for (var timeslot in slots) {
          if (timeslot.from == null || timeslot.to == null) continue;
          final dateStr = isToday ? todayDate : yesterdayDate;
          var start = DateFormat("dd-MM-yyyy HH:mm")
              .parse("$dateStr ${timeslot.from}");
          var end = DateFormat("dd-MM-yyyy HH:mm")
              .parse("$dateStr ${timeslot.to}");
          if (!end.isAfter(start)) {
            // Midnight-crossing slot — extend end to next calendar day
            end = end.add(const Duration(days: 1));
          } else if (isYesterday) {
            // Yesterday's non-crossing slot never reaches today
            continue;
          }
          if (isCurrentDateInRange(start, end)) return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  bool isCurrentDateInRange(DateTime startDate, DateTime endDate) {
    final currentDate = DateTime.now();
    return currentDate.isAfter(startDate) && currentDate.isBefore(endDate);
  }
}

class GeoFireData {
  String? geohash;
  GeoPoint? geoPoint;

  GeoFireData({this.geohash, this.geoPoint});

  factory GeoFireData.fromJson(Map<dynamic, dynamic> parsedJson) {
    return GeoFireData(
      geohash: parsedJson['geohash'] ?? '',
      // geoPoint is typed GeoPoint? - a bare `?? ''` fallback assigned a
      // String into that field whenever a vendor's geopoint was null,
      // which is a real type violation under sound null safety and threw
      // at parse time (found 2026-08-23: silently dropped any order whose
      // permanently-embedded vendor snapshot had geopoint: null, since the
      // whole OrderModel.fromJson call is wrapped in a try/catch upstream
      // that swallows the exception with no visible error). null is
      // already a valid, correctly-typed value here - just use it.
      geoPoint: parsedJson['geopoint'] is GeoPoint ? parsedJson['geopoint'] as GeoPoint : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'geohash': geohash,
      'geopoint': geoPoint,
    };
  }
}

class Filters {
  String cuisine;

  String wifi;

  String breakfast;

  String dinner;

  String lunch;

  String seating;

  String vegan;

  String reservation;

  String music;

  String price;

  Filters(
      {required this.cuisine,
      this.seating = '',
      this.price = '',
      this.breakfast = '',
      this.dinner = '',
      this.lunch = '',
      this.music = '',
      this.reservation = '',
      this.vegan = '',
      this.wifi = ''});

  factory Filters.fromJson(Map<dynamic, dynamic> parsedJson) {
    return Filters(
        cuisine: parsedJson["Cuisine"] ?? '',
        wifi: parsedJson["Free Wi-Fi"] ?? 'No',
        breakfast: parsedJson["Good for Breakfast"] ?? 'No',
        dinner: parsedJson["Good for Dinner"] ?? 'No',
        lunch: parsedJson["Good for Lunch"] ?? 'No',
        music: parsedJson["Live Music"] ?? 'No',
        price: parsedJson["Price"] ?? '\$',
        reservation: parsedJson["Takes Reservations"] ?? 'No',
        vegan: parsedJson["Vegetarian Friendly"] ?? 'No',
        seating: parsedJson["Outdoor Seating"] ?? 'No');
  }

  Map<String, dynamic> toJson() {
    return {
      'Cuisine': cuisine,
      'Free Wi-Fi': wifi,
      'Good for Breakfast': breakfast,
      'Good for Dinner': dinner,
      'Good for Lunch': lunch,
      'Live Music': music,
      'Price': price,
      'Takes Reservations': reservation,
      'Vegetarian Friendly': vegan,
      'Outdoor Seating': seating
    };
  }
}
