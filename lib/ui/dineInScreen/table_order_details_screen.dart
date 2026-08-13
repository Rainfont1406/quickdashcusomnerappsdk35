import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/BookTableModel.dart';
import 'package:emartconsumer/services/device_session_service.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class TableOrderDetailsScreen extends StatefulWidget {
  final BookTableModel bookTableModel;

  const TableOrderDetailsScreen({Key? key, required this.bookTableModel}) : super(key: key);

  @override
  State<TableOrderDetailsScreen> createState() => _TableOrderDetailsScreenState();
}

class _TableOrderDetailsScreenState extends State<TableOrderDetailsScreen> {
  Future<PolylineResult>? _polylinesFuture;
  List<LatLng> _polylineCoordinates = [];
  List<Polyline> _polylines = [];
  List<Marker> _markers = [];
  late BitmapDescriptor _userIcon;
  late BitmapDescriptor _storeIcon;
  GoogleMapController? _mapController;
  bool _iconsLoaded = false;

  _StatusInfo get _statusInfo {
    if (widget.bookTableModel.status == ORDER_STATUS_ACCEPTED) {
      return _StatusInfo(
        label: 'Confirmed'.tr(),
        subtitle: 'Your table is reserved. Show this confirmation at the restaurant.'.tr(),
        color: const Color(0xFF2E7D32),
        bg: const Color(0xFFE8F5E9),
        icon: Icons.check_circle_rounded,
      );
    }
    if (widget.bookTableModel.status == ORDER_STATUS_REJECTED) {
      return _StatusInfo(
        label: 'Reservation Declined'.tr(),
        subtitle: 'The restaurant could not accommodate your request.'.tr(),
        color: AppThemeData.error500,
        bg: const Color(0xFFFFEBEE),
        icon: Icons.cancel_rounded,
      );
    }
    // ORDER_STATUS_PLACED — check if expired
    final isExpired = widget.bookTableModel.date.compareTo(Timestamp.now()) <= 0;
    if (isExpired) {
      return _StatusInfo(
        label: 'Expired'.tr(),
        subtitle: 'This reservation has passed without confirmation.'.tr(),
        color: AppThemeData.grey500,
        bg: AppThemeData.grey100,
        icon: Icons.schedule,
      );
    }
    return _StatusInfo(
      label: 'Awaiting Confirmation'.tr(),
      subtitle: 'The restaurant is reviewing your request. This may take a few minutes.'.tr(),
      color: AppThemeData.accent600,
      bg: AppThemeData.accent50,
      icon: Icons.hourglass_empty_rounded,
    );
  }

  @override
  void initState() {
    super.initState();
    if (kDebugMode) print('Booking ID: ${widget.bookTableModel.id}');

    // (2026-08-03) Device-session verification redesign - this confirmation
    // is "shown at the restaurant" the same way an order/QR gate pass is,
    // so it gets the same session-scoped fallback check as
    // OrderDetailsScreen (see DeviceSessionService.enforceActiveForOrder's
    // doc comment). Fire-and-forget; must never delay rendering the
    // confirmation for the common (still-active) case.
    DeviceSessionService.enforceActiveForOrder(context);

    if (widget.bookTableModel.status == ORDER_STATUS_ACCEPTED) {
      _polylinesFuture = PolylinePoints().getRouteBetweenCoordinates(
        googleApiKey: GOOGLE_API_KEY,
        request: PolylineRequest(
          origin: PointLatLng(
              widget.bookTableModel.vendor.latitude, widget.bookTableModel.vendor.longitude),
          destination: PointLatLng(widget.bookTableModel.author.location.latitude,
              widget.bookTableModel.author.location.longitude),
          mode: TravelMode.driving,
        ),
      );
    }
    _loadMarkerIcons();
  }

