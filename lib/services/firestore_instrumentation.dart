import 'dart:convert' show utf8;
import 'dart:typed_data' show Uint8List;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Approximate payload size of one document's fields, in bytes (2026-09-19).
///
/// WHY THIS EXISTS: read count and egress are billed separately, and for
/// this app egress is already known to be the bigger of the two - see
/// SharedVendorsWatcher's doc comment ("~5.2KB avg x N vendors... read
/// count is cheap, egress bytes are the actual concern"). A doc-count-only
/// log cannot tell a 200-byte status doc from a 40KB vendor doc.
///
/// Sizing follows Firestore's own documented per-type storage sizes (string
/// = UTF-8 bytes + 1, number = 8, bool/null = 1, Timestamp = 8, GeoPoint =
/// 16, reference = path length + 1, map/array = sum of members, plus the
/// map key strings). That is deliberately an APPROXIMATION of what crosses
/// the wire, not an exact figure: real egress is protobuf-framed and may be
/// compressed, and gRPC/TLS overhead is not counted here. It is meant for
/// comparing labels against each other and spotting a heavy one, not for
/// reconciling to the last byte against a Cloud Billing line item.
int estimateFirestoreValueBytes(Object? value) {
  if (value == null) return 1;
  if (value is bool) return 1;
  if (value is num) return 8;
  if (value is String) return utf8.encode(value).length + 1;
  if (value is Timestamp || value is DateTime) return 8;
  if (value is GeoPoint) return 16;
  if (value is DocumentReference) return utf8.encode(value.path).length + 1;
  if (value is Blob) return value.bytes.length;
  if (value is Uint8List) return value.length;
  if (value is Iterable) {
    var total = 0;
    for (final v in value) {
      total += estimateFirestoreValueBytes(v);
    }
    return total;
  }
  if (value is Map) {
    var total = 0;
    value.forEach((k, v) {
      total += utf8.encode(k.toString()).length + 1;
      total += estimateFirestoreValueBytes(v);
    });
    return total;
  }
  // Unknown/unhandled type - counted as a small non-zero value rather than
  // 0, so it can never silently vanish from the totals.
  return 8;
}

/// Total estimated payload bytes across every document in a query snapshot.
int estimateSnapshotBytes(Iterable<DocumentSnapshot> docs) {
  var total = 0;
  for (final d in docs) {
    total += estimateFirestoreValueBytes(d.data());
  }
  return total;
}

// Diagnostic instrumentation only (originally added 2026-09-03 inside
// FirebaseHelper.dart, promoted to a shared file 2026-09-04 so every
// screen's own direct Firestore calls — not just the ones already routed
// through FireStoreUtils — can be measured the same way). Tracks whether
// each Firestore read was served from local cache or fetched from the
// server, and every Firestore write, with per-label counts, doc counts,
// and latency. Never changes query/write/cache/listener/business logic —
// import this file and swap .get()/.snapshots()/.set()/.update()/.delete()/
// .add() for the *Logged equivalents below, nothing else.
//
// debugPrint is used deliberately, not dart:developer's log() — log() only
// surfaces when a debugger/VM service is attached, so it's silently
// invisible in a release build with nothing attached (confirmed the hard
// way: the read logging was dead in a release APK until switched to
// debugPrint, which is what [STARTUP-PERF] and other release-visible logs
// in this codebase already use).

class FirestoreReadStats {
  static final Map<String, int> _serverCount = {};
  static final Map<String, int> _cacheCount = {};
  // Per-label doc/exists count, summed across every getLogged/snapshotsLogged
  // call for that label - this is what actually answers "how many documents
  // did this fetch", as opposed to _serverCount/_cacheCount which only count
  // how many *calls* happened. record() below is a plain map mutation, never
  // throttled the way debugPrint bursts are - see dumpSummary()'s doc comment.
  static final Map<String, int> _docCount = {};
  // A read that reports CACHE but took seconds to resolve did NOT come from a
  // fast local lookup - the SDK tried the server first and fell back to cache
  // when the slow network beat it. Google can still bill those server-side
  // queries, so a CACHE label is NOT proof the read was free. Confirmed
  // 2026-09-15: a cold start whose every label logged source=CACHE
  // (tookMs 9233-10088) coincided with a real, billed 199-document spike on
  // the project's own document/read_count metric. These are counted
  // separately so a summary can flag them instead of quietly reporting $0.
  static final Map<String, int> _slowCacheCount = {};
  static const int _slowCacheThresholdMs = 1000;

