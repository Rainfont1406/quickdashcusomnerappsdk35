import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// Small, persisted running counters used for "repeated X" signals (repeat
// restaurant visit, repeat product view, repeat search query). There is
// deliberately no separate "is this a repeat?" detection step anywhere in
// this system - every relevant event just carries its own running count
// (e.g. visitCount), and "repeated" is a downstream read-time
// interpretation (count > 1), not something decided at write time.
//
// Bounded by distinct-entity count, not event count (unlike
// BehaviorQueueStore, whose size is bounded by event volume) - a single
// small JSON map, persisted whole on every increment. Cheap because this
// map only grows with how many distinct restaurants/products/queries a
// user has ever touched, not how many times they've touched them.
class BehaviorCounters {
  static const String _prefsKey = 'behavior_counters_v1';
  static Map<String, int>? _cache;

  static Future<Map<String, int>> _hydrate() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      _cache = {};
      return _cache!;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _cache = decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      _cache = {};
    }
    return _cache!;
  }

  static String _key(String namespace, String key) => '$namespace:$key';

  // Increments and returns the NEW count for (namespace, key), e.g.
  // ('restaurant_visit', vendorID) or ('search_query', normalizedQuery).
  static Future<int> increment(String namespace, String key) async {
    final map = await _hydrate();
    final k = _key(namespace, key);
    final next = (map[k] ?? 0) + 1;
    map[k] = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(map));
    return next;
  }

  // Read-only peek without incrementing.
  static int peek(String namespace, String key) {
    return _cache?[_key(namespace, key)] ?? 0;
  }
}
