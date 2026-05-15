class TaxModel {
  String? country;
  bool? enable;
  String? tax;
  String? id;
  String? type;
  String? title;
  String? sectionId;
  bool? isTakeaway; // New field to determine if tax applies to takeaway orders

  TaxModel(
      {this.country,
      this.enable,
      this.tax,
      this.id,
      this.type,
      this.title,
      this.sectionId,
      this.isTakeaway});

  TaxModel.fromJson(Map<String, dynamic> json) {
    country = json['country'];
    enable = json['enable'];
    tax = json['tax'];
    id = json['id'];
    type = json['type'];
    title = json['title'];
    sectionId = json['sectionId'];
    isTakeaway =
        json['isTakeaway'] ?? false; // Default to false if not specified
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['country'] = country;
    data['enable'] = enable;
    data['tax'] = tax;
    data['id'] = id;
    data['type'] = type;
    data['title'] = title;
    data['sectionId'] = sectionId;
    data['isTakeaway'] = isTakeaway;

    return data;
  }
}
