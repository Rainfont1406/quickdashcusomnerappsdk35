import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/LocalOfferCategoryModel.dart';
import 'package:emartconsumer/model/LocalOfferModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/localOffers/LocalOfferDetailsScreen.dart';
import 'package:flutter/material.dart';

// Offers & Discounts (2026-08-03) - admin-authored local-business promotion
// feed. Deliberately separate from the food/vendor system - no vendor/
// product/order backing, pure visibility for nearby local businesses. See
// LocalOfferModel/LocalOfferCategoryModel for the Firestore schema. Offers
// are fetched in full per category (see FireStoreUtils.getAllActiveLocalOffers)
// and sorted client-side (2026-08-07 - see _compareOffers) since the sort
// depends on live-GPS distance and an admin-recommended flag, neither of
// which Firestore can order by server-side.
//
// Card/category layout (final, 2026-08-04) - image on top (full width,
// 16:8 landscape strip), text below. Admin-uploaded images are wide
// promo-poster graphics with their own text/logos baked in (same as the
// detail screen's hero banner) - a side panel of any shape always
// center-cropped away large parts of them, so the slot now matches the
// image's own wide shape instead. bannerImageUrl only - no separate
// logoUrl/"Card Image" field is used by the app anymore, one image serves
// both the card and the detail screen. Text panel below has a soft
// per-category tint background, sized to its own content (no forced
// minimum height/center-alignment, so a short offer doesn't leave empty
// background under the last line). Top category row uses flat icons in
// per-category-tinted circles, no colored backdrop on the card itself.
// No CTA button, no category chip, and no favorite/heart icon on the card
// - those live on the detail screen or the top filter row instead.
// Distance and "Valid till" (red only when <=5 days remain, neutral grey
// otherwise) sit side-by-side in the text panel via Wrap.
class LocalOffersListScreen extends StatefulWidget {
  const LocalOffersListScreen({Key? key}) : super(key: key);

  @override
  State<LocalOffersListScreen> createState() => _LocalOffersListScreenState();
}

class _LocalOffersListScreenState extends State<LocalOffersListScreen> {
  List<LocalOfferCategoryModel> _categories = [];
  List<LocalOfferModel> _allOffers = [];
  List<LocalOfferModel> _visibleOffers = [];
  String? _selectedCategoryId;
  String _searchText = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // (2026-08-07) A business with every offer past its date is dropped from
  // the feed entirely rather than shown with an "Expired" label.
  List<LocalOfferModel> _onlyActive(List<LocalOfferModel> list) =>
      list.where((o) => o.hasActiveOffers).toList();

  // Sort priority (2026-08-07, per explicit request): admin-recommended
  // businesses first, then within that tier (and again within the
  // non-recommended tier) businesses with a resolvable distance before ones
  // without one, nearest first; soonest-expiring offer as the final
  // tiebreak, with "Available Now" (no date) sinking to the bottom of its
  // bucket since there's nothing to rank it by. Distance is computed from
  // live GPS (see _distanceKm) so this can't be done as a Firestore
  // server-side orderBy - it's applied here after the full active set is
  // fetched.
  int _compareOffers(LocalOfferModel a, LocalOfferModel b) {
    final aRecommended = a.isRecommended ?? false;
    final bRecommended = b.isRecommended ?? false;
    if (aRecommended != bRecommended) return aRecommended ? -1 : 1;

    final aDistance = _distanceKm(a);
    final bDistance = _distanceKm(b);
    if ((aDistance != null) != (bDistance != null)) return aDistance != null ? -1 : 1;
    if (aDistance != null && bDistance != null) {
      final byDistance = aDistance.compareTo(bDistance);
      if (byDistance != 0) return byDistance;
    }

    final aValidTill = a.unambiguousValidTillFor(a.primary);
    final bValidTill = b.unambiguousValidTillFor(b.primary);
    if ((aValidTill != null) != (bValidTill != null)) return aValidTill != null ? -1 : 1;
    if (aValidTill != null && bValidTill != null) return aValidTill.compareTo(bValidTill);

    return 0;
  }

  Future<void> _load() async {
    final results = await Future.wait([
      FireStoreUtils.getLocalOfferCategories(),
      FireStoreUtils.getAllActiveLocalOffers(),
    ]);
    if (!mounted) return;
    final offers = _onlyActive(results[1] as List<LocalOfferModel>)..sort(_compareOffers);
    setState(() {
      _categories = results[0] as List<LocalOfferCategoryModel>;
      _allOffers = offers;
      _loading = false;
    });
    _applyFilters();
  }

