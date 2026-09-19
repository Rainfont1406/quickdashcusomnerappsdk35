import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted "when did we last refresh this config?" gate (2026-09-15).
///
/// WHY THIS EXISTS: several app-config fetches ran on EVERY cold start even
/// though their result was already persisted on-device and virtually never
/// changes (Razorpay gateway settings, wallet on/off, tax rates,
/// recommendation tuning). Proven live against the project's own
/// firestore.googleapis.com/document/read_count metric: a steady-state cold
/// start billed ~18-20 documents, of which ~9 were these
/// rarely-changing config reads - re-fetched every single launch purely to
/// overwrite a local copy that was already correct.
///
/// The local copies themselves already existed (UserPreference.setRazorPayData
/// / setWalletData, etc. have persisted them to SharedPreferences for a long
/// time) and the rest of the app already reads from them. What was missing was
/// any notion of "this copy is still fresh, don't re-fetch" - so every launch
/// paid the read again. This class is only that missing age check.
///
/// SAFETY POSTURE - it never serves stale data by accident:
///   - Callers must only consult this AFTER confirming a local value actually
///     exists; a fresh install (no local copy) always fetches.
///   - [markRefreshed] is called only AFTER a fetch genuinely succeeds, so a
///     failed/offline fetch never starts a fresh TTL window.
///   - Any SharedPreferences error resolves to "not fresh" (i.e. fetch),
///     never to "fresh".
///   - A device clock moved backwards can't pin a config as permanently
///     fresh (see the `now >= lastMs` guard).
class ConfigRefreshGate {
  ConfigRefreshGate._();

  static const String _prefix = 'config_last_refresh_';

