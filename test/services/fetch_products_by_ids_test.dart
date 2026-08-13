// Regression tests for FireStoreUtils.dedupeAndChunkIds (2026-08-05) - the
// pure dedup+chunk logic behind fetchProductsByIds, which replaced N
// individual getProductByID() calls (one per cart line) with a batched
// `where('id', whereIn: ...)` query. This is the only part of the change
// testable without a live/mocked Firestore, which this project has no
// infrastructure for (no fake_cloud_firestore/mockito dependency).
//
// The other regression scenarios asked for when this was implemented -
// deleted products, unpublished products, out-of-stock items, changed
// prices - are NOT exercised here because they're unaffected by this
// change: fetchProductsByIds only changes HOW products are fetched (one
// batched query instead of N), never what CartScreen._validateCart() does
// with the result. A deleted product still surfaces as a missing map entry
// (mapped back to null exactly like getProductByID's old not-found-throws-
// caught-as-null behavior); publish/quantity/price fields on a successfully
// fetched ProductModel are read by _validateCart's existing, completely
// untouched processing loop. Verifying those end-to-end needs either a live
// Firestore-backed run of the app or a mocking layer neither of which is
// available from this environment.
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dedupeAndChunkIds', () {
    test('empty input returns no chunks', () {
      expect(FireStoreUtils.dedupeAndChunkIds([]), isEmpty);
    });

    test('a single id returns one chunk with one id', () {
      final chunks = FireStoreUtils.dedupeAndChunkIds(['p1']);
      expect(chunks, [
        ['p1']
      ]);
    });

    test('variants: two cart lines sharing the same base product id are deduped to one', () {
      // e.g. "Pizza - Large" (p1~v1) and "Pizza - Medium" (p1~v2) both
      // resolve to base id p1 before being passed in here.
      final chunks = FireStoreUtils.dedupeAndChunkIds(['p1', 'p1']);
      expect(chunks.expand((c) => c).toList(), ['p1']);
    });

    test('mixed cart: distinct products plus a repeated variant base id dedupes only the repeat', () {
      final chunks =
          FireStoreUtils.dedupeAndChunkIds(['p1', 'p2', 'p1', 'p3', 'p2']);
      final flat = chunks.expand((c) => c).toSet();
      expect(flat, {'p1', 'p2', 'p3'});
      expect(chunks.expand((c) => c).length, 3); // no duplicates survive
    });

    test('exactly chunkSize distinct ids fit in a single chunk', () {
      final ids = List.generate(30, (i) => 'p$i');
      final chunks = FireStoreUtils.dedupeAndChunkIds(ids, chunkSize: 30);
      expect(chunks.length, 1);
      expect(chunks.first.length, 30);
    });

    test('chunkSize + 1 distinct ids splits into two chunks, none exceeding chunkSize', () {
      final ids = List.generate(31, (i) => 'p$i');
      final chunks = FireStoreUtils.dedupeAndChunkIds(ids, chunkSize: 30);
      expect(chunks.length, 2);
      expect(chunks[0].length, 30);
      expect(chunks[1].length, 1);
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(30));
      }
    });

    test('a large cart (91 distinct ids) chunks into ceil(91/30) = 4 groups, all ids preserved exactly once', () {
      final ids = List.generate(91, (i) => 'p$i');
      final chunks = FireStoreUtils.dedupeAndChunkIds(ids, chunkSize: 30);
      expect(chunks.length, 4);
      expect(chunks.map((c) => c.length).toList(), [30, 30, 30, 1]);
      final flat = chunks.expand((c) => c).toSet();
      expect(flat.length, 91);
      expect(flat, ids.toSet());
    });

    test('duplicates spread across what would otherwise cross a chunk boundary still dedupe before chunking, not after', () {
      // 35 distinct ids, each repeated once (70 raw entries) - if dedup ran
      // AFTER chunking instead of before, this could produce wrong/uneven
      // chunk boundaries; asserting the total distinct count and chunk
      // shape together catches that ordering bug.
      final raw = <String>[];
      for (var i = 0; i < 35; i++) {
        raw.add('p$i');
        raw.add('p$i');
      }
      final chunks = FireStoreUtils.dedupeAndChunkIds(raw, chunkSize: 30);
      expect(chunks.length, 2);
      expect(chunks[0].length, 30);
      expect(chunks[1].length, 5);
      final flat = chunks.expand((c) => c).toSet();
      expect(flat.length, 35);
    });
  });
}
