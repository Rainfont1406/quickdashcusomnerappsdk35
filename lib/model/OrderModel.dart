import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emartconsumer/model/AddressModel.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/localDatabase.dart';

import 'TaxModel.dart';

class OrderModel {
  String authorID, payment_method;

  User author;

  User? driver;

  String? driverID;

  List<CartProduct> products;

  Timestamp createdAt;
  bool payment_shared = false;
  String vendorID;
  String? sectionId;

  VendorModel vendor;

  String status;

  AddressModel? address;

  String id;
  num? discount;
  String? couponCode;
  String? couponId, notes;

  // var extras = [];
  //String? extra_size;
  String? tipValue;
  String? adminCommission;
  String? adminCommissionType;
  final bool? takeAway;

  String? deliveryCharge;
  List<TaxModel>? taxModel;
  Map<String, dynamic>? specialDiscount;

  String courierCompanyName;
  String courierTrackingId;

  String? estimatedTimeToPrepare;
  Timestamp? acceptedAt;

  // Set whenever `status` transitions to ORDER_STATUS_COMPLETED or
  // ORDER_STATUS_REJECTED — lets the vendor/customer chat stay open for a
  // limited window after the order reaches a terminal state instead of
  // locking the instant it does (see isWithinTerminalChatWindow in
  // helper.dart). Written by the Vendor App/Web, read here.
  Timestamp? statusUpdatedAt;
  Timestamp? scheduleTime;
  String? orderType; // "Takeaway" or "Dining" for Dineaway feature
  // Phase 1 real-time seat availability - only set for orderType=='Dining'
  // at a vendor with VendorModel.seatCapacity configured. Lets
  // streamCurrentSeatAvailability sum actual party sizes instead of just
  // counting active orders. See TABLE_BOOKING_CAPACITY_AND_DEPOSIT_PLAN.html.
  int? diningGuestCount;
  // Explicit vendor signal that the table has actually been vacated -
  // deliberately separate from status==Completed, which only means the
  // order/kitchen side is done (food served, payment settled). A customer
  // can still be sitting at the table well after that. Set via the "Mark
  // Seat Free" button (vendor-side order actions), shown only once the
  // order is Completed and only for vendors with seatCapacity configured.
  bool seatFreed;
  String? staffStatus;

  // ── Vendor-initiated Bill Pay request fields ─────────────────────────────
  // These three describe the ORIGINAL pending request document only (read
  // via BillPayRequestScreen/OrdersScreen) — never set on a normal order.
  String? initiatedBy; // 'vendor' when the vendor built the cart and sent it to the customer for approval
  Timestamp? billPayExpiresAt; // 60-minute approval deadline, refreshed on vendor edit
  Timestamp? billPayRespondedAt; // when the customer accepted or declined

  // Set on the brand-new order created by Accept & Pay (see CartScreen's
  // Bill Pay mode / PaymentScreen) — links it back to the original pending
  // request so a Cloud Function can reconcile that document afterward. Never
  // set together with initiatedBy/billPayExpiresAt on the same document.
  String? billPayRequestId;

  // Set only for orders paid through the new server-verified Razorpay flow
  // (createVerifiedOrderPayment/verifyRazorpayPayment) — lets
  // verifyOrderOnCreate cross-check that a matching, consumed
  // payment_intents doc actually exists before trusting this order's price.
  String? razorpayOrderId;

  // Immutable purchase-analytics snapshot (2026-07-22) - written ONCE, by
  // the customer, at order creation (PaymentScreen/CheckoutScreen), and
  // NEVER touched again by anything - the order document stays fully
  // immutable from the customer's side after creation. Exists so
  // PurchaseCompletionListener can learn category/cuisine/budget/order-mode
  // preference from a COMPLETED order with zero additional Firestore reads
  // - no re-querying products, no re-querying the vendor, no recomputing
  // checkout totals - just what was actually purchased, exactly as it was
  // at the moment of purchase, regardless of later menu/category changes.
  // Exactly-once idempotency is provided elsewhere (a deterministic-ID
  // marker doc PurchaseCompletionListener creates under the customer's own
  // behavior_batches collection) - see that class' own doc comment.
  Map<String, dynamic>? analyticsSnapshot;

