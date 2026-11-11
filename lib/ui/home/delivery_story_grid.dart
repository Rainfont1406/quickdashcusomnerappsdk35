// Delivery-only story section (2026-11-11, staging): Zomato-style image
// grid instead of the round logo circles. One card per restaurant with
// its story photo, the restaurant's offer badge, rating, name and an
// estimated delivery time. Tapping opens the normal story viewer.
// Dineaway keeps the original StoryView circles - this widget is never
// used there.

import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/model/story_model.dart';
import 'package:emartconsumer/services/delivery_location_helper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/perf_diagnostic_file_service.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/home/story_view.dart';
import 'package:emartconsumer/utils/network_image_widget.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class DeliveryStoryGrid extends StatefulWidget {
  final List<StoryModel> storyList;
  final List<VendorModel> vendors;
  final Map<String, String> offerBadges;
  final Set<String> viewedIds;
  final void Function(String storyID)? onViewRecorded;

  const DeliveryStoryGrid({
    super.key,
    required this.storyList,
    required this.vendors,
    this.offerBadges = const {},
    this.viewedIds = const {},
    this.onViewRecorded,
  });

  @override
  State<DeliveryStoryGrid> createState() => _DeliveryStoryGridState();
}

class _DeliveryStoryGridState extends State<DeliveryStoryGrid> {
  static const int _collapsed = 6; // two rows of three
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          GridView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: shown,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 14,
              childAspectRatio: 0.66,
            ),
            itemBuilder: (_, i) => _card(stories, i, byId[stories[i].vendorID.toString()]!, dark),
          ),
          if (stories.length > _collapsed)
            TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: AppThemeData.primary500),
              label: Text(
                (_expanded ? 'Show less' : 'See all ${stories.length}').tr(),
                style: const TextStyle(fontFamily: AppThemeData.semiBold, color: AppThemeData.primary500),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(List<StoryModel> stories, int index, VendorModel v, bool dark) {
    final story = stories[index];
    final url = story.imageUrl.first.toString();
    final badge = widget.offerBadges[v.id];
    final rating = v.reviewsCount > 0 ? v.reviewsSum / v.reviewsCount : 0.0;
    final eta = _eta(v);
    final viewed = widget.viewedIds.contains(story.storyID ?? '');
    final open = v.isAcceptingOrders;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MoreStories(
          storyList: stories,
          index: index,
          orderType: 'Delivery',
          onViewRecorded: widget.onViewRecorded,
        ),
      )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
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
                  // Soft top shade so the white offer text stays readable.
                  if (badge != null)
                    const Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 48,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x99000000), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                  if (badge != null)
                    Positioned(
                      left: 6,
                      top: 6,
                      right: 6,
                      child: Text(
                        badge.toUpperCase(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          height: 1.2,
                          fontFamily: AppThemeData.bold,
                        ),
                      ),
                    ),
                  if (!open)
                    Positioned(
                      left: 6,
                      right: 6,
                      bottom: 30,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('Closed now'.tr(),
                              style: const TextStyle(color: Colors.white, fontSize: 9.5, fontFamily: AppThemeData.semiBold)),
                        ),
                      ),
                    ),
                  if (rating > 0)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E7B34),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, color: Colors.white, size: 11),
                            const SizedBox(width: 2),
                            Text(rating.toStringAsFixed(1),
                                style: const TextStyle(color: Colors.white, fontSize: 10.5, fontFamily: AppThemeData.bold)),
                          ],
                        ),
                      ),
                    ),
                  // Unseen story: small dot like a notification.
                  if (!viewed)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: AppThemeData.primary500,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
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
