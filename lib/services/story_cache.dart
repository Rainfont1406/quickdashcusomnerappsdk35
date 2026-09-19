import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emartconsumer/model/story_model.dart';
import 'package:emartconsumer/services/config_refresh_gate.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On-device persistent cache for the per-section story list (2026-09-15).
///
/// WHY: getStory() re-read every story document in the section on every cold
/// start (7 docs on the measured test section). Its existing cache is an
/// in-memory 10-minute TTL that dies with the app process, so it never helped
/// a cold start at all.
///
/// WHAT MAKES STORIES DIFFERENT FROM THE OTHER CACHED CONFIGS: a story can
/// expire, and StoryModel.isExpired depends on three separate factors that do
/// NOT cache equally well:
///
///   1. `backstopExpiresAt` (hard date cap locked at purchase) - pure time
///      math, so a cached copy evaluates this EXACTLY right with zero reads.
///   2. `createdAt + duration` (legacy day-based stories) - same, exact
///      offline.
///   3. `viewCount >= viewPackageSize` - NOT cacheable. viewCount is a shared
///      server-side counter incremented by OTHER customers viewing the same
///      story. A cached copy can never learn that someone else exhausted the
///      vendor's purchased view package.
///
/// Factor 3 is the reason this class is more than a plain TTL cache. Because
/// viewPackageSize is literally purchased (see StoryModel.amountPaid /
/// pricePerView), serving a story past its package means the vendor receives
/// impressions they did not pay for. So:
///
///   - [needsServerVerify] refuses the cache entirely when ANY cached story is
///     already within [_viewHeadroomThreshold] of its package cap - those are
///     the ones realistically about to exhaust.
///   - [fullRefreshInterval] forces a real re-fetch on a fixed cadence
///     regardless, which is also what catches deletions and un-approvals (a
///     cache can't observe a document disappearing).
///
/// Residual, explicitly accepted risk (product decision 2026-09-15): a story
/// sitting below the headroom threshold could still be exhausted by a burst of
/// other viewers between refreshes, showing free impressions for up to
/// [fullRefreshInterval]. Fully closing that needs a server-side signal (a
/// per-section digest document bumped by a Cloud Function on story writes),
/// which was deliberately deferred as cross-repo work.
class StoryCache {
  StoryCache._();

  /// Safety-net cadence for a genuine full re-fetch. Also the upper bound on
  /// how long a deleted/un-approved story can linger, and on the free-
  /// impression window described above.
  static const Duration fullRefreshInterval = Duration(hours: 6);

  /// Cached stories at or above this fraction of their purchased view package
  /// are treated as "about to exhaust" - the cache is skipped and the real
  /// list fetched instead.
  static const double _viewHeadroomThreshold = 0.85;

  static const String _prefsKeyPrefix = 'cached_story_list_';
  static String _prefsKey(String sectionId) => '$_prefsKeyPrefix$sectionId';

  /// Gate key for [fullRefreshInterval]; kept separate from the payload key so
  /// the freshness clock and the data can be reasoned about independently.
  static String gateKey(String sectionId) => 'storyList_$sectionId';

  /// True when the cached set must not be trusted because at least one story
  /// is close enough to its purchased view cap that other viewers have likely
  /// exhausted it since this copy was written. See the class doc.
  static bool needsServerVerify(List<StoryModel> cached) {
    for (final s in cached) {
      final size = s.viewPackageSize;
      if (size != null && size > 0 && s.viewCount >= (size * _viewHeadroomThreshold)) {
        debugPrint('[StoryCache] cached story ${s.storyID} at ${s.viewCount}/$size '
            'views (>= ${(_viewHeadroomThreshold * 100).round()}% of package) '
            '- forcing a server fetch rather than trusting the cache');
        return true;
      }
    }
    return false;
  }

  /// Reads the persisted list. Returns null when absent or unparseable, both
  /// of which mean "go fetch". Deliberately does NOT check
  /// [fullRefreshInterval] - the caller decides how to combine freshness with
  /// [needsServerVerify] and the new-story probe.
  static Future<List<StoryModel>?> read(String sectionId) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefsKey(sectionId));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final stories = <StoryModel>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        stories.add(StoryModel.fromJson(_decodeTimestamps(entry.cast<String, dynamic>())));
      }
      return stories;
    } catch (_) {
      return null;
    }
  }

  /// Persists [stories] and starts a fresh [fullRefreshInterval] window.
  /// Call only after a genuinely successful fetch.
  static Future<void> write(String sectionId, List<StoryModel> stories) async {
    try {
      final encoded = stories.map((s) => _encodeTimestamps(s.toJson())).toList();
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefsKey(sectionId), jsonEncode(encoded));
      await ConfigRefreshGate.markRefreshed(gateKey(sectionId));
    } catch (e) {
      debugPrint('[StoryCache] write failed (non-fatal, next start re-fetches): $e');
    }
  }

  /// The newest createdAt across [stories] - the lower bound for the
  /// "has anything new been posted?" probe query. Null when unknowable, which
  /// the caller must treat as "can't probe, do a full fetch".
  static Timestamp? newestCreatedAt(List<StoryModel> stories) {
    Timestamp? newest;
    for (final s in stories) {
      final c = s.createdAt;
      if (c == null) continue;
      if (newest == null || c.compareTo(newest) > 0) newest = c;
    }
    return newest;
  }

  // StoryModel.toJson() emits real Timestamp objects for createdAt and
  // backstopExpiresAt, which jsonEncode cannot represent. They are stored as
  // epoch millis and rebuilt into Timestamps on read - these two fields drive
  // the entire time-based half of isExpired, so dropping them (as the generic
  // ConfigRefreshGate.writeDoc helper would) is not an option here.
  static Map<String, dynamic> _encodeTimestamps(Map<String, dynamic> json) {
    final out = Map<String, dynamic>.from(json);
    for (final field in const ['createdAt', 'backstopExpiresAt']) {
      final v = out[field];
      out[field] = v is Timestamp ? v.millisecondsSinceEpoch : null;
    }
    return out;
  }

  static Map<String, dynamic> _decodeTimestamps(Map<String, dynamic> json) {
    final out = Map<String, dynamic>.from(json);
    for (final field in const ['createdAt', 'backstopExpiresAt']) {
      final v = out[field];
      out[field] = v is int ? Timestamp.fromMillisecondsSinceEpoch(v) : null;
    }
    return out;
  }
}