  // Per-label payload bytes (2026-09-19). Read COUNT and EGRESS are billed
  // separately by Google, and for this app egress has already been measured
  // as the bigger problem of the two: SharedVendorsWatcher's own doc comment
  // records the Home vendor listener at ~5.2KB average x N vendors as "the
  // dominant Home screen EGRESS cost... read count is cheap, egress bytes
  // are the actual concern". Counting documents alone cannot see that - a
  // 200-byte status doc and a 40KB vendor doc were both just "1". This
  // tracks the size side so a label's true cost is visible.
  static final Map<String, int> _byteCount = {};

  static void record(String label, bool fromCache,
      [int docCount = 1, int? tookMs, int bytes = 0]) {
    final map = fromCache ? _cacheCount : _serverCount;
    map[label] = (map[label] ?? 0) + 1;
    _docCount[label] = (_docCount[label] ?? 0) + docCount;
    _byteCount[label] = (_byteCount[label] ?? 0) + bytes;
    if (fromCache && tookMs != null && tookMs >= _slowCacheThresholdMs) {
      _slowCacheCount[label] = (_slowCacheCount[label] ?? 0) + 1;
    }
  }

  /// Zeroes every counter. Call this right before a cold-start sequence you
  /// want to measure in isolation (e.g. HomeScreen.initState) so a later
  /// dumpSummary() reflects only that screen's reads, not whatever ran
  /// during splash/login before it.
  static void reset() {
    _serverCount.clear();
    _cacheCount.clear();
    _docCount.clear();
    _slowCacheCount.clear();
    _byteCount.clear();
  }

  // 2026-09-15: confirmed live that a cold-start burst of many individual
  // [FirestoreRead]/[FirestoreListener] debugPrint lines can produce ZERO
  // visible output in the device's logcat buffer, despite Cloud Monitoring
  // proving the real reads happened (61 reads, real running process, no
  // matching log lines anywhere). The per-call counts above are unaffected -
  // they're synchronous map increments, not prints - so calling this ONCE,
  // well after the burst (a few seconds delay), turns N possibly-dropped
  // lines into a handful of lines with much better odds of surviving.
  /// Human-readable byte size, so a summary line reads "5.2KB" rather than
  /// "5324" - the whole point is spotting a heavy label at a glance.
  static String fmtBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)}MB';
  }

  static void dumpSummary() {
    final labels = {..._serverCount.keys, ..._cacheCount.keys}.toList()..sort();
    final totalDocs = _docCount.values.fold<int>(0, (a, b) => a + b);
    final totalSlowCache = _slowCacheCount.values.fold<int>(0, (a, b) => a + b);
    final totalBytes = _byteCount.values.fold<int>(0, (a, b) => a + b);
    // Server-sourced bytes only - the ones that actually crossed the network
    // and therefore actually cost egress. A cache-served read transfers
    // nothing, so lumping it into the egress figure would overstate cost.
    final serverBytes = _byteCount.entries
        .where((e) => (_serverCount[e.key] ?? 0) > 0)
        .fold<int>(0, (a, e) => a + e.value);
    debugPrint('[FirestoreReadStats] ===== summary (${DateTime.now().toIso8601String()}) - '
        'total documents read across all labels: $totalDocs, '
        'payload ${fmtBytes(totalBytes)} (of which labels that hit the server: '
        '${fmtBytes(serverBytes)}) =====');
    for (final l in labels) {
      final slow = _slowCacheCount[l] ?? 0;
      final bytes = _byteCount[l] ?? 0;
      final docs = _docCount[l] ?? 0;
      // Average per document makes a fat-document label obvious even when
      // its read count looks harmless (e.g. 1 read x 40KB).
      final avg = docs > 0 ? ' avg=${fmtBytes(bytes ~/ docs)}/doc' : '';
      debugPrint('[FirestoreReadStats] $l -> server=${_serverCount[l] ?? 0} cache=${_cacheCount[l] ?? 0} '
          'docs=$docs bytes=${fmtBytes(bytes)}$avg'
          '${slow > 0 ? " SLOW-CACHE=$slow(may still be billed)" : ""}');
    }
    if (totalSlowCache > 0) {
      debugPrint('[FirestoreReadStats] WARNING: $totalSlowCache read(s) reported CACHE but took '
          '>${_slowCacheThresholdMs}ms - the SDK likely hit the server first and fell back to '
          'cache on a slow network. Do NOT treat those as free; cross-check the project\'s '
          'document/read_count metric for this window.');
    }
  }
}

class FirestoreWriteStats {
  static final Map<String, int> _count = {};

  static void record(String label) {
    _count[label] = (_count[label] ?? 0) + 1;
  }

  static void dumpSummary() {
    final labels = _count.keys.toList()..sort();
    debugPrint('[FirestoreWriteStats] ===== session summary (${DateTime.now().toIso8601String()}) =====');
    for (final l in labels) {
      debugPrint('[FirestoreWriteStats] $l -> ${_count[l]} writes');
    }
  }
}

