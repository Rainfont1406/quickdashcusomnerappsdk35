import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

// One heading+subtitle pair within a business's offer (2026-08-05) - a
// business can post several of these ("Buy 1 Get 1", "Flat ₹200 off
// ₹2000+") without duplicating the rest of LocalOfferModel. offers[0] is
// shown on the main list card and the detail screen hero; offers[1:] shows
// under "More offers here" on that same offer's detail screen.
class LocalOfferHeading {
  String? discountText;
  String? subHeadline;
  // (2026-08-08) Per-heading start date, added alongside (not replacing)
  // LocalOfferModel.startDate - same fallback pattern as validTill below.
  // See LocalOfferModel.effectiveStartDateFor. A heading with a startDate in
  // the future is excluded from activeOffers until that date arrives.
  Timestamp? startDate;
  // (2026-08-07) Per-heading expiry, added alongside (not replacing)
  // LocalOfferModel.validTill - existing docs only have the top-level date,
  // so this is null for any heading an admin hasn't set its own date on.
  // See LocalOfferModel.effectiveValidTillFor for the fallback resolution.
  Timestamp? validTill;
  // (2026-08-07) Per-heading badge, added alongside (not replacing)
  // LocalOfferModel.badgeTag - same fallback pattern as validTill above.
  // See LocalOfferModel.effectiveBadgeTagFor.
  String? badgeTag;

  LocalOfferHeading({this.discountText, this.subHeadline, this.startDate, this.validTill, this.badgeTag});

  LocalOfferHeading.fromJson(Map<String, dynamic> json) {
    discountText = json['discountText'] ?? '';
    subHeadline = json['subHeadline'] ?? '';
    startDate = json['startDate'];
    validTill = json['validTill'];
    badgeTag = json['badgeTag'] ?? '';
  }

  Map<String, dynamic> toJson() => {
        'discountText': discountText,
        'subHeadline': subHeadline,
        'startDate': startDate,
        'validTill': validTill,
        'badgeTag': badgeTag,
      };
}

// One action button (2026-08-05) - a business can show several
// (call/website/directions/WhatsApp) instead of being limited to one.
// "directions" holds the Google Maps share link directly in [ctaValue] -
// there's no separate top-level maps field anymore.
class CtaButton {
  // "website" | "directions" | "call" | "whatsapp"
  String? ctaType;
  String? ctaValue;
  // (2026-08-07) Optional branch name (e.g. "Andheri West") - only
  // meaningful when ctaType == 'directions' and the business has more than
  // one such button (multiple store locations). Ignored otherwise.
  String? label;
  // (2026-08-07) Per-branch coordinates, admin-panel-side parsed from this
  // button's own @lat,lng maps link - same best-effort parse LocalOfferModel
  // used to do once for the whole offer, now done per directions button so
  // each branch can carry its own distance. See LocalOfferModel.branches.
  GeoPoint? resolvedLocation;

  CtaButton({this.ctaType, this.ctaValue, this.label, this.resolvedLocation});

  CtaButton.fromJson(Map<String, dynamic> json) {
    ctaType = json['ctaType'] ?? 'website';
    ctaValue = json['ctaValue'] ?? '';
    label = json['label'] ?? '';
    resolvedLocation = json['resolvedLocation'];
  }

  Map<String, dynamic> toJson() => {
        'ctaType': ctaType,
        'ctaValue': ctaValue,
        'label': label,
        'resolvedLocation': resolvedLocation,
      };
}

// One store branch, resolved from a "directions" CtaButton - see
// LocalOfferModel.branches. Not stored directly; derived from ctaButtons (or
// the legacy whole-offer resolvedLocation for pre-migration docs).
class LocalOfferBranch {
  final String? label;
  final GeoPoint location;
  final String mapsUrl;

  const LocalOfferBranch({this.label, required this.location, required this.mapsUrl});
}

