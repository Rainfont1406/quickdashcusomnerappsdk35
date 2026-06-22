import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_osm_plugin/flutter_osm_plugin.dart';

class VendorLocationScreen extends StatefulWidget {
  final VendorModel vendorModel;

  const VendorLocationScreen({Key? key, required this.vendorModel})
      : super(key: key);

  @override
  State<VendorLocationScreen> createState() => _VendorLocationScreenState();
}

class _VendorLocationScreenState extends State<VendorLocationScreen> {
  late final MapController _mapController;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController(
      initPosition: GeoPoint(
        latitude: widget.vendorModel.latitude,
        longitude: widget.vendorModel.longitude,
      ),
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  String get _displayAddress {
    final locality = widget.vendorModel.locality.trim();
    final landmark = widget.vendorModel.landmark.trim();
    if (locality.isEmpty) return widget.vendorModel.location;
    if (landmark.isEmpty) return locality;
    return '$locality ($landmark)';
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ── OSM Map ─────────────────────────────────────────────────────
          OSMFlutter(
            controller: _mapController,
            mapIsLoading: Container(
              color: dark ? AppThemeData.surfaceDark : const Color(0xFFF0F0F0),
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(AppThemeData.primary500),
                  strokeWidth: 2.5,
                ),
              ),
            ),
            osmOption: const OSMOption(
              zoomOption: ZoomOption(
                initZoom: 16,
                minZoomLevel: 3,
                maxZoomLevel: 19,
                stepZoom: 1.0,
              ),
            ),
            onMapIsReady: (active) async {
              if (!active || !mounted) return;
              setState(() => _mapReady = true);
              final pt = GeoPoint(
                latitude: widget.vendorModel.latitude,
                longitude: widget.vendorModel.longitude,
              );
              await _mapController.addMarker(
                pt,
                markerIcon: const MarkerIcon(
                  icon: Icon(
                    Icons.location_pin,
                    color: AppThemeData.primary500,
                    size: 48,
                  ),
                ),
              );
            },
          ),

          // ── Back button ──────────────────────────────────────────────────
          Positioned(
            top: topPadding + 8,
            left: 12,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
          ),

          // ── Bottom info card ─────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: dark ? AppThemeData.darkBgSecondary : Colors.white,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.14),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              padding:
                  EdgeInsets.fromLTRB(20, 20, 20, bottomPadding + 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppThemeData.primary500.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.store_rounded,
                        color: AppThemeData.primary500, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.vendorModel.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontFamily: AppThemeData.semiBold,
                            color: dark
                                ? AppThemeData.darkTextPrimary
                                : AppThemeData.neutral900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.location_on_rounded,
                                size: 14,
                                color: AppThemeData.primary500),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _displayAddress,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontFamily: AppThemeData.regular,
                                  height: 1.4,
                                  color: dark
                                      ? AppThemeData.darkTextSecondary
                                      : AppThemeData.neutral600,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
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
