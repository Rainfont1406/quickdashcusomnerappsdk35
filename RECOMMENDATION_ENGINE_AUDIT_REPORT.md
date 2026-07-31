# Recommendation Engine — End-to-End Verification Report

**Date:** 2026-07-19
**Scope:** `lib/services/recommendation/recommendation_engine.dart` and its dynamic-section-sizing helpers (`dynamicSectionLimit`/`sectionLimitFor`/`pairingSectionLimitFor`), exercised via a synthetic 26-restaurant dataset.
**Method:** Automated Dart test suite (`test/recommendation/`) run against the engine directly — `RecommendationEngine` is documented as pure Dart, synchronous, and Firebase-free (its own file header: "Every method here takes already-loaded data as arguments and returns a plain scored/ranked result"), so this is the correct, fully-automatable layer to verify it at.
**Result:** 80 automated test cases, **79 passed**, **1 confirmed defect** (narrow scope, detailed below). No changes were made to `recommendation_engine.dart` itself — per the audit's own ground rule, the finding is reported for your decision rather than silently patched.

---

## 1. Test dataset

`test/recommendation/vendor_dataset.dart` builds **26 synthetic restaurants** (`buildVendorDataset()`), each a real `VendorModel` + `List<ProductModel>` pair:

| # | Label | Business Type | Cuisines | Menu size |
|---|---|---|---|---|
| 1 | Pure North Indian | Restaurant | North Indian | 20 |
| 2 | Pure Chinese | Restaurant | Chinese | 20 |
| 3 | Cafe | Cafe | Cafe | 20 |
| 4 | Bakery | Bakery | Bakery | 20 |
| 5 | Juice Bar | Juice Bar | Beverage | 20 |
| 6 | Fast Food | Fast Food | Fast Food | 20 |
| 7 | North Indian + Chinese | Restaurant | 2 cuisines | 20 |
| 8 | North Indian + Fast Food | Restaurant | 2 cuisines | 20 |
| 9 | Chinese + Cafe | Cafe | 2 cuisines | 20 |
| 10 | Cafe + Bakery | Cafe | 2 cuisines | 20 |
| 11 | North Indian + Chinese + Fast Food | Restaurant | 3 cuisines | 20 |
| 12 | North Indian + Chinese + Beverage | Restaurant | 3 cuisines | 20 |
| 13 | Cloud Kitchen | **no Business Type profile entry** | North Indian | 20 |
| 14 | No cuisine configured | Restaurant | — | 20 |
| 15 | No Business Type configured | — | North Indian | 20 |
| 16 | Only Business Type configured | Restaurant | — | 20 |
| 17 | Both configured | Restaurant | North Indian | 20 |
| 18 | Neither configured | — | — | 20 |
| 19 | Tiny menu | Restaurant | North Indian | **5** |
| 20 | Small menu | Restaurant | North Indian | **15** |
| 21 | Medium menu | Restaurant | 2 cuisines | **40** |
| 22 | Large menu | Restaurant | 3 cuisines | **150** |
| 23 | Huge menu (perf) | Restaurant | 3 cuisines | **500** |
| 24 | Zero-sales cold start | Restaurant | North Indian | 10 |
| 25 | High-sales veteran | Restaurant | 2 cuisines | 50 |
| 26 | Single product | Restaurant | North Indian | 1 |

Every restaurant's menu is drawn from the same **19-dish vocabulary** named in the brief (Butter Chicken, Dal Makhani, Paneer Butter Masala, Butter Naan, Garlic Naan, Rice, Jeera Rice, Raita, Salad, Biryani, Coffee, Tea, Juice, Milkshake, Pizza, Burger, Pasta, Noodles, Soup, Dessert), tagged to a shared 14-category vocabulary, with admin-style `cuisineCategoryAffinity`/`businessTypeProfiles` config maps mirroring the real Firestore-backed shape (`business_context_cuisine_affinity` / `business_context_type_profiles`).

