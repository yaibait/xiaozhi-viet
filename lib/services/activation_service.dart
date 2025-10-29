import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import '../models/config.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class ActivationResponse {
  final bool needsActivation;
  final String? verificationCode;
  final String? message;
  final String? challenge;
  final String? latestVersion;

  ActivationResponse({
    required this.needsActivation,
    this.verificationCode,
    this.message,
    this.challenge,
    this.latestVersion,
  });

  factory ActivationResponse.fromJson(Map<String, dynamic> json) {
    final activation = json['activation'];

    return ActivationResponse(
      needsActivation: activation != null,
      verificationCode: activation?['code'], // SERVER generate code!
      message: activation?['message'],
      challenge: activation?['challenge'],
      latestVersion: json['latest_version'],
    );
  }
}

class ActivationService {
  final Logger _logger = Logger();
  final XiaozhiConfig config;

  // Device fingerprint - Serial number và HMAC key
  // String? _serialNumber;
  // String? _hmacKey;
  bool _isActivated = false;

  // Activation state
  String? _currentChallenge;
  String? _currentCode;

  ActivationService(this.config) {
    // _ensureDeviceIdentity();
  }

  /// Đảm bảo device có serial number và HMAC key
  // void _ensureDeviceIdentity() {
  //   // Generate serial number nếu chưa có (trong thực tế nên lưu vào SharedPreferences)
  //   _serialNumber = _generateSerialNumber();
  //   _hmacKey = _generateHmacKey();

  //   _logger.i('📱 Serial Number: $_serialNumber');
  //   _logger.d('🔐 HMAC Key: $_hmacKey');
  // }

  // String _generateSerialNumber() {
  //   // Format: FLUTTER-XXXXXX (6 chữ số)
  //   final random = Random();
  //   final number = random.nextInt(900000) + 100000;
  //   return 'FLUTTER-$number';
  // }

  // String _generateHmacKey() {
  //   // Generate random 32-byte key
  //   final random = Random.secure();
  //   final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  //   return base64Encode(bytes);
  // }

  // ActivationService(this.config);
  /// Tính HMAC signature từ challenge
  String _generateHmacSignature(String challenge) {
    if (config.hmacKey == "") {
      throw Exception('HMAC key not initialized');
    }

    // Decode HMAC key từ base64
    final keyBytes = base64Decode(config.hmacKey);

    // Tạo HMAC-SHA256
    final hmac = Hmac(sha256, keyBytes);
    final digest = hmac.convert(utf8.encode(challenge));

    // Return hex string
    return digest.toString();
  }

  /// Gửi OTA request để:
  /// 1. Đăng ký device lần đầu (server sẽ generate verification code)
  /// 2. Kiểm tra activation status
  Future<ActivationResponse> checkOtaStatus() async {
    try {
      _logger.i('Gửi OTA request...');
      final headers = {
        'Activation-Version': '2.0.0',
        'User-Agent': 'bread-compact-wifi/bi-xiaozhi-2.0.0',
        'Device-Id': config.deviceId,
        'Client-Id': config.clientId,
        'Content-Type': 'application/json',
      };
      String activeUrl = config.otaVersionUrl;
      final response = await http.post(
        Uri.parse(activeUrl),
        headers: headers,
        body: jsonEncode(config.toOtaJson()),
      );

      _logger.i('OTA Response status: ${response.statusCode}');
      _logger.d('OTA Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final activationResponse = ActivationResponse.fromJson(data);

        if (activationResponse.needsActivation) {
          // Lưu lại challenge và code để dùng cho activate()
          _currentChallenge = activationResponse.challenge;
          _currentCode = activationResponse.verificationCode;

          _logger.w('⚠️ Device cần activation!');
          _logger.i(
            '🔑 Verification Code: ${activationResponse.verificationCode}',
          );
          _logger.i('🔐 Challenge: ${activationResponse.challenge}');
          _logger.i('💬 Message: ${activationResponse.message}');
        } else {
          _logger.i('✅ Device đã được activate!');
          _isActivated = true;
          // mqtt();
        }

        return activationResponse;
      } else {
        throw Exception('OTA request failed: ${response.statusCode}');
      }
    } catch (e) {
      _logger.e('❌ Lỗi khi gửi OTA request: $e');
      rethrow;
    }
  }

