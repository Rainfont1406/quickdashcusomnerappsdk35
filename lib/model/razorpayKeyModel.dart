class RazorPayModel {
  String razorpayKey;
  String razorpaySecret;
  bool isEnabled;
  bool isSandboxEnabled;

  RazorPayModel({
    this.razorpayKey = '',
    this.razorpaySecret = '',
    required this.isEnabled,
    required this.isSandboxEnabled,
  });

  factory RazorPayModel.fromJson(Map<String, dynamic> parsedJson) {
    return RazorPayModel(
      razorpayKey: parsedJson['razorpayKey'] ?? '',
      razorpaySecret: parsedJson['razorpaySecret'] ?? '',
      isSandboxEnabled: parsedJson['isSandboxEnabled'] ?? false,
      isEnabled: parsedJson['isEnabled'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'razorpayKey': razorpayKey,
      'razorpaySecret': razorpaySecret,
      'isEnabled': isEnabled,
      'isSandboxEnabled': isSandboxEnabled,
    };
  }
}
