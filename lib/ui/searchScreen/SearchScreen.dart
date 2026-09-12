import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/behavior/behavior_counters.dart';
import 'package:emartconsumer/services/behavior/behavior_event_types.dart';
import 'package:emartconsumer/services/behavior/behavior_tracker.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/recommendation/recommendation_config.dart';
import 'package:emartconsumer/services/recommendation/recommendation_engine.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:emartconsumer/utils/network_image_widget.dart';
import 'package:emartconsumer/widget/coming_soon_view.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Industry-standard search normalization: trim outer whitespace, lowercase,
// then collapse any run of internal whitespace to a single space - so
// "Chinese", "chinese", "CHINESE", " Chinese  Food " and "Chinese   Food"
// all compare identically. Applied once to every cached searchable field
// when it's loaded (see SearchScreenState's caches) and once per keystroke
// to the query itself (unavoidable - the query changes every keystroke, but
// normalizing one short string is cheap; it's the per-vendor/per-product
// data that must never be re-normalized on every keystroke).
String _normalizeSearchText(String input) {
  return input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

// ── Typo Tolerance + Prefix/Contains + Token Search (2026-07-25) ──────────
//
// Replaces plain `.contains(query)` substring matching everywhere in this
// file with a token-level cascade: exact -> prefix -> contains -> typo-
// tolerant fuzzy (Levenshtein edit distance within a length-scaled
// budget). Three requirements, one mechanism:
//   - Typo Tolerance: "piza"/"pzza" still finds "Pizza".
//   - Prefix + Contains: a word STARTING WITH the query (autocomplete-
//     style) is checked before, and preferred over, a mid-string
//     substring hit - both still count as a match, prefix just wins the
//     cascade first.
//   - Token Search: a multi-word query matches regardless of word order
//     or extra words in between ("chicken biryani" finds "Biryani
//     Chicken" and "Chicken Tikka Biryani" alike) - AND semantics across
//     query tokens (every query token must match something), OR
//     semantics within one token's search across target tokens (any one
//     target token matching is enough for that query token).
//
// Zero new Firestore reads/state - operates purely on the already-cached,
// already-normalized strings this screen builds once at load time (see
// _titleCache/_cuisineCache/_productCategoryCache/_productNameCache),
// tokenizing them on the fly per keystroke. That's cheap: splitting an
// already-normalized string on a single space character, not
// re-normalizing (same "only the query itself is normalized/tokenized
// per keystroke" cost model _normalizeSearchText's own doc comment
// already established for this file).

// Classic DP edit distance (insert/delete/substitute, unit cost each).
// O(len(a) * len(b)) - fine here since every input is a single short
// search word (a restaurant/cuisine/category/dish token, a handful of
// characters), never a long string, and this only ever runs once the
// cheaper exact/prefix/contains checks below have already failed for a
// given token pair - a correctly-typed query never reaches it at all.
int _editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (j) => j);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      final del = prev[j] + 1;
      final ins = curr[j - 1] + 1;
      final sub = prev[j - 1] + cost;
      curr[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
}

// How many typo'd characters (insert/delete/substitute) a word of this
// length may have and still count as a match - a standard search-industry
// scaled budget (mirrors Algolia's own typo-tolerance defaults): too
// short to safely fuzz at all (0-3 chars - e.g. "cat" vs "car" are both
// real, unrelated words exactly one edit apart), 1 allowed edit for a
// normal word (4-8 chars), 2 for a long word (9+, where one extra edit is
// proportionally less likely to collide with a different real word).
int _typoBudgetFor(String word) {
  if (word.length <= 3) return 0;
  if (word.length <= 8) return 1;
  return 2;
}

// Match strength between one query token and one target token, checked in
// cheapest-first order (exact -> prefix -> contains -> fuzzy) so the
// common case - a correctly-typed query - never pays for an edit-distance
// computation at all. Returns 0.0 for no match; any positive value is a
// match (the exact number only orders which cascade step won, not used
// for cross-result ranking).
double _tokenMatchScore(String queryToken, String targetToken) {
  if (queryToken.isEmpty || targetToken.isEmpty) return 0.0;
  if (queryToken == targetToken) return 1.0;
  if (targetToken.startsWith(queryToken)) return 0.9; // Prefix
  if (targetToken.contains(queryToken)) return 0.7; // Contains
  final budget = _typoBudgetFor(queryToken); // Typo Tolerance
  if (budget > 0 && (targetToken.length - queryToken.length).abs() <= budget) {
    if (_editDistance(queryToken, targetToken) <= budget) return 0.5;
  }
  return 0.0;
}

