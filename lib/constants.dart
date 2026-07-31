import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart'; // also re-exports intl (NumberFormat, DateFormat)
import 'package:emartconsumer/model/CurrencyModel.dart';
import 'package:emartconsumer/model/SectionModel.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/model/VendorCategoryModel.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/model/mail_setting.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/widget/permission_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'model/TaxModel.dart';

const FINISHED_ON_BOARDING = 'finishedOnBoarding';
const PHONE_AUTH_USER_ID = 'phoneAuthUserId';
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
// A coupon and a vendor's special discount can stack, but combined they can
// never discount more than this percentage of the order amount. Populated
// from settings/globalSettings at startup (see main.dart); this default is
// the fallback when that field hasn't been set by an admin yet.
double maxCombinedDiscountPercent = 70;
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
// Admin-managed Business Context master data (2026-07-19) - Restaurant
// Type/Cuisine -> preferred Product Category IDs, consumed by
// RecommendationEngine. See FirebaseHelper.getBusinessContext.
const BUSINESS_CONTEXT_TYPE_PROFILES = 'business_context_type_profiles';
const BUSINESS_CONTEXT_CUISINE_AFFINITY = 'business_context_cuisine_affinity';
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

// Vendor-initiated Bill Pay request — pre-payment gate statuses (order.status).
// Must match the identical constants in the vendor app / vendor web.
const BILLPAY_STATUS_PENDING_APPROVAL = 'Pending Approval';
const BILLPAY_STATUS_DECLINED = 'Declined by Customer';
const BILLPAY_STATUS_EXPIRED = 'Expired';
const BILLPAY_STATUS_CANCELLED = 'Cancelled by Vendor';

const dineInPlaced = "dinein_placed";
const orderPlaced = "order_placed";
const scheduleOrder = "schedule_order";
const rentalBooked = "rental_booked";
// dynamicNotification content-template types for vendor-initiated Bill Pay —
// falls back to a generic placeholder message if no admin template exists yet.
const billPayRequestDeclined = "bill_pay_request_declined";
const billPayRequestAccepted = "bill_pay_request_accepted";

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
const Wallet = "wallet";
const RIDESORDER = "rides";
const PARCELORDER = "parcel_orders";
const RENTALORDER = "rental_orders";
const PROVIDERORDER = "provider_orders";

const PARCELCATEGORY = "parcel_categories";
const PARCELWEIGHT = "parcel_weight";

const Setting = 'settings';
// Safe-fields-only mirror of gateway settings (public key + enabled flags,
// never a secret) - kept in sync by the mirrorRazorpayPublicSettings Cloud
// Function. settings/razorpaySettings itself is admin-only now that its
// secret is no longer publicly readable.
const SettingPublic = 'settings_public';
const StripeSetting = 'stripeSettings';
const FavouriteStore = "favorite_vendor";
const FavouriteItem = "favorite_item";
const FavouriteOndemandItem = "favorite_service";
const COD = 'CODSettings';
const TermsAndConditions = 'terms_and_condition';
const GIFT_CARDS = 'gift_cards';
const GIFT_PURCHASES = 'gift_purchases';
const GlobalURL = "https://admin.quickdash.co.in/";
const CloudFunctionsBaseURL = "https://us-central1-quick-dash-84f6a.cloudfunctions.net";
const Currency = 'currencies';
const STORAGE_ROOT = 'emart';

CurrencyModel? currencyData;
SectionModel? sectionConstantModel;
List<VendorModel> allstoreList = [];
// Product-level category master list (vendor_categories, scoped to the
// current section) — populated once by HomeScreen.getBanner()'s existing
// getCuisines() call (same collection AddOrUpdateProductScreen's per-item
// category picker reads). Shared globally, same lifecycle/pattern as
// allstoreList above, so SearchScreen's "Product Category" search tier can
// reuse it instead of firing its own independent query.
List<VendorCategoryModel> allProductCategoriesList = [];
// O(1) lookup companion to allProductCategoriesList above (2026-07-21,
// Category-Based Pairing Configuration) - rebuilt every time that list is,
// right alongside it, so nothing ever has to linear-scan the category list
// per product tap. See newVendorProductsScreen.dart's _resolvedPairsWellWith.
Map<String, VendorCategoryModel> productCategoryById = {};