**Customer-behavior personas** (`fixtures.dart`): beverage lover, dessert lover, North Indian lover, Chinese lover, Pizza lover, mixed preference, brand-new (zero signal), zero-orders-but-browsed, and an order-volume ladder (1/10/100 orders) — covering every persona named in the brief.

This dataset composition is itself asserted by 4 passing tests (`1. Test dataset generation`).

---

## 2–9, 12. Section-by-section results

| Section | Tests | Result |
|---|---|---|
| Dynamic section-size table (all 7 bands + boundary values) | 23 | ✅ all pass |
| 7. Business Context (Type-only / Cuisine-only / both / neither / Cloud Kitchen / no-op check) | 6 | ✅ all pass |
| 6. Multi-cuisine pairing (6 named combos + Restaurant-Type-independence + full trigger sweep) | 8 | ✅ all pass |
| 5. Pairs Well With (priority chain, vendor pairing, cart dedup, saturation, cap-at-8) | 6 | ✅ all pass |
| 3. Explore Menu (5/15/40/150-product sizes, category order, representative-product match, multi-cuisine exposure, determinism) | 9 | ✅ all pass |
| 4. Recommended For You (cold start, 4 preference personas, order-volume confidence trend, crash safety) | 7 | ✅ all pass |
| 2. Restaurant Must Try / Hidden Gems / Most Loved Here | 3 | ✅ all pass |
| 9. Confidence verification | 3 | ⚠️ **1 failed** (see §10) |
| 8. Cold start (0 orders × 10/50 products) | 2 | ✅ all pass |
| 12. Edge cases (1 product, 500 products, zero/huge history, empty/missing/deleted/unknown cuisine & Business Type & category) | 8 | ✅ all pass |
| 10. Performance | 2 | ✅ all pass (see §11) |
| **Total** | **80 (incl. 4 dataset-integrity tests)** | **79 pass / 1 fail** |

Full pass/fail list (one line per test) is reproducible via:
```
fvm flutter test test/recommendation/
```

### Key ordering/behavior evidence gathered

- **Business Context noisy-OR is provably not a plain sum**: `businessContextScore` for a primary(1.0)+cuisine(0.7) match returns exactly `1.0`, never `1.7`.
- **Cloud Kitchen** (Business Type set, zero profile entry) degrades to "cuisine-only" behavior with no crash, exactly as designed.
- **The frozen Butter-Chicken-multi-cuisine regression scenario** (North Indian + Chinese + Fast Food) is directly re-verified: Naan/Rice/Raita all outrank Coffee/Pizza/Burger/Noodles for a Butter Chicken trigger, and Restaurant Type is confirmed to participate **unnarrowed** even under a Fast-Food-only-cuisine trigger (Naan still scores via Type alone under a Pizza trigger).
- **Cafe + Bakery shared-category test** confirms the "no arbitrary tie-break" design: triggering from Dessert (which matches both Cafe and Bakery affinity) correctly activates Bakery's Bread category too, while triggering from Coffee (Cafe-only) correctly does **not**.
- **Pairs Well With's full 9-tier priority chain** was independently verified tier-by-tier: vendor-curated leads unconditionally → cart-duplicate suppression removes entirely → saturation deprioritizes-never-eliminates (both the "abundant alternatives" and "must backfill" cases) → Product Context → Cross-Sell → Preference → Best Seller → stable id order, in that exact order, with deliberate ties constructed at each tier to isolate it.
- **`pairingSectionLimitFor` never exceeds 8**, confirmed even on the 500-product restaurant where the uncapped `sectionLimitFor` correctly returns 20.
- **Explore Menu's representative-product selection is byte-identical to `reorderByScore` on the real menu** (once the test correctly restricts to one representative per category — see the note on this fix in §12).
- **True cold start (0 orders, no Business Context configured) returns empty for every section** — no fabricated recommendations, confirmed for both 10-product and 50-product menus.

