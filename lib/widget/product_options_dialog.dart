import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/AttributesModel.dart';
import 'package:emartconsumer/model/ItemAttributes.dart';
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
  List<String> selectedVariants = [];
  List<String> selectedIndexVariants = [];
  List<String> selectedIndexArray = [];
  List<int> selectedAddOns = [];
  List<AttributesModel> attributesList = [];
  double totalPrice = 0.0;
  String finalPrice = "0.0";
  String finalDisPrice = "0.0";
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    // Eagerly initialize all selection state before the first build()
    // to prevent RangeError when accessing selectedAddOns/selectedVariants.
    _initSelectionsSync();
    _loadAttributes();
  }

  // Synchronous init — runs before the first build so no index is ever
  // accessed on an empty list.
  void _initSelectionsSync() {
    // Add-ons: fill all slots with 0 immediately
    selectedAddOns = List.filled(widget.productModel.addOnsTitle.length, 0);

    // Variants: pick the first available option per attribute
    final attrs = widget.productModel.itemAttributes?.attributes;
    if (attrs == null || attrs.isEmpty) return;

    for (int i = 0; i < attrs.length; i++) {
      final options = attrs[i].attributeOptions;
      if (options == null || options.isEmpty) {
        // Keep lists in sync even when an attribute has no options
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
    _updatePrice();
  }

  void _loadAttributes() async {
    try {
      final attributes = await FireStoreUtils.getAttributes();
      if (mounted) {
        setState(() {
          attributesList = attributes;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _updatePrice() {
    double basePrice = 0.0;
    double discountPrice = 0.0;

    final attrs = widget.productModel.itemAttributes?.attributes;
    final variants = widget.productModel.itemAttributes?.variants;
    if (attrs != null && attrs.isNotEmpty && variants != null) {
      final matchingVariants = variants
          .where((e) => e.variant_sku == selectedVariants.join('-'));
      if (matchingVariants.isNotEmpty) {
        basePrice = double.parse(
            productCommissionPrice(matchingVariants.first.variant_price ?? '0'));
        discountPrice = 0;
      }
    } else {
      basePrice =
          double.parse(productCommissionPrice(widget.productModel.price));
      discountPrice =
          double.parse(widget.productModel.disPrice.toString()) <= 0
              ? 0
              : double.parse(productCommissionPrice(
                  widget.productModel.disPrice.toString()));
    }

    double addOnsTotal = 0.0;
    final priceList = widget.productModel.addOnsPrice;
    for (int i = 0; i < selectedAddOns.length; i++) {
      if (selectedAddOns[i] > 0 && i < priceList.length) {
        addOnsTotal += double.parse(
                productCommissionPrice(priceList[i].toString())) *
            selectedAddOns[i];
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

  void _selectVariantOption(int attributeIndex, String option, int optionIndex) {
    setState(() {
      selectedVariants.removeAt(attributeIndex);
      selectedIndexVariants
          .removeWhere((e) => e.contains('$attributeIndex _'));
      selectedIndexArray
          .removeWhere((e) => e.startsWith('${attributeIndex}_'));
      selectedVariants.insert(attributeIndex, option);
      selectedIndexVariants.add('${attributeIndex} _$option');
      selectedIndexArray.add('${attributeIndex}_$optionIndex');
      _updatePrice();
    });
  }

  void _updateAddOnQuantity(int index, int change) {
    setState(() {
      selectedAddOns[index] = (selectedAddOns[index] + change).clamp(0, 10);
      _updatePrice();
    });
  }

  void _addToCart() async {
    try {
      await _saveSelectedAddOns();
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
      takeaway: widget.productModel.takeaway,
      deliveryOption: widget.productModel.deliveryOption,
      addOnsTitle: widget.productModel.addOnsTitle,
      addOnsPrice: widget.productModel.addOnsPrice,
      itemAttributes: widget.productModel.itemAttributes,
      reviewsCount: widget.productModel.reviewsCount,
      reviewsSum: widget.productModel.reviewsSum,
      specification: widget.productModel.specification,
      reviewAttributes: widget.productModel.reviewAttributes,
      isDigitalProduct: widget.productModel.isDigitalProduct,
      digitalProduct: widget.productModel.digitalProduct,
    );

    final iaVariants = widget.productModel.itemAttributes?.variants;
    final iaAttrs = widget.productModel.itemAttributes?.attributes;
    if (selectedVariants.isNotEmpty &&
        iaVariants != null &&
        iaAttrs != null) {
      final matchingVariants = iaVariants
          .where((e) => e.variant_sku == selectedVariants.join('-'));
      if (matchingVariants.isNotEmpty) {
        final selectedVariant = matchingVariants.first;
        if (selectedVariant.variant_quantity == "0") {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "Selected variant is out of stock. Please choose another option.".tr(),
                ),
                backgroundColor: AppThemeData.error500,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                duration: const Duration(seconds: 3),
              ),
            );
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
          variant_id: selectedVariant.variant_id,
          variant_price: selectedVariant.variant_price,
          variant_image: selectedVariant.variant_image,
          variant_sku: selectedVariant.variant_sku,
          variant_options: mapData,
        );
      }
    }

      widget.onAddToCart(updatedProduct, totalPrice);
    } catch (e) {
      debugPrint("ProductOptionsDialog._addToCart error: $e");
    }
  }

  Future<void> _saveSelectedAddOns() async {
    List<AddAddonsDemo> lstAddOns = [];
    SharedPreferences sp = await SharedPreferences.getInstance();
    String existingAddOns = sp.getString("musics_key") ?? "";
    if (existingAddOns.isNotEmpty) {
      try {
        lstAddOns = AddAddonsDemo.decode(existingAddOns);
      } catch (_) {
        lstAddOns = [];
      }
    }
    lstAddOns.removeWhere((a) => a.categoryID == widget.productModel.id);
    for (int i = 0; i < selectedAddOns.length; i++) {
      for (int j = 0; j < selectedAddOns[i]; j++) {
        lstAddOns.add(AddAddonsDemo(
          name: widget.productModel.addOnsTitle[i].toString(),
          index: i,
          isCheck: true,
          categoryID: widget.productModel.id,
          price: productCommissionPrice(
              widget.productModel.addOnsPrice[i].toString()),
        ));
      }
    }
    try {
      await sp.setString("musics_key", AddAddonsDemo.encode(lstAddOns));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    bool hasVariants = widget.productModel.itemAttributes != null &&
        widget.productModel.itemAttributes!.attributes!.isNotEmpty;
    bool hasAddOns = widget.productModel.addOnsTitle.isNotEmpty;

    if (!hasVariants && !hasAddOns) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onAddToCart(widget.productModel, totalPrice);
      });
      return const SizedBox.shrink();
    }

    final bg = isDarkMode(context) ? AppThemeData.surfaceDark : Colors.white;
    final divColor = isDarkMode(context)
        ? AppThemeData.grey800
        : AppThemeData.grey100;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 0),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDarkMode(context)
                    ? AppThemeData.grey600
                    : AppThemeData.grey300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Header: product image + name + "Customize" ───────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: NetworkImageWidget(
                    imageUrl: widget.productModel.photo.toString(),
                    fit: BoxFit.cover,
                    height: 60,
                    width: 60,
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
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode(context)
                              ? AppThemeData.grey50
                              : AppThemeData.grey900,
                          fontFamily: AppThemeData.semiBold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "Customize your order".tr(),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDarkMode(context)
                              ? AppThemeData.grey400
                              : AppThemeData.grey600,
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
                      color: isDarkMode(context)
                          ? AppThemeData.grey800
                          : AppThemeData.grey100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: isDarkMode(context)
                          ? AppThemeData.grey300
                          : AppThemeData.grey700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Divider(height: 20, thickness: 1, color: divColor),

          // ── Scrollable content ────────────────────────────────
          // Selections are pre-initialized so content renders immediately.
          // Attribute display names update once Firebase responds (isLoading).
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasVariants) ..._buildVariantsSection(),
                  if (hasAddOns) ..._buildAddOnsSection(),
                ],
              ),
            ),
          ),

          // ── Footer: price + add button ────────────────────────
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
                  // Price info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Total".tr(),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDarkMode(context)
                                ? AppThemeData.grey400
                                : AppThemeData.grey600,
                            fontFamily: AppThemeData.regular,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          amountShow(amount: totalPrice.toString()),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppThemeData.primary500,
                            fontFamily: AppThemeData.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Add Item button
                  ElevatedButton(
                    onPressed: _addToCart,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppThemeData.primary500,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 2,
                    ),
                    child: Text(
                      "Add Item".tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
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

  List<Widget> _buildVariantsSection() {
    return [
      _sectionHeader("Choose Options".tr()),
      const SizedBox(height: 10),
      ...widget.productModel.itemAttributes!.attributes!
          .asMap()
          .entries
          .map((entry) {
        int attributeIndex = entry.key;
        Attributes attribute = entry.value;

        String attributeName = "Option ${attributeIndex + 1}";
        try {
          AttributesModel? found = attributesList.isNotEmpty
              ? attributesList.firstWhere(
                  (a) => a.id == attribute.attributesId,
                  orElse: () => AttributesModel(
                      id: attribute.attributesId, title: attributeName),
                )
              : null;
          if (found?.title?.isNotEmpty == true) attributeName = found!.title!;
        } catch (_) {}

        // Skip attributes with no options instead of crashing on null/empty
        final options = attribute.attributeOptions;
        if (options == null || options.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(
              color: isDarkMode(context)
                  ? AppThemeData.grey700
                  : AppThemeData.grey200,
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
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDarkMode(context)
                          ? AppThemeData.grey100
                          : AppThemeData.grey800,
                      fontFamily: AppThemeData.semiBold,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppThemeData.primary500.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      "Required".tr(),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppThemeData.primary500,
                        fontFamily: AppThemeData.medium,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: options
                    .asMap()
                    .entries
                    .map((optionEntry) {
                  int optionIndex = optionEntry.key;
                  String option = optionEntry.value.toString();
                  bool isSelected =
                      selectedVariants.length > attributeIndex &&
                          selectedVariants[attributeIndex] == option;
                  final bool isAvailable =
                      _isOptionAvailable(attributeIndex, option);
                  final bool dark = isDarkMode(context);

                  return GestureDetector(
                    onTap: isAvailable
                        ? () => _selectVariantOption(
                            attributeIndex, option, optionIndex)
                        : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: !isAvailable
                            ? (dark
                                ? AppThemeData.grey900
                                : AppThemeData.grey100)
                            : (isSelected
                                ? AppThemeData.primary500
                                : (dark
                                    ? AppThemeData.grey800
                                    : AppThemeData.grey50)),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: !isAvailable
                              ? (dark
                                  ? AppThemeData.grey800
                                  : AppThemeData.grey200)
                              : (isSelected
                                  ? AppThemeData.primary500
                                  : (dark
                                      ? AppThemeData.grey700
                                      : AppThemeData.grey300)),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            option,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: !isAvailable
                                  ? (dark
                                      ? AppThemeData.grey600
                                      : AppThemeData.grey400)
                                  : (isSelected
                                      ? Colors.white
                                      : (dark
                                          ? AppThemeData.grey200
                                          : AppThemeData.grey800)),
                              fontFamily: AppThemeData.medium,
                              decoration: !isAvailable
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: dark
                                  ? AppThemeData.grey600
                                  : AppThemeData.grey400,
                            ),
                          ),
                          if (!isAvailable) ...[
                            const SizedBox(height: 2),
                            Text(
                              "Sold out",
                              style: TextStyle(
                                fontSize: 9,
                                fontFamily: AppThemeData.regular,
                                color: dark
                                    ? AppThemeData.grey600
                                    : AppThemeData.grey400,
                              ),
                            ),
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

  List<Widget> _buildAddOnsSection() {
    return [
      _sectionHeader("Add-ons".tr()),
      const SizedBox(height: 10),
      ...widget.productModel.addOnsTitle.asMap().entries.map((entry) {
        int index = entry.key;
        String title = entry.value.toString();
        // Guard against price list being shorter than title list
        if (index >= widget.productModel.addOnsPrice.length ||
            index >= selectedAddOns.length) {
          return const SizedBox.shrink();
        }
        String price = widget.productModel.addOnsPrice[index].toString();
        bool isSelected = selectedAddOns[index] > 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppThemeData.primary500.withOpacity(0.05)
                : (isDarkMode(context)
                    ? AppThemeData.grey800.withOpacity(0.5)
                    : AppThemeData.grey50),
            border: Border.all(
              color: isSelected
                  ? AppThemeData.primary500.withOpacity(0.4)
                  : (isDarkMode(context)
                      ? AppThemeData.grey700
                      : AppThemeData.grey200),
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
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode(context)
                            ? AppThemeData.grey100
                            : AppThemeData.grey800,
                        fontFamily: AppThemeData.medium,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "+ ${amountShow(amount: productCommissionPrice(price))}",
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppThemeData.primary500,
                        fontFamily: AppThemeData.medium,
                      ),
                    ),
                  ],
                ),
              ),
              // Qty stepper
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isSelected
                        ? AppThemeData.primary500
                        : (isDarkMode(context)
                            ? AppThemeData.grey700
                            : AppThemeData.grey300),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: selectedAddOns[index] > 0
                          ? () => _updateAddOnQuantity(index, -1)
                          : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppThemeData.primary500
                              : (isDarkMode(context)
                                  ? AppThemeData.grey700
                                  : AppThemeData.grey200),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6),
                            bottomLeft: Radius.circular(6),
                          ),
                        ),
                        child: Icon(
                          Icons.remove,
                          size: 14,
                          color: isSelected
                              ? Colors.white
                              : (isDarkMode(context)
                                  ? AppThemeData.grey500
                                  : AppThemeData.grey500),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      height: 30,
                      child: Center(
                        child: Text(
                          selectedAddOns[index].toString(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode(context)
                                ? AppThemeData.grey100
                                : AppThemeData.grey900,
                            fontFamily: AppThemeData.semiBold,
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _updateAddOnQuantity(index, 1),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                          color: AppThemeData.primary500,
                          borderRadius: BorderRadius.only(
                            topRight: Radius.circular(6),
                            bottomRight: Radius.circular(6),
                          ),
                        ),
                        child: const Icon(Icons.add,
                            size: 14, color: Colors.white),
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
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppThemeData.primary500,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: isDarkMode(context)
                ? AppThemeData.grey50
                : AppThemeData.grey900,
            fontFamily: AppThemeData.semiBold,
          ),
        ),
      ],
    );
  }
}
