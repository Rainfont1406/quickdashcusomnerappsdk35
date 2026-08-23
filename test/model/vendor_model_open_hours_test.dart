// Regression tests for the schedule-time vendor-open gate fix (2026-08-23):
// CartScreen._validateCart() used to check VendorModel.isAcceptingOrders,
// which always evaluated against DateTime.now() - never the customer's
// chosen scheduleTime - so a vendor momentarily closed at cart-load time
// could permanently block checkout even for a schedule slot the vendor
// would legitimately be open for, and vice versa.
//
// These tests cover the pure logic added/changed for that fix:
// VendorModel.isCurrentDateInRange (now takes an optional `at`, and is now
// inclusive at both edges to match CartScreen._generateTimeSlots(), which
// generates the closing-time slot itself), VendorModel.isOpen(at), and
// VendorModel.isAcceptingOrdersAt(at). No Firestore/widget dependency -
// these are plain synchronous methods on a model built directly in-memory.
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/model/WorkingHoursModel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VendorModel.isCurrentDateInRange', () {
    final vendor = VendorModel();
    final start = DateTime(2026, 8, 23, 9, 0);
    final end = DateTime(2026, 8, 23, 22, 0);

    test('an instant well inside the range is in range', () {
      expect(
        vendor.isCurrentDateInRange(start, end, DateTime(2026, 8, 23, 15, 0)),
        isTrue,
      );
    });

    test('an instant well outside the range is not in range', () {
      expect(
        vendor.isCurrentDateInRange(start, end, DateTime(2026, 8, 23, 23, 0)),
        isFalse,
      );
      expect(
        vendor.isCurrentDateInRange(start, end, DateTime(2026, 8, 23, 6, 0)),
        isFalse,
      );
    });

    test('exactly the start instant is in range (inclusive)', () {
      expect(vendor.isCurrentDateInRange(start, end, start), isTrue);
    });

    test('exactly the end instant is in range (inclusive) - the boundary-edge fix', () {
      // CartScreen._generateTimeSlots() generates the closing-time slot
      // itself (`for (m = startMinutes; m <= endMinutes; m += 30)`), so a
      // customer scheduling for exactly closing time must pass this check
      // too - a strict isBefore(end) would reject the one slot the picker
      // itself explicitly offers.
      expect(vendor.isCurrentDateInRange(start, end, end), isTrue);
    });

    test('one millisecond before start is not in range', () {
      expect(
        vendor.isCurrentDateInRange(
            start, end, start.subtract(const Duration(milliseconds: 1))),
        isFalse,
      );
    });

    test('one millisecond after end is not in range', () {
      expect(
        vendor.isCurrentDateInRange(
            start, end, end.add(const Duration(milliseconds: 1))),
        isFalse,
      );
    });

    test('omitting `at` falls back to DateTime.now() (existing callers unaffected)', () {
      final now = DateTime.now();
      final wideStart = now.subtract(const Duration(hours: 1));
      final wideEnd = now.add(const Duration(hours: 1));
      expect(vendor.isCurrentDateInRange(wideStart, wideEnd), isTrue);
    });
  });

  group('VendorModel.isOpen(at) / isAcceptingOrdersAt(at)', () {
    // 2026-08-24 is a Monday.
    VendorModel vendorOpenMondayEveningOnly() => VendorModel(
          reststatus: true,
          workingHours: [
            WorkingHoursModel(
              day: 'Monday',
              timeslot: [Timeslot(from: '18:00', to: '23:00')],
            ),
          ],
        );

    test('a scheduled time inside the working-hours window is open', () {
      final vendor = vendorOpenMondayEveningOnly();
      final scheduled = DateTime(2026, 8, 24, 19, 30); // Monday 7:30pm
      expect(vendor.isOpen(scheduled), isTrue);
      expect(vendor.isAcceptingOrdersAt(scheduled), isTrue);
    });

    test('a scheduled time outside the working-hours window is closed', () {
      final vendor = vendorOpenMondayEveningOnly();
      final scheduled = DateTime(2026, 8, 24, 12, 0); // Monday noon - before 18:00
      expect(vendor.isOpen(scheduled), isFalse);
      expect(vendor.isAcceptingOrdersAt(scheduled), isFalse);
    });

    test('a scheduled time on a day with no configured hours is closed', () {
      final vendor = vendorOpenMondayEveningOnly();
      final scheduled = DateTime(2026, 8, 25, 19, 30); // Tuesday - no entry at all
      expect(vendor.isOpen(scheduled), isFalse);
    });

    test('manual reststatus=false closed override still blocks a schedule inside working hours', () {
      // This is the exact gap the fix closed: CartScreen's slot picker only
      // looks at workingHours, never reststatus - isAcceptingOrdersAt is
      // what actually catches a manual "closed today" toggle.
      final vendor = VendorModel(
        reststatus: false,
        workingHours: [
          WorkingHoursModel(
            day: 'Monday',
            timeslot: [Timeslot(from: '18:00', to: '23:00')],
          ),
        ],
      );
      final scheduled = DateTime(2026, 8, 24, 19, 30);
      expect(vendor.isOpen(scheduled), isTrue); // the hours themselves say open...
      expect(vendor.isAcceptingOrdersAt(scheduled), isFalse); // ...but the manual toggle wins
    });

    test('exactly the closing-time instant is still open (boundary-edge fix, via isOpen)', () {
      final vendor = vendorOpenMondayEveningOnly();
      final scheduled = DateTime(2026, 8, 24, 23, 0); // exactly 23:00
      expect(vendor.isOpen(scheduled), isTrue);
    });

    test('midnight-crossing slot: a schedule after midnight matches yesterday\'s slot', () {
      // Monday 22:00 -> 02:00 crosses into Tuesday. A schedule for Tuesday
      // 01:00 should count as still within Monday's slot.
      final vendor = VendorModel(
        reststatus: true,
        workingHours: [
          WorkingHoursModel(
            day: 'Monday',
            timeslot: [Timeslot(from: '22:00', to: '02:00')],
          ),
        ],
      );
      final scheduledLateNight = DateTime(2026, 8, 25, 1, 0); // Tuesday 1am
      expect(vendor.isOpen(scheduledLateNight), isTrue);

      final scheduledMorning = DateTime(2026, 8, 25, 6, 0); // Tuesday 6am - well past the crossed window
      expect(vendor.isOpen(scheduledMorning), isFalse);
    });

    test('a non-crossing slot on the day before does not leak into today', () {
      // Sunday 09:00 -> 20:00 does NOT cross midnight, so it must not be
      // treated as reaching into Monday at all.
      final vendor = VendorModel(
        reststatus: true,
        workingHours: [
          WorkingHoursModel(
            day: 'Sunday',
            timeslot: [Timeslot(from: '09:00', to: '20:00')],
          ),
        ],
      );
      final mondayMorning = DateTime(2026, 8, 24, 9, 0);
      expect(vendor.isOpen(mondayMorning), isFalse);
    });

    test('isOpen() with no argument still defaults to DateTime.now() (existing callers unaffected)', () {
      final now = DateTime.now();
      final vendor = VendorModel(
        reststatus: true,
        workingHours: [
          WorkingHoursModel(
            day: [
              'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'
            ][now.weekday % 7],
            timeslot: [Timeslot(from: '00:00', to: '23:59')],
          ),
        ],
      );
      expect(vendor.isOpen(), isTrue);
      expect(vendor.isOpen(now), isTrue);
    });
  });
}
