// Shared special-discount + coupon "offer ladder" computation - extracted
// 2026-08-30 (§11.21 follow-up) from newVendorProductsScreen.dart's
// previously-private _todaysSpecialSlots/_bestSpecialValueAt/_combineAndCap/
// _recomputeOfferLadder so the same logic can be reused on the table-booking
// screen (show offers before booking) and its confirmation screen (show what
// got locked in) without drifting out of sync with the vendor page's own
// version. Pure computation over already-loaded data - the vendor's
// specialDiscount array is already in memory on VendorModel, and coupons
// come from FireStoreUtils().getAllCoupons(), which is itself a 5-minute
// static app-wide cache (see FirebaseHelper.dart) - calling it from a new
// screen never costs an extra Firestore read as long as anything else in the
// app fetched coupons in the last 5 minutes.
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/model/offer_model.dart';
import 'package:intl/intl.dart';

class SpecialOfferPreviewRung {
  final double thresholdAmount;
  final double savingAmount;
  final String? offerCode;
  // Formatted "hh:mm a" end time of the special-discount slot that won this
  // rung - null when the rung's saving is pure coupon, or the winning slot
  // has no end time.
  final String? validTill;
  const SpecialOfferPreviewRung({
    required this.thresholdAmount,
    required this.savingAmount,
    this.offerCode,
    this.validTill,
  });
}

class _SpecialSlotCandidate {
  final double minAmount;
  final double rawDiscount;
  final bool isPercent;
  final String? validTill;
  const _SpecialSlotCandidate({
    required this.minAmount,
    required this.rawDiscount,
    required this.isPercent,
    this.validTill,
  });
}

class SpecialDiscountPreview {
  // Today's active special-discount slots for [vendor], filtered by day,
  // time-window, and [orderType] ('Delivery' or 'Takeaway' - Dining/Bill Pay
  // callers pass 'Takeaway', matching the existing, established collapse
  // used everywhere else in this codebase). Evaluated at [at] (defaults to
  // DateTime.now()) - callers on a booking-confirmation screen should pass
  // the booking's own createdAt for an exact "what did I just lock in" read.
  static List<_SpecialSlotCandidate> _todaysSlots(
    VendorModel vendor,
    String orderType, {
    DateTime? at,
  }) {
    if (!vendor.specialDiscountEnable || vendor.specialDiscount.isEmpty) {
      return [];
    }
    final now = at ?? DateTime.now();
    final currentDay = DateFormat('EEEE', 'en_US').format(now);
    final dateStr = DateFormat('dd-MM-yyyy').format(now);
    final List<_SpecialSlotCandidate> active = [];

    for (final dayDiscount in vendor.specialDiscount) {
      if (dayDiscount.day != currentDay) continue;
      if (dayDiscount.timeslot == null || dayDiscount.timeslot!.isEmpty) {
        continue;
      }
      for (final slot in dayDiscount.timeslot!) {
        if ((slot.from?.isEmpty ?? true) || (slot.to?.isEmpty ?? true)) {
          continue;
        }
        try {
          final start =
              DateFormat('dd-MM-yyyy HH:mm').parse('$dateStr ${slot.from}');
          var end = DateFormat('dd-MM-yyyy HH:mm').parse('$dateStr ${slot.to}');
          if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
          if (!vendor.isCurrentDateInRange(start, end, now)) continue;
        } catch (_) {
          continue;
        }
        if (slot.orderType != null && slot.orderType!.isNotEmpty) {
          if (slot.orderType != orderType) continue;
        }
        String? validTill;
        try {
          validTill = DateFormat('hh:mm a')
              .format(DateFormat('HH:mm').parse(slot.to!));
        } catch (_) {}
        active.add(_SpecialSlotCandidate(
          minAmount: double.tryParse(slot.applicableAmount ?? '0') ?? 0,
          rawDiscount: double.tryParse(slot.discount ?? '0') ?? 0,
          isPercent: slot.type == 'percentage',
          validTill: validTill,
        ));
      }
    }
    return active;
  }

