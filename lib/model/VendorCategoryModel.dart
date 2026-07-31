class VendorCategoryModel {
  List<dynamic>? reviewAttributes;
  String? sectionId;
  String? photo;
  String? description;
  String? id;
  String? title;
  num? order;
  // Category-Based Pairing Configuration (2026-07-21) - admin-managed,
  // Pairs Well With ONLY. Which OTHER vendor_categories ids are allowed
  // candidates when a product from THIS category is added to cart. Empty/
  // missing means "not configured yet" - callers fall back to the existing
  // Business Context pairing signal for that category (see
  // newVendorProductsScreen.dart's _resolvedPairsWellWith), not to zero
  // recommendations - only an EXPLICITLY-configured-but-still-empty list
  // (which the admin UI doesn't allow to be saved as different from
  // "unconfigured" anyway) would ever mean "no pairing recs".
  List<String>? pairingCategoryIds;

  VendorCategoryModel(
      {this.reviewAttributes, this.sectionId, this.photo, this.description, this.id, this.title, this.order, this.pairingCategoryIds});

  VendorCategoryModel.fromJson(Map<String, dynamic> json) {
    reviewAttributes = json['review_attributes'] ?? [];
    sectionId = json['section_id'] ?? "";
    photo = json['photo'] ?? "";
    description = json['description'] ?? '';
    id = json['id'] ?? "";
    title = json['title'] ?? "";
    order = json['order'] ?? 0;
    pairingCategoryIds = (json['pairingCategoryIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['review_attributes'] = reviewAttributes;
    data['section_id'] = sectionId;
    data['photo'] = photo;
    data['description'] = description;
    data['id'] = id;
    data['title'] = title;
    data['order'] = order;
    data['pairingCategoryIds'] = pairingCategoryIds;
    return data;
  }
}
