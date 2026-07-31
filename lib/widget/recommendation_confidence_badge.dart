import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/recommendation/recommendation_engine.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';

// The green recommendation-confidence bar shown on every product card - see
// RecommendationEngine.recommendationConfidenceScores for the score/label
// this renders. Returns nothing at all when [confidence] is null (below
// RecommendationEngine.minimumRecommendationConfidence, or no signal for
// this product) - never a faint/weak indicator, per explicit product
// direction ("do not display a weak recommendation indicator for every
// product").
class RecommendationConfidenceBadge extends StatelessWidget {
  final ProductRecommendationConfidence? confidence;
  // Grid cards (128px wide) need a tighter, single-line pill; the main
  // menu's wide list row has room for a slightly larger one.
  final bool compact;

  const RecommendationConfidenceBadge({
    Key? key,
    required this.confidence,
    this.compact = false,
  }) : super(key: key);

  static const Map<RecommendationLabel, String> _text = {
    // Customer-facing text only (2026-07-23 rename) - the enum value stays
    // mostOrdered internally (ranking/allocation code, tests, Firestore
    // schema all untouched) so this is a pure display-layer change.
    RecommendationLabel.mostOrdered: 'Trending',
    RecommendationLabel.matchesYourTaste: 'Matches Your Taste',
    RecommendationLabel.basedOnSearches: 'Based on Your Searches',
    RecommendationLabel.fitsYourBudget: 'Great Value',
    RecommendationLabel.worthTrying: 'Worth Trying',
    RecommendationLabel.hiddenGem: 'Hidden Gem',
    RecommendationLabel.popularChoice: 'Popular Choice',
  };

  @override
  Widget build(BuildContext context) {
    final c = confidence;
    if (c == null) return const SizedBox.shrink();
    // fitsYourBudget/"Great Value" can no longer be the dominant label at
    // all (see recommendationConfidenceScores' consider() calls, revised
    // 2026-07-20) - it's excluded from the label vote entirely now rather
    // than being selected and then hidden here, so there's nothing left for
    // this widget to special-case for that label.
    final isDark = isDarkMode(context);

    // UI-ONLY display mapping (2026-07-23) - Trending/Popular Choice have
    // already cleared the restaurant-confidence gate, Business Context
    // grouping, badge allocation, and ranking by the time they reach this
    // widget, so a real confidence of e.g. 8% doesn't mean "barely
    // qualifies" - it just means this product's SHARE of total recent
    // orders is small on a menu with many products, even though it's
    // already one of the restaurant's strongest sellers. Compressing the
    // displayed range to 40-100% (instead of 0-100%) avoids that bar
    // reading as "weak" for an already-selective badge. Monotonic, so
    // relative ordering between products is unchanged.
    //
    // Deliberately confined to this widget, and only for these two labels -
    // recommendationConfidenceScores/Firestore/analytics/every other label
    // (matchesYourTaste, hiddenGem, etc.) keep the real, untransformed
    // score. c.score itself is NEVER mutated - only a local display copy.
    final isTrendingOrPopular = c.label == RecommendationLabel.mostOrdered ||
        c.label == RecommendationLabel.popularChoice;
    final realScore = c.score.clamp(0.0, 1.0);
    final displayScore =
        isTrendingOrPopular ? (0.40 + realScore * 0.60).clamp(0.40, 1.0) : realScore;

    // Fill intensity scales with confidence - a pill that's barely past the
    // minimum-confidence floor still reads as visibly lighter than one at
    // full confidence, without ever going all the way to "empty". A richer,
    // more saturated green than the previous version - reads as a deliberate
    // "trust meter" chip rather than a faint line, closer to the reference
    // (Zomato's "Highly reordered" pill) this was compared against.
    final green = Color.lerp(
      isDark ? const Color(0xFF43A047) : const Color(0xFF81C784),
      isDark ? const Color(0xFF00E676) : const Color(0xFF1B5E20),
      displayScore,
    )!;
    final trackColor =
        isDark ? Colors.white.withOpacity(0.10) : AppThemeData.grey200;

    // Zomato-style: a chunky, rounded pill INLINE before the label, not a
    // thin underline beneath it (2026-07-18 redesign - the original 3px
    // hairline read as an afterthought rather than a confidence meter).
    // Widened again same day - the first pass (22/28px) was still too
    // short to actually read as a meter at a glance; this is deliberately
    // the dominant visual element of the badge, wider than the label text
    // gets in most cases, so the confidence LEVEL is what registers first.
    final pillWidth = compact ? 46.0 : 64.0;
    final pillHeight = compact ? 6.0 : 8.0;

    return Padding(
      // Bottom padding widened slightly (was 0 for the non-compact list
      // card) now that the pill is taller - gives it room to breathe
      // against the price row directly below instead of crowding it.
      padding: EdgeInsets.only(top: compact ? 4 : 6, bottom: compact ? 3 : 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(pillHeight / 2),
            child: SizedBox(
              height: pillHeight,
              width: pillWidth,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
                    Container(color: trackColor),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: constraints.maxWidth * displayScore,
                        decoration: BoxDecoration(color: green),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: compact ? 5 : 8),
          Flexible(
            child: Text(
              (_text[c.label] ?? '').tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 9.5 : 11,
                fontWeight: FontWeight.w600,
                fontFamily: AppThemeData.medium,
                color: isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
