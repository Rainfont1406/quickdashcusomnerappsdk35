import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/AddressModel.dart';
import 'package:emartconsumer/model/OrderModel.dart';
import 'package:flutter/foundation.dart';

class User with ChangeNotifier {
  String email;

  String firstName;

  String lastName;

  UserSettings settings;

  String phoneNumber;

  bool active;
  bool isActive;

  Timestamp lastOnlineTimestamp;

  String userID;
  String countryCode;

  String profilePictureURL;

  String appIdentifier;

  String fcmToken;

  UserLocation location;

  List<AddressModel>? shippingAddress = [];

  String? stripeCustomer;

  String role;

  String carName;

  String carNumber;

  String carPictureURL;

  String? inProgressOrderID;
  String? vendorID;
  dynamic wallet_amount;

  OrderModel? orderRequestData;
  UserBankDetails userBankDetails;
  GeoFireData geoFireData;
  GeoPoint coordinates;
  String serviceType;
  String vehicleType;
  String carMakes;
  num? rotation;
  num reviewsCount;
  num reviewsSum;
  bool isCompany;

  String companyId;
  String companyName;
  String companyAddress;
  String driverRate;
  String carRate;
  CarInfo? carInfo;
  List<dynamic>? rentalBookingDate;
  Timestamp? createdAt;
  // Stored as ISO date string "yyyy-MM-dd"; null when not set.
  String? dob;

  User(
      {this.email = '',
      this.userID = '',
      this.countryCode = '',
      this.profilePictureURL = '',
      this.firstName = '',
      this.phoneNumber = '',
      this.lastName = '',
      this.active = true,
      this.isActive = false,
      this.wallet_amount = 0.0,
      this.shippingAddress,
      userBankDetails,
      geoFireData,
      coordinates,
      lastOnlineTimestamp,
      settings,
      this.fcmToken = '',
      location,
      this.stripeCustomer,
      this.rotation,
      this.role = USER_ROLE_DRIVER,
      this.carName = '',
      this.carNumber = '',
      this.carMakes = '',
      this.reviewsCount = 0,
      this.reviewsSum = 0,
      this.carPictureURL = '',
      this.serviceType = "",
      this.vehicleType = "",
      this.inProgressOrderID = '',
      this.orderRequestData,
      this.isCompany = false,
      this.rentalBookingDate,
      this.companyId = "",
      this.companyName = "",
      this.companyAddress = "",
      this.driverRate = "0",
      this.carRate = "0",
      this.vendorID = "",
      this.createdAt,
      this.dob,
      carInfo})
      : lastOnlineTimestamp = lastOnlineTimestamp ?? Timestamp.now(),
        settings = settings ?? UserSettings(),
        appIdentifier = 'Flutter Uber Eats Consumer ${Platform.operatingSystem}',
        location = location ?? UserLocation(),
        userBankDetails = userBankDetails ?? UserBankDetails(),
        coordinates = coordinates ?? const GeoPoint(0.0, 0.0),
        carInfo = carInfo ?? CarInfo(),
        geoFireData = geoFireData ??
            GeoFireData(
              geohash: "",
              geoPoint: const GeoPoint(0.0, 0.0),
            );

  String fullName() {
    return ((email.isEmpty) && (phoneNumber.isEmpty)) ? 'Login to Manage' : '$firstName $lastName'.trim();
  }

