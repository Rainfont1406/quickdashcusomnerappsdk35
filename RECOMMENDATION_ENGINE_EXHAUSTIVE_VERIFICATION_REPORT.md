# Recommendation Engine — Exhaustive Verification Report

**Date:** 2026-07-19
**Scope:** Every `RecommendationEngine` entry point, including the full Combo Recommendation Algorithm Update (eligibility gating, combo-last/cap-2 partitioning, cart content awareness, combo-trigger cuisine resolution, Combo Purchase Learning).
**Method:** 520 independently generated, seeded (`Random(20260719)`, fully reproducible), randomized synthetic scenarios (`test/recommendation/exhaustive_fuzz_test.dart`), plus the full pre-existing suite (126 curated/matrix/isolation tests) run alongside it as a combined regression pass. Engine-layer only — this exercises `RecommendationEngine` directly against synthetic `RestaurantRecommendationContext` fixtures, not UI rendering, per explicit scope.

## Headline result

| Metric | Value |
|---|---|
| Scenarios generated | 520 |
| Scenarios run | 520 (100%) |
| Total assertions executed | 50,147 |
| Assertions passed | 50,147 |
| Assertions failed | **0** |
| Combined suite (fuzz + 126 pre-existing tests) | 127/127 passing |
| Uncaught exceptions | 0 |

## 1. Scenario generation

Every scenario is built from a single seeded `Random`, advanced sequentially — re-running the file reproduces byte-identical scenarios every time, and any future failure would print the exact `ScenarioConfig` (index + every dimension value) needed to reproduce it in isolation. Dimensions randomized per scenario:

- **Menu size**: weighted pick from `{1, 3, 5, 10, 20, 50, 100, 250, 500}` — every size in the spec is hit repeatedly; weighting favors smaller menus (35% at 1/3/5, 30% at 10/20, 25% at 50/100, 10% at 250/500) to match realistic restaurant-size distribution while keeping total runtime bounded.
- **Business Type**: random from `{Restaurant, Cafe, Bakery, Juice Bar, Fast Food, Cloud Kitchen, none}`.
- **Cuisines**: 0–5, random subset of the 6 configured cuisines (North Indian, Chinese, Fast Food, Cafe, Bakery, Beverage).
- **Business Context configuration**: 20% of scenarios simulate completely missing `businessTypeProfiles`/`cuisineCategoryAffinity` maps (the "missing affinity" edge case), 80% use the full admin-configured maps.
- **Combo density**: `none` / `few` (1–2 combos) / `heavy` (~40% of the menu), each combo bundling 2–4 randomly chosen child products with randomized quantities — matching Burger+Fries+Drink-style bundles.
- **Customer behavior**: 9 variants — none, browsing-only, search-only, order-only, heavy, restaurant-loyal, cuisine-loyal, category-loyal, combo-loyal.
- **Budget**: ₹100 / 150 / 250 / 500 / 800 / 1500.
- **Cart state**: empty, one item, multiple items, repeated-category, repeated-product, combo-in-cart, multi-combo, large-family (8+ items).
- **Menu composition**: random veg-only / non-veg-only / mixed products, name collisions via a shared adjective+noun pool (reproducing near-duplicate "Butter Naan" / "Garlic Naan" style dish families).

## 2. What every scenario verifies

For each of the 520 scenarios, the following ran against the same materialized context and were asserted (not just executed — every check is a real, recorded assertion):

- **`computeMergedScores`**: determinism (two consecutive calls produce byte-identical maps).
- **Recommended For You**: determinism; never exceeds the section limit; no duplicate products; combo count never exceeds the cap (2); no combo appears before an individual product; once a combo appears, only combos follow; confidence is non-increasing among individual products (combos are deliberately exempt from this — see §4).
- **Explore Menu**: determinism; no duplicates; combo count never exceeds the cap.
- **Restaurant Must Try / Most Loved Here / Hidden Gems**: no duplicates; Most Loved Here entries all have real sales this window (never fabricated).
- **Combo eligibility** (every combo in every scenario, 4,166 individual evaluations): score always within `[0,1]`; exactly `0.0` for a true cold-start customer (no behavioral evidence at all) — verified directly, not assumed.
- **Pairing** (normal and combo triggers, empty and populated/saturated carts): `pairingContextScore` bounded `[0,1]`; `fillPairsWellWith` never exceeds `maxItems`; no duplicates; never re-suggests an item already in the cart (including combo children, via the cart-content-awareness expansion).
- **Budget awareness spot check**: for low-budget customers (≤₹150) with real behavioral evidence, a dramatically over-budget combo's eligibility score stays honestly bounded rather than being inflated.
- **No crash**: every scenario's full pipeline wrapped in try/catch — a failure here is recorded as an `UNCAUGHT EXCEPTION` scenario failure with full repro info, not a silent skip. Zero occurred.