// Admin-authored local-business promotion card (2026-08-03) - "Offers &
// Discounts" section. Deliberately NOT backed by a real vendor/product/
// order - this is pure visibility/promotion for nearby local businesses,
// admin pastes in everything, customer app only ever reads and opens the
// attached CTA link. See local_offers collection.
class LocalOfferModel {
  String? id;
  String? businessName;
  String? categoryId;
  // Free text, e.g. "Hot Deal" / "Best Savings" / "Trending" - admin types
  // whatever fits, never a fixed enum on the app side.
  String? badgeTag;
  // (2026-08-05) One document = one business now; a business can have
  // several offer headings here instead of several sibling documents (see
  // LocalOfferHeading above). Free text headline, deliberately NOT assumed
  // to be a percentage ("50% OFF" and "Starting at ₹29" must both render
  // as-is, no "%" suffix or format baked into the UI).
  List<LocalOfferHeading> offers;
  String? description;
  // (2026-08-05) Up to 7 wide cover images - bannerImageUrls[0] is what
  // shows on the main list card and the detail screen's hero (via
  // [primaryBannerUrl]); the rest render as a swipeable gallery on the
  // detail screen only.
  List<String> bannerImageUrls;
  // Free text, e.g. "10:00 AM - 9:00 PM" - deliberately not structured
  // open/close times, admin just types the display string directly.
  String? timings;
  // (2026-08-08) Business-level default start date - see startDate on
  // LocalOfferHeading for the per-heading override and
  // effectiveStartDateFor for the fallback resolution. The offer is hidden
  // from the customer app (see activeOffers) until this date.
  Timestamp? startDate;
  Timestamp? validTill;
  // (2026-08-05) Best-effort, admin-panel-side parsed from the @lat,lng
  // pattern in whichever ctaButtons entry is type "directions" (shortened
  // maps.app.goo.gl links can't be parsed this way and are left null) -
  // only used for the "X km away" distance badge, which is hidden entirely
  // when this is null rather than blocking anything.
  GeoPoint? resolvedLocation;
  // (2026-08-05) A business can show several action buttons instead of
  // just one - see CtaButton above. Order matters: rendered in this order,
  // first one styled as the primary/filled button, the rest as secondary
  // outlined buttons.
  List<CtaButton> ctaButtons;
  bool? isActive;
  // (2026-08-07) Admin-set boost for the main list's sort order - see
  // LocalOffersListScreen's comparator. Not a customer-facing label, just a
  // ranking signal.
  bool? isRecommended;
  Timestamp? createdAt;

  // (2026-08-07) Prefers the first still-active heading over the literal
  // array-first one, so a business whose offers[0] happens to have expired
  // doesn't keep showing that expired headline as its main card/hero while
  // a later, still-valid heading sits unseen further down the array.
  LocalOfferHeading get primary {
    final active = activeOffers;
    if (active.isNotEmpty) return active.first;
    return offers.isNotEmpty ? offers.first : LocalOfferHeading(discountText: '', subHeadline: '');
  }

  // (2026-08-07) Expired offers are hidden from customers entirely rather
  // than shown with an "Expired" label - a heading counts as expired only
  // when it has a genuinely known date (unambiguousValidTillFor - see that
  // getter for why an ambiguous shared fallback doesn't count) that has
  // actually passed. Headings with no knowable date are never auto-hidden.
  // (2026-08-08) A heading whose effective start date is still in the
  // future is likewise excluded - not "expired" but "not started yet",
  // same visibility outcome either way. Uses effectiveStartDateFor (not the
  // unambiguous variant) since a not-yet-started heading should stay hidden
  // regardless of whether the date came from itself or the business-level
  // default - there's no ambiguity risk here the way there is for display.
  List<LocalOfferHeading> get activeOffers => offers.where((h) {
        final start = effectiveStartDateFor(h);
        if (start != null && start.toDate().isAfter(DateTime.now())) return false;
        final till = unambiguousValidTillFor(h);
        return till == null || till.toDate().isAfter(DateTime.now());
      }).toList();

  // Whether this business has anything left to show at all - false means
  // every offer it posted has expired, so the whole listing should be
  // hidden from the app (not just individual cards within it).
  bool get hasActiveOffers => activeOffers.isNotEmpty;

  // Convenience accessor for the main list card - bannerImageUrls[0], or
  // null when no banner was ever uploaded.
  String? get primaryBannerUrl => bannerImageUrls.isNotEmpty ? bannerImageUrls.first : null;

