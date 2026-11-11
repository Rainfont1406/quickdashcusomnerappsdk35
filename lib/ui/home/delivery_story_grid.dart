// Delivery-only story section (2026-11-11, staging): Zomato-style
// restaurant promo grid instead of the round logo circles.
//
// One card per restaurant: a landscape (rectangle) photo from its story,
// the restaurant's offer on a dark strip over the photo, rating, name and
// an estimated delivery time. Tapping a card opens the RESTAURANT PAGE
// (not the story viewer): in Delivery the story is the vendor's ad for an
// instant order, so the customer goes straight to the menu.
//
// Dineaway keeps the original StoryView circles - this widget is never
// used there.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/services/behavior/behavior_event_types.dart';
import 'package:emartconsumer/services/firestore_instrumentation.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/model/story_model.dart';
import 'package:emartconsumer/services/behavior/behavior_tracker.dart';
import 'package:emartconsumer/services/delivery_location_helper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/perf_diagnostic_file_service.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:emartconsumer/utils/network_image_widget.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class DeliveryStoryGrid extends StatefulWidget {
  final List<StoryModel> storyList;
  final List<VendorModel> vendors;
  final Map<String, String> offerBadges;

  const DeliveryStoryGrid({
    super.key,
    required this.storyList,
    required this.vendors,
    this.offerBadges = const {},
  });

  @override
  State<DeliveryStoryGrid> createState() => _DeliveryStoryGridState();
}

class _DeliveryStoryGridState extends State<DeliveryStoryGrid> {
  static const int _collapsed = 6; // two rows of three
  static const double _imageRatio = 1.2; // width : height, landscape like Zomato
  bool _expanded = false;

  /// Rough delivery time: 20 min kitchen + 3 min per km, rounded to 5 min,
  /// shown as a 5-minute range ("25-30 mins"). Null when the distance is
  /// unknown, so no made-up time is shown.
  String? _eta(VendorModel v) {
    final here = MyAppState.selectedPosotion.location;
    if (!isRealLocation(here)) return null;
    if (v.latitude.abs() < 1 && v.longitude.abs() < 1) return null;
    final km = Geolocator.distanceBetween(here!.latitude, here.longitude, v.latitude, v.longitude) / 1000;
    if (km > 30) return null; // too far for a meaningful delivery time
    final low = ((20 + km * 3) / 5).round() * 5;
    return '$low-${low + 5} ${'mins'.tr()}';
  }

  /// Green for good ratings, lighter green for average, orange below 3.
  static Color _ratingColor(double r) => r >= 4
      ? const Color(0xFF1E7B34)
      : r >= 3
          ? const Color(0xFF3F9142)
          : const Color(0xFFDB7C38);

  void _openRestaurant(StoryModel story, VendorModel v) {
    // ignore: unawaited_futures
    _recordClick(story); // never blocks opening the restaurant
    BehaviorTracker.setNextEntrySource('Home');
    push(context, NewVendorProductsScreen(vendorModel: v));
  }

