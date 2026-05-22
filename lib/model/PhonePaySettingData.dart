class PhonePaySettingData {
  bool isEnabled;
  bool isSandbox;
  String merchantId;
  String saltKey;
  int saltIndex;
  String redirectUrl;
  String callbackUrl;

  PhonePaySettingData({
    this.isEnabled = false,
    this.isSandbox = true,
    this.merchantId = '',
    this.saltKey = '',
    this.saltIndex = 1,
    this.redirectUrl = '',
    this.callbackUrl = '',
  });

  factory PhonePaySettingData.fromJson(Map<String, dynamic> json) {
    return PhonePaySettingData(
      isEnabled: json['isEnabled'] ?? false,
      isSandbox: json['isSandbox'] ?? true,
      merchantId: json['merchantId'] ?? '',
      saltKey: json['saltKey'] ?? '',
      saltIndex: json['saltIndex'] ?? 1,
      redirectUrl: json['redirectUrl'] ?? '',
      callbackUrl: json['callbackUrl'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isEnabled': isEnabled,
      'isSandbox': isSandbox,
      'merchantId': merchantId,
      'saltKey': saltKey,
      'saltIndex': saltIndex,
      'redirectUrl': redirectUrl,
      'callbackUrl': callbackUrl,
    };
  }
}