  Future<void> mqtt() async {
    // Thông tin cấu hình từ JSON
    const endpoint = 'mqtt.xiaozhi.me';
    const clientId =
        'GID_test@@@4A_B1_61_93_68_26@@@8fb005c7-3913-4c60-a05e-7ab2b5ae60de';
    const username = 'eyJpcCI6IjEuNTMuOTIuMTQzIn0=';
    const password = 'cB/gOd5L/5N3sNdk9811GYU9NEBTIeXtepMw8eMsXAE=';
    const publishTopic = 'device-server';
    const subscribeTopic = 'null'; // Có thể bỏ qua nếu thực sự là null

    // Tạo client
    final client = MqttServerClient(endpoint, clientId);
    client.port =
        1883; // Nếu server không dùng TLS. Nếu có TLS thì đổi thành 8883
    client.secure = false; // true nếu server yêu cầu SSL
    client.keepAlivePeriod = 30;
    client.logging(on: true);

    // Cấu hình callback
    client.onConnected = () => print('✅ Kết nối MQTT thành công');
    client.onDisconnected = () => print('❌ Mất kết nối MQTT');
    client.onSubscribed = (topic) => print('📡 Đã subscribe: $topic');
    client.onUnsubscribed = (topic) => print('🚫 Đã unsubscribe: $topic');
    client.onSubscribeFail = (topic) => print('⚠️ Subscribe thất bại: $topic');
    client.pongCallback = () => print('🏓 Ping response');
    // client.securityContext = SecurityContext.defaultContext;
    // Cấu hình kết nối
    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs(username, password)
        .startClean()
        .withWillQos(MqttQos.atMostOnce);
    client.connectionMessage = connMess;

    try {
      print('🔌 Đang kết nối tới $endpoint ...');
      await client.connect();
    } on Exception catch (e) {
      print('❌ Lỗi kết nối: $e');
      client.disconnect();
      return;
    }

    // Kiểm tra trạng thái
    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      print('🎯 MQTT đã kết nối với broker $endpoint');
    } else {
      print('⚠️ Không thể kết nối MQTT: ${client.connectionStatus}');
      client.disconnect();
      return;
    }

    // Đăng ký nhận topic (nếu có)
    if (subscribeTopic != 'null') {
      client.subscribe(subscribeTopic, MqttQos.atMostOnce);
    }

