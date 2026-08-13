import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/constants/typography.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';

// The "You saved ₹X on this order" pill — pops in with a small bounce when
// it first appears, then keeps a slow breathing scale and a light diagonal
// shine sweeping across it on a loop, so it stays noticeable instead of
// reading as flat, static text. Shared by CartScreen and BillPayRequestScreen
// so both show savings the same way.
class SavingsBanner extends StatefulWidget {
  final double totalSavings;
  final bool dark;

  const SavingsBanner({super.key, required this.totalSavings, required this.dark});

  @override
  State<SavingsBanner> createState() => _SavingsBannerState();
}

class _SavingsBannerState extends State<SavingsBanner>
    with TickerProviderStateMixin {
  late final AnimationController _loopController;
  late final AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    _loopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    )..forward();
  }

  @override
  void dispose() {
    _loopController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: CurvedAnimation(
        parent: _entranceController,
        curve: Curves.elasticOut,
      ),
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _entranceController,
          curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 300.0;
            return AnimatedBuilder(
              animation: _loopController,
              builder: (context, _) {
                final t = _loopController.value;
                final breathe = 1.0 + 0.02 * math.sin(t * 2 * math.pi);
                // The shine only plays for the first slice of each loop,
                // then sits still until the next lap — a periodic sweep
                // reads as a deliberate highlight, a continuous one reads
                // as noise.
                const sweepWindow = 0.4;
                final sweepActive = t <= sweepWindow;
                final sweepProgress = sweepActive ? (t / sweepWindow) : 1.0;

                return Transform.scale(
                  scale: breathe,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: widget.dark
                                ? AppThemeData.success400.withValues(alpha: 0.15)
                                : AppThemeData.success50,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.local_offer_rounded,
                                color: AppThemeData.success400,
                                size: 15,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${'You saved'.tr()} ${amountShow(amount: widget.totalSavings.toStringAsFixed(2))} ${'on this order'.tr()}',
                                style: AppTypography.labelMedium.copyWith(
                                  color: AppThemeData.success400,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (sweepActive)
                          Positioned(
                            left: -70 + sweepProgress * (w + 140),
                            top: 0,
                            bottom: 0,
                            width: 70,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [
                                      Colors.white.withValues(alpha: 0.0),
                                      Colors.white.withValues(alpha: 0.45),
                                      Colors.white.withValues(alpha: 0.0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
