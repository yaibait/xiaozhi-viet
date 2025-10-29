import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:logger/logger.dart';
import '../models/config.dart';

/// Listening modes
enum ListeningMode { realtime, autoStop, manual }

/// Abort reasons
enum AbortReason { wakeWordDetected, userInterrupted }

/// Connection state
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

/// WebSocket Protocol implementation
/// Port from Python websocket_protocol.py
class XiaozhiWebSocketService {
  final Logger _logger = Logger();
  final XiaozhiConfig config;

  // WebSocket connection
  WebSocketChannel? _channel;
  bool _connected = false;
  bool _isClosing = false;
  String? _sessionId;

  // Hello handshake
  Completer<bool>? _helloCompleter;

  // Callbacks
  Function(Map<String, dynamic>)? _onIncomingJson;
  Function(Uint8List)? _onIncomingAudio;
  Function()? _onAudioChannelOpened;
  Function()? _onAudioChannelClosed;
  Function(String)? _onNetworkError;
  Function(bool connected, String reason)? _onConnectionStateChanged;
  Function(int attempt, int maxAttempts)? _onReconnecting;

  // Heartbeat & monitoring
  Timer? _heartbeatTimer;
  Timer? _connectionMonitorTimer;
  DateTime? _lastPingTime;
  DateTime? _lastPongTime;
  final Duration _pingInterval = Duration(seconds: 30);
  final Duration _pingTimeout = Duration(seconds: 10);

  // Reconnection
  bool _autoReconnectEnabled = true;
  int _reconnectAttempts = 5;
  int _maxReconnectAttempts = 10;

  // Streams for TTS and ASR
  final StreamController<String> _ttsTextController =
      StreamController<String>.broadcast();
  final StreamController<String> _asrTextController =
      StreamController<String>.broadcast();
  final StreamController<ConnectionState> _connectionStateController =
      StreamController<ConnectionState>.broadcast();

  // Public streams
  Stream<String> get ttsTextStream => _ttsTextController.stream;
  Stream<String> get asrTextStream => _asrTextController.stream;
  Stream<ConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  // Getters
  bool get isConnected => _connected;
  String? get sessionId => _sessionId;
  ConnectionState get connectionState =>
      _connected ? ConnectionState.connected : ConnectionState.disconnected;

  XiaozhiWebSocketService(this.config);

  // ============================================================================
  // Callback setters
  // ============================================================================

  void onIncomingJson(Function(Map<String, dynamic>) callback) {
    _onIncomingJson = callback;
  }

  void onIncomingAudio(Function(Uint8List) callback) {
    _onIncomingAudio = callback;
  }

  void onAudioChannelOpened(Function() callback) {
    _onAudioChannelOpened = callback;
  }

  void onAudioChannelClosed(Function() callback) {
    _onAudioChannelClosed = callback;
  }

  void onNetworkError(Function(String) callback) {
    _onNetworkError = callback;
  }

  void onConnectionStateChanged(Function(bool, String) callback) {
    _onConnectionStateChanged = callback;
  }

  void onReconnecting(Function(int, int) callback) {
    _onReconnecting = callback;
  }

  // ============================================================================
  // Connection management
  // ============================================================================

