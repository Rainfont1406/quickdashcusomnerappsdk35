import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/src/public_ext.dart';
import 'package:emartconsumer/AppGlobal.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/behavior/behavior_tracker.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
// import 'package:emartconsumer/ui/vendorProductsScreen/NewVendorProductsScreen.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../constants.dart';
import '../../widget/road_distance_text.dart';
import '../vendorProductsScreen/newVendorProductsScreen.dart';

class ViewAllNewArrivalStoreScreen extends StatefulWidget {
  const ViewAllNewArrivalStoreScreen({Key? key, this.isPageCallForDineIn = false, this.isPageCallForPopular = false,required this.vendorList}) : super(key: key);

  @override
  _ViewAllNewArrivalStoreScreenState createState() => _ViewAllNewArrivalStoreScreenState();

  final bool? isPageCallForPopular;
  final bool? isPageCallForDineIn;
  final List<VendorModel> vendorList;
}

class _ViewAllNewArrivalStoreScreenState extends State<ViewAllNewArrivalStoreScreen> {
  Stream<List<VendorModel>>? vendorsFuture;
  final fireStoreUtils = FireStoreUtils();
  List<VendorModel> newArrivalLst = [];
  var position = const LatLng(23.12, 70.22);
  bool showLoader = true;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    _getUserLocation();
    newArrivalLst = widget.vendorList;
    // setState(() {
    //   if (widget.isPageCallForDineIn!) {
    //     if (widget.isPageCallForPopular!) {
    //       lstNewArrivalStore = fireStoreUtils.getPopularsVendors(path: "isDineIn").asBroadcastStream();
    //     } else {
    //       lstNewArrivalStore = fireStoreUtils.getVendorsForNewArrival(path: "isDineIn").asBroadcastStream();
    //     }
    //   } else {
    //     lstNewArrivalStore = fireStoreUtils.getVendorsForNewArrival().asBroadcastStream();
    //   }
    //
      showLoader = false;
    // });
    setState(() {

    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: isDarkMode(context) ? AppThemeData.surfaceDark : AppThemeData.surface,
        appBar: AppGlobal.buildAppBar(context, (widget.isPageCallForPopular ?? false) ? "Popular Stores".tr() : "New Arrival Items".tr()),
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
                : ListView.builder(
                shrinkWrap: true,
                scrollDirection: Axis.vertical,
                physics: const BouncingScrollPhysics(),
                itemCount: newArrivalLst.length,
                itemBuilder: (context, index) => buildPopularsItem(newArrivalLst[index]))));
  }

  /// Same "Closed" pill used on the home screen restaurant card.
  Widget _closedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEEEE),
        borderRadius: BorderRadius.circular(50),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFDC2626).withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFFDC2626),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'Closed',
            style: TextStyle(
              color: Color(0xFFDC2626),
              fontSize: 11,
              height: 1.2,
              fontFamily: AppThemeData.semiBold,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPopularsItem(VendorModel vendorModel) {
    return GestureDetector(
      onTap: () {
        BehaviorTracker.setNextEntrySource('Home');
        push(
          context,
          NewVendorProductsScreen(vendorModel: vendorModel),
        );
      },
      child: Container(
        height: (MediaQuery.of(context).size.width * 0.55).clamp(200.0, 300.0),
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
                child: Stack(
              children: [
                CachedNetworkImage(
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
                ),
                if (!vendorModel.isAcceptingOrders)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: _closedBadge(),
                  ),
              ],
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
                            style:  TextStyle(
                              letterSpacing: 0.5,
                              fontWeight: FontWeight.bold,
                              color: isDarkMode(context) ? AppThemeData.grey50 : AppThemeData.grey900,
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
                              style:  TextStyle(
                                letterSpacing: 0.5,
                                color: isDarkMode(context) ? AppThemeData.grey400 : AppThemeData.grey500,
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
    setState(() {
      position = LatLng(MyAppState.selectedPosotion.location?.latitude ?? 0.0, MyAppState.selectedPosotion.location?.longitude ?? 0.0);
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  String? getKm(double latitude, double longitude) {
    double distanceInMeters = Geolocator.distanceBetween(latitude, longitude, position.latitude, position.longitude);
    double kilometer = distanceInMeters / 1000;
    print("KiloMeter$kilometer");

    double minutes = 1.2;
    double value = minutes * kilometer;
    final int hour = value ~/ 60;
    final double minute = value % 60;
    print('${hour.toString().padLeft(2, "0")}:${minute.toStringAsFixed(0).padLeft(2, "0")}');
    return kilometer.toStringAsFixed(currencyData?.decimal ?? 2).toString();
  }
}
