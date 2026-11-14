import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:flutter/material.dart';

/// True when a dish has a usable photo URL (not empty / "null").
/// Same rule as newVendorProductsScreen's _hasDishPhoto.
bool hasDishPhoto(String? url) {
  final u = (url ?? '').trim();
  return u.isNotEmpty && u != 'null' && u.startsWith('http');
}

/// 2026-11-14 (owner): a dish with no photo shows a soft brand tint (with the
/// dish name when [name] is given) instead of the QuickDash placeholder image.
/// Same look as the restaurant menu's no-photo panel (d4459a6).
class NoPhotoPanel extends StatelessWidget {
  final String? name;
  final double? height;
  final double? width;
  final double radius;
  final double fontSize;

  const NoPhotoPanel({
    super.key,
    this.name,
    this.height,
    this.width,
    this.radius = 0,
    this.fontSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkMode(context);
    return Container(
      height: height,
      width: width ?? double.infinity,
      padding: name == null ? null : const EdgeInsets.fromLTRB(10, 30, 10, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: isDark
            ? AppThemeData.primary500.withValues(alpha: 0.18)
            : AppThemeData.primary500.withValues(alpha: 0.07),
      ),
      alignment: Alignment.bottomLeft,
      child: name == null
          ? null
          : Text(
              name!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppThemeData.grey900,
              ),
            ),
    );
  }
}

/// Round fallback for a vendor logo that is missing or fails to load: the
/// restaurant's first letter on the brand colour - the same look the Home story
/// circle already uses when a vendor has no logo at all. Used instead of the
/// QuickDash placeholder, which reads as "wrong restaurant" (2026-11-14).
class InitialAvatar extends StatelessWidget {
  final String name;
  final double size;
  const InitialAvatar({super.key, required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    final t = name.trim();
    return Container(
      width: size,
      height: size,
      color: AppThemeData.primary500,
      alignment: Alignment.center,
      child: Text(
        t.isNotEmpty ? t[0].toUpperCase() : '?',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