  /// 2026-11-11 (owner): in Delivery a story "view" = a customer tapping the
  /// card to open the restaurant, counted ONCE per customer per story per
  /// day - same rule and same story_views doc as the Dineaway viewer
  /// (StoryView.recordView), with source: deliveryGridTap. Repeat taps the
  /// same day don't add more. The purchased view package (viewPackageSize, capped in firestore.rules)
  /// still stops the story once used up. Lossy on failure by design - it
  /// must never stop the restaurant from opening.
  Future<void> _recordClick(StoryModel story) async {
    final userID = MyAppState.currentUser?.userID ?? auth.FirebaseAuth.instance.currentUser?.uid;
    final storyID = story.storyID;
    if (userID == null || userID.isEmpty || storyID == null || storyID.isEmpty) return;
    BehaviorTracker.track(kEvtStoryViewed, {'storyId': storyID, 'vendorId': story.vendorID, 'via': 'deliveryGridTap'});
    final now = DateTime.now();
    final dateKey = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final db = FirebaseFirestore.instance;
    // Same doc id as the Dineaway viewer, so a customer counts once per
    // story per day whichever way they saw it.
    final viewRef = db.collection('story_views').doc('${storyID}_${userID}_$dateKey');
    final storyRef = db.collection(STORY).doc(storyID);
    try {
      var counted = false;
      await db.runTransaction((tx) async {
        final existing = await tx.getLogged(viewRef, 'DeliveryStoryGrid.recordClick:story_views (tx)');
        if (existing.exists) return; // already counted today
        tx.set(viewRef, {
          'storyID': storyID,
          'userID': userID,
          'vendorID': story.vendorID,
          'dateKey': dateKey,
          'viewedAt': Timestamp.now(),
          'source': 'deliveryGridTap',
        });
        tx.update(storyRef, {'viewCount': FieldValue.increment(1)});
        counted = true;
      });
      debugPrint('[DeliveryStoryGrid] story=$storyID ${counted ? 'view counted' : 'already counted today'}');
    } catch (e) {
      // e.g. view package used up (rules reject the +1) or a slow network.
      debugPrint('[DeliveryStoryGrid] click not counted story=$storyID: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final byId = {for (final v in widget.vendors) v.id: v};
    // One card per restaurant: its first delivery image story.
    final stories = <StoryModel>[];
    final seen = <String>{};
    for (final s in widget.storyList) {
      final vid = s.vendorID?.toString() ?? '';
      if (!s.delivery || !s.hasImage || !byId.containsKey(vid) || !seen.add(vid)) continue;
      stories.add(s);
    }
    if (stories.isEmpty) return const SizedBox();

    final shown = _expanded ? stories.length : stories.length.clamp(0, _collapsed);
    final dark = isDarkMode(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(builder: (context, box) {
        const gap = 10.0;
        final cardW = (box.maxWidth - gap * 2) / 3;
        final imageH = cardW / _imageRatio;
        // image + name + time lines (grows with the phone's text size).
        final extent = imageH + 8 + 44 * textScale;
        return Column(
          children: [
            GridView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: shown,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: gap,
                mainAxisSpacing: 14,
                mainAxisExtent: extent,
              ),
              itemBuilder: (_, i) =>
                  _card(stories[i], byId[stories[i].vendorID.toString()]!, imageH, dark),
            ),
            if (stories.length > _collapsed)
              TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: AppThemeData.primary500),
                label: Text(
                  _expanded ? 'Show less'.tr() : '${'See all'.tr()} (${stories.length})',
                  style: const TextStyle(fontFamily: AppThemeData.semiBold, color: AppThemeData.primary500),
                ),
              ),
          ],
        );
      }),
    );
  }

  Widget _card(StoryModel story, VendorModel v, double imageH, bool dark) {
    final url = story.imageUrl.first.toString();
    final offer = widget.offerBadges[v.id];
    final rating = v.reviewsCount > 0 ? v.reviewsSum / v.reviewsCount : 0.0;
    final eta = _eta(v);
    final open = v.isAcceptingOrders;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openRestaurant(story, v),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: imageH,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColorFiltered(
                    colorFilter: open
                        ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
                        : const ColorFilter.matrix(<double>[
                            0.33, 0.33, 0.33, 0, 0, //
                            0.33, 0.33, 0.33, 0, 0, //
                            0.33, 0.33, 0.33, 0, 0, //
                            0, 0, 0, 1, 0,
                          ]),
                    child: NetworkImageWidget(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      // Card is ~110 px wide; ask the CDN for a small copy.
                      resizeWidth: 120,
                      cacheManager: perfDiagnosticCacheManager,
                    ),
                  ),
                  // Offer strip, top-left over the photo (Zomato style).
                  if (offer != null)
                    Positioned(
                      left: 0,
                      top: 0,
                      right: 14,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: const BorderRadius.only(
                            bottomRight: Radius.circular(8),
                          ),
                        ),
                        child: Text(
                          offer.toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            height: 1.2,
                            fontFamily: AppThemeData.bold,
                          ),
                        ),
                      ),
                    ),
                  if (!open)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('Closed now'.tr(),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 9.5, fontFamily: AppThemeData.semiBold)),
                      ),
                    ),
                  // Rating badge, bottom-left (Zomato style). A restaurant
                  // with no reviews yet shows "NEW" instead of a fake 0.0.
                  Positioned(
                    left: 5,
                    bottom: 5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: rating > 0 ? _ratingColor(rating) : Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (rating > 0) ...[
                            const Icon(Icons.star_rounded, color: Colors.white, size: 11),
                            const SizedBox(width: 2),
                          ],
                          Text(rating > 0 ? rating.toStringAsFixed(1) : 'NEW'.tr(),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 10.5, fontFamily: AppThemeData.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            v.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontFamily: AppThemeData.semiBold,
              color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
            ),
          ),
          if (eta != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.timer_outlined,
                    size: 13, color: dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral600),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    eta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontFamily: AppThemeData.regular,
                      color: dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
