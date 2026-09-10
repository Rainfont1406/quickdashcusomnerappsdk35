import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/model/VendorModel.dart';

class BookTableModel {
  String authorID;

  User author;

  Timestamp createdAt, date;

  String vendorID;


  VendorModel vendor;

  String status;
  String id, guestEmail, guestFirstName, guestLastName, guestPhone;
  String? occasion, specialRequest, section_id;
  bool firstVisit;
  int totalGuest;

  // ── New booking fields ──────────────────────────────────────────
  String bookingType;       // 'flexible' | 'slot_based'
  String slotId;            // for slot-based bookings
  String selectedTime;      // selected time (flexible) or slot start time
  String selectedEndTime;   // slot end time
  String bookingDate;       // human-readable date string e.g. "Mon, Jan 15 2024"
  String bookingDateKey;    // 'yyyy-MM-dd' for Firestore equality queries (no composite index needed)
  String pricingModel;      // 'free' | 'per_person' | 'table_charge' | 'cover_charge'
  num bookingCharge;        // per-unit charge
  num totalCharge;          // totalGuest * bookingCharge or flat charge
  String approvalMode;      // 'auto' | 'manual'
  // Whether this booking's dine_in_capacity reservation has been given back
  // (auto-release sweep, "Mark Seat Free", or vendor reject) - added
  // 2026-08-28. This field was missing from this model entirely (though
  // present on the Vendor App's copy), so every booking ever created here
  // wrote a Firestore doc with no capacityReleased field at all - not
  // false, genuinely absent. That silently broke AutoReleaseStaleBooking
  // Capacity.php's own Firestore-level `capacityReleased == false` filter
  // forever (a missing field never matches an equality filter), meaning
  // the 15-min auto-release sweep never found a single real booking to
  // release. Fixed on the PHP side (status-only filter, in-memory check
  // instead) and here, so newly created bookings explicitly carry the
  // field going forward.
  bool capacityReleased;

  BookTableModel(
      {author,
      this.authorID = '',
      createdAt,
      date,
      this.vendorID = '',
      this.section_id = '',
      vendor,
      this.id = '',
      this.status = '',
      this.guestEmail = '',
      this.guestFirstName = '',
      this.guestLastName = '',
      this.guestPhone = '',
      this.occasion,
      this.specialRequest,
      this.firstVisit = false,
      this.totalGuest = 0,
      this.bookingType = 'flexible',
      this.slotId = '',
      this.selectedTime = '',
      this.selectedEndTime = '',
      this.bookingDate = '',
      this.bookingDateKey = '',
      this.pricingModel = 'free',
      this.bookingCharge = 0,
      this.totalCharge = 0,
      this.approvalMode = 'auto',
      this.capacityReleased = false})
      : author = author ?? User(),
        createdAt = createdAt ?? Timestamp.now(),
        date = date ?? Timestamp.now(),
        vendor = vendor ?? VendorModel();

