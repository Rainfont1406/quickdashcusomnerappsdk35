# Location Picker Implementation Guide

This guide provides complete instructions for implementing the **OpenStreetMap (OSM) Location Picker** feature in your Flutter customer app. This feature allows users to:
- Select location on an interactive map
- Search for places by name/address
- Get current GPS location
- Reverse geocode coordinates to addresses

---

## Overview

The location picker system consists of 3 main files:

| File | Purpose |
|------|---------|
| `place_picker_osm.dart` | Main map picker screen with interactive map |
| `osm_map_search_place.dart` | Search UI for finding places |
| `osm_search_place_controller.dart` | Search controller with API calls |

---

## Part 1: Dependencies

Add these packages to your `pubspec.yaml`:

```yaml
dependencies:
  # Map & Location
  flutter_osm_plugin: ^1.3.4
  osm_nominatim: ^3.0.1
  geolocator: ^13.0.1
  location: ^7.0.1
  geocoding: ^3.0.0

  # Network & Utilities
  connectivity_plus: ^6.0.5
  http: ^1.2.2
  fluttertoast: ^8.2.8
  get: ^4.6.6
```

Then run:
```bash
flutter pub get
```

---

## Part 2: Platform Configuration

### Android Setup

**1. Add location permissions to `android/app/src/main/AndroidManifest.xml`:**

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.yourcompany.yourapp">

    <!-- Location permissions -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.INTERNET" />

    <application
        ...>
        ...
    </application>
</manifest>
```

**2. For Android 12+ (API 31+), add to `AndroidManifest.xml` inside `<application>` tag:**

```xml
<application
    android:usesCleartextTraffic="true"
    ...>

    <!-- For Android 12+ -->
    <service android:name="com.mapbox.common.customLocation.CustomLocationService"
        android:enabled="true"
        android:exported="false" />
</application>
```

**3. Update `android/app/build.gradle` min SDK:**

```gradle
android {
    defaultConfig {
        minSdkVersion 21
        targetSdkVersion 34
    }
}
```

### iOS Setup

**1. Add location permissions to `ios/Runner/Info.plist`:**

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs access to location to select delivery location.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>This app needs access to location to select delivery location.</string>
```

**2. Update `ios/Podfile` minimum iOS version:**

```ruby
platform :ios, '12.0'
```

Then run:
```bash
cd ios && pod install && cd ..
```

---

## Part 3: Implementation Files

### File 1: `lib/widget/place_picker_osm.dart`

