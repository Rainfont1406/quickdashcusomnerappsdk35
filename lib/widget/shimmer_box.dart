import 'package:emartconsumer/services/helper.dart';
import 'package:flutter/material.dart';

/// Shared shimmer/skeleton loading placeholder. Used anywhere an image is
/// still loading — replaces spinner-style indicators (CircularProgressIndicator)
/// with the same pulsing-box look used for the Home screen's skeleton and
/// story shimmer states, so loading reads as "content is arriving" rather
/// than "something is stuck."
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height = 105,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
          ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(
            dark ? const Color(0xFF2A2A2A) : const Color(0xFFE4E4E4),
            dark ? const Color(0xFF383838) : const Color(0xFFF5F5F5),
            _ctrl.value,
          ),
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      ),
    );
  }
}