  // Immutable pricing snapshot (2026-08-04) - written ONCE, a few seconds
  // after order creation, by the verifyOrderOnCreate Cloud Function, after
  // it has re-verified subtotal/discount/specialDiscount/tax/deliveryCharge
  // against server-side data (the special discount is a time-window check
  // that trigger can silently correct post-creation). This is the single
  // source of truth for "what did this order actually cost" - every screen
  // displaying an ALREADY-PLACED order's total should read from here instead
  // of recomputing from raw order fields. Absent on orders created before
  // this backend change deployed, and briefly absent (a few seconds) right
  // after a brand-new order is created before the trigger has run - screens
  // MUST fall back to their existing recompute logic when this is null.
  Map<String, dynamic>? pricing;

  OrderModel({
    this.address,
    author,
    this.driver,
    this.driverID,
    this.authorID = '',
    this.payment_method = '',
    createdAt,
    this.id = '',
    this.products = const [],
    this.status = '',
    this.discount = 0,
    this.payment_shared = false,
    this.couponCode = '',
    this.couponId = '',
    this.notes = '',
    vendor,
    /*this.extras = const [], this.extra_size,*/ this.tipValue,
    this.adminCommission,
    this.takeAway = false,
    this.adminCommissionType,
    this.deliveryCharge,
    this.vendorID = '',
    this.sectionId = '',
    this.courierCompanyName = '',
    this.courierTrackingId = '',
    this.specialDiscount,
    this.estimatedTimeToPrepare,
    this.acceptedAt,
    this.statusUpdatedAt,
    this.taxModel,
    this.scheduleTime,
    this.orderType,
    this.diningGuestCount,
    this.seatFreed = false,
    this.staffStatus,
    this.initiatedBy,
    this.billPayExpiresAt,
    this.billPayRespondedAt,
    this.billPayRequestId,
    this.razorpayOrderId,
    this.analyticsSnapshot,
    this.pricing,
  })  : author = author ?? User(),
        createdAt = createdAt ?? Timestamp.now(),
        vendor = vendor ?? VendorModel();