  /// True when [key] was successfully refreshed less than [ttl] ago, i.e. the
  /// caller can skip its network fetch entirely. False means "go fetch".
  static Future<bool> isFresh(String key, Duration ttl) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final lastMs = sp.getInt('$_prefix$key');
      if (lastMs == null) return false;
      final now = DateTime.now().millisecondsSinceEpoch;
      // now < lastMs means the clock moved backwards (or the stored value is
      // bogus) - treat as not fresh rather than trusting a future timestamp
      // that would otherwise suppress refreshes until it passes.
      if (now < lastMs) return false;
      return (now - lastMs) < ttl.inMilliseconds;
    } catch (_) {
      return false;
    }
  }

  /// Records "refreshed now" for [key]. Call ONLY after the fetch succeeded.
  static Future<void> markRefreshed(String key) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt('$_prefix$key', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // Best-effort - failing to record just means the next launch re-fetches,
      // which is the safe direction to fail in.
    }
  }

  /// Convenience for the common shape: "skip the fetch if a local copy exists
  /// and is still inside [ttl]". [hasLocalValue] must be the caller's own
  /// check that a usable persisted value is actually present.
  static Future<bool> canSkipFetch({
    required String key,
    required Duration ttl,
    required bool hasLocalValue,
  }) async {
    if (!hasLocalValue) return false;
    final fresh = await isFresh(key, ttl);
    if (fresh) {
      debugPrint('[ConfigCache] $key served from persisted local copy '
          '(still inside ${ttl.inHours}h TTL) - 0 Firestore reads');
    }
    return fresh;
  }

  static const String _docPrefix = 'config_doc_';

  /// Reads a previously-stored raw Firestore document map for [key], but only
  /// while it is still inside [ttl]. Returns null when absent, expired or
  /// unparseable - all of which mean "go fetch".
  ///
  /// Deliberately stores the RAW `snap.data()` map rather than a serialized
  /// model: the caller rehydrates with its existing `fromJson`, so no model
  /// needs a hand-written `toJson` that could silently drift out of sync as
  /// fields are added.
  static Future<Map<String, dynamic>?> readDoc(String key, Duration ttl) async {
    try {
      if (!await isFresh(key, ttl)) return null;
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('$_docPrefix$key');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return decoded.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  /// Stores [data] for [key] and starts its TTL window. Call only after a
  /// genuinely successful fetch.
  ///
  /// Firestore maps can contain values `jsonEncode` cannot represent
  /// (Timestamp, GeoPoint, DocumentReference). Those are dropped rather than
  /// throwing, so a document carrying one still caches its plain fields - the
  /// configs gated here are flat primitives. If a caller ever needs a
  /// non-primitive field preserved it must not use this helper.
  static Future<void> writeDoc(String key, Map<String, dynamic> data) async {
    try {
      final safe = <String, dynamic>{};
      data.forEach((k, v) {
        if (v == null || v is num || v is bool || v is String) {
          safe[k] = v;
        } else if (v is List && v.every((e) => e == null || e is num || e is bool || e is String)) {
          safe[k] = v;
        }
      });
      final sp = await SharedPreferences.getInstance();
      await sp.setString('$_docPrefix$key', jsonEncode(safe));
      await markRefreshed(key);
    } catch (_) {
      // Best-effort - next launch just re-fetches.
    }
  }

  static const String _rawPrefix = 'config_raw_';

  /// Raw-string variant, for caching an HTTP response body verbatim.
  ///
  /// This is the LOSSLESS option and the right one for anything whose parsed
  /// model contains nested or non-primitive fields. [writeDoc]/[writeList]
  /// deliberately drop non-primitives, which is fine for a flat config but
  /// would silently destroy data for richer models (VendorModel's
  /// workingHours/topProducts/location, OfferModel's expiresAt, ProductModel's
  /// variants). Caching the original JSON text instead means the cached path
  /// parses through exactly the same code as the live path, so the two cannot
  /// diverge.
  static Future<String?> readRaw(String key, Duration ttl) async {
    try {
      if (!await isFresh(key, ttl)) return null;
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('$_rawPrefix$key');
      if (raw == null || raw.isEmpty) return null;
      return raw;
    } catch (_) {
      return null;
    }
  }

  /// Returns the stored body regardless of age, or null if none was ever
  /// stored. For stale-while-error only (see cachedBunnyGet): an expired copy
  /// is served when a refresh fails, because the alternative is a billed
  /// Firestore fallback over equally-stale data.
  static Future<String?> readRawIgnoringTtl(String key) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('$_rawPrefix$key');
      if (raw == null || raw.isEmpty) return null;
      debugPrint('[ConfigCache] $key refresh failed - serving EXPIRED local '
          'copy instead of falling back to Firestore');
      return raw;
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeRaw(String key, String body) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('$_rawPrefix$key', body);
      await markRefreshed(key);
    } catch (_) {
      // Best-effort - next call just re-fetches.
    }
  }

  static const String _listPrefix = 'config_list_';

  /// List-of-documents variant of [readDoc], for configs that are a small
  /// collection rather than a single document (e.g. the home banner lists).
  /// Same TTL and failure posture: null means "go fetch".
  static Future<List<Map<String, dynamic>>?> readList(
      String key, Duration ttl) async {
    try {
      if (!await isFresh(key, ttl)) return null;
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('$_listPrefix$key');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Stores [items] for [key] and starts its TTL window. Call only after a
  /// genuinely successful fetch. Same primitive-only constraint as [writeDoc]
  /// - callers must not rely on this for Timestamp/GeoPoint fields.
  static Future<void> writeList(
      String key, List<Map<String, dynamic>> items) async {
    try {
      final safe = items.map((m) {
        final out = <String, dynamic>{};
        m.forEach((k, v) {
          if (v == null || v is num || v is bool || v is String) out[k] = v;
        });
        return out;
      }).toList();
      final sp = await SharedPreferences.getInstance();
      await sp.setString('$_listPrefix$key', jsonEncode(safe));
      await markRefreshed(key);
    } catch (_) {
      // Best-effort - next launch just re-fetches.
    }
  }

  /// Clears every recorded refresh time, forcing all gated configs to fetch
  /// again on their next call. For logout/"reset app data"-style flows.
  static Future<void> clearAll() async {
    try {
      final sp = await SharedPreferences.getInstance();
      for (final k in sp.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
        await sp.remove(k);
      }
    } catch (_) {}
  }
}
