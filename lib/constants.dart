import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/model/CurrencyModel.dart';
import 'package:emartconsumer/model/SectionModel.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/model/mail_setting.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/widget/permission_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'model/TaxModel.dart';

const FINISHED_ON_BOARDING = 'finishedOnBoarding';
const COUPON_BG_COLOR = 0xFFFCF8F3;
const DARK_BG_COLOR = 0xff121212;
const COUPON_DASH_COLOR = 0xFFCACFDA;
const GREY_TEXT_COLOR = 0xff5E5C5C;
const DarkContainerColor = 0xff26272C;
const DarkContainerBorderColor = 0xff515151;

const PROVIDER_ORDER = "provider_orders";
const ORDER_STATUS_ONGOING = "Order Ongoing";
const ORDER_STATUS_COMPLETED = "Order Completed";
const ORDER_STATUS_REJECTED = "Order Rejected";
const ORDER_STATUS_CANCELLED = "Order Cancelled";
const ORDER_STATUS_ASSIGNED = "Order Assigned";

String appVersion = '';
const List colorList = [
  Color(0xFFFFBC99),
  const Color(0xFFCABDFF),
  const Color(0xFFB1E5FC),
  const Color(0xFFB5EBCD),
  const Color(0xFFFFD88D),
  const Color(0xFFCBEBA4),
  const Color(0xFFFB9B9B),
  const Color(0xFFF8B0ED),
  const Color(0xFFAFC6FF)
];

const USERS = 'users';
const ONBoarding = 'on_boarding';
const VEHICLETYPE = 'vehicle_type';
const RENTALVEHICLETYPE = 'rental_vehicle_type';
const REPORTS = 'reports';
const Deliverycharge = 6;
const CATEGORIES = 'vendor_categories';
const VENDORS = 'vendors';
const PRODUCTS = 'vendor_products';
const SECTION = 'sections';
const SERVICE = 'service';
const BANNER = 'Banner';
const PAYID = 'eMart';
const ORDERS = 'vendor_orders';
const VENDOR_ATTRIBUTES = "vendor_attributes";
const BRANDS = "brands";
const REVIEW_ATTRIBUTES = "review_attributes";
const SOS = 'SOS';
const complaints = 'complaints';
const COUPONS = "coupons";
const CAB_COUPONS = "promos";
const PARCELCOUPONS = "parcel_coupons";
const RENTALCOUPONS = "rental_coupons";
const ORDERS_TABLE = 'booked_table';
const POPULAR_DESTINATION = 'popular_destinations';
const dynamicNotification = 'dynamic_notification';
const STORY = 'story';
const REFERRAL = 'referral';
const emailTemplates = 'email_templates';

const PROVIDER_CATEGORIES = 'provider_categories';
const PROVIDERS_SERVICES = 'providers_services';
const PROVIDER_COUPONS = 'providers_coupons';
const PROVIDER_WORKERS = 'providers_workers';

const providerAccepted = "provider_accepted";
const providerRejected = "provider_rejected";
const providerServiceInTransit = "service_intransit";
const providerServiceCompleted = "service_completed";
const providerServiceExtraCharges = "service_charges";
const providerBookingPlaced = "booking_placed";
const providerBookingCancel = "service_cancelled";
const workerRejected = "worker_rejected";

String senderId = '';
String jsonNotificationFileURL = '';
String GOOGLE_API_KEY = '';

const ORDER_STATUS_PLACED = 'Order Placed';
const ORDER_STATUS_ACCEPTED = 'Order Accepted';
const ORDER_STATUS_DRIVER_PENDING = 'Driver Pending';
const ORDER_STATUS_DRIVER_ACCEPTED = 'Driver Accepted';
const ORDER_STATUS_DRIVER_REJECTED = 'Driver Rejected';
const ORDER_STATUS_SHIPPED = 'Order Shipped';
const ORDER_STATUS_IN_TRANSIT = 'In Transit';
const ORDER_REACHED_DESTINATION = 'Reached Destination';

const dineInPlaced = "dinein_placed";
const orderPlaced = "order_placed";
const scheduleOrder = "schedule_order";
const rentalBooked = "rental_booked";

const walletTopup = "wallet_topup";
const newVendorSignup = "new_vendor_signup";
const payoutRequestStatus = "payout_request_status";
const payoutRequest = "payout_request";
const newOrderPlaced = "new_order_placed";
const newRideBook = "new_ride_book";
const newParcelBook = "new_parcel_book";
const newCarBook = "new_car_book";
const newOnDemandBook = "new_ondemand_book";