  factory BookTableModel.fromJson(Map<String, dynamic> parsedJson) {
    int guestVal = 0;
    if (parsedJson['totalGuest'] == null || parsedJson['totalGuest'] == double.infinity) {
      guestVal = 0;
    } else {
      if (parsedJson['totalGuest'] is String) {
        guestVal = int.parse(parsedJson['totalGuest']);
      } else {
        guestVal = (parsedJson['totalGuest'] is double) ? (parsedJson["totalGuest"].isNaN ? 0 : (parsedJson['totalGuest'] as double).toInt()) : parsedJson['totalGuest'];
      }
    }
    return BookTableModel(
        author: parsedJson.containsKey('author') ? User.fromJson(parsedJson['author']) : User(),
        authorID: parsedJson['authorID'] ?? '',
        createdAt: parsedJson['createdAt'] ?? Timestamp.now(),
        date: parsedJson['date'] ?? Timestamp.now(),
        id: parsedJson['id'] ?? '',
        section_id: parsedJson['section_id'] ?? '',
        vendor: parsedJson.containsKey('vendor') ? VendorModel.fromJson(parsedJson['vendor']) : VendorModel(),
        vendorID: parsedJson['vendorID'] ?? '',
        status: parsedJson['status'] ?? '',
        guestEmail: parsedJson['guestEmail'] ?? '',
        guestFirstName: parsedJson['guestFirstName'] ?? '',
        guestLastName: parsedJson['guestLastName'] ?? '',
        guestPhone: parsedJson['guestPhone'] ?? '',
        occasion: (parsedJson["occasion"] != null && parsedJson["occasion"].toString().isNotEmpty) ? parsedJson["occasion"] : "",
        specialRequest: (parsedJson["specialRequest"] != null && parsedJson["specialRequest"].toString().isNotEmpty) ? parsedJson["specialRequest"] : "",
        firstVisit: parsedJson["firstVisit"] != null ? parsedJson["firstVisit"] : false,
        totalGuest: guestVal,
        bookingType: parsedJson['bookingType'] as String? ?? 'flexible',
        slotId: parsedJson['slotId'] as String? ?? '',
        selectedTime: parsedJson['selectedTime'] as String? ?? '',
        selectedEndTime: parsedJson['selectedEndTime'] as String? ?? '',
        bookingDate: parsedJson['bookingDate'] as String? ?? '',
        bookingDateKey: parsedJson['bookingDateKey'] as String? ?? '',
        pricingModel: parsedJson['pricingModel'] as String? ?? 'free',
        bookingCharge: parsedJson['bookingCharge'] is num ? parsedJson['bookingCharge'] as num : 0,
        totalCharge: parsedJson['totalCharge'] is num ? parsedJson['totalCharge'] as num : 0,
        approvalMode: parsedJson['approvalMode'] as String? ?? 'auto',
        capacityReleased: parsedJson['capacityReleased'] == true);
  }

  // Same trim as OrderModel._vendorSnapshot (2026-09-06) - full
  // VendorModel.toJson() dumped ~65 fields into every booking (confirmed
  // live: a recent booked_table document ran ~15KB of embedded vendor
  // alone). A cross-app field-usage trace found only these fields are ever
  // read off booking.vendor across the Customer App, Vendor App, and
  // Vendor Web. VendorModel.fromJson() defaults every omitted field, so
  // this isn't a partial-parse risk on read.
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

  // Same trim as OrderModel._authorSnapshot - the booking's own
  // guestFirstName/guestLastName/guestPhone fields already carry the
  // actually-displayed guest details (see the field docs above), so this
  // embed only needs to cover the handful of author.X reads found on
  // booking.author (map-directions location, fcmToken for notifications).
  static Map<String, dynamic> _authorSnapshot(User a) => {
    'id': a.userID,
    'firstName': a.firstName,
    'lastName': a.lastName,
    'phoneNumber': a.phoneNumber,
    'email': a.email,
    'fcmToken': a.fcmToken,
    'location': a.location.toJson(),
  };

  Map<String, dynamic> toJson() {
    return {
      'author': _authorSnapshot(author),
      'authorID': authorID,
      'createdAt': createdAt,
      'date': date,
      'id': id,
      'section_id': section_id,
      'status': status,
      'vendor': _vendorSnapshot(vendor),
      'vendorID': vendorID,
      'guestEmail': guestEmail,
      'guestFirstName': guestFirstName,
      'guestLastName': guestLastName,
      'guestPhone': guestPhone,
      'occasion': occasion,
      'specialRequest': specialRequest,
      'firstVisit': firstVisit,
      'totalGuest': totalGuest,
      'bookingType': bookingType,
      'slotId': slotId,
      'selectedTime': selectedTime,
      'selectedEndTime': selectedEndTime,
      'bookingDate': bookingDate,
      'bookingDateKey': bookingDateKey,
      'pricingModel': pricingModel,
      'bookingCharge': bookingCharge,
      'totalCharge': totalCharge,
      'approvalMode': approvalMode,
      'capacityReleased': capacityReleased,
    };
  }
}
