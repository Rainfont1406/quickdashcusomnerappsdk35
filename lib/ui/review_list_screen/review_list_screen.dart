import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/Ratingmodel.dart';
import 'package:emartconsumer/model/VendorModel.dart';
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
  @override
  void initState() {
    // TODO: implement initState
    getAllReview();
    super.initState();
  }

  List<RatingModel> ratingList = <RatingModel>[];
  bool isLoading = true;

  getAllReview() async {
    await FireStoreUtils.getVendorReviews(widget.vendorId).then(
      (value) {
        ratingList = value;
      },
    );
    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDarkMode(context) ? AppThemeData.surfaceDark : AppThemeData.surface,
      appBar: AppBar(
        backgroundColor: isDarkMode(context) ? AppThemeData.surfaceDark : AppThemeData.surface,
        centerTitle: false,
        titleSpacing: 0,
        title: Text(
          "Reviews".tr(),
          textAlign: TextAlign.start,
          style: TextStyle(
            fontFamily: AppThemeData.medium,
            fontSize: 16,
            color: isDarkMode(context) ? AppThemeData.grey50 : AppThemeData.grey900,
          ),
        ),
      ),
      body: isLoading
          ? loader()
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: ratingList.isEmpty
                  ? Center(child: Text("No Review Found"))
                  : ListView.builder(
                      itemCount: ratingList.length,
                      itemBuilder: (context, index) {
                        RatingModel ratingModel = ratingList[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Container(
                            decoration: ShapeDecoration(
                              color: isDarkMode(context) ? AppThemeData.grey900 : AppThemeData.grey50,
                              shape: RoundedRectangleBorder(
                                side: BorderSide(width: 1, color: isDarkMode(context) ? AppThemeData.grey700 : AppThemeData.grey200),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ratingModel.uname.toString(),
                                    style: TextStyle(color: isDarkMode(context) ? AppThemeData.grey50 : AppThemeData.grey900, fontSize: 18, fontFamily: AppThemeData.semiBold),
                                  ),
                                  const SizedBox(
                                    height: 5,
                                  ),
                                  RatingBar.builder(
                                    ignoreGestures: true,
                                    initialRating: ratingModel.rating ?? 0.0,
                                    minRating: 1,
                                    direction: Axis.horizontal,
                                    itemCount: 5,
                                    itemSize: 18,
                                    itemPadding: const EdgeInsets.symmetric(horizontal: 2.0),
                                    itemBuilder: (context, _) => const Icon(
                                      Icons.star,
                                      color: AppThemeData.warning300,
                                    ),
                                    onRatingUpdate: (double rate) {},
                                  ),
                                  const SizedBox(
                                    height: 5,
                                  ),
                                  Text(
                                    ratingModel.comment.toString(),
                                    style: TextStyle(color: isDarkMode(context) ? AppThemeData.grey50 : AppThemeData.grey900, fontSize: 16, fontFamily: AppThemeData.medium),
                                  ),
                                  const SizedBox(
                                    height: 10,
                                  ),
                                  Text(
                                    timestampToDateTime(ratingModel.createdAt!),
                                    style: TextStyle(color: isDarkMode(context) ? AppThemeData.grey300 : AppThemeData.grey600, fontSize: 14, fontFamily: AppThemeData.medium),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
