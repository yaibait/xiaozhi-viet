class XiaozhiConfig {
  final String deviceId;
  final String clientId;
  final String serialNumber;
  final String otaVersionUrl;
  final String wsUrl;
  final String firmwareVersion;
  final String model;
  final String hmacKey;
  XiaozhiConfig({
    required this.deviceId,
    required this.clientId,
    required this.serialNumber,
    required this.hmacKey,
    this.otaVersionUrl = 'https://api.tenclass.net/xiaozhi/ota/',
    this.wsUrl = 'wss://api.tenclass.net/xiaozhi/v1/',
    this.firmwareVersion = '1.0.0',
    this.model = 'flutter-client',
  });

  Map<String, dynamic> toOtaJson() {
    return {
      'device_id': deviceId,
      'client_id': clientId,
      'serial_number': serialNumber,
      'current_version': firmwareVersion,
      'hmac_key': hmacKey,
      'model': model,
      'chip': 'flutter',
      'features': ['voice', 'text'],
    };
  }
}
