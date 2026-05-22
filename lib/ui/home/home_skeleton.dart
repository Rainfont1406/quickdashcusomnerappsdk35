import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/theme/responsive.dart';
import 'package:flutter/material.dart';

class HomeSkeletonLoader extends StatefulWidget {
  const HomeSkeletonLoader({super.key});

  @override
  State<HomeSkeletonLoader> createState() => _HomeSkeletonLoaderState();
}

class _HomeSkeletonLoaderState extends State<HomeSkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = isDarkMode(context);
    final Color base =
        dark ? const Color(0xFF232323) : const Color(0xFFEAEAEA);
    final Color hi =
        dark ? const Color(0xFF3A3A3A) : const Color(0xFFF8F8F8);

    return ColoredBox(
      color: dark ? AppThemeData.surfaceDark : AppThemeData.surface,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) => _buildBody(context, base, hi, _anim.value),
      ),
    );
  }

  // ── Shimmer box ─────────────────────────────────────────────────────────────
  // All boxes share the same shimmer `t` so the light wave sweeps the whole
  // screen simultaneously rather than each box individually.

  Widget _box(
    double width,
    double height, {
    required Color base,
    required Color hi,
    required double t,
    double radius = 6,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          colors: [base, hi, base],
          stops: const [0.0, 0.5, 1.0],
          begin: Alignment(-2.4 + 3.6 * t, -0.3),
          end: Alignment(-0.6 + 3.6 * t, 0.3),
        ),
      ),
    );
  }

  // ── Layout helpers ───────────────────────────────────────────────────────────

  Widget _section({required List<Widget> children}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );

  Widget _titleRow(Color base, Color hi, double t) => Row(
        children: [
          _box(130, 18, base: base, hi: hi, t: t, radius: 9),
          const Spacer(),
          _box(56, 13, base: base, hi: hi, t: t, radius: 7),
        ],
      );

  // ── Full skeleton body ───────────────────────────────────────────────────────

  Widget _buildBody(BuildContext context, Color base, Color hi, double t) {
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.of(context).viewPadding.top),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerSkeleton(base, hi, t),
              Expanded(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      _storiesRow(base, hi, t),
                      const SizedBox(height: 20),
                      _section(children: [
                        _titleRow(base, hi, t),
                        const SizedBox(height: 10),
                        _categoryGrid(base, hi, t),
                      ]),
                      const SizedBox(height: 32),
                      _section(children: [_bannerSkeleton(base, hi, t)]),
                      const SizedBox(height: 28),
                      _section(children: [
                        _titleRow(base, hi, t),
                        const SizedBox(height: 12),
                      ]),
                      _topSellingRow(context, base, hi, t),
                      const SizedBox(height: 28),
                      _section(children: [
                        _titleRow(base, hi, t),
                        const SizedBox(height: 12),
                      ]),
                      _newArrivalRow(context, base, hi, t),
                      const SizedBox(height: 32),
                      _section(children: [_bannerSkeleton(base, hi, t)]),
                      const SizedBox(height: 28),
                      _section(children: [
                        _titleRow(base, hi, t),
                        const SizedBox(height: 12),
                        ..._restaurantCards(context, base, hi, t),
                      ]),
                      const SizedBox(height: 110),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── FAB skeleton pinned at bottom ──────────────────────────────────
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 12,
            left: 0,
            right: 0,
            child: Center(
              child: _fabSkeleton(base, hi, t),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────────

  Widget _headerSkeleton(Color base, Color hi, double t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Row(
            children: [
              _box(42, 42, base: base, hi: hi, t: t, radius: 21),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _box(100, 13, base: base, hi: hi, t: t, radius: 7),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        _box(12, 12, base: base, hi: hi, t: t, radius: 6),
                        const SizedBox(width: 4),
                        _box(155, 12, base: base, hi: hi, t: t, radius: 6),
                        const SizedBox(width: 4),
                        _box(14, 14, base: base, hi: hi, t: t, radius: 7),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _box(42, 42, base: base, hi: hi, t: t, radius: 21),
            ],
          ),
          const SizedBox(height: 12),
          _box(double.infinity, 48, base: base, hi: hi, t: t, radius: 12),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Stories row ──────────────────────────────────────────────────────────────

  Widget _storiesRow(Color base, Color hi, double t) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, __) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _box(64, 64, base: base, hi: hi, t: t, radius: 32),
            const SizedBox(height: 7),
            _box(44, 9, base: base, hi: hi, t: t, radius: 5),
          ],
        ),
      ),
    );
  }

  // ── Category grid ────────────────────────────────────────────────────────────

  Widget _categoryGrid(Color base, Color hi, double t) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.72,
        mainAxisSpacing: 10,
        crossAxisSpacing: 8,
      ),
      itemCount: 8,
      itemBuilder: (_, __) => Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _box(54, 54, base: base, hi: hi, t: t, radius: 14),
          const SizedBox(height: 7),
          _box(42, 10, base: base, hi: hi, t: t, radius: 5),
        ],
      ),
    );
  }

  // ── Banner ───────────────────────────────────────────────────────────────────

  Widget _bannerSkeleton(Color base, Color hi, double t) =>
      _box(double.infinity, 145, base: base, hi: hi, t: t, radius: 18);

  // ── Top Selling horizontal row ────────────────────────────────────────────────

  Widget _topSellingRow(BuildContext context, Color base, Color hi, double t) {
    final double cardH =
        (MediaQuery.of(context).size.width * 0.56).clamp(180.0, 250.0);
    final double imgH = (cardH * 0.52).roundToDouble();
    final double bodyH = cardH - imgH;
    return SizedBox(
      height: cardH,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) =>
            _topSellingCard(cardH, imgH, bodyH, base, hi, t),
      ),
    );
  }

  Widget _topSellingCard(
      double cardH, double imgH, double bodyH, Color base, Color hi, double t) {
    return Container(
      width: 150,
      height: cardH,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _box(double.infinity, imgH, base: base, hi: hi, t: t, radius: 0),
          SizedBox(
            height: bodyH,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _box(110, 12, base: base, hi: hi, t: t, radius: 6),
                      const SizedBox(height: 6),
                      _box(72, 10, base: base, hi: hi, t: t, radius: 5),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _box(52, 12, base: base, hi: hi, t: t, radius: 6),
                      _box(32, 12, base: base, hi: hi, t: t, radius: 6),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── New Arrivals horizontal row ───────────────────────────────────────────────

  Widget _newArrivalRow(BuildContext context, Color base, Color hi, double t) {
    final double cardH = Responsive.height(26, context);
    final double imgH = Responsive.height(14, context);
    return SizedBox(
      height: cardH,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) =>
            _newArrivalCard(cardH, imgH, base, hi, t),
      ),
    );
  }

  Widget _newArrivalCard(
      double cardH, double imgH, Color base, Color hi, double t) {
    return Container(
      width: 155,
      height: cardH,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _box(double.infinity, imgH, base: base, hi: hi, t: t, radius: 0),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _box(115, 12, base: base, hi: hi, t: t, radius: 6),
                  _box(80, 10, base: base, hi: hi, t: t, radius: 5),
                  Row(
                    children: [
                      _box(32, 10, base: base, hi: hi, t: t, radius: 5),
                      const Spacer(),
                      _box(44, 10, base: base, hi: hi, t: t, radius: 5),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── All Restaurants vertical list ─────────────────────────────────────────────

  List<Widget> _restaurantCards(
      BuildContext context, Color base, Color hi, double t) {
    final double imgH = Responsive.height(22, context);
    return List.generate(3, (i) {
      return Padding(
        padding: EdgeInsets.only(bottom: i == 2 ? 0 : 20),
        child: Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _box(double.infinity, imgH, base: base, hi: hi, t: t, radius: 0),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _box(160, 16, base: base, hi: hi, t: t, radius: 8),
                        const Spacer(),
                        _box(56, 22, base: base, hi: hi, t: t, radius: 11),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _box(12, 12, base: base, hi: hi, t: t, radius: 6),
                        const SizedBox(width: 4),
                        _box(90, 11, base: base, hi: hi, t: t, radius: 5),
                        const SizedBox(width: 12),
                        _box(12, 12, base: base, hi: hi, t: t, radius: 6),
                        const SizedBox(width: 4),
                        _box(55, 11, base: base, hi: hi, t: t, radius: 5),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _box(52, 22, base: base, hi: hi, t: t, radius: 6),
                        const SizedBox(width: 8),
                        _box(100, 12, base: base, hi: hi, t: t, radius: 6),
                        const Spacer(),
                        _box(88, 30, base: base, hi: hi, t: t, radius: 20),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  // ── FAB skeleton ──────────────────────────────────────────────────────────────

  Widget _fabSkeleton(Color base, Color hi, double t) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _box(24, 24, base: hi, hi: base, t: t, radius: 6),
          const SizedBox(width: 10),
          _box(24, 24, base: hi, hi: base, t: t, radius: 6),
          const SizedBox(width: 16),
          _box(1, 30, base: hi, hi: base, t: t, radius: 0),
          const SizedBox(width: 16),
          _box(90, 20, base: hi, hi: base, t: t, radius: 10),
        ],
      ),
    );
  }
}