/// Schedules a one-off aggregated read summary dump [delay] after being
/// called - drop this into any important screen's initState (see
/// HomeScreen.dart for the original) so a burst of individual per-fetch
/// [FirestoreRead]/[FirestoreListener] lines - which can get silently
/// dropped by logcat when many fire close together, confirmed live
/// 2026-09-15 - still leaves behind one small, high-survival-odds summary
/// line with the exact per-label document counts.
///
/// [screenLabel] only labels the header line so multiple screens' dumps are
/// easy to tell apart in one logcat capture. This does NOT call
/// FirestoreReadStats.reset() - unlike HomeScreen (the app's first real
/// screen after login, safe to zero everything) most screens can be reached
/// while another screen is still alive underneath, so resetting here would
/// erase that other screen's own not-yet-dumped counts. Every fetch label in
/// this codebase already carries its own screen prefix by convention (e.g.
/// 'CartScreen.something', 'PurchaseCompletionListener:vendor_orders'), so
/// look for this screen's own labels in the cumulative dump rather than
/// expecting an isolated total.
///
/// Pass [isStillActive] (typically `() => mounted`) to skip the dump if the
/// screen was already closed by the time [delay] elapses.
///
/// Dumps TWICE (at [delay], then again at [lateDelay]) because a single early
/// dump is not enough: measured on a real device 2026-09-15, cold-start
/// .get() calls took 11-12 SECONDS to resolve on a slow network, so a 10s
/// dump caught only 2 of 13 labels. The early dump still has value (it shows
/// what resolved fast); the late one is the complete picture.
void scheduleFirestoreReadDump(String screenLabel,
    {Duration delay = const Duration(seconds: 15),
    Duration lateDelay = const Duration(seconds: 45),
    bool Function()? isStillActive}) {
  void dump(Duration after) {
    Future.delayed(after, () {
      if (isStillActive != null && !isStillActive()) return;
      debugPrint('[FirestoreReadStats] ===== $screenLabel +${after.inSeconds}s summary follows =====');
      FirestoreReadStats.dumpSummary();
      // 2026-09-15: FirestoreWriteStats.dumpSummary() existed but was never
      // called anywhere in the app - every write was individually logged
      // (`[FirestoreWrite] ...`) but never summarized, so there was no way to
      // see a screen's total write cost the way the read summary already
      // shows total read cost. Same dump cadence as reads, same reasoning
      // (survives a burst better than N individual lines).
      debugPrint('[FirestoreWriteStats] ===== $screenLabel +${after.inSeconds}s summary follows =====');
      FirestoreWriteStats.dumpSummary();
    });
  }

  dump(delay);
  dump(lateDelay);
}

extension LoggedQuery<T> on Query<T> {
  Future<QuerySnapshot<T>> getLogged(String label, [GetOptions? options]) async {
    final sw = Stopwatch()..start();
    final snap = options == null ? await get() : await get(options);
    sw.stop();
    final fromCache = snap.metadata.isFromCache;
    final bytes = estimateSnapshotBytes(snap.docs);
    FirestoreReadStats.record(
        label, fromCache, snap.docs.length, sw.elapsedMilliseconds, bytes);
    debugPrint('[FirestoreRead] $label source=${fromCache ? "CACHE" : "SERVER"} '
        'docs=${snap.docs.length} bytes=${FirestoreReadStats.fmtBytes(bytes)} '
        'tookMs=${sw.elapsedMilliseconds} '
        'at=${DateTime.now().toIso8601String()}');
    return snap;
  }

  Stream<QuerySnapshot<T>> snapshotsLogged(String label) {
    return snapshots().map((snap) {
      final fromCache = snap.metadata.isFromCache;
      final bytes = estimateSnapshotBytes(snap.docs);
      FirestoreReadStats.record(label, fromCache, snap.docs.length, null, bytes);
      debugPrint('[FirestoreListener] $label source=${fromCache ? "CACHE" : "SERVER"} '
          'docs=${snap.docs.length} bytes=${FirestoreReadStats.fmtBytes(bytes)} '
          'at=${DateTime.now().toIso8601String()}');
      return snap;
    });
  }
}

extension LoggedDocRef<T> on DocumentReference<T> {
  Future<DocumentSnapshot<T>> getLogged(String label) async {
    final sw = Stopwatch()..start();
    final snap = await get();
    sw.stop();
    final fromCache = snap.metadata.isFromCache;
    final bytes = estimateFirestoreValueBytes(snap.data());
    FirestoreReadStats.record(label, fromCache, 1, sw.elapsedMilliseconds, bytes);
    debugPrint('[FirestoreRead] $label source=${fromCache ? "CACHE" : "SERVER"} '
        'exists=${snap.exists} bytes=${FirestoreReadStats.fmtBytes(bytes)} '
        'tookMs=${sw.elapsedMilliseconds} '
        'at=${DateTime.now().toIso8601String()}');
    return snap;
  }