  /// Connect to WebSocket server
  Future<bool> connect() async {
    if (_isClosing) {
      _logger.w('⚠️ Connection is closing, cancel new connection attempt');
      return false;
    }

    try {
      _connectionStateController.add(ConnectionState.connecting);

      // Create hello completer
      _helloCompleter = Completer<bool>();

      // Build WebSocket URL
      final uri = Uri.parse(config.wsUrl);

      // Build headers - WebSocketChannel doesn't support custom headers directly
      // We need to use the connection string or a different package
      _logger.i('🔌 Connecting to: ${config.wsUrl}');
      final headers = {
        'Authorization': 'Bearer test-token',
        "Protocol-Version": "1",
        "Device-Id": config.deviceId,
        "Client-Id": config.clientId,
      };
      // print(jsonEncode(headers));
      // final headers = {
      //   'Authorization': 'Bearer test-token',
      //   'Protocol-Version': '1',
      //   'Device-Id': '00:15:5d:a5:bb:de',
      //   'Client-Id': 'eec7fe06-238a-426b-9ae1-d50748f13dd9',
      // };
      // Create WebSocket channel
      // Tạo HttpClient cho phép bỏ qua SSL lỗi (nếu cần)
      final client = HttpClient();
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
      try {
        _channel = IOWebSocketChannel.connect(
          uri,
          headers: headers,
          customClient: client,
        );
      } catch (e) {
        print(e);
        _channel = WebSocketChannel.connect(uri);
        String authMessage = 'Authorization: Bearer test-token}';
        _channel!.sink.add(authMessage);
        String deviceIdMessage = 'Device-ID: ${config.deviceId}';
        _channel!.sink.add(deviceIdMessage);
      }

      // Start message handler
      _startMessageHandler();

      // Start connection monitor
      _startConnectionMonitor();

      // Send hello message
      await _sendHello();

      // Wait for server hello (timeout 10s)
      final success = await _helloCompleter!.future.timeout(
        Duration(seconds: 10),
        onTimeout: () {
          _logger.e('❌ Timeout waiting for server hello');
          _handleNetworkError('Timeout waiting for server response');
          return false;
        },
      );

      if (success) {
        _connected = true;
        _reconnectAttempts = 0;
        _connectionStateController.add(ConnectionState.connected);
        _logger.i('✅ Connected to WebSocket server');

        _onConnectionStateChanged?.call(true, 'Connected successfully');

        return true;
      } else {
        await _cleanupConnection();
        return false;
      }
    } catch (e) {
      _logger.e('❌ WebSocket connection failed: $e');
      await _cleanupConnection();
      _handleNetworkError('Failed to connect: $e');
      return false;
    }
  }

  /// Send hello message to server
  Future<void> _sendHello() async {
    final helloMessage = {
      'type': 'hello',
      'version': 1,
      'features': {'mcp': true},
      'transport': 'websocket',
      'audio_params': {
        'format': 'opus',
        'sample_rate': 16000,
        'channels': 1,
        'frame_duration': 60,
      },
    };

    _logger.d('📤 Sending hello: ${jsonEncode(helloMessage)}');
    await sendText(jsonEncode(helloMessage));
  }

  /// Handle server hello response
  void _handleServerHello(Map<String, dynamic> data) {
    try {
      final transport = data['transport'];
      if (transport == null || transport != 'websocket') {
        _logger.e('❌ Unsupported transport: $transport');
        _helloCompleter?.complete(false);
        return;
      }

      _sessionId = data['session_id'];
      _logger.i('✅ Received server hello, session_id: $_sessionId');

      // Complete hello handshake
      _helloCompleter?.complete(true);

      // Notify audio channel opened
      _onAudioChannelOpened?.call();
    } catch (e) {
      _logger.e('❌ Error handling server hello: $e');
      _helloCompleter?.complete(false);
      _handleNetworkError('Failed to process server response: $e');
    }
  }

  /// Start message handler
  void _startMessageHandler() {
    _channel?.stream.listen(
      (message) {
        // print('Binh Received: $message');
        if (_isClosing) return;

        try {
          if (message is String) {
            // JSON message
            _handleJsonMessage(message);
          } else if (message is List<int>) {
            // Binary audio message
            _handleAudioMessage(Uint8List.fromList(message));
          }
        } catch (e) {
          _logger.e('❌ Error handling message: $e');
        }
      },
      onError: (e, st) {
        print('❌ Error: $e\n$st');
      },
      onDone: () {
        print(
          '🔌 Closed with code: ${_channel?.closeCode}, reason: ${_channel?.closeReason}',
        );
        if (!_isClosing) {
          _logger.w('⚠️ WebSocket connection closed');
          _handleConnectionLoss('Connection closed');
        }
      },
      cancelOnError: false,
    );
  }

