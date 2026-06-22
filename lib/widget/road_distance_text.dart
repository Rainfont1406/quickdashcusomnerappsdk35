import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:flutter/material.dart';

/// Displays road driving distance to a vendor using OSRM.
/// Shows '-- km' while loading or when user location is unavailable.
/// Results are cached per session so repeated builds don't re-fetch.
class RoadDistanceText extends StatefulWidget {
  final double vendorLat;
  final double vendorLon;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool showAwaySuffix;

  const RoadDistanceText({
    super.key,
    required this.vendorLat,
    required this.vendorLon,
    this.style,
    this.maxLines,
    this.overflow,
    this.showAwaySuffix = false,
  });

  @override
  State<RoadDistanceText> createState() => _RoadDistanceTextState();
}

class _RoadDistanceTextState extends State<RoadDistanceText> {
  late Future<String> _future;
  String _userPositionKey = '';

  @override
  void initState() {
    super.initState();
    _userPositionKey = _buildPositionKey();
    _future = _fetchDistance();
  }

  @override
  void didUpdateWidget(RoadDistanceText old) {
    super.didUpdateWidget(old);
    final newKey = _buildPositionKey();
    if (newKey != _userPositionKey ||
        old.vendorLat != widget.vendorLat ||
        old.vendorLon != widget.vendorLon) {
      _userPositionKey = newKey;
      setState(() {
        _future = _fetchDistance();
      });
    }
  }

  String _buildPositionKey() {
    final loc = MyAppState.selectedPosotion.location;
    if (loc == null) return '';
    return '${loc.latitude.toStringAsFixed(4)},${loc.longitude.toStringAsFixed(4)}';
  }

  Future<String> _fetchDistance() async {
    final suffix = widget.showAwaySuffix ? ' away' : '';
    final loc = MyAppState.selectedPosotion.location;
    if (loc == null) return '-- km$suffix';
    final km = await getRoadDistanceKm(
      loc,
      UserLocation(latitude: widget.vendorLat, longitude: widget.vendorLon),
    );
    final d = double.tryParse(km) ?? 0;
    final meters = d * 1000;
    if (widget.showAwaySuffix && meters <= 20) return 'Nearby';
    if (d < 1) return '${meters.toStringAsFixed(0)} m$suffix';
    return '${d.toStringAsFixed(1)} km$suffix';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _future,
      builder: (ctx, snap) {
        final text = snap.data ?? '-- km${widget.showAwaySuffix ? ' away' : ''}';
        final isNearby = text == 'Nearby';
        return Text(
          text,
          style: isNearby
              ? widget.style?.copyWith(color: const Color(0xFF16A34A))
              : widget.style,
          maxLines: widget.maxLines,
          overflow: widget.overflow,
        );
      },
    );
  }
}