const MENU_ITEM = 'banner_items';

const USER_ROLE_DRIVER = 'driver';
const USER_ROLE_CUSTOMER = 'customer';
const USER_ROLE_VENDOR = 'vendor';
const USER_ROLE_PROVIDER = 'provider';
const tax = 'tax';
const Order_Rating = 'items_review';
const CONTACT_US = 'ContactUs';
const COUPON = 'coupons';
const Wallet = "wallet";
const RIDESORDER = "rides";
const PARCELORDER = "parcel_orders";
const RENTALORDER = "rental_orders";
const PROVIDERORDER = "provider_orders";

const PARCELCATEGORY = "parcel_categories";
const PARCELWEIGHT = "parcel_weight";

const Setting = 'settings';
const StripeSetting = 'stripeSettings';
const FavouriteStore = "favorite_vendor";
const FavouriteItem = "favorite_item";
const FavouriteOndemandItem = "favorite_service";
const COD = 'CODSettings';
const TermsAndConditions = 'terms_and_condition';
const GIFT_CARDS = 'gift_cards';
const GIFT_PURCHASES = 'gift_purchases';
const GlobalURL = "https://admin.quickdash.co.in/";
const Currency = 'currencies';
const STORAGE_ROOT = 'emart';

CurrencyModel? currencyData;
SectionModel? sectionConstantModel;
List<VendorModel> allstoreList = [];

String placeholderImage = '';
List<TaxModel>? taxList = [];
String? country = "";
String? selectedMapType = "";

List sectionColor = [
  [Color(0xFFFEF8E7), Color(0xFFF7CD59)],
  [Color(0xFFEEEBF9), Color(0xFF8F7CD8)],
  [Color(0xFFFFF8E5), Color(0xFFF7CD59)],
  [Color(0xFFF5E5FF), Color(0xFFCC80FF)],
  [Color(0xFFFAEBEB), Color(0xFFDB7474)],
  [Color(0xFFE5F9FF), Color(0xFF72DEFF)],
  [Color(0xFFEFF5F1), Color(0xFFADCEB7)],
  [Color(0xFFEAFBF1), Color(0xFF85E5AE)],
  [Color(0xFFE7F8FE), Color(0xFF529DB6)],
  [Color(0xFFEEEBF9), Color(0xFF8F7CD8)],
];

List eCommerceProductColor = [
  [Color(0xFFEEEBF9), Color(0xFFE5F9FF)],
  [Color(0xFFFAEBEB), Color(0xFFFFE5E6)],
  [Color(0xFFFEF8E7), Color(0xFFEAFBF1)],
  [Color(0xFFEFF5F1), Color(0xFFE7F8FE)],
];

String durationToString(int minutes) {
  var d = Duration(minutes: minutes);
  List<String> parts = d.toString().split(':');
  return '${parts[0].padLeft(2, '0')}.${parts[1].padLeft(2, '0')}';
}

String getReferralCode() {
  var rng = Random();
  return (rng.nextInt(900000) + 100000).toString();
}

double getDoubleVal(dynamic input) {
  if (input == null) {
    return 0.1;
  }

  if (input is int) {
    return double.parse(input.toString());
  }

  if (input is double) {
    return input;
  }
  return 0.1;
}

String productCommissionPrice(String price) {
  // String commission = "0";
  // if (sectionConstantModel!.adminCommision != null &&
  //     sectionConstantModel!.adminCommision!.enable == true) {
  //   if (sectionConstantModel!.adminCommision!.type!.toLowerCase() ==
  //           "Percent".toLowerCase() ||
  //       sectionConstantModel!.adminCommision!.type?.toLowerCase() ==
  //           "Percentage".toLowerCase()) {
  //     commission = (double.parse(price) +
  //             (double.parse(price) *
  //                 double.parse(sectionConstantModel!.adminCommision!.commission
  //                     .toString()) /
  //                 100))
  //         .toString();
  //   } else {
  //     commission = (double.parse(price) +
  //             double.parse(
  //                 sectionConstantModel!.adminCommision!.commission.toString()))
  //         .toString();
  //   }
  // } else {
  //   commission = price;
  // }
  return price;
}

String calculateReview(
    {required String? reviewCount, required String? reviewSum}) {
  if (0 == double.parse(reviewSum.toString()) &&
      0 == double.parse(reviewSum.toString())) {
    return "0";
  }
  return (double.parse(reviewSum.toString()) /
          double.parse(reviewCount.toString()))
      .toStringAsFixed(1);
}

