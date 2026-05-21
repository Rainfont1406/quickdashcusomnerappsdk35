class AttributesModel {
  String? id;
  String? title;
  String? type; // "SS" = single select, "MS" = multi select
  List<GlobalAttributeOption> options;

  AttributesModel({this.id, this.title, this.type, this.options = const []});

  AttributesModel.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        title = json['title'],
        type = (json['type'] as String?)?.isNotEmpty == true ? json['type'] : 'SS',
        options = (json['options'] as List<dynamic>?)
                ?.map((e) => GlobalAttributeOption.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type ?? 'SS',
        'options': options.map((e) => e.toJson()).toList(),
      };
}

class GlobalAttributeOption {
  String id;
  String name;
  double price;

  GlobalAttributeOption({required this.id, required this.name, this.price = 0.0});

  GlobalAttributeOption.fromJson(Map<String, dynamic> json)
      : id = json['id']?.toString() ?? '',
        name = json['name']?.toString() ?? '',
        price = (json['price'] != null ? (json['price'] as num).toDouble() : 0.0);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'price': price};
}