// Live, app-wide Delivery-mode gate. Updated by a single Firestore listener
// started in ContainerScreen (not per-screen), so every screen that gates
// itself on isDeliveryActiveNotifier reacts instantly to an admin toggle,
// not just whichever screen happens to be mounted.
final ValueNotifier<bool> isDeliveryActiveNotifier = ValueNotifier<bool>(true);
final ValueNotifier<String> deliveryOffMessageNotifier = ValueNotifier<String>('');

// Set true by PaymentScreen while a gateway checkout sheet (Razorpay/UPI/
// Card, PayFast's WebView, etc.) is actually open, false once it closes.
// The global offline ConnectivityGate checks this before popping itself
// over the app — a gateway's own native UI has its own network handling,
// and a connectivity blip mid-payment must not force our overlay on top of
// it (see ConnectivityGate in lib/services/connectivity_gate.dart).
final ValueNotifier<bool> paymentInProgressNotifier = ValueNotifier<bool>(false);
// Mirrors HomeScreen's selctedOrderTypeValue so other screens (Search, Map,
// etc.) can synchronously check the current mode without re-reading
// SharedPreferences. Set whenever HomeScreen's order-type switch changes.
// Defaults to Dineaway, matching HomeScreen's default — Delivery is
// currently gated behind isDeliveryActiveNotifier and shows "Coming Soon".
String currentOrderTypeGlobal = 'Dineaway';

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

