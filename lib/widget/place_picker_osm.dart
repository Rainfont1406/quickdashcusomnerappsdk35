import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
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

/// Lightweight result model for inline search suggestions.
class _PlaceSuggestion {
  final String title;
  final String subtitle;
  final double lat;
  final double lon;
  final IconData icon;
  const _PlaceSuggestion({
    required this.title,
    required this.subtitle,
    required this.lat,
    required this.lon,
    required this.icon,
  });
}

class _LocationPickerState extends State<LocationPicker> {
  GeoPoint? selectedLocation;
  late MapController mapController;
  Place? place;

  final TextEditingController searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  String currentAddress = '';
  bool isLoadingAddress = false;
  Timer? _debounceTimer;
  Timer? _mapCheckTimer;
  bool isMapReady = false;
  GeoPoint? _lastCheckedLocation;
  int _addressRequestCounter = 0;
  bool _isProcessingAddressRequest = false;
  bool _isLocating = false;

  // True once the user has deliberately chosen a location:
  // GPS loaded, search result selected, or manual map pan.
  bool _userPickedLocation = false;
  // True while GPS is programmatically animating the map so the center
  // tracker doesn't misread GPS movement as a user pan.
  bool _gpsMoving = false;

  // ── Inline search state ─────────────────────────────────────────────────
  List<_PlaceSuggestion> _searchResults = [];
  bool _isSearchLoading = false;
  bool _showSearchResults = false;
  Timer? _searchDebounce;
  int _searchRequestId = 0;

  @override
  void initState() {
    super.initState();
    mapController = MapController(
      initPosition: GeoPoint(latitude: 26.8467, longitude: 80.9462),
    );
    searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _mapCheckTimer?.cancel();
    _searchDebounce?.cancel();
    searchController.removeListener(_onSearchChanged);
    searchController.dispose();
    _searchFocus.dispose();
    mapController.dispose();
    _addressRequestCounter = 0;
    _isProcessingAddressRequest = false;
    super.dispose();
  }

  // ── Toast ───────────────────────────────────────────────────────────────

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

  // ── Map center polling (address resolution when user pans) ──────────────

