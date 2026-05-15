import 'dart:async';
import 'dart:convert';

import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_osm_plugin/flutter_osm_plugin.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

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
      backgroundColor: isError ? AppThemeData.primary500 : Colors.black87,
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }

  fetchAddress(text) async {
    final currentRequestId = ++_requestCounter;

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
          'User-Agent': 'QuickDash/1.0',
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
                city: addrMap['city'] ?? addrMap['town'] ?? addrMap['village'] ?? '',
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
    _requestCounter = 0;
    super.onClose();
  }
}
