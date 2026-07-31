import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// Local, offline-durable persistence for the pending behavior-event queue.
// Follows the same all-static-class-over-SharedPreferences pattern as
// lib/userPrefrence.dart's UserPreference (already used there for
// JSON-encoded objects) - deliberately NOT the Moor/SQLite CartDatabase,
// which has no schema-migration strategy in place today, making it a real
// risk to extend for something new.
//
// Fetches its own SharedPreferences instance independently (rather than
// depending on UserPreference.init() having already run) so there's no
// startup-ordering coupling between the two.
class BehaviorQueueStore {
  static const String _prefsKey = 'behavior_event_queue_v1';

  // Bounds local storage if uploads fail for a long stretch (extended
  // offline period, repeated flush failures) - oldest events are dropped
  // first once the cap is hit, since a rough behavior signal is more useful
  // than none, and unbounded growth would defeat "very low local overhead."
  static const int maxPersisted = 200;

  static Future<List<Map<String, dynamic>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      // Corrupt/unparseable queue (e.g. app update changed shape) - drop it
      // rather than crash; a lost batch of behavior events is harmless.
      return [];
    }
  }

  static Future<void> save(List<Map<String, dynamic>> events) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(events));
  }

  // Appends with drop-oldest-on-overflow and returns the resulting list -
  // callers persist the returned list via save().
  static List<Map<String, dynamic>> appendCapped(
    List<Map<String, dynamic>> current,
    Map<String, dynamic> event,
  ) {
    final next = [...current, event];
    if (next.length > maxPersisted) {
      return next.sublist(next.length - maxPersisted);
    }
    return next;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
