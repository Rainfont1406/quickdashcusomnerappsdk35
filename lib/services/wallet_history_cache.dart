import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emartconsumer/model/topupTranHistory.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On-device cache for the wallet transaction list (2026-09-15).
///
/// WHY: walletScreen attached a live listener over the customer's last 20
/// wallet transactions on every single open, and attaching a listener bills
/// its whole matching result set - so ~20 documents every time the wallet was
/// opened, to re-read rows that had not changed since the last open.
///
/// A completed wallet transaction is immutable, which makes it cacheable in
/// exactly the way this codebase already caches settled orders (see
/// order_history_cache.dart's isOrderSafeToCachePermanently). This class is
/// the wallet equivalent.
///
/// WHAT IS DELIBERATELY *NOT* CACHED:
///   - The BALANCE. That lives on users/{uid}.wallet_amount and keeps its own
///     independent live listener in walletScreen, untouched by this class, so
///     a Razorpay top-up or an admin credit still lands instantly. Caching a
///     wallet balance would be wrong at any TTL.
///   - The FINALITY of a non-terminal transaction (see [isTerminal]). Those
///     rows ARE persisted (2026-09-16 fix - see [write]), so [cursorFor] can
///     still find them and pull the cursor back on a cold start, not just
///     within the session that first saw them; but they carry no guarantee
///     their cached copy is current, and the read cursor is deliberately
///     held back to keep re-fetching them live until they settle - see
///     [cursorFor].
class WalletHistoryCache {
  WalletHistoryCache._();

  /// Matches the page size walletScreen has always shown.
  static const int maxEntries = 20;

  static const String _prefsKeyPrefix = 'cached_wallet_history_';
  static String _prefsKey(String userId) => '$_prefsKeyPrefix$userId';

  /// A transaction in this state will never change again, so it is safe to
  /// keep permanently. Verified against live production data 2026-09-15:
  /// every sampled wallet document was 'success'. Anything unrecognised is
  /// treated as NON-terminal on purpose - the safe direction is to keep
  /// watching a row we are unsure about, not to freeze it.
  static bool isTerminal(TopupTranHistoryModel t) =>
      t.payment_status.toLowerCase() == 'success';

  /// The point from which live data is still required.
  ///
  /// Normally this is the newest cached transaction - everything older is
  /// already held locally. But if ANY known transaction is still non-terminal,
  /// the cursor is pulled back to just before the oldest such row, so that row
  /// keeps arriving in the live query until it settles. Without this, a
  /// pending transaction older than the newest successful one would fall
  /// outside the query window and silently disappear from the list.
  static Timestamp? cursorFor(List<TopupTranHistoryModel> known) {
    if (known.isEmpty) return null;
    final nonTerminal = known.where((t) => !isTerminal(t)).toList();
    if (nonTerminal.isNotEmpty) {
      Timestamp oldest = nonTerminal.first.date;
      for (final t in nonTerminal) {
        if (t.date.compareTo(oldest) < 0) oldest = t.date;
      }
      // One millisecond back so the row itself is still matched by a
      // strictly-greater-than filter.
      return Timestamp.fromMillisecondsSinceEpoch(
          oldest.millisecondsSinceEpoch - 1);
    }
    Timestamp newest = known.first.date;
    for (final t in known) {
      if (t.date.compareTo(newest) > 0) newest = t.date;
    }
    return newest;
  }

  /// Union of [cached] and [fresh], de-duplicated by transaction id (fresh
  /// wins, so a row that just changed state replaces its stale copy), sorted
  /// newest-first and capped at [maxEntries].
  static List<TopupTranHistoryModel> merge(
      List<TopupTranHistoryModel> cached, List<TopupTranHistoryModel> fresh) {
    final byId = <String, TopupTranHistoryModel>{};
    for (final t in cached) {
      if (t.id.isNotEmpty) byId[t.id] = t;
    }
    for (final t in fresh) {
      if (t.id.isNotEmpty) byId[t.id] = t;
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return merged.length > maxEntries ? merged.sublist(0, maxEntries) : merged;
  }

  static Future<List<TopupTranHistoryModel>> read(String userId) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefsKey(userId));
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <TopupTranHistoryModel>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        try {
          out.add(TopupTranHistoryModel.fromJson(
              _decodeDate(e.cast<String, dynamic>())));
        } catch (_) {
          // Skip one unparseable row rather than losing the whole cache.
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Persists [transactions] as-is (terminal AND non-terminal rows).
  ///
  /// 2026-09-16: previously filtered to terminal-only before writing, which
  /// broke [cursorFor]'s own pull-back-for-non-terminal-rows logic across a
  /// cold start - a transaction that was still pending when the app was
  /// killed would never be written to disk, so on the next launch `known`
  /// (seeded from [read]) contained no non-terminal rows for cursorFor to
  /// pull the cursor back for. If a newer transaction had settled since,
  /// the live query's `date > cursor` cutoff permanently excluded that
  /// still-pending row - it silently vanished from wallet history even
  /// after it later settled server-side. Persisting it (its cached copy is
  /// never trusted as final - isTerminal is re-checked on every read) keeps
  /// it visible to cursorFor on every future cold start until it actually
  /// settles and a fresh live snapshot overwrites it via [merge].
  static Future<void> write(
      String userId, List<TopupTranHistoryModel> transactions) async {
    try {
      if (transactions.isEmpty) return;
      final encoded = transactions
          .map((t) => _encodeDate(t.toJson()))
          .toList(growable: false);
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefsKey(userId), jsonEncode(encoded));
    } catch (e) {
      debugPrint('[WalletHistoryCache] write failed (non-fatal): $e');
    }
  }

  /// Clears this user's cached history - for logout, so one account's
  /// transactions can never be shown under another.
  static Future<void> clear(String userId) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_prefsKey(userId));
    } catch (_) {}
  }

  // `date` is a Timestamp, which jsonEncode cannot represent - stored as epoch
  // millis and rebuilt on read. TopupTranHistoryModel.fromJson already guards
  // a non-Timestamp `date` by substituting Timestamp.now(), which would
  // silently re-date every cached row, so this conversion is load-bearing.
  static Map<String, dynamic> _encodeDate(Map<String, dynamic> json) {
    final out = Map<String, dynamic>.from(json);
    final v = out['date'];
    out['date'] = v is Timestamp ? v.millisecondsSinceEpoch : null;
    return out;
  }

  static Map<String, dynamic> _decodeDate(Map<String, dynamic> json) {
    final out = Map<String, dynamic>.from(json);
    final v = out['date'];
    out['date'] = v is int ? Timestamp.fromMillisecondsSinceEpoch(v) : null;
    return out;
  }
}
