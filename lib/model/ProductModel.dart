import 'dart:convert';

import 'package:emartconsumer/model/ItemAttributes.dart';
import 'package:emartconsumer/model/NutritionInfo.dart';
import 'package:emartconsumer/model/ProductAttributeConfig.dart';
import 'package:emartconsumer/model/variant_info.dart';

class ProductModel {
  String categoryID;
  String brandID;
  String description;
  String id;
  String photo;
  List<dynamic> photos;
  String price;
  String name;
  String vendorID;
  String section_id;
  int quantity;
  bool publish;
  int calories;
  int grams;
  int proteins;
  int fats;
  bool veg;
  bool nonveg;
  String? disPrice = "0";
  bool dineAway;       // combined flag: product is available in DineAway service
  bool deliveryOption;
  bool dineIn;         // DineAway sub-option: dine-in
  bool takeaway;       // DineAway sub-option: takeaway
  List<dynamic> addOnsTitle = [];
  List<dynamic> addOnsPrice = [];
  String? addon_name;
  String? addon_price;
  ItemAttributes? itemAttributes;
  Map<String, dynamic>? reviewAttributes;
  Map<String, dynamic> specification = {};
  num reviewsCount;
  num reviewsSum;
  VariantInfo? variant_info;
  bool? isDigitalProduct;
  String? digitalProduct;
  List<ProductAttributeConfig> productAttributes;
  bool nutritionEnabled;
  NutritionInfo? nutritionInfo;

  ProductModel({
    this.categoryID = '',
    this.brandID = '',
    this.description = '',
    this.id = '',
    this.photo = '',
    this.photos = const [],
    this.price = '',
    this.name = '',
    this.quantity = 0,
    this.vendorID = '',
    this.section_id = '',
    this.calories = 0,
    this.grams = 0,
    this.proteins = 0,
    this.fats = 0,
    this.publish = true,
    this.veg = false,
    this.nonveg = false,
    this.addon_name,
    this.addon_price,
    this.disPrice,
    this.dineAway = false,
    this.deliveryOption = false,
    this.dineIn = false,
    this.takeaway = false,
    this.reviewsCount = 0,
    this.reviewsSum = 0,
    this.addOnsPrice = const [],
    this.addOnsTitle = const [],
    this.itemAttributes,
    this.variant_info,
    this.specification = const {},
    this.reviewAttributes,
    this.isDigitalProduct,
    this.digitalProduct,
    this.productAttributes = const [],
    this.nutritionEnabled = false,
    this.nutritionInfo,
  });

