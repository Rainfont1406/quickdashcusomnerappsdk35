import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/widget/osm_map_search_place.dart';
import 'package:flutter/material.dart';
import 'package:flutter_osm_plugin/flutter_osm_plugin.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:location/location.dart';
import 'package:osm_nominatim/osm_nominatim.dart';
import 'package:provider/provider.dart';
import 'package:emartconsumer/utils/DarkThemeProvider.dart';

class LocationPicker extends StatefulWidget {
  const LocationPicker({super.key});

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  GeoPoint? selectedLocation;
  late MapController mapController;
  Place? place;
  TextEditingController searchController = TextEditingController();
  String currentAddress = '';
  bool isLoadingAddress = false;
  Timer? _debounceTimer;
  Timer? _mapCheckTimer;
  bool isMapReady = false;
  GeoPoint? _lastCheckedLocation;
  int _addressRequestCounter = 0;
  bool _isProcessingAddressRequest = false;

  @override
  void initState() {
    super.initState();
    mapController = MapController(
      initPosition: GeoPoint(latitude: 37.7749, longitude: -122.4194),
    );
  }

  void _showToast(String message, {bool isError = false}) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: isError ? AppThemeData.error500 : Colors.black87,
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }

  void _startMapCenterTracking() {
    _mapCheckTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) async {
      if (!mounted) { timer.cancel(); return; }
      if (_isProcessingAddressRequest) return;
      try {
        GeoPoint centerPoint = await mapController.centerMap;
        if (_lastCheckedLocation == null || _hasLocationChanged(_lastCheckedLocation!, centerPoint)) {
          _lastCheckedLocation = centerPoint;
          _debounceTimer?.cancel();
          if (mounted) setState(() => isLoadingAddress = true);
          _debounceTimer = Timer(const Duration(milliseconds: 1200), () async {
            if (!mounted) return;
            selectedLocation = centerPoint;
            await _fetchAddressForLocation(centerPoint);
          });
        }
      } catch (e) {
        developer.log("Error tracking map center: $e");
      }
    });
  }

  bool _hasLocationChanged(GeoPoint oldLocation, GeoPoint newLocation) {
    const double threshold = 0.00005;
    return (oldLocation.latitude - newLocation.latitude).abs() > threshold ||
        (oldLocation.longitude - newLocation.longitude).abs() > threshold;
  }

  Future<bool> _hasNetworkConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      return connectivityResult.contains(ConnectivityResult.mobile) ||
          connectivityResult.contains(ConnectivityResult.wifi) ||
          connectivityResult.contains(ConnectivityResult.ethernet);
    } catch (e) {
      return true;
    }
  }

  Future<void> _fetchAddressForLocation(GeoPoint position) async {
    if (!mounted) return;
    if (_isProcessingAddressRequest) return;
    if (!await _hasNetworkConnection()) {
      _showToast("No internet connection".tr(), isError: true);
      return;
    }

    final currentRequestId = ++_addressRequestCounter;
    _isProcessingAddressRequest = true;
    if (mounted) setState(() => isLoadingAddress = true);

    try {
      String fetchedAddress = '';
      try {
        final url = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?lat=${position.latitude}&lon=${position.longitude}&format=json&addressdetails=1',
        );
        final response = await http.get(url, headers: {
          'User-Agent': 'QuickDash/1.0',
          'Accept': 'application/json',
        }).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['display_name'] != null) {
            fetchedAddress = data['display_name'];
          } else if (data['address'] != null) {
            final addr = data['address'];
            List<String> parts = [];
            if (addr['road'] != null) parts.add(addr['road'].toString());
            if (addr['city'] != null) parts.add(addr['city'].toString());
            if (addr['state'] != null) parts.add(addr['state'].toString());
            if (addr['country'] != null) parts.add(addr['country'].toString());
            if (parts.isNotEmpty) fetchedAddress = parts.join(', ');
          }
        }
      } catch (httpError) {
        try {
          final fetchedPlace = await Nominatim.reverseSearch(
            lat: position.latitude,
            lon: position.longitude,
            addressDetails: true,
          ).timeout(const Duration(seconds: 15));
          if (fetchedPlace.displayName.isNotEmpty) {
            fetchedAddress = fetchedPlace.displayName;
          }
        } catch (_) {}
      }

      if (currentRequestId != _addressRequestCounter || !mounted) return;

      setState(() {
        if (fetchedAddress.isNotEmpty) {
          currentAddress = fetchedAddress;
          place = Place(
            lat: position.latitude,
            lon: position.longitude,
            displayName: fetchedAddress,
            placeId: 0,
            osmType: '',
            osmId: 0,
            placeRank: 0,
            category: '',
            type: '',
            importance: 0,
            boundingBox: ['0', '0', '0', '0'],
          );
        } else {
          currentAddress = 'Selected Location';
          place = Place(
            lat: position.latitude,
            lon: position.longitude,
            displayName: currentAddress,
            placeId: 0,
            osmType: '',
            osmId: 0,
            placeRank: 0,
            category: '',
            type: '',
            importance: 0,
            boundingBox: ['0', '0', '0', '0'],
          );
        }
        isLoadingAddress = false;
      });
    } catch (e) {
      if (currentRequestId == _addressRequestCounter && mounted) {
        setState(() {
          currentAddress = 'Selected Location';
          place = Place(
            lat: position.latitude,
            lon: position.longitude,
            displayName: currentAddress,
            placeId: 0,
            osmType: '',
            osmId: 0,
            placeRank: 0,
            category: '',
            type: '',
            importance: 0,
            boundingBox: ['0', '0', '0', '0'],
          );
          isLoadingAddress = false;
        });
      }
    } finally {
      if (currentRequestId == _addressRequestCounter) {
        _isProcessingAddressRequest = false;
      }
    }
  }

  Future<void> _setUserLocation() async {
    try {
      _showToast("Getting your location...".tr());
      final locationData = await _getCurrentLocation();
      if (locationData != null && mounted) {
        selectedLocation = GeoPoint(latitude: locationData.latitude, longitude: locationData.longitude);
        await mapController.moveTo(selectedLocation!, animate: true);
        await _fetchAddressForLocation(selectedLocation!);
        _showToast("Location updated".tr());
      }
    } catch (e) {
      _showToast("Error getting location".tr(), isError: true);
    }
  }

  static Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Location().requestService();
      return null;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions permanently denied');
    }
    return await Geolocator.getCurrentPosition();
  }

  Future<void> _openSearchScreen() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OsmSearchPlacesApi()),
    );
    if (result != null && result is SearchInfo) {
      if (result.point != null && mounted) {
        GeoPoint point = result.point!;
        selectedLocation = point;
        await mapController.moveTo(point, animate: true);
        await _fetchAddressForLocation(point);
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _mapCheckTimer?.cancel();
    mapController.dispose();
    searchController.dispose();
    _addressRequestCounter = 0;
    _isProcessingAddressRequest = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeChange = Provider.of<DarkThemeProvider>(context);
    final dark = themeChange.darkTheme;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── OSM Map ─────────────────────────────────────────────────
          OSMFlutter(
            controller: mapController,
            mapIsLoading: Container(
              color: dark ? AppThemeData.surfaceDark : const Color(0xFFF0F0F0),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      valueColor: const AlwaysStoppedAnimation<Color>(AppThemeData.primary500),
                      strokeWidth: 2.5,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Loading map...'.tr(),
                      style: TextStyle(
                        fontFamily: AppThemeData.medium,
                        fontSize: 14,
                        color: dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            osmOption: OSMOption(
              userLocationMarker: UserLocationMaker(
                personMarker: const MarkerIcon(
                  icon: Icon(Icons.person_pin_circle, color: Colors.blue, size: 48),
                ),
                directionArrowMarker: const MarkerIcon(
                  icon: Icon(Icons.location_on, color: Colors.blue, size: 48),
                ),
              ),
              zoomOption: const ZoomOption(
                initZoom: 14,
                minZoomLevel: 3,
                maxZoomLevel: 19,
                stepZoom: 1.0,
              ),
            ),
            onMapIsReady: (active) async {
              if (active) {
                setState(() => isMapReady = true);
                _setUserLocation();
                _startMapCenterTracking();
              }
            },
            onGeoPointClicked: (geoPoint) async {
              selectedLocation = geoPoint;
              await _fetchAddressForLocation(geoPoint);
            },
          ),

          // ── Centered pin ─────────────────────────────────────────────
          if (isMapReady)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppThemeData.primary500.withValues(alpha: 0.15),
                      border: Border.all(color: AppThemeData.primary500.withValues(alpha: 0.4), width: 1.5),
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: AppThemeData.primary500,
                      size: 28,
                    ),
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      color: AppThemeData.primary500,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4, spreadRadius: 1)
                      ],
                    ),
                  ),
                  const SizedBox(height: 20), // offset for bottom balance
                ],
              ),
            ),

          // ── Top gradient scrim ────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 160,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.55), Colors.transparent],
                ),
              ),
            ),
          ),

          // ── Back button ───────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
              ),
            ),
          ),

          // ── Search bar ────────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 62,
            right: 12,
            child: GestureDetector(
              onTap: _openSearchScreen,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: dark ? AppThemeData.darkBgSecondary : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    Icon(Icons.search_rounded, color: AppThemeData.primary500, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Search for a location...'.tr(),
                        style: TextStyle(
                          fontSize: 14,
                          fontFamily: AppThemeData.regular,
                          color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral400,
                        ),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 20,
                      color: dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral200,
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.tune_rounded, size: 18,
                        color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral400),
                    const SizedBox(width: 14),
                  ],
                ),
              ),
            ),
          ),

          // ── Current location FAB ──────────────────────────────────────
          Positioned(
            bottom: currentAddress.isNotEmpty ? 220 : 24,
            right: 16,
            child: GestureDetector(
              onTap: _setUserLocation,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: dark ? AppThemeData.darkBgSecondary : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                  border: Border.all(
                    color: dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral200,
                    width: 1,
                  ),
                ),
                child: Icon(Icons.my_location_rounded, color: AppThemeData.primary500, size: 22),
              ),
            ),
          ),

          // ── Bottom address card ───────────────────────────────────────
          if (currentAddress.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: dark ? AppThemeData.darkBgSecondary : Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 20,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding + 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppThemeData.primary500.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.location_on_rounded, color: AppThemeData.primary500, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Selected Location'.tr(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: AppThemeData.semiBold,
                                      color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral500,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  if (isLoadingAddress) ...[
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        valueColor: const AlwaysStoppedAnimation(AppThemeData.primary500),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                currentAddress,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontFamily: AppThemeData.medium,
                                  height: 1.4,
                                  color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: selectedLocation != null && place != null && !isLoadingAddress
                            ? () => Navigator.pop(context, place)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppThemeData.primary500,
                          disabledBackgroundColor: AppThemeData.primary500.withValues(alpha: 0.4),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              'Confirm Location'.tr(),
                              style: const TextStyle(
                                fontSize: 16,
                                fontFamily: AppThemeData.semiBold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