  Stream<DocumentSnapshot<T>> snapshotsLogged(String label) {
    return snapshots().map((snap) {
      final fromCache = snap.metadata.isFromCache;
      final bytes = estimateFirestoreValueBytes(snap.data());
      FirestoreReadStats.record(label, fromCache, 1, null, bytes);
      debugPrint('[FirestoreListener] $label source=${fromCache ? "CACHE" : "SERVER"} '
          'exists=${snap.exists} bytes=${FirestoreReadStats.fmtBytes(bytes)} '
          'at=${DateTime.now().toIso8601String()}');
      return snap;
    });
  }

  Future<void> setLogged(T data, String label, [SetOptions? options]) async {
    final sw = Stopwatch()..start();
    options == null ? await set(data) : await set(data, options);
    sw.stop();
    FirestoreWriteStats.record(label);
    debugPrint('[FirestoreWrite] $label op=SET tookMs=${sw.elapsedMilliseconds} '
        'at=${DateTime.now().toIso8601String()}');
  }

  Future<void> updateLogged(Map<Object, Object?> data, String label) async {
    final sw = Stopwatch()..start();
    await update(data);
    sw.stop();
    FirestoreWriteStats.record(label);
    debugPrint('[FirestoreWrite] $label op=UPDATE tookMs=${sw.elapsedMilliseconds} '
        'at=${DateTime.now().toIso8601String()}');
  }

  Future<void> deleteLogged(String label) async {
    final sw = Stopwatch()..start();
    await delete();
    sw.stop();
    FirestoreWriteStats.record(label);
    debugPrint('[FirestoreWrite] $label op=DELETE tookMs=${sw.elapsedMilliseconds} '
        'at=${DateTime.now().toIso8601String()}');
  }
}

extension LoggedCollectionAdd<T> on CollectionReference<T> {
  Future<DocumentReference<T>> addLogged(T data, String label) async {
    final sw = Stopwatch()..start();
    final ref = await add(data);
    sw.stop();
    FirestoreWriteStats.record(label);
    debugPrint('[FirestoreWrite] $label op=ADD tookMs=${sw.elapsedMilliseconds} '
        'at=${DateTime.now().toIso8601String()}');
    return ref;
  }
}

/// Transaction reads (2026-09-19). Until now these were the single largest
/// blind spot left in this whole read-cost audit: `tx.get()` does NOT go
/// through LoggedQuery/LoggedDocRef above, so all 7 transaction reads in
/// this app (story-view dedupe, per-line-item stock decrement, the three
/// reads inside reserveBookingCapacity, releaseBookingCapacity, bill-pay
/// expiry) were real, billed reads with zero trace in FirestoreReadStats.
///
/// Two things make these worth logging more than an ordinary read, not less:
///
///  1. A transaction read can NEVER be served free from the local cache -
///     that's the whole point of a transaction, it must see authoritative
///     server state. So unlike a `.get()` (where a CACHE label at least
///     *might* mean $0), every one of these is a guaranteed billed read.
///     The fromCache flag is still logged rather than hardcoded, so if the
///     SDK ever reports otherwise that shows up instead of being masked.
///
///  2. Firestore RETRIES a transaction whose callback raced a conflicting
///     write, re-running the whole callback - and re-billing every read in
///     it. Because this records per call rather than per transaction, a
///     retried transaction correctly shows up as 2x/3x reads. That is the
///     real billed cost, and it was previously invisible; a count here
///     higher than the number of transactions actually attempted is the
///     signal, not a bug.
extension LoggedTransactionGet on Transaction {
  Future<DocumentSnapshot<T>> getLogged<T>(
      DocumentReference<T> ref, String label) async {
    final sw = Stopwatch()..start();
    final snap = await get(ref);
    sw.stop();
    final fromCache = snap.metadata.isFromCache;
    final bytes = estimateFirestoreValueBytes(snap.data());
    FirestoreReadStats.record(label, fromCache, 1, sw.elapsedMilliseconds, bytes);
    debugPrint('[FirestoreRead] $label source=${fromCache ? "CACHE" : "SERVER"} '
        'exists=${snap.exists} bytes=${FirestoreReadStats.fmtBytes(bytes)} '
        'tookMs=${sw.elapsedMilliseconds} '
        'at=${DateTime.now().toIso8601String()}');
    return snap;
  }
}
