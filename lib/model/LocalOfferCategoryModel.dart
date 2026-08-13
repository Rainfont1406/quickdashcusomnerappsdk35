// Admin-managed category chip for the Offers & Discounts section
// (2026-08-03) - deliberately Firestore-driven, not a hardcoded list, so
// admin can add/retire a vertical (e.g. "Travel") without an app update -
// see local_offer_categories collection.
class LocalOfferCategoryModel {
  String? id;
  String? name;
  String? iconUrl;
  num? sortOrder;
  bool? isActive;

  LocalOfferCategoryModel({this.id, this.name, this.iconUrl, this.sortOrder, this.isActive});

  LocalOfferCategoryModel.fromJson(Map<String, dynamic> json) {
    id = json['id'] ?? '';
    name = json['name'] ?? '';
    iconUrl = json['iconUrl'] ?? '';
    sortOrder = json['sortOrder'] ?? 0;
    isActive = json['isActive'] ?? true;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['name'] = name;
    data['iconUrl'] = iconUrl;
    data['sortOrder'] = sortOrder;
    data['isActive'] = isActive;
    return data;
  }
}