  factory User.fromJson(Map<String, dynamic> parsedJson) {
    List<AddressModel>? shippingAddressList = [];
    if (parsedJson['shippingAddress'] != null) {
      shippingAddressList = <AddressModel>[];
      parsedJson['shippingAddress'].forEach((v) {
        shippingAddressList!.add(AddressModel.fromJson(v));
      });
    }
    return User(
        wallet_amount: parsedJson['wallet_amount'] ?? 0.0,
        email: parsedJson['email'] ?? '',
        firstName: parsedJson['firstName'] ?? '',
        lastName: parsedJson['lastName'] ?? '',
        active: parsedJson['active'] ?? true,
        isActive: parsedJson['isActive'] ?? false,
        lastOnlineTimestamp: _parseTimestamp(parsedJson['lastOnlineTimestamp']),
        userBankDetails: parsedJson.containsKey('userBankDetails') ? UserBankDetails.fromJson(parsedJson['userBankDetails']) : UserBankDetails(),
        geoFireData: parsedJson.containsKey('g')
            ? GeoFireData.fromJson(parsedJson['g'])
            : GeoFireData(
                geohash: "",
                geoPoint: const GeoPoint(0.0, 0.0),
              ),
        coordinates: parsedJson['coordinates'] ?? const GeoPoint(0.0, 0.0),
        settings: parsedJson.containsKey('settings') ? UserSettings.fromJson(parsedJson['settings']) : UserSettings(),
        phoneNumber: parsedJson['phoneNumber'] ?? '',
        userID: parsedJson['id'] ?? parsedJson['userID'] ?? '',
        countryCode: parsedJson['countryCode'] ?? parsedJson['countryCode'] ?? '',
        profilePictureURL: parsedJson['profilePictureURL'] ?? '',
        fcmToken: parsedJson['fcmToken'] ?? '',
        location: parsedJson.containsKey('location') ? UserLocation.fromJson(parsedJson['location']) : UserLocation(),
        shippingAddress: shippingAddressList,
        driverRate: parsedJson['driverRate'] ?? '',
        carRate: parsedJson['carRate'] ?? '',
        carInfo: parsedJson.containsKey('carInfo') ? CarInfo.fromJson(parsedJson['carInfo']) : CarInfo(),
        stripeCustomer: parsedJson['stripeCustomer'],
        role: parsedJson['role'] ?? '',
        carName: parsedJson['carName'] ?? '',
        carNumber: parsedJson['carNumber'] ?? '',
        carPictureURL: parsedJson['carPictureURL'] ?? '',
        inProgressOrderID: parsedJson['inProgressOrderID'],
        serviceType: parsedJson['serviceType'] ?? '',
        vehicleType: parsedJson['vehicleType'] ?? '',
        carMakes: parsedJson['carMakes'] ?? '',
        rotation: parsedJson['rotation'] ?? 0.0,
        reviewsCount: parsedJson['reviewsCount'] ?? 0,
        reviewsSum: parsedJson['reviewsSum'] ?? 0,
        isCompany: parsedJson['isCompany'] ?? false,
        companyId: parsedJson['companyId'] ?? '',
        companyName: parsedJson['companyName'] ?? '',
        companyAddress: parsedJson['companyAddress'] ?? '',
        rentalBookingDate: parsedJson['rentalBookingDate'] ?? [],
        vendorID: parsedJson['vendorID'] ?? '',
        createdAt: _parseTimestamp(parsedJson['createdAt']),
        dob: parsedJson['dob'],
        orderRequestData: parsedJson.containsKey('orderRequestData') ? OrderModel.fromJson(parsedJson['orderRequestData']) : null);
  }

