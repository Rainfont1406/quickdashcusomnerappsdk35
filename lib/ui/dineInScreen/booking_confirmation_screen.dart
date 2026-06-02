import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart' show amountShow, ORDER_STATUS_ACCEPTED;
import 'package:emartconsumer/model/BookTableModel.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/dineInScreen/my_booking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BookingConfirmationScreen extends StatelessWidget {
  final BookTableModel booking;

  const BookingConfirmationScreen({Key? key, required this.booking}) : super(key: key);

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
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    icon: const Icon(Icons.home_rounded, size: 18, color: Colors.white),
                    label: Text('Done'.tr(), style: const TextStyle(color: Colors.white)),
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
