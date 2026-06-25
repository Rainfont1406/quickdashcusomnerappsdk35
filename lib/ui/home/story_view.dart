import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/model/story_model.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/utils/network_image_widget.dart';
import 'package:emartconsumer/widget/story_view/controller/story_controller.dart';
import 'package:emartconsumer/widget/story_view/utils.dart';
import 'package:flutter/material.dart';
import '../../widget/story_view/widgets/story_view.dart';
import '../vendorProductsScreen/newVendorProductsScreen.dart';

/// Full-screen story viewer opened from HomeScreen.
///
/// Uses [PageView] for left/right swipe between vendors (exactly like
/// Instagram Stories) while [StoryView] handles tap-to-advance and
/// tap-to-rewind within a single vendor's story items.
class MoreStories extends StatefulWidget {
  final List<StoryModel> storyList;
  final int index;
  final String orderType;

  const MoreStories({
    super.key,
    required this.index,
    required this.storyList,
    required this.orderType,
  });

  @override
  MoreStoriesState createState() => MoreStoriesState();
}

class MoreStoriesState extends State<MoreStories> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.index;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _advanceToNext() {
    if (!mounted) return;
    if (_currentIndex < widget.storyList.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        // ClampingScrollPhysics prevents over-scrolling past the first/last
        // vendor, matching the Instagram experience.
        physics: const ClampingScrollPhysics(),
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemCount: widget.storyList.length,
        itemBuilder: (context, index) {
          return _VendorStoryPage(
            // ValueKey ensures each page keeps its own state when scrolling.
            key: ValueKey('story_vendor_$index'),
            story: widget.storyList[index],
            orderType: widget.orderType,
            isActive: index == _currentIndex,
            onComplete: _advanceToNext,
            onClose: () => Navigator.pop(context),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// One vendor's story page (owns its StoryController)
// ─────────────────────────────────────────────────────────────────────────────

class _VendorStoryPage extends StatefulWidget {
  final StoryModel story;
  final String orderType;
  final bool isActive;
  final VoidCallback onComplete;
  final VoidCallback onClose;

  const _VendorStoryPage({
    super.key,
    required this.story,
    required this.orderType,
    required this.isActive,
    required this.onComplete,
    required this.onClose,
  });

  @override
  State<_VendorStoryPage> createState() => _VendorStoryPageState();
}

class _VendorStoryPageState extends State<_VendorStoryPage> {
  late StoryController _controller;
  late List<StoryItem> _items;
  bool _viewRecorded = false;

  @override
  void initState() {
    super.initState();
    _controller = StoryController();
    _items = _buildItems();
    // Page is built before it becomes visible — keep paused until active.
    if (!widget.isActive) _controller.pause();
  }

  // Records a unique view for this story, deduped per (story, user, day) so
  // a returning viewer on a later calendar day still counts as a new view
  // against the vendor's purchased view package - but re-opening the same
  // story multiple times today does not.
  Future<void> _recordView() async {
    if (_viewRecorded) return;
    _viewRecorded = true; // client-side debounce, set before await

    final userID = MyAppState.currentUser?.userID;
    final storyID = widget.story.storyID;
    if (userID == null || userID.isEmpty || storyID == null || storyID.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final dateKey =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

    final firestore = FirebaseFirestore.instance;
    final viewRef =
        firestore.collection('story_views').doc('${storyID}_${userID}_$dateKey');
    final storyRef = firestore.collection(STORY).doc(storyID);

    try {
      await firestore.runTransaction((tx) async {
        final existing = await tx.get(viewRef);
        if (existing.exists) return; // already counted today
        tx.set(viewRef, {
          'storyID': storyID,
          'userID': userID,
          'vendorID': widget.story.vendorID,
          'dateKey': dateKey,
          'viewedAt': Timestamp.now(),
        });
        tx.update(storyRef, {'viewCount': FieldValue.increment(1)});
      });
    } catch (_) {
      // Swallow - e.g. the story doc was deleted concurrently because
      // another viewer's view just exhausted its package.
    }
  }

  @override
  void didUpdateWidget(_VendorStoryPage old) {
    super.didUpdateWidget(old);
    if (old.isActive != widget.isActive) {
      widget.isActive ? _controller.play() : _controller.pause();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<StoryItem> _buildItems() {
    final story = widget.story;
    final items = <StoryItem>[];

    if (widget.orderType == "Delivery".tr() && story.hasImage) {
      for (final url in story.imageUrl) {
        items.add(StoryItem.pageImage(
          url: url.toString(),
          controller: _controller,
          duration: const Duration(seconds: 5),
        ));
      }
    } else if ((widget.orderType == "Dineaway".tr() ||
            widget.orderType == "Takeaway".tr()) &&
        story.takeaway) {
      if (story.hasVideo) {
        for (final url in story.videoUrl) {
          final urlStr = url.toString();
          if (urlStr.isNotEmpty) {
            // Default 10 s — will be corrected to actual video length by
            // StoryVideo → StoryController.notifyDuration → StoryViewState.
            items.add(StoryItem.pageVideo(urlStr, controller: _controller));
          }
        }
      } else if (story.hasImage) {
        for (final url in story.imageUrl) {
          items.add(StoryItem.pageImage(
            url: url.toString(),
            controller: _controller,
            duration: const Duration(seconds: 5),
          ));
        }
      }
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      // Nothing to show — advance immediately (skip this vendor).
      WidgetsBinding.instance
          .addPostFrameCallback((_) => widget.onComplete());
      return const SizedBox.shrink();
    }

    final topPad = MediaQuery.of(context).viewPadding.top;

    return Stack(
      children: [
        // ── Story content ────────────────────────────────────────────────
        StoryView(
          storyItems: _items,
          controller: _controller,
          progressPosition: ProgressPosition.top,
          repeat: false,
          onComplete: widget.onComplete,
          onStoryShow: (storyItem, index) => _recordView(),
          onVerticalSwipeComplete: (direction) {
            if (direction == Direction.down) widget.onClose();
          },
          indicatorHeight: IndicatorHeight.small,
          indicatorOuterPadding: EdgeInsets.only(
            left: 12,
            right: 12,
            top: topPad + 6,
            bottom: 0,
          ),
        ),

        // ── Top gradient scrim (behind vendor header) ────────────────────
        Positioned(
          top: 0, left: 0, right: 0,
          height: topPad + 140,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xCC000000), Colors.transparent],
              ),
            ),
          ),
        ),

        // ── Vendor header ────────────────────────────────────────────────
        Positioned(
          top: topPad + 50,
          left: 16,
          right: 56,
          child: _VendorHeader(
            vendorId: widget.story.vendorID.toString(),
            storyController: _controller,
          ),
        ),

        // ── Close button ─────────────────────────────────────────────────
        Positioned(
          top: topPad + 8,
          right: 12,
          child: GestureDetector(
            onTap: widget.onClose,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25), width: 1),
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vendor header — avatar + name + rating + "Visit" chip
// ─────────────────────────────────────────────────────────────────────────────

class _VendorHeader extends StatelessWidget {
  final String vendorId;
  final StoryController storyController;

  const _VendorHeader({
    required this.vendorId,
    required this.storyController,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VendorModel?>(
      future: FireStoreUtils.getVendor(vendorId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSkeleton();
        }
        if (snapshot.hasError || snapshot.data == null) {
          return const SizedBox.shrink();
        }
        final vendor = snapshot.data!;
        return GestureDetector(
          onTap: () {
            storyController.pause();
            push(context, NewVendorProductsScreen(vendorModel: vendor));
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.85), width: 2),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8)
                  ],
                ),
                child: ClipOval(
                  child: NetworkImageWidget(
                    imageUrl: vendor.photo.toString(),
                    width: 44, height: 44,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Name + rating
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      vendor.title.toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontFamily: AppThemeData.semiBold,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: Color(0xFFFBBC05), size: 13),
                        const SizedBox(width: 3),
                        Text(
                          "${calculateReview(reviewCount: vendor.reviewsCount.toString(), reviewSum: vendor.reviewsSum.toString())} reviews",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                            fontFamily: AppThemeData.medium,
                            shadows: const [
                              Shadow(color: Colors.black38, blurRadius: 4)
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Visit chip
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35), width: 1),
                ),
                child: Text(
                  'Visit'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontFamily: AppThemeData.semiBold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSkeleton() {
    return Row(
      children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.2)),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 13, width: 120,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6)),
            ),
            const SizedBox(height: 6),
            Container(
              height: 10, width: 80,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5)),
            ),
          ],
        ),
      ],
    );
  }
}