---

## 10. Confidence verification — 1 confirmed defect

**Finding:** In **Recommended For You only**, the final displayed order can show a lower-ranked product with a *strictly higher* confidence badge than a higher-ranked product above it.

**Reproduction** (from the test's debug trace, restaurant "North Indian + Chinese + Fast Food", `mixedPreferenceCustomer`, uniform staggered sales):

```
Salad         → position 17, confidence 0.5344
Garlic Naan   → position 16, confidence 0.5917
Butter Chicken→ position 15, confidence 0.5966
Rice          → position 20 (LAST), confidence 0.7252   ← higher than all three above it
```

**Root cause:** `recommendForYou` → `_selectDiverse` (recommendation_engine.dart:1201). This function does a two-phase pass over the score-sorted list:
1. **Primary pass**: walks the sorted list top to bottom, keeping at most one product per "dish family" (near-duplicate name group via Jaccard token similarity — e.g. "Rice" and "Jeera Rice" share the token `rice`, similarity 0.5, at the `_duplicateSimilarityThreshold`).
2. **Backfill pass**: if the primary pass didn't fill `limit`, it walks the *same sorted list again from the top* and appends anything not yet chosen — including family-mates skipped in phase 1.

Because "Rice" and "Jeera Rice" are the same dish family, and "Jeera Rice" appeared earlier in the sorted order, "Rice" was skipped in the primary pass and only picked up in the backfill pass — which appends it at the **end** of the result regardless of its own score. Its score (0.7252) happens to be higher than several primary-pass picks that were included earlier specifically *because* they belonged to not-yet-used families, even at lower scores.

**Scope:** This affects **only `recommendForYou`** (the sole caller of `_selectDiverse`). It does **not** affect:
- Explore Menu (`exploreMenuSelection` — no diversity pass, one-per-category by construction)
- Restaurant Must Try / Hidden Gems (`topBySource`/`hiddenGems` — explicitly no diversity pass, by design, per that function's own doc comment)
- Pairs Well With's vendor-configured badge-eligible items (confirmed by a passing test — `fillPairsWellWith`'s vendor branch has no diversity/backfill step at all)

**Trigger conditions:** menu size ≥ `_diversityMinMenuSize` (10, so the diversity pass is active) **and** at least one pair of near-duplicate-named dishes where the lower-scored one displaces the higher-scored one out of the initial top-`limit` window into backfill. This requires real near-duplicate product names (Jaccard ≥ 0.5), so it's a real but narrow-frequency scenario — most menus won't hit it often, but any menu with size-variant dishes ("Rice"/"Jeera Rice", "Butter Naan"/"Garlic Naan", "Coffee"/"Iced Coffee", etc.) can.

**Suggested fix (not applied):** After assembling `chosen` in `_selectDiverse`, do a final stable re-sort of the whole list by score descending (keeping the family-uniqueness selection from phase 1 as-is, just re-ordering the combined primary+backfill set by score at the end) — this preserves "at most one per family in front" for a well-filled list while guaranteeing the invariant `normalizedMergedScores` was originally introduced to protect. This is a small, localized change to `_selectDiverse` alone; nothing else in the file references its internal two-phase structure.

I have not applied this fix. It touches a heavily-reviewed, previously-frozen function, so it's flagged here for your decision rather than changed unilaterally.

---

## 11. Performance verification

Measured via `Stopwatch` inside the test suite (informational — not a tight SLA, but a regression guard against an accidental O(n²)/O(n³) blowup):

| Scenario | Result |
|---|---|
| Full pipeline (computeMergedScores + recommendForYou + exploreMenuSelection + recommendationConfidenceScores + fillPairsWellWith) on **500 products** | **247ms** |
| `computeMergedScores` on 40 products | 142μs |
| `computeMergedScores` on 500 products | 456μs (≈3.2× for 12.5× the products — sub-linear in practice at this scale, well short of quadratic) |

**Firestore reads/writes:** Not measurable by execution here (the engine is provably Firebase-free — confirmed by the complete absence of any `firestore.`/`.collection(` call anywhere in `recommendation_engine.dart`, and the file's own header states this explicitly). The *only* Firestore-touching layer is `FireStoreUtils.loadRecommendationContext` (`FirebaseHelper.dart`), whose read set is, by its own doc comments:
- 1 behavior-summary fetch (batched across up to 12 monthly docs, cached per session for repeat calls)
- 1 rolling-sales-window fetch per vendor visit
- 1 Business Context fetch, served from an in-memory live listener after the very first app-session read (not re-fetched per restaurant visit)
- **Zero writes** — the engine and its data-loading layer are read-only

I did not attempt to execute this against a real Firestore project (staging or otherwise) to get literal read-count telemetry, since that requires live credentials/quota and this audit's automatable scope is the engine itself. If you want live read-count numbers, that requires either Firestore's own usage dashboard for a real session, or instrumenting `FireStoreUtils` with a counter — say the word and I'll wire that up separately.

---

## 13. Not automatable in this environment

The brief also asked for UI-level regression across Search/Cart/Checkout/Product page and screenshots. Both require a running app on a device/emulator, which this sandboxed environment doesn't have attached. What I verified instead as a substitute:
- **Static regression check**: `dart analyze` across every file touched in this and the prior session (0 new errors, only pre-existing unrelated warnings).
- **Call-site isolation check** (carried over from the prior session's work): grep-confirmed that `Restaurant Must Try`/`Most Loved Here` still use the untouched `defaultSectionLimit`, and that the new dynamic-limit helpers (`sectionLimitFor`/`pairingSectionLimitFor`) are the only new call sites.
- If you want the Search/Cart/Checkout/Product-page regression pass done for real, that needs to run on your device/emulator — happy to hand you a manual test checklist, or do it live if you attach a device/run `flutter run` yourself and share the session.

---

## Environment note

This sandbox only has Flutter 3.35.1 installed; the project is pinned to 3.27.3 via `fvm_config.json`/`CLAUDE.md`, which isn't actually installed here. To get the suite running at all, I temporarily added an `intl` override to `pubspec.yaml`'s `dependency_overrides`, ran the tests, then **fully reverted both `pubspec.yaml` and `pubspec.lock`** to their exact pre-session byte content (verified via diff against a pre-edit backup) — confirmed only your pre-existing, unrelated pending `visibility_detector` change remains. `.dart_tool/` (gitignored) was left resolved under 3.35.1 from that run; run `fvm flutter pub get` once before your next real build to re-sync it under 3.27.3.

## Suite location

- `test/recommendation/fixtures.dart` — builders (products, vendors, ctx, behavior personas)
- `test/recommendation/vendor_dataset.dart` — the 26-restaurant dataset
- `test/recommendation/recommendation_engine_verification_test.dart` — all 80 test cases

Run with `fvm flutter test test/recommendation/` once your SDK is available.

## Verdict

**79/80 automated checks pass.** The engine's ranking, Business Context (Type/Cuisine/both/neither/Cloud Kitchen), multi-cuisine pairing narrowing, Pairs Well With's full priority chain, cold-start honesty, and dynamic section-sizing all behave exactly as designed under every scenario tested, including every edge case in §12 (1 product, 500 products, deleted/unknown cuisine/category/Business Type, zero and huge customer history).

One confirmed, narrow-scope defect exists in `_selectDiverse`'s backfill ordering (Recommended For You only) — not a regression from this session's dynamic-limit work (pre-existing in the diversity logic), not previously covered by any prior audit round in this engagement. **I'd recommend NOT declaring the engine fully production-ready until you decide on this one** — either accept it as a known, low-frequency, cosmetic-only issue (confidence badges aren't literally wrong, just occasionally out of relative order against a backfilled item), or say the word and I'll apply the minimal fix described in §10.
