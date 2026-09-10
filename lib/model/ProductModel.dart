import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emartconsumer/model/ComboProductItem.dart';
import 'package:emartconsumer/model/ItemAttributes.dart';
import 'package:emartconsumer/model/NutritionInfo.dart';
import 'package:emartconsumer/model/ProductAttributeConfig.dart';
import 'package:emartconsumer/model/variant_info.dart';

class ProductModel {
  String categoryID;
  String brandID;
  String description;
  String id;
  String photo; // 16:9 cover image (1600x900)
  String photoOriginal; // unmodified master asset, as uploaded by the vendor
  List<dynamic> photos;
  String price;
  String name;
  String vendorID;
  String section_id;
  int quantity;
  bool publish;
  // calories/proteins/fats removed (2026-09-06) - exact duplicates of
  // nutrition_info.calories/.protein/.fat, always written as 0 (the add/
  // edit product form never sets them; only nutrition_info's own richer
  // form does) and read nowhere except fully commented-out code in the
  // legacy ProductDetailsScreen. The live Nutrition Filter feature (see
  // newVendorProductsScreen.dart's classifyMetric calls) uses
  // nutritionInfo exclusively. grams kept - a real, distinct field (serving
  // size), not part of this duplication.
  int grams;
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
  String productStatus; // 'pending' | 'approved' | 'rejected'
  List<String> recommendedProductIds; // vendor-selected cross-sell picks, max 5, order preserved

  // Combo products - isCombo is the ONLY structural signal a combo should
  // ever be identified by anywhere in this app (never categoryID/category
  // name - category stays a normal, real, admin-managed category exactly
  // like any other product's). comboProducts references existing menu
  // products by id + quantity only; every other field (name, price, images,
  // variants, nutrition, ...) continues to belong solely to the combo
  // product itself, never duplicated from its children. Mirrors vendorWeb's
  // ProductModel - both apps read/write the same Firestore shape.
  bool isCombo;
  List<ComboProductItem> comboProducts;

  // Combo Category Intelligence (2026-07-25) - vendor-selected category IDs
  // a combo REPRESENTS for customer preference-matching purposes only (e.g.
  // a "Family Combo" containing Biryani+Nuggets+Burger+Cold Drink might be
  // tagged Biryani/Fast Food/Beverage). Deliberately separate from
  // categoryID (which stays isCombo's real, normal, admin-managed category
  // per that field's own doc comment above, never read for preference
  // matching) - this is the ONLY field RecommendationEngine reads to learn
  // "what categories does this combo represent". No vendor-facing UI writes
  // this yet (empty on every real combo today); RecommendationEngine falls
  // back to deriving it from comboProducts' own child categories when empty
  // - see RecommendationEngine._effectiveCategoryIds. Additive-only: absent
  // on every product created before this field existed, and that's a valid,
  // handled state, not an error.
  List<String> comboCategoryIds;

  // Nullable, never defaulted/backfilled - absent on every product created
  // before this field existed, and stays absent forever unless the vendor
  // app re-saves it (which it never does on plain edits, only on create -
  // see vendorApp/lib/services/FirebaseHelper.dart's addOrUpdateProduct).
  // RecommendationEngine's "new product" signal treats null as "no signal",
  // never fakes a value.
  Timestamp? createdAt;

  ProductModel({
    this.categoryID = '',
    this.brandID = '',
    this.description = '',
    this.id = '',
    this.photo = '',
    this.photoOriginal = '',
    this.photos = const [],
    this.price = '',
    this.name = '',
    this.quantity = 0,
    this.vendorID = '',
    this.section_id = '',
    this.grams = 0,
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
    this.productStatus = 'approved',
    this.recommendedProductIds = const [],
    this.isCombo = false,
    this.comboProducts = const [],
    this.comboCategoryIds = const [],
    this.createdAt,
  });

  factory ProductModel.fromJson(Map<String, dynamic> parsedJson) {
    return ProductModel(
      categoryID: parsedJson['categoryID'] ?? '',
      brandID: parsedJson['brandID'] ?? '',
      description: parsedJson['description'] ?? '',
      id: parsedJson['id'] ?? '',
      photo: parsedJson['photo'],
      photoOriginal: parsedJson['photoOriginal'] ?? parsedJson['photo'] ?? '',
      photos: parsedJson['photos'] ?? [],
      price: parsedJson['price'] ?? '',
      quantity: parsedJson['quantity'] ?? 0,
      name: parsedJson['name'] ?? '',
      vendorID: parsedJson['vendorID'] ?? '',
      section_id: parsedJson['section_id'] ?? '',
      publish: parsedJson['publish'] ?? true,
      grams: parsedJson['grams'] ?? 0,
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
      productStatus: parsedJson['product_status'] ?? 'approved',
      recommendedProductIds: (() {
        final raw = parsedJson['recommendedProductIds'];
        if (raw is List) return raw.map((e) => e.toString()).toList();
        return <String>[];
      })(),
      isCombo: parsedJson['isCombo'] ?? false,
      comboProducts: (() {
        final raw = parsedJson['comboProducts'];
        if (raw is List) {
          return raw
              .whereType<Map>()
              .map((e) => ComboProductItem.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
        return <ComboProductItem>[];
      })(),
      comboCategoryIds: (() {
        final raw = parsedJson['comboCategoryIds'];
        if (raw is List) return raw.map((e) => e.toString()).toList();
        return <String>[];
      })(),
      // No fallback on purpose - absent means null, never a fake/inferred
      // timestamp (see field doc comment above).
      createdAt: parsedJson['createdAt'] is Timestamp
          ? parsedJson['createdAt'] as Timestamp
          : null,
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
      'photoOriginal': photoOriginal,
      'photos': photos,
      'price': price,
      'name': name,
      'quantity': quantity,
      'vendorID': vendorID,
      'section_id': section_id,
      'publish': publish,
      'grams': grams,
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
      'product_status': productStatus,
      'recommendedProductIds': recommendedProductIds,
      'isCombo': isCombo,
      'comboProducts': comboProducts.map((e) => e.toJson()).toList(),
      'comboCategoryIds': comboCategoryIds,
      'createdAt': createdAt,
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