Widget loader() {
  return Center(
    child: CircularProgressIndicator(color: AppThemeData.primary500),
  );
}

String maskingString(String documentId, int maskingDigit) {
  String maskedDigits = documentId;
  for (int i = 0; i < documentId.length - maskingDigit; i++) {
    maskedDigits = maskedDigits.replaceFirst(documentId[i], "*");
  }
  return maskedDigits;
}

String getFileName(String url) {
  RegExp regExp = RegExp(r'.+(\/|%2F)(.+)\?.+');
  //This Regex won't work if you remove ?alt...token
  var matches = regExp.allMatches(url);

  var match = matches.elementAt(0);
  print(Uri.decodeFull(match.group(2)!));
  return Uri.decodeFull(match.group(2)!);
}

double getTaxValue({String? amount, TaxModel? taxModel}) {
  double taxVal = 0.0;
  if (taxModel != null && taxModel.enable == true) {
    if (taxModel.type == "fix") {
      taxVal = double.parse(taxModel.tax.toString());
    } else {
      taxVal = (double.parse(amount.toString()) *
              double.parse(taxModel.tax!.toString())) /
          100;
    }
  }
  return taxVal;
}

Uri createCoordinatesUrl(double latitude, double longitude, [String? label]) {
  var uri;
  if (kIsWeb) {
    uri = Uri.https('www.google.com', '/maps/search/',
        {'api': '1', 'query': '$latitude,$longitude'});
  } else if (Platform.isAndroid) {
    var query = '$latitude,$longitude';
    if (label != null) query += '($label)';
    uri = Uri(scheme: 'geo', host: '0,0', queryParameters: {'q': query});
  } else if (Platform.isIOS) {
    var params = {'ll': '$latitude,$longitude'};
    if (label != null) params['q'] = label;
    uri = Uri.https('maps.apple.com', '/', params);
  } else {
    uri = Uri.https('www.google.com', '/maps/search/',
        {'api': '1', 'query': '$latitude,$longitude'});
  }

  return uri;
}

String amountShow({required String? amount}) {
  int decimalPlaces = 2; // Default to 2 decimal places
  if (currencyData != null) {
    decimalPlaces = currencyData!.decimal > 0 ? currencyData!.decimal : 2; // Ensure at least 2 decimal places
  }

  String formattedAmount = double.parse(amount.toString()).toStringAsFixed(decimalPlaces);

  if (currencyData == null) {
    return "₹ $formattedAmount";
  } else {
    if (currencyData!.symbolatright == true) {
      return "$formattedAmount ${currencyData!.symbol.toString()}";
    } else {
      return "${currencyData!.symbol.toString()} $formattedAmount";
    }
  }
}

String timestampToDateTime(Timestamp timestamp) {
  DateTime dateTime = timestamp.toDate();
  return DateFormat('MMM dd,yyyy hh:mm aa').format(dateTime);
}

String getKm(UserLocation pos1, UserLocation pos2) {
  double distanceInMeters = Geolocator.distanceBetween(
      pos1.latitude, pos1.longitude, pos2.latitude, pos2.longitude);
  double kilometer = distanceInMeters / 1000;
  debugPrint("KiloMeter$kilometer");
  return kilometer.toStringAsFixed(2).toString();
}

String getImageVAlidUrl(String? url) {
  String imageUrl = placeholderImage;
  if (url != null && url.isNotEmpty) {
    imageUrl = url;
  }
  return imageUrl;
}

MailSettings? mailSettings;

sendMail(
    {String? subject,
    String? body,
    bool? isAdmin = false,
    List<dynamic>? recipients}) async {}

Future<void> makePhoneCall(String phoneNumber) async {
  final Uri launchUri = Uri(
    scheme: 'tel',
    path: phoneNumber,
  );
  await launchUrl(launchUri);
}

void checkPermission(Function() onTap, BuildContext context) async {
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied) {
    SnackBar snack = SnackBar(
      content: const Text(
        'You have to allow location permission to use your location',
        style: TextStyle(color: Colors.white),
      ).tr(),
      duration: const Duration(seconds: 2),
      backgroundColor: Colors.black,
    );
    ScaffoldMessenger.of(context).showSnackBar(snack);
  } else if (permission == LocationPermission.deniedForever) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return PermissionDialog();
      },
    );
  } else {
    onTap();
  }
}

extension StringExtension on String {
  String capitalizeString() {
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}
