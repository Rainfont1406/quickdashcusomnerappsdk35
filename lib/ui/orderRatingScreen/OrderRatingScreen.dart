import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/OrderModel.dart';
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/model/Ratingmodel.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/behavior/behavior_event_types.dart';
import 'package:emartconsumer/services/behavior/behavior_tracker.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import '../../constants/typography.dart';
import '../../constants/spacing.dart';

// ── Quick keyword suggestions shown above the text field ─────────────────────
const _kKeywords = [
  'Delicious Food',
  'Great Taste',
  'Fresh Food',
  'Healthy Option',
  'Highly Recommended',
  'Quality Ingredients',
  'Taste Could Be Better',
  'Not Fresh',
];

// ─────────────────────────────────────────────────────────────────────────────

class OrderRatingScreen extends StatefulWidget {
  final OrderModel orderModel;

  const OrderRatingScreen({Key? key, required this.orderModel})
      : super(key: key);

  @override
  State<OrderRatingScreen> createState() => _OrderRatingScreenState();
}

class _OrderRatingScreenState extends State<OrderRatingScreen> {
  bool _loading = true;
  bool _alreadyRated = false;
  bool _submitting = false;
  bool _submitted = false;

  double _stars = 0;
  final _commentCtrl = TextEditingController();
  final _focusNode = FocusNode();
  final _textFieldKey = GlobalKey();
  bool _focused = false;

  // Existing rating for read-only display
  double _existingStars = 0;
  String _existingComment = '';

