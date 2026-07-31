// One line item inside a combo product - a reference to an existing, real
// menu product plus how many of it the combo includes. Deliberately just an
// id + quantity, not a duplicated copy of that product's own fields (name,
// price, images, ...) - those continue to live only on the referenced
// product itself, per the combo architecture decision (single Add Product
// flow, no duplicated product logic). Mirrors vendorWeb's ComboProductItem -
// both apps read/write the same Firestore shape.
class ComboProductItem {
  final String productId;
  final int quantity;

  const ComboProductItem({
    required this.productId,
    this.quantity = 1,
  });

  factory ComboProductItem.fromJson(Map<String, dynamic> json) => ComboProductItem(
        productId: json['productId'] ?? '',
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      );

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'quantity': quantity,
      };

  ComboProductItem copyWith({String? productId, int? quantity}) => ComboProductItem(
        productId: productId ?? this.productId,
        quantity: quantity ?? this.quantity,
      );
}
