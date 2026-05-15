import 'dart:convert';

class VariantInfo {
  String? variant_id;
  String? variant_price;
  String? variant_sku;
  String? variant_image;
  Map<String, dynamic>? variant_options;

  VariantInfo(
      {this.variant_id,
      this.variant_price,
      this.variant_image,
      this.variant_sku,
      this.variant_options});

  VariantInfo.fromJson(Map<String, dynamic> json) {
    variant_id = json['variant_id'] ?? '';
    variant_price = json['variant_price'] ?? '';
    variant_sku = json['variant_sku'] ?? '';
    variant_image = json['variant_image'] ?? '';
    // variant_options may arrive as a Map or as a JSON-encoded String
    final rawOpts = json['variant_options'];
    if (rawOpts is Map<String, dynamic>) {
      variant_options = rawOpts;
    } else if (rawOpts is String && rawOpts.isNotEmpty && rawOpts != 'null') {
      try {
        final decoded = jsonDecode(rawOpts);
        variant_options =
            decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      } catch (_) {
        variant_options = <String, dynamic>{};
      }
    } else {
      variant_options = <String, dynamic>{};
    }
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['variant_id'] = variant_id;
    data['variant_price'] = variant_price;
    data['variant_sku'] = variant_sku;
    data['variant_image'] = variant_image;
    data['variant_options'] = variant_options;
    return data;
  }
}
