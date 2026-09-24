import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/bunny_reference_mirror.dart';
import 'package:emartconsumer/services/firestore_instrumentation.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

class TermsAndCondition extends StatefulWidget {
  const TermsAndCondition({Key? key}) : super(key: key);

  @override
  State<TermsAndCondition> createState() => _TermsAndConditionState();
}

class _TermsAndConditionState extends State<TermsAndCondition> {
  String? _content;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    // 2026-09-25: Bunny mirror first (0 Firestore reads, cached 24h on the
    // device); the original Firestore read below is the fallback.
    final mirrored = await fetchLegalTextFromBunny('terms-and-conditions.json', 'terms_and_condition');
    if (mirrored != null) {
      if (mounted) setState(() => _content = mirrored);
      return;
    }
    try {
      final doc = await FireStoreUtils.firestore
          .collection(Setting)
          .doc("termsAndConditions")
          .getLogged('_loadContent:Setting');
      if (mounted) {
        setState(() {
          _content = doc['terms_and_condition'] as String?;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    return Scaffold(
      backgroundColor: dark ? AppThemeData.surfaceDark : const Color(0xFFF4F6FA),
      appBar: AppBar(
        backgroundColor:
            dark ? AppThemeData.darkBgSecondary : Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Terms & Conditions'.tr(),
          style: TextStyle(
            fontSize: 18,
            fontFamily: AppThemeData.semiBold,
            color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: dark
                ? AppThemeData.darkBorderPrimary
                : AppThemeData.neutral200,
          ),
        ),
      ),
      body: _buildBody(dark),
    );
  }

  Widget _buildBody(bool dark) {
    if (_hasError) {
      return _buildError(dark);
    }
    if (_content == null) {
      return _buildShimmer(dark);
    }
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppThemeData.primary500, AppThemeData.primary600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppThemeData.primary500.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.gavel_rounded,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Terms & Conditions'.tr(),
                        style: const TextStyle(
                          fontSize: 17,
                          fontFamily: AppThemeData.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Please read carefully before using our service.'.tr(),
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: AppThemeData.regular,
                          color: Colors.white.withValues(alpha: 0.8),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Content card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: dark ? AppThemeData.darkBgSecondary : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.2 : 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: HtmlWidget(
              _content!,
              textStyle: TextStyle(
                fontSize: 14,
                fontFamily: AppThemeData.regular,
                color: dark
                    ? AppThemeData.darkTextSecondary
                    : AppThemeData.neutral700,
                height: 1.65,
              ),
              onErrorBuilder: (context, element, error) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        size: 16, color: AppThemeData.danger300),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$element ${"error: ".tr()}$error',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppThemeData.danger300,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              onLoadingBuilder: (context, element, loadingProgress) =>
                  const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppThemeData.primary500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          // Footer note
          Center(
            child: Text(
              'Last updated · QuickDash'.tr(),
              style: TextStyle(
                fontSize: 12,
                fontFamily: AppThemeData.regular,
                color: dark
                    ? AppThemeData.darkTextTertiary
                    : AppThemeData.neutral400,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildShimmer(bool dark) {
    final base = dark ? const Color(0xFF1E2A3A) : const Color(0xFFEEF0F4);
    final highlight =
        dark ? const Color(0xFF2A3A50) : const Color(0xFFF8F9FB);
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: _ShimmerBox(
        dark: dark,
        base: base,
        highlight: highlight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header placeholder
            Container(
              height: 88,
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(height: 20),
            // Content block placeholders
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: dark ? AppThemeData.darkBgSecondary : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < 5; i++) ...[
                    _ShimmerLine(width: i == 0 ? 0.5 : 1.0, base: base),
                    const SizedBox(height: 10),
                    _ShimmerLine(width: 1.0, base: base),
                    const SizedBox(height: 8),
                    _ShimmerLine(width: 0.85, base: base),
                    const SizedBox(height: 8),
                    _ShimmerLine(width: 0.95, base: base),
                    const SizedBox(height: 20),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(bool dark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppThemeData.danger300.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wifi_off_rounded,
                  size: 36, color: AppThemeData.danger300),
            ),
            const SizedBox(height: 20),
            Text(
              'Unable to load content'.tr(),
              style: TextStyle(
                fontSize: 18,
                fontFamily: AppThemeData.semiBold,
                color: dark
                    ? AppThemeData.darkTextPrimary
                    : AppThemeData.neutral900,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Please check your connection and try again.'.tr(),
              style: TextStyle(
                fontSize: 14,
                fontFamily: AppThemeData.regular,
                color: dark
                    ? AppThemeData.darkTextSecondary
                    : AppThemeData.neutral500,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.refresh_rounded,
                    color: Colors.white, size: 18),
                label: Text(
                  'Try Again'.tr(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontFamily: AppThemeData.semiBold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppThemeData.primary500,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  setState(() => _hasError = false);
                  _loadContent();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShimmerBox extends StatefulWidget {
  final bool dark;
  final Color base;
  final Color highlight;
  final Widget child;

  const _ShimmerBox({
    required this.dark,
    required this.base,
    required this.highlight,
    required this.child,
  });

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0, end: 1).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          colors: [widget.base, widget.highlight, widget.base],
          stops: [0.0, _anim.value, 1.0],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(bounds),
        child: widget.child,
      ),
    );
  }
}

class _ShimmerLine extends StatelessWidget {
  final double width;
  final Color base;

  const _ShimmerLine({required this.width, required this.base});

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: width,
      alignment: Alignment.centerLeft,
      child: Container(
        height: 13,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}
