import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/src/public_ext.dart';
import 'package:emartconsumer/AppGlobal.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/behavior/behavior_tracker.dart';
import 'package:emartconsumer/services/shared_vendors_watcher.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
// import 'package:emartconsumer/ui/vendorProductsScreen/NewVendorProductsScreen.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../constants.dart';
import '../../utils/network_image_widget.dart';
import '../../widget/road_distance_text.dart';
import '../vendorProductsScreen/newVendorProductsScreen.dart';

class ViewAllPopularStoreScreen extends StatefulWidget {
  const ViewAllPopularStoreScreen({Key? key}) : super(key: key);

  @override
  _ViewAllPopularStoreScreenState createState() => _ViewAllPopularStoreScreenState();
}

class _ViewAllPopularStoreScreenState extends State<ViewAllPopularStoreScreen> {
  Stream<List<VendorModel>>? vendorsFuture;
  List<VendorModel> storeAllLst = [];

  // List<VendorModel> popularStoreLst = [];
  var position = const LatLng(23.12, 70.22);
  bool showLoader = true;

  @override
  void initState() {
    super.initState();
    _getUserLocation();
    // 2026-09-11: was fireStoreUtils.getAllStores(), a second independent
    // raw GeoFirestore listener over the whole section duplicating
    // HomeScreen's own (already migrated 2026-09-07) - reads off the same
    // shared, Bunny-mirrored watcher instead of opening another one.
    final sectionId = sectionConstantModel?.id ?? '';
    final lat = MyAppState.selectedPosotion.location?.latitude ?? 0.0;
    final lng = MyAppState.selectedPosotion.location?.longitude ?? 0.0;
    vendorsFuture = SharedVendorsWatcher.watch(sectionId, lat, lng).asBroadcastStream();
    vendorsFuture!.listen((value) {
      storeAllLst.clear();
      storeAllLst.addAll(value);
      List<VendorModel> temp5 = storeAllLst.where((element) => num.parse((element.reviewsSum / element.reviewsCount).toString()) == 5).toList();
      List<VendorModel> temp5_ = storeAllLst
          .where((element) => num.parse((element.reviewsSum / element.reviewsCount).toString()) > 4 && num.parse((element.reviewsSum / element.reviewsCount).toString()) < 5)
          .toList();
      List<VendorModel> temp4 = storeAllLst
          .where((element) => num.parse((element.reviewsSum / element.reviewsCount).toString()) > 3 && num.parse((element.reviewsSum / element.reviewsCount).toString()) < 4)
          .toList();
      List<VendorModel> temp3 = storeAllLst
          .where((element) => num.parse((element.reviewsSum / element.reviewsCount).toString()) > 2 && num.parse((element.reviewsSum / element.reviewsCount).toString()) < 3)
          .toList();
      List<VendorModel> temp2 = storeAllLst
          .where((element) => num.parse((element.reviewsSum / element.reviewsCount).toString()) > 1 && num.parse((element.reviewsSum / element.reviewsCount).toString()) < 2)
          .toList();
      List<VendorModel> temp1 = storeAllLst.where((element) => num.parse((element.reviewsSum / element.reviewsCount).toString()) == 1).toList();
      List<VendorModel> temp0 = storeAllLst.where((element) => num.parse((element.reviewsSum / element.reviewsCount).toString()) == 0).toList();
      List<VendorModel> temp0_ = storeAllLst.where((element) => element.reviewsSum == 0 && element.reviewsCount == 0).toList();

      storeAllLst.clear();
      storeAllLst.addAll(temp5);
      storeAllLst.addAll(temp5_);
      storeAllLst.addAll(temp4);
      storeAllLst.addAll(temp3);
      storeAllLst.addAll(temp2);
      storeAllLst.addAll(temp1);
      storeAllLst.addAll(temp0);
      storeAllLst.addAll(temp0_);
      print("==================storeAllLst==${storeAllLst}");
      setState(() {
        showLoader = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: isDarkMode(context) ? AppThemeData.surfaceDark : AppThemeData.surface,
        appBar: AppGlobal.buildAppBar(context, "Most Popular".tr()),
        body: Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            margin: const EdgeInsets.fromLTRB(0, 10, 0, 10),
            child: showLoader
                ? Center(
                    child: CircularProgressIndicator.adaptive(
                      valueColor: AlwaysStoppedAnimation(AppThemeData.primary500),
                    ),
                  )
                : storeAllLst.isEmpty
                    ? showEmptyState('No Items'.tr(), context)
                    : ListView.builder(
                        shrinkWrap: true,
                        scrollDirection: Axis.vertical,
                        physics: const BouncingScrollPhysics(),
                        itemCount: storeAllLst.length,
                        itemBuilder: (context, index) => buildPopularsItem(storeAllLst[index]))));
  }

  Widget buildPopularsItem(VendorModel vendorModel) {
    return GestureDetector(
      onTap: () {
        BehaviorTracker.setNextEntrySource('Home');
        precacheVendorHeroImage(context, vendorModel);
        push(
          context,
          NewVendorProductsScreen(vendorModel: vendorModel),
        );
      },
      child: Container(
        width: MediaQuery.of(context).size.width * 0.75,
        height: (MediaQuery.of(context).size.width * 0.62).clamp(200.0, 300.0),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        clipBehavior: Clip.antiAlias,
        decoration: ShapeDecoration(
          color: isDarkMode(context) ? AppThemeData.grey900 : AppThemeData.grey50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          shadows: [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 32,
              offset: Offset(0, 0),
              spreadRadius: 0,
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
                child: CachedNetworkImage(
              imageUrl: getImageVAlidUrl(vendorModel.photo),
              imageBuilder: (context, imageProvider) => Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
                ),
              ),
              placeholder: (context, url) => Center(
                  child: CircularProgressIndicator.adaptive(
                valueColor: AlwaysStoppedAnimation(AppThemeData.primary500),
              )),
              errorWidget: (context, url, error) => ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Image.network(
                    placeholderImage,
                    fit: BoxFit.cover,
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height,
                  )),
              fit: BoxFit.cover,
            )),
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.fromLTRB(15, 0, 5, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(vendorModel.title,
                            maxLines: 1,
                            style: const TextStyle(
                              letterSpacing: 0.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xff000000),
                            )).tr(),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0, bottom: 0),
                        child: Column(
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.star,
                                  size: 20,
                                  color: AppThemeData.primary500,
                                ),
                                const SizedBox(width: 3),
                                Text(vendorModel.reviewsCount != 0 ? (vendorModel.reviewsSum / vendorModel.reviewsCount).toStringAsFixed(1) : 0.toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xff666666),
                                    )),
                                const SizedBox(width: 3),
                                Text("(${vendorModel.reviewsCount})",
                                    style: const TextStyle(
                                      letterSpacing: 0.5,
                                      color: Color(0xff666666),
                                    )),
                              ],
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      const ImageIcon(
                        AssetImage('assets/images/location3x.png'),
                        size: 15,
                        color: Color(0xff555353),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 5, right: 5),
                          child: Text(vendorModel.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                letterSpacing: 0.5,
                                color: Color(0xff555353),
                              )),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 10, right: 10),
                        child: Row(
                          children: [
                            Container(
                              height: 5,
                              width: 5,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xff555353),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 10, right: 10),
                              child: RoadDistanceText(
                                vendorLat: vendorModel.latitude,
                                vendorLon: vendorModel.longitude,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xff555353),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  void _getUserLocation() async {
    //   var positions = await GeolocatorPlatform.instance
    //      .getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

    setState(() {
      position = LatLng(MyAppState.selectedPosotion.location!.latitude, MyAppState.selectedPosotion.location!.longitude);
      // cameraPosition = CameraPosition(
      //   target: LatLng(position.latitude, position.longitude),
      //   zoom: 14.4746,
      // );
    });
  }

  String? getKm(double latitude, double longitude) {
    double distanceInMeters = Geolocator.distanceBetween(latitude, longitude, position.latitude, position.longitude);
    double kilometer = distanceInMeters / 1000;

    double minutes = 1.2;
    double value = minutes * kilometer;
    final int hour = value ~/ 60;
    final double minute = value % 60;
    return kilometer.toStringAsFixed(currencyData!.decimal).toString();
  }
}
