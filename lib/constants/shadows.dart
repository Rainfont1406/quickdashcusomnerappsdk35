// lib/constants/shadows.dart
import 'package:flutter/material.dart';

class AppShadows {
  static const BoxShadow shadowNone = BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0),
    offset: Offset(0, 0),
    blurRadius: 0,
  );

  static const BoxShadow shadowSm = BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.04),
    offset: Offset(0, 1),
    blurRadius: 2,
  );

  static const BoxShadow shadowMd = BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.06),
    offset: Offset(0, 2),
    blurRadius: 4,
  );

  static const BoxShadow shadowLg = BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.08),
    offset: Offset(0, 4),
    blurRadius: 8,
  );

  static const BoxShadow shadowXl = BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.10),
    offset: Offset(0, 8),
    blurRadius: 16,
  );

  static const BoxShadow shadow2xl = BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.12),
    offset: Offset(0, 16),
    blurRadius: 32,
  );
}