  factory OrderModel.fromJson(Map<String, dynamic> parsedJson) {
    List<CartProduct> products = parsedJson.containsKey('products')
        ? List<CartProduct>.from((parsedJson['products'] as List<dynamic>).map((e) => CartProduct.fromJson(e))).toList()
        : [].cast<CartProduct>();

    num discountVal = 0;
    if (parsedJson['discount'] == null) {
      discountVal = 0;
    } else if (parsedJson['discount'] is String) {
      discountVal = double.parse(parsedJson['discount']);
    } else {
      discountVal = parsedJson['discount'];
    }
    List<TaxModel>? taxList;
    if (parsedJson['taxSetting'] != null) {
      taxList = <TaxModel>[];
      parsedJson['taxSetting'].forEach((v) {
        taxList!.add(TaxModel.fromJson(v));
      });
    }

    return OrderModel(
      address: (parsedJson.containsKey('address') && parsedJson['address'] != null)
          ? AddressModel.fromJson(parsedJson['address'])
          : AddressModel(),
      author: parsedJson.containsKey('author') ? User.fromJson(parsedJson['author']) : User(),
      authorID: parsedJson['authorID'] ?? '',
      createdAt: _parseTimestamp(parsedJson['createdAt']) ?? Timestamp.now(),
      id: parsedJson['id'] ?? '',
      products: products,
      status: parsedJson['status'] ?? '',
      discount: discountVal,
      couponCode: parsedJson['couponCode'] ?? '',
      couponId: parsedJson['couponId'] ?? '',
      notes: (parsedJson["notes"] != null && parsedJson["notes"].toString().isNotEmpty) ? parsedJson["notes"] : "",
      vendor: parsedJson.containsKey('vendor') ? VendorModel.fromJson(parsedJson['vendor']) : VendorModel(),
      vendorID: parsedJson['vendorID'] ?? '',
      sectionId: parsedJson['section_id'] ?? '',
      driver: parsedJson.containsKey('driver') ? User.fromJson(parsedJson['driver']) : null,
      driverID: parsedJson.containsKey('driverID') ? parsedJson['driverID'] : null,
      adminCommission: parsedJson["adminCommission"] ?? "",
      adminCommissionType: parsedJson["adminCommissionType"] ?? "",
      tipValue: parsedJson["tip_amount"] ?? "",
      takeAway: parsedJson["takeAway"] ?? false,
      payment_method: parsedJson['payment_method'] ?? '',
      payment_shared: parsedJson['payment_shared'] ?? true,
      // taxModel: (parsedJson.containsKey('taxSetting') && parsedJson['taxSetting'] != null) ? TaxModel.fromJson(parsedJson['taxSetting']) : null,
      //extras: parsedJson["extras"]!=null?parsedJson["extras"]:[],
      // extra_size: parsedJson["extras_price"]!=null?parsedJson["extras_price"]:"",
      deliveryCharge: parsedJson["deliveryCharge"],
      courierCompanyName: parsedJson["courierCompanyName"] ?? '',
      courierTrackingId: parsedJson["courierTrackingId"] ?? '',
      specialDiscount: parsedJson["specialDiscount"] ?? {},
      estimatedTimeToPrepare: parsedJson["estimatedTimeToPrepare"] ?? '',
      acceptedAt: _parseTimestamp(parsedJson["acceptedAt"]),
      statusUpdatedAt: _parseTimestamp(parsedJson["statusUpdatedAt"]),
      taxModel: taxList,
      scheduleTime: _parseTimestamp(parsedJson["scheduleTime"]),
      orderType: parsedJson["orderType"],
      diningGuestCount: (parsedJson["diningGuestCount"] is num) ? (parsedJson["diningGuestCount"] as num).toInt() : null,
      seatFreed: parsedJson["seatFreed"] ?? false,
      staffStatus: parsedJson["staffStatus"],
      initiatedBy: parsedJson["initiatedBy"],
      billPayExpiresAt: _parseTimestamp(parsedJson["billPayExpiresAt"]),
      billPayRespondedAt: _parseTimestamp(parsedJson["billPayRespondedAt"]),
      billPayRequestId: parsedJson["billPayRequestId"],
      razorpayOrderId: parsedJson["razorpayOrderId"],
      analyticsSnapshot: parsedJson["analyticsSnapshot"] == null
          ? null
          : Map<String, dynamic>.from(parsedJson["analyticsSnapshot"]),
      pricing: parsedJson["pricing"] == null ? null : Map<String, dynamic>.from(parsedJson["pricing"]),
    );
  }