Create this file - **the main location picker screen**:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_osm_plugin/flutter_osm_plugin.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:location/location.dart';
import 'package:osm_nominatim/osm_nominatim.dart';
import 'package:your_app/widget/osm_map_search_place.dart'; // Import search screen

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
      backgroundColor: isError ? Colors.red : Colors.black87,
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }

  void _startMapCenterTracking() {
    _mapCheckTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_isProcessingAddressRequest) return;

      try {
        GeoPoint centerPoint = await mapController.centerMap;
        if (_lastCheckedLocation == null || _hasLocationChanged(_lastCheckedLocation!, centerPoint)) {
          _lastCheckedLocation = centerPoint;
          _debounceTimer?.cancel();
          if (mounted) {
            setState(() => isLoadingAddress = true);
          }
          _debounceTimer = Timer(const Duration(milliseconds: 1200), () async {
            if (!mounted) return;
            selectedLocation = centerPoint;
            await _fetchAddressForLocation(centerPoint);
          });
        }
      } catch (e) {
        log("Error tracking map center: $e");
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
      _showToast("No internet connection", isError: true);
      return;
    }

    final currentRequestId = ++_addressRequestCounter;
    _isProcessingAddressRequest = true;

    if (mounted) setState(() => isLoadingAddress = true);

    try {
      String fetchedAddress = '';
      try {
        final url = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?lat=${position.latitude}&lon=${position.longitude}&format=json&addressdetails=1'
        );
        final response = await http.get(
          url,
          headers: {
            'User-Agent': 'YourAppName/1.0',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 15));

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
      _showToast("Getting your location...");
      final locationData = await _getCurrentLocation();
      if (locationData != null) {
        selectedLocation = GeoPoint(
          latitude: locationData.latitude,
          longitude: locationData.longitude,
        );
        await mapController.moveTo(selectedLocation!, animate: true);
        await _fetchAddressForLocation(selectedLocation!);
        _showToast("Location updated");
      }
    } catch (e) {
      _showToast("Error getting location", isError: true);
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
      MaterialPageRoute(builder: (context) => const OsmSearchPlacesApi()),
    );
    if (result != null && result is SearchInfo) {
      if (result.point != null) {
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
    const primaryColor = Color(0xFF00AAFF); // Your primary color

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Select Location', style: TextStyle(color: Colors.white)),
        elevation: 0,
      ),
      body: Stack(
        children: [
          OSMFlutter(
            controller: mapController,
            mapIsLoading: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: primaryColor),
                  SizedBox(height: 16),
                  Text('Loading map...'),
                ],
              ),
            ),
            osmOption: OSMOption(
              userLocationMaker: UserLocationMaker(
                personMarker: const MarkerIcon(
                  icon: Icon(Icons.person_pin_circle, color: Colors.blue, size: 48),
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
          if (isMapReady)
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 40),
                child: const Icon(
                  Icons.location_pin,
                  size: 50,
                  color: Colors.red,
                  shadows: [Shadow(blurRadius: 10, color: Colors.black26, offset: Offset(0, 2))],
                ),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: InkWell(
                onTap: _openSearchScreen,
                child: TextField(
                  controller: searchController,
                  enabled: false,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, color: primaryColor),
                    hintText: 'Search location',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
            ),
          ),
          if (currentAddress.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, -2))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: primaryColor, size: 24),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('Selected Location', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                        if (isLoadingAddress)
                          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(currentAddress, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500), maxLines: 3, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: selectedLocation != null && place != null ? () => Navigator.pop(context, place) : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle, size: 20),
                            SizedBox(width: 8),
                            Text('Confirm Location', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
      floatingActionButton: FloatingActionButton(
        onPressed: _setUserLocation,
        backgroundColor: Colors.white,
        child: const Icon(Icons.my_location, color: primaryColor),
      ),
    );
  }
}
```

---

### File 2: `lib/widget/osm_map_search_place.dart`

Create this file - **the search UI screen**:

```dart
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:your_app/widget/osm_search_place_controller.dart';
import 'package:your_app/theme/app_them_data.dart'; // Your theme file

