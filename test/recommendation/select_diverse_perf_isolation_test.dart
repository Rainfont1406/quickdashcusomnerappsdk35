// Isolates _selectDiverse's final rank-order re-sort cost specifically.
// Run this file TWICE: once with the fix's two lines present (current state
// - "new"), once with them temporarily commented out ("old") - see the audit
// procedure notes in performance_benchmark_test.dart. businessContext source
// is held constant (always on) in both runs so this measures ONLY the
// re-sort's marginal cost, not conflated with the Business Context source.
import 'package:emartconsumer/services/recommendation/recommendation_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'vendor_dataset.dart';

double _benchMs(void Function() fn, {int warmup = 20, required int iterations}) {
  for (var i = 0; i < warmup; i++) fn();
  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) fn();
  sw.stop();
  return sw.elapsedMicroseconds / iterations / 1000.0;
}

void main() {
  test('Isolation benchmark: recommendForYou (businessContext held constant)', () {
    final typical = buildVendorDataset().firstWhere((f) => f.label == 'Medium menu (40 products)');
    final typicalSales = {for (final p in typical.products.take(10)) p.id: (typical.products.indexOf(p) % 5) + 1};
    final typicalCtx = buildCtx(
      vendor: typical.vendor, products: typical.products, behavior: mixedPreferenceCustomer(),
      sales30: typicalSales, businessTypeProfiles: fullBusinessTypeProfiles, cuisineCategoryAffinity: fullCuisineAffinity,
    );
    final typicalMs = _benchMs(
      () => RecommendationEngine.recommendForYou(typicalCtx, limit: RecommendationEngine.sectionLimitFor(typicalCtx)),
      iterations: 300,
    );
    // ignore: avoid_print
    print('recommendForYou [typical (~40 products)] = ${typicalMs.toStringAsFixed(4)}ms');

    final large = buildVendorDataset().firstWhere((f) => f.products.length == 500);
    final largeSales = {for (var i = 0; i < large.products.length; i += 3) large.products[i].id: (i % 20) + 1};
    final largeCtx = buildCtx(
      vendor: large.vendor, products: large.products, behavior: mixedPreferenceCustomer(),
      sales30: largeSales, businessTypeProfiles: fullBusinessTypeProfiles, cuisineCategoryAffinity: fullCuisineAffinity,
    );
    final largeMs = _benchMs(
      () => RecommendationEngine.recommendForYou(largeCtx, limit: RecommendationEngine.sectionLimitFor(largeCtx)),
      iterations: 30,
    );
    // ignore: avoid_print
    print('recommendForYou [large (500 products)] = ${largeMs.toStringAsFixed(4)}ms');

    expect(true, isTrue);
  });
}