  // A handful of older documents have createdAt stored as a plain RFC3339
  // string instead of a Firestore Timestamp (predates the fsNowTimestamp()
  // fix) - assigning that String straight into this Timestamp? field throws
  // at parse time and silently drops the whole containing document (e.g. an
  // order embedding this user as its author) from whatever stream is
  // listening. Tolerate both shapes instead of trusting the data is clean.
  static Timestamp? _parseTimestamp(dynamic raw) {
    if (raw is Timestamp) return raw;
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return Timestamp.fromDate(parsed);
    }
    return null;
  }

  factory User.fromPayload(Map<String, dynamic> parsedJson) {
    List<AddressModel>? shippingAddressList = [];
    if (parsedJson['shippingAddress'] != null) {
      shippingAddressList = <AddressModel>[];
      parsedJson['shippingAddress'].forEach((v) {
        shippingAddressList!.add(AddressModel.fromJson(v));
      });
    }
    return User(
        wallet_amount: parsedJson['wallet_amount'] ?? 0.0,
        email: parsedJson['email'] ?? '',
        firstName: parsedJson['firstName'] ?? '',
        lastName: parsedJson['lastName'] ?? '',
        active: parsedJson['active'] ?? true,
        isActive: parsedJson['isActive'] ?? false,
        lastOnlineTimestamp: Timestamp.fromMillisecondsSinceEpoch(parsedJson['lastOnlineTimestamp']),
        settings: parsedJson.containsKey('settings') ? UserSettings.fromJson(parsedJson['settings']) : UserSettings(),
        userBankDetails: parsedJson.containsKey('userBankDetails') ? UserBankDetails.fromJson(parsedJson['userBankDetails']) : UserBankDetails(),
        geoFireData: parsedJson.containsKey('g')
            ? GeoFireData.fromJson(parsedJson['g'])
            : GeoFireData(
                geohash: "",
                geoPoint: const GeoPoint(0.0, 0.0),
              ),
        coordinates: parsedJson['coordinates'] ?? const GeoPoint(0.0, 0.0),
        phoneNumber: parsedJson['phoneNumber'] ?? '',
        userID: parsedJson['id'] ?? parsedJson['userID'] ?? '',
        countryCode: parsedJson['id'] ?? parsedJson['countryCode'] ?? '',
        profilePictureURL: parsedJson['profilePictureURL'] ?? '',
        fcmToken: parsedJson['fcmToken'] ?? '',
        rotation: parsedJson['rotation'] ?? 0.0,
        driverRate: parsedJson['driverRate'] ?? '',
        carRate: parsedJson['carRate'] ?? '',
        carInfo: parsedJson.containsKey('carInfo') ? CarInfo.fromJson(parsedJson['carInfo']) : CarInfo(),
        location: parsedJson.containsKey('location') ? UserLocation.fromJson(parsedJson['location']) : UserLocation(),
        shippingAddress: shippingAddressList,
        stripeCustomer: parsedJson['stripeCustomer'] ?? '',
        role: parsedJson['role'] ?? '',
        carMakes: parsedJson['carMakes'] ?? '',
        carName: parsedJson['carName'] ?? '',
        carNumber: parsedJson['carNumber'] ?? '',
        carPictureURL: parsedJson['carPictureURL'] ?? '',
        inProgressOrderID: parsedJson['inProgressOrderID'],
        serviceType: parsedJson['serviceType'] ?? '',
        vehicleType: parsedJson['vehicleType'] ?? '',
        reviewsCount: parsedJson['reviewsCount'] ?? 0,
        reviewsSum: parsedJson['reviewsSum'] ?? 0,
        isCompany: parsedJson['isCompany'] ?? false,
        companyId: parsedJson['companyId'] ?? '',
        companyName: parsedJson['companyName'] ?? '',
        companyAddress: parsedJson['companyAddress'] ?? '',
        rentalBookingDate: parsedJson['rentalBookingDate'] ?? [],
        vendorID: parsedJson['vendorID'] ?? '',
        createdAt: _parseTimestamp(parsedJson['createdAt']),
        dob: parsedJson['dob'],
        orderRequestData: parsedJson.containsKey('orderRequestData') ? OrderModel.fromJson(parsedJson['orderRequestData']) : null);
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {
      'wallet_amount': wallet_amount,
      'email': email,
      'firstName': firstName,
      'lastName': lastName,
      'settings': settings.toJson(),
      'phoneNumber': phoneNumber,
      'id': userID,
      'countryCode': countryCode,
      'active': active,
      'lastOnlineTimestamp': lastOnlineTimestamp,
      'profilePictureURL': profilePictureURL,
      'appIdentifier': appIdentifier,
      'fcmToken': fcmToken,
      'location': location.toJson(),
      'stripeCustomer': stripeCustomer,
      'role': role,
      "g": geoFireData.toJson(),
      'coordinates': coordinates,
      "userBankDetails": userBankDetails.toJson(),
      'createdAt': this.createdAt,
      'dob': dob,
      'shippingAddress': shippingAddress != null ? shippingAddress!.map((v) => v.toJson()).toList() : null,
    };
    if (role == USER_ROLE_PROVIDER) {
      json.addAll({
        'reviewsCount': reviewsCount,
        'reviewsSum': reviewsSum,
      });
    }
    if (role == USER_ROLE_DRIVER) {
      json.addAll({
        'role': role,
        'isActive': isActive,
        'carName': carName,
        'carNumber': carNumber,
        'carPictureURL': carPictureURL,
        'vehicleType': vehicleType,
        'carMakes': carMakes,
        'rotation': rotation,
        'reviewsCount': reviewsCount,
        'reviewsSum': reviewsSum,
        'isCompany': isCompany,
        'companyId': companyId,
        'companyName': companyName,
        'companyAddress': companyAddress,
        'serviceType': serviceType,
        'driverRate': driverRate,
        'carRate': carRate,
        'carInfo': carInfo!.toJson(),
        'rentalBookingDate': rentalBookingDate,
      });
    }
    if (role == USER_ROLE_VENDOR) {
      json.addAll({
        'vendorID': vendorID,
      });
    }
    if (inProgressOrderID != null) {
      json.addAll({'inProgressOrderID': inProgressOrderID});
    }
    return json;
  }

  Map<String, dynamic> toPayload() {
    Map<String, dynamic> json = {
      'wallet_amount': wallet_amount,
      'email': email,
      'firstName': firstName,
      'lastName': lastName,
      'settings': settings.toJson(),
      'phoneNumber': phoneNumber,
      'id': userID,
      'active': active,
      'lastOnlineTimestamp': lastOnlineTimestamp.millisecondsSinceEpoch,
      'profilePictureURL': profilePictureURL,
      'appIdentifier': appIdentifier,
      'fcmToken': fcmToken,
      'location': location.toJson(),
      'shippingAddress': shippingAddress != null ? shippingAddress!.map((v) => v.toJson()).toList() : null,
      'stripeCustomer': stripeCustomer,
      'role': role,
      "g": geoFireData.toJson(),
      'coordinates': coordinates,
      "userBankDetails": userBankDetails.toJson(),
      'createdAt': this.createdAt,
      'dob': dob,
    };
    if (role == USER_ROLE_DRIVER) {
      json.addAll({
        'role': role,
        'isActive': isActive,
        'carName': carName,
        'carNumber': carNumber,
        'carPictureURL': carPictureURL,
        'vehicleType': vehicleType,
        'carMakes': carMakes,
        'rotation': rotation,
        'reviewsCount': reviewsCount,
        'reviewsSum': reviewsSum,
        'isCompany': isCompany,
        'companyId': companyId,
        'companyName': companyName,
        'companyAddress': companyAddress,
        'serviceType': serviceType,
        'driverRate': driverRate,
        'carRate': carRate,
        'carInfo': carInfo!.toJson(),
        'rentalBookingDate': rentalBookingDate,
      });
    }
    if (role == USER_ROLE_VENDOR) {
      json.addAll({
        'vendorID': vendorID,
      });
    }
    if (inProgressOrderID != null) {
      json.addAll({'inProgressOrderID': inProgressOrderID});
    }
    return json;
  }
}

