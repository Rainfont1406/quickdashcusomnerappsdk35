import 'package:emartconsumer/model/VendorModel.dart';

/// 2026-10-07: what a Dining checkout needs to know, kept in memory for the
/// session so that backing out of the Payment screen and coming back does not
/// read the same things again:
///  - the restaurant's seat settings (vendor_live, ~0.4 KB) - 5 min;
///  - whether this customer already has a table booked there today - 3 min;
///  - the guest count the customer chose - 30 min, so the guest sheet is not
///    asked again (the Payment page shows "Guests: X" with a Change button).
/// Memory only (gone when the app is closed), keyed by customer + restaurant,
/// and cleared on logout. Nothing here is a source of truth: the server
/// re-verifies seats and prices when the order is placed.
class DiningCheckoutCache {
  static const Duration _vendorTtl = Duration(minutes: 5);
  static const Duration _bookingTtl = Duration(minutes: 3);
  static const Duration _guestsTtl = Duration(minutes: 30);

  static final Map<String, _Entry> _m = {};

  static String _k(String userId, String vendorId) => '$userId|$vendorId';

  static VendorModel? vendor(String userId, String vendorId) {
    final e = _m[_k(userId, vendorId)];
    if (e == null || e.vendor == null || !_fresh(e.vendorAt, _vendorTtl)) return null;
    return e.vendor;
  }

  static void putVendor(String userId, String vendorId, VendorModel v) {
    final e = _m.putIfAbsent(_k(userId, vendorId), () => _Entry());
    e.vendor = v;
    e.vendorAt = DateTime.now();
  }

  /// `checked` is false when the booking lookup has not been done (or is
  /// stale); when true, `guests` is null for "no booking today".
  static ({bool checked, int? guests}) existingBooking(String userId, String vendorId) {
    final e = _m[_k(userId, vendorId)];
    if (e == null || !e.bookingChecked || !_fresh(e.bookingAt, _bookingTtl)) {
      return (checked: false, guests: null);
    }
    return (checked: true, guests: e.bookingGuests);
  }

  static void putExistingBooking(String userId, String vendorId, int? guests) {
    final e = _m.putIfAbsent(_k(userId, vendorId), () => _Entry());
    e.bookingChecked = true;
    e.bookingGuests = guests;
    e.bookingAt = DateTime.now();
  }

  static int? guestCount(String userId, String vendorId) {
    final e = _m[_k(userId, vendorId)];
    if (e == null || e.guests == null || !_fresh(e.guestsAt, _guestsTtl)) return null;
    return e.guests;
  }

  static void putGuestCount(String userId, String vendorId, int guests) {
    final e = _m.putIfAbsent(_k(userId, vendorId), () => _Entry());
    e.guests = guests;
    e.guestsAt = DateTime.now();
  }

  /// A table booking was just created or changed: forget the booking lookup
  /// and the remembered guest count for this restaurant.
  static void forgetBooking(String userId, String vendorId) {
    final e = _m[_k(userId, vendorId)];
    if (e == null) return;
    e.bookingChecked = false;
    e.guests = null;
  }

  static void clearAll() => _m.clear();

  static bool _fresh(DateTime? at, Duration ttl) =>
      at != null && DateTime.now().difference(at) < ttl;
}

class _Entry {
  VendorModel? vendor;
  DateTime? vendorAt;
  bool bookingChecked = false;
  int? bookingGuests;
  DateTime? bookingAt;
  int? guests;
  DateTime? guestsAt;
}
