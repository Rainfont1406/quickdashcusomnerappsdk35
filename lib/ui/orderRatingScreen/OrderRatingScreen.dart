import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/OrderModel.dart';
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/model/Ratingmodel.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import '../../constants/typography.dart';
import '../../constants/spacing.dart';

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
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

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

  Future<void> _submit() async {
    if (_stars == 0) {
      _snack('Please select a star rating.'.tr(), AppThemeData.neutral800);
      return;
    }
    if (_commentCtrl.text.trim().isEmpty) {
      _snack('Please write a review.'.tr(), AppThemeData.neutral800);
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

      if (_productModel != null) {
        _productModel!.reviewsCount = _reviewCount + 1;
        _productModel!.reviewsSum = _reviewSum + _stars;
        await FireStoreUtils.updateProduct(_productModel!);
      }
      if (_vendorModel != null) {
        _vendorModel!.reviewsCount = _vendorReviewCount + 1;
        _vendorModel!.reviewsSum = _vendorReviewSum + _stars;
        await FireStoreUtils.updateVendor(_vendorModel!);
      }

      if (mounted) setState(() { _submitting = false; _submitted = true; });
    } catch (_) {
      if (mounted) setState(() => _submitting = false);
      _snack('Failed to submit. Please try again.'.tr(), AppThemeData.error500);
    }
  }

  void _snack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      backgroundColor: bg,
    ));
  }

  String _label(double stars) {
    if (stars >= 5) return 'Excellent!'.tr();
    if (stars >= 4) return 'Very Good'.tr();
    if (stars >= 3) return 'Good'.tr();
    if (stars >= 2) return 'Fair'.tr();
    return 'Poor'.tr();
  }

  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    return Scaffold(
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
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(
          color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
        ),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator.adaptive(
                valueColor:
                    AlwaysStoppedAnimation(AppThemeData.primary500),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.spacing5),
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
          borderRadius: BorderRadius.circular(16),
          child: Image.network(
            widget.orderModel.vendor.photo.isNotEmpty
                ? widget.orderModel.vendor.photo
                : placeholderImage,
            width: 80,
            height: 80,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppThemeData.neutral100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.store_rounded,
                  color: AppThemeData.neutral400, size: 32),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.spacing3),
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
        const SizedBox(height: AppSpacing.spacing1),
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
      padding: const EdgeInsets.all(AppSpacing.spacing5),
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgPrimary : AppThemeData.neutral0,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'How was your experience?'.tr(),
            style: AppTypography.labelLarge.copyWith(
              color: dark
                  ? AppThemeData.darkTextSecondary
                  : AppThemeData.neutral600,
            ),
          ),
          const SizedBox(height: AppSpacing.spacing4),

          // ── Star selector ──
          RatingBar.builder(
            initialRating: _stars,
            minRating: 1,
            direction: Axis.horizontal,
            allowHalfRating: false,
            itemCount: 5,
            itemSize: 46,
            itemPadding: const EdgeInsets.symmetric(horizontal: 6),
            itemBuilder: (_, __) =>
                Icon(Icons.star_rounded, color: AppThemeData.warning500),
            onRatingUpdate: (val) => setState(() => _stars = val),
          ),

          if (_stars > 0) ...[
            const SizedBox(height: AppSpacing.spacing2),
            Text(
              _label(_stars),
              style: AppTypography.labelSmall.copyWith(
                color: AppThemeData.warning500,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.spacing5),

          // ── Review text field ──
          Container(
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
            child: TextField(
              controller: _commentCtrl,
              maxLines: 5,
              minLines: 4,
              style: AppTypography.bodyMedium.copyWith(
                color: dark
                    ? AppThemeData.darkTextPrimary
                    : AppThemeData.neutral900,
              ),
              decoration: InputDecoration(
                hintText: 'Share your experience with others...'.tr(),
                hintStyle: AppTypography.bodyMedium.copyWith(
                  color: dark
                      ? AppThemeData.darkTextTertiary
                      : AppThemeData.neutral400,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.spacing5),

          // ── Submit button ──
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppThemeData.primary500,
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

  // ── Read-only card (already submitted) ────────────────────────────────────

  Widget _buildReadOnlyCard(bool dark) {
    final stars = _submitted ? _stars : _existingStars;
    final comment =
        _submitted ? _commentCtrl.text.trim() : _existingComment;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.spacing5),
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgPrimary : AppThemeData.neutral0,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Already submitted badge ──
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
                  'Already Submitted'.tr(),
                  style: AppTypography.labelMedium.copyWith(
                    color: AppThemeData.success500,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.spacing5),

          // ── Read-only stars ──
          RatingBar.builder(
            initialRating: stars,
            minRating: 1,
            direction: Axis.horizontal,
            allowHalfRating: true,
            ignoreGestures: true,
            itemCount: 5,
            itemSize: 40,
            itemPadding: const EdgeInsets.symmetric(horizontal: 6),
            itemBuilder: (_, __) =>
                Icon(Icons.star_rounded, color: AppThemeData.warning500),
            onRatingUpdate: (_) {},
          ),

          const SizedBox(height: AppSpacing.spacing2),
          Text(
            _label(stars),
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
                  color: dark
                      ? AppThemeData.darkTextSecondary
                      : AppThemeData.neutral700,
                ),
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.spacing5),

          // ── Disabled submit button ──
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: dark
                    ? AppThemeData.neutral800
                    : AppThemeData.neutral200,
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