// Token Search: [queryTokens] (pre-split by the caller once per keystroke,
// not re-split per candidate - see _runSearch) must EACH find at least
// one matching token somewhere in [target] (AND across query tokens) -
// word order in [target] is irrelevant. Returns 0.0 (no match) or a
// positive score; every call site here only needs "> 0" to decide
// inclusion, the same threshold semantics the `.contains()` checks this
// replaces already had.
double _fuzzyTextMatchScore(List<String> queryTokens, String target) {
  if (queryTokens.isEmpty || target.isEmpty) return 0.0;
  final targetTokens = target.split(' ');
  double total = 0.0;
  for (final qToken in queryTokens) {
    double best = 0.0;
    for (final tToken in targetTokens) {
      final s = _tokenMatchScore(qToken, tToken);
      if (s > best) best = s;
      if (best == 1.0) break; // can't improve on an exact hit
    }
    if (best == 0.0) return 0.0; // every query token must match something
    total += best;
  }
  return total / queryTokens.length;
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  SearchScreenState createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  String _query = '';
  List<String> _recentSearches = [];
  List<VendorModel> _results = [];
  List<VendorModel> _recommended = [];
  List<String> _trending = [];

  // Which tier each currently-displayed result matched on ('name'/'cuisine'/
  // 'category'/'dish') - rebuilt on every _runSearch call, read when a
  // result card is tapped so "selected from search" vs "selected from
  // cuisine search" can be tracked accurately. A vendor from _recommended
  // (not an actual search match) is absent here on purpose - tapping one of
  // those isn't a search selection.
  Map<String, String> _tierByVendorId = {};

  // Phase 2 recommendation engine (2026-07-17) - Stage 1 personalization
  // term for _score() below. Computed once against the full allstoreList
  // (not recomputed per keystroke) so every tier/ranking in this screen
  // shares one consistent normalization; refreshed once the async behavior
  // summary load completes, then _buildRecommended()/_runSearch() are
  // re-run so the UI updates in place. Empty (all-zero) for signed-out/new
  // users - _score() treats that as "no personalization signal", not an
  // error, so Stage 0 ranking is untouched until real signal exists.
  Map<String, double> _personalizationScores = {};

  // Search-behavior tracking fires once per typing "session" (not per
  // keystroke, not even once per pause-in-typing - see _trackIfNew below)
  // at whichever session-end point happens first: losing focus, tapping a
  // result, an explicit submit/chip-tap, or this screen being disposed with
  // an untracked query still in the box.
  //
  // 2026-07-18 fix: this used to be a 900ms keystroke-pause debounce, which
  // fired a SEPARATE tracked "search" every time the user paused mid-word
  // for >=900ms while composing a query (confirmed against live data: a
  // customer typing "buuurg" with natural typing pauses produced 6 distinct
  // tracked fragments - "b", "bu", "buu", "buuu", "buur", "buuurg" - all
  // counted as independent searches in topSearchKeywords/searchDayHits).
  // Firestore's FieldValue.increment has no compensating "un-increment
  // whatever we just sent a moment ago" - the write is already merged into
  // a shared aggregate by the time a later keystroke would reveal it was
  // premature - so the fix is to never send an intermediate fragment in the
  // first place: track only the query the user actually settled on.
  String? _lastTrackedQuery;

  // Every cache below is normalized ONCE here (trim + lowercase + collapse
  // internal whitespace to a single space - see _normalizeSearchText), never
  // re-normalized per keystroke. Only the query itself is normalized per
  // keystroke, which is unavoidable (it changes) but cheap (one short
  // string). Location is deliberately not cached/searched here - handled
  // elsewhere in the app.
  //
  // Priority order (see _runSearch): Restaurant Name > Cuisine Name >
  // Product Category > dish/item name (kept as the pre-existing lowest-
  // priority fallback tier - nothing in this rework removes it, it's just
  // no longer flattened together with everything else).
  late final List<String> _titleCache;
  // Store-level Cuisine names (North Indian, Chinese, Pizza, ...), joined
  // into one normalized string per vendor.
  late final List<String> _cuisineCache;
  // Product-level category names (the real, live category system used by
  // AddOrUpdateProductScreen - e.g. "Chinese", "Starters") aggregated per
  // vendor from that vendor's own menu. _categoryIdToTitle is read from the
  // GLOBAL allProductCategoriesList (constants.dart) - populated once by
  // HomeScreen.getBanner()'s existing getCuisines() call, so normally this
  // costs zero additional Firestore queries. If this screen is somehow
  // reached before Home has populated it (deep link, future navigation
  // change), _ensureProductCategoriesLoaded() below fetches it once as a
  // fallback and fills the SAME global list, so it's still only ever
  // fetched once app-wide, not once per SearchScreen open.
  List<String> _productCategoryCache = [];
  Map<String, String> _categoryIdToTitle = {};

  Map<String, String> _buildCategoryIdToTitle() => {
        for (final c in allProductCategoriesList)
          if ((c.id ?? '').isNotEmpty) c.id!: _normalizeSearchText(c.title ?? ''),
      };

  // Dish/item name search — products loaded for whichever order type
  // (Delivery vs Dineaway) launched this screen, so a store whose name
  // doesn't match can still surface via a matching dish. Normalized once
  // alongside _searchableProducts itself, not per keystroke.
  final bool _isDineaway = currentOrderTypeGlobal == 'Dineaway'.tr();
  List<ProductModel> _searchableProducts = [];
  List<String> _productNameCache = [];
  late final Map<String, VendorModel> _vendorById = {
    for (final v in allstoreList) v.id: v,
  };

  // Search → Category Learning (2026-07-22) - the deduplicated set of
  // Product Category IDs represented by the CURRENT query's matches,
  // recomputed every _runSearch call, read back by _trackSearchPerformed
  // when a search is actually tracked (see that method + the category-name/
  // dish-name collection inside _runSearch for how this gets populated).
  // Not persisted, not read anywhere else - purely a same-frame handoff
  // from "what matched" to "what gets tracked", same lifetime as _results.
  Set<String> _lastMatchedCategoryIds = {};

  // Search → Cuisine Learning (2026-07-27) - same lifetime/handoff pattern
  // as _lastMatchedCategoryIds above. Populated from two sources in
  // _runSearch: vendors matched directly by Cuisine Name (tierCuisine -
  // already computed for ranking, just never read for learning before
  // this), and the vendors behind any dish-name match (mirrors category's
  // own product-name source) - a search for "Pasta" teaches "likes Pasta"
  // AND "likes Italian" if the matching dish's restaurant is Italian.
  Set<String> _lastMatchedCuisineIds = {};

  static const String _recentKey = 'search_recent_queries';
  static const int _maxRecent = 8;

  @override
  void initState() {
    super.initState();
    _titleCache =
        allstoreList.map((v) => _normalizeSearchText(v.title)).toList();
    _cuisineCache = allstoreList
        .map((v) => _normalizeSearchText(v.cuisineNames.join(' ')))
        .toList();
    _categoryIdToTitle = _buildCategoryIdToTitle();
    if (allProductCategoriesList.isEmpty) {
      // Home normally populates this before Search is reachable; this is
      // just a safety net for whatever future flow might reach Search first.
      _ensureProductCategoriesLoaded();
    }
    _buildRecommended();
    _buildTrending();
    _loadRecent();
    _loadSearchableProducts();
    _loadPersonalization();
    // Session-end tracking trigger #1: the keyboard/field losing focus
    // (tapping elsewhere, dismissing the keyboard) means the user is done
    // with this query, whatever it currently is.
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _query.trim().isNotEmpty) {
        _trackIfNew(_query);
      }
    });
  }

  Future<void> _loadPersonalization() async {
    try {
      final summary = await FireStoreUtils.getBehaviorSummary();
      if (!mounted || summary.isEmpty) return;
      _personalizationScores =
          RecommendationEngine.restaurantPreferenceScores(allstoreList, summary);
      _buildRecommended();
      setState(() {});
      if (_query.trim().isNotEmpty) _runSearch(_query);
    } catch (_) {
      // Non-critical - ranking simply stays unpersonalized.
    }
  }

  Future<void> _ensureProductCategoriesLoaded() async {
    final fireStoreUtils = FireStoreUtils();
    final categories = await fireStoreUtils.getCuisines();
    if (!mounted) return;
    if (allProductCategoriesList.isEmpty) {
      // Fill the GLOBAL list, not just a local copy — any other screen
      // (including a later SearchScreen open) benefits too, and this fallback
      // never fires again once it's populated.
      allProductCategoriesList
        ..clear()
        ..addAll(categories);
    }
    _categoryIdToTitle = _buildCategoryIdToTitle();
    _buildProductCategoryCache();
    if (_query.trim().isNotEmpty) _runSearch(_query);
  }

  // A product with no delivery/takeaway/dine-in flags set is a legacy,
  // unrestricted item (see ProductDetailsScreen._hasRestrictions) — treat it
  // as available for any order type rather than hiding it from search.
  bool _productSupportsCurrentOrderType(ProductModel p) {
    final bool hasRestrictions = p.deliveryOption || p.takeaway || p.dineIn;
    if (!hasRestrictions) return true;
    return _isDineaway ? (p.dineIn || p.takeaway) : p.deliveryOption;
  }

  Future<void> _loadSearchableProducts() async {
    final fireStoreUtils = FireStoreUtils();
    final list = _isDineaway
        ? await fireStoreUtils.getAllTakeAWayProducts()
        : await fireStoreUtils.getAllDelevryProducts();
    if (!mounted) return;
    _searchableProducts = list.where(_productSupportsCurrentOrderType).toList();
    _productNameCache =
        _searchableProducts.map((p) => _normalizeSearchText(p.name)).toList();
    _buildProductCategoryCache();
    if (_query.trim().isNotEmpty) _runSearch(_query);
  }

  // Product Category tier: resolves each product's categoryID against
  // _categoryIdToTitle (built synchronously above from the already-shared
  // allProductCategoriesList — zero additional Firestore queries here).
  // Only _searchableProducts itself needs an async wait, same as the dish-
  // name tier already required.
  void _buildProductCategoryCache() {
    final Map<String, Set<String>> categoryNamesByVendor = {};
    for (final p in _searchableProducts) {
      final categoryName = _categoryIdToTitle[p.categoryID];
      if (categoryName == null || categoryName.isEmpty) continue;
      categoryNamesByVendor.putIfAbsent(p.vendorID, () => <String>{}).add(categoryName);
    }
    _productCategoryCache = allstoreList
        .map((v) => (categoryNamesByVendor[v.id] ?? const <String>{}).join(' '))
        .toList();
  }

  @override
  void dispose() {
    // Session-end tracking trigger #2: this screen going away entirely
    // (back navigation, or removed from the stack some other way) with a
    // query still sitting in the box that never lost focus and was never
    // submitted/tapped-through - e.g. the user typed, glanced at results,
    // then pressed back without tapping anything. Fire-and-forget is fine
    // here (BehaviorTracker.track is synchronous internally); it must not
    // be awaited from dispose().
    if (_query.trim().isNotEmpty) _trackIfNew(_query);
    _queryCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // Tracks [rawQuery] as one completed search - but only if it's actually
  // different from the last query this session already tracked, so the
  // several session-end triggers above (focus loss, result tap, submit,
  // dispose) never double-track the same final query just because more
  // than one of them fires for it.
  void _trackIfNew(String rawQuery) {
    final normalized = _normalizeSearchText(rawQuery);
    if (normalized.isEmpty || normalized == _lastTrackedQuery) return;
    _lastTrackedQuery = normalized;
    _trackSearchPerformed(rawQuery);
  }

  // ── Data preparation ──────────────────────────────────────────────────────

  void _buildRecommended() {
    final open = allstoreList
        .where((v) => v.isAcceptingOrders)
        .toList();
    // Index-decorated for a deterministic tie-break - plain List.sort isn't
    // guaranteed stable, and two restaurants tying on _score() is common
    // (e.g. both unrated and equidistant).
    final indexed = open.asMap().entries.toList()
      ..sort((a, b) {
        final cmp = _score(b.value).compareTo(_score(a.value));
        return cmp != 0 ? cmp : a.key.compareTo(b.key);
      });
    _recommended = indexed.map((e) => e.value).take(10).toList();
  }

  // Suggests cuisine names rather than the old categoryTitle - keeps this
  // consistent with the new search tiers below (categoryTitle is no longer
  // part of search matching at all, so a trending chip built from it could
  // tap through to zero results).
  //
  // Genuinely frequency-ranked (2026-07-17 fix - this used to add cuisines
  // in first-seen menu order despite the "Trending" label, which wasn't
  // actually true). This is deliberately NOT the same thing as a
  // cross-user "Popular Searches" claim: it's a straightforward count of
  // how many restaurants in allstoreList (server-fetched shared data,
  // identical for every user) serve each cuisine - a real global
  // computation, just not derived from anyone's search behavior.
  void _buildTrending() {
    final counts = <String, int>{};
    final displayName = <String, String>{};
    for (final v in allstoreList) {
      for (final name in v.cuisineNames) {
        final t = name.trim();
        if (t.isEmpty) continue;
        final key = t.toLowerCase();
        counts[key] = (counts[key] ?? 0) + 1;
        displayName.putIfAbsent(key, () => t);
      }
    }
    // Index-decorated for a deterministic tie-break (first-seen cuisine
    // wins - Dart's Map preserves insertion order) - plain List.sort isn't
    // guaranteed stable, and equal cuisine counts are common.
    final keys = counts.keys.toList();
    final indexed = keys.asMap().entries.toList()
      ..sort((a, b) {
        final cmp = counts[b.value]!.compareTo(counts[a.value]!);
        return cmp != 0 ? cmp : a.key.compareTo(b.key);
      });
    _trending =
        indexed.take(10).map((e) => displayName[e.value]!).toList();
  }

  Future<void> _loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_recentKey) ?? [];
    if (mounted) setState(() => _recentSearches = raw);
  }

  Future<void> _addRecent(String q) async {
    final trimmed = q.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final updated = [trimmed, ..._recentSearches.where((s) => s != trimmed)]
        .take(_maxRecent)
        .toList();
    await prefs.setStringList(_recentKey, updated);
    if (mounted) setState(() => _recentSearches = updated);
  }

  Future<void> _removeRecent(String q) async {
    final prefs = await SharedPreferences.getInstance();
    final updated = _recentSearches.where((s) => s != q).toList();
    await prefs.setStringList(_recentKey, updated);
    if (mounted) setState(() => _recentSearches = updated);
  }

  Future<void> _clearAllRecent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentKey);
    if (mounted) setState(() => _recentSearches = []);
  }

  // ── Search ────────────────────────────────────────────────────────────────

  void _onChanged(String value) {
    setState(() => _query = value);
    if (value.trim().isEmpty) {
      setState(() => _results = []);
      // Cleared back to empty - the next thing typed starts a brand-new
      // session, not a continuation of whatever was tracked before.
      _lastTrackedQuery = null;
      return;
    }
    _runSearch(value);
    // No tracking call here on purpose - see _trackIfNew's call sites
    // (focus loss, result tap, submit, chip-tap, dispose) for where a
    // completed query actually gets tracked.
  }

  // Priority-tiered, case-insensitive, whitespace-normalized search over the
  // already-cached dataset — no Firestore query happens here, ever. A vendor
  // is placed in exactly ONE tier (its highest-priority match) and never
  // duplicated across tiers:
  //   1. Restaurant Name
  //   2. Cuisine Name
  //   3. Product Category (resolved from that vendor's own menu items)
  //   4. Dish/item name (lowest priority, pre-existing fallback - a store
  //      whose name/cuisine/category didn't match can still surface via a
  //      matching dish)
  // Location is intentionally excluded - handled elsewhere in the app.
  void _runSearch(String text) {
    final query = _normalizeSearchText(text);
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }

    // Typo Tolerance + Prefix/Contains + Token Search (2026-07-25) - the
    // query is tokenized ONCE per keystroke here, not re-split per
    // candidate below (see _fuzzyTextMatchScore's own doc comment).
    final queryTokens = query.split(' ');

    final matchedIds = <String>{};
    final tierName = <VendorModel>[];
    final tierCuisine = <VendorModel>[];
    final tierProductCategory = <VendorModel>[];
    final tierDish = <VendorModel>[];
    final tierByVendorId = <String, String>{};

    for (int i = 0; i < allstoreList.length; i++) {
      final v = allstoreList[i];
      if (_titleCache.length > i && _fuzzyTextMatchScore(queryTokens, _titleCache[i]) > 0) {
        tierName.add(v);
        matchedIds.add(v.id);
        tierByVendorId[v.id] = 'name';
      } else if (_cuisineCache.length > i &&
          _fuzzyTextMatchScore(queryTokens, _cuisineCache[i]) > 0) {
        tierCuisine.add(v);
        matchedIds.add(v.id);
        tierByVendorId[v.id] = 'cuisine';
      } else if (_productCategoryCache.length > i &&
          _fuzzyTextMatchScore(queryTokens, _productCategoryCache[i]) > 0) {
        tierProductCategory.add(v);
        matchedIds.add(v.id);
        tierByVendorId[v.id] = 'category';
      }
    }

    for (int i = 0; i < _searchableProducts.length; i++) {
      if (!(_productNameCache.length > i &&
          _fuzzyTextMatchScore(queryTokens, _productNameCache[i]) > 0)) {
        continue;
      }
      final vendor = _vendorById[_searchableProducts[i].vendorID];
      if (vendor == null || matchedIds.contains(vendor.id)) continue;
      matchedIds.add(vendor.id);
      tierDish.add(vendor);
      tierByVendorId[vendor.id] = 'dish';
    }
    _tierByVendorId = tierByVendorId;

    // Search → Category Learning (2026-07-22) - independent of the vendor
    // ranking tiers above, deliberately: those decide WHICH RESTAURANTS to
    // show and dedupe by vendor, which would silently drop a second
    // matching category once one vendor already matched on an earlier tier
    // (e.g. a vendor matching by Name would never reach the dish-name loop
    // at all). Category learning needs every matching category regardless
    // of vendor ranking, so it reads the same two already-in-memory sources
    // directly instead of piggy-backing on the tier loops:
    //   1. Category NAME matches "Coffee"/"Biryani" resolving straight to
    //      that category, via _categoryIdToTitle - the canonical global
    //      category list (constants.dart), already built, zero extra reads.
    //   2. Product NAME matches ("Mango Juice") resolving to that product's
    //      own categoryID, via the already-loaded _searchableProducts -
    //      the same list the dish tier above iterates.
    // Deduplicated via Set by construction - "Juice +1" once, however many
    // Juice-category products matched, matching the existing
    // categoryInteractionCounts weighting used everywhere else (a search
    // match is browsing-strength evidence, same weight as a product view).
    final matchedCategoryIds = <String>{};
    _categoryIdToTitle.forEach((categoryId, title) {
      if (_fuzzyTextMatchScore(queryTokens, title) > 0) matchedCategoryIds.add(categoryId);
    });
    for (int i = 0; i < _searchableProducts.length; i++) {
      if (_productNameCache.length > i &&
          _fuzzyTextMatchScore(queryTokens, _productNameCache[i]) > 0) {
        final categoryId = _searchableProducts[i].categoryID;
        if (categoryId.isNotEmpty) matchedCategoryIds.add(categoryId);
      }
    }
    _lastMatchedCategoryIds = matchedCategoryIds;

    // Search → Cuisine Learning (2026-07-27) - same "every match regardless
    // of vendor ranking" reasoning as category learning above, using its
    // own two sources: vendors matched directly by Cuisine Name (tierCuisine,
    // already computed above for ranking - zero extra work), and the
    // vendors behind any dish-name match (same loop category's product-name
    // source uses, just reading .vendorID -> _vendorById instead of
    // .categoryID). Deduplicated via Set by construction, same weighting
    // rationale as category (a search match is browsing-strength evidence).
    final matchedCuisineIds = <String>{};
    for (final v in tierCuisine) {
      matchedCuisineIds.addAll(v.cuisineIds);
    }
    for (int i = 0; i < _searchableProducts.length; i++) {
      if (_productNameCache.length > i &&
          _fuzzyTextMatchScore(queryTokens, _productNameCache[i]) > 0) {
        final vendor = _vendorById[_searchableProducts[i].vendorID];
        if (vendor != null) matchedCuisineIds.addAll(vendor.cuisineIds);
      }
    }
    _lastMatchedCuisineIds = matchedCuisineIds;

    // Within each tier: open first, then ranked by score; closed at the bottom.
    // Index-decorated for a deterministic tie-break - plain List.sort isn't
    // guaranteed stable, and two restaurants tying on open-status + _score()
    // is common.
    void rank(List<VendorModel> tier) {
      final indexed = tier.asMap().entries.toList();
      indexed.sort((a, b) {
        final aOpen = a.value.isAcceptingOrders;
        final bOpen = b.value.isAcceptingOrders;
        if (aOpen != bOpen) return aOpen ? -1 : 1;
        final cmp = _score(b.value).compareTo(_score(a.value));
        return cmp != 0 ? cmp : a.key.compareTo(b.key);
      });
      final ranked = indexed.map((e) => e.value).toList();
      tier
        ..clear()
        ..addAll(ranked);
    }

    rank(tierName);
    rank(tierCuisine);
    rank(tierProductCategory);
    rank(tierDish);

    setState(() => _results = [...tierName, ...tierCuisine, ...tierProductCategory, ...tierDish]);
  }

  void _applyQuery(String text) {
    _queryCtrl.text = text;
    setState(() => _query = text);
    _addRecent(text);
    _runSearch(text);
    _focusNode.unfocus();
    // Already an explicit action (tapping a recent/trending chip) - track
    // immediately. _trackIfNew's dedup guard means this is a no-op if the
    // focus-loss listener (fired by the unfocus() call just above) already
    // tracked this same value a moment earlier.
    _trackIfNew(text);
  }

  void _onSubmit(String text) {
    if (text.trim().isEmpty) return;
    _addRecent(text.trim());
    _runSearch(text.trim());
    _focusNode.unfocus();
    _trackIfNew(text);
  }

  Future<void> _trackSearchPerformed(String rawQuery) async {
    final query = _normalizeSearchText(rawQuery);
    if (query.isEmpty) return;
    final tierCounts = <String, int>{'name': 0, 'cuisine': 0, 'category': 0, 'dish': 0};
    for (final tier in _tierByVendorId.values) {
      tierCounts[tier] = (tierCounts[tier] ?? 0) + 1;
    }
    final repeatCount = await BehaviorCounters.increment('search_query', query);
    BehaviorTracker.track(kEvtSearchPerformed, {
      'query': query,
      'resultTierCounts': tierCounts,
      'repeatCount': repeatCount,
      'categoryIds': _lastMatchedCategoryIds.toList(),
      'cuisineIds': _lastMatchedCuisineIds.toList(),
    });
  }

  // ── Scoring ───────────────────────────────────────────────────────────────

  double _score(VendorModel v) {
    final rating = v.reviewsCount > 0 ? v.reviewsSum / v.reviewsCount : 0.0;
    final popularity = v.reviewsCount.toDouble().clamp(0, 500) / 500;
    final nearness = 1.0 / (_distanceKm(v) + 0.1);
    // Phase 2 (2026-07-17): purely additive on top of the original
    // rating/popularity/nearness formula (not carved out of its existing
    // 40/30/30 budget) so a signal-less user's ranking is byte-for-byte
    // identical to Stage 0 - personalization defaults to 0 and changes
    // nothing until real behavior signal exists.
    final personalization = _personalizationScores[v.id] ?? 0.0;
    // Recommendation Configuration (2026-07-22) - was the literal
    // 40/30/30/20 weights; RecommendationConfig.current already defaults
    // to these exact numbers, so this is byte-for-byte the same formula
    // until an admin changes a value in the Admin Panel.
    final config = RecommendationConfig.current;
    return rating * config.ratingWeight +
        popularity * config.popularityWeight +
        nearness.clamp(0.0, config.distanceWeight) +
        personalization * config.personalizationWeight;
  }

  double _distanceKm(VendorModel v) {
    final loc = MyAppState.selectedPosotion.location;
    if (loc == null) return 9999.0;
    return Geolocator.distanceBetween(
          loc.latitude, loc.longitude, v.latitude, v.longitude) /
        1000;
  }

  String _distanceLabel(VendorModel v) {
    final km = _distanceKm(v);
    if (km >= 9000) return '';
    if (km < 1) return '${(km * 1000).toStringAsFixed(0)} m';
    return '${km.toStringAsFixed(1)} km';
  }

  // ── Next-opening label ────────────────────────────────────────────────────

  String _nextOpeningLabel(VendorModel v) {
    if (v.workingHours.isEmpty) return 'Temporarily unavailable';

    final now = DateTime.now();
    final todayDate = DateFormat('dd-MM-yyyy').format(now);
    final todayName = DateFormat('EEEE', 'en_US').format(now);

    // Remaining slots today
    for (final wh in v.workingHours) {
      if (wh.day == todayName && wh.timeslot != null) {
        for (final slot in wh.timeslot!) {
          if (slot.from == null) continue;
          try {
            final start = DateFormat('dd-MM-yyyy HH:mm')
                .parse('$todayDate ${slot.from}');
            if (start.isAfter(now)) {
              return 'Opens today at ${_fmtTime(slot.from!)}';
            }
          } catch (_) {}
        }
      }
    }

    // Next 7 days
    for (int d = 1; d <= 7; d++) {
      final next = now.add(Duration(days: d));
      final nextName = DateFormat('EEEE', 'en_US').format(next);
      for (final wh in v.workingHours) {
        if (wh.day == nextName &&
            wh.timeslot != null &&
            wh.timeslot!.isNotEmpty) {
          String? earliest;
          for (final slot in wh.timeslot!) {
            if (slot.from == null) continue;
            if (earliest == null) {
              earliest = slot.from;
            } else {
              try {
                final a = DateFormat('HH:mm').parse(earliest);
                final b = DateFormat('HH:mm').parse(slot.from!);
                if (b.isBefore(a)) earliest = slot.from;
              } catch (_) {}
            }
          }
          if (earliest != null) {
            if (d == 1) return 'Opens tomorrow at ${_fmtTime(earliest)}';
            return 'Opens ${DateFormat('EEEE').format(next)} at ${_fmtTime(earliest)}';
          }
        }
      }
    }

    return 'Temporarily unavailable';
  }

  String _fmtTime(String hhmm) {
    try {
      return DateFormat('h:mm a').format(DateFormat('HH:mm').parse(hhmm));
    } catch (_) {
      return hhmm;
    }
  }

  String _rating(VendorModel v) => calculateReview(
        reviewCount: v.reviewsCount.toString(),
        reviewSum: v.reviewsSum.toString(),
      );

  // photos[0] is the square restaurant logo; photo is the wide banner.
  String _logoUrl(VendorModel v) {
    if (v.photos.isNotEmpty) {
      final first = v.photos.first.toString().trim();
      if (first.isNotEmpty && first != 'null') return first;
    }
    return v.photo;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDeliveryActiveNotifier,
      builder: (context, deliveryActive, _) {
        if (currentOrderTypeGlobal == 'Delivery'.tr() && !deliveryActive) {
          return ComingSoonScreen(message: deliveryOffMessageNotifier.value);
        }
        return _buildSearchScreen(context);
      },
    );
  }

  Widget _buildSearchScreen(BuildContext context) {
    final dark = isDarkMode(context);
    return Scaffold(
      backgroundColor:
          dark ? AppThemeData.surfaceDark : AppThemeData.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(dark),
            Divider(
              height: 1,
              thickness: 1,
              color: dark ? AppThemeData.grey800 : AppThemeData.grey200,
            ),
            Expanded(
              child: _query.trim().isEmpty
                  ? _buildEmptyState(dark)
                  : _buildResults(dark),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          _circleButton(
            icon: Icons.arrow_back_rounded,
            dark: dark,
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: dark ? AppThemeData.grey800 : AppThemeData.grey100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(Icons.search_rounded,
                      size: 20,
                      color: dark
                          ? AppThemeData.grey400
                          : AppThemeData.grey500),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _queryCtrl,
                      focusNode: _focusNode,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      maxLength: 100,
                      buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                      style: TextStyle(
                        fontSize: 15,
                        fontFamily: AppThemeData.regular,
                        color: dark
                            ? AppThemeData.grey50
                            : AppThemeData.grey900,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText:
                            'Restaurants, cuisines, dishes...'.tr(),
                        hintStyle: TextStyle(
                          fontSize: 14,
                          fontFamily: AppThemeData.regular,
                          color: dark
                              ? AppThemeData.grey500
                              : AppThemeData.grey400,
                        ),
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: _onChanged,
                      onSubmitted: _onSubmit,
                    ),
                  ),
                  if (_query.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _queryCtrl.clear();
                        _onChanged('');
                        _focusNode.requestFocus();
                      },
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10),
                        child: Icon(Icons.close_rounded,
                            size: 18,
                            color: dark
                                ? AppThemeData.grey400
                                : AppThemeData.grey500),
                      ),
                    )
                  else
                    const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmptyState(bool dark) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Recent searches ─────────────────────────────────────────────
          if (_recentSearches.isNotEmpty) ...[
            _sectionHeader(
              dark,
              'Recent',
              action: GestureDetector(
                onTap: _clearAllRecent,
                child: Text(
                  'Clear all',
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: AppThemeData.medium,
                    color: AppThemeData.primary500,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children:
                    _recentSearches.map((q) => _recentTile(q, dark)).toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // ── Trending chips ──────────────────────────────────────────────
          if (_trending.isNotEmpty) ...[
            _sectionHeader(dark, 'Trending'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    _trending.map((t) => _trendingChip(t, dark)).toList(),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // ── Recommended open restaurants ────────────────────────────────
          if (_recommended.isNotEmpty) ...[
            _sectionHeader(dark, 'Recommended for You'),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding:
                  const EdgeInsets.fromLTRB(16, 0, 16, 0),
              itemCount: _recommended.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) =>
                  _vendorCard(_recommended[i], dark),
            ),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ── Results ───────────────────────────────────────────────────────────────

  Widget _buildResults(bool dark) {
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: dark ? AppThemeData.grey700 : AppThemeData.grey300,
            ),
            const SizedBox(height: 16),
            Text(
              'No results for "$_query"',
              style: TextStyle(
                fontSize: 16,
                fontFamily: AppThemeData.medium,
                color: dark ? AppThemeData.grey400 : AppThemeData.grey600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different keyword or cuisine',
              style: TextStyle(
                fontSize: 13,
                fontFamily: AppThemeData.regular,
                color: dark ? AppThemeData.grey600 : AppThemeData.grey400,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      itemCount: _results.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${_results.length} result${_results.length == 1 ? '' : 's'}'
              ' for "$_query"',
              style: TextStyle(
                fontSize: 13,
                fontFamily: AppThemeData.medium,
                color: dark ? AppThemeData.grey400 : AppThemeData.grey500,
              ),
            ),
          );
        }
        final v = _results[i - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _vendorCard(v, dark),
        );
      },
    );
  }

  // ── Shared components ─────────────────────────────────────────────────────

  Widget _sectionHeader(bool dark, String title, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.tr(),
              style: TextStyle(
                fontSize: 17,
                fontFamily: AppThemeData.bold,
                color: dark ? AppThemeData.grey50 : AppThemeData.grey900,
              ),
            ),
          ),
          if (action != null) action,
        ],
      ),
    );
  }

  Widget _recentTile(String q, bool dark) {
    return InkWell(
      onTap: () => _applyQuery(q),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Icon(Icons.history_rounded,
                size: 18,
                color:
                    dark ? AppThemeData.grey500 : AppThemeData.grey400),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                q,
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: AppThemeData.regular,
                  color: dark
                      ? AppThemeData.grey200
                      : AppThemeData.grey700,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => _removeRecent(q),
              child: Icon(Icons.close_rounded,
                  size: 16,
                  color: dark
                      ? AppThemeData.grey600
                      : AppThemeData.grey400),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trendingChip(String label, bool dark) {
    return GestureDetector(
      onTap: () => _applyQuery(label),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: dark ? AppThemeData.grey800 : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: dark ? AppThemeData.grey700 : AppThemeData.grey200,
          ),
          boxShadow: dark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.trending_up_rounded,
                size: 14, color: AppThemeData.primary500),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontFamily: AppThemeData.medium,
                color: dark
                    ? AppThemeData.grey200
                    : AppThemeData.grey700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vendorCard(VendorModel v, bool dark) {
    final isOpen = v.isAcceptingOrders;
    final rating = _rating(v);
    final dist = _distanceLabel(v);
    final statusLabel = isOpen ? 'Open' : _nextOpeningLabel(v);

    return GestureDetector(
      onTap: () {
        final q = _query.trim().isNotEmpty ? _query.trim() : v.title;
        _addRecent(q);
        // Session-end tracking trigger #3: tapping through to a restaurant
        // is the strongest possible signal that the current query is
        // "done" - track it immediately rather than waiting on focus loss/
        // dispose, which may be delayed if this screen stays underneath the
        // pushed route. Only when the customer actually typed something -
        // don't fabricate a search keyword out of v.title for a plain
        // browse-the-recommended-list tap.
        if (_query.trim().isNotEmpty) _trackIfNew(_query);
        // Only an actual search-tier match counts as "selected from
        // search" - a card from _recommended (not a search result at all)
        // has no entry in _tierByVendorId and correctly fires nothing here.
        final tier = _tierByVendorId[v.id];
        if (tier == 'cuisine') {
          BehaviorTracker.track(kEvtRestaurantSelectedFromCuisineSearch,
              {'vendorId': v.id, 'query': _normalizeSearchText(_query)});
        } else if (tier != null) {
          BehaviorTracker.track(kEvtRestaurantSelectedFromSearch,
              {'vendorId': v.id, 'query': _normalizeSearchText(_query), 'tier': tier});
        }
        // Search Conversion context (Phase 2, 2026-07-24) - entry source +
        // search keyword/type consumed by the destination screen's
        // startRestaurantSession() call, so the resulting
        // restaurantEngagement doc can answer "search -> restaurant ->
        // order/exit/long-browsing/cart-abandonment" without a second
        // collection (see BehaviorTracker's own doc comment). tier=='name'
        // is a restaurant-name match; 'cuisine' is a cuisine match;
        // 'category'/'dish' are both product-level matches, folded into
        // 'Product' - the spec's own three-way split (Restaurant/Cuisine/
        // Product) doesn't distinguish a matched category from a matched
        // dish name, and neither does this.
        //
        // Guarded by the same tier != null check as the track() calls
        // above - a _recommended-list tap (tier == null) must leave
        // whatever entry source/search context was already pending
        // untouched, not overwrite it with a fabricated 'Search'/'Product'
        // label. Before this guard, ANY tap on this card - recommended or
        // not - stamped the next restaurant visit as entrySource: 'Search'
        // with an empty searchKeyword, since the ternaries below default
        // to 'Search'/'Product' even when tier is null.
        if (tier != null) {
          BehaviorTracker.setNextEntrySource(tier == 'cuisine' ? 'Cuisine' : 'Search');
          BehaviorTracker.setNextSearchContext(
            _normalizeSearchText(_query),
            tier == 'name' ? 'Restaurant' : (tier == 'cuisine' ? 'Cuisine' : 'Product'),
          );
        }
        precacheVendorHeroImage(context, v);
        push(context, NewVendorProductsScreen(vendorModel: v));
      },
      child: Container(
        decoration: BoxDecoration(
          color: dark ? AppThemeData.grey900 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Logo ──────────────────────────────────────────────────────
            // photos[0] is the square logo — use BoxFit.contain so it is
            // never cropped, with a neutral background behind any whitespace.
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(
                  isOpen
                      ? Colors.transparent
                      : Colors.grey.withValues(alpha: 0.4),
                  BlendMode.saturation,
                ),
                child: Container(
                  width: 100,
                  height: 100,
                  color: dark ? AppThemeData.grey800 : AppThemeData.grey100,
                  // LazyNetworkImage (2026-09-11) - this card is also used by
                  // the "Recommended for You" list in _buildEmptyState, which
                  // is shrinkWrap + NeverScrollableScrollPhysics nested inside
                  // a SingleChildScrollView (so it can report an intrinsic
                  // height), forcing all 10 recommended vendors to build up
                  // front and fire a logo fetch on search-screen open
                  // regardless of what's actually visible. Gating on real
                  // scroll visibility here costs nothing for this card's
                  // OTHER use in _buildResults' already-lazy ListView.builder
                  // (it becomes visible immediately there either way).
                  child: LazyNetworkImage(
                    cacheKey: 'search_vendor_${v.id}',
                    width: 100,
                    height: 100,
                    builder: (context) => CachedNetworkImage(
                      imageUrl: _logoUrl(v),
                      width: 100,
                      height: 100,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(AppThemeData.primary500),
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Center(
                        child: Icon(Icons.store_rounded,
                            size: 40, color: AppThemeData.grey400),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // ── Info ──────────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      v.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontFamily: AppThemeData.bold,
                        color: dark
                            ? AppThemeData.grey50
                            : const Color(0xFF111111),
                      ),
                    ),
                    const SizedBox(height: 3),
                    // Cuisine tag - prefer the real cuisineNames selection;
                    // fall back to the legacy categoryTitle only for a
                    // restaurant that hasn't set its cuisines yet.
                    if (v.cuisineNames.isNotEmpty || v.categoryTitle.isNotEmpty)
                      Text(
                        v.cuisineNames.isNotEmpty
                            ? v.cuisineNames.join(' · ')
                            : v.categoryTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: AppThemeData.regular,
                          color: dark
                              ? AppThemeData.grey400
                              : AppThemeData.grey500,
                        ),
                      ),
                    const SizedBox(height: 6),
                    // Rating · reviews · distance
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: Color(0xFFFBBC05), size: 13),
                        const SizedBox(width: 3),
                        Text(
                          rating,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: AppThemeData.semiBold,
                            color: dark
                                ? AppThemeData.grey300
                                : const Color(0xFF333333),
                          ),
                        ),
                        Text(
                          ' · ${v.reviewsCount} reviews',
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: AppThemeData.regular,
                            color: dark
                                ? AppThemeData.grey500
                                : AppThemeData.grey400,
                          ),
                        ),
                        if (dist.isNotEmpty) ...[
                          Text(
                            ' · $dist',
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: AppThemeData.regular,
                              color: dark
                                  ? AppThemeData.grey500
                                  : AppThemeData.grey400,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 7),
                    // Status badge
                    _statusBadge(isOpen, statusLabel, dark),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(bool isOpen, String label, bool dark) {
    final Color bg;
    final Color fg;
    final Widget icon;

    if (isOpen) {
      bg = const Color(0xFFECFDF5);
      fg = const Color(0xFF16A34A);
      icon = Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: Color(0xFF16A34A),
          shape: BoxShape.circle,
        ),
      );
    } else if (label == 'Temporarily unavailable') {
      bg = dark ? AppThemeData.grey800 : AppThemeData.grey100;
      fg = dark ? AppThemeData.grey400 : AppThemeData.grey500;
      icon = Icon(Icons.pause_circle_outline_rounded, size: 12, color: fg);
    } else {
      // "Opens today/tomorrow/X at HH:MM"
      bg = const Color(0xFFFFFBEB);
      fg = const Color(0xFFD97706);
      icon = Icon(Icons.access_time_rounded, size: 12, color: fg);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                fontFamily: AppThemeData.semiBold,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required bool dark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dark ? AppThemeData.grey700 : AppThemeData.grey100,
        ),
        child: Icon(icon,
            size: 20,
            color: dark ? AppThemeData.grey200 : AppThemeData.grey700),
      ),
    );
  }
}