/// Formats a monetary amount with the active currency symbol, thousands
/// separator, and decimal places from [currencyData].
///
/// Pass [decimals] to override the currency's decimal setting (e.g. 0 for
/// whole-number booking charges).  Output examples (INR, decimal=2):
///   amountShow(amount: '199')         → ₹199.00
///   amountShow(amount: '1299.5')      → ₹1,299.50
///   amountShow(amount: '100', decimals: 0) → ₹100
String amountShow({required String? amount, int? decimals}) {
  final double value = double.tryParse(amount?.toString() ?? '') ?? 0.0;
  final int places = decimals ??
      ((currencyData != null && currencyData!.decimal > 0)
          ? currencyData!.decimal
          : 2);

  // '#,##0.00' adds thousands separator and fixed decimal places.
  final String pattern =
      places > 0 ? '#,##0.${'0' * places}' : '#,##0';
  final String formatted = NumberFormat(pattern, 'en_US').format(value);

  final String sym = currencyData?.symbol ?? '₹';
  return '$sym$formatted';
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

// Per-session cache: vendor pair → road distance string (km).
// Keyed by rounded coords so minor GPS jitter doesn't create duplicate entries.
final Map<String, String> _roadDistanceCache = {};

// In-flight request dedup: without this, every RoadDistanceText widget that
// happens to render the same vendor+user-location pair before the first
// call resolves (e.g. the same vendor shown in both a horizontal carousel
// and a vertical list) fires its own independent OSRM request, since the
// completed-result cache above isn't populated until a request finishes.
// That multiplies traffic against the public OSRM demo server, which is
// rate-limited — the extra concurrent requests are a direct cause of
// otherwise-avoidable fallbacks to Haversine.
final Map<String, Future<String>> _roadDistanceInFlight = {};

/// Call this whenever the user changes their delivery address so stale
/// distance values are not served from the cache.
void clearRoadDistanceCache() => _roadDistanceCache.clear();

// Returns actual road/driving distance via OSRM (OSM routing).
// Falls back to straight-line Haversine if the API is unreachable.
Future<String> getRoadDistanceKm(UserLocation pos1, UserLocation pos2) async {
  final key =
      '${pos1.latitude.toStringAsFixed(4)},${pos1.longitude.toStringAsFixed(4)}'
      '-${pos2.latitude.toStringAsFixed(4)},${pos2.longitude.toStringAsFixed(4)}';
  if (_roadDistanceCache.containsKey(key)) return _roadDistanceCache[key]!;
  final existing = _roadDistanceInFlight[key];
  if (existing != null) return existing;

  final future = _fetchRoadDistanceKm(pos1, pos2, key);
  _roadDistanceInFlight[key] = future;
  try {
    return await future;
  } finally {
    _roadDistanceInFlight.remove(key);
  }
}

Future<String> _fetchRoadDistanceKm(
    UserLocation pos1, UserLocation pos2, String key) async {
  final startedAt = DateTime.now();
  final haversineKm = double.tryParse(getKm(pos1, pos2)) ?? 0;

  int? httpStatus;
  String? routeCode;
  double? osrmKm;
  bool fallbackUsed = false;
  String? errorDetail;
  String result;

  try {
    // OSRM expects lon,lat order (opposite of lat,lon convention)
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving'
      '/${pos1.longitude},${pos1.latitude}'
      ';${pos2.longitude},${pos2.latitude}'
      '?overview=false',
    );
    final response =
        await http.get(url).timeout(const Duration(seconds: 10));
    httpStatus = response.statusCode;
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      routeCode = data['code'] as String?;
      final routes = data['routes'] as List?;
      if (routeCode == 'Ok' && routes != null && routes.isNotEmpty) {
        final meters = (routes[0]['distance'] as num).toDouble();
        osrmKm = meters / 1000;
        result = osrmKm.toStringAsFixed(2);
      } else {
        fallbackUsed = true;
        result = haversineKm.toStringAsFixed(2);
      }
    } else {
      fallbackUsed = true;
      result = haversineKm.toStringAsFixed(2);
    }
  } on TimeoutException catch (e) {
    fallbackUsed = true;
    errorDetail = 'TIMEOUT: $e';
    result = haversineKm.toStringAsFixed(2);
  } catch (e) {
    fallbackUsed = true;
    errorDetail = e.toString();
    result = haversineKm.toStringAsFixed(2);
  }

  final finishedAt = DateTime.now();
  debugPrint(
    '[RoadDistance] key=$key '
    'requestStarted=${startedAt.toIso8601String()} '
    'requestFinished=${finishedAt.toIso8601String()} '
    'elapsedMs=${finishedAt.difference(startedAt).inMilliseconds} '
    'httpStatus=${httpStatus ?? "N/A"} '
    'routeCode=${routeCode ?? "N/A"} '
    'osrmDistanceKm=${osrmKm?.toStringAsFixed(3) ?? "N/A"} '
    'haversineDistanceKm=${haversineKm.toStringAsFixed(3)} '
    'fallbackUsed=$fallbackUsed '
    'finalDistanceDisplayedKm=$result '
    'error=${errorDetail ?? "none"}',
  );

  _roadDistanceCache[key] = result;
  return result;
}

String getImageVAlidUrl(String? url) {
  String imageUrl = placeholderImage;
  if (url != null && url.isNotEmpty) {
    imageUrl = url;
  }
  return bunnyOptimizedUrl(imageUrl);
}

// Bunny's Optimizer add-on (enabled 2026-07-30 on the production pull zone)
// supports on-the-fly resizing via ?width=&quality= query params on any
// cdn.quickdash.co.in URL — see IMAGE_OPTIMIZATION_AUDIT.md. This is the
// dominant chokepoint (getImageVAlidUrl is called from ~22 files) so a single
// change here covers nearly every image in the app. 800px is a deliberately
// generic, safe-for-most-contexts cap (thumbnails/cards/avatars all display
// well under this) — narrower than an ideal per-widget size in some cases,
// but converts what were previously 1-5MB originals into a consistently
// moderate size everywhere, without touching every call site's widget code.
// Only Bunny URLs understand these params; Firebase Storage URLs (still in
// use for some legacy images) are left untouched.
String bunnyOptimizedUrl(String url, {int width = 800, int quality = 80}) {
  if (!url.contains('cdn.quickdash.co.in')) return url;
  if (url.contains('width=')) return url; // already has explicit params — don't double up
  final separator = url.contains('?') ? '&' : '?';
  return '$url${separator}width=$width&quality=$quality';
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
