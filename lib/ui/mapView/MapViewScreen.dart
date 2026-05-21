import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
// import 'package:emartconsumer/ui/vendorProductsScreen/NewVendorProductsScreen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_osm_plugin/flutter_osm_plugin.dart' as osmMap;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapViewScreen extends StatefulWidget {
  final bool isShowAppBar;

  const MapViewScreen({super.key, required this.isShowAppBar});

  @override
  _MapViewScreenState createState() => _MapViewScreenState();
}

class _MapViewScreenState extends State<MapViewScreen> {
  UserLocation? locationData;
  Stream<List<VendorModel>>? _mapFuture;
  Stream<List<VendorModel>>? vendorsFuture;
  late BitmapDescriptor mapMarker;
  late BitmapDescriptor mapMarkerSelect;
  int selected = 0;
  ScrollController contro = ScrollController();
  Timer? _scrollDebounce;

  void setCustomMaker() async {
    if (selectedMapType == "osm") {
      departureOsmIcon = Image.asset("assets/images/map_selected3x.png", width: 30, height: 30); //OSM
    } else {
      mapMarker = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(),
        'assets/images/map_unselected2x.png',
      );
      mapMarkerSelect = await BitmapDescriptor.fromAssetImage(const ImageConfiguration(), 'assets/images/map_selected3x.png');
    }
  }

  GoogleMapController? _mapController;
  FireStoreUtils fireStoreUtils = FireStoreUtils();
  List<VendorModel> vendors = [];

  var id, inx, latpos, lotpos;
  final itemKey = GlobalKey();

  // var controller = IndexedScrollController();
  late osmMap.MapController mapOsmController;
  Map<String, osmMap.GeoPoint> osmMarkers = <String, osmMap.GeoPoint>{};
  Image? departureOsmIcon; //OSM

  @override
  void initState() {
    // _getLocation();
    super.initState();
    if (selectedMapType == 'osm') {
      mapOsmController = osmMap.MapController(initPosition: osmMap.GeoPoint(latitude: 20.9153, longitude: -100.7439), useExternalTracking: false); //OSM
    }
    setState(() {
      _mapFuture = (allstoreList.isNotEmpty
              ? Stream.value(List<VendorModel>.from(allstoreList))
              : fireStoreUtils.getAllStores())
          .asBroadcastStream();
      vendorsFuture = _mapFuture;
    });
    setCustomMaker();
  }

  @override
  void dispose() {
    _scrollDebounce?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // Card width is 78 % of screen width, capped at 300 px; step includes 12 px right margin.
  static double _cardWidthFor(double screenWidth) =>
      (screenWidth * 0.78).clamp(200.0, 300.0);
  static double _cardStepFor(double screenWidth) =>
      _cardWidthFor(screenWidth) + 12.0;

  void scrollable() {
    if (contro.hasClients) {
      final screenWidth = MediaQuery.of(context).size.width;
      contro.jumpTo(id * _cardStepFor(screenWidth));
    }
  }

  Future<void> updateCameraLocation(
    LatLng source,
    LatLng destination,
    GoogleMapController? mapController,
  ) async {
    if (mapController == null) return;

    LatLngBounds bounds;

    if (source.latitude > destination.latitude && source.longitude > destination.longitude) {
      bounds = LatLngBounds(southwest: destination, northeast: source);
    } else if (source.longitude > destination.longitude) {
      bounds = LatLngBounds(southwest: LatLng(source.latitude, destination.longitude), northeast: LatLng(destination.latitude, source.longitude));
    } else if (source.latitude > destination.latitude) {
      bounds = LatLngBounds(southwest: LatLng(destination.latitude, source.longitude), northeast: LatLng(source.latitude, destination.longitude));
    } else {
      bounds = LatLngBounds(southwest: source, northeast: destination);
    }

    CameraUpdate cameraUpdate = CameraUpdate.newLatLngBounds(bounds, 100);

    return checkCameraLocation(cameraUpdate, mapController);
  }

  Future<void> checkCameraLocation(CameraUpdate cameraUpdate, GoogleMapController mapController) async {
    mapController.animateCamera(cameraUpdate);
    LatLngBounds l1 = await mapController.getVisibleRegion();
    LatLngBounds l2 = await mapController.getVisibleRegion();

    if (l1.southwest.latitude == -90 || l2.southwest.latitude == -90) {
      return checkCameraLocation(cameraUpdate, mapController);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double _screenWidth = MediaQuery.of(context).size.width;
    final double _cardWidth = _cardWidthFor(_screenWidth);
    final double _cardStep = _cardStepFor(_screenWidth);
    return Scaffold(
      appBar: widget.isShowAppBar == true ? AppBar() : null,
      body: Stack(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height,
            width: MediaQuery.of(context).size.width,
            child: StreamBuilder<List<VendorModel>>(
                stream: _mapFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return Center(
                      child: CircularProgressIndicator.adaptive(
                        valueColor: AlwaysStoppedAnimation(AppThemeData.primary500),
                      ),
                    );
                  }
                  vendors = snapshot.data!;
                  return selectedMapType == "osm"
                      ? RepaintBoundary(
                          child: osmMap.OSMFlutter(
                              controller: mapOsmController,
                              osmOption: osmMap.OSMOption(
                                userTrackingOption: const osmMap.UserTrackingOption(
                                  enableTracking: true,
                                  unFollowUser: false,
                                ),
                                zoomOption: const osmMap.ZoomOption(
                                  initZoom: 14,
                                  minZoomLevel: 2,
                                  maxZoomLevel: 19,
                                  stepZoom: 1.0,
                                ),
                                roadConfiguration: const osmMap.RoadOption(
                                  roadColor: Colors.yellowAccent,
                                ),
                              ),
                              onMapIsReady: (active) async {
                                if (active) {
                                  vendors.forEach(
                                    (element)  {
                                       mapOsmController
                                          .addMarker(osmMap.GeoPoint(latitude: element.latitude, longitude: element.longitude),
                                          markerIcon: osmMap.MarkerIcon(iconWidget: departureOsmIcon),
                                          angle: pi / 3,
                                          iconAnchor: osmMap.IconAnchor(
                                            anchor: osmMap.Anchor.top,
                                          ))
                                          .then((v) {
                                        osmMarkers['marker_${element.id}'] = osmMap.GeoPoint(latitude: element.latitude, longitude: element.longitude);
                                      });
                                      setState(()  {});
                                    },
                                  );
                                }
                              }),
                        )
                      : GoogleMap(
                          zoomControlsEnabled: false,
                          myLocationEnabled: true,
                          buildingsEnabled: false,
                          markers: List.generate(
                            vendors.length,
                            (index) => Marker(
                              onDrag: (latLng) {
                                setState(() {
                                  latpos = vendors[index].latitude;
                                  lotpos = vendors[index].longitude;
                                  CameraUpdate.newLatLngZoom(latLng, 10);
                                  move();
                                });
                              },
                              markerId: MarkerId('marker_$index'),
                              position: LatLng(vendors[index].latitude, vendors[index].longitude),
                              icon: selected == index ? mapMarkerSelect : mapMarker,
                              onTap: () {
                                setState(() {
                                  selected = index;
                                  id = index;
                                  inx = index;
                                  latpos = vendors[index].latitude;
                                  lotpos = vendors[index].longitude;
                                });
                              },
                              infoWindow: InfoWindow(
                                onTap: () {
                                  push(
                                    context,
                                    NewVendorProductsScreen(
                                      vendorModel: vendors[index],
                                    ),
                                  );
                                },
                                title: vendors[index].title,
                              ),
                            ),
                          ).toSet(),
                          mapType: MapType.normal,
                          initialCameraPosition: CameraPosition(
                            target: locationData == null
                                ? vendors.isNotEmpty
                                    ? LatLng(vendors.first.latitude, vendors.first.longitude)
                                    : const LatLng(0, 0)
                                : LatLng(locationData!.latitude, locationData!.longitude),
                            zoom: 14,
                          ),
                          onMapCreated: _onMapCreated,
                        );
                }),
          ),
          // ── Bottom vendor card strip ───────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 80,
            height: 160,
            child: StreamBuilder<List<VendorModel>>(
              stream: vendorsFuture,
              initialData: const [],
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const SizedBox.shrink();
                }
                vendors = snapshot.data!;
                return NotificationListener<ScrollNotification>(
                  onNotification: (_) {
                    if (contro.hasClients) {
                      final int idx = (contro.position.pixels / _cardStep)
                          .round()
                          .clamp(0, vendors.length - 1);
                      _scrollDebounce?.cancel();
                      _scrollDebounce =
                          Timer(const Duration(milliseconds: 150), () {
                        if (!mounted) return;
                        setState(() {
                          selected = idx;
                          latpos = vendors[idx].latitude;
                          lotpos = vendors[idx].longitude;
                          move();
                        });
                      });
                    }
                    return true;
                  },
                  child: ListView.builder(
                    controller: contro,
                    itemCount: vendors.length,
                    scrollDirection: Axis.horizontal,
                    key: itemKey,
                    padding: const EdgeInsets.only(left: 16, right: 8),
                    itemBuilder: (context, index) {
                      final VendorModel vendor = vendors[index];
                      final bool isSelected = selected == index;
                      final bool isOpen = vendor.isOpen() || vendor.reststatus;
                      final String rating = calculateReview(
                        reviewCount: vendor.reviewsCount.toString(),
                        reviewSum: vendor.reviewsSum.toString(),
                      );

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            selected = index;
                            latpos = vendor.latitude;
                            lotpos = vendor.longitude;
                          });
                          if (selectedMapType == 'osm') {
                            mapOsmController.moveTo(
                              osmMap.GeoPoint(
                                  latitude: vendor.latitude,
                                  longitude: vendor.longitude),
                              animate: true,
                            );
                          } else {
                            _mapController?.animateCamera(
                              CameraUpdate.newLatLngZoom(
                                  LatLng(vendor.latitude, vendor.longitude),
                                  15),
                            );
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeInOut,
                          width: _cardWidth,
                          margin: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: isDarkMode(context)
                                ? AppThemeData.grey900
                                : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? AppThemeData.primary500
                                  : Colors.transparent,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                    alpha: isSelected ? 0.14 : 0.07),
                                blurRadius: isSelected ? 20 : 12,
                                offset: Offset(0, isSelected ? 6 : 3),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              // ── Restaurant photo ──────────────────────
                              SizedBox(
                                width: 110,
                                child: CachedNetworkImage(
                                  imageUrl: getImageVAlidUrl(vendor.photo),
                                  fit: BoxFit.cover,
                                  imageBuilder: (_, img) => DecoratedBox(
                                    decoration: BoxDecoration(
                                      image: DecorationImage(
                                          image: img, fit: BoxFit.cover),
                                    ),
                                  ),
                                  placeholder: (_, __) => Container(
                                    color: isDarkMode(context)
                                        ? AppThemeData.grey800
                                        : AppThemeData.grey100,
                                    child: Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator.adaptive(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation(
                                              AppThemeData.primary500),
                                        ),
                                      ),
                                    ),
                                  ),
                                  errorWidget: (_, __, ___) => Container(
                                    color: isDarkMode(context)
                                        ? AppThemeData.grey800
                                        : AppThemeData.grey100,
                                    child: Icon(Icons.store_rounded,
                                        color: AppThemeData.grey400, size: 32),
                                  ),
                                ),
                              ),
                              // ── Info panel ────────────────────────────
                              Expanded(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 11, 12, 11),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      // Name
                                      Text(
                                        vendor.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14,
                                          height: 1.2,
                                          fontFamily: AppThemeData.bold,
                                          color: isDarkMode(context)
                                              ? AppThemeData.grey50
                                              : const Color(0xFF1A1A1A),
                                        ),
                                      ),
                                      // Rating
                                      Row(
                                        children: [
                                          const Icon(Icons.star_rounded,
                                              color: Color(0xFFFBBC05), size: 14),
                                          const SizedBox(width: 3),
                                          Text(
                                            rating,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              height: 1.2,
                                              fontFamily: AppThemeData.semiBold,
                                              color: Color(0xFF1A1A1A),
                                            ),
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            '(${vendor.reviewsCount.toInt()})',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              height: 1.2,
                                              fontFamily: AppThemeData.medium,
                                              color: Color(0xFF888888),
                                            ),
                                          ),
                                        ],
                                      ),
                                      // Location
                                      Row(
                                        children: [
                                          Icon(Icons.location_on_rounded,
                                              color: AppThemeData.primary500,
                                              size: 13),
                                          const SizedBox(width: 3),
                                          Expanded(
                                            child: Text(
                                              vendor.location,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                height: 1.2,
                                                fontFamily: AppThemeData.medium,
                                                color: Color(0xFF888888),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      // Open/Closed + View button row
                                      Row(
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color: isOpen
                                                  ? const Color(0xFF16A34A)
                                                  : const Color(0xFFDC2626),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            isOpen ? 'Open'.tr() : 'Closed'.tr(),
                                            style: TextStyle(
                                              fontSize: 11,
                                              height: 1.2,
                                              fontFamily: AppThemeData.semiBold,
                                              color: isOpen
                                                  ? const Color(0xFF16A34A)
                                                  : const Color(0xFFDC2626),
                                            ),
                                          ),
                                          const Spacer(),
                                          GestureDetector(
                                            onTap: () => push(context,
                                                NewVendorProductsScreen(
                                                    vendorModel: vendor)),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3),
                                              decoration: BoxDecoration(
                                                color: AppThemeData.primary500,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: const Text(
                                                'View',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  height: 1.2,
                                                  fontFamily:
                                                      AppThemeData.semiBold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;

    if (isDarkMode(context)) {
      _mapController!.setMapStyle('[{"featureType": "all","'
          'elementType": "'
          'geo'
          'met'
          'ry","stylers": [{"color": "#242f3e"}]},{"featureType": "all","elementType": "labels.text.stroke","stylers": [{"lightness": -80}]},{"featureType": "administrative","elementType": "labels.text.fill","stylers": [{"color": "#746855"}]},{"featureType": "administrative.locality","elementType": "labels.text.fill","stylers": [{"color": "#d59563"}]},{"featureType": "poi","elementType": "labels.text.fill","stylers": [{"color": "#d59563"}]},{"featureType": "poi.park","elementType": "geometry","stylers": [{"color": "#263c3f"}]},{"featureType": "poi.park","elementType": "labels.text.fill","stylers": [{"color": "#6b9a76"}]},{"featureType": "road","elementType": "geometry.fill","stylers": [{"color": "#2b3544"}]},{"featureType": "road","elementType": "labels.text.fill","stylers": [{"color": "#9ca5b3"}]},{"featureType": "road.arterial","elementType": "geometry.fill","stylers": [{"color": "#38414e"}]},{"featureType": "road.arterial","elementType": "geometry.stroke","stylers": [{"color": "#212a37"}]},{"featureType": "road.highway","elementType": "geometry.fill","stylers": [{"color": "#746855"}]},{"featureType": "road.highway","elementType": "geometry.stroke","stylers": [{"color": "#1f2835"}]},{"featureType": "road.highway","elementType": "labels.text.fill","stylers": [{"color": "#f3d19c"}]},{"featureType": "road.local","elementType": "geometry.fill","stylers": [{"color": "#38414e"}]},{"featureType": "road.local","elementType": "geometry.stroke","stylers": [{"color": "#212a37"}]},{"featureType": "transit","elementType": "geometry","stylers": [{"color": "#2f3948"}]},{"featureType": "transit.station","elementType": "labels.text.fill","stylers": [{"color": "#d59563"}]},{"featureType": "water","elementType": "geometry","stylers": [{"color": "#17263c"}]},{"featureType": "water","elementType": "labels.text.fill","stylers": [{"color": "#515c6d"}]},{"featureType": "water","elementType": "labels.text.stroke","stylers": [{"lightness": -20}]}]');
    }

    if (locationData != null) {
      _mapController!.moveCamera(
        CameraUpdate.newLatLng(
          LatLng(locationData!.latitude, locationData!.longitude),
        ),
      );
    }
  }

  Future<void> getTempLocation() async {
    debugPrint('location map: ${MyAppState.selectedPosotion.location}');
    if (MyAppState.currentUser == null && MyAppState.selectedPosotion.location!.latitude != 0 && MyAppState.selectedPosotion.location!.longitude != 0) {
      locationData = MyAppState.selectedPosotion.location;
      setState(() {});
    }
  }

  void move() {
    if(selectedMapType == "osm"){
      mapOsmController.moveTo(
        osmMap.GeoPoint(latitude: latpos, longitude: lotpos),
        animate: true,
      );
    }else{
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(latpos, lotpos), 13),
      );
    }

  }
}
