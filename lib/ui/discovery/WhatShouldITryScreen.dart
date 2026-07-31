import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/recommendation/recommendation_engine.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/utils/network_image_widget.dart';
import 'package:emartconsumer/widget/recommendation_confidence_badge.dart';
import 'package:flutter/material.dart';

// Phase 2 recommendation engine (2026-07-17) - "What Should I Try?"
// discovery page. Scoped to ONE restaurant (launched from
// newVendorProductsScreen's app bar, which passes its already-computed
// RestaurantRecommendationContext via the constructor - no re-fetch here,
// pure presentational reuse of the same RecommendationEngine calls the
// restaurant page itself uses). Deliberately read-only: tapping a card
// returns to the restaurant menu rather than duplicating that screen's
// variant/wallet/vendor-switch add-to-cart handling for what's meant to be
// a lightweight browsing aid, not a second ordering flow.
//
// Every section here is fully automatic/data-driven - Vendor Featured was
// removed entirely (2026-07-17) per explicit product direction to keep the
// recommendation system 100% data-driven with no vendor configuration
// anywhere. See RECOMMENDATION_SYSTEM_ARCHITECTURE.html Section 12.
//
// Sparkle screen redesign (2026-07-23) - Restaurant Must Try was removed
// from THIS screen only (still fully intact everywhere else - Recommended
// For You/Explore/RecommendationEngine.topBySource('mustTry') itself are
// all untouched). Exactly 3 sections remain, in a fixed order, treated as
// ONE all-or-nothing group (see build() below): Based on Your Taste ->
// Most Loved Here -> Hidden Gems. Products are deduplicated across all
// three in that priority order via a single in-memory Set, and if any one
// section ends up empty after dedup, the entire group is hidden rather
// than showing a partial page.
class WhatShouldITryScreen extends StatelessWidget {
  final RestaurantRecommendationContext recoContext;
  // Computed once by the parent (newVendorProductsScreen's _loadRecoContext)
  // and passed through here, same pattern as recoContext itself - never
  // recomputed on this screen.
  final Map<String, ProductRecommendationConfidence> confidenceScores;

  const WhatShouldITryScreen({
    Key? key,
    required this.recoContext,
    this.confidenceScores = const {},
  }) : super(key: key);

  // Delegates to RecommendationEngine.mostLovedHere (2026-07-19 -
  // consolidated from a locally-duplicated raw-sales sort, shared with
  // newVendorProductsScreen._mostLovedHereProducts, into one function so
  // the two screens can never drift again; now also Business-Context-aware).
  List<ProductModel> _mostLoved() => RecommendationEngine.mostLovedHere(recoContext,
      limit: RecommendationEngine.defaultSectionLimit);

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkMode(context);

