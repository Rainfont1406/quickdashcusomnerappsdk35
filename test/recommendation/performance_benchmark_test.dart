// Before/after performance benchmark for the three additions under review:
//   1. Business Context as a computeMergedScores source ('businessContext')
//   2. pairingContextScore + the pairingContextScores map build in Pairs Well With
//   3. _selectDiverse's final rank-order re-sort (the badge-consistency fix)
//
// (1) and (2) are measured with ZERO engine-file changes: computeMergedScores/
// recommendForYou already accept an optional `sources` map, so "old" is
// reproduced by passing RecommendationEngine.defaultSources with
// 'businessContext' removed - the real production code path, not a mock.
// (3) has no such hook (it's an unconditional final step inside a private
// function), so isolating its cost requires briefly commenting out the two
// added lines in recommendation_engine.dart, measuring, then restoring them -
// exactly the same reversible procedure used for the fuzz-test sanity check
// earlier in this audit. The restore is verified via a fresh dart analyze
// pass and a full test/recommendation/ re-run at the end.
//
// Methodology: 30-iteration JIT warmup (discarded) + 300 measured iterations
// per call, reporting mean ms/call. This is a Dart VM (`flutter test`)
// benchmark, not real-device timing - use the DELTA (added cost), not the
// absolute numbers, as the actionable signal.
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/services/recommendation/behavior_summary_snapshot.dart';
import 'package:emartconsumer/services/recommendation/recommendation_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'vendor_dataset.dart';

double _benchMs(void Function() fn, {int warmup = 30, int iterations = 300}) {
  for (var i = 0; i < warmup; i++) fn();
  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) fn();
  sw.stop();
  return sw.elapsedMicroseconds / iterations / 1000.0;
}

void _report(String label, double oldMs, double newMs) {
  final delta = newMs - oldMs;
  final pct = oldMs > 0 ? (delta / oldMs * 100) : 0;
  // ignore: avoid_print
  print('${label.padRight(46)} old=${oldMs.toStringAsFixed(4)}ms  '
      'new=${newMs.toStringAsFixed(4)}ms  '
      'delta=${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(4)}ms '
      '(${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%)');
}

RestaurantRecommendationContext _typicalCtx() {
  final f = buildVendorDataset().firstWhere((f) => f.label == 'Medium menu (40 products)');
  final sales = {for (final p in f.products.take(10)) p.id: (f.products.indexOf(p) % 5) + 1};
  return buildCtx(
    vendor: f.vendor,
    products: f.products,
    behavior: mixedPreferenceCustomer(),
    sales30: sales,
    businessTypeProfiles: fullBusinessTypeProfiles,
    cuisineCategoryAffinity: fullCuisineAffinity,
  );
}

RestaurantRecommendationContext _largeCtx() {
  final f = buildVendorDataset().firstWhere((f) => f.products.length == 500);
  final sales = {for (var i = 0; i < f.products.length; i += 3) f.products[i].id: (i % 20) + 1};
  return buildCtx(
    vendor: f.vendor,
    products: f.products,
    behavior: mixedPreferenceCustomer(),
    sales30: sales,
    businessTypeProfiles: fullBusinessTypeProfiles,
    cuisineCategoryAffinity: fullCuisineAffinity,
  );
}

void main() {
  final noBusinessContextSources = Map<String, CandidateSource>.of(RecommendationEngine.defaultSources)
    ..remove('businessContext');

  test('Benchmark: computeMergedScores - with vs without the Business Context source', () {
    for (final entry in {'typical (~40 products)': _typicalCtx(), 'large (500 products)': _largeCtx()}.entries) {
      final ctx = entry.value;
      final oldMs = _benchMs(() => RecommendationEngine.computeMergedScores(ctx, sources: noBusinessContextSources));
      final newMs = _benchMs(() => RecommendationEngine.computeMergedScores(ctx));
      _report('computeMergedScores [${entry.key}]', oldMs, newMs);
    }
    expect(true, isTrue); // this test's purpose is the printed report, not an assertion
  });

  test('Benchmark: recommendForYou - with vs without the Business Context source', () {
    for (final entry in {'typical (~40 products)': _typicalCtx(), 'large (500 products)': _largeCtx()}.entries) {
      final ctx = entry.value;
      final limit = RecommendationEngine.sectionLimitFor(ctx);
      final oldMs = _benchMs(() => RecommendationEngine.recommendForYou(ctx, limit: limit, sources: noBusinessContextSources));
      final newMs = _benchMs(() => RecommendationEngine.recommendForYou(ctx, limit: limit));
      _report('recommendForYou [${entry.key}]', oldMs, newMs);
    }
    expect(true, isTrue);
  });

  test('Benchmark: pairingContextScore - map-build cost for Pairs Well With', () {
    for (final entry in {'typical (~40 products)': _typicalCtx(), 'large (500 products)': _largeCtx()}.entries) {
      final ctx = entry.value;
      final trigger = ctx.allProducts.first;
      final pool = ctx.allProducts.skip(1).toList();
      // "old" = this map was never computed at all (the parameter didn't exist) - 0ms baseline.
      final newMs = _benchMs(() {
        // ignore: unused_local_variable
        final m = {for (final p in pool) p.id: RecommendationEngine.pairingContextScore(p, trigger, ctx)};
      });
      _report('pairingContextScore map build [${entry.key}, ${pool.length} candidates]', 0.0, newMs);
    }
    expect(true, isTrue);
  });

  test('Benchmark: fillPairsWellWith - with vs without a populated pairingContextScores map', () {
    for (final entry in {'typical (~40 products)': _typicalCtx(), 'large (500 products)': _largeCtx()}.entries) {
      final ctx = entry.value;
      final trigger = ctx.allProducts.first;
      final pool = ctx.allProducts.skip(1).toList();
      final pairingScores = {for (final p in pool) p.id: RecommendationEngine.pairingContextScore(p, trigger, ctx)};
      final merged = RecommendationEngine.normalizedMergedScores(ctx);
      final pref = RecommendationEngine.scoreBySource(ctx, 'preference');
      final best = RecommendationEngine.scoreBySource(ctx, 'bestSeller');
      final limit = RecommendationEngine.pairingSectionLimitFor(ctx);

      final oldMs = _benchMs(() => RecommendationEngine.fillPairsWellWith(
            vendorConfigured: const [],
            candidatePool: pool,
            mergedScores: merged,
            preferenceScores: pref,
            bestSellerScores: best,
            crossSellFrequency: ctx.crossSellFrequency,
            // pairingContextScores omitted - defaults to {} (the pre-feature shape)
            maxItems: limit,
          ));
      final newMs = _benchMs(() => RecommendationEngine.fillPairsWellWith(
            vendorConfigured: const [],
            candidatePool: pool,
            mergedScores: merged,
            preferenceScores: pref,
            bestSellerScores: best,
            crossSellFrequency: ctx.crossSellFrequency,
            pairingContextScores: pairingScores,
            maxItems: limit,
          ));
      _report('fillPairsWellWith (map already built) [${entry.key}]', oldMs, newMs);
    }
    expect(true, isTrue);
  });
}