  static double _couponValueAt(OfferModel coupon, double amount) {
    final isPercent = coupon.discountTypeOffer == 'Percentage' ||
        coupon.discountTypeOffer == 'Percent';
    final raw = double.tryParse(coupon.discountOffer ?? '0') ?? 0;
    return isPercent ? amount * raw / 100 : (raw > amount ? amount : raw);
  }

  static ({double value, String? validTill}) _bestSpecialValueAt(
      double amount, List<_SpecialSlotCandidate> slots) {
    double best = 0;
    String? bestValidTill;
    for (final slot in slots) {
      if (amount < slot.minAmount) continue;
      final actual = slot.isPercent
          ? amount * slot.rawDiscount / 100
          : (slot.rawDiscount > amount ? amount : slot.rawDiscount);
      if (actual > best) {
        best = actual;
        bestValidTill = slot.validTill;
      }
    }
    return (value: best, validTill: bestValidTill);
  }

  static ({double coupon, double special}) _combineAndCap(
      double amount, double couponValue, double specialValue) {
    double coupon = couponValue;
    double special = specialValue;

    if (coupon > 0 && special > 0 && coupon + special > amount) {
      if (coupon <= special) {
        coupon = 0;
      } else {
        special = 0;
      }
    }

    final double maxCombined = amount * maxCombinedDiscountPercent / 100;
    if (coupon + special > maxCombined) {
      final double cappedCoupon = coupon > maxCombined ? maxCombined : coupon;
      final double remaining =
          (maxCombined - cappedCoupon).clamp(0.0, double.infinity);
      special = special > remaining ? remaining : special;
      coupon = cappedCoupon;
    }
    return (coupon: coupon, special: special);
  }

  /// Builds the "maximum rupee saving" ladder: one rung per unique minimum
  /// order amount across every active coupon and special-discount slot,
  /// each answering "if I spend at least this much, what's the most I can
  /// save?" - same algorithm as the vendor page's own offer banner, so a
  /// customer never sees a different answer in two different screens.
  static List<SpecialOfferPreviewRung> buildLadder({
    required VendorModel vendor,
    required List<OfferModel> coupons,
    required String orderType,
    DateTime? at,
  }) {
    final specialSlots = _todaysSlots(vendor, orderType, at: at);
    final relevantCoupons = coupons
        .where((c) =>
            (c.storeId == vendor.id ||
                c.storeId == null ||
                (c.storeId?.isEmpty ?? true)) &&
            c.isPublic != false)
        .toList();

    final Set<double> candidateAmounts = {
      for (final c in relevantCoupons)
        double.tryParse(c.applicableAmount ?? '0') ?? 0,
      for (final s in specialSlots) s.minAmount,
    };

    final List<SpecialOfferPreviewRung> rungs = [];
    for (final amount in candidateAmounts) {
      if (amount <= 0) continue;

      OfferModel? bestCoupon;
      double bestCouponValue = 0;
      for (final coupon in relevantCoupons) {
        final minAmt = double.tryParse(coupon.applicableAmount ?? '0') ?? 0;
        if (amount < minAmt) continue;
        final value = _couponValueAt(coupon, amount);
        if (value > bestCouponValue) {
          bestCouponValue = value;
          bestCoupon = coupon;
        }
      }
      final bestSpecial = _bestSpecialValueAt(amount, specialSlots);

      final combo = _combineAndCap(amount, bestCouponValue, bestSpecial.value);
      final totalSaving = combo.coupon + combo.special;
      if (totalSaving <= 0) continue;

      rungs.add(SpecialOfferPreviewRung(
        thresholdAmount: amount,
        savingAmount: totalSaving,
        offerCode: combo.coupon > 0 ? bestCoupon?.offerCode : null,
        validTill: combo.special > 0 ? bestSpecial.validTill : null,
      ));
    }

    rungs.sort((a, b) => a.thresholdAmount.compareTo(b.thresholdAmount));
    return rungs;
  }
}
