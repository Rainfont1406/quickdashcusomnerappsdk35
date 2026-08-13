import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/LocalOfferModel.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

// Offer detail / "gate pass"-style view for one Offers & Discounts post -
// see LocalOffersListScreen's own header comment for the feature's overall
// scope. (2026-08-05) A business can have several action buttons
// (call/whatsapp/website/directions) - see offer.ctaButtons, rendered in
// admin-chosen order, first as filled/primary and the rest as outlined.
//
// (2026-08-07) Visual redesign: the content now sits in a rounded sheet that
// overlaps the banner's bottom edge (standard "card slides up over the
// photo" treatment) instead of plain text starting flush below a hard-cut
// image, the primary offer is a gradient hero card instead of a flat pale
// box, and Valid Till/Timings are side-by-side compact chips instead of
// full-width rows separated by dividers - the old layout read as sparse/
// empty because most of its vertical space was a single icon-sized line per
// fact. The dead location-icon row (rendered an icon with no text next to
// it - categoryId was never resolved to a name) is removed entirely.
class LocalOfferDetailsScreen extends StatefulWidget {
  final LocalOfferModel offer;

  const LocalOfferDetailsScreen({Key? key, required this.offer}) : super(key: key);

  @override
  State<LocalOfferDetailsScreen> createState() => _LocalOfferDetailsScreenState();
}

class _LocalOfferDetailsScreenState extends State<LocalOfferDetailsScreen> {
  static const double _bannerHeight = 250;
  // How far the rounded content sheet rides up over the banner's bottom
  // edge. Kept small (was 26) - banner images are admin-uploaded posters
  // with real text/content spread across their full height (e.g. "All
  // Medicines" callouts near the bottom), so a large overlap was hiding
  // part of the actual image rather than just a safe empty margin.
  static const double _sheetOverlap = 10;

  final PageController _bannerController = PageController();
  int _bannerPage = 0;

  @override
  void dispose() {
    _bannerController.dispose();
    super.dispose();
  }

