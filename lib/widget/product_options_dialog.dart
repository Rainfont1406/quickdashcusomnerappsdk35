import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/AttributesModel.dart';
import 'package:emartconsumer/model/ProductAttributeConfig.dart';
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/model/variant_info.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/productDetailsScreen/ProductDetailsScreen.dart';
import 'package:emartconsumer/utils/network_image_widget.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProductOptionsDialog extends StatefulWidget {
  final ProductModel productModel;
  final Function(ProductModel, double) onAddToCart;

  const ProductOptionsDialog({
    Key? key,
    required this.productModel,
    required this.onAddToCart,
  }) : super(key: key);

  @override
  _ProductOptionsDialogState createState() => _ProductOptionsDialogState();
}

class _ProductOptionsDialogState extends State<ProductOptionsDialog> {
  // ── Legacy variant system ──────────────────────────────────────────────────
  List<String> selectedVariants = [];
  List<String> selectedIndexVariants = [];
  List<String> selectedIndexArray = [];
  List<AttributesModel> attributesList = [];

  // ── Add-ons ───────────────────────────────────────────────────────────────
  List<int> selectedAddOns = [];

  // ── New productAttribute variant system ───────────────────────────────────
  // SS: attrId → selected optionId (one pick)
  final Map<String, String> _ssSel = {};
  // MS: attrId → set of selected optionIds (multi pick)
  final Map<String, Set<String>> _msSel = {};

  // ── Price state ───────────────────────────────────────────────────────────
  double totalPrice = 0.0;
  String finalPrice = "0.0";
  String finalDisPrice = "0.0";
  bool isLoading = true;

  // ── Helpers ───────────────────────────────────────────────────────────────
  bool get _hasNewVariants =>
      widget.productModel.productAttributes.isNotEmpty &&
      widget.productModel.productAttributes.any((c) => c.options.any((o) => o.enabled));

  bool get _hasLegacyVariants =>
      widget.productModel.itemAttributes != null &&
      widget.productModel.itemAttributes!.attributes!.isNotEmpty;