    // Small-menu rule (2026-07-18): this whole page adds nothing once a
    // customer can already see the entire menu at a glance - every section
    // below is empty regardless of underlying data.
    if (!RecommendationEngine.hasEnoughProductsForSections(recoContext)) {
      return Scaffold(
        backgroundColor: isDark ? AppThemeData.grey900 : AppThemeData.grey50,
        appBar: AppBar(
          title: Text('What Should I Try?'.tr()),
          backgroundColor: isDark ? AppThemeData.grey900 : Colors.white,
          foregroundColor: isDark ? AppThemeData.grey50 : AppThemeData.grey900,
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              "We're still learning this menu — check back soon!".tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? AppThemeData.grey400 : AppThemeData.grey600,
              ),
            ),
          ),
        ),
      );
    }

    // Sparkle screen recommendation group (2026-07-23 redesign) - exactly
    // 3 sections now (Restaurant Must Try removed from THIS screen only;
    // RecommendationEngine.topBySource(ctx,'mustTry') itself is untouched
    // and still feeds Recommended For You/Explore/Hidden Gems' backfill
    // below, same computation, zero duplication). Fixed order, never
    // reordered: Based on Your Taste -> Most Loved Here -> Hidden Gems.
    //
    // Duplicate prevention: a single in-memory `shown` Set, built up in
    // priority order (Taste first, reserved; then Most Loved Here,
    // filtered against Taste and reserved; then Hidden Gems, filtered
    // against both). O(n) - each section's already-ranked, already-scored
    // list (topBySource/mostLovedHere/hiddenGems all pure reads of
    // already-loaded recoContext data, zero new Firestore reads, zero new
    // scoring) is walked once with O(1) Set lookups.
    final shown = <String>{};

    final taste = RecommendationEngine.topBySource(recoContext, 'preference',
            n: RecommendationEngine.defaultSectionLimit,
            categoryFirst: true,
            businessContextBoost: true)
        .where((p) => !shown.contains(p.id))
        .toList();
    shown.addAll(taste.map((p) => p.id));

    final mostLoved = _mostLoved().where((p) => !shown.contains(p.id)).toList();
    shown.addAll(mostLoved.map((p) => p.id));

    // Hidden Gems: real hiddenGems() output first, filtered against both
    // earlier sections. If that alone doesn't fill the section, backfill
    // with Restaurant Specialities (topBySource 'mustTry', the same
    // source and ranking Restaurant Must Try always used) as "a few
    // Restaurant Specialities products" per the discovery-and-uniqueness
    // rule - filtered against `shown` AND against the real gems already
    // chosen, so nothing already displayed anywhere on this screen can
    // reappear here.
    final realGems = RecommendationEngine.hiddenGems(recoContext,
            n: RecommendationEngine.defaultSectionLimit)
        .where((p) => !shown.contains(p.id))
        .toList();
    final hiddenGems = List<ProductModel>.of(realGems);
    if (hiddenGems.length < RecommendationEngine.defaultSectionLimit) {
      final gemIds = realGems.map((p) => p.id).toSet();
      final specialityFill = RecommendationEngine.topBySource(
              recoContext, 'mustTry', n: RecommendationEngine.defaultSectionLimit)
          .where((p) => !shown.contains(p.id) && !gemIds.contains(p.id))
          .take(RecommendationEngine.defaultSectionLimit - hiddenGems.length);
      hiddenGems.addAll(specialityFill);
    }
    shown.addAll(hiddenGems.map((p) => p.id));

    // Partial-group visibility (2026-07-23, revised - reverses the earlier
    // all-or-nothing rule): show whichever of the 3 sections actually have
    // real results, in the same fixed order, rather than hiding the whole
    // group just because one section came up empty. Only hides entirely
    // when ALL THREE are empty (nothing at all to show).
    final visibleSections = <MapEntry<String, List<ProductModel>>>[
      if (taste.isNotEmpty) MapEntry('❤️ ' + 'Based On Your Taste'.tr(), taste),
      if (mostLoved.isNotEmpty) MapEntry('🔥 ' + 'Most Loved By Customers'.tr(), mostLoved),
      if (hiddenGems.isNotEmpty) MapEntry('💎 ' + 'Hidden Gems'.tr(), hiddenGems),
    ];

    return Scaffold(
      backgroundColor: isDark ? AppThemeData.grey900 : AppThemeData.grey50,
      appBar: AppBar(
        title: Text('What Should I Try?'.tr()),
        backgroundColor: isDark ? AppThemeData.grey900 : Colors.white,
        foregroundColor: isDark ? AppThemeData.grey50 : AppThemeData.grey900,
        // Explicit iconTheme/titleTextStyle (2026-07-23 fix) - Styles.dart's
        // GLOBAL light-mode AppBarTheme hardcodes both to Colors.white (every
        // other screen uses a colored primary app bar, where that's correct).
        // Flutter resolves AppBar.iconTheme/titleTextStyle from the WIDGET
        // first, then the THEME, and only falls back to a color derived from
        // foregroundColor last - so without these, the global white theme
        // silently wins over foregroundColor above, rendering the back
        // button (and title) white-on-white on this screen's white app bar.
        iconTheme: IconThemeData(color: isDark ? AppThemeData.grey50 : AppThemeData.grey900),
        titleTextStyle: TextStyle(
          color: isDark ? AppThemeData.grey50 : AppThemeData.grey900,
          fontFamily: AppThemeData.semiBold,
          fontSize: 18,
        ),
        elevation: 0,
      ),
      body: visibleSections.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  "We're still learning this menu — check back soon!".tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? AppThemeData.grey400 : AppThemeData.grey600,
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                for (final section in visibleSections)
                  _DiscoverySection(
                    title: section.key,
                    products: section.value,
                    confidenceScores: confidenceScores,
                  ),
                // Partial-state note (2026-07-23) - shown at the BOTTOM,
                // below whatever section(s) ARE visible, only when fewer
                // than all 3 are showing (1 or 2). Never replaces the
                // visible sections - just tells the customer more is
                // coming, rather than silently looking incomplete.
                if (visibleSections.length < 3)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                    child: Text(
                      "We're still learning this menu and your preferences — check back soon!"
                          .tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isDark ? AppThemeData.grey400 : AppThemeData.grey600,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _DiscoverySection extends StatelessWidget {
  final String title;
  final List<ProductModel> products;
  final Map<String, ProductRecommendationConfidence> confidenceScores;

  const _DiscoverySection({
    required this.title,
    required this.products,
    required this.confidenceScores,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkMode(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              title,
              style: TextStyle(
                fontFamily: AppThemeData.bold,
                fontSize: 18,
                color: isDark ? AppThemeData.grey50 : AppThemeData.grey900,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            // 225 (2026-07-20, was 194) - scaled to match
            // _DiscoveryProductCard's own ~15% size increase (128->148 wide,
            // 95->109 image height), same bump newVendorProductsScreen's
            // _buildRecoProductCard got, so this screen's cards match the
            // menu's text size instead of looking smaller/inconsistent.
            height: 225,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.only(left: 16),
              itemCount: products.length,
              itemBuilder: (context, index) => Padding(
                key: ValueKey(products[index].id),
                padding: const EdgeInsets.only(right: 14),
                child: _DiscoveryProductCard(
                  product: products[index],
                  confidence: confidenceScores[products[index].id],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoveryProductCard extends StatelessWidget {
  final ProductModel product;
  final ProductRecommendationConfidence? confidence;
  const _DiscoveryProductCard({required this.product, this.confidence});

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkMode(context);
    final price = productCommissionPrice(product.price.toString());
    final disPriceRaw = double.tryParse(product.disPrice.toString()) ?? 0;
    final disPrice = disPriceRaw > 0
        ? productCommissionPrice(product.disPrice.toString())
        : null;
    // No per-product rating badge - ProductModel.reviewsCount/reviewsSum do
    // not represent real per-product ratings (see recommendation_engine.dart's
    // file header: a single order-level rating gets written to only the
    // first product in that order). Showing it here would be exactly the
    // "fake product rating" this whole redesign exists to eliminate.

    // No card box (2026-07-18) - matches the same flattening applied to
    // newVendorProductsScreen's _buildRecoProductCard, see its comment.
    // Sized up 15% (2026-07-20, was 128 wide/95 image/12px text) to match
    // that same card's later size increase - kept in sync since both
    // screens deliberately duplicate this card design.
    return GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      child: SizedBox(
        width: 148,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: NetworkImageWidget(
                imageUrl: getImageVAlidUrl(product.photo),
                height: 109,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 7, 9, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppThemeData.grey900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  disPrice == null
                      ? Text(
                          amountShow(amount: price),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppThemeData.grey300
                                : AppThemeData.grey700,
                          ),
                        )
                      : Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          children: [
                            Text(
                              amountShow(amount: disPrice),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppThemeData.primary500,
                              ),
                            ),
                            Text(
                              amountShow(amount: price),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppThemeData.grey400
                                    : AppThemeData.grey500,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ],
                        ),
                  RecommendationConfidenceBadge(
                    confidence: confidence,
                    compact: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
