// Guards against exactly the bug class found and fixed 2026-09-19:
// CategoryDetailsScreen's raw GeoFirestore .within() query fanned out into
// 9 live Firestore listeners that were completely invisible to the app's
// own read-cost logging (FirestoreReadStats) - confirmed live to cost real,
// billed reads (up to ~179 in one screen visit for an identical pattern on
// the old DineInScreen) with zero matching lines in the app's own log.
// Several other raw .get()/.snapshots() call sites were found the same way
// (main.dart's warm-up read, on_boarding_controller.dart, behavior_tracker's
// monthly prune, two chat inbox screens' pagination).
//
// Every one of those got fixed by routing through firestore_instrumentation
// .dart's getLogged()/snapshotsLogged() extensions instead of the SDK's own
// .get()/.snapshots(). This script is the durable guard against the same
// class of bug creeping back in via a future raw call site the audit didn't
// (and a later one won't) manually sweep for.
//
// Run: dart run tool/check_unlogged_firestore_reads.dart
// Exits non-zero (and lists every offending line) if any raw Firestore
// .get()/.snapshots() call is found outside the instrumentation file itself.
//
// This is deliberately a plain text/regex scan, not a custom_lint analyzer
// plugin - custom_lint would add a new dependency to an already tightly
// version-pinned pubspec (confirmed 218 packages already behind their
// latest compatible versions), risking a resolution break for a project
// that already has enough of that fragility. A script has no such risk.

import 'dart:io';

// Call-site hints (a Firestore chain in the surrounding lines) PLUS
// Firestore type names. The type names were added 2026-09-19 after this
// script was caught missing a real unlogged listener: geoflutterfire's
// vendored `_createStream(Query<T> ref) => ref.snapshots()` has no
// .collection()/firestore. anywhere near it - the receiver is a plain
// local named `ref`, and the only Firestore tell is the `Query<T>` in the
// signature. A hint list that only knows about fluent chains cannot see
// helper methods that take an already-built Query/DocumentReference.
final RegExp _firestoreHint = RegExp(
  r'\.collection\(|firestore\.|FirebaseFirestore|\.doc\(|'
  r'\bQuery<|\bQuerySnapshot|\bCollectionReference|\bDocumentReference|'
  r'\bDocumentSnapshot',
);
final RegExp _rawGet = RegExp(r'\.get\(\)');

// `\.snapshots\(` not `\.snapshots\(\)` - the empty-parens version missed
// `.snapshots(includeMetadataChanges: true)` entirely (found 2026-09-19 in
// firestore_pagination.dart's live-watcher listener, a real listener the
// first version of this script could not see).
final RegExp _rawSnapshots = RegExp(r'\.snapshots\(');

// Transaction reads (2026-09-19). These take an argument (the DocumentRef),
// so the no-arg _rawGet pattern above never matched them - which is exactly
// how all 7 of this app's transaction reads stayed invisible to the audit
// until they were found by hand. A transaction read can never be a free
// cache hit and is re-billed on every retry, so it matters more than an
// ordinary read, not less. Matched separately, and NOT window-gated on a
// Firestore hint below, since `tx.`/`transaction.` is already unambiguous.
final RegExp _rawTxGet = RegExp(r'\b(tx|txn|transaction)\.get\(');

// Files that legitimately call the SDK's raw read APIs.
const _allowlist = {
  // Defines the getLogged()/snapshotsLogged()/tx.getLogged() wrappers
  // themselves, so it necessarily calls the raw APIs internally.
  'lib/services/firestore_instrumentation.dart',

  // Its own always-on wrapper: both of this widget's listeners record into
  // FirestoreReadStats unconditionally, because `logLabel` is a REQUIRED
  // constructor param as of 2026-09-19 (it used to be optional, which is
  // exactly how two chat inbox screens' reads went unlogged for as long as
  // they existed). If logLabel is ever made optional again, remove this
  // allowlist entry - the guarantee it rests on would be gone.
  'lib/widget/firebase_pagination/src/firestore_pagination.dart',

  // Vendored third-party geoflutterfire, not code we hand-maintain. Its
  // ref.snapshots() is genuinely unlogged, but it is UNREACHABLE as of
  // 2026-09-19: its only entry points were FireStoreUtils.getAllStores(),
  // getVendorsByCuisineID() and getNearestDriver(), and all three now have
  // zero callers (Home/DineIn/MapView/ViewAllPopularStores migrated to
  // SharedVendorsWatcher 2026-09-11, CategoryDetailsScreen 2026-09-19).
  // REVIVAL RISK: giving any of those three methods a caller again silently
  // reopens an unlogged, 9-listener-per-call geo read path - audit the
  // caller, don't trust this allowlist to mean "free".
  'lib/widget/geoflutterfire/src/collection/base.dart',
};

void main() {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stderr.writeln('tool/check_unlogged_firestore_reads.dart must be run '
        'from the project root (lib/ not found in current directory).');
    exit(2);
  }

  final violations = <String>[];

  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final relPath = entity.path.replaceAll('\\', '/');
    if (_allowlist.any((f) => relPath.endsWith(f))) continue;

    final lines = entity.readAsLinesSync();
    var inBlockComment = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();

      // Track /* ... */ block comments across lines - a single-line skip
      // isn't enough (confirmed needed: FirebaseHelper.dart has a raw,
      // dead .get() call sitting inside a multi-line /* */ block).
      // Deliberately simple (no nested-comment handling - Dart doesn't
      // nest /* */ anyway) rather than a full lexer, matching this
      // script's plain-text-scan scope.
      if (inBlockComment) {
        if (line.contains('*/')) inBlockComment = false;
        continue;
      }
      if (trimmed.startsWith('/*') && !line.contains('*/')) {
        inBlockComment = true;
        continue;
      }
      if (trimmed.startsWith('//') || trimmed.startsWith('/*')) continue;

      // Transaction reads are self-identifying - flag immediately, no
      // surrounding-Firestore-context check needed.
      if (_rawTxGet.hasMatch(line)) {
        violations.add('$relPath:${i + 1}: ${line.trim()}');
        continue;
      }

      if (!_rawGet.hasMatch(line) && !_rawSnapshots.hasMatch(line)) continue;

      // A genuine Firestore chain reads .collection(...)/.doc(...)/
      // firestore. somewhere on this line or a few lines above it (fluent
      // chains are usually split across lines) - this window keeps the
      // check from flagging unrelated .get()/.snapshots() calls (GetX's
      // Get., SharedPreferences, Drift's local db, dart:core Map.get, etc).
      final windowStart = (i - 6).clamp(0, lines.length);
      final window = lines.sublist(windowStart, i + 1).join('\n');
      if (_firestoreHint.hasMatch(window)) {
        violations.add('$relPath:${i + 1}: ${line.trim()}');
      }
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln(
        'Found ${violations.length} raw Firestore .get()/.snapshots() call(s) '
        'not routed through getLogged()/snapshotsLogged() '
        '(see lib/services/firestore_instrumentation.dart):\n');
    for (final v in violations) {
      stderr.writeln('  $v');
    }
    stderr.writeln('\nFix: use .getLogged(\'YourLabel\') instead of .get(), '
        '.snapshotsLogged(\'YourLabel\') instead of .snapshots(), or '
        'tx.getLogged(ref, \'YourLabel\') instead of tx.get(ref), so this read '
        'shows up in FirestoreReadStats and the app\'s read-cost logs.');
    exit(1);
  }

  stdout.writeln('OK: no unwrapped Firestore .get()/.snapshots() calls found.');
}