  // (2026-08-08) Same fallback pattern as effectiveValidTillFor below, for
  // the Start Date side - a heading's own start date if it has one, else
  // the whole-offer default. See activeOffers for how this gates visibility.
  Timestamp? effectiveStartDateFor(LocalOfferHeading heading) => heading.startDate ?? startDate;

  // (2026-08-07) Every "show a Valid Till date for this heading" call site
  // should go through this, not read heading.validTill directly - it falls
  // back to the whole-offer date for headings that don't have their own
  // (every heading on a pre-migration doc, or one an admin left blank).
  Timestamp? effectiveValidTillFor(LocalOfferHeading heading) => heading.validTill ?? validTill;

  // (2026-08-07) Customer-facing display should use THIS, not
  // effectiveValidTillFor directly, anywhere a specific heading's date is
  // shown next to that heading (grid cards, list card). The whole-offer
  // date is only unambiguous when there's just one heading - once a
  // business has several, falling back to one shared date for whichever
  // heading doesn't have its own would misrepresent which offer that date
  // actually belongs to, so those show no date at all rather than a
  // possibly-wrong one. The single-offer hero card has no such ambiguity
  // (there's nothing else it could mean), so it keeps falling back.
  Timestamp? unambiguousValidTillFor(LocalOfferHeading heading) =>
      offers.length <= 1 ? effectiveValidTillFor(heading) : heading.validTill;

  // Same fallback pattern as effectiveValidTillFor - a heading's own badge
  // if it has one, else the whole-offer badge.
  String? effectiveBadgeTagFor(LocalOfferHeading heading) =>
      (heading.badgeTag ?? '').isNotEmpty ? heading.badgeTag : badgeTag;

  // (2026-08-07) Every "directions" CTA button with a resolvable location is
  // its own store branch - a business with several of these has several
  // physical locations, not several links to the same one. Falls back to the
  // old whole-offer [resolvedLocation] (as a single unlabeled branch) for
  // docs saved before this per-button field existed.
  List<LocalOfferBranch> get branches {
    final fromButtons = ctaButtons
        .where((b) => b.ctaType == 'directions' && b.resolvedLocation != null)
        .map((b) => LocalOfferBranch(label: b.label, location: b.resolvedLocation!, mapsUrl: b.ctaValue ?? ''))
        .toList();
    if (fromButtons.isNotEmpty) return fromButtons;
    if (resolvedLocation == null) return [];
    final legacyDirectionsButtons = ctaButtons.where((b) => b.ctaType == 'directions');
    final legacyUrl = legacyDirectionsButtons.isEmpty ? '' : (legacyDirectionsButtons.first.ctaValue ?? '');
    return [LocalOfferBranch(location: resolvedLocation!, mapsUrl: legacyUrl)];
  }

  // (2026-08-07) Branches farther than this are dropped entirely rather than
  // just ranked lower - a location 200km away isn't a useful "nearby branch"
  // result. Only applied once a business has more than one branch to choose
  // between (see LocalOffersListScreen/_visibleCtaButtons) - a business's
  // one and only location is always shown regardless of distance.
  static const double maxBranchDistanceKm = 20;

  /// Every branch within [maxBranchDistanceKm] of the given point, nearest
  /// first. Empty if this offer has no resolvable branch, or none are within
  /// range.
  List<(LocalOfferBranch, double)> branchesWithDistance(double userLat, double userLng) {
    final withDistance = branches
        .map((b) => (
              b,
              Geolocator.distanceBetween(b.location.latitude, b.location.longitude, userLat, userLng) / 1000,
            ))
        .where((e) => e.$2 <= maxBranchDistanceKm)
        .toList();
    withDistance.sort((a, b) => a.$2.compareTo(b.$2));
    return withDistance;
  }

  /// Nearest branch's distance in km, or null if none are within
  /// [maxBranchDistanceKm] (or this offer has no resolvable location at
  /// all) - used for the main list card's distance badge and its place in
  /// the sort order.
  double? nearestBranchDistanceKm(double userLat, double userLng) {
    final list = branchesWithDistance(userLat, userLng);
    return list.isEmpty ? null : list.first.$2;
  }