  void _startMapCenterTracking() {
    _mapCheckTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) async {
      if (!mounted) { timer.cancel(); return; }
      if (_isProcessingAddressRequest) return;
      try {
        GeoPoint centerPoint = await mapController.centerMap;
        if (_lastCheckedLocation == null ||
            _hasLocationChanged(_lastCheckedLocation!, centerPoint)) {
          // Capture BEFORE overwriting — first poll is always the default
          // init position and must never count as a user interaction.
          final bool wasFirstPoll = _lastCheckedLocation == null;
          _lastCheckedLocation = centerPoint;
          // Only treat as deliberate interaction when it is NOT the first
          // poll (which is always the default SF position) AND GPS is not
          // the one animating the map programmatically.
          if (!_gpsMoving && !wasFirstPoll && mounted) {
            setState(() => _userPickedLocation = true);
          }
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

  // ── Network check ───────────────────────────────────────────────────────

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

  // ── Reverse geocoding ───────────────────────────────────────────────────

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
        currentAddress = fetchedAddress.isNotEmpty ? fetchedAddress : 'Selected Location';
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

  // ── GPS current location ─────────────────────────────────────────────────

  Future<void> _setUserLocation() async {
    if (_isLocating) return;
    if (mounted) setState(() => _isLocating = true);
    try {
      final locationData = await _getCurrentLocation();
      if (locationData != null && mounted) {
        selectedLocation = GeoPoint(
            latitude: locationData.latitude, longitude: locationData.longitude);
        _gpsMoving = true;
        await mapController.moveTo(selectedLocation!, animate: true);
        _gpsMoving = false;
        await _fetchAddressForLocation(selectedLocation!);
        if (mounted) setState(() => _userPickedLocation = true);
      } else if (mounted) {
        _showToast("Could not get your location. Please try again.".tr(),
            isError: true);
      }
    } catch (e) {
      if (mounted) _showToast("Error getting location".tr(), isError: true);
    } finally {
      if (mounted) setState(() => _isLocating = false);
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

  // ── Inline search (Zomato / Swiggy style) ──────────────────────────────

  void _onSearchChanged() {
    final text = searchController.text.trim();
    _searchDebounce?.cancel();
    if (text.isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _showSearchResults = false;
          _isSearchLoading = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _isSearchLoading = true);
    _searchDebounce =
        Timer(const Duration(milliseconds: 350), () => _performSearch(text));
  }

  Future<void> _performSearch(String query) async {
    final myId = ++_searchRequestId;
    try {
      final lang = Localizations.localeOf(context).languageCode;
      final url = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'addressdetails': '1',
        'limit': '8',
        'accept-language': lang,
        // Hard filter: only Indian results are returned at all.
        'countrycodes': 'in',
      });
      final response = await http.get(url, headers: {
        'User-Agent': 'QuickDash/1.0',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 12));

      if (myId != _searchRequestId || !mounted) return;

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final results = data.map<_PlaceSuggestion>((p) {
          final addr = p['address'] as Map<String, dynamic>? ?? {};
          final cls = p['class'] as String? ?? '';
          final type = p['type'] as String? ?? '';

          // Title: most specific named element available
          String title = '';
          for (final k in ['name', 'amenity', 'shop', 'tourism', 'leisure', 'building', 'office']) {
            if (addr[k] != null && addr[k].toString().isNotEmpty) {
              title = addr[k].toString();
              break;
            }
          }
          if (title.isEmpty) {
            final dn = (p['display_name'] as String? ?? '').split(', ');
            title = dn.isNotEmpty ? dn[0] : query;
          }

          // Subtitle: road → neighbourhood/suburb → city → state
          final sub = <String>[];
          final road = addr['road'] ?? addr['street'] ?? addr['pedestrian'];
          if (road != null) sub.add(road.toString());
          final nb = addr['neighbourhood'] ?? addr['suburb'];
          if (nb != null) sub.add(nb.toString());
          final city = addr['city'] ?? addr['town'] ?? addr['village'];
          if (city != null) sub.add(city.toString());
          final state = addr['state'];
          if (state != null) sub.add(state.toString());

          // Icon hint
          IconData icon = Icons.location_on_rounded;
          if (cls == 'amenity' ||
              ['restaurant', 'cafe', 'fast_food', 'food_court'].contains(type))
            icon = Icons.restaurant_rounded;
          else if (cls == 'place' ||
              ['city', 'town', 'village', 'suburb', 'neighbourhood'].contains(type))
            icon = Icons.location_city_rounded;
          else if (cls == 'highway' ||
              type == 'residential' ||
              type == 'road')
            icon = Icons.route_rounded;

          return _PlaceSuggestion(
            title: title,
            subtitle: sub.take(3).join(', '),
            lat: double.tryParse(p['lat'].toString()) ?? 0,
            lon: double.tryParse(p['lon'].toString()) ?? 0,
            icon: icon,
          );
        }).toList();

        if (mounted) {
          setState(() {
            _searchResults = results;
            _showSearchResults = results.isNotEmpty;
            _isSearchLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isSearchLoading = false);
      }
    } catch (_) {
      if (myId == _searchRequestId && mounted) {
        setState(() => _isSearchLoading = false);
      }
    }
  }

  Future<void> _selectSearchResult(_PlaceSuggestion suggestion) async {
    final pt = GeoPoint(latitude: suggestion.lat, longitude: suggestion.lon);
    if (mounted) {
      // Cancel any pending debounce and remove the listener BEFORE setting
      // text — otherwise setting text triggers _onSearchChanged which would
      // re-run the search and make the list reappear after 350 ms.
      _searchDebounce?.cancel();
      searchController.removeListener(_onSearchChanged);
      setState(() {
        _showSearchResults = false;
        _searchResults = [];
        _isSearchLoading = false;
        searchController.text = suggestion.title;
      });
      searchController.addListener(_onSearchChanged);
      _searchFocus.unfocus(); // outside setState for proper keyboard dismissal
    }
    selectedLocation = pt;
    if (mounted) setState(() => _userPickedLocation = true);
    await mapController.moveTo(pt, animate: true);
    await _fetchAddressForLocation(pt);
  }

  // ── Build ────────────────────────────────────────────────────────────────

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
          // ── OSM Map ───────────────────────────────────────────────────
          OSMFlutter(
            controller: mapController,
            mapIsLoading: Container(
              color: dark ? AppThemeData.surfaceDark : const Color(0xFFF0F0F0),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppThemeData.primary500),
                      strokeWidth: 2.5,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Loading map...'.tr(),
                      style: TextStyle(
                        fontFamily: AppThemeData.medium,
                        fontSize: 14,
                        color: dark
                            ? AppThemeData.darkTextSecondary
                            : AppThemeData.neutral600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            osmOption: OSMOption(
              userLocationMarker: UserLocationMaker(
                personMarker: const MarkerIcon(
                  icon: Icon(Icons.person_pin_circle,
                      color: Colors.blue, size: 48),
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

          // ── Centered pin ──────────────────────────────────────────────
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
                      border: Border.all(
                          color:
                              AppThemeData.primary500.withValues(alpha: 0.4),
                          width: 1.5),
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
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 4,
                            spreadRadius: 1)
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),

          // ── Top gradient scrim ─────────────────────────────────────────
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
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.transparent
                  ],
                ),
              ),
            ),
          ),

          // ── Top bar: back button + search ──────────────────────────────
          // SafeArea (not a manual MediaQuery.padding.top + fixed offset)
          // keeps the back button clear of the status bar/notch on phones
          // where that inset is taller or shaped differently than usual.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 18),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Search input
                          Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: dark
                                  ? AppThemeData.darkBgSecondary
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  blurRadius: 12,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: TextField(
                              controller: searchController,
                              focusNode: _searchFocus,
                              style: TextStyle(
                                fontSize: 14,
                                fontFamily: AppThemeData.medium,
                                color: dark
                                    ? AppThemeData.darkTextPrimary
                                    : AppThemeData.neutral900,
                              ),
                              decoration: InputDecoration(
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                border: InputBorder.none,
                                prefixIcon: Icon(Icons.search_rounded,
                                    color: AppThemeData.primary500, size: 22),
                                suffixIcon: _isSearchLoading
                                    ? Padding(
                                        padding: const EdgeInsets.all(14),
                                        child: SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                const AlwaysStoppedAnimation(
                                                    AppThemeData.primary500),
                                          ),
                                        ),
                                      )
                                    : searchController.text.isNotEmpty
                                        ? IconButton(
                                            icon: Icon(Icons.close_rounded,
                                                size: 18,
                                                color: dark
                                                    ? AppThemeData
                                                        .darkTextTertiary
                                                    : AppThemeData
                                                        .neutral400),
                                            onPressed: () {
                                              searchController.clear();
                                              setState(() {
                                                _searchResults = [];
                                                _showSearchResults = false;
                                              });
                                            },
                                          )
                                        : null,
                                hintText: 'Search for a location...'.tr(),
                                hintStyle: TextStyle(
                                  fontSize: 14,
                                  fontFamily: AppThemeData.regular,
                                  color: dark
                                      ? AppThemeData.darkTextTertiary
                                      : AppThemeData.neutral400,
                                ),
                              ),
                            ),
                          ),

                          // Inline results dropdown
                          if (_showSearchResults && _searchResults.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              decoration: BoxDecoration(
                                color: dark
                                    ? AppThemeData.darkBgSecondary
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              constraints:
                                  const BoxConstraints(maxHeight: 280),
                              child: ListView.separated(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: _searchResults.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: dark
                                      ? AppThemeData.darkBorderPrimary
                                      : AppThemeData.neutral100,
                                ),
                                itemBuilder: (_, i) {
                                  final s = _searchResults[i];
                                  return ListTile(
                                    dense: true,
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 4),
                                    leading: Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: AppThemeData.primary500
                                            .withValues(alpha: 0.1),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: Icon(s.icon,
                                          color: AppThemeData.primary500,
                                          size: 18),
                                    ),
                                    title: Text(
                                      s.title,
                                      style: TextStyle(
                                        fontFamily: AppThemeData.semiBold,
                                        fontSize: 13,
                                        color: dark
                                            ? AppThemeData.darkTextPrimary
                                            : AppThemeData.neutral900,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: s.subtitle.isNotEmpty
                                        ? Text(
                                            s.subtitle,
                                            style: TextStyle(
                                              fontFamily:
                                                  AppThemeData.regular,
                                              fontSize: 11,
                                              color: dark
                                                  ? AppThemeData
                                                      .darkTextTertiary
                                                  : AppThemeData.neutral500,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          )
                                        : null,
                                    onTap: () => _selectSearchResult(s),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
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
              onTap: _isLocating ? null : _setUserLocation,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _isLocating
                      ? AppThemeData.primary500.withValues(alpha: 0.12)
                      : dark
                          ? AppThemeData.darkBgSecondary
                          : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                  border: Border.all(
                    color: _isLocating
                        ? AppThemeData.primary500.withValues(alpha: 0.5)
                        : dark
                            ? AppThemeData.darkBorderPrimary
                            : AppThemeData.neutral200,
                    width: _isLocating ? 1.5 : 1,
                  ),
                ),
                child: _isLocating
                    ? Padding(
                        padding: const EdgeInsets.all(13),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppThemeData.primary500,
                        ),
                      )
                    : Icon(Icons.my_location_rounded,
                        color: AppThemeData.primary500, size: 22),
              ),
            ),
          ),

          // ── Bottom address card ──────────────────────────────────────
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
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: dark
                              ? AppThemeData.darkBorderPrimary
                              : AppThemeData.neutral300,
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
                            color: AppThemeData.primary500
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.location_on_rounded,
                              color: AppThemeData.primary500, size: 20),
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
                                      color: dark
                                          ? AppThemeData.darkTextTertiary
                                          : AppThemeData.neutral500,
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
                                        valueColor:
                                            const AlwaysStoppedAnimation(
                                                AppThemeData.primary500),
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
                                  color: dark
                                      ? AppThemeData.darkTextPrimary
                                      : AppThemeData.neutral900,
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
                    // Hint shown while waiting for GPS or user interaction
                    if (!_userPickedLocation && !isLoadingAddress)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 13,
                                color: dark
                                    ? AppThemeData.darkTextTertiary
                                    : AppThemeData.neutral400),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Waiting for GPS — or pan the map to pick manually'
                                    .tr(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: dark
                                      ? AppThemeData.darkTextTertiary
                                      : AppThemeData.neutral500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: selectedLocation != null &&
                                place != null &&
                                !isLoadingAddress &&
                                _userPickedLocation
                            ? () => Navigator.pop(context, place)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppThemeData.primary500,
                          disabledBackgroundColor:
                              AppThemeData.primary500.withValues(alpha: 0.35),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isLoadingAddress || (_isLocating && !_userPickedLocation))
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            else
                              const Icon(Icons.check_circle_rounded,
                                  color: Colors.white, size: 20),
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
