import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/Ratingmodel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';

class ReviewListScreen extends StatefulWidget {
  final String vendorId;

  const ReviewListScreen({super.key, required this.vendorId});

  @override
  State<ReviewListScreen> createState() => _ReviewListScreenState();
}

class _ReviewListScreenState extends State<ReviewListScreen> {
  List<RatingModel> ratingList = <RatingModel>[];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    getAllReview();
  }

  getAllReview() async {
    await FireStoreUtils.getVendorReviews(widget.vendorId).then((value) {
      ratingList = value;
    });
    setState(() {
      isLoading = false;
    });
  }

  double get _averageRating {
    if (ratingList.isEmpty) return 0;
    final sum = ratingList.fold<double>(0, (acc, r) => acc + (r.rating ?? 0));
    return sum / ratingList.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDarkMode(context) ? AppThemeData.surfaceDark : AppThemeData.grey100,
      appBar: AppBar(
        backgroundColor: AppThemeData.primary500,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
        ),
        title: Text(
          "Reviews".tr(),
          style: const TextStyle(
            fontFamily: AppThemeData.semiBold,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
      ),
      body: isLoading
          ? loader()
          : ratingList.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    _buildRatingSummary(),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: ratingList.length,
                        itemBuilder: (context, index) => _buildReviewCard(ratingList[index]),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildRatingSummary() {
    return Container(
      color: AppThemeData.primary500,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _averageRating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 40,
                    fontFamily: AppThemeData.bold,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                RatingBar.builder(
                  ignoreGestures: true,
                  initialRating: _averageRating,
                  minRating: 1,
                  direction: Axis.horizontal,
                  itemCount: 5,
                  itemSize: 16,
                  itemPadding: const EdgeInsets.symmetric(horizontal: 1),
                  itemBuilder: (context, _) => const Icon(Icons.star, color: AppThemeData.warning300),
                  onRatingUpdate: (_) {},
                ),
                const SizedBox(height: 6),
                Text(
                  '${ratingList.length} ${'reviews'.tr()}',
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: AppThemeData.regular,
                    color: Colors.white.withOpacity(0.85),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewCard(RatingModel ratingModel) {
    final name = ratingModel.uname?.toString() ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: isDarkMode(context) ? AppThemeData.grey900 : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0x0A000000),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppThemeData.primary500.withOpacity(0.12),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 16,
                      fontFamily: AppThemeData.semiBold,
                      color: AppThemeData.primary500,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 15,
                          fontFamily: AppThemeData.semiBold,
                          color: isDarkMode(context) ? AppThemeData.grey50 : AppThemeData.grey900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      RatingBar.builder(
                        ignoreGestures: true,
                        initialRating: ratingModel.rating ?? 0.0,
                        minRating: 1,
                        direction: Axis.horizontal,
                        itemCount: 5,
                        itemSize: 14,
                        itemPadding: const EdgeInsets.symmetric(horizontal: 1),
                        itemBuilder: (context, _) => const Icon(Icons.star, color: AppThemeData.warning300),
                        onRatingUpdate: (_) {},
                      ),
                    ],
                  ),
                ),
                Text(
                  timestampToDateTime(ratingModel.createdAt!),
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: AppThemeData.regular,
                    color: isDarkMode(context) ? AppThemeData.grey400 : AppThemeData.grey500,
                  ),
                ),
              ],
            ),
            if (ratingModel.comment != null && ratingModel.comment!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                ratingModel.comment!,
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: AppThemeData.regular,
                  color: isDarkMode(context) ? AppThemeData.grey200 : AppThemeData.grey700,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppThemeData.primary500.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.star_outline_rounded, size: 52, color: AppThemeData.primary500),
          ),
          const SizedBox(height: 16),
          Text(
            "No Reviews Yet".tr(),
            style: TextStyle(
              fontSize: 18,
              fontFamily: AppThemeData.semiBold,
              color: isDarkMode(context) ? AppThemeData.grey50 : AppThemeData.grey900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Be the first to share your experience!".tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontFamily: AppThemeData.regular,
              color: isDarkMode(context) ? AppThemeData.grey400 : AppThemeData.grey500,
            ),
          ),
        ],
      ),
    );
  }
}
