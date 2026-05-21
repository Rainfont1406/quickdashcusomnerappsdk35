import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/theme/responsive.dart';
import 'package:flutter/material.dart';

class VendorProductsSkeletonLoader extends StatefulWidget {
  const VendorProductsSkeletonLoader({super.key});

  @override
  State<VendorProductsSkeletonLoader> createState() =>
      _VendorProductsSkeletonLoaderState();
}

class _VendorProductsSkeletonLoaderState
    extends State<VendorProductsSkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final bool dark = isDarkMode(context);
        final Color base =
            dark ? const Color(0xFF252525) : const Color(0xFFE8E8E8);
        final Color hi =
            dark ? const Color(0xFF3C3C3C) : const Color(0xFFF5F5F5);
        final Color bg =
            dark ? AppThemeData.surfaceDark : AppThemeData.surface;
        return _buildBody(context, base, hi, bg);
      },
    );
  }

  Widget _box(
    double width,
    double height, {
    required Color base,
    required Color hi,
    double radius = 6,
  }) {
    final double t = _ctrl.value;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          colors: [base, hi, base],
          stops: const [0.0, 0.5, 1.0],
          begin: Alignment(-2.0 + 2.6 * t, 0),
          end: Alignment(-0.4 + 2.6 * t, 0),
        ),
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, Color base, Color hi, Color bg) {
    final double bannerH = Responsive.height(30, context);
    return ColoredBox(
      color: bg,
      child: Column(
        children: [
          // ── Hero banner placeholder with nav overlay ──────────────────────
          SizedBox(
            height: bannerH,
            child: Stack(
              children: [
                _box(double.infinity, bannerH, base: base, hi: hi, radius: 0),
                // Gradient overlay so nav buttons feel natural
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.25),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.45],
                    ),
                  ),
                ),
                // Back + favourite buttons
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 16,
                  right: 16,
                  child: Row(
                    children: [
                      _box(36, 36,
                          base: const Color(0xFF555555),
                          hi: const Color(0xFF666666),
                          radius: 18),
                      const Spacer(),
                      _box(36, 36,
                          base: const Color(0xFF555555),
                          hi: const Color(0xFF666666),
                          radius: 18),
                    ],
                  ),
                ),
                // Dot indicators at bottom of banner
                Positioned(
                  bottom: 10,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(3, (i) {
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == 0 ? 10 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: i == 0
                              ? AppThemeData.primary500
                              : Colors.white.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),

          // ── Scrollable content placeholder ────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Restaurant info card
                  _restaurantInfoCard(base, hi, bg),
                  const SizedBox(height: 12),

                  // Status badge
                  _box(160, 36, base: base, hi: hi, radius: 10),
                  const SizedBox(height: 16),

                  // Menu container: search + filters + products
                  _menuSectionSkeleton(base, hi, bg),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _restaurantInfoCard(Color base, Color hi, Color bg) {
    final dark = isDarkMode(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _box(160, 18, base: base, hi: hi, radius: 9),
                const SizedBox(height: 7),
                _box(120, 12, base: base, hi: hi, radius: 6),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _box(80, 11, base: base, hi: hi, radius: 5),
                    const SizedBox(width: 10),
                    _box(60, 11, base: base, hi: hi, radius: 5),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _box(80, 36, base: base, hi: hi, radius: 10),
        ],
      ),
    );
  }

  Widget _menuSectionSkeleton(Color base, Color hi, Color bg) {
    final dark = isDarkMode(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search bar
          _box(double.infinity, 46, base: base, hi: hi, radius: 14),
          const SizedBox(height: 12),

          // Veg/Non-veg filter chips
          Row(
            children: [
              Expanded(
                  child: _box(double.infinity, 38,
                      base: base, hi: hi, radius: 24)),
              const SizedBox(width: 10),
              Expanded(
                  child: _box(double.infinity, 38,
                      base: base, hi: hi, radius: 24)),
            ],
          ),
          const SizedBox(height: 16),

          // Product list placeholder — 4 items
          ..._productItems(base, hi),
        ],
      ),
    );
  }

  List<Widget> _productItems(Color base, Color hi) {
    return List.generate(4, (i) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left: text details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Veg dot
                  _box(18, 18, base: base, hi: hi, radius: 4),
                  const SizedBox(height: 7),
                  _box(140, 14, base: base, hi: hi, radius: 7),
                  const SizedBox(height: 6),
                  _box(180, 10, base: base, hi: hi, radius: 5),
                  const SizedBox(height: 4),
                  _box(120, 10, base: base, hi: hi, radius: 5),
                  const SizedBox(height: 9),
                  _box(58, 14, base: base, hi: hi, radius: 7),
                ],
              ),
            ),
            const SizedBox(width: 14),
            // Right: image + add button
            Column(
              children: [
                _box(100, 88, base: base, hi: hi, radius: 12),
                const SizedBox(height: 6),
                _box(100, 30, base: base, hi: hi, radius: 8),
              ],
            ),
          ],
        ),
      );
    });
  }
}