  Future<void> _launch(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _onCtaButtonTap(CtaButton button) async {
    switch (button.ctaType) {
      case 'directions':
      case 'website':
        await _launch(button.ctaValue);
        break;
      case 'call':
        await _launch('tel:${button.ctaValue}');
        break;
      case 'whatsapp':
        await _launch('https://wa.me/${button.ctaValue}');
        break;
      default:
        await _launch(button.ctaValue);
        break;
    }
  }

  // (2026-08-07) Returns the FINAL display string, already translated where
  // needed - callers must not call .tr() on the result again. Needed because
  // a multi-branch business's label (admin-typed branch name + computed
  // distance, e.g. "Andheri West · 1.1 km") is dynamic text that must never
  // be run through .tr() (would just fail the lookup and fall back anyway,
  // but is semantically wrong - see easy_localization's own key-not-found
  // warnings for why untranslatable strings shouldn't go through .tr()).
  // [distanceKm] is only ever passed for a directions button that's one of
  // several branches (see _visibleCtaButtons) - a business's single location
  // never shows a distance here, only the plain label.
  // (2026-08-07) Multi-branch support: when a business has more than one
  // "directions" button, each one is a separate physical location (see
  // CtaButton.label/resolvedLocation, set per-button in the admin panel).
  // Branches beyond LocalOfferModel.maxBranchDistanceKm are dropped from
  // this list entirely rather than just ranked lower - a branch 200km away
  // isn't a useful result to show. A single directions button (by far the
  // common case) is never touched by this - the distance cap only applies
  // once there's more than one to choose between. If the user's live
  // location isn't available yet, falls back to every button unfiltered/
  // unsorted with no distances, same as this screen behaved before branches
  // existed.
  (List<CtaButton>, Map<CtaButton, double>) _visibleCtaButtons(LocalOfferModel offer) {
    final directionsButtons = offer.ctaButtons.where((b) => b.ctaType == 'directions').toList();
    if (directionsButtons.length <= 1) return (offer.ctaButtons, {});

    final userLoc = MyAppState.selectedPosotion.location;
    if (userLoc == null) return (offer.ctaButtons, {});

    final distances = <CtaButton, double>{};
    for (final b in directionsButtons) {
      final loc = b.resolvedLocation;
      if (loc == null) continue;
      final km = Geolocator.distanceBetween(loc.latitude, loc.longitude, userLoc.latitude, userLoc.longitude) / 1000;
      if (km <= LocalOfferModel.maxBranchDistanceKm) distances[b] = km;
    }

    final visibleDirections = directionsButtons.where((b) => distances.containsKey(b)).toList()
      ..sort((a, b) => distances[a]!.compareTo(distances[b]!));
    final others = offer.ctaButtons.where((b) => b.ctaType != 'directions').toList();
    return ([...others, ...visibleDirections], distances);
  }

  String _ctaLabelFor(CtaButton button, {double? distanceKm}) {
    switch (button.ctaType) {
      case 'directions':
        final label = (button.label ?? '').trim();
        final base = label.isNotEmpty ? label : 'View Location'.tr();
        return distanceKm != null ? '$base · ${distanceKm.toStringAsFixed(1)} km' : base;
      case 'call':
        return 'Call Now'.tr();
      case 'whatsapp':
        return 'WhatsApp'.tr();
      case 'website':
      default:
        return 'Visit Website'.tr();
    }
  }

  IconData _ctaIconFor(CtaButton button) {
    switch (button.ctaType) {
      case 'directions':
        return Icons.near_me_rounded;
      case 'call':
        return Icons.call_rounded;
      case 'whatsapp':
        return Icons.chat_rounded;
      case 'website':
      default:
        return Icons.language_rounded;
    }
  }

  // Shorter than _ctaLabelFor's full label ("View Location" -> "Location")
  // - used only under the compact quick-action circles, which don't have
  // room for the longer phrasing without wrapping or ellipsis-clipping.
  // Same "already-translated, don't .tr() the result" contract as
  // _ctaLabelFor above.
  String _ctaShortLabelFor(CtaButton button, {double? distanceKm}) {
    switch (button.ctaType) {
      case 'directions':
        final label = (button.label ?? '').trim();
        final base = label.isNotEmpty ? label : 'Location'.tr();
        return distanceKm != null ? '$base · ${distanceKm.toStringAsFixed(1)} km' : base;
      case 'call':
        return 'Call'.tr();
      case 'whatsapp':
        return 'WhatsApp'.tr();
      case 'website':
      default:
        return 'Website'.tr();
    }
  }

  // (2026-08-07) Gradient fill (matching the hero card) + border + colored
  // shadow instead of a flat solid-color ElevatedButton - ElevatedButton's
  // own styleFrom only takes a single flat backgroundColor, so this needs
  // its own Container/InkWell to get the gradient, same premium depth
  // treatment as everything else on this screen.
  Widget _buildSingleCtaButton(CtaButton button, {double? distanceKm}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onCtaButtonTap(button),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppThemeData.primary500, AppThemeData.primary700],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppThemeData.primary700, width: 1),
            boxShadow: [
              BoxShadow(
                  color: AppThemeData.primary500.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 6)),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_ctaIconFor(button), color: Colors.white),
              const SizedBox(width: 8),
              Text(_ctaLabelFor(button, distanceKm: distanceKm),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }

  // (2026-08-07) Rectangular 2-column card grid instead of a circular
  // icon row - each button gets its own accent color from the same
  // rotating palette the offer cards use (border + tinted fill + colored
  // shadow + icon chip), instead of one purple "primary" button and every
  // other button looking identical in plain white/grey. Reads as a proper
  // set of distinct actions rather than a repeated template.
  Widget _buildCtaQuickActionsRow(List<CtaButton> buttons, Map<CtaButton, double> distances) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: buttons.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2.3,
      ),
      itemBuilder: (context, i) => _buildCtaCard(buttons[i], i, distanceKm: distances[buttons[i]]),
    );
  }

  Widget _buildCtaCard(CtaButton button, int index, {double? distanceKm}) {
    final accent = _headingAccentPalette[index % _headingAccentPalette.length];
    return InkWell(
      onTap: () => _onCtaButtonTap(button),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.4), width: 1.3),
          boxShadow: [
            BoxShadow(color: accent.withValues(alpha: 0.22), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
              child: Icon(_ctaIconFor(button), size: 17, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              // (2026-08-07) Matches the main list card's own distance-chip
              // font size (10) - a branch label + distance ("Location · 3.5
              // km") is longer than the plain "Call"/"Website" labels this
              // was originally sized for at 13, and was clipping with an
              // ellipsis before it could finish.
              child: Text(_ctaShortLabelFor(button, distanceKm: distanceKm),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 10, color: accent)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    final offer = widget.offer;
    final sheetColor = dark ? AppThemeData.darkBgSecondary : Colors.white;

    // (2026-08-07) Multiple headings now show together as a colorful grid
    // (see _buildOffersGrid) instead of one hero card + a plain list below -
    // each card carries its own validity countdown, so the Valid Till chip
    // below is single-offer only; Timings is a business-level fact and
    // still shows either way.
    // Based on what's actually still active/shown, not the raw posted
    // count - if only one heading is left active (the rest expired), the
    // customer should see the single-hero treatment, not a 1-card grid.
    final isMultiOffer = offer.activeOffers.length > 1;
    // Hero card (single-offer case only) shows offers[0]'s own validity,
    // falling back to the whole-offer date for headings that don't have
    // their own.
    final heroValidTill = offer.effectiveValidTillFor(offer.primary);
    final hasValidTill = !isMultiOffer && heroValidTill != null;
    final hasTimings = (offer.timings ?? '').isNotEmpty;
    final hasDescription = (offer.description ?? '').isNotEmpty;

    // (2026-08-03) SafeArea wraps the WHOLE body, not just the icon row -
    // previously only the icon row respected the status bar inset, so the
    // banner image itself was drawn starting at y=0 and rendered behind/
    // under the status bar (reported as the banner "overlapping with the
    // screen above it"). Now the banner starts below the status bar like
    // every other screen in the app.
    return Scaffold(
      backgroundColor: dark ? AppThemeData.darkBgPrimary : const Color(0xFFF2F0F8),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBanner(dark, offer),
              // Transform.translate pulls this sheet up over the banner's
              // bottom edge (paint-only, so it bypasses layout) - the rounded
              // corners + shadow then read as one elevated surface rather
              // than a hard photo/text cut. Neither Container.margin nor
              // Padding.padding can do this: both assert their inset is
              // non-negative and throw at build time otherwise. The unclaimed
              // layout space this leaves at the very bottom of the scroll
              // view is intentional - trivial and unnoticeable there.
              Transform.translate(
                offset: const Offset(0, -_sheetOverlap),
                child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: sheetColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(26),
                    topRight: Radius.circular(26),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: dark ? 0.28 : 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(offer.businessName ?? '',
                        style: TextStyle(
                            fontFamily: AppThemeData.bold,
                            fontSize: 22,
                            color: dark ? AppThemeData.darkTextPrimary : AppThemeData.grey900)),
                    const SizedBox(height: 16),
                    if (isMultiOffer) _buildOffersGrid(dark, offer) else _buildHeroOfferCard(offer),
                    if (hasValidTill || hasTimings) ...[
                      const SizedBox(height: 14),
                      _buildInfoChipsRow(dark, offer, hasValidTill ? heroValidTill : null, hasTimings),
                    ],
                    if (hasDescription) ...[
                      const SizedBox(height: 16),
                      _buildAboutCard(dark, offer),
                    ],
                    if (offer.ctaButtons.isNotEmpty) const SizedBox(height: 20),

                    // (2026-08-07) A single action button stays full-width
                    // and prominent (it's the only path to the business, so
                    // it should read as a primary CTA). Two or more switch
                    // to a compact icon-row "quick actions" strip (Call /
                    // WhatsApp / Website / Directions) instead of stacking
                    // full-width buttons - the same pattern Google Maps/
                    // Zomato business profiles use, and far more scannable
                    // than 3-4 rows of near-identical buttons. Multi-branch
                    // businesses go through _visibleCtaButtons first, which
                    // may drop far-away branches - so the visible count here
                    // can differ from offer.ctaButtons.length.
                    Builder(builder: (context) {
                      final (visibleButtons, distances) = _visibleCtaButtons(offer);
                      if (visibleButtons.length == 1) {
                        return _buildSingleCtaButton(visibleButtons.first, distanceKm: distances[visibleButtons.first]);
                      } else if (visibleButtons.length > 1) {
                        return _buildCtaQuickActionsRow(visibleButtons, distances);
                      }
                      return const SizedBox.shrink();
                    }),
                  ],
                ),
              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBanner(bool dark, LocalOfferModel offer) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // (2026-08-05) Up to 7 banner images now, swipeable - a single image
        // behaves exactly as before (PageView with one page just never
        // scrolls). Dot indicator only appears when there's more than one to
        // swipe between.
        offer.bannerImageUrls.isNotEmpty
            ? SizedBox(
                width: double.infinity,
                height: _bannerHeight,
                child: PageView.builder(
                  controller: _bannerController,
                  itemCount: offer.bannerImageUrls.length,
                  onPageChanged: (i) => setState(() => _bannerPage = i),
                  itemBuilder: (context, i) => CachedNetworkImage(
                    imageUrl: offer.bannerImageUrls[i],
                    width: double.infinity,
                    height: _bannerHeight,
                    fit: BoxFit.cover,
                    // (2026-08-03) Without these, a slow load or a failed
                    // fetch both rendered as nothing at all - reported as
                    // "banner/logo not visible".
                    placeholder: (context, url) => Container(
                      color: dark ? AppThemeData.darkBgTertiary : AppThemeData.grey200,
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: dark ? AppThemeData.darkBgTertiary : AppThemeData.grey200,
                      child: Icon(Icons.image_not_supported_outlined,
                          color: dark ? AppThemeData.grey400 : AppThemeData.grey500),
                    ),
                  ),
                ),
              )
            : Container(
                width: double.infinity,
                height: _bannerHeight,
                color: dark ? AppThemeData.darkBgTertiary : AppThemeData.grey200,
              ),
        // Soft bottom scrim so the photo eases into the content sheet
        // instead of the sheet's rounded edge cutting across it abruptly -
        // kept short and light so it doesn't wash out the actual image
        // content admins uploaded (was 100px tall / 0.30 alpha, dark enough
        // to obscure real text/callouts baked into the banner poster).
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 40,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.16)],
                ),
              ),
            ),
          ),
        ),
        if (offer.bannerImageUrls.length > 1)
          Positioned(
            // Lifted above the overlapping content sheet (_sheetOverlap) so
            // the dots stay visible instead of being covered by it.
            bottom: _sheetOverlap + 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(offer.bannerImageUrls.length, (i) {
                final active = i == _bannerPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? Colors.white : Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: _circleIconButton(Icons.arrow_back, () => Navigator.pop(context)),
        ),
      ],
    );
  }

  Widget _buildHeroOfferCard(LocalOfferModel offer) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppThemeData.primary500, AppThemeData.primary700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppThemeData.primary500.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Faint watermark for a bit of coupon-like texture instead of a
          // flat solid-color block.
          Positioned(
            right: -12,
            top: -18,
            child: Icon(Icons.local_offer_rounded, size: 100, color: Colors.white.withValues(alpha: 0.10)),
          ),
          Builder(builder: (context) {
            final badge = offer.effectiveBadgeTagFor(offer.primary);
            return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((badge ?? '').isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(badge!.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
                ),
              const SizedBox(height: 10),
              Text(offer.primary.discountText ?? '',
                  style: TextStyle(
                      fontFamily: AppThemeData.bold, fontSize: 28, color: Colors.white, height: 1.1)),
              if ((offer.primary.subHeadline ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(offer.primary.subHeadline!,
                    style: TextStyle(
                        fontFamily: AppThemeData.medium,
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.88))),
              ],
            ],
            );
          }),
        ],
      ),
    );
  }

  // (2026-08-07) Multiple headings render together as a 2-column grid of
  // bold accent-colored cards instead of one hero card + a plain list below
  // it - each card carries its own discount, subheadline, and validity
  // countdown so every offer this business has posted is visible at once.
  Widget _buildOffersGrid(bool dark, LocalOfferModel offer) {
    final active = offer.activeOffers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Active Offers (${active.length})'.tr(),
            style: TextStyle(
                fontFamily: AppThemeData.bold,
                fontSize: 16,
                color: dark ? AppThemeData.darkTextPrimary : AppThemeData.grey900)),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: active.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            // A fixed pixel height (previously 196) made these portrait-tall
            // regardless of column width - an aspect ratio keeps them the
            // flatter landscape rectangle shape actual reference cards use.
            // (2026-08-08) Raised from 0.92 - now that the divider sits tight
            // against its footer text (see _buildOfferGridCard), the old
            // ratio left real unused height at the bottom of the card rather
            // than just redistributing it - this shrinks the card itself to
            // match actual content instead of leaving that space behind.
            childAspectRatio: 1.15,
          ),
          itemBuilder: (context, i) => _buildOfferGridCard(offer, active[i], i),
        ),
      ],
    );
  }

  Widget _buildOfferGridCard(LocalOfferModel offer, LocalOfferHeading heading, int index) {
    final accent = _headingAccentPalette[index % _headingAccentPalette.length];
    final headingValidTill = offer.unambiguousValidTillFor(heading);
    final headingBadge = offer.effectiveBadgeTagFor(heading);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if ((headingBadge ?? '').isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(headingBadge!.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: AppThemeData.bold,
                          fontSize: 9,
                          color: accent,
                          letterSpacing: 0.3)),
                ),
                const SizedBox(height: 6),
              ],
              // Headline/subheadline sit in the left column with the dashed
              // "%" icon fixed to the right (Row, not a Stack overlay) - so a
              // 2-line headline never runs underneath and collides with it.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // (2026-08-07) Raised from 2/1 lines - a long
                        // headline was hitting the old cap and truncating
                        // with "..." while the card still had visible empty
                        // space below it before the divider/footer. Column's
                        // mainAxisSize.min still means a short headline
                        // doesn't force this taller than it needs to be -
                        // these are ceilings, not fixed allocations, so the
                        // subheadline still gets room to itself run 2 lines
                        // when the headline above it is short.
                        Text((heading.discountText ?? '').toUpperCase(),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontFamily: AppThemeData.bold,
                                fontSize: 14,
                                color: Colors.white,
                                height: 1.1)),
                        if ((heading.subHeadline ?? '').isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(heading.subHeadline!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontFamily: AppThemeData.medium,
                                  fontSize: 10,
                                  color: Colors.white.withValues(alpha: 0.9))),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  DottedBorder(
                    borderType: BorderType.Circle,
                    // (2026-08-07) A lightened tint of this card's own accent
                    // - not a black-blend, which read muddy sitting on top of
                    // an already-saturated card background. Lightening keeps
                    // it a clean, solid color that still visibly belongs to
                    // this card's own hue.
                    color: _tint(accent, 0.60),
                    strokeWidth: 1.3,
                    dashPattern: const [4, 3],
                    padding: const EdgeInsets.all(6),
                    child: Icon(_gridBadgeIconFor(heading.discountText), size: 14, color: _tint(accent, 0.60)),
                  ),
                ],
              ),
            ],
          ),
          // (2026-08-07) Divider + footer row grouped into their own tight
          // Column instead of sitting as two separate children of the outer
          // spaceBetween Column - spaceBetween was inserting a stretched gap
          // between every pair of children (top content <-> line, AND line
          // <-> footer text), which read as an oversized gap under the line
          // specifically. Grouping them means spaceBetween only sees two
          // blocks (top content, this footer block) and puts its one gap
          // between those - the line stays snug against its own footer text,
          // only the outer gap absorbs the leftover card height.
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Divider(color: Colors.white.withValues(alpha: 0.3), height: 12),
              Builder(builder: (context) {
                final urgent = headingValidTill != null &&
                    headingValidTill.toDate().difference(DateTime.now()).inDays <= _urgentDaysThreshold;
                final (label, icon) = headingValidTill != null
                    ? _formatGridValidity(headingValidTill)
                    : ('Available Now'.tr(), Icons.check_circle_outline_rounded);
                // (2026-08-08) Three-tier alert color instead of one flat
                // translucent-white treatment for every state - urgent
                // (<=7 days left) is red so it actually reads as an alert,
                // "Available Now" is green (a positive, nothing-to-worry-
                // about signal), and a dated-but-not-urgent heading stays
                // neutral (translucent white, matching the card's own
                // accent) - so red stays meaningful instead of every card
                // looking equally alarming.
                final Color chipColor = urgent
                    ? AppThemeData.danger300
                    : headingValidTill == null
                        ? AppThemeData.success400
                        : Colors.white.withValues(alpha: 0.20);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: chipColor, borderRadius: BorderRadius.circular(6)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 11, color: Colors.white),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontFamily: AppThemeData.medium, fontSize: 10, color: Colors.white)),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatValidTill(Timestamp ts) {
    final d = ts.toDate();
    return '${d.day}/${d.month}/${d.year}';
  }

  // discountText is deliberately free text, never assumed to be a
  // percentage ("50% OFF" and "Starting at ₹29" must both render as-is -
  // see LocalOfferHeading's own doc comment) - so the little icon in the
  // dashed circle is picked from what the headline actually says instead of
  // always showing "%", which would misrepresent a flat-amount or BOGO deal.
  static IconData _gridBadgeIconFor(String? discountText) {
    final text = (discountText ?? '').toLowerCase();
    if (text.contains('%')) return Icons.percent_rounded;
    if (text.contains('buy') && text.contains('get')) return Icons.card_giftcard_rounded;
    if (text.contains('₹') || text.contains('rs.') || text.contains('rs ')) {
      return Icons.currency_rupee_rounded;
    }
    if (text.contains('free')) return Icons.redeem_rounded;
    return Icons.local_offer_rounded;
  }

  // "X Days Remaining" instead of a bare date - a countdown reads more
  // urgent/premium than a plain expiry date, and matches the style used
  // elsewhere for time-limited deals.
  static String _formatDaysRemaining(Timestamp ts) {
    final days = ts.toDate().difference(DateTime.now()).inDays;
    if (days < 0) return 'Expired'.tr();
    if (days == 0) return 'Expires Today'.tr();
    if (days == 1) return '1 Day Remaining'.tr();
    return '$days ' + 'Days Remaining'.tr();
  }

  // (2026-08-08) Also drives the grid card's red alert chip (see
  // _buildOfferGridCard), not just the text format below, so both switch to
  // "urgent" together.
  static const int _urgentDaysThreshold = 5;

  // Grid cards show the actual date normally ("Valid till 31 Aug 2026") and
  // only switch to the "X Days Remaining" countdown once an offer is
  // genuinely close to expiring (<=5 days) - a countdown on every card
  // regardless of how far off the date is would make every offer look
  // equally urgent, which stops meaning anything.
  static (String, IconData) _formatGridValidity(Timestamp ts) {
    final days = ts.toDate().difference(DateTime.now()).inDays;
    if (days <= _urgentDaysThreshold) {
      return (_formatDaysRemaining(ts), Icons.access_time_filled_rounded);
    }
    return ('${'Valid till'.tr()} ${DateFormat('d MMM yyyy').format(ts.toDate())}', Icons.calendar_today_outlined);
  }

  // Same 6-color rotation LocalOffersListScreen uses for its cards (kept as
  // its own copy here since that file's palette is library-private) - gives
  // each "More offers" heading its own accent instead of one flat grey/
  // purple treatment for all of them.
  static const List<Color> _headingAccentPalette = [
    Color(0xFF9333EA),
    Color(0xFF16A34A),
    Color(0xFF2563EB),
    Color(0xFFDB2777),
    Color(0xFFE11D48),
    Color(0xFFD97706),
  ];

  // Blends toward white - used to derive a lighter, still-solid shade of a
  // card's own accent color (e.g. for the dashed circle) instead of an
  // unrelated fixed color or a black-blend that turns muddy on a saturated
  // background.
  static Color _tint(Color color, double amount) {
    return Color.lerp(color, Colors.white, amount)!;
  }

  // Valid Till / Timings side by side as compact chips instead of full-width
  // rows separated by dividers - halves the vertical space two facts used
  // to take and reads as a grouped "ticket info" strip.
  Widget _buildInfoChipsRow(bool dark, LocalOfferModel offer, Timestamp? validTill, bool hasTimings) {
    final chips = <Widget>[
      if (validTill != null)
        _infoChip(dark, Icons.calendar_today_outlined, 'Valid Till'.tr(), _formatValidTill(validTill)),
      if (hasTimings) _infoChip(dark, Icons.access_time_rounded, 'Timings'.tr(), offer.timings!),
    ];
    // IntrinsicHeight + stretch: Timings can wrap to a 2nd line while Valid
    // Till stays on 1 - without this the two chips would end up different
    // heights and look misaligned side by side.
    return IntrinsicHeight(
      child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: chips[i]),
        ],
      ],
      ),
    );
  }

  // (2026-08-07) Dark mode already reads as "layered" - the sheet
  // (darkBgSecondary) and these cards (darkBgTertiary) are two visibly
  // different tones. Light mode didn't have an equivalent: a white sheet
  // with flat grey100 cards and no shadow at all just looks like plain text
  // on a plain page. White-with-shadow (the standard raised-card pattern)
  // gives light mode the same "this is a distinct surface" cue dark mode
  // already had from tone alone.
  static List<BoxShadow> _cardShadow(bool dark) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.24 : 0.06),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ];

  Widget _infoChip(bool dark, IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgTertiary : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: dark ? null : Border.all(color: AppThemeData.grey200),
        boxShadow: _cardShadow(dark),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppThemeData.primary500),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: TextStyle(
                        fontFamily: AppThemeData.medium,
                        fontSize: 11,
                        color: dark ? AppThemeData.grey400 : AppThemeData.grey600)),
                const SizedBox(height: 2),
                Text(value,
                    // Timings is admin free-text and can run longer than a
                    // half-width chip fits on one line (e.g. "10:00 AM -
                    // 9:00 PM" was clipping its closing "PM") - wrap to a
                    // second line instead of losing the tail of the string.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: AppThemeData.semiBold,
                        fontSize: 13,
                        height: 1.25,
                        color: dark ? AppThemeData.darkTextPrimary : AppThemeData.grey900)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutCard(bool dark, LocalOfferModel offer) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgTertiary : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: dark ? null : Border.all(color: AppThemeData.grey200),
        boxShadow: _cardShadow(dark),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: dark ? AppThemeData.grey400 : AppThemeData.grey600),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('About'.tr(),
                    style: TextStyle(
                        fontFamily: AppThemeData.medium,
                        fontSize: 13,
                        color: dark ? AppThemeData.grey400 : AppThemeData.grey600)),
                const SizedBox(height: 4),
                Text(offer.description!,
                    style: TextStyle(
                        fontFamily: AppThemeData.regular,
                        fontSize: 14,
                        height: 1.4,
                        color: dark ? AppThemeData.darkTextPrimary : AppThemeData.grey900)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleIconButton(IconData icon, VoidCallback onTap, {Color? iconColor}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Icon(icon, size: 18, color: iconColor ?? AppThemeData.grey900),
      ),
    );
  }
}
