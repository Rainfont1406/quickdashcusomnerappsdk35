import 'dart:convert';

class ProductAttributeConfig {
  final String attributeId;
  final String attributeTitle;
  final String type; // "SS" or "MS"
  final bool isRequired;
  final List<ProductAttributeOption> options;

  ProductAttributeConfig({
    required this.attributeId,
    required this.attributeTitle,
    this.type = 'SS',
    this.isRequired = false,
    this.options = const [],
  });

  factory ProductAttributeConfig.fromJson(Map<String, dynamic> json) =>
      ProductAttributeConfig(
        attributeId: json['attribute_id']?.toString() ?? '',
        attributeTitle: json['attribute_title']?.toString() ?? '',
        type: json['type']?.toString() ?? 'SS',
        isRequired: json['is_required'] ?? false,
        options: (json['options'] as List<dynamic>?)
                ?.map((e) => ProductAttributeOption.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'attribute_id': attributeId,
        'attribute_title': attributeTitle,
        'type': type,
        'is_required': isRequired,
        'options': options.map((e) => e.toJson()).toList(),
      };

  ProductAttributeConfig copyWith({List<ProductAttributeOption>? options}) =>
      ProductAttributeConfig(
        attributeId: attributeId,
        attributeTitle: attributeTitle,
        type: type,
        isRequired: isRequired,
        options: options ?? this.options,
      );

  static List<ProductAttributeConfig> listFromJson(dynamic raw) {
    if (raw == null) return [];
    try {
      List<dynamic> list = raw is String ? jsonDecode(raw) : raw as List<dynamic>;
      return list.map((e) => ProductAttributeConfig.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static String listToJson(List<ProductAttributeConfig> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());
}

class ProductAttributeOption {
  final String id;
  final String name;
  final double price;
  final bool enabled;

  ProductAttributeOption({
    required this.id,
    required this.name,
    this.price = 0.0,
    this.enabled = true,
  });

  factory ProductAttributeOption.fromJson(Map<String, dynamic> json) =>
      ProductAttributeOption(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        price: (json['price'] != null ? (json['price'] as num).toDouble() : 0.0),
        enabled: json['enabled'] ?? true,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'price': price, 'enabled': enabled};

  ProductAttributeOption copyWith({bool? enabled, double? price}) =>
      ProductAttributeOption(
        id: id,
        name: name,
        price: price ?? this.price,
        enabled: enabled ?? this.enabled,
      );
}
