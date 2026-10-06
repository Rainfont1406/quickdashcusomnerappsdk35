import 'package:emartconsumer/services/dining_checkout_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(DiningCheckoutCache.clearAll);

  test('a guest count is remembered per customer and restaurant', () {
    DiningCheckoutCache.putGuestCount('u1', 'v1', 4);
    expect(DiningCheckoutCache.guestCount('u1', 'v1'), 4);
    expect(DiningCheckoutCache.guestCount('u2', 'v1'), isNull); // another customer
    expect(DiningCheckoutCache.guestCount('u1', 'v2'), isNull); // another restaurant
  });

  test('changing the guest count replaces the remembered one', () {
    DiningCheckoutCache.putGuestCount('u1', 'v1', 2);
    DiningCheckoutCache.putGuestCount('u1', 'v1', 6);
    expect(DiningCheckoutCache.guestCount('u1', 'v1'), 6);
  });

  test('"no booking today" is remembered as checked, not as unknown', () {
    expect(DiningCheckoutCache.existingBooking('u1', 'v1').checked, false);
    DiningCheckoutCache.putExistingBooking('u1', 'v1', null);
    final r = DiningCheckoutCache.existingBooking('u1', 'v1');
    expect(r.checked, true);
    expect(r.guests, isNull);
    DiningCheckoutCache.putExistingBooking('u1', 'v1', 3);
    expect(DiningCheckoutCache.existingBooking('u1', 'v1').guests, 3);
  });

  test('forgetBooking drops the booking lookup and the guest count', () {
    DiningCheckoutCache.putGuestCount('u1', 'v1', 5);
    DiningCheckoutCache.putExistingBooking('u1', 'v1', 5);
    DiningCheckoutCache.forgetBooking('u1', 'v1');
    expect(DiningCheckoutCache.guestCount('u1', 'v1'), isNull);
    expect(DiningCheckoutCache.existingBooking('u1', 'v1').checked, false);
  });
}
