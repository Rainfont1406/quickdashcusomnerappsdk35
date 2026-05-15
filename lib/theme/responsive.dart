import 'dart:math';
import 'package:flutter/material.dart';

class Responsive {
  static double width(double size, BuildContext context) {
    return MediaQuery.of(context).size.width * (size / 100);
  }

  static double height(double size, BuildContext context) {
    return MediaQuery.of(context).size.height * (size / 100);
  }

  // Returns true when the shortest screen dimension ≥ 600 dp (tablet breakpoint)
  static bool isTablet(BuildContext context) {
    final s = MediaQuery.of(context).size;
    return min(s.width, s.height) >= 600;
  }

  // Clamp a percentage-based height between a min and max pixel value
  static double clampedHeight(
    double pct,
    BuildContext context, {
    double minPx = 120,
    double maxPx = 400,
  }) {
    return MediaQuery.of(context).size.height * (pct / 100);
  }

  // Horizontal card width: 60 % on phones, 40 % on tablets
  static double cardWidth(BuildContext context) {
    return isTablet(context)
        ? MediaQuery.of(context).size.width * 0.40
        : MediaQuery.of(context).size.width * 0.60;
  }

  // Category chip width: 23 % phone, 15 % tablet
  static double categoryWidth(BuildContext context) {
    return isTablet(context)
        ? MediaQuery.of(context).size.width * 0.15
        : MediaQuery.of(context).size.width * 0.23;
  }

  // Safe horizontal padding that scales on tablets
  static EdgeInsets horizontalPadding(BuildContext context) {
    return EdgeInsets.symmetric(
      horizontal: isTablet(context) ? 32 : 16,
    );
  }
}
