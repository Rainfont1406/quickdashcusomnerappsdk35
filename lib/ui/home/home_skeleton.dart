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
    final bool dark = isDarkMode(context);
    return ColoredBox(
      // Fill the scaffold background immediately on first frame — prevents white flash
      color: dark ? AppThemeData.surfaceDark : AppThemeData.surface,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final Color base =
              dark ? const Color(0xFF252525) : const Color(0xFFE8E8E8);
          final Color hi =
              dark ? const Color(0xFF3C3C3C) : const Color(0xFFF5F5F5);
          return _buildBody(context, base, hi);
        },
      ),
    );
  }

  // ── Core shimmer box ──────────────────────────────────────────────────────

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

  // ── Layout helpers ────────────────────────────────────────────────────────

  Widget _section({required List<Widget> children}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );

  Widget _titleRow(Color base, Color hi) => Row(
        children: [
          _box(140, 18, base: base, hi: hi, radius: 9),
          const Spacer(),
          _box(52, 13, base: base, hi: hi, radius: 6),
        ],
      );

  // ── Full skeleton body ────────────────────────────────────────────────────

  Widget _buildBody(BuildContext context, Color base, Color hi) {
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.of(context).viewPadding.top),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _headerSkeleton(base, hi),
          Expanded(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _storiesRow(base, hi),
                  const SizedBox(height: 20),
                  _section(children: [
                    _titleRow(base, hi),
                    const SizedBox(height: 10),
                    _categoryGrid(base, hi),
                  ]),
                  const SizedBox(height: 32),
                  _section(children: [_bannerSkeleton(base, hi)]),
                  const SizedBox(height: 24),
                  _section(children: [
                    _titleRow(base, hi),
                    const SizedBox(height: 10),
                  ]),
                  _topSellingRow(context, base, hi),
                  const SizedBox(height: 24),
                  _section(children: [
                    _titleRow(base, hi),
                    const SizedBox(height: 10),
                  ]),
                  _newArrivalRow(context, base, hi),
                  const SizedBox(height: 32),
                  _section(children: [_bannerSkeleton(base, hi)]),
                  const SizedBox(height: 24),
                  _section(children: [
                    _titleRow(base, hi),
                    const SizedBox(height: 10),
                    ..._restaurantCards(context, base, hi),
                  ]),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _headerSkeleton(Color base, Color hi) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Row(
            children: [
              _box(42, 42, base: base, hi: hi, radius: 21),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _box(110, 14, base: base, hi: hi, radius: 7),
                    const SizedBox(height: 6),
                    _box(170, 12, base: base, hi: hi, radius: 6),
                  ],
                ),
              ),
              _box(42, 42, base: base, hi: hi, radius: 21),
            ],
          ),
          const SizedBox(height: 12),
          _box(double.infinity, 48, base: base, hi: hi, radius: 12),
          const SizedBox(height: 5),
        ],
      ),
    );
  }

  // ── Stories row ───────────────────────────────────────────────────────────

  Widget _storiesRow(Color base, Color hi) {
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _box(62, 62, base: base, hi: hi, radius: 31),
            const SizedBox(height: 6),
            _box(48, 9, base: base, hi: hi, radius: 5),
          ],
        ),
      ),
    );
  }

  // ── Category grid ─────────────────────────────────────────────────────────

  Widget _categoryGrid(Color base, Color hi) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.72,
        mainAxisSpacing: 10,
        crossAxisSpacing: 5,
      ),
      itemCount: 8,
      itemBuilder: (_, __) => Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _box(54, 54, base: base, hi: hi, radius: 27),
          const SizedBox(height: 6),
          _box(40, 10, base: base, hi: hi, radius: 5),
        ],
      ),
    );
  }

  // ── Banner ────────────────────────────────────────────────────────────────

  Widget _bannerSkeleton(Color base, Color hi) =>
      _box(double.infinity, 140, base: base, hi: hi, radius: 16);

  // ── Top Selling horizontal row ─────────────────────────────────────────────

  Widget _topSellingRow(BuildContext context, Color base, Color hi) {
    final double cardH =
        (MediaQuery.of(context).size.width * 0.56).clamp(180.0, 250.0);
    final double imgH = (cardH * 0.524).roundToDouble();
    final double bodyH = cardH - imgH;
    return SizedBox(
      height: cardH,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => _topSellingCard(cardH, imgH, bodyH, base, hi),
      ),
    );
  }

  Widget _topSellingCard(
      double cardH, double imgH, double bodyH, Color base, Color hi) {
    return Container(
      width: 148,
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
          _box(double.infinity, imgH, base: base, hi: hi, radius: 0),
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
                      _box(100, 12, base: base, hi: hi, radius: 6),
                      const SizedBox(height: 5),
                      _box(70, 10, base: base, hi: hi, radius: 5),
                    ],
                  ),
                  _box(58, 12, base: base, hi: hi, radius: 6),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── New Arrivals horizontal row ────────────────────────────────────────────

  Widget _newArrivalRow(BuildContext context, Color base, Color hi) {
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
        itemBuilder: (_, __) => _newArrivalCard(cardH, imgH, base, hi),
      ),
    );
  }

  Widget _newArrivalCard(double cardH, double imgH, Color base, Color hi) {
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
          _box(double.infinity, imgH, base: base, hi: hi, radius: 0),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _box(110, 12, base: base, hi: hi, radius: 6),
                  _box(80, 10, base: base, hi: hi, radius: 5),
                  Row(
                    children: [
                      _box(30, 10, base: base, hi: hi, radius: 5),
                      const Spacer(),
                      _box(40, 10, base: base, hi: hi, radius: 5),
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

  // ── All Restaurants vertical list ──────────────────────────────────────────

  List<Widget> _restaurantCards(
      BuildContext context, Color base, Color hi) {
    final double imgH = Responsive.height(24, context);
    return List.generate(3, (i) {
      return Padding(
        padding: EdgeInsets.only(bottom: i == 2 ? 0 : 24),
        child: Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _box(double.infinity, imgH, base: base, hi: hi, radius: 0),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _box(180, 18, base: base, hi: hi, radius: 9),
                    const SizedBox(height: 10),
                    Divider(height: 1, thickness: 0.8, color: base),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _box(70, 13, base: base, hi: hi, radius: 6),
                        const Spacer(),
                        _box(90, 13, base: base, hi: hi, radius: 6),
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
}
