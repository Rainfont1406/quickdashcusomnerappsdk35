// Delivery-location helpers shared by the address screens and checkout
// (2026-11-10).
//
// - isRealLocation(): AddressModel/UserLocation default to placeholder
//   coordinates (UserLocation() = 0.01/0.01, fromJson falls back to 0.1), so
//   "location != null" does not mean the customer actually picked a place.
// - deliveryLocationPayload(): what the payment Cloud Functions receive as
//   `deliveryLocation` so the server can compute the delivery fee itself
//   (QUICKDASH_BACKEND_CHANGES_2026-11-07 section 3). Delivery orders only -
//   Dining / Takeaway / Bill Pay never send it.
// - currentLocationAddress() / pickLocationOnMap(): one-tap "use my current
//   location" and the map picker, both returning a ready AddressModel.

import 'dart:async';

import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/AddressModel.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/widget/place_picker_osm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_google_maps_webservices/places.dart' show Component;
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_place_picker_mb/google_maps_place_picker.dart';
import 'package:uuid/uuid.dart';

/// Where the map opens when we know nothing better (all partner restaurants
/// are in Lucknow today). The pickers still jump to the phone's GPS position
/// when it is available.
const LatLng _fallbackMapCenter = LatLng(26.8467, 80.9462);

bool isRealLocation(UserLocation? l) {
  if (l == null) return false;
  final lat = l.latitude, lng = l.longitude;
  if (!lat.isFinite || !lng.isFinite) return false;
  if (lat.abs() > 90 || lng.abs() > 180) return false;
  // Placeholder defaults sit within a degree of 0,0 (open sea) - never a
  // real delivery address.
  if (lat.abs() < 1 && lng.abs() < 1) return false;
  return true;
}

/// `deliveryLocation` for the payment functions, or null when this is not a
/// delivery order or the address has no real coordinates (the server then
/// keeps the app's fee while its fee mode is off/log).
Map<String, double>? deliveryLocationPayload({
  required bool isDelivery,
  AddressModel? address,
}) {
  if (!isDelivery) return null;
  final l = address?.location;
  if (!isRealLocation(l)) return null;
  return {'latitude': l!.latitude, 'longitude': l.longitude};
}

/// Result of a location lookup: an address, or a message to show.
class LocationLookup {
  final AddressModel? address;
  final String? error;
  const LocationLookup({this.address, this.error});
}

Future<String?> _addressText(double lat, double lng) async {
  try {
    final marks = await geo
        .placemarkFromCoordinates(lat, lng)
        .timeout(const Duration(seconds: 6));
    if (marks.isEmpty) return null;
    final m = marks.first;
    final parts = <String>[];
    for (final s in [m.name, m.street, m.subLocality, m.locality, m.administrativeArea, m.postalCode]) {
      final v = (s ?? '').trim();
      if (v.isNotEmpty && !parts.contains(v)) parts.add(v);
    }
    return parts.isEmpty ? null : parts.join(', ');
  } catch (_) {
    return null;
  }
}

AddressModel _newAddress(double lat, double lng, String text) => AddressModel(
      locality: text,
      location: UserLocation(latitude: lat, longitude: lng),
      addressAs: 'Other',
      isDefault: false,
    )..id = const Uuid().v4();

/// One tap: GPS fix -> readable address. Never hangs: the fix is bounded
/// and the last known position is used if a fresh one does not arrive.
Future<LocationLookup> currentLocationAddress() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationLookup(error: 'Please turn on location (GPS) and try again.');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      return const LocationLookup(error: 'Location permission is needed to use your current location.');
    }
    if (perm == LocationPermission.deniedForever) {
      return const LocationLookup(
          error: 'Location permission is turned off for QuickDash. Enable it in Settings, or pick on the map.');
    }

    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      pos = await Geolocator.getLastKnownPosition();
    }
    if (pos == null) {
      return const LocationLookup(error: 'Could not get your location. Please pick it on the map.');
    }
    final text = await _addressText(pos.latitude, pos.longitude) ??
        '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
    return LocationLookup(address: _newAddress(pos.latitude, pos.longitude, text));
  } catch (_) {
    return const LocationLookup(error: 'Could not get your location. Please pick it on the map.');
  }
}

/// Opens the configured map picker (OSM or Google) centred on [start] (or
/// the currently selected location) and returns the picked place.
Future<AddressModel?> pickLocationOnMap(BuildContext context, {UserLocation? start}) async {
  final from = isRealLocation(start)
      ? start
      : (isRealLocation(MyAppState.selectedPosotion.location) ? MyAppState.selectedPosotion.location : null);

  if (selectedMapType == 'osm') {
    final value = await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LocationPicker(
              initialLat: from?.latitude,
              initialLng: from?.longitude,
              deliveryMode: true,
            )));
    if (value == null) return null;
    final double lat = value.lat, lng = value.lon;
    return _newAddress(lat, lng, value.displayName.toString());
  }

  AddressModel? picked;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (ctx) => PlacePicker(
        apiKey: GOOGLE_API_KEY,
        onPlacePicked: (result) {
          final loc = result.geometry?.location;
          if (loc != null) {
            picked = _newAddress(loc.lat, loc.lng, (result.formattedAddress ?? '').toString());
          }
          Navigator.of(ctx).pop();
        },
        initialPosition: from != null ? LatLng(from.latitude, from.longitude) : _fallbackMapCenter,
        // Jump to GPS only when we had nothing better to show.
        useCurrentLocation: from == null,
        selectInitialPosition: true,
        usePinPointingSearch: true,
        usePlaceDetailSearch: true,
        zoomGesturesEnabled: true,
        zoomControlsEnabled: true,
        initialMapType: MapType.normal,
        resizeToAvoidBottomInset: false,
        autocompleteComponents: [Component(Component.country, 'in')],
      ),
    ),
  );
  return picked;
}