    // Lắng nghe message đến
    client.updates?.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final recMess = c[0].payload as MqttPublishMessage;
      final pt = MqttPublishPayload.bytesToStringAsString(
        recMess.payload.message,
      );
      print('📩 Nhận message từ topic: ${c[0].topic} => $pt');
    });

    // Gửi thử 1 message
    final builder = MqttClientPayloadBuilder();
    builder.addString('Hello from Flutter!');
    client.publishMessage(publishTopic, MqttQos.atMostOnce, builder.payload!);

    // (Tuỳ chọn) giữ kết nối trong 30 giây rồi ngắt
    await Future.delayed(Duration(seconds: 30));
    client.disconnect();
    print('🔚 Ngắt kết nối');
  }

  /// Bước 2: Gửi activation request với HMAC signature
  /// Retry cho đến khi user nhập code trên web hoặc timeout
  Future<bool> activate({
    Duration maxWaitTime = const Duration(minutes: 5),
    Duration retryInterval = const Duration(seconds: 5),
  }) async {
    if (_currentChallenge == null || config.serialNumber == "") {
      _logger.e('❌ Thiếu challenge hoặc serial number để activate');
      return false;
    }

    try {
      // Tính HMAC signature
      final hmacSignature = _generateHmacSignature(_currentChallenge!);
      _logger.i('🔐 Generated HMAC: $hmacSignature');

      // Chuẩn bị payload theo format của server
      // final payload = {
      //   'Payload': {
      //     'algorithm': 'hmac-sha256',
      //     'serial_number': config.serialNumber,
      //     'challenge': _currentChallenge,
      //     'hmac': hmacSignature,
      //   },
      // };
      final payload = {
        'application': {'version': '2.0.0', 'elf_sha256': hmacSignature},
        'board': {
          'type': 'bread-compact-wifi',
          'name': 'bi-xiaozhi',
          'mac': config.deviceId,
        },
      };
      // Activation URL
      final activateUrl = config.otaVersionUrl.endsWith('/')
          ? '${config.otaVersionUrl}activate'
          : '${config.otaVersionUrl}/activate';

      _logger.i('📍 Activation URL: $activateUrl');

      // Headers
      final headers = {
        'Activation-Version': '2.0.0',
        'User-Agent': 'bread-compact-wifi/bi-xiaozhi-2.0.0',
        'Device-Id': config.deviceId,
        'Client-Id': config.clientId,
        'Content-Type': 'application/json',
      };

      _logger.d('📤 Activation payload: ${jsonEncode(payload)}');

      // Retry loop
      final maxRetries = (maxWaitTime.inSeconds / retryInterval.inSeconds)
          .ceil();
      var errorCount = 0;
      String? lastError;

      for (var attempt = 0; attempt < maxRetries; attempt++) {
        try {
          _logger.i('🔄 Thử activate (lần ${attempt + 1}/$maxRetries)...');

          // Gửi activation request
          final response = await http
              .post(
                Uri.parse(activateUrl),
                headers: headers,
                body: jsonEncode(payload),
              )
              .timeout(Duration(seconds: 10));

          _logger.i('📥 Response status: ${response.statusCode}');
          _logger.d('📥 Response body: ${response.body}');

          if (response.statusCode == 200) {
            // ✅ Activation thành công!
            _logger.i('✅ Device đã được activate thành công!');
            _isActivated = true;
            return true;
          } else if (response.statusCode == 202) {
            // ⏳ Đang chờ user nhập code trên web
            _logger.i('⏳ Đang chờ user nhập verification code...');

            // Hiển thị lại code sau mỗi vài lần retry
            if (attempt > 0 && attempt % 3 == 0 && _currentCode != null) {
              _logger.i('🔑 Verification Code: $_currentCode');
            }

            await Future.delayed(retryInterval);
          } else {
            // ❌ Lỗi khác
            String errorMsg = 'Unknown error';

            try {
              final errorData = jsonDecode(response.body);
              errorMsg =
                  errorData['error'] ??
                  'Unknown error (Status: ${response.statusCode})';
            } catch (_) {
              errorMsg = 'Server error (Status: ${response.statusCode})';
            }

            // Log lỗi nhưng vẫn tiếp tục retry
            if (errorMsg != lastError) {
              _logger.w('⚠️ Server response: $errorMsg');
              _logger.w('⏳ Tiếp tục chờ activation...');
              lastError = errorMsg;
            }

            // Đếm lỗi "Device not found"
            if (errorMsg.contains('Device not found')) {
              errorCount++;
              if (errorCount >= 5 && errorCount % 5 == 0) {
                _logger.w(
                  '\n💡 Tip: Nếu lỗi vẫn tiếp diễn, hãy thử refresh trang web và lấy code mới\n',
                );
              }
            }

            await Future.delayed(retryInterval);
          }
        } catch (e) {
          _logger.w('⚠️ Request error: $e, đang retry...');
          await Future.delayed(retryInterval);
        }
      }

      // Timeout - hết số lần retry
      _logger.e('❌ Activation timeout sau $maxRetries lần thử');
      _logger.e('❌ Last error: $lastError');
      return false;
    } catch (e) {
      _logger.e('❌ Activation error: $e');
      return false;
    }
  }

  /// Polling wrapper - kết hợp checkOtaStatus + activate
  Future<bool> processActivation({
    Duration maxWaitTime = const Duration(minutes: 5),
    Duration retryInterval = const Duration(seconds: 5),
  }) async {
    try {
      // Bước 1: Check OTA status để lấy code + challenge
      final otaResponse = await checkOtaStatus();

      if (!otaResponse.needsActivation) {
        // Đã activate rồi
        return true;
      }

      if (otaResponse.verificationCode == null ||
          otaResponse.challenge == null) {
        _logger.e('❌ OTA response thiếu verification code hoặc challenge');
        return false;
      }

      // Bước 2: Activate với HMAC signature
      return await activate(
        maxWaitTime: maxWaitTime,
        retryInterval: retryInterval,
      );
    } catch (e) {
      _logger.e('❌ Process activation error: $e');
      return false;
    }
  }

  // Getters
  bool get isActivated => _isActivated;
  String? get currentChallenge => _currentChallenge;
  String? get currentCode => _currentCode;

  // Setters
  void setActivated(bool status) {
    _isActivated = status;
  }
}
