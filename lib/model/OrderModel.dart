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
    this.staffStatus,
    this.initiatedBy,
    this.billPayExpiresAt,
    this.billPayRespondedAt,
    this.billPayRequestId,
    this.razorpayOrderId,
    this.analyticsSnapshot,
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
      createdAt: parsedJson['createdAt'] ?? Timestamp.now(),
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
      acceptedAt: parsedJson["acceptedAt"],
      statusUpdatedAt: parsedJson["statusUpdatedAt"],
      taxModel: taxList,
      scheduleTime: parsedJson["scheduleTime"],
      orderType: parsedJson["orderType"],
      staffStatus: parsedJson["staffStatus"],
      initiatedBy: parsedJson["initiatedBy"],
      billPayExpiresAt: parsedJson["billPayExpiresAt"],
      billPayRespondedAt: parsedJson["billPayRespondedAt"],
      billPayRequestId: parsedJson["billPayRequestId"],
      razorpayOrderId: parsedJson["razorpayOrderId"],
      analyticsSnapshot: parsedJson["analyticsSnapshot"] == null
          ? null
          : Map<String, dynamic>.from(parsedJson["analyticsSnapshot"]),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'address': address == null ? null : this.address!.toJson(),
      'author': author.toJson(),
      'authorID': authorID,
      'payment_method': payment_method,
      'createdAt': createdAt,
      'id': id,
      'products': products.map((e) => e.toJson()).toList(),
      'status': status,
      'discount': discount,
      'couponCode': couponCode,
      'couponId': couponId,
      'notes': notes,
      'payment_shared': payment_shared,
      'vendor': vendor.toJson(),
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
      "initiatedBy": this.initiatedBy,
      "billPayExpiresAt": this.billPayExpiresAt,
      "billPayRespondedAt": this.billPayRespondedAt,
      "billPayRequestId": this.billPayRequestId,
      "razorpayOrderId": this.razorpayOrderId,
      "analyticsSnapshot": this.analyticsSnapshot,
    };
  }
}