  bool get _hasAddOns => widget.productModel.addOnsTitle.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _initSelectionsSync();
    _loadAttributes();
  }

  void _initSelectionsSync() {
    // Add-ons
    selectedAddOns = List.filled(widget.productModel.addOnsTitle.length, 0);

    // Legacy itemAttributes variants
    final attrs = widget.productModel.itemAttributes?.attributes;
    if (attrs != null && attrs.isNotEmpty) {
      for (int i = 0; i < attrs.length; i++) {
        final options = attrs[i].attributeOptions;
        if (options == null || options.isEmpty) {
          selectedVariants.add('');
          selectedIndexVariants.add('$i _');
          selectedIndexArray.add('${i}_-1');
          continue;
        }
        String defaultOption = options[0].toString();
        int defaultOptionIndex = 0;
        for (int j = 0; j < options.length; j++) {
          final opt = options[j].toString();
          if (_isOptionAvailable(i, opt)) {
            defaultOption = opt;
            defaultOptionIndex = j;
            break;
          }
        }
        selectedVariants.add(defaultOption);
        selectedIndexVariants.add('$i _$defaultOption');
        selectedIndexArray.add('${i}_$defaultOptionIndex');
      }
    }

    // New productAttribute variants — pre-select first enabled option for SS
    for (final cfg in widget.productModel.productAttributes) {
      final enabledOpts = cfg.options.where((o) => o.enabled).toList();
      if (cfg.type == 'SS' && enabledOpts.isNotEmpty) {
        _ssSel[cfg.attributeId] = enabledOpts.first.id;
      } else if (cfg.type == 'MS') {
        _msSel[cfg.attributeId] = {};
      }
    }

    _updatePrice();
  }

  void _loadAttributes() async {
    try {
      final attributes = await FireStoreUtils.getAttributes();
      if (mounted) setState(() { attributesList = attributes; isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  double _calcNewVariantTotal() {
    double total = 0;
    for (final cfg in widget.productModel.productAttributes) {
      final enabled = cfg.options.where((o) => o.enabled).toList();
      if (cfg.type == 'SS') {
        final selId = _ssSel[cfg.attributeId];
        final matches = enabled.where((o) => o.id == selId);
        if (matches.isNotEmpty) total += matches.first.effectivePrice;
      } else {
        final selIds = _msSel[cfg.attributeId] ?? {};
        for (final o in enabled) {
          if (selIds.contains(o.id)) total += o.effectivePrice;
        }
      }
    }
    return total;
  }

  void _updatePrice() {
    double basePrice = 0.0;
    double discountPrice = 0.0;

    if (_hasNewVariants) {
      // New variant system: variant total REPLACES base price
      basePrice = _calcNewVariantTotal();
      discountPrice = 0;
    } else {
      // Legacy itemAttributes system
      final attrs = widget.productModel.itemAttributes?.attributes;
      final variants = widget.productModel.itemAttributes?.variants;
      if (attrs != null && attrs.isNotEmpty && variants != null) {
        final matching = variants.where((e) => e.variant_sku == selectedVariants.join('-'));
        if (matching.isNotEmpty) {
          basePrice = double.parse(productCommissionPrice(matching.first.variant_price ?? '0'));
        }
      } else {
        basePrice = double.parse(productCommissionPrice(widget.productModel.price));
        discountPrice = double.parse(widget.productModel.disPrice.toString()) <= 0
            ? 0
            : double.parse(productCommissionPrice(widget.productModel.disPrice.toString()));
      }
    }

    double addOnsTotal = 0.0;
    final priceList = widget.productModel.addOnsPrice;
    for (int i = 0; i < selectedAddOns.length; i++) {
      if (selectedAddOns[i] > 0 && i < priceList.length) {
        addOnsTotal += double.parse(productCommissionPrice(priceList[i].toString())) * selectedAddOns[i];
      }
    }

    setState(() {
      totalPrice = (discountPrice > 0 ? discountPrice : basePrice) + addOnsTotal;
      finalPrice = basePrice.toString();
      finalDisPrice = discountPrice.toString();
    });
  }

  bool _isOptionAvailable(int attributeIndex, String option) {
    final variants = widget.productModel.itemAttributes?.variants;
    if (variants == null || variants.isEmpty) return true;
    return variants.any((v) {
      if (v.variant_sku == null) return false;
      final parts = v.variant_sku!.split('-');
      if (parts.length <= attributeIndex) return false;
      return parts[attributeIndex] == option && v.variant_quantity != "0";
    });
  }

  void _selectLegacyVariant(int attributeIndex, String option, int optionIndex) {
    setState(() {
      selectedVariants.removeAt(attributeIndex);
      selectedIndexVariants.removeWhere((e) => e.contains('$attributeIndex _'));
      selectedIndexArray.removeWhere((e) => e.startsWith('${attributeIndex}_'));
      selectedVariants.insert(attributeIndex, option);
      selectedIndexVariants.add('${attributeIndex} _$option');
      selectedIndexArray.add('${attributeIndex}_$optionIndex');
      _updatePrice();
    });
  }

  void _selectSS(String attrId, String optId) {
    setState(() {
      _ssSel[attrId] = optId;
      _updatePrice();
    });
  }

  void _toggleMS(String attrId, String optId) {
    setState(() {
      final set = _msSel.putIfAbsent(attrId, () => {});
      if (set.contains(optId)) {
        set.remove(optId);
      } else {
        set.add(optId);
      }
      _updatePrice();
    });
  }

  void _updateAddOnQty(int index, int change) {
    setState(() {
      selectedAddOns[index] = (selectedAddOns[index] + change).clamp(0, 10);
      _updatePrice();
    });
  }

  void _addToCart() async {
    try {
      await _saveSelectedAddOns();
      if (_hasNewVariants) await _saveNewVariantSelections();
      await Future.delayed(const Duration(milliseconds: 80));

      ProductModel updatedProduct = ProductModel(
        id: widget.productModel.id,
        name: widget.productModel.name,
        description: widget.productModel.description,
        photo: widget.productModel.photo,
        photos: widget.productModel.photos,
        categoryID: widget.productModel.categoryID,
        brandID: widget.productModel.brandID,
        vendorID: widget.productModel.vendorID,
        section_id: widget.productModel.section_id,
        price: finalPrice,
        disPrice: finalDisPrice,
        calories: widget.productModel.calories,
        grams: widget.productModel.grams,
        proteins: widget.productModel.proteins,
        fats: widget.productModel.fats,
        veg: widget.productModel.veg,
        nonveg: widget.productModel.nonveg,
        dineAway: widget.productModel.dineAway,
        deliveryOption: widget.productModel.deliveryOption,
        dineIn: widget.productModel.dineIn,
        takeaway: widget.productModel.takeaway,
        addOnsTitle: widget.productModel.addOnsTitle,
        addOnsPrice: widget.productModel.addOnsPrice,
        itemAttributes: widget.productModel.itemAttributes,
        productAttributes: widget.productModel.productAttributes,
        reviewsCount: widget.productModel.reviewsCount,
        reviewsSum: widget.productModel.reviewsSum,
        specification: widget.productModel.specification,
        reviewAttributes: widget.productModel.reviewAttributes,
        isDigitalProduct: widget.productModel.isDigitalProduct,
        digitalProduct: widget.productModel.digitalProduct,
      );

      // Legacy variant: apply variant_info
      final iaVariants = widget.productModel.itemAttributes?.variants;
      final iaAttrs = widget.productModel.itemAttributes?.attributes;
      if (selectedVariants.isNotEmpty && iaVariants != null && iaAttrs != null) {
        final matching = iaVariants.where((e) => e.variant_sku == selectedVariants.join('-'));
        if (matching.isNotEmpty) {
          final sv = matching.first;
          if (sv.variant_quantity == "0") {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text("Selected variant is out of stock. Please choose another option.".tr()),
                backgroundColor: AppThemeData.error500,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                duration: const Duration(seconds: 3),
              ));
            }
            return;
          }
          final Map<String, String> mapData = {};
          for (int ai = 0; ai < iaAttrs.length; ai++) {
            if (ai >= selectedVariants.length) break;
            final attr = iaAttrs[ai];
            final attrModel = attributesList.firstWhere(
              (a) => a.id == attr.attributesId,
              orElse: () => AttributesModel(id: attr.attributesId, title: attr.attributesId ?? ''),
            );
            mapData[attrModel.title.toString()] = selectedVariants[ai];
          }
          updatedProduct.variant_info = VariantInfo(
            variant_id: sv.variant_id,
            variant_price: sv.variant_price,
            variant_image: sv.variant_image,
            variant_sku: sv.variant_sku,
            variant_options: mapData,
          );
        }
      }

      // New productAttribute variant system: build variant_info from selections
      if (_hasNewVariants && updatedProduct.variant_info == null) {
        final Map<String, String> variantOptions = {};
        for (final cfg in widget.productModel.productAttributes) {
          if (cfg.type == 'SS') {
            final selId = _ssSel[cfg.attributeId];
            final matches = cfg.options.where((o) => o.id == selId);
            if (matches.isNotEmpty) {
              variantOptions[cfg.attributeTitle] = matches.first.name;
            }
          } else {
            final selIds = _msSel[cfg.attributeId] ?? {};
            final names = cfg.options
                .where((o) => selIds.contains(o.id))
                .map((o) => o.name)
                .join(', ');
            if (names.isNotEmpty) {
              variantOptions[cfg.attributeTitle] = names;
            }
          }
        }
        if (variantOptions.isNotEmpty) {
          updatedProduct.variant_info = VariantInfo(variant_options: variantOptions);
        }
      }

      widget.onAddToCart(updatedProduct, totalPrice);
    } catch (e) {
      debugPrint("ProductOptionsDialog._addToCart error: $e");
    }
  }

  Future<void> _saveNewVariantSelections() async {
    final sp = await SharedPreferences.getInstance();
    final Map<String, dynamic> selectionMap = {};
    for (final cfg in widget.productModel.productAttributes) {
      List<Map<String, dynamic>> selectedOpts = [];
      if (cfg.type == 'SS') {
        final selId = _ssSel[cfg.attributeId];
        final opt = cfg.options.where((o) => o.id == selId);
        if (opt.isNotEmpty) selectedOpts = [{'id': opt.first.id, 'name': opt.first.name}];
      } else {
        final selIds = _msSel[cfg.attributeId] ?? {};
        selectedOpts = cfg.options.where((o) => selIds.contains(o.id))
            .map((o) => {'id': o.id, 'name': o.name})
            .toList();
      }
      if (selectedOpts.isNotEmpty) {
        selectionMap[cfg.attributeId] = {
          'title': cfg.attributeTitle,
          'type': cfg.type,
          'options': selectedOpts,
        };
      }
    }
    await sp.setString('attr_sel_${widget.productModel.id}', jsonEncode(selectionMap));
  }

  Future<void> _saveSelectedAddOns() async {
    List<AddAddonsDemo> lstAddOns = [];
    SharedPreferences sp = await SharedPreferences.getInstance();
    String existing = sp.getString("musics_key") ?? "";
    if (existing.isNotEmpty) {
      try { lstAddOns = AddAddonsDemo.decode(existing); } catch (_) { lstAddOns = []; }
    }
    lstAddOns.removeWhere((a) => a.categoryID == widget.productModel.id);
    for (int i = 0; i < selectedAddOns.length; i++) {
      for (int j = 0; j < selectedAddOns[i]; j++) {
        lstAddOns.add(AddAddonsDemo(
          name: widget.productModel.addOnsTitle[i].toString(),
          index: i,
          isCheck: true,
          categoryID: widget.productModel.id,
          price: productCommissionPrice(widget.productModel.addOnsPrice[i].toString()),
        ));
      }
    }
    try { await sp.setString("musics_key", AddAddonsDemo.encode(lstAddOns)); } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasNewVariants && !_hasLegacyVariants && !_hasAddOns) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onAddToCart(widget.productModel, totalPrice);
      });
      return const SizedBox.shrink();
    }

    final bg = isDarkMode(context) ? AppThemeData.surfaceDark : Colors.white;
    final divColor = isDarkMode(context) ? AppThemeData.grey800 : AppThemeData.grey100;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 0),
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: isDarkMode(context) ? AppThemeData.grey600 : AppThemeData.grey300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: NetworkImageWidget(
                    imageUrl: widget.productModel.photo.toString(),
                    fit: BoxFit.cover, height: 60, width: 60,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.productModel.name,
                        style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold,
                          color: isDarkMode(context) ? AppThemeData.grey50 : AppThemeData.grey900,
                          fontFamily: AppThemeData.semiBold,
                        ),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "Customize your order".tr(),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDarkMode(context) ? AppThemeData.grey400 : AppThemeData.grey600,
                          fontFamily: AppThemeData.regular,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isDarkMode(context) ? AppThemeData.grey800 : AppThemeData.grey100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close, size: 18,
                        color: isDarkMode(context) ? AppThemeData.grey300 : AppThemeData.grey700),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 20, thickness: 1, color: divColor),
          // Scrollable content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_hasNewVariants) ..._buildNewVariantsSection(),
                  if (_hasLegacyVariants) ..._buildLegacyVariantsSection(),
                  if (_hasAddOns) ..._buildAddOnsSection(),
                ],
              ),
            ),
          ),
          // Footer: price + add button
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: bg,
                border: Border(top: BorderSide(color: divColor, width: 1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Total".tr(),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDarkMode(context) ? AppThemeData.grey400 : AppThemeData.grey600,
                            fontFamily: AppThemeData.regular,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          amountShow(amount: totalPrice.toStringAsFixed(2)),
                          style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold,
                            color: AppThemeData.primary500,
                            fontFamily: AppThemeData.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _addToCart,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppThemeData.primary500,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 2,
                    ),
                    child: Text(
                      "Add Item".tr(),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── New productAttribute SS/MS section ─────────────────────────────────────
  List<Widget> _buildNewVariantsSection() {
    final isDark = isDarkMode(context);
    final configs = widget.productModel.productAttributes
        .where((c) => c.options.any((o) => o.enabled))
        .toList();
    if (configs.isEmpty) return [];

    return [
      _sectionHeader("Choose Variant".tr()),
      const SizedBox(height: 10),
      ...configs.map((cfg) => _buildAttrGroup(cfg, isDark)),
    ];
  }

  Widget _buildAttrGroup(ProductAttributeConfig cfg, bool isDark) {
    final isMS = cfg.type == 'MS';
    final enabledOpts = cfg.options.where((o) => o.enabled).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF374151) : const Color(0xFFF3F4F6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group header
          Row(
            children: [
              Expanded(
                child: Text(
                  cfg.attributeTitle,
                  style: TextStyle(
                    fontSize: 14, fontFamily: AppThemeData.semiBold,
                    color: isDark ? AppThemeData.grey50 : AppThemeData.grey900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isMS
                      ? const Color(0xFF3B82F6).withValues(alpha: 0.12)
                      : const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isMS ? 'Pick multiple'.tr() : 'Pick one'.tr(),
                  style: TextStyle(
                    fontSize: 10, fontFamily: AppThemeData.medium,
                    color: isMS ? const Color(0xFF3B82F6) : const Color(0xFF10B981),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Options
          ...enabledOpts.map((opt) => isMS
              ? _buildMSRow(cfg.attributeId, opt, isDark)
              : _buildSSRow(cfg.attributeId, opt, isDark)),
        ],
      ),
    );
  }

  Widget _buildSSRow(String attrId, ProductAttributeOption opt, bool isDark) {
    final isSelected = _ssSel[attrId] == opt.id;
    return GestureDetector(
      onTap: () => _selectSS(attrId, opt.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: isSelected
              ? AppThemeData.primary500.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppThemeData.primary500.withValues(alpha: 0.5)
                : (isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB)),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            // Radio indicator
            Container(
              width: 18, height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppThemeData.primary500 : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppThemeData.primary500,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                opt.name,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: isSelected ? AppThemeData.semiBold : AppThemeData.regular,
                  color: isSelected
                      ? (isDark ? AppThemeData.grey50 : AppThemeData.grey900)
                      : (isDark ? AppThemeData.grey300 : AppThemeData.grey700),
                ),
              ),
            ),
            _buildPriceWidget(opt, isSelected, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildMSRow(String attrId, ProductAttributeOption opt, bool isDark) {
    final isSelected = (_msSel[attrId] ?? {}).contains(opt.id);
    return GestureDetector(
      onTap: () => _toggleMS(attrId, opt.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: isSelected
              ? AppThemeData.primary500.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppThemeData.primary500.withValues(alpha: 0.5)
                : (isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB)),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            // Checkbox indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 18, height: 18,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: isSelected ? AppThemeData.primary500 : Colors.transparent,
                border: Border.all(
                  color: isSelected ? AppThemeData.primary500 : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                opt.name,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: isSelected ? AppThemeData.semiBold : AppThemeData.regular,
                  color: isSelected
                      ? (isDark ? AppThemeData.grey50 : AppThemeData.grey900)
                      : (isDark ? AppThemeData.grey300 : AppThemeData.grey700),
                ),
              ),
            ),
            _buildPriceWidget(opt, isSelected, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceWidget(ProductAttributeOption opt, bool isSelected, bool isDark) {
    if (opt.price <= 0 && opt.discountedPrice <= 0) {
      return Text(
        'Free'.tr(),
        style: TextStyle(fontSize: 12, fontFamily: AppThemeData.medium, color: const Color(0xFF10B981)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          amountShow(amount: opt.effectivePrice.toStringAsFixed(2)),
          style: TextStyle(
            fontSize: 13, fontFamily: AppThemeData.semiBold,
            color: isSelected ? AppThemeData.primary500 : (isDark ? AppThemeData.grey300 : AppThemeData.grey700),
          ),
        ),
        if (opt.discountedPrice > 0 && opt.price > 0)
          Text(
            amountShow(amount: opt.price.toStringAsFixed(2)),
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppThemeData.grey500 : AppThemeData.grey400,
              decoration: TextDecoration.lineThrough,
            ),
          ),
      ],
    );
  }

  // ── Legacy itemAttributes section ──────────────────────────────────────────
  List<Widget> _buildLegacyVariantsSection() {
    return [
      _sectionHeader("Choose Options".tr()),
      const SizedBox(height: 10),
      ...widget.productModel.itemAttributes!.attributes!.asMap().entries.map((entry) {
        final attributeIndex = entry.key;
        final attribute = entry.value;

        String attributeName = "Option ${attributeIndex + 1}";
        try {
          AttributesModel? found = attributesList.isNotEmpty
              ? attributesList.firstWhere(
                  (a) => a.id == attribute.attributesId,
                  orElse: () => AttributesModel(id: attribute.attributesId, title: attributeName),
                )
              : null;
          if (found?.title?.isNotEmpty == true) attributeName = found!.title!;
        } catch (_) {}

        final options = attribute.attributeOptions;
        if (options == null || options.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(
              color: isDarkMode(context) ? AppThemeData.grey700 : AppThemeData.grey200,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    attributeName,
                    style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700,
                      color: isDarkMode(context) ? AppThemeData.grey100 : AppThemeData.grey800,
                      fontFamily: AppThemeData.semiBold,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppThemeData.primary500.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      "Required".tr(),
                      style: const TextStyle(fontSize: 10, color: AppThemeData.primary500, fontFamily: AppThemeData.medium),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: options.asMap().entries.map((optEntry) {
                  final optionIndex = optEntry.key;
                  final option = optEntry.value.toString();
                  final isSelected = selectedVariants.length > attributeIndex &&
                      selectedVariants[attributeIndex] == option;
                  final isAvailable = _isOptionAvailable(attributeIndex, option);
                  final dark = isDarkMode(context);

                  return GestureDetector(
                    onTap: isAvailable
                        ? () => _selectLegacyVariant(attributeIndex, option, optionIndex)
                        : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: !isAvailable
                            ? (dark ? AppThemeData.grey900 : AppThemeData.grey100)
                            : (isSelected
                                ? AppThemeData.primary500
                                : (dark ? AppThemeData.grey800 : AppThemeData.grey50)),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: !isAvailable
                              ? (dark ? AppThemeData.grey800 : AppThemeData.grey200)
                              : (isSelected
                                  ? AppThemeData.primary500
                                  : (dark ? AppThemeData.grey700 : AppThemeData.grey300)),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            option,
                            style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600,
                              color: !isAvailable
                                  ? (dark ? AppThemeData.grey600 : AppThemeData.grey400)
                                  : (isSelected
                                      ? Colors.white
                                      : (dark ? AppThemeData.grey200 : AppThemeData.grey800)),
                              fontFamily: AppThemeData.medium,
                              decoration: !isAvailable ? TextDecoration.lineThrough : null,
                              decorationColor: dark ? AppThemeData.grey600 : AppThemeData.grey400,
                            ),
                          ),
                          if (!isAvailable) ...[
                            const SizedBox(height: 2),
                            Text("Sold out", style: TextStyle(
                              fontSize: 9, fontFamily: AppThemeData.regular,
                              color: dark ? AppThemeData.grey600 : AppThemeData.grey400,
                            )),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      }).toList(),
      const SizedBox(height: 4),
    ];
  }

  // ── Add-ons section ────────────────────────────────────────────────────────
  List<Widget> _buildAddOnsSection() {
    return [
      _sectionHeader("Add-ons".tr()),
      const SizedBox(height: 10),
      ...widget.productModel.addOnsTitle.asMap().entries.map((entry) {
        final index = entry.key;
        final title = entry.value.toString();
        if (index >= widget.productModel.addOnsPrice.length || index >= selectedAddOns.length) {
          return const SizedBox.shrink();
        }
        final price = widget.productModel.addOnsPrice[index].toString();
        final isSelected = selectedAddOns[index] > 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppThemeData.primary500.withValues(alpha: 0.05)
                : (isDarkMode(context) ? AppThemeData.grey800.withValues(alpha: 0.5) : AppThemeData.grey50),
            border: Border.all(
              color: isSelected
                  ? AppThemeData.primary500.withValues(alpha: 0.4)
                  : (isDarkMode(context) ? AppThemeData.grey700 : AppThemeData.grey200),
              width: isSelected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: isDarkMode(context) ? AppThemeData.grey100 : AppThemeData.grey800,
                      fontFamily: AppThemeData.medium,
                    )),
                    const SizedBox(height: 2),
                    Text("+ ${amountShow(amount: productCommissionPrice(price))}",
                        style: const TextStyle(fontSize: 13, color: AppThemeData.primary500, fontFamily: AppThemeData.medium)),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isSelected ? AppThemeData.primary500 : (isDarkMode(context) ? AppThemeData.grey700 : AppThemeData.grey300),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: selectedAddOns[index] > 0 ? () => _updateAddOnQty(index, -1) : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 30, height: 30,
                        decoration: BoxDecoration(
                          color: isSelected ? AppThemeData.primary500 : (isDarkMode(context) ? AppThemeData.grey700 : AppThemeData.grey200),
                          borderRadius: const BorderRadius.only(topLeft: Radius.circular(6), bottomLeft: Radius.circular(6)),
                        ),
                        child: Icon(Icons.remove, size: 14, color: isSelected ? Colors.white : AppThemeData.grey500),
                      ),
                    ),
                    SizedBox(
                      width: 32, height: 30,
                      child: Center(child: Text(
                        selectedAddOns[index].toString(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold,
                          color: isDarkMode(context) ? AppThemeData.grey100 : AppThemeData.grey900,
                          fontFamily: AppThemeData.semiBold,
                        ),
                      )),
                    ),
                    GestureDetector(
                      onTap: () => _updateAddOnQty(index, 1),
                      child: Container(
                        width: 30, height: 30,
                        decoration: const BoxDecoration(
                          color: AppThemeData.primary500,
                          borderRadius: BorderRadius.only(topRight: Radius.circular(6), bottomRight: Radius.circular(6)),
                        ),
                        child: const Icon(Icons.add, size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    ];
  }

  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 3, height: 16,
          decoration: BoxDecoration(color: AppThemeData.primary500, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold,
          color: isDarkMode(context) ? AppThemeData.grey50 : AppThemeData.grey900,
          fontFamily: AppThemeData.semiBold,
        )),
      ],
    );
  }
}