  factory ProductModel.fromJson(Map<String, dynamic> parsedJson) {
    return ProductModel(
      categoryID: parsedJson['categoryID'] ?? '',
      brandID: parsedJson['brandID'] ?? '',
      description: parsedJson['description'] ?? '',
      id: parsedJson['id'] ?? '',
      photo: parsedJson['photo'],
      photos: parsedJson['photos'] ?? [],
      price: parsedJson['price'] ?? '',
      quantity: parsedJson['quantity'] ?? 0,
      name: parsedJson['name'] ?? '',
      vendorID: parsedJson['vendorID'] ?? '',
      section_id: parsedJson['section_id'] ?? '',
      publish: parsedJson['publish'] ?? true,
      calories: parsedJson['calories'] ?? 0,
      grams: parsedJson['grams'] ?? 0,
      proteins: parsedJson['proteins'] ?? 0,
      fats: parsedJson['fats'] ?? 0,
      nonveg: parsedJson['nonveg'] ?? false,
      disPrice: parsedJson['disPrice'] ?? '0',
      specification: (() {
        final raw = parsedJson['product_specification'];
        if (raw == null) return <String, dynamic>{};
        if (raw is Map<String, dynamic>) return raw;
        if (raw is String && raw.isNotEmpty && raw != 'null') {
          try { return jsonDecode(raw) as Map<String, dynamic>; } catch (_) {}
        }
        return <String, dynamic>{};
      })(),
      // dineAway: true if product supports any DineAway mode (takeaway or dine-in)
      dineAway: (() {
        final dineAwayMap = parsedJson['DineAway'] as Map<String, dynamic>?;
        if (dineAwayMap != null) {
          return (dineAwayMap['takeaway'] as bool? ?? false) ||
                 (dineAwayMap['dineIn'] as bool? ?? false);
        }
        return parsedJson['takeawayOption'] as bool? ?? false;
      })(),
      deliveryOption: parsedJson['deliveryOption'] ?? false,
      // dineIn: DineAway.dineIn sub-option
      dineIn: (() {
        final dineAwayMap = parsedJson['DineAway'] as Map<String, dynamic>?;
        if (dineAwayMap != null) return dineAwayMap['dineIn'] as bool? ?? false;
        return parsedJson['dineIn'] as bool? ?? false;
      })(),
      // takeaway: DineAway.takeaway sub-option
      takeaway: (() {
        final dineAwayMap = parsedJson['DineAway'] as Map<String, dynamic>?;
        if (dineAwayMap != null) return dineAwayMap['takeaway'] as bool? ?? false;
        final stored = parsedJson['dineAwayTakeaway'] as bool?;
        if (stored != null) return stored;
        return parsedJson['takeawayOption'] as bool? ?? false;
      })(),
      addOnsPrice: parsedJson['addOnsPrice'] ?? [],
      addOnsTitle: parsedJson['addOnsTitle'] ?? [],
      reviewsCount: parsedJson['reviewsCount'] ?? 0,
      reviewsSum: parsedJson['reviewsSum'] ?? 0,
      variant_info: (parsedJson.containsKey('variant_info') &&
              parsedJson['variant_info'] != null)
          ? parsedJson['variant_info'].runtimeType.toString() ==
                  '_InternalLinkedHashMap<String, dynamic>'
              ? VariantInfo.fromJson(parsedJson['variant_info'])
              : null
          : null,
      reviewAttributes: (() {
        final raw = parsedJson['reviewAttributes'];
        if (raw == null) return <String, dynamic>{};
        if (raw is Map<String, dynamic>) return raw;
        if (raw is String && raw.isNotEmpty && raw != 'null') {
          try { return jsonDecode(raw) as Map<String, dynamic>; } catch (_) {}
        }
        return <String, dynamic>{};
      })(),
      addon_name: parsedJson["addon_name"] ?? "",
      addon_price: parsedJson["addon_price"] ?? "",
      veg: parsedJson['veg'] ?? false,
      itemAttributes: (() {
        final raw = parsedJson['item_attribute'];
        if (raw == null) return null;
        try {
          if (raw is Map<String, dynamic>) return ItemAttributes.fromJson(raw);
          if (raw is String && raw.isNotEmpty && raw != 'null') {
            return ItemAttributes.fromJson(
                jsonDecode(raw) as Map<String, dynamic>);
          }
        } catch (_) {}
        return null;
      })(),
      isDigitalProduct: parsedJson['isDigitalProduct'] ?? false,
      digitalProduct: parsedJson['digitalProduct'] ?? "",
      productAttributes: (() {
        final raw = parsedJson['product_attributes'];
        if (raw == null) return <ProductAttributeConfig>[];
        try {
          if (raw is List) {
            return raw.map((e) => ProductAttributeConfig.fromJson(e as Map<String, dynamic>)).toList();
          }
          if (raw is String && raw.isNotEmpty && raw != 'null') {
            return ProductAttributeConfig.listFromJson(raw);
          }
        } catch (_) {}
        return <ProductAttributeConfig>[];
      })(),
      nutritionEnabled: parsedJson['nutrition_enabled'] ?? false,
      nutritionInfo: (() {
        final raw = parsedJson['nutrition_info'];
        if (raw == null) return null;
        try {
          if (raw is Map<String, dynamic>) return NutritionInfo.fromJson(raw);
        } catch (_) {}
        return null;
      })(),
    );
  }

  Map<String, dynamic> toJson() {
    photos.toList().removeWhere((element) => element == null);
    return {
      'categoryID': categoryID,
      'brandID': brandID,
      'description': description,
      'id': id,
      'photo': photo,
      'photos': photos,
      'price': price,
      'name': name,
      'quantity': quantity,
      'vendorID': vendorID,
      'section_id': section_id,
      'publish': publish,
      'calories': calories,
      'grams': grams,
      'proteins': proteins,
      'fats': fats,
      'veg': veg,
      'nonveg': nonveg,
      'DineAway': {
        'takeaway': takeaway,
        'dineIn': dineIn,
      },
      'deliveryOption': deliveryOption,
      'disPrice': disPrice,
      "addOnsTitle": addOnsTitle,
      "addOnsPrice": addOnsPrice,
      "addon_name": addon_name,
      "addon_price": addon_price,
      'item_attribute':
          itemAttributes == null ? null : itemAttributes!.toJson(),
      'product_specification': specification,
      'reviewAttributes': reviewAttributes,
      'reviewsCount': reviewsCount,
      'reviewsSum': reviewsSum,
      'isDigitalProduct': isDigitalProduct,
      'digitalProduct': digitalProduct,
      'product_attributes': productAttributes.map((e) => e.toJson()).toList(),
      'nutrition_enabled': nutritionEnabled,
      'nutrition_info': nutritionInfo?.toJson(),
    };
  }
}

class ReviewsAttribute {
  num? reviewsCount;
  num? reviewsSum;

  ReviewsAttribute({
    this.reviewsCount,
    this.reviewsSum,
  });

  ReviewsAttribute.fromJson(Map<String, dynamic> json) {
    reviewsCount = json['reviewsCount'] ?? 0;
    reviewsSum = json['reviewsSum'] ?? 0;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['reviewsCount'] = reviewsCount;
    data['reviewsSum'] = reviewsSum;
    return data;
  }
}