  Future<void> _loadMarkerIcons() async {
    _userIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(44, 44)), 'assets/images/location_black3x.png');
    _storeIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(44, 44)), 'assets/images/location_orange3x.png');
    if (mounted) setState(() => _iconsLoaded = true);
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = isDarkMode(context);
    final size = MediaQuery.of(context).size;
    final status = _statusInfo;

    return Scaffold(
      backgroundColor: dark ? AppThemeData.surfaceDark : AppThemeData.grey100,
      appBar: AppBar(
        backgroundColor: dark ? AppThemeData.darkBgPrimary : Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: dark ? Colors.white : Colors.black),
        ),
        title: Text(
          'Booking Details'.tr(),
          style: TextStyle(
            fontSize: 16,
            fontFamily: AppThemeData.semiBold,
            color: dark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // STATUS CARD
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: status.bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: status.color.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: status.color.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(status.icon, color: status.color, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(status.label,
                            style: TextStyle(
                              fontSize: 15,
                              fontFamily: AppThemeData.semiBold,
                              color: status.color,
                            )),
                        const SizedBox(height: 4),
                        Text(status.subtitle,
                            style: TextStyle(fontSize: 12, color: status.color.withOpacity(0.8))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // RESTAURANT INFO CARD
            _card(
              dark: dark,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.restaurant_rounded, color: AppThemeData.primary500, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.bookTableModel.vendor.title,
                              style: TextStyle(
                                fontSize: 15,
                                fontFamily: AppThemeData.semiBold,
                                color: dark ? Colors.white : Colors.black,
                              )),
                          const SizedBox(height: 3),
                          Text(widget.bookTableModel.vendor.location,
                              style: TextStyle(
                                fontSize: 12,
                                color: dark ? AppThemeData.grey400 : AppThemeData.grey500,
                              ),
                              maxLines: 2),
                        ],
                      ),
                    ),
                    Column(children: [
                      _iconBtn(
                        icon: Icons.navigation_rounded,
                        onTap: () => launchUrl(createCoordinatesUrl(
                          widget.bookTableModel.vendor.latitude,
                          widget.bookTableModel.vendor.longitude,
                          widget.bookTableModel.vendor.title,
                        )),
                        dark: dark,
                      ),
                      if (widget.bookTableModel.vendor.phonenumber.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _iconBtn(
                          icon: Icons.phone_rounded,
                          onTap: () => launchUrl(Uri(
                              scheme: 'tel',
                              path: widget.bookTableModel.vendor.phonenumber)),
                          dark: dark,
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // BOOKING DETAILS CARD
            _card(
              dark: dark,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: Text('Reservation Details'.tr(),
                          style: TextStyle(
                            fontSize: 13,
                            fontFamily: AppThemeData.semiBold,
                            color: AppThemeData.primary500,
                            letterSpacing: 0.3,
                          )),
                    ),
                    _detailRow(
                      icon: Icons.person_outline,
                      label: 'Guest Name'.tr(),
                      value:
                          '${widget.bookTableModel.guestFirstName} ${widget.bookTableModel.guestLastName}',
                      dark: dark,
                    ),
                    _divider(dark),
                    _detailRow(
                      icon: Icons.phone_outlined,
                      label: 'Phone'.tr(),
                      value: widget.bookTableModel.guestPhone,
                      dark: dark,
                    ),
                    _divider(dark),
                    _detailRow(
                      icon: Icons.calendar_today_outlined,
                      label: 'Date & Time'.tr(),
                      value: DateFormat("EEEE, MMM d, yyyy 'at' hh:mm a")
                          .format(widget.bookTableModel.date.toDate()),
                      dark: dark,
                    ),
                    _divider(dark),
                    _detailRow(
                      icon: Icons.people_outline,
                      label: 'Guests'.tr(),
                      value: '${widget.bookTableModel.totalGuest}',
                      dark: dark,
                    ),
                    if ((widget.bookTableModel.occasion ?? '').isNotEmpty) ...[
                      _divider(dark),
                      _detailRow(
                        icon: Icons.celebration_outlined,
                        label: 'Occasion'.tr(),
                        value: widget.bookTableModel.occasion!,
                        dark: dark,
                      ),
                    ],
                    if ((widget.bookTableModel.specialRequest ?? '').isNotEmpty) ...[
                      _divider(dark),
                      _detailRow(
                        icon: Icons.note_outlined,
                        label: 'Special Requests'.tr(),
                        value: widget.bookTableModel.specialRequest!,
                        dark: dark,
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // MAP (only when confirmed and route is available)
            if (widget.bookTableModel.status == ORDER_STATUS_ACCEPTED && _iconsLoaded)
              _card(
                dark: dark,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: (MediaQuery.of(context).size.height * 0.28).clamp(180.0, 260.0),
                    child: _buildMap(),
                  ),
                ),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _card({required bool dark, required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgSecondary : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: dark
            ? [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))]
            : [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: child,
    );
  }

  Widget _divider(bool dark) {
    return Divider(
        height: 1,
        indent: 16,
        endIndent: 16,
        color: dark ? AppThemeData.darkBorderPrimary : AppThemeData.grey100);
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String value,
    required bool dark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppThemeData.primary500),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      fontSize: 11,
                      color: dark ? AppThemeData.grey400 : AppThemeData.grey500,
                      fontFamily: AppThemeData.medium,
                    )),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                      fontSize: 14,
                      color: dark ? Colors.white : Colors.black,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn({required IconData icon, required VoidCallback onTap, required bool dark}) {
    return Material(
      color: dark ? AppThemeData.darkBgTertiary : AppThemeData.grey100,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: AppThemeData.primary500, size: 20),
        ),
      ),
    );
  }

  Widget _buildMap() {
    if (_polylinesFuture == null) return const SizedBox.shrink();
    return FutureBuilder<PolylineResult>(
      future: _polylinesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator.adaptive(
              valueColor: AlwaysStoppedAnimation(AppThemeData.primary500),
            ),
          );
        }
        if (snapshot.hasData && snapshot.data!.status == 'OK') {
          _polylineCoordinates =
              snapshot.data!.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
          _polylines = [
            Polyline(
              polylineId: const PolylineId('route'),
              color: AppThemeData.primary500,
              width: 4,
              points: _polylineCoordinates,
            )
          ];
          if (_polylineCoordinates.isNotEmpty) {
            _markers = [
              Marker(
                markerId: const MarkerId('restaurant'),
                position: _polylineCoordinates.first,
                icon: _storeIcon,
                infoWindow: InfoWindow(title: widget.bookTableModel.vendor.title),
              ),
              Marker(
                markerId: const MarkerId('user'),
                position: _polylineCoordinates.last,
                icon: _userIcon,
                infoWindow: InfoWindow(
                    title:
                        '${widget.bookTableModel.guestFirstName} ${widget.bookTableModel.guestLastName}'),
              ),
            ];
          }
        }
        return GoogleMap(
          myLocationEnabled: false,
          compassEnabled: false,
          zoomControlsEnabled: false,
          gestureRecognizers: {
            Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())
          },
          markers: Set<Marker>.from(_markers),
          polylines: Set<Polyline>.of(_polylines),
          mapType: MapType.normal,
          initialCameraPosition: CameraPosition(
            target: LatLng(
                widget.bookTableModel.vendor.latitude, widget.bookTableModel.vendor.longitude),
            zoom: 13,
          ),
          onMapCreated: (controller) async {
            _mapController = controller;
            if (isDarkMode(context)) {
              _mapController!.setMapStyle(
                  '[{"featureType":"all","elementType":"geometry","stylers":[{"color":"#242f3e"}]},{"featureType":"all","elementType":"labels.text.stroke","stylers":[{"lightness":-80}]},{"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#2b3544"}]},{"featureType":"road.highway","elementType":"geometry.fill","stylers":[{"color":"#746855"}]},{"featureType":"water","elementType":"geometry","stylers":[{"color":"#17263c"}]}]');
            }
            if (_polylineCoordinates.length >= 2) {
              _fitMapBounds();
            }
          },
        );
      },
    );
  }

  void _fitMapBounds() async {
    if (_mapController == null || _polylineCoordinates.length < 2) return;
    final src = _polylineCoordinates.first;
    final dst = _polylineCoordinates.last;
    final LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(
        src.latitude < dst.latitude ? src.latitude : dst.latitude,
        src.longitude < dst.longitude ? src.longitude : dst.longitude,
      ),
      northeast: LatLng(
        src.latitude > dst.latitude ? src.latitude : dst.latitude,
        src.longitude > dst.longitude ? src.longitude : dst.longitude,
      ),
    );
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
  }
}

class _StatusInfo {
  final String label;
  final String subtitle;
  final Color color;
  final Color bg;
  final IconData icon;

  const _StatusInfo({
    required this.label,
    required this.subtitle,
    required this.color,
    required this.bg,
    required this.icon,
  });
}
