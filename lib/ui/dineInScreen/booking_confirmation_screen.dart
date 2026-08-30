import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart' show amountShow, ORDER_STATUS_ACCEPTED;
import 'package:emartconsumer/model/BookTableModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/special_discount_preview.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/dineInScreen/my_booking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BookingConfirmationScreen extends StatelessWidget {
  final BookTableModel booking;
  // When this booking was made from the Cart's "Dining -> Book a Table"
  // choice (2026-08-29 fix), the customer still has an unpaid food order
  // sitting in that same cart - popping all the way to Home here (the
  // previous unconditional behavior) silently abandoned it with no path
  // back to Payment. Popping twice instead (this screen + the booking
  // screen beneath it) lands them back on that same Cart, still holding
  // their items, ready to continue checkout.
  final bool returnToCart;

  const BookingConfirmationScreen({Key? key, required this.booking, this.returnToCart = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool dark = isDarkMode(context);

    return Scaffold(
      backgroundColor: dark ? AppThemeData.surfaceDark : const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppThemeData.primary600, AppThemeData.primary400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          'Booking Confirmed'.tr(),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ── Success animation ─────────────────────────────────────
            const SizedBox(height: 24),
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppThemeData.primary600, AppThemeData.primary400],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppThemeData.primary500.withOpacity(0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 52),
            ),
            const SizedBox(height: 20),

            Text(
              'Your table has been reserved successfully.'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: dark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _statusSubtitle(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: dark ? Colors.white60 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 28),

            // ── Booking details card ────────────────────────────────
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: dark ? const Color(0xff1e1e1e) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(dark ? 0.3 : 0.07),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Card header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppThemeData.primary600, AppThemeData.primary400],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          'Booking Details'.tr(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: booking.id));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Booking ID copied'.tr())),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.copy_rounded, size: 13, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  'Copy ID'.tr(),
                                  style: const TextStyle(fontSize: 11, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Detail rows
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _detailRow(dark, Icons.confirmation_number_outlined, 'Booking ID'.tr(),
                            '#${booking.id.substring(0, 8).toUpperCase()}'),
                        _divider(dark),
                        _detailRow(dark, Icons.restaurant_outlined, 'Restaurant'.tr(),
                            booking.vendor.title),
                        _divider(dark),
                        _detailRow(dark, Icons.calendar_today_rounded, 'Date'.tr(),
                            booking.bookingDate.isNotEmpty
                                ? booking.bookingDate
                                : DateFormat('EEE, MMM d yyyy').format(booking.date.toDate())),
                        _divider(dark),
                        _detailRow(
                          dark,
                          Icons.access_time_rounded,
                          'Time'.tr(),
                          booking.selectedEndTime.isNotEmpty
                              ? '${booking.selectedTime} – ${booking.selectedEndTime}'
                              : booking.selectedTime.isNotEmpty
                                  ? booking.selectedTime
                                  : DateFormat('hh:mm a').format(booking.date.toDate()),
                        ),
                        _divider(dark),
                        _detailRow(dark, Icons.people_outline_rounded, 'Guests'.tr(),
                            '${booking.totalGuest} ${booking.totalGuest == 1 ? "Guest".tr() : "Guests".tr()}'),
                        if (booking.totalCharge > 0) ...[
                          _divider(dark),
                          _detailRow(dark, Icons.payments_outlined, 'Total Charge'.tr(),
                              amountShow(amount: booking.totalCharge.toString(), decimals: 0)),
                        ],
                        _divider(dark),
                        _detailRow(
                          dark,
                          Icons.info_outline_rounded,
                          'Status'.tr(),
                          booking.status == ORDER_STATUS_ACCEPTED
                              ? 'Confirmed'.tr()
                              : 'Pending Approval'.tr(),
                          valueColor: booking.status == ORDER_STATUS_ACCEPTED
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFFFA726),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Approval notice ─────────────────────────────────────
            if (booking.status != ORDER_STATUS_ACCEPTED)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFCC02).withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_rounded, color: Color(0xFFFFA000), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your booking is pending vendor approval. You will be notified once it\'s confirmed.'.tr(),
                        style: const TextStyle(fontSize: 12, color: Color(0xFF795548)),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),
            _LockedInOffers(booking: booking, dark: dark),
            const SizedBox(height: 24),

            // ── Action buttons ──────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => push(context, const MyBookingScreen()),
                    icon: const Icon(Icons.list_alt_rounded, size: 18),
                    label: Text('My Bookings'.tr()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppThemeData.primary500,
                      side: const BorderSide(color: AppThemeData.primary500),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (returnToCart) {
                        // This screen + the booking screen beneath it -
                        // lands exactly back on the Cart that launched them.
                        Navigator.of(context)
                          ..pop()
                          ..pop();
                      } else {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      }
                    },
                    icon: Icon(returnToCart ? Icons.arrow_back_rounded : Icons.home_rounded, size: 18, color: Colors.white),
                    label: Text(returnToCart ? 'Back to Order'.tr() : 'Done'.tr(), style: const TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppThemeData.primary500,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Support ─────────────────────────────────────────────
            TextButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.support_agent_rounded, size: 18),
              label: Text('Need Help? Contact Support'.tr()),
              style: TextButton.styleFrom(
                foregroundColor: dark ? Colors.white54 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _statusSubtitle() {
    if (booking.status == ORDER_STATUS_ACCEPTED) {
      return 'Get ready for your dining experience!'.tr();
    }
    return 'Awaiting restaurant confirmation'.tr();
  }

  Widget _detailRow(bool dark, IconData icon, String label, String value,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppThemeData.primary500),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: dark ? Colors.white60 : Colors.grey.shade600,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ?? (dark ? Colors.white : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(bool dark) => Divider(
        height: 1,
        color: dark ? Colors.white12 : Colors.grey.shade100,
      );
}

// Shows what special discount/coupon got locked in by making this booking
// (2026-08-30, §11.21 follow-up) - evaluated at booking.createdAt, the exact
// same instant the server's table-booking-time-lock uses for the real
// Dining/Bill Pay order later, so this is a true preview of what checkout
// will actually apply, not a generic "offers available" list. booking.vendor
// is already embedded on BookTableModel (no extra read); coupons come from
// the same 5-minute static cache every other offers display in the app uses.
class _LockedInOffers extends StatefulWidget {
  final BookTableModel booking;
  final bool dark;
  const _LockedInOffers({required this.booking, required this.dark});

  @override
  State<_LockedInOffers> createState() => _LockedInOffersState();
}

class _LockedInOffersState extends State<_LockedInOffers> {
  List<SpecialOfferPreviewRung> _rungs = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final coupons = await FireStoreUtils().getAllCoupons();
      if (!mounted) return;
      setState(() {
        _rungs = SpecialDiscountPreview.buildLadder(
          vendor: widget.booking.vendor,
          coupons: coupons,
          orderType: 'Takeaway',
          at: widget.booking.createdAt.toDate(),
        );
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _rungs.isEmpty) return const SizedBox.shrink();
    final dark = widget.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (dark ? AppThemeData.primary400 : AppThemeData.primary500)
            .withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppThemeData.primary500.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_offer_rounded,
                  size: 18, color: AppThemeData.primary500),
              const SizedBox(width: 8),
              Text(
                'Locked in for your visit'.tr(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: dark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'These offers were live when you booked, and will still apply when you dine or pay - even if they end before then.'
                .tr(),
            style: TextStyle(
              fontSize: 11.5,
              color: dark ? Colors.white60 : Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 10),
          ..._rungs.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 14,
                        color: dark
                            ? AppThemeData.primary300
                            : AppThemeData.primary600),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${'Save'.tr()} ${amountShow(amount: r.savingAmount.toStringAsFixed(2))} ${'on orders above'.tr()} ${amountShow(amount: r.thresholdAmount.toStringAsFixed(2))}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: dark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