  // For updating review counters
  ProductModel? _productModel;
  VendorModel? _vendorModel;
  num _reviewCount = 0, _reviewSum = 0;
  num _vendorReviewCount = 0, _vendorReviewSum = 0;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    _load();
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() => _focused = _focusNode.hasFocus);
      if (_focusNode.hasFocus) {
        // Wait for keyboard animation to complete before scrolling text field into view
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted && _textFieldKey.currentContext != null) {
            Scrollable.ensureVisible(
              _textFieldKey.currentContext!,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              alignmentPolicy:
                  ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
            );
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _load() async {
    final existing =
        await FireStoreUtils().getReviewsbyID(widget.orderModel.id);
    if (existing != null) {
      if (mounted) {
        setState(() {
          _alreadyRated = true;
          _existingStars = (existing.rating ?? 0).toDouble();
          _existingComment = existing.comment ?? '';
          _loading = false;
        });
      }
      return;
    }

    if (widget.orderModel.products.isNotEmpty) {
      try {
        _productModel = await FireStoreUtils()
            .getProductByID(widget.orderModel.products.first.id);
        _reviewCount = _productModel!.reviewsCount;
        _reviewSum = _productModel!.reviewsSum;
        _vendorModel =
            await FireStoreUtils.getVendor(_productModel!.vendorID);
        if (_vendorModel != null) {
          _vendorReviewCount = _vendorModel!.reviewsCount;
          _vendorReviewSum = _vendorModel!.reviewsSum;
        }
      } catch (_) {}
    }

    if (mounted) setState(() => _loading = false);
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_stars == 0) {
      _snack('Please select a star rating.'.tr());
      return;
    }
    if (_commentCtrl.text.trim().isEmpty) {
      _snack('Please write a review.'.tr());
      return;
    }

    setState(() => _submitting = true);
    try {
      final docRef =
          FireStoreUtils.firestore.collection(Order_Rating).doc();
      final rate = RatingModel(
        id: docRef.id,
        productId: widget.orderModel.products.isNotEmpty
            ? widget.orderModel.products.first.id
            : '',
        comment: _commentCtrl.text.trim(),
        photos: [],
        rating: _stars,
        orderId: widget.orderModel.id,
        vendorId: widget.orderModel.vendorID,
        customerId: MyAppState.currentUser!.userID,
        uname: MyAppState.currentUser!.firstName +
            MyAppState.currentUser!.lastName,
        profile: MyAppState.currentUser!.profilePictureURL,
        createdAt: Timestamp.now(),
        reviewAttributes: {},
      );
      await FireStoreUtils.updateReviewbyId(rate);
      BehaviorTracker.track(kEvtRestaurantRated, {
        'vendorId': widget.orderModel.vendorID,
        'productId': rate.productId,
        'rating': _stars,
        'hasReviewText': _commentCtrl.text.trim().isNotEmpty,
        'orderId': widget.orderModel.id,
      });

      if (_productModel != null) {
        final newCount = _reviewCount + 1;
        final newSum = _reviewSum + _stars;
        await FireStoreUtils.updateProductReviewStats(
            _productModel!.id, newCount, newSum, _productModel!.reviewAttributes ?? {});
        _productModel!.reviewsCount = newCount;
        _productModel!.reviewsSum = newSum;
      }
      if (_vendorModel != null) {
        final newVendorCount = _vendorReviewCount + 1;
        final newVendorSum = _vendorReviewSum + _stars;
        await FireStoreUtils.updateVendorReviewStats(
            _vendorModel!.id, newVendorCount, newVendorSum);
        _vendorModel!.reviewsCount = newVendorCount;
        _vendorModel!.reviewsSum = newVendorSum;
      }

      if (mounted) {
        setState(() {
          _submitting = false;
          _submitted = true;
        });
      }
    } catch (e, s) {
      // ignore: avoid_print
      print('[REVIEW-DEBUG] OrderRatingScreen submit EXCEPTION: $e\n$s');
      if (mounted) setState(() => _submitting = false);
      _snack('Failed to submit. Please try again.'.tr());
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontFamily: AppThemeData.medium)),
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      backgroundColor: AppThemeData.neutral800,
    ));
  }

  void _appendKeyword(String keyword) {
    final current = _commentCtrl.text.trim();
    if (current.contains(keyword)) return;
    final updated =
        current.isEmpty ? keyword : '$current  $keyword';
    _commentCtrl.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
    );
  }

  String _ratingLabel(double stars) {
    if (stars >= 5) return 'Excellent! ✨'.tr();
    if (stars >= 4) return 'Very Good! 😊'.tr();
    if (stars >= 3) return 'Good 👍'.tr();
    if (stars >= 2) return 'Fair 😐'.tr();
    if (stars >= 1) return 'Poor 😞'.tr();
    return '';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor:
          dark ? AppThemeData.darkBgSecondary : AppThemeData.neutral50,
      appBar: AppBar(
        title: Text(
          'Rate Your Order'.tr(),
          style: AppTypography.h5.copyWith(
            color: dark
                ? AppThemeData.darkTextPrimary
                : AppThemeData.neutral900,
          ),
        ),
        backgroundColor:
            dark ? AppThemeData.darkBgPrimary : AppThemeData.neutral0,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(
          color:
              dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
        ),
      ),
      body: _loading
          ? _RatingSkeletonLoader(dark: dark)
          : SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                // Extra bottom padding so submit button clears keyboard
                MediaQuery.of(context).viewInsets.bottom > 0
                    ? MediaQuery.of(context).viewInsets.bottom + 20
                    : 32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildHeader(dark),
                  const SizedBox(height: AppSpacing.spacing6),
                  _alreadyRated || _submitted
                      ? _buildReadOnlyCard(dark)
                      : _buildFormCard(dark),
                ],
              ),
            ),
    );
  }

  // ── Restaurant header ─────────────────────────────────────────────────────

  Widget _buildHeader(bool dark) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.network(
            widget.orderModel.vendor.photo.isNotEmpty
                ? widget.orderModel.vendor.photo
                : placeholderImage,
            width: 82,
            height: 82,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: AppThemeData.neutral100,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.store_rounded,
                  color: AppThemeData.neutral400, size: 34),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          widget.orderModel.vendor.title,
          style: AppTypography.h5.copyWith(
            color: dark
                ? AppThemeData.darkTextPrimary
                : AppThemeData.neutral900,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          DateFormat('dd MMM yyyy').format(
            DateTime.fromMillisecondsSinceEpoch(
              widget.orderModel.createdAt.millisecondsSinceEpoch,
            ),
          ),
          style: AppTypography.bodySmall.copyWith(
            color: dark
                ? AppThemeData.darkTextSecondary
                : AppThemeData.neutral500,
          ),
        ),
      ],
    );
  }

  // ── Editable form card ────────────────────────────────────────────────────

  Widget _buildFormCard(bool dark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgPrimary : Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Prompt label ──────────────────────────────────────────────────
          Text(
            'How was your experience?'.tr(),
            style: AppTypography.labelLarge.copyWith(
              fontSize: 16,
              color: dark
                  ? AppThemeData.darkTextSecondary
                  : AppThemeData.neutral600,
            ),
          ),
          const SizedBox(height: 20),

          // ── Star rating ───────────────────────────────────────────────────
          RatingBar.builder(
            initialRating: _stars,
            minRating: 1,
            direction: Axis.horizontal,
            allowHalfRating: false,
            itemCount: 5,
            itemSize: 46,
            itemPadding: const EdgeInsets.symmetric(horizontal: 5),
            itemBuilder: (_, index) {
              final filled = index < _stars;
              return Icon(
                filled ? Icons.star_rounded : Icons.star_outline_rounded,
                color: filled
                    ? AppThemeData.warning500
                    : (dark
                        ? AppThemeData.neutral600
                        : AppThemeData.neutral300),
              );
            },
            onRatingUpdate: (val) => setState(() => _stars = val),
            unratedColor: dark
                ? AppThemeData.neutral700
                : AppThemeData.neutral200,
          ),

          // ── Animated label ────────────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: _stars > 0
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey(_stars),
                      tween: Tween(begin: 0.75, end: 1.0),
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.elasticOut,
                      builder: (_, scale, child) =>
                          Transform.scale(scale: scale, child: child),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppThemeData.warning500
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _ratingLabel(_stars),
                          style: AppTypography.labelMedium.copyWith(
                            color: AppThemeData.warning500,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          const SizedBox(height: 24),
          Divider(
              height: 1,
              color: dark
                  ? AppThemeData.neutral800
                  : AppThemeData.neutral100),
          const SizedBox(height: 20),

          // ── Keyword chips (placed ABOVE text field — never overlaps) ──────
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Quick tags'.tr(),
              style: AppTypography.labelSmall.copyWith(
                fontSize: 11,
                letterSpacing: 0.5,
                color: dark
                    ? AppThemeData.darkTextSecondary
                    : AppThemeData.neutral500,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kKeywords.map((kw) {
                final selected =
                    _commentCtrl.text.contains(kw);
                return GestureDetector(
                  onTap: () {
                    _appendKeyword(kw);
                    setState(() {});
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 7),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppThemeData.primary500
                          : (dark
                              ? AppThemeData.neutral800
                              : AppThemeData.neutral50),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? AppThemeData.primary500
                            : (dark
                                ? AppThemeData.neutral700
                                : AppThemeData.neutral200),
                        width: 1.2,
                      ),
                    ),
                    child: Text(
                      kw,
                      style: AppTypography.labelSmall.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? Colors.white
                            : (dark
                                ? AppThemeData.neutral300
                                : AppThemeData.neutral600),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 16),

          // ── Review text field ─────────────────────────────────────────────
          AnimatedContainer(
            key: _textFieldKey,
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: dark
                  ? AppThemeData.darkBgSecondary
                  : AppThemeData.neutral50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _focused
                    ? AppThemeData.primary500
                    : (dark
                        ? AppThemeData.neutral700
                        : AppThemeData.neutral200),
                width: _focused ? 1.6 : 1.0,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: AppThemeData.primary500
                            .withValues(alpha: 0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : [],
            ),
            child: TextField(
              controller: _commentCtrl,
              focusNode: _focusNode,
              maxLines: null,
              minLines: 4,
              maxLength: 1000,
              buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: AppTypography.bodyMedium.copyWith(
                height: 1.6,
                fontSize: 14,
                color: dark
                    ? AppThemeData.darkTextPrimary
                    : AppThemeData.neutral900,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Tell others about your order…'.tr(),
                hintStyle: AppTypography.bodyMedium.copyWith(
                  fontSize: 14,
                  height: 1.6,
                  color: dark
                      ? AppThemeData.darkTextTertiary
                      : AppThemeData.neutral400,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Submit button ─────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppThemeData.primary500,
                disabledBackgroundColor: dark
                    ? AppThemeData.neutral700
                    : AppThemeData.neutral200,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor:
                            AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Text(
                      'Submit Review'.tr(),
                      style: AppTypography.labelLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Read-only card (already rated / just submitted) ───────────────────────

  Widget _buildReadOnlyCard(bool dark) {
    final stars = _submitted ? _stars : _existingStars;
    final comment =
        _submitted ? _commentCtrl.text.trim() : _existingComment;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgPrimary : Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Badge ─────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppThemeData.success500.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded,
                    color: AppThemeData.success500, size: 18),
                const SizedBox(width: 6),
                Text(
                  _submitted
                      ? 'Review Submitted! 🎉'.tr()
                      : 'Already Submitted'.tr(),
                  style: AppTypography.labelMedium.copyWith(
                    color: AppThemeData.success500,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.spacing5),

          // ── Read-only stars ───────────────────────────────────────────────
          RatingBar.builder(
            initialRating: stars,
            minRating: 1,
            direction: Axis.horizontal,
            allowHalfRating: true,
            ignoreGestures: true,
            itemCount: 5,
            itemSize: 44,
            itemPadding: const EdgeInsets.symmetric(horizontal: 6),
            itemBuilder: (_, __) =>
                Icon(Icons.star_rounded, color: AppThemeData.warning500),
            onRatingUpdate: (_) {},
          ),

          const SizedBox(height: 8),
          Text(
            _ratingLabel(stars),
            style: AppTypography.labelSmall.copyWith(
              color: AppThemeData.warning500,
              fontWeight: FontWeight.w600,
            ),
          ),

          if (comment.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.spacing5),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: dark
                    ? AppThemeData.darkBgSecondary
                    : AppThemeData.neutral50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: dark
                      ? AppThemeData.neutral700
                      : AppThemeData.neutral200,
                ),
              ),
              child: Text(
                comment,
                style: AppTypography.bodyMedium.copyWith(
                  height: 1.6,
                  color: dark
                      ? AppThemeData.darkTextSecondary
                      : AppThemeData.neutral700,
                ),
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.spacing5),

          // ── Disabled button ───────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: dark
                    ? AppThemeData.neutral800
                    : AppThemeData.neutral100,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: null,
              child: Text(
                'Review Submitted'.tr(),
                style: AppTypography.labelLarge.copyWith(
                  color: AppThemeData.neutral400,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Skeleton loader ──────────────────────────────────────────────────────────

class _RatingSkeletonLoader extends StatefulWidget {
  final bool dark;

  const _RatingSkeletonLoader({required this.dark});

  @override
  State<_RatingSkeletonLoader> createState() =>
      _RatingSkeletonLoaderState();
}

class _RatingSkeletonLoaderState extends State<_RatingSkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // ── Shimmer box ────────────────────────────────────────────────────────────

  Widget _box(double w, double h, {double radius = 8}) {
    final base = widget.dark
        ? const Color(0xFF252525)
        : const Color(0xFFE8E8E8);
    final hi = widget.dark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFF4F4F4);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              colors: [base, hi, base],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment(-2.0 + 2.6 * t, 0),
              end: Alignment(-0.4 + 2.6 * t, 0),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardBg =
        widget.dark ? const Color(0xFF1C1C1C) : Colors.white;
    final divColor = widget.dark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFFF0F0F0);

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Header skeleton ────────────────────────────────────────────────
          Column(
            children: [
              // Restaurant image circle
              _box(82, 82, radius: 18),
              const SizedBox(height: 12),
              // Name line
              _box(160, 18, radius: 9),
              const SizedBox(height: 8),
              // Date line
              _box(100, 12, radius: 6),
            ],
          ),

          const SizedBox(height: 28),

          // ── Form card skeleton ─────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(22),
              boxShadow: widget.dark
                  ? []
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 24,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // "How was your experience?" label
                _box(190, 15, radius: 7),
                const SizedBox(height: 22),

                // 5 star circles — horizontal: 5 matches RatingBar itemPadding
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    return Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 5),
                      child: _box(44, 44, radius: 22),
                    );
                  }),
                ),

                const SizedBox(height: 24),
                Divider(height: 1, color: divColor),
                const SizedBox(height: 20),

                // "Quick tags" label
                Align(
                  alignment: Alignment.centerLeft,
                  child: _box(72, 11, radius: 5),
                ),
                const SizedBox(height: 12),

                // Keyword chip row 1
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _box(90, 30, radius: 20),
                      _box(110, 30, radius: 20),
                      _box(96, 30, radius: 20),
                      _box(80, 30, radius: 20),
                      _box(118, 30, radius: 20),
                      _box(88, 30, radius: 20),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Text box
                _box(double.infinity, 110, radius: 16),

                const SizedBox(height: 24),

                // Submit button
                _box(double.infinity, 54, radius: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
