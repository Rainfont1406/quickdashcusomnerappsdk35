import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// Local, offline-durable persistence for BehaviorTracker's
// _recentRestaurantSessions list. Same all-static-class-over-SharedPreferences
// pattern as BehaviorQueueStore - that list was previously in-memory only,
// which meant CheckoutScreen/PaymentScreen's recentRestaurantSessionFor()
// lookup went empty on any app restart between browsing a vendor's menu and
// checking out, silently blanking analyticsSnapshot.restaurantSessionId on
// an otherwise-normal order. Persisting it closes that gap without changing
// the existing 120-minute recency window's semantics at all.
class RecentRestaurantSessionStore {
  static const String _prefsKey = 'behavior_recent_restaurant_sessions_v1';

  static Future<List<Map<String, dynamic>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      // Corrupt/unparseable list (e.g. app update changed shape) - drop it
      // rather than crash; losing this cache just means the next order
      // falls back to an empty restaurantSessionId, same as today.
      return [];
    }
  }

  static Future<void> save(List<Map<String, dynamic>> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(sessions));
  }
}
