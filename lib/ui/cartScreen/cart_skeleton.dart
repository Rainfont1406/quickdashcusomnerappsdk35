import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';

class CartSkeletonLoader extends StatefulWidget {
  const CartSkeletonLoader({super.key});

  @override
  State<CartSkeletonLoader> createState() => _CartSkeletonLoaderState();
}

class _CartSkeletonLoaderState extends State<CartSkeletonLoader>
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

  Widget _buildBody(BuildContext context, Color base, Color hi, Color bg) {
    return ColoredBox(
      color: bg,
      child: SafeArea(
        child: Column(
          children: [
            // ── App bar ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  _box(38, 38, base: base, hi: hi, radius: 19),
                  const SizedBox(width: 14),
                  _box(70, 17, base: base, hi: hi, radius: 8),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ── Scrollable content ───────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Items container card
                    _itemsCard(base, hi),
                    const SizedBox(height: 14),

                    // Coupon row
                    _flatCard(base, hi, _couponRow(base, hi)),
                    const SizedBox(height: 10),

                    // Address / schedule row
                    _flatCard(base, hi, _simpleRow(base, hi, 90, 160)),
                    const SizedBox(height: 10),

                    // Bill details card
                    _billCard(base, hi),
                    const SizedBox(height: 10),

                    // Tip section
                    _flatCard(base, hi, _simpleRow(base, hi, 110, 130)),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),

            // ── Place Order bar ──────────────────────────────────────────────
            _checkoutBar(base, hi),
          ],
        ),
      ),
    );
  }

  // ── Items container ─────────────────────────────────────────────────────────

  Widget _itemsCard(Color base, Color hi) {
    final dark = isDarkMode(context);
    final divider = Divider(
        height: 1,
        thickness: 1,
        color: dark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0));
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: "Your Order" + vendor
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _box(110, 16, base: base, hi: hi, radius: 8),
                const SizedBox(height: 6),
                _box(80, 11, base: base, hi: hi, radius: 5),
              ],
            ),
          ),
          divider,
          // Cart item 1
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: _cartItem(base, hi),
          ),
          divider,
          // Cart item 2
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: _cartItem(base, hi),
          ),
          divider,
          // Add more items row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              children: [
                _box(18, 18, base: base, hi: hi, radius: 9),
                const SizedBox(width: 10),
                _box(110, 12, base: base, hi: hi, radius: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartItem(Color base, Color hi) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Thumbnail
        _box(70, 70, base: base, hi: hi, radius: 12),
        const SizedBox(width: 12),
        // Name + description + price
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _box(130, 14, base: base, hi: hi, radius: 7),
              const SizedBox(height: 6),
              _box(90, 10, base: base, hi: hi, radius: 5),
              const SizedBox(height: 10),
              _box(56, 14, base: base, hi: hi, radius: 7),
            ],
          ),
        ),
        const SizedBox(width: 10),
        // Qty controls + price
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _box(56, 10, base: base, hi: hi, radius: 5),
            const SizedBox(height: 8),
            _box(90, 30, base: base, hi: hi, radius: 20),
          ],
        ),
      ],
    );
  }

  // ── Generic section card ────────────────────────────────────────────────────

  Widget _flatCard(Color base, Color hi, Widget child) {
    final dark = isDarkMode(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: child,
    );
  }

  Widget _couponRow(Color base, Color hi) => Row(
        children: [
          _box(36, 36, base: base, hi: hi, radius: 10),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _box(100, 13, base: base, hi: hi, radius: 6),
                const SizedBox(height: 5),
                _box(150, 10, base: base, hi: hi, radius: 5),
              ],
            ),
          ),
          _box(26, 26, base: base, hi: hi, radius: 13),
        ],
      );

  Widget _simpleRow(Color base, Color hi, double labelW, double valueW) => Row(
        children: [
          _box(36, 36, base: base, hi: hi, radius: 10),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _box(labelW, 13, base: base, hi: hi, radius: 6),
                const SizedBox(height: 5),
                _box(valueW, 10, base: base, hi: hi, radius: 5),
              ],
            ),
          ),
        ],
      );

  // ── Bill card ───────────────────────────────────────────────────────────────

  Widget _billCard(Color base, Color hi) {
    final dark = isDarkMode(context);
    final dividerColor =
        dark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        children: [
          _billRow(base, hi, 80, 50),
          const SizedBox(height: 10),
          _billRow(base, hi, 64, 56),
          const SizedBox(height: 10),
          _billRow(base, hi, 100, 42),
          const SizedBox(height: 10),
          _billRow(base, hi, 72, 38),
          const SizedBox(height: 12),
          Divider(height: 1, thickness: 1, color: dividerColor),
          const SizedBox(height: 12),
          _billRow(base, hi, 72, 64, large: true),
        ],
      ),
    );
  }

  Widget _billRow(Color base, Color hi, double labelW, double valueW,
      {bool large = false}) {
    final h = large ? 16.0 : 12.0;
    return Row(
      children: [
        _box(labelW, h, base: base, hi: hi, radius: 6),
        const Spacer(),
        _box(valueW, h, base: base, hi: hi, radius: 6),
      ],
    );
  }

  // ── Checkout bar ─────────────────────────────────────────────────────────────

  Widget _checkoutBar(Color base, Color hi) {
    return Container(
      decoration: BoxDecoration(
        color: AppThemeData.primary500.withValues(alpha: 0.25),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _box(56, 10, base: base, hi: hi, radius: 5),
                  const SizedBox(height: 5),
                  _box(76, 18, base: base, hi: hi, radius: 9),
                ],
              ),
              _box(130, 46, base: base, hi: hi, radius: 14),
            ],
          ),
        ),
      ),
    );
  }
}
