import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// Local, offline-durable persistence for BehaviorTracker's combo-metadata
// cache. Same all-static-class-over-SharedPreferences pattern as
// BehaviorQueueStore/RecentRestaurantSessionStore.
//
// WHY THIS EXISTS: a combo product's isCombo/comboProducts/comboCategoryIds
// live only on its catalog ProductModel, which is in scope for free at
// add-to-cart time (the same moment isVeg/isNonVeg/categoryId are already
// captured there) but NOT at checkout time, where only the leaner
// CartProduct survives (no combo fields, and adding them would need a
// CartProducts/Moor schema migration this codebase deliberately avoids -
// same reasoning as the veg/non-veg signal's own doc comment). Caching
// what was learned at add-to-cart time, keyed by productId, lets checkout
// (and PurchaseCompletionListener, later, at order completion) recover it
// with zero extra Firestore reads instead of re-fetching the catalog
// product. Persisted so it survives an app restart between adding a combo
// to cart and eventually checking out, same durability reasoning as
// RecentRestaurantSessionStore.
class ComboMetadataStore {
  static const String _prefsKey = 'behavior_combo_metadata_v1';

  static Future<Map<String, dynamic>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt/unparseable cache - drop it rather than crash; losing this
      // just means the next combo order is missing enrichment, same as
      // today's baseline (no combo signal at all).
      return {};
    }
  }

  static Future<void> save(Map<String, dynamic> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(entries));
  }
}