  /// Switches category server-side (a fresh query) rather than filtering the
  /// already-loaded "All" list, since a category the user hasn't visited yet
  /// may not be in it.
  Future<void> _selectCategory(String? categoryId) async {
    setState(() {
      _selectedCategoryId = categoryId;
      _loading = true;
      _allOffers = [];
      _visibleOffers = [];
    });
    final offers = _onlyActive(await FireStoreUtils.getAllActiveLocalOffers(categoryId: categoryId))
      ..sort(_compareOffers);
    if (!mounted) return;
    setState(() {
      _allOffers = offers;
      _loading = false;
    });
    _applyFilters();
  }

  // Category filtering happens server-side per page (see _selectCategory) -
  // search is the only client-side filter left, applied over whatever
  // pages have loaded so far for the current category.
  void _applyFilters() {
    var list = _allOffers;
    if (_searchText.trim().isNotEmpty) {
      final q = _searchText.trim().toLowerCase();
      list = list
          .where((o) =>
              (o.businessName ?? '').toLowerCase().contains(q) ||
              (o.primary.discountText ?? '').toLowerCase().contains(q) ||
              (o.primary.subHeadline ?? '').toLowerCase().contains(q))
          .toList();
    }
    setState(() => _visibleOffers = list);
  }

  // (2026-08-07) Nearest of the business's branches within
  // LocalOfferModel.maxBranchDistanceKm - a multi-location business (e.g.
  // several "Get Directions" buttons) is judged by whichever branch is
  // actually closest, not just its first one.
  double? _distanceKm(LocalOfferModel offer) {
    final userLoc = MyAppState.selectedPosotion.location;
    if (userLoc == null) return null;
    return offer.nearestBranchDistanceKm(userLoc.latitude, userLoc.longitude);
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    // Same warm lavender-white the rest of the app's own Scaffold uses
    // (ContainerScreen) - a neutral pure grey here read as flatter/colder
    // than the rest of the app and made this screen look "white on white".
    final bg = dark ? AppThemeData.darkBgPrimary : const Color(0xFFF2F0F8);
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildSearchBar(dark),
                  _buildCategoryRow(dark),
                  Expanded(
                    child: _visibleOffers.isEmpty
                        ? Center(
                            child: Text('No offers found nearby yet.'.tr(),
                                style: TextStyle(
                                    fontFamily: AppThemeData.medium,
                                    color: dark ? AppThemeData.grey400 : AppThemeData.grey600)),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
                            itemCount: _visibleOffers.length,
                            itemBuilder: (context, index) {
                              return _OfferCard(
                                offer: _visibleOffers[index],
                                distanceKm: _distanceKm(_visibleOffers[index]),
                                dark: dark,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LocalOfferDetailsScreen(offer: _visibleOffers[index]),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSearchBar(bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: dark ? AppThemeData.darkBgSecondary : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: dark ? AppThemeData.darkBorderPrimary : AppThemeData.grey200),
        ),
        child: TextField(
          onChanged: (v) {
            _searchText = v;
            _applyFilters();
          },
          style: TextStyle(
              fontFamily: AppThemeData.regular,
              color: dark ? AppThemeData.darkTextPrimary : AppThemeData.grey900),
          decoration: InputDecoration(
            hintText: 'Search offers, stores or services...'.tr(),
            hintStyle: TextStyle(fontFamily: AppThemeData.regular, color: AppThemeData.grey400),
            prefixIcon: const Icon(Icons.search),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryRow(bool dark) {
    if (_categories.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 88,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _CategoryChip(
            label: 'All'.tr(),
            icon: Icons.apps_rounded,
            iconUrl: null,
            iconColor: dark ? AppThemeData.grey400 : AppThemeData.grey600,
            selected: _selectedCategoryId == null,
            dark: dark,
            onTap: () => _selectCategory(null),
          ),
          const SizedBox(width: 14),
          for (var i = 0; i < _categories.length; i++) ...[
            _CategoryChip(
              label: _categories[i].name ?? '',
              icon: _iconForCategory(_categories[i].name ?? ''),
              iconUrl: _categories[i].iconUrl,
              iconColor: _categoryIconPalette[i % _categoryIconPalette.length],
              selected: _selectedCategoryId == _categories[i].id,
              dark: dark,
              onTap: () => _selectCategory(_categories[i].id),
            ),
            const SizedBox(width: 14),
          ],
        ],
      ),
    );
  }
}

// Small fixed color palette (2026-08-03) - categories are admin-managed
// text names with no color field of their own; cycling a palette by
// position gives each icon its own color without adding a new Firestore
// field/admin control for something this cosmetic.
const List<Color> _categoryIconPalette = [
  Color(0xFF9333EA),
  Color(0xFF16A34A),
  Color(0xFF2563EB),
  Color(0xFFDB2777),
  Color(0xFFE11D48),
  Color(0xFFD97706),
];

/// Best-effort icon guess from the category's own name - only ever used as
/// a fallback UNDER the admin-uploaded iconUrl (see _CategoryChip), never
/// instead of it.
IconData _iconForCategory(String name) {
  final n = name.toLowerCase();
  if (n.contains('groom')) return Icons.content_cut_rounded;
  if (n.contains('grocer')) return Icons.shopping_basket_outlined;
  if (n.contains('cloth') || n.contains('fashion')) return Icons.checkroom_rounded;
  if (n.contains('electron')) return Icons.headphones_rounded;
  if (n.contains('health') || n.contains('pharma')) return Icons.favorite_rounded;
  if (n.contains('travel')) return Icons.flight_rounded;
  return Icons.local_offer_rounded;
}

/// Icon to pair with a free-text badgeTag - matched by common keywords,
/// generic tag icon otherwise. Purely decorative, never gates anything.
IconData _iconForBadge(String tag) {
  final t = tag.toLowerCase();
  if (t.contains('hot')) return Icons.local_fire_department_rounded;
  if (t.contains('best') || t.contains('saving')) return Icons.star_rounded;
  if (t.contains('trend')) return Icons.trending_up_rounded;
  return Icons.sell_rounded;
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? iconUrl;
  final Color iconColor;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.iconUrl,
    required this.iconColor,
    required this.selected,
    required this.dark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // (2026-08-03) The uploaded icon images are square PNGs (often with a
    // white canvas baked in), so rendering them un-clipped read as plain
    // squares - back to a circular avatar (ClipOval + a light fill so any
    // white/transparent canvas still reads as a filled circle, BoxFit.cover
    // so it fills the circle edge-to-edge with no corner gaps), matching
    // the circular story avatars used elsewhere in the app. Selected state
    // stays a light rounded highlight around the whole chip.
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 68,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppThemeData.primary50 : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: selected ? Border.all(color: AppThemeData.primary200) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: Container(
                width: 44,
                height: 44,
                // (2026-08-03) Tinted with this chip's own iconColor rather
                // than a flat neutral grey, per explicit request - "All"
                // keeps the neutral fill since it has no category color of
                // its own.
                color: iconColor.withOpacity(dark ? 0.28 : 0.15),
                child: (iconUrl != null && iconUrl!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: iconUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Icon(icon, size: 24, color: iconColor),
                        errorWidget: (context, url, error) => Icon(icon, size: 24, color: iconColor),
                      )
                    : Icon(icon, size: 24, color: iconColor),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: selected ? AppThemeData.bold : AppThemeData.medium,
                fontSize: 12,
                color: selected
                    ? AppThemeData.primary500
                    : (dark ? AppThemeData.darkTextPrimary : AppThemeData.grey900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Per-category accent color (discount text, CTA button, distance-pill
// text/icon) - keyed by a stable hash of the category id so a business's
// card always matches its own category chip's color. The card's own
// background stays plain white/darkBgSecondary (see build() below) - only
// these specific elements carry the per-category color, matching the
// reference design exactly.
const List<Color> _cardAccentPalette = [
  Color(0xFF9333EA),
  Color(0xFF16A34A),
  Color(0xFF2563EB),
  Color(0xFFDB2777),
  Color(0xFFE11D48),
  Color(0xFFD97706),
];

int _paletteIndexFor(String? categoryId) {
  if (categoryId == null || categoryId.isEmpty) return 0;
  return categoryId.hashCode.abs() % _cardAccentPalette.length;
}

class _OfferCard extends StatelessWidget {
  final LocalOfferModel offer;
  final double? distanceKm;
  final bool dark;
  final VoidCallback onTap;

  const _OfferCard({
    required this.offer,
    required this.distanceKm,
    required this.dark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final paletteIndex = _paletteIndexFor(offer.categoryId);
    final accent = _cardAccentPalette[paletteIndex];
    // (2026-08-05) First of up to 7 banner images only - the rest show as a
    // gallery on the detail screen instead. The separate logoUrl/"Card
    // Image" field is no longer used by the app; this image fits the
    // card's own image panel (BoxFit.cover below, sized to that panel
    // only, never the whole card).
    final imageUrl = offer.primaryBannerUrl;
    // (2026-08-03) Red is an urgency signal, not a permanent style - only
    // apply it once the offer is genuinely close to expiring (<=5 days),
    // otherwise use the same neutral grey the distance chip already uses.
    // (2026-08-07) Uses the card's own heading validity - unambiguousValidTillFor
    // only falls back to the whole-offer date when there's just one heading
    // (unambiguous); with several, showing the shared default next to
    // whichever one doesn't have its own date would misrepresent which
    // offer it actually belongs to, so it shows nothing for those instead.
    final cardValidTill = offer.unambiguousValidTillFor(offer.primary);
    final daysLeft = cardValidTill?.toDate().difference(DateTime.now()).inDays;
    final validTillUrgent = daysLeft != null && daysLeft <= 5;
    final validTillBg = validTillUrgent
        ? AppThemeData.danger50
        : (dark ? AppThemeData.darkBgTertiary : AppThemeData.grey100);
    final validTillFg = validTillUrgent
        ? AppThemeData.danger400
        : (dark ? AppThemeData.grey400 : AppThemeData.grey600);

    // (2026-08-04) Image-on-top, full width, text below (was a side-by-side
    // split) - these images are wide promo-poster graphics (own text/logos
    // spread across the full width, same as the detail screen's hero
    // banner), so a side panel (square or rectangular) always center-cropped
    // away large parts of them no matter its proportions. A full-width
    // landscape strip matches the poster's own shape instead of fighting it.
    // Text panel below uses mainAxisSize.min (no forced minHeight, no
    // center-alignment) so it hugs its actual content - a short offer with
    // no badge/subheadline/validTill doesn't leave empty background below
    // the last line.
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: dark ? AppThemeData.darkBgSecondary : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(dark ? 0.3 : 0.05), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              // (2026-08-04) Matches the real uploaded images' own aspect
              // ratio (checked directly - 1600x900, i.e. 16:9) - the slot
              // was previously 16:8 (2.0), wider than the source images,
              // so BoxFit.cover scaled to match width and cropped the
              // excess off the top/bottom to fill the extra-wide box.
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18)),
                child: (imageUrl ?? '').isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: dark ? AppThemeData.darkBgTertiary : AppThemeData.grey100,
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: dark ? AppThemeData.darkBgTertiary : AppThemeData.grey100,
                          child: Icon(Icons.image_not_supported_outlined,
                              size: 24, color: dark ? AppThemeData.grey400 : AppThemeData.grey500),
                        ),
                      )
                    : Container(color: dark ? AppThemeData.darkBgTertiary : AppThemeData.grey100),
              ),
            ),
            // Soft per-category tinted background (2026-08-03) behind just
            // the text portion - only the bottom corners round now, the top
            // ones belong to the image above.
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: accent.withOpacity(dark ? 0.16 : 0.08),
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18)),
              ),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((offer.badgeTag ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppThemeData.accent500.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_iconForBadge(offer.badgeTag!), size: 11, color: AppThemeData.accent600),
                            const SizedBox(width: 4),
                            Text(
                              offer.badgeTag!.toUpperCase(),
                              style: TextStyle(
                                  fontFamily: AppThemeData.bold, fontSize: 10, color: AppThemeData.accent600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // (2026-08-03) Category chip removed from the card
                  // entirely per explicit request - the category is
                  // already shown via the top category-chip row/filter,
                  // so it's redundant here. Distance stays, near valid
                  // till.
                  Text(offer.businessName ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: AppThemeData.bold,
                          fontSize: 15,
                          color: dark ? AppThemeData.darkTextPrimary : AppThemeData.grey900)),
                  if ((offer.primary.subHeadline ?? '').isNotEmpty)
                    Text(offer.primary.subHeadline!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: AppThemeData.regular,
                            fontSize: 12,
                            color: dark ? AppThemeData.grey400 : AppThemeData.grey600)),
                  const SizedBox(height: 2),
                  Text(offer.primary.discountText ?? '',
                      style: TextStyle(fontFamily: AppThemeData.bold, fontSize: 22, color: accent)),
                  // (2026-08-03) Own pill background, no calendar icon (was
                  // plain grey text with a calendar icon); red only when
                  // <=5 days remain (see validTillUrgent above) - neutral
                  // grey otherwise, so red stays meaningful as an actual
                  // expiry warning instead of a permanent color.
                  if (cardValidTill != null || distanceKm != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (cardValidTill != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: validTillBg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                  'Valid till'.tr() +
                                      ' ${cardValidTill.toDate().day}/${cardValidTill.toDate().month}/${cardValidTill.toDate().year}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontFamily: AppThemeData.medium, fontSize: 11, color: validTillFg)),
                            ),
                          // Distance sits beside valid-till now (Wrap, not a
                          // fixed column) instead of always stacking below
                          // it - one line saved whenever both are present,
                          // rather than reserved vertical space either way.
                          if (distanceKm != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: dark ? AppThemeData.darkBgTertiary : AppThemeData.grey100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.location_on_rounded,
                                      size: 10, color: dark ? AppThemeData.grey400 : AppThemeData.grey600),
                                  const SizedBox(width: 3),
                                  Text('${distanceKm!.toStringAsFixed(1)} km away',
                                      style: TextStyle(
                                          fontFamily: AppThemeData.medium,
                                          fontSize: 10,
                                          color: dark ? AppThemeData.grey400 : AppThemeData.grey600)),
                                ],
                              ),
                            ),
                        ],
                      ),
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