  /// Handle JSON message
  void _handleJsonMessage(String message) {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final msgType = data['type'];

      _logger.d('📥 Received JSON: $msgType');

      if (msgType == 'hello') {
        _handleServerHello(data);
      } else if (msgType == 'tts') {
        _handleTtsMessage(data);
      } else if (msgType == 'asr') {
        _handleAsrMessage(data);
      } else {
        // Other messages - forward to callback
        _onIncomingJson?.call(data);
      }
    } catch (e) {
      _logger.e('❌ Invalid JSON message: $message, error: $e');
    }
  }

  /// Handle TTS message
  void _handleTtsMessage(Map<String, dynamic> data) {
    final state = data['state'];
    final text = data['text'];

    if (state == 'sentence_start' && text != null) {
      _logger.d('🔊 TTS: $text');
      _ttsTextController.add(text);
    }
  }

  /// Handle ASR message
  void _handleAsrMessage(Map<String, dynamic> data) {
    final text = data['text'];
    final isFinal = data['is_final'] ?? false;

    if (text != null && isFinal) {
      _logger.d('🎤 ASR: $text');
      _asrTextController.add(text);
    }
  }

  /// Handle binary audio message
  void _handleAudioMessage(Uint8List data) {
    _onIncomingAudio?.call(data);
  }

  // ============================================================================
  // Connection monitoring & heartbeat
  // ============================================================================

  /// Start connection monitor
  void _startConnectionMonitor() {
    _connectionMonitorTimer?.cancel();

    _connectionMonitorTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (_isClosing) {
        timer.cancel();
        return;
      }

      // Check if connection is still alive
      // In Dart, we rely on onDone callback
      // This is mainly for additional checks
    });
  }

  /// Start heartbeat (ping/pong)
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();

    _heartbeatTimer = Timer.periodic(_pingInterval, (timer) async {
      if (_isClosing) {
        timer.cancel();
        return;
      }

      try {
        _lastPingTime = DateTime.now();

        // Send ping (this is implicit in web_socket_channel)
        // The package handles ping/pong automatically

        _logger.d('💓 Heartbeat ping');
      } catch (e) {
        _logger.e('❌ Heartbeat failed: $e');
        await _handleConnectionLoss('Heartbeat failed');
      }
    });
  }

  /// Handle connection loss
  Future<void> _handleConnectionLoss(String reason) async {
    _logger.w('⚠️ Connection lost: $reason');

    _connected = false;
    _connectionStateController.add(ConnectionState.disconnected);

    _onConnectionStateChanged?.call(false, reason);

    if (_autoReconnectEnabled && !_isClosing) {
      await _attemptReconnect();
    } else {
      await _cleanupConnection();
      _handleNetworkError(reason);
    }
  }

  /// Attempt to reconnect
  Future<void> _attemptReconnect() async {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _logger.e('❌ Max reconnection attempts reached');
      _handleNetworkError(
        'Failed to reconnect after $_maxReconnectAttempts attempts',
      );
      await _cleanupConnection();
      return;
    }

    _reconnectAttempts++;
    _connectionStateController.add(ConnectionState.reconnecting);

    _logger.i(
      '🔄 Reconnecting... (attempt $_reconnectAttempts/$_maxReconnectAttempts)',
    );
    _onReconnecting?.call(_reconnectAttempts, _maxReconnectAttempts);

    // Wait before reconnecting
    await Future.delayed(Duration(seconds: 3 * _reconnectAttempts));

    // Try to reconnect
    final success = await connect();

    if (!success && _autoReconnectEnabled) {
      await _attemptReconnect();
    }
  }

  /// Enable auto reconnect
  void enableAutoReconnect({int maxAttempts = 5}) {
    _autoReconnectEnabled = true;
    _maxReconnectAttempts = maxAttempts;
    _logger.i('✅ Auto-reconnect enabled, max attempts: $maxAttempts');
  }

  /// Disable auto reconnect
  void disableAutoReconnect() {
    _autoReconnectEnabled = false;
    _maxReconnectAttempts = 0;
    _logger.i('❌ Auto-reconnect disabled');
  }

  // ============================================================================
  // Send methods
  // ============================================================================

  /// Send text message
  Future<void> sendText(String message) async {
    if (_channel == null || _isClosing) {
      _logger.w('⚠️ WebSocket not connected or closing');
      return;
    }

    try {
      _channel!.sink.add(message);
      _logger.d(
        '📤 Sent text: ${message.substring(0, message.length > 100 ? 100 : message.length)}...',
      );
    } catch (e) {
      _logger.e('❌ Failed to send text: $e');
      await _handleConnectionLoss('Failed to send text: $e');
    }
  }

  /// Send text message (typed)
  Future<void> sendTextMessage(String text) async {
    if (_sessionId == null) {
      _logger.w('⚠️ No session ID, cannot send message');
      return;
    }
    // {"session_id": "", "type": "listen", "state": "detect", "text": "chao x\u00ecn"}
    final message = {
      'session_id': _sessionId,
      'type': 'listen',
      'state': 'detect',
      'text': text,
    };

    await sendText(jsonEncode(message));
  }

  /// Send audio data
  Future<void> sendAudio(Uint8List data) async {
    if (!isAudioChannelOpened()) {
      _logger.w('⚠️ Audio channel not opened');
      return;
    }

    try {
      // _logger.i('🎤 data...$data');

      _channel!.sink.add(data);
    } catch (e) {
      _logger.e('❌ Failed to send audio: $e');
      await _handleConnectionLoss('Failed to send audio: $e');
    }
  }

  /// Check if audio channel is opened
  bool isAudioChannelOpened() {
    return _channel != null && _connected && !_isClosing;
  }

  // ============================================================================
  // Protocol methods (from Python Protocol class)
  // ============================================================================

  /// Send abort speaking message
  Future<void> sendAbortSpeaking(AbortReason reason) async {
    final message = {
      'session_id': _sessionId,
      'type': 'abort',
      if (reason == AbortReason.wakeWordDetected)
        'reason': 'wake_word_detected',
    };
    await sendText(jsonEncode(message));
  }

  /// Send wake word detected
  Future<void> sendWakeWordDetected(String wakeWord) async {
    final message = {
      'session_id': _sessionId,
      'type': 'listen',
      'state': 'detect',
      'text': wakeWord,
    };
    await sendText(jsonEncode(message));
  }

  /// Send start listening
  Future<void> sendStartListening(ListeningMode mode) async {
    final modeMap = {
      ListeningMode.realtime: 'realtime',
      ListeningMode.autoStop: 'auto',
      ListeningMode.manual: 'manual',
    };

    final message = {
      'session_id': _sessionId,
      'type': 'listen',
      'state': 'start',
      'mode': modeMap[mode],
    };
    await sendText(jsonEncode(message));
  }

  /// Send stop listening
  Future<void> sendStopListening() async {
    final message = {
      'session_id': _sessionId,
      'type': 'listen',
      'state': 'stop',
    };
    await sendText(jsonEncode(message));
  }

  /// Send IoT descriptors
  Future<void> sendIotDescriptors(
    List<Map<String, dynamic>> descriptors,
  ) async {
    for (var i = 0; i < descriptors.length; i++) {
      final descriptor = descriptors[i];
      if (descriptor.isEmpty) {
        _logger.e('❌ Invalid descriptor at index $i');
        continue;
      }

      final message = {
        'session_id': _sessionId,
        'type': 'iot',
        'update': true,
        'descriptors': [descriptor],
      };

      try {
        await sendText(jsonEncode(message));
      } catch (e) {
        _logger.e('❌ Failed to send IoT descriptor at index $i: $e');
      }
    }
  }

  /// Send IoT states
  Future<void> sendIotStates(Map<String, dynamic> states) async {
    final message = {
      'session_id': _sessionId,
      'type': 'iot',
      'update': true,
      'states': states,
    };
    await sendText(jsonEncode(message));
  }

  /// Send MCP message
  Future<void> sendMcpMessage(Map<String, dynamic> payload) async {
    final message = {
      'session_id': _sessionId,
      'type': 'mcp',
      'payload': payload,
    };
    await sendText(jsonEncode(message));
  }

  // ============================================================================
  // Cleanup
  // ============================================================================

  /// Handle network error
  void _handleNetworkError(String error) {
    _logger.e('❌ Network error: $error');
    _onNetworkError?.call(error);
  }

  /// Cleanup connection
  Future<void> _cleanupConnection() async {
    _connected = false;

    // Cancel timers
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _connectionMonitorTimer?.cancel();
    _connectionMonitorTimer = null;

    // Close channel
    await _channel?.sink.close();
    _channel = null;

    _lastPingTime = null;
    _lastPongTime = null;
  }

  /// Disconnect
  Future<void> disconnect() async {
    _isClosing = true;

    try {
      await _cleanupConnection();
      _onAudioChannelClosed?.call();
      _connectionStateController.add(ConnectionState.disconnected);
      _logger.i('✅ Disconnected from WebSocket');
    } catch (e) {
      _logger.e('❌ Error disconnecting: $e');
    } finally {
      _isClosing = false;
    }
  }

  /// Dispose
  void dispose() {
    disconnect();
    _ttsTextController.close();
    _asrTextController.close();
    _connectionStateController.close();
  }

  // ============================================================================
  // Connection info
  // ============================================================================

  Map<String, dynamic> getConnectionInfo() {
    return {
      'connected': _connected,
      'is_closing': _isClosing,
      'auto_reconnect_enabled': _autoReconnectEnabled,
      'reconnect_attempts': _reconnectAttempts,
      'max_reconnect_attempts': _maxReconnectAttempts,
      'last_ping_time': _lastPingTime?.toIso8601String(),
      'last_pong_time': _lastPongTime?.toIso8601String(),
      'websocket_url': config.wsUrl,
      'session_id': _sessionId,
    };
  }
}