  LocalOfferModel({
    this.id,
    this.businessName,
    this.categoryId,
    this.badgeTag,
    List<LocalOfferHeading>? offers,
    this.description,
    List<String>? bannerImageUrls,
    this.timings,
    this.startDate,
    this.validTill,
    this.resolvedLocation,
    List<CtaButton>? ctaButtons,
    this.isActive,
    this.isRecommended,
    this.createdAt,
  })  : offers = offers ?? [],
        bannerImageUrls = bannerImageUrls ?? [],
        ctaButtons = ctaButtons ?? [];

  LocalOfferModel.fromJson(Map<String, dynamic> json)
      : offers = [],
        bannerImageUrls = [],
        ctaButtons = [] {
    id = json['id'] ?? '';
    businessName = json['businessName'] ?? '';
    categoryId = json['categoryId'] ?? '';
    badgeTag = json['badgeTag'] ?? '';
    final rawOffers = json['offers'];
    if (rawOffers is List && rawOffers.isNotEmpty) {
      offers.addAll(rawOffers
          .whereType<Map>()
          .map((o) => LocalOfferHeading.fromJson(Map<String, dynamic>.from(o))));
    } else {
      // Not migrated to the offers[] array yet - fall back to the legacy
      // flat fields so a pre-migration doc still renders instead of blank.
      final legacyDiscountText = json['discountText'] ?? '';
      final legacySubHeadline = json['subHeadline'] ?? '';
      if ((legacyDiscountText as String).isNotEmpty) {
        offers.add(LocalOfferHeading(discountText: legacyDiscountText, subHeadline: legacySubHeadline));
      }
    }
    description = json['description'] ?? '';
    final rawBannerUrls = json['bannerImageUrls'];
    if (rawBannerUrls is List && rawBannerUrls.isNotEmpty) {
      bannerImageUrls.addAll(rawBannerUrls.whereType<String>().where((u) => u.isNotEmpty));
    } else {
      // Not migrated to bannerImageUrls[] yet - fall back to the legacy
      // flat field so a pre-migration doc still shows its banner.
      final legacyBannerUrl = json['bannerImageUrl'] ?? '';
      if ((legacyBannerUrl as String).isNotEmpty) bannerImageUrls.add(legacyBannerUrl);
    }
    timings = json['timings'] ?? '';
    startDate = json['startDate'];
    validTill = json['validTill'];
    resolvedLocation = json['resolvedLocation'];
    final rawCtaButtons = json['ctaButtons'];
    if (rawCtaButtons is List && rawCtaButtons.isNotEmpty) {
      ctaButtons.addAll(rawCtaButtons
          .whereType<Map>()
          .map((b) => CtaButton.fromJson(Map<String, dynamic>.from(b))));
    } else {
      // Not migrated to ctaButtons[] yet - fall back to the legacy flat
      // ctaType/ctaValue/mapsUrl fields, replicating the old "auto Get
      // Directions button" behavior (shown whenever mapsUrl was set and the
      // single ctaType wasn't already 'directions') as an explicit second
      // button, so a pre-migration doc renders exactly as it used to.
      final legacyType = json['ctaType'] ?? 'website';
      final legacyValue = json['ctaValue'] ?? '';
      final legacyMapsUrl = json['mapsUrl'] ?? '';
      ctaButtons.add(CtaButton(
        ctaType: legacyType,
        ctaValue: legacyType == 'directions' ? legacyMapsUrl : legacyValue,
      ));
      if ((legacyMapsUrl as String).isNotEmpty && legacyType != 'directions') {
        ctaButtons.add(CtaButton(ctaType: 'directions', ctaValue: legacyMapsUrl));
      }
    }
    isActive = json['isActive'] ?? true;
    isRecommended = json['isRecommended'] ?? false;
    createdAt = json['createdAt'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['businessName'] = businessName;
    data['categoryId'] = categoryId;
    data['badgeTag'] = badgeTag;
    data['offers'] = offers.map((o) => o.toJson()).toList();
    data['description'] = description;
    data['bannerImageUrls'] = bannerImageUrls;
    data['timings'] = timings;
    data['startDate'] = startDate;
    data['validTill'] = validTill;
    data['resolvedLocation'] = resolvedLocation;
    data['ctaButtons'] = ctaButtons.map((b) => b.toJson()).toList();
    data['isActive'] = isActive;
    data['isRecommended'] = isRecommended;
    data['createdAt'] = createdAt;
    return data;
  }
}