  // Some documents have one of these Timestamp fields stored as a plain
  // RFC3339 string instead of a real Firestore Timestamp (predates the
  // fsNowTimestamp() fix documented elsewhere) - assigning that String
  // straight into a Timestamp/Timestamp? field throws at parse time and
  // silently drops the whole order from whatever stream is listening.
  static Timestamp? _parseTimestamp(dynamic raw) {
    if (raw is Timestamp) return raw;
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return Timestamp.fromDate(parsed);
    }
    return null;
  }

  // Trimmed snapshot of the embedded vendor written into every order - full
  // VendorModel.toJson() writes ~65 fields (~11KB, ~65% of a typical order
  // document). A cross-app field-usage trace (Sept 2026) found only these
  // are ever read, across the Customer App, Vendor App, Vendor Web, the
  // Admin Panel's Blade views, and its 4 order-triggered Cloud Functions
  // (verifyOrder/reconcileBillPay/dineOccupancy/vendorEarnings - confirmed
  // clean, they key off vendorID, never this embedded copy). VendorModel/
  // User.fromJson() default every field not present, so omitted fields
  // just read back as empty/false/0 everywhere this doc is read - not a
  // partial-parse risk. `id` deliberately omitted - order.vendorID is the
  // canonical field; the 2 read sites that used to read vendor.id now read
  // vendorID directly instead. specialDiscountEnable is kept because it
  // gates whether a discount that applied at order time still shows on old
  // receipts - it must reflect state at order time, not the vendor's
  // current setting, so it can't just be looked up live.
  static Map<String, dynamic> _vendorSnapshot(VendorModel v) => {
    'title': v.title,
    'photo': v.photo,
    'phonenumber': v.phonenumber,
    'author': v.author,
    'location': v.location,
    'locality': v.locality,
    'landmark': v.landmark,
    'latitude': v.latitude,
    'longitude': v.longitude,
    'specialDiscountEnable': v.specialDiscountEnable,
    'enableBillPaymentTimer': v.enableBillPaymentTimer,
    'section_id': v.section_id,
    'fcmToken': v.fcmToken,
  };

  // Same reasoning as _vendorSnapshot above, for the embedded customer
  // (~40 User fields down to these 7, ~3KB down to a few hundred bytes).
  // `id` (not `userID`) matches User.toJson()'s own key convention, so a
  // round trip through User.fromJson() is unaffected. `location` is kept
  // because it freezes the delivery address as it was at order time.
  static Map<String, dynamic> _authorSnapshot(User a) => {
    'id': a.userID,
    'firstName': a.firstName,
    'lastName': a.lastName,
    'phoneNumber': a.phoneNumber,
    'email': a.email,
    'fcmToken': a.fcmToken,
    'location': a.location.toJson(),
  };

  // Every product in an order shares the order's own vendorID (single-vendor
  // cart, enforced at add-to-cart time in CartDatabase.addProduct) - blanked
  // here instead of repeating the same ~20-char id on every line item. Kept
  // as an empty string, not omitted, so CartProduct.fromJson's non-nullable
  // vendorID field doesn't throw on read. Anything needing a line item's
  // vendor must read the order's own vendorID instead - see
  // OrderDetailsScreen's reorder buttons, updated accordingly.
  static Map<String, dynamic> _productSnapshot(CartProduct e) {
    final json = e.toJson();
    json['vendorID'] = '';
    return json;
  }

  Map<String, dynamic> toJson() {
    return {
      // 2026-09-26: omitted (not null) when there's no address (Dining /
      // Takeaway). Vendor Web/App builds before today parsed a null
      // address as a crash and silently dropped the whole order - a
      // missing key they already handle. Same data either way.
      if (address != null) 'address': this.address!.toJson(),
      'author': _authorSnapshot(author),
      'authorID': authorID,
      'payment_method': payment_method,
      'createdAt': createdAt,
      'id': id,
      'products': products.map((e) => _productSnapshot(e)).toList(),
      'status': status,
      'discount': discount,
      'couponCode': couponCode,
      'couponId': couponId,
      'notes': notes,
      'payment_shared': payment_shared,
      'vendor': _vendorSnapshot(vendor),
      'vendorID': vendorID,
      'section_id': sectionId,
      'adminCommission': adminCommission,
      'adminCommissionType': adminCommissionType,
      "tip_amount": tipValue,
      "taxSetting": taxModel != null ? taxModel!.map((v) => v.toJson()).toList() : null,
      // "extras":this.extras,
      //"extras_price":this.extra_size,
      "takeAway": takeAway,
      "deliveryCharge": deliveryCharge,
      "specialDiscount": specialDiscount,
      "courierCompanyName": courierCompanyName,
      "courierTrackingId": courierTrackingId,
      "estimatedTimeToPrepare": this.estimatedTimeToPrepare,
      "acceptedAt": this.acceptedAt,
      "statusUpdatedAt": this.statusUpdatedAt,
      "scheduleTime": this.scheduleTime,
      "orderType": this.orderType,
      "diningGuestCount": this.diningGuestCount,
      "seatFreed": this.seatFreed,
      "initiatedBy": this.initiatedBy,
      "billPayExpiresAt": this.billPayExpiresAt,
      "billPayRespondedAt": this.billPayRespondedAt,
      "billPayRequestId": this.billPayRequestId,
      "razorpayOrderId": this.razorpayOrderId,
      "analyticsSnapshot": this.analyticsSnapshot,
      "pricing": this.pricing,
    };
  }
}
