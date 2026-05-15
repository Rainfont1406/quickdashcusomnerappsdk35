import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/AppGlobal.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/VendorCategoryModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/categoryDetailsScreen/CategoryDetailsScreen.dart';
import 'package:emartconsumer/utils/network_image_widget.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CuisinesScreen extends StatefulWidget {
  const CuisinesScreen({Key? key, this.isPageCallFromHomeScreen = false, this.isPageCallForDineIn = false}) : super(key: key);

  @override
  _CuisinesScreenState createState() => _CuisinesScreenState();
  final bool? isPageCallFromHomeScreen;
  final bool? isPageCallForDineIn;
}

class _CuisinesScreenState extends State<CuisinesScreen> {
  final fireStoreUtils = FireStoreUtils();
  late Future<List<VendorCategoryModel>> categoriesFuture;
  SharedPreferences? sp;
  String? lastID = "0";

  @override
  void initState() {
    super.initState();
    getLastId();
    categoriesFuture = fireStoreUtils.getCuisines();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: isDarkMode(context) ? AppThemeData.surfaceDark : AppThemeData.surface,
        appBar: widget.isPageCallFromHomeScreen! ? AppGlobal.buildAppBar(context, "Categories".tr()) : null,
        body: FutureBuilder<List<VendorCategoryModel>>(
            future: categoriesFuture,
            initialData: const [],
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasData || (snapshot.data?.isNotEmpty ?? false)) {
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: snapshot.data!.length,
                  shrinkWrap: true,
                  itemBuilder: (context, index) {
                    return snapshot.data != null ? buildCuisineCell(snapshot.data![index], lastID!) : showEmptyState('No Categories'.tr(), context);
                  },
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 0.7,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 5,
                  ),
                );
              }
              return const CircularProgressIndicator();
            }));
  }

  Widget buildCuisineCell(VendorCategoryModel cuisineModel, String lastID) {
    return InkWell(
      onTap: () {
        if (sp != null) {
          this.lastID = cuisineModel.id;
          sp!.setString("CatLastID", cuisineModel.id.toString());
          setState(() {});
        }
        push(
            context,
            CategoryDetailsScreen(
              category: cuisineModel,
              isDineIn: widget.isPageCallForDineIn!,
            ));
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Circle image with border (matching home screen design)
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isDarkMode(context)
                    ? AppThemeData.grey800
                    : AppThemeData.grey200,
                width: 2,
              ),
            ),
            child: ClipOval(
              child: NetworkImageWidget(
                imageUrl: cuisineModel.photo.toString(),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 5),
          // Text below image with fixed height
          Container(
            width: 70,
            height: 32,
            child: Text(
              cuisineModel.title.toString(),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDarkMode(context)
                    ? AppThemeData.grey50
                    : AppThemeData.grey900,
                fontFamily: AppThemeData.medium,
                fontSize: 12,
              ),
            ).tr(),
          ),
        ],
      ),
    );
  }

  Future<void> getLastId() async {
    sp = await SharedPreferences.getInstance();
    if (sp!.getString("CatLastID") != null) {
      lastID = sp?.getString("CatLastID");
    }
  }
}

//Container(
//             decoration: BoxDecoration(
//
//               borderRadius: BorderRadius.circular(8),
//               image: DecorationImage(
//                 image: NetworkImage(cuisineModel.photo),
//                 fit: BoxFit.cover,
//                 colorFilter: ColorFilter.mode(
//                     Colors.black.withOpacity(0.5), BlendMode.darken),
//               ),
//             ),
//             child: Center(
//               child: Text(
//                 cuisineModel.title,
//                 style: TextStyle(
//                     color: Colors.white,  fontSize: 20),
//               ).tr(),
//             ),
//           ),