class WebSocketService {
  final String url;
  final Map<String, String>? headers;
  final Duration pingInterval;
  final Duration pingTimeout;
  final Duration closeTimeout;
  final int maxMessageSize;

  IOWebSocketChannel? _channel;
  Timer? _pingTimer;
  Timer? _pongMonitor;
  DateTime _lastPong = DateTime.now();
  bool _isClosing = false;

  WebSocketService({
    required this.url,
    this.headers,
    this.pingInterval = const Duration(seconds: 20),
    this.pingTimeout = const Duration(seconds: 20),
    this.closeTimeout = const Duration(seconds: 10),
    this.maxMessageSize = 10 * 1024 * 1024, // 10MB
  });

  /// ✅ Kết nối socket
  Future<void> connect() async {
    try {
      print('🌐 Connecting to $url ...');

      // Tạo client SSL không kiểm tra chứng chỉ (nếu server tự ký)
      final client = HttpClient();
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;

      // Kết nối WebSocket thủ công để tắt nén (compression=None)
      final rawSocket = await WebSocket.connect(
        url,
        headers: headers,
        compression: CompressionOptions.compressionOff,
        customClient: client,
      );

      _channel = IOWebSocketChannel(rawSocket);
      _lastPong = DateTime.now();

      print('✅ Connected to $url');

      // Bắt đầu ping/pong
      _startPing();
      _startPongMonitor();

      // Lắng nghe dữ liệu
      _channel!.stream.listen(
        (data) => _onMessage(data),
        onDone: _onClosed,
        onError: _onError,
      );
    } catch (e) {
      print('❌ Connection failed: $e');
      await _reconnect();
    }
  }

