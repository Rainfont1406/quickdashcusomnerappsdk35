import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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

  static void record(String label, bool fromCache) {
    final map = fromCache ? _cacheCount : _serverCount;
    map[label] = (map[label] ?? 0) + 1;
  }

  static void dumpSummary() {
    final labels = {..._serverCount.keys, ..._cacheCount.keys}.toList()..sort();
    debugPrint('[FirestoreReadStats] ===== session summary (${DateTime.now().toIso8601String()}) =====');
    for (final l in labels) {
      debugPrint('[FirestoreReadStats] $l -> server=${_serverCount[l] ?? 0} cache=${_cacheCount[l] ?? 0}');
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

extension LoggedQuery<T> on Query<T> {
  Future<QuerySnapshot<T>> getLogged(String label, [GetOptions? options]) async {
    final sw = Stopwatch()..start();
    final snap = options == null ? await get() : await get(options);
    sw.stop();
    final fromCache = snap.metadata.isFromCache;
    FirestoreReadStats.record(label, fromCache);
    debugPrint('[FirestoreRead] $label source=${fromCache ? "CACHE" : "SERVER"} '
        'docs=${snap.docs.length} tookMs=${sw.elapsedMilliseconds} '
        'at=${DateTime.now().toIso8601String()}');
    return snap;
  }

  Stream<QuerySnapshot<T>> snapshotsLogged(String label) {
    return snapshots().map((snap) {
      final fromCache = snap.metadata.isFromCache;
      FirestoreReadStats.record(label, fromCache);
      debugPrint('[FirestoreListener] $label source=${fromCache ? "CACHE" : "SERVER"} '
          'docs=${snap.docs.length} at=${DateTime.now().toIso8601String()}');
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
    FirestoreReadStats.record(label, fromCache);
    debugPrint('[FirestoreRead] $label source=${fromCache ? "CACHE" : "SERVER"} '
        'exists=${snap.exists} tookMs=${sw.elapsedMilliseconds} '
        'at=${DateTime.now().toIso8601String()}');
    return snap;
  }

  Stream<DocumentSnapshot<T>> snapshotsLogged(String label) {
    return snapshots().map((snap) {
      final fromCache = snap.metadata.isFromCache;
      FirestoreReadStats.record(label, fromCache);
      debugPrint('[FirestoreListener] $label source=${fromCache ? "CACHE" : "SERVER"} '
          'exists=${snap.exists} at=${DateTime.now().toIso8601String()}');
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