class OsmSearchPlacesApi extends StatelessWidget {
  const OsmSearchPlacesApi({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF00AAFF); // Your primary color

    return GetX<OsmSearchPlaceController>(
      init: OsmSearchPlaceController(),
      builder: (controller) {
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: primaryColor,
            leading: InkWell(
              onTap: () => Navigator.pop(context),
              child: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            title: const Text('Search Places', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              children: [
                TextField(
                  controller: controller.searchTxtController.value,
                  decoration: InputDecoration(
                    hintText: 'Search your location here',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: Obx(() => controller.searchText.value.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.cancel),
                            onPressed: () {
                              controller.searchTxtController.value.clear();
                              controller.searchText.value = '';
                              controller.suggestionsList.clear();
                            },
                          )
                        : const SizedBox.shrink()),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                Obx(() {
                  if (controller.isLoading.value) {
                    return const Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  } else if (controller.suggestionsList.isEmpty && controller.searchText.value.isNotEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Center(child: Text('No locations found', style: TextStyle(color: Colors.grey))),
                    );
                  } else if (controller.suggestionsList.isNotEmpty) {
                    return Expanded(
                      child: ListView.builder(
                        itemCount: controller.suggestionsList.length,
                        itemBuilder: (context, index) {
                          final suggestion = controller.suggestionsList[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: const Icon(Icons.location_on, color: primaryColor),
                              title: Text(
                                suggestion.displayName,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                Navigator.pop(context, suggestion.searchInfo);
                              },
                            ),
                          );
                        },
                      ),
                    );
                  } else {
                    return const SizedBox.shrink();
                  }
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

---

### File 3: `lib/widget/osm_search_place_controller.dart`

Create this file - **the search controller**:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_osm_plugin/flutter_osm_plugin.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:osm_nominatim/osm_nominatim.dart';

class SearchResult {
  final SearchInfo searchInfo;
  final String displayName;

  SearchResult({required this.searchInfo, required this.displayName});

  GeoPoint? get point => searchInfo.point;
  Address? get address => searchInfo.address;
}

class OsmSearchPlaceController extends GetxController {
  Rx<TextEditingController> searchTxtController = TextEditingController().obs;
  RxList<SearchResult> suggestionsList = <SearchResult>[].obs;
  RxBool isLoading = false.obs;
  RxString searchText = ''.obs;
  Timer? _debounceTimer;
  String? _currentSearchQuery;
  int _requestCounter = 0;

  @override
  void onInit() {
    super.onInit();
    searchTxtController.value.addListener(() {
      searchText.value = searchTxtController.value.text;
      _onChanged();
    });
  }

  _onChanged() {
    _debounceTimer?.cancel();
    String text = searchTxtController.value.text.trim();

    if (text.isEmpty) {
      suggestionsList.clear();
      isLoading.value = false;
      _currentSearchQuery = null;
      return;
    }

    isLoading.value = true;
    _debounceTimer = Timer(const Duration(milliseconds: 1000), () {
      fetchAddress(text);
    });
  }

  void _showToast(String message, {bool isError = false}) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: isError ? Colors.red : Colors.black87,
      textColor: Colors.white,
    );
  }

  fetchAddress(text) async {
    final currentRequestId = ++_requestCounter;
    _currentSearchQuery = text;

    try {
      if (text.isEmpty) {
        suggestionsList.clear();
        isLoading.value = false;
        return;
      }

      await _searchWithNominatim(text, currentRequestId);
    } catch (e) {
      if (currentRequestId == _requestCounter) {
        _showToast("Search failed", isError: true);
        suggestionsList.clear();
      }
    } finally {
      if (currentRequestId == _requestCounter) {
        isLoading.value = false;
      }
    }
  }

  Future<void> _searchWithNominatim(String text, int requestId) async {
    try {
      List<SearchResult> results = [];

      final encodedQuery = Uri.encodeComponent(text);
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=$encodedQuery&format=json&addressdetails=1&limit=10'
      );

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'YourAppName/1.0',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        for (var place in data) {
          try {
            final lat = double.parse(place['lat'].toString());
            final lon = double.parse(place['lon'].toString());
            final geoPoint = GeoPoint(latitude: lat, longitude: lon);

            Address? constructedAddress;
            if (place['address'] != null) {
              final addrMap = place['address'];
              constructedAddress = Address(
                street: addrMap['road'] ?? '',
                city: addrMap['city'] ?? addrMap['town'] ?? '',
                state: addrMap['state'] ?? '',
                country: addrMap['country'] ?? '',
              );
            }

            final displayName = place['display_name'] ?? 'Unknown location';
            final searchInfo = SearchInfo(point: geoPoint, address: constructedAddress);

            results.add(SearchResult(searchInfo: searchInfo, displayName: displayName));
          } catch (_) {}
        }
      }

      if (requestId != _requestCounter) return;

      if (results.isNotEmpty) {
        suggestionsList.value = results;
      } else {
        suggestionsList.clear();
      }
    } catch (e) {
      if (requestId == _requestCounter) {
        suggestionsList.clear();
      }
    }
  }

  @override
  void onClose() {
    _debounceTimer?.cancel();
    searchTxtController.value.dispose();
    suggestionsList.clear();
    _currentSearchQuery = null;
    _requestCounter = 0;
    super.onClose();
  }
}
```

---

## Part 4: Usage Example

### Using the Location Picker

```dart
import 'package:flutter/material.dart';
import 'package:your_app/widget/place_picker_osm.dart';

class AddressScreen extends StatefulWidget {
  const AddressScreen({super.key});

  @override
  State<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends State<AddressScreen> {
  String selectedAddress = 'No location selected';
  double? latitude;
  double? longitude;

  Future<void> openLocationPicker() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LocationPicker()),
    );

    if (result != null) {
      setState(() {
        selectedAddress = result.displayName;
        latitude = result.lat;
        longitude = result.lon;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Address')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Selected Location:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(selectedAddress),
                  if (latitude != null && longitude != null) ...[
                    const SizedBox(height: 8),
                    Text('Lat: $latitude, Lon: $longitude', style: const TextStyle(color: Colors.grey)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: openLocationPicker,
              icon: const Icon(Icons.map),
              label: const Text('Select Location on Map'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## Part 5: Customization

### Change Primary Color

Replace `const Color(0xFF00AAFF)` with your app's primary color in:
1. `place_picker_osm.dart` - Line ~380
2. `osm_map_search_place.dart` - Line ~16

### Change Map Style

In `OSMOption` within `place_picker_osm.dart`, you can customize:

```dart
osmOption: OSMOption(
  zoomOption: const ZoomOption(
    initZoom: 14,          // Initial zoom level
    minZoomLevel: 3,       // Minimum zoom
    maxZoomLevel: 19,      // Maximum zoom
    stepZoom: 1.0,
  ),
  // Change map tile server (default is OpenStreetMap)
  // You can use other tile providers if needed
),
```

---

## Part 6: How It Works

### Data Flow

```
User Action                    Component
    |
    v
[Open Map Screen]      ->   LocationPicker widget initializes
    |
    v
[Map Loads]            ->   OSMFlutter renders map
    |
    +-- [Get GPS]      ->   Fetches device location via Geolocator
    |
    +-- [Drag/Click]   ->   Map center tracking detects position change
    |
    v
[Fetch Address]        ->   Nominatim API reverse geocodes coordinates
    |
    v
[Display Address]      ->   Shows in bottom card
    |
    v
[Confirm]              ->   Returns Place object with location data
```

### Search Flow

```
[Type in Search]       ->   OsmSearchPlaceController
    |
    v
[Debounce 1s]          ->   Waits for typing to stop
    |
    v
[Nominatim API]        ->   Searches places by name
    |
    v
[Display Results]      ->   ListView of location suggestions
    |
    v
[Select Result]        ->   Returns SearchInfo to map
    |
    v
[Map Moves]            ->   Centers map on selected location
```

---

## Part 7: Troubleshooting

### Issue: Map not loading

**Solution:**
- Check internet connection
- Verify `flutter_osm_plugin` is properly installed
- For iOS: Run `pod install` in ios folder

### Issue: Location permission denied

**Solution:**
- Check permissions in AndroidManifest.xml / Info.plist
- Handle permission denied case in app settings

### Issue: Address not loading

**Solution:**
- Check network connectivity
- Nominatim API may be rate-limited (1 request per second recommended)
- Fallback to coordinates if address fails

### Issue: Search not working

**Solution:**
- Verify internet connection
- Check if Nominatim server is accessible
- API may be rate-limited, implement proper throttling

---

## Part 8: Important Notes

1. **No API Key Required**: Uses OpenStreetMap/Nominatim which is free
2. **Rate Limiting**: Nominatim allows ~1 request/second - already implemented via debouncing
3. **User-Agent**: Always include a unique User-Agent in Nominatim requests
4. **Offline**: The map tiles require internet connection
5. **Alternatives**: For production with higher volume, consider:
   - Self-hosted Nominatim instance
   - Google Maps API (requires API key and billing)
   - Mapbox (requires API key)

---

## Summary

This implementation provides:
- ✅ Interactive map for location selection
- ✅ GPS current location button
- ✅ Search places by name/address
- ✅ Reverse geocoding (coordinates → address)
- ✅ Network connectivity checks
- ✅ Error handling and fallbacks
- ✅ No API keys required (uses OpenStreetMap)

Copy the 3 main files to your customer app's widget folder and follow the platform configuration steps to integrate.