  /// 📤 Gửi tin nhắn
  void send(dynamic data) {
    if (_channel != null && _channel!.closeCode == null) {
      _channel!.sink.add(data);
    }
  }

  /// 🩵 Gửi ping định kỳ
  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(pingInterval, (_) {
      if (_channel == null || _channel!.closeCode != null) return;
      try {
        send(jsonEncode({"type": "ping"}));
        print("📡 Sent ping");
      } catch (_) {}
    });
  }

  /// 🩷 Theo dõi pong timeout
  void _startPongMonitor() {
    _pongMonitor?.cancel();
    _pongMonitor = Timer.periodic(const Duration(seconds: 5), (_) {
      final diff = DateTime.now().difference(_lastPong).inSeconds;
      if (diff > pingTimeout.inSeconds) {
        print("⚠️ Pong timeout (${pingTimeout.inSeconds}s) → reconnecting...");
        _reconnect();
      }
    });
  }

  /// 📩 Nhận dữ liệu
  void _onMessage(dynamic data) {
    if (data is String && data.length > maxMessageSize) {
      print('🚨 Message too large (> ${maxMessageSize ~/ 1024 / 1024}MB)');
      _close();
      return;
    }

    // Kiểm tra pong
    if (data == 'pong' ||
        (data is String && data.contains('pong') && !data.contains('ping'))) {
      _lastPong = DateTime.now();
      print('💓 Received pong');
    } else {
      print('📩 Message: $data');
    }
  }

  /// 🔄 Khi đóng kết nối
  void _onClosed() {
    print('❌ Socket closed (${_channel?.closeCode})');
    if (!_isClosing) _reconnect();
  }

  /// ⚠️ Khi có lỗi
  void _onError(dynamic error) {
    print('⚠️ Socket error: $error');
    _reconnect();
  }

  /// 🔄 Reconnect
  Future<void> _reconnect() async {
    await _close();
    print('🔁 Reconnecting in 5s...');
    await Future.delayed(const Duration(seconds: 5));
    await connect();
  }

  /// ❌ Đóng kết nối an toàn (close_timeout)
  Future<void> _close() async {
    if (_channel == null) return;
    _isClosing = true;
    try {
      _pingTimer?.cancel();
      _pongMonitor?.cancel();
      _channel!.sink.close();
      await Future.delayed(closeTimeout);
    } catch (_) {}
    _channel = null;
    _isClosing = false;
  }
}