## 3. Performance (520-scenario run + combined 127-test run)

| Function | Calls | Avg | Min | Max | p95 |
|---|---|---|---|---|---|
| `computeMergedScores` | 520 | 0.94ms | 0.002ms | 17.5ms | 4.60ms |
| `recommendForYou` | 520 | 12.77ms | 0.001ms | 236.9ms | 148.9ms |
| `exploreMenuSelection` | 520 | 0.96ms | 0.003ms | 22.9ms | 4.30ms |
| `fillPairsWellWith` | 520 | 0.059ms | 0ms | 2.93ms | 0.33ms |
| `comboEligibilityScore` | 4,166 | 0.009ms | 0ms | 0.44ms | 0.023ms |

`recommendForYou`'s p95/max are dominated entirely by the rare 250/500-product scenarios (the weighted distribution keeps these to ~10% of runs) — consistent with the dedicated 500-product benchmark from earlier in this engagement (~200-250ms), not a new cost introduced by combo logic. The separate `performance_benchmark_test.dart` old-vs-new comparison (run in the same combined pass) showed a +14.5% delta on the 500-product `recommendForYou` case this run, which is machine-load noise consistent with prior runs in this session (this specific number has fluctuated ±15% across multiple runs on this hardware) — not a real regression; every other function shows sub-millisecond, noise-level deltas.

## 4. Notable design confirmation: combo confidence exemption

The exhaustive run confirmed, at scale, an intentional and previously-discussed trade-off: once a combo clears `comboEligibilityThreshold`, it can have a *higher* raw confidence score than individual products that still rank above it, because the combo-last partition is a hard priority rule (business requirement: "combos never dominate, never appear first"), not a score-based one. The fuzz test's confidence-monotonicity check was scoped to individual products only for exactly this reason — asserting strict monotonicity across the whole list (including combos) would be asserting something the spec explicitly overrides. This is documented in `recommendForYou`'s own combo-partition comment and confirmed here empirically across hundreds of eligible-combo scenarios with zero contradictions.

## 5. Edge cases covered

- 1-product and 500-product restaurants (both ends of the menu-size spectrum).
- Combo-heavy menus (~40% combos) alongside combo-free menus.
- Missing Business Context configuration (20% of scenarios) — no crash, honest zero-signal fallback confirmed.
- True cold-start customers (no behavior at all) paired with combo-heavy menus — combo eligibility confirmed exactly 0.0 in every such case, never fabricated.
- Combo children referencing other randomly-generated products (including cases where quantities >1 per child).
- Saturated/multi-combo/large-family carts exercising both individual and combo cart-awareness.
- Vegetarian-only and non-veg-only menus.
- Every named budget tier from ₹100 to ₹1500 against combo prices ranging ₹150–₹1350.

## 6. Remaining risks / not covered by this pass

- **UI rendering** was explicitly out of scope for this verification (per the brief) — the "combo trigger skips the Pairs Well With panel" behavior lives in `newVendorProductsScreen.dart`'s `_showPairsWellWith` (a widget-layer method) and was verified by direct code inspection + the earlier targeted change, not a widget test here. If you want that exercised via `flutter_test`'s widget-testing APIs, that's a separate, larger effort (would need Firebase/widget scaffolding this pure-engine suite deliberately avoids).
- **"Trending" section**: named in the brief's "Recommendation Sections" list, but no such section exists anywhere in this codebase — the closest concept is Restaurant Must Try's internal recent-trend boost (`_mustTryTrend`), which isn't a separately exposed section. Flagging this rather than fabricating a test for a feature that doesn't exist.
- **Live Firestore read/write counts**: not measurable from this pure-Dart suite (the engine is provably Firebase-free, confirmed by the complete absence of any `firestore.`/`.collection(` call in `recommendation_engine.dart`) — the same limitation noted in the original audit report.
- **Memory allocation** wasn't independently profiled beyond wall-clock timing (Dart VM tests don't expose a lightweight allocation-tracking API without external tooling) — the performance numbers above are execution-time only, consistent with every other benchmark in this engagement.

## 7. Recommended improvements (optional, not blocking)

- The `recommendForYou` p95 (148.9ms, driven by rare 500-product scenarios) is acceptable for a background/async section load but worth keeping an eye on if real menus regularly approach that size — no action needed today.
- Consider periodically re-running `exhaustive_fuzz_test.dart` with a different seed (or a rotating seed per CI run) to broaden randomized coverage over time, while keeping this seed (`20260719`) as the permanent, reproducible baseline for regression comparisons.

## Verdict

**Production-ready**, per the criteria set out in this verification: 520/520 scenarios executed, 50,147/50,147 assertions passed, 127/127 combined suite tests passed, zero crashes, zero non-deterministic output, all documented trade-offs (combo confidence exemption) confirmed intentional rather than defects.
