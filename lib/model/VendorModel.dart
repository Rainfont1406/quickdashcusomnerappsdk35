import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
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

  Timestamp? createdAt;

  String description;

  String phonenumber;

  Map<String, dynamic> filters;

  String id;

  double latitude;

  double longitude;

  String photo;

  List<dynamic> photos;
  List<dynamic> vendorMenuPhotos;

  String location;

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
  DeliveryChargeModel? deliveryCharge;
  List<WorkingHoursModel> workingHours;
  List<SpecialDiscountModel> specialDiscount;
  bool specialDiscountEnable;

  VendorModel(
      {this.author = '',
      this.hidephotos = false,
      this.authorName = '',
      this.authorProfilePic = '',
      this.categoryID = '',
      this.categoryPhoto = '',
      this.categoryTitle = '',
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
    };
    if (deliveryCharge != null) {
      json.addAll({'deliveryCharge': deliveryCharge!.toJson()});
    }
    return json;
  }

  bool isOpen() {
    final now = DateTime.now();
    var day = DateFormat('EEEE', 'en_US').format(now);
    var date = DateFormat('dd-MM-yyyy').format(now);
    for (var element in workingHours) {
      if (day == element.day.toString()) {
        if (element.timeslot!.isNotEmpty) {
          for (var timeslot in element.timeslot!) {
            var start = DateFormat("dd-MM-yyyy HH:mm").parse("$date ${timeslot.from}");
            var end = DateFormat("dd-MM-yyyy HH:mm").parse("$date ${timeslot.to}");
            if (isCurrentDateInRange(start, end)) {
              return true;
            }
          }
        }
      }
    }
    return false;
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
      geoPoint: parsedJson['geopoint'] ?? '',
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
