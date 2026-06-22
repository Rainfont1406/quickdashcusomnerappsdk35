import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/OrderModel.dart';
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/model/variant_info.dart';
import 'package:emartconsumer/services/app_dialog.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/ui/cartScreen/CartScreen.dart';
import 'package:emartconsumer/ui/container/ContainerScreen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/typography.dart';

// ─── Data model ───────────────────────────────────────────────────────────────

class _ProductRow {
  final CartProduct original;
  final ProductModel? current;
  final String? reason; // null = available
  final bool priceChanged;
  final String? newPrice; // for variant products: updated price from Firestore
  bool excluded = false; // user dismissed this unavailable item from view

  _ProductRow({
    required this.original,
    this.current,
    this.reason,
    this.priceChanged = false,
    this.newPrice,
  });

  bool get isAvailable => reason == null;

  String get displayPrice =>
      (priceChanged && current != null)
          ? (newPrice ?? current!.price)
          : original.price;

  double get lineTotal {
    final base = double.tryParse(displayPrice) ?? 0;
    final extras = double.tryParse(original.extras_price ?? '0') ?? 0;
    return original.quantity * (base + extras);
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class ReOrderReviewScreen extends StatefulWidget {
  final OrderModel orderModel;

  const ReOrderReviewScreen({Key? key, required this.orderModel})
      : super(key: key);

  @override
  State<ReOrderReviewScreen> createState() => _ReOrderReviewScreenState();
}

class _ReOrderReviewScreenState extends State<ReOrderReviewScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _submitting = false;
  VendorModel? _vendor;
  bool _vendorClosed = false;
  List<_ProductRow> _rows = [];
  late AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _validate();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  // ── Validation ────────────────────────────────────────────────────────────

  Future<void> _validate() async {
    final futures = <Future<dynamic>>[
      FireStoreUtils.getVendor(widget.orderModel.vendorID),
      ...widget.orderModel.products.map((cp) async {
        try {
          return await FireStoreUtils().getProductByID(cp.id.split('~').first);
        } catch (_) {
          return null;
        }
      }),
    ];

    final results = await Future.wait(futures);
    _vendor = results[0] as VendorModel?;
    if (_vendor != null && !_vendor!.isAcceptingOrders) {
      _vendorClosed = true;
    }

    final rows = <_ProductRow>[];
    for (var i = 0; i < widget.orderModel.products.length; i++) {
      final cp = widget.orderModel.products[i];
      final fresh = results[i + 1] as ProductModel?;
      String? reason;
      bool priceChanged = false;
      // Declared outside the if/else so it stays in scope for _ProductRow below.
      String? newVariantPrice;

      if (fresh == null || !fresh.publish) {
        reason = 'No longer available'.tr();
      } else {
        // variant_options is always stored as {} (empty map) in the cart, so
        // checking variant_options.isNotEmpty always returns false and wrongly
        // treats every variant product as a plain product. Use variant_sku
        // instead — it IS stored correctly and uniquely identifies the selected
        // variant combination (e.g. "M-Red").
        final vi = _getVariantInfo(cp.variant_info);
        final sku = vi?.variant_sku ?? '';

        if (vi != null) {
          // Variant product — never compare against the base product price.
          // variant_sku may be empty if the vendor didn't set SKUs, so guard.
          if (sku.isNotEmpty) {
            final freshVariants = fresh.itemAttributes?.variants;
            if (freshVariants != null && freshVariants.isNotEmpty) {
              final freshVariant = freshVariants
                  .where((v) => v.variant_sku == sku)
                  .firstOrNull;
              if (freshVariant != null) {
                final oldP = double.tryParse(cp.price) ?? 0;
                final newP = double.tryParse(freshVariant.variant_price ?? '0') ?? 0;
                if ((oldP - newP).abs() > 0.001) {
                  priceChanged = true;
                  newVariantPrice = freshVariant.variant_price;
                }
              }
            }
          }
          // If sku is empty or variant not found in fresh data, we cannot
          // determine whether the price changed — keep priceChanged=false and
          // reuse the original order price rather than falling back to the
          // wrong base product price.
        } else {
          // Plain product (no variant selected) — safe to compare base prices.
          final oldP = double.tryParse(cp.price) ?? 0;
          final newP = double.tryParse(fresh.price) ?? 0;
          if ((oldP - newP).abs() > 0.001) priceChanged = true;
        }
      }

      rows.add(_ProductRow(
        original: cp,
        current: fresh,
        reason: reason,
        priceChanged: priceChanged,
        newPrice: newVariantPrice,
      ));
    }

    if (mounted) setState(() { _rows = rows; _loading = false; });
  }

  // ── Cart action ────────────────────────────────────────────────────────────

  Future<void> _addToCart() async {
    final db = Provider.of<CartDatabase>(context, listen: false);
    final existing = await db.allCartProducts;

    if (existing.isNotEmpty &&
        existing.any((p) => p.vendorID != widget.orderModel.vendorID)) {
      final confirmed = await AppDialog.showConfirm(
        context,
        title: 'Replace Cart?'.tr(),
        message: 'Your cart has items from another restaurant. Adding these items will clear your current cart.'.tr(),
        confirmLabel: 'Clear & Add'.tr(),
        cancelLabel: 'Cancel'.tr(),
        destructive: true,
      );
      if (!confirmed) return;
      await db.deleteAllProducts();
    }

    setState(() => _submitting = true);
    for (final row in _rows) {
      if (!row.isAvailable) continue;
      CartProduct cp = row.original;
      if (row.priceChanged && row.current != null) {
        cp = CartProduct(
          id: row.original.id,
          category_id: row.original.category_id,
          name: row.original.name,
          photo: row.original.photo,
          // For variant products newPrice is the updated variant price;
          // for non-variant products fall back to fresh base price.
          price: row.newPrice ?? row.current!.price,
          discountPrice: row.newPrice != null ? '' : (row.current!.disPrice ?? ''),
          vendorID: row.original.vendorID,
          quantity: row.original.quantity,
          extras_price: row.original.extras_price,
          extras: row.original.extras,
          variant_info: row.original.variant_info,
        );
      }
      await db.reAddProduct(cp);
    }

    if (!mounted) return;
    // Open CartScreen inside ContainerScreen so the AppBar, back button, and
    // drawer are all present — CartScreen has no AppBar of its own.
    pushAndRemoveUntil(
      context,
      ContainerScreen(
        user: MyAppState.currentUser,
        currentWidget: const CartScreen(),
        appBarTitle: 'Your Cart'.tr(),
        drawerSelection: DrawerSelection.Cart,
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  int get _availableCount => _rows.where((r) => r.isAvailable).length;

  double get _subtotal =>
      _rows.where((r) => r.isAvailable).fold(0.0, (s, r) => s + r.lineTotal);

  List<String> _parseAddons(dynamic raw) {
    String clean(String s) {
      s = s.replaceAll('"', '').trim();
      while (s.startsWith('/')) s = s.substring(1).trim();
      while (s.endsWith('/')) s = s.substring(0, s.length - 1).trim();
      return s;
    }

    if (raw is List) {
      return raw
          .map((e) => clean(e.toString()))
          .where((s) => s.isNotEmpty && s != 'null' && s != '[]')
          .toList();
    }
    if (raw is String && raw.isNotEmpty && raw != '[]') {
      final c =
          raw.replaceAll('[', '').replaceAll(']', '').replaceAll('"', '');
      final sep = c.contains(',') ? ',' : '/';
      return c
          .split(sep)
          .map((s) => clean(s))
          .where((s) => s.isNotEmpty && s != 'null')
          .toList();
    }
    return [];
  }

  VariantInfo? _getVariantInfo(dynamic raw) {
    if (raw is VariantInfo) return raw;
    if (raw is Map<String, dynamic>) return VariantInfo.fromJson(raw);
    if (raw is String && raw.isNotEmpty && raw != 'null') {
      try { return VariantInfo.fromJson(jsonDecode(raw)); } catch (_) {}
    }
    return null;
  }

  List<MapEntry<String, dynamic>> _parseVariants(dynamic raw) {
    final vi = _getVariantInfo(raw);
    return (vi?.variant_options?.isNotEmpty ?? false)
        ? vi!.variant_options!.entries.toList()
        : [];
  }

  Widget _chip(String label, {bool isVariant = false, required bool dark}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isVariant
            ? AppThemeData.primary500.withValues(alpha: dark ? 0.18 : 0.10)
            : (dark ? AppThemeData.neutral800 : AppThemeData.neutral100),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isVariant
              ? AppThemeData.primary500.withValues(alpha: dark ? 0.40 : 0.30)
              : (dark ? AppThemeData.neutral700 : AppThemeData.neutral200),
          width: 0.7,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppThemeData.semiBold,
          fontSize: 11,
          color: isVariant
              ? AppThemeData.primary500
              : (dark ? AppThemeData.neutral300 : AppThemeData.neutral600),
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    return Scaffold(
      backgroundColor:
          dark ? AppThemeData.darkBgPrimary : const Color(0xFFF4F5F9),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: dark ? AppThemeData.darkBgSecondary : Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          color: dark ? Colors.white : AppThemeData.neutral900,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Review Order'.tr(),
          style: AppTypography.h6.copyWith(
            fontWeight: FontWeight.w700,
            color: dark ? Colors.white : AppThemeData.neutral900,
          ),
        ),
      ),
      body: _loading ? _buildSkeleton(dark) : _buildContent(dark),
    );
  }

  // ── Skeleton ───────────────────────────────────────────────────────────────

  Widget _sk(double w, double h, double r, bool dark) {
    return AnimatedBuilder(
      animation: _shimmerCtrl,
      builder: (_, __) {
        final v = _shimmerCtrl.value;
        return Container(
          width: w > 0 ? w : null,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(r),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                dark ? AppThemeData.neutral800 : AppThemeData.neutral200,
                dark ? AppThemeData.neutral700 : AppThemeData.neutral100,
                dark ? AppThemeData.neutral800 : AppThemeData.neutral200,
              ],
              stops: [
                (v - 0.3).clamp(0.0, 1.0),
                v.clamp(0.0, 1.0),
                (v + 0.3).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSkeleton(bool dark) {
    final bg = dark ? AppThemeData.darkBgSecondary : Colors.white;
    final shadow = [
      BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 10,
          offset: const Offset(0, 3))
    ];
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Restaurant card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: shadow),
                child: Row(
                  children: [
                    _sk(56, 56, 14, dark),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sk(150, 14, 7, dark),
                        const SizedBox(height: 8),
                        _sk(70, 22, 11, dark),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _sk(80, 10, 5, dark),
              const SizedBox(height: 10),
              // 3 product card shimmers
              for (int i = 0; i < 3; i++) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: shadow),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sk(48, 48, 10, dark),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Full-width name line
                            Row(children: [
                              Expanded(child: _sk(0, 13, 6, dark)),
                            ]),
                            const SizedBox(height: 8),
                            Row(children: [
                              _sk(58, 22, 11, dark),
                              const SizedBox(width: 6),
                              _sk(58, 22, 11, dark),
                            ]),
                            const SizedBox(height: 8),
                            _sk(60, 13, 6, dark),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        // Bottom bar skeleton
        Container(
          color: bg,
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
          child: Row(children: [
            Expanded(child: _sk(0, 52, 14, dark)),
          ]),
        ),
      ],
    );
  }

  // ── Content ────────────────────────────────────────────────────────────────

  Widget _buildContent(bool dark) {
    final visible = _rows.where((r) => !r.excluded).toList();
    final avail = _availableCount;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _buildRestaurantCard(dark),
              if (_vendorClosed) ...[
                const SizedBox(height: 12),
                _buildBanner(
                  Icons.access_time_rounded,
                  'Restaurant is currently closed. You can still add items to your cart.'
                      .tr(),
                  const Color(0xFFF59E0B),
                  dark,
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'ORDER ITEMS'.tr(),
                style: TextStyle(
                  fontFamily: AppThemeData.semiBold,
                  fontSize: 11,
                  letterSpacing: 0.9,
                  color: AppThemeData.neutral500,
                ),
              ),
              const SizedBox(height: 10),
              ...visible.map((row) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildProductCard(row, dark),
                  )),
              if (avail > 0) ...[
                const SizedBox(height: 4),
                _buildSummaryCard(dark),
              ],
            ],
          ),
        ),
        _buildBottomBar(dark, avail),
      ],
    );
  }

  Widget _buildRestaurantCard(bool dark) {
    final isDining = widget.orderModel.orderType == 'Dining';
    final isTakeaway = widget.orderModel.takeAway == true ||
        widget.orderModel.orderType == 'Takeaway';
    final typeLabel = isDining
        ? 'Dine-In'
        : isTakeaway
            ? 'Takeaway'
            : 'Delivery';
    final typeColor = isDining
        ? AppThemeData.secondary300
        : isTakeaway
            ? AppThemeData.warning300
            : AppThemeData.success400;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgSecondary : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 3))
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              widget.orderModel.vendor.photo.isNotEmpty
                  ? widget.orderModel.vendor.photo
                  : placeholderImage,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppThemeData.neutral100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.store_rounded,
                    color: AppThemeData.neutral400, size: 24),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.orderModel.vendor.title,
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    color: dark ? Colors.white : AppThemeData.neutral900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: typeColor.withValues(alpha: 0.40), width: 0.8),
                  ),
                  child: Text(
                    typeLabel.tr(),
                    style: TextStyle(
                      fontFamily: AppThemeData.semiBold,
                      fontSize: 11,
                      color: typeColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBanner(IconData icon, String msg, Color color, bool dark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(
                fontFamily: AppThemeData.regular,
                fontSize: 12,
                height: 1.5,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(_ProductRow row, bool dark) {
    final avail = row.isAvailable;
    final variants = _parseVariants(row.original.variant_info);
    final addons = _parseAddons(row.original.extras);
    final isVeg = row.current?.veg ?? false;
    final isNonVeg = row.current?.nonveg ?? false;

    return Opacity(
      opacity: avail ? 1.0 : 0.55,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: dark ? AppThemeData.darkBgSecondary : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: row.reason != null
              ? Border.all(
                  color: AppThemeData.error500.withValues(alpha: 0.30),
                  width: 1)
              : null,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildThumb(row, isVeg, isNonVeg),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: avail
                                  ? AppThemeData.primary500
                                      .withValues(alpha: 0.10)
                                  : AppThemeData.neutral200,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '×${row.original.quantity}',
                              style: TextStyle(
                                fontFamily: AppThemeData.semiBold,
                                fontSize: 11,
                                color: avail
                                    ? AppThemeData.primary500
                                    : AppThemeData.neutral400,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              row.original.name,
                              style: AppTypography.bodySmall.copyWith(
                                fontWeight: FontWeight.w600,
                                color: dark
                                    ? (avail
                                        ? Colors.white
                                        : AppThemeData.neutral600)
                                    : (avail
                                        ? AppThemeData.neutral900
                                        : AppThemeData.neutral400),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (variants.isNotEmpty || addons.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: [
                            ...variants.map((e) => _chip(e.value.toString(),
                                isVariant: true, dark: dark)),
                            ...addons.map((e) => _chip(e, dark: dark)),
                          ],
                        ),
                      ],
                      const SizedBox(height: 7),
                      _buildPriceRow(row, dark),
                    ],
                  ),
                ),
              ],
            ),
            // Unavailable badge + dismiss
            if (row.reason != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppThemeData.error500.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color:
                              AppThemeData.error500.withValues(alpha: 0.25),
                          width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.remove_circle_outline_rounded,
                            size: 11, color: AppThemeData.error500),
                        const SizedBox(width: 4),
                        Text(
                          row.reason!,
                          style: TextStyle(
                            fontFamily: AppThemeData.medium,
                            fontSize: 11,
                            color: AppThemeData.error500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => row.excluded = true),
                    child: Text(
                      'Dismiss'.tr(),
                      style: TextStyle(
                        fontFamily: AppThemeData.semiBold,
                        fontSize: 12,
                        color: AppThemeData.neutral400,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            // Price-change notice (available items only)
            if (avail && row.priceChanged) ...[
              const SizedBox(height: 8),
              _buildBanner(
                Icons.price_change_outlined,
                'Price has been updated for this item.'.tr(),
                AppThemeData.warning300,
                dark,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildThumb(_ProductRow row, bool isVeg, bool isNonVeg) {
    if (row.original.photo.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          row.original.photo,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _vegIndicator(isVeg, isNonVeg),
        ),
      );
    }
    return _vegIndicator(isVeg, isNonVeg);
  }

  Widget _vegIndicator(bool isVeg, bool isNonVeg) {
    final color = isNonVeg
        ? AppThemeData.error500
        : isVeg
            ? AppThemeData.success400
            : AppThemeData.neutral300;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Center(
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 1.5),
            borderRadius: isNonVeg
                ? BorderRadius.circular(2)
                : BorderRadius.circular(3),
          ),
          child: Center(
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: color,
                shape:
                    isNonVeg ? BoxShape.rectangle : BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPriceRow(_ProductRow row, bool dark) {
    if (row.priceChanged && row.current != null) {
      return Row(
        children: [
          Text(
            amountShow(amount: row.original.price),
            style: TextStyle(
              fontFamily: AppThemeData.regular,
              fontSize: 12,
              color: AppThemeData.neutral400,
              decoration: TextDecoration.lineThrough,
              decorationColor: AppThemeData.neutral400,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            // displayPrice uses newPrice (updated variant price) for variant
            // products and current!.price (fresh base price) for plain ones —
            // never raw current!.price which is always the base product price.
            amountShow(amount: row.displayPrice),
            style: AppTypography.labelMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: AppThemeData.primary500,
            ),
          ),
        ],
      );
    }
    return Text(
      amountShow(amount: row.displayPrice),
      style: AppTypography.labelMedium.copyWith(
        fontWeight: FontWeight.w700,
        color: dark ? AppThemeData.neutral200 : AppThemeData.neutral800,
      ),
    );
  }

  Widget _buildSummaryCard(bool dark) {
    final avail = _availableCount;
    final total = _rows.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgSecondary : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            avail < total
                ? '$avail of $total ${avail == 1 ? 'item' : 'items'} available'
                    .tr()
                : '$avail ${avail == 1 ? 'item' : 'items'} ready to add'.tr(),
            style: AppTypography.caption.copyWith(color: AppThemeData.neutral500),
          ),
          Text(
            '${'Est.'.tr()} ${amountShow(amount: _subtotal.toStringAsFixed(2))}',
            style: AppTypography.labelMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: dark ? Colors.white : AppThemeData.neutral900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(bool dark, int avail) {
    final total = _rows.length;
    final String label;
    final bool enabled;

    if (_submitting) {
      label = 'Adding to cart...'.tr();
      enabled = false;
    } else if (avail == 0) {
      label = 'No items available'.tr();
      enabled = false;
    } else if (avail < total) {
      label = 'Add $avail ${avail == 1 ? 'item' : 'items'} to Cart'.tr();
      enabled = true;
    } else {
      label = 'Add All to Cart'.tr();
      enabled = true;
    }

    return Container(
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgSecondary : Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4))
        ],
      ),
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      child: GestureDetector(
        onTap: (enabled && !_submitting) ? _addToCart : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 52,
          decoration: BoxDecoration(
            gradient: enabled
                ? const LinearGradient(
                    colors: [AppThemeData.primary500, AppThemeData.primary600])
                : null,
            color: enabled ? null : AppThemeData.neutral200,
            borderRadius: BorderRadius.circular(14),
            boxShadow: enabled
                ? [
                    BoxShadow(
                        color: AppThemeData.primary500.withValues(alpha: 0.28),
                        blurRadius: 14,
                        offset: const Offset(0, 5))
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_submitting)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor:
                          AlwaysStoppedAnimation(Colors.white)),
                )
              else
                Icon(Icons.shopping_cart_checkout_rounded,
                    size: 18,
                    color: enabled ? Colors.white : AppThemeData.neutral400),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppThemeData.semiBold,
                  fontSize: 15,
                  color: enabled ? Colors.white : AppThemeData.neutral400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