class UserSettings {
  bool pushNewMessages;

  bool orderUpdates;

  bool newArrivals;

  bool promotions;

  UserSettings({this.pushNewMessages = true, this.orderUpdates = true, this.newArrivals = true, this.promotions = true});

  factory UserSettings.fromJson(Map<dynamic, dynamic> parsedJson) {
    return UserSettings(
      pushNewMessages: parsedJson['pushNewMessages'] ?? true,
      orderUpdates: parsedJson['orderUpdates'] ?? true,
      newArrivals: parsedJson['newArrivals'] ?? true,
      promotions: parsedJson['promotions'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pushNewMessages': pushNewMessages,
      'orderUpdates': orderUpdates,
      'newArrivals': newArrivals,
      'promotions': promotions,
    };
  }
}

class UserLocation {
  double latitude;
  double longitude;

  UserLocation({this.latitude = 0.01, this.longitude = 0.01});

  factory UserLocation.fromJson(Map<dynamic, dynamic> parsedJson) {
    return UserLocation(
      latitude: parsedJson['latitude'] ?? 00.1,
      longitude: parsedJson['longitude'] ?? 00.1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}

class GeoFireData {
  String? geohash;
  GeoPoint? geoPoint;

  GeoFireData({this.geohash, this.geoPoint});

  factory GeoFireData.fromJson(Map<dynamic, dynamic> parsedJson) {
    return GeoFireData(
      geohash: parsedJson['geohash'] ?? '',
      geoPoint: parsedJson['geopoint'] is GeoPoint
          ? parsedJson['geopoint'] as GeoPoint
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'geohash': geohash,
      'geopoint': geoPoint,
    };
  }
}

class UserBankDetails {
  String bankName;

  String branchName;

  String holderName;

  String accountNumber;

  String otherDetails;

  UserBankDetails({
    this.bankName = '',
    this.otherDetails = '',
    this.branchName = '',
    this.accountNumber = '',
    this.holderName = '',
  });

  factory UserBankDetails.fromJson(Map<String, dynamic> parsedJson) {
    return UserBankDetails(
      bankName: parsedJson['bankName'] ?? '',
      branchName: parsedJson['branchName'] ?? '',
      holderName: parsedJson['holderName'] ?? '',
      accountNumber: parsedJson['accountNumber'] ?? '',
      otherDetails: parsedJson['otherDetails'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bankName': bankName,
      'branchName': branchName,
      'holderName': holderName,
      'accountNumber': accountNumber,
      'otherDetails': otherDetails,
    };
  }
}

class CarInfo {
  String? passenger;
  String? doors;
  String? airConditioning;
  String? gear;
  String? mileage;
  String? fuelFilling;
  String? fuelType;
  String? maxPower;
  String? mph;
  String? topSpeed;
  List<dynamic>? carImage;

  CarInfo({
    this.passenger,
    this.doors,
    this.airConditioning,
    this.gear,
    this.mileage,
    this.fuelFilling,
    this.fuelType,
    this.carImage,
    this.maxPower,
    this.mph,
    this.topSpeed,
  });

  CarInfo.fromJson(Map<String, dynamic> json) {
    passenger = json['passenger'] ?? "";
    doors = json['doors'] ?? "";
    airConditioning = json['air_conditioning'] ?? "";
    gear = json['gear'] ?? "";
    mileage = json['mileage'] ?? "";
    fuelFilling = json['fuel_filling'] ?? "";
    fuelType = json['fuel_type'] ?? "";
    carImage = json['car_image'] ?? [];
    maxPower = json['maxPower'] ?? "";
    mph = json['mph'] ?? "";
    topSpeed = json['topSpeed'] ?? "";
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['passenger'] = passenger;
    data['doors'] = doors;
    data['air_conditioning'] = airConditioning;
    data['gear'] = gear;
    data['mileage'] = mileage;
    data['fuel_filling'] = fuelFilling;
    data['fuel_type'] = fuelType;
    data['car_image'] = carImage;
    data['maxPower'] = maxPower;
    data['mph'] = mph;
    data['topSpeed'] = topSpeed;
    return data;
  }
}
