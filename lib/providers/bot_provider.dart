import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import '../models/config.dart';
import '../services/websocket_service.dart';
import '../services/activation_service.dart';
import '../services/audio_service.dart';
import '../services/vad_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'dart:math';
import 'dart:convert';
import '../services/tts_playback_service.dart'; // ← ADD THIS

/// Bot states
enum BotState {
  idle, // Đang đợi
  listening, // Đang nghe user
  thinking, // Đang xử lý
  speaking, // Đang nói
  error, // Lỗi
}

/// Bot emotions
enum BotEmotion {
  neutral, // Bình thường
  happy, // Vui
  thinking, // Đang suy nghĩ
  listening, // Đang lắng nghe
  speaking, // Đang nói
  sad, // Buồn
  error, // Lỗi
}

/// Main Bot Provider
class BotProvider extends ChangeNotifier {
  final Logger _logger = Logger();

  // Services
  XiaozhiConfig? _config;
  XiaozhiWebSocketService? _wsService;
  ActivationService? _activationService;
  final AudioService _audioService = AudioService();
  final VadService _vadService = VadService();
  final TtsPlaybackService _ttsPlayback = TtsPlaybackService(); // ← ADD THIS

  // State
  BotState _state = BotState.idle;
  BotEmotion _emotion = BotEmotion.neutral;
  bool _isActivated = false;
  bool _isConnected = false;
  String? _activationCode;

  // Text
  String _currentTtsText = '';
  String _currentAsrText = '';
  final List<ChatMessage> _messages = [];
  final uuid = Uuid();
  // Subscriptions
  StreamSubscription? _ttsSubscription;
  StreamSubscription? _asrSubscription;
  StreamSubscription? _audioDataSubscription;
  StreamSubscription? _vadSubscription;
  StreamSubscription? _connectionStateSubscription;
  StreamSubscription? _ttsPlaybackSubscription; // ← ADD THIS

  // Getters
  BotState get state => _state;
  BotEmotion get emotion => _emotion;
  bool get isActivated => _isActivated;
  bool get isConnected => _isConnected;
  String? get activationCode => _activationCode;
  String get currentTtsText => _currentTtsText;
  String get currentAsrText => _currentAsrText;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isListening => _state == BotState.listening;
  bool get isSpeaking => _state == BotState.speaking;

  // ============================================================================
  // Initialization
  // ============================================================================

  /// Initialize bot
  Future<void> initialize({String? deviceId, String? clientId}) async {
    try {
      _logger.i('🤖 Initializing bot...');
      // Lấy device_id từ SharedPreferences nếu có
      final prefs = await SharedPreferences.getInstance();

      final savedDeviceId = prefs.getString('device_id');
      final savedClientId = prefs.getString('client_id');
      final serial_number = prefs.getString('serial_number');
      final hmacKey = prefs.getString('hmac_key');
      final finalDeviceId = deviceId ?? savedDeviceId ?? _generateDeviceId();
      final finalClientId = clientId ?? savedClientId ?? _generateClientId();
      final finalserialNumber =
          serial_number ?? serial_number ?? generateSerialFromUuid();
      final finalHmacKey = hmacKey ?? hmacKey ?? _generateHmacKey();
      // Lưu lại nếu là lần đầu
      if (savedDeviceId == null) {
        await prefs.setString('device_id', finalDeviceId);
      }
      if (savedClientId == null) {
        await prefs.setString('client_id', finalClientId);
      }
      // Create config
      _config = XiaozhiConfig(
        deviceId: finalDeviceId,
        clientId: finalClientId,
        serialNumber: finalserialNumber,
        hmacKey: finalHmacKey,
      );

      // Create services
      _activationService = ActivationService(_config!);
      _wsService = XiaozhiWebSocketService(_config!);

      // Setup callbacks
      _setupWebSocketCallbacks();

      // Check activation
      _logger.i('📡 Checking activation status...');
      final response = await _activationService!.checkOtaStatus();

      if (response.needsActivation) {
        _activationCode = response.verificationCode;
        _isActivated = false;
        _updateEmotion(BotEmotion.neutral);
        _logger.i('🔑 Need activation: $_activationCode');

        // Start activation in background
        _startActivation();
      } else {
        _isActivated = true;
        _logger.i('✅ Already activated');
        await connect();
      }
      _audioService.init();
      notifyListeners();
    } catch (e) {
      _logger.e('❌ Initialization error: $e');
      _updateState(BotState.error);
      _updateEmotion(BotEmotion.error);
    }
  }

  String generateSerialFromUuid() {
    final u = uuid.v4().replaceAll('-', ''); // 32 hex chars
    // lấy 8 hex đầu và 12 hex cuối (còn lại bỏ giữa)
    final part1 = u.substring(0, 8);
    final part2 = u.substring(20, 32);
    return 'SN-${part1}-${part2}';
  }

  String _generateHmacKey() {
    // Generate random 32-byte key
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }

  String _generateDeviceId() {
    return randomMac();
  }

  String _toHex(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();

  String randomMac({bool locallyAdministered = true}) {
    final rnd = Random.secure();
    // Sinh 6 byte
    final bytes = List<int>.generate(6, (_) => rnd.nextInt(256));

    // Điều chỉnh byte đầu:
    // - đảm bảo unicast: clear bit 0 (LSB)
    // - nếu locallyAdministered true: set bit 1 (the "locally administered" bit)
    int first = bytes[0];
    first = first & 0xFE; // clear multicast bit (LSB)
    if (locallyAdministered) {
      first = first | 0x02; // set locally-administered bit (bit 1)
    } else {
      first = first & 0xFD; // clear locally-administered (optional)
    }
    bytes[0] = first;

    return bytes.map(_toHex).join(':').toLowerCase();
  }

  String _generateClientId() {
    return uuid.v4().toLowerCase();
  }

  /// Setup WebSocket callbacks
  void _setupWebSocketCallbacks() {
    // TTS stream
    _ttsSubscription = _wsService!.ttsTextStream.listen((text) {
      _currentTtsText = text;
      _addMessage(ChatMessage(text: text, isUser: false));
      _updateState(BotState.speaking);
      _updateEmotion(BotEmotion.speaking);
      _logger.i('🔊 TTS: $text');
      notifyListeners();
    });

    // ASR stream
    _asrSubscription = _wsService!.asrTextStream.listen((text) {
      _currentAsrText = text;
      _addMessage(ChatMessage(text: text, isUser: true));
      _logger.i('🎤 ASR: $text');
      notifyListeners();
    });

    // Connection state
    _connectionStateSubscription = _wsService!.connectionStateStream.listen((
      state,
    ) {
      _isConnected = state == ConnectionState.connected;
      _logger.i('🔌 Connection state: $state');
      notifyListeners();
    });

    // Audio data stream
    _audioDataSubscription = _audioService.audioDataStream.listen((opusData) {
      // Send to server
      _wsService?.sendAudio(opusData);
    });
    // ✅ THÊM MỚI - TTS Audio stream (Server → Speaker)
    _wsService!.onIncomingAudio((opusData) {
      _logger.d('🔊 Received TTS audio: ${opusData.length} bytes');

      // Buffer audio frame
      _ttsPlayback.playOpusFrame(opusData);
    });

    // ✅ THÊM MỚI - TTS Playback state
    _ttsPlaybackSubscription = _ttsPlayback.playbackStateStream.listen((
      isPlaying,
    ) {
      if (isPlaying) {
        _updateState(BotState.speaking);
        _updateEmotion(BotEmotion.speaking);
      } else {
        // Playback finished
        _updateState(BotState.idle);
        _updateEmotion(BotEmotion.happy);
      }
      notifyListeners();
    });
    // VAD stream
    _vadSubscription = _vadService.vadEventStream.listen((event) {
      if (event == VadEvent.speechStart) {
        _logger.d('🎤 Speech started');
        _updateEmotion(BotEmotion.listening);
      } else if (event == VadEvent.speechEnd) {
        _logger.d('🔇 Speech ended');
        // Auto stop listening if in auto mode
        if (_state == BotState.listening) {
          stopListening();
        }
      }
    });
  }

  /// Start activation process
  void _startActivation() async {
    try {
      _logger.i('🚀 Starting activation...');
      final success = await _activationService!.activate();

      if (success) {
        _isActivated = true;
        _activationCode = null;
        _logger.i('✅ Activation successful!');
        await connect();
      } else {
        _logger.e('❌ Activation failed');
        _updateState(BotState.error);
        _updateEmotion(BotEmotion.error);
      }

      notifyListeners();
    } catch (e) {
      _logger.e('❌ Activation error: $e');
    }
  }

  // ============================================================================
  // Connection
  // ============================================================================

  /// Connect to WebSocket
  Future<void> connect() async {
    try {
      _logger.i('🔌 Connecting to server...');
      final success = await _wsService!.connect();

      if (success) {
        _isConnected = true;
        _updateState(BotState.idle);
        _updateEmotion(BotEmotion.happy);
        _logger.i('✅ Connected!');
      } else {
        _logger.e('❌ Connection failed');
        _updateState(BotState.error);
        _updateEmotion(BotEmotion.error);
      }

      notifyListeners();
    } catch (e) {
      _logger.e('❌ Connection error: $e');
      _updateState(BotState.error);
      _updateEmotion(BotEmotion.error);
    }
  }

  /// Disconnect
  Future<void> disconnect() async {
    await _wsService?.disconnect();
    _isConnected = false;
    _updateState(BotState.idle);
    notifyListeners();
  }

  // ============================================================================
  // Voice interaction
  // ============================================================================

  /// Start listening
  Future<void> startListening({
    ListeningMode mode = ListeningMode.autoStop,
  }) async {
    if (!_isConnected) {
      _logger.w('⚠️ Not connected');
      return;
    }

    try {
      _logger.i('🎤 Starting listening...');

      // Update state
      _updateState(BotState.listening);
      _updateEmotion(BotEmotion.listening);

      // Send start listening to server
      await _wsService!.sendStartListening(mode);

      // Start audio recording
      await _audioService.startRecording();

      _logger.i('✅ Listening started');
      notifyListeners();
    } catch (e) {
      _logger.e('❌ Error starting listening: $e');
      _updateState(BotState.error);
    }
  }

  /// Stop listening
  Future<void> stopListening() async {
    try {
      _logger.i('🛑 Stopping listening...');

      // Stop audio recording
      await _audioService.stopRecording();

      // Send stop listening to server
      await _wsService!.sendStopListening();

      // Update state
      _updateState(BotState.thinking);
      _updateEmotion(BotEmotion.thinking);

      _logger.i('✅ Listening stopped');
      // ✅ THÊM MỚI - Wait for TTS response và play
      // Server sẽ gửi TTS audio frames về
      // TtsPlaybackService sẽ buffer chúng

      // Wait một chút để đảm bảo nhận đủ audio
      await Future.delayed(Duration(milliseconds: 500));

      // Play buffered audio
      final bufferInfo = _ttsPlayback.getBufferInfo();
      if (bufferInfo['frames'] > 0) {
        _logger.i('🔊 Playing TTS audio (${bufferInfo['frames']} frames)');
        await _ttsPlayback.playBuffer();
      }
      notifyListeners();
    } catch (e) {
      _logger.e('❌ Error stopping listening: $e');
    }
  }

  /// Toggle listening
  Future<void> toggleListening() async {
    if (_state == BotState.listening) {
      await stopListening();
    } else {
      await startListening();
    }
  }

  /// Send text message
  Future<void> sendTextMessage(String text) async {
    if (!_isConnected) {
      _logger.w('⚠️ Not connected');
      return;
    }

    try {
      _logger.i('📤 Sending text: $text');

      // Add to messages
      _addMessage(ChatMessage(text: text, isUser: true));

      // Send to server
      await _wsService!.sendTextMessage(text);

      // Update state
      _updateState(BotState.thinking);
      _updateEmotion(BotEmotion.thinking);

      notifyListeners();
    } catch (e) {
      _logger.e('❌ Error sending text: $e');
    }
  }

  // ============================================================================
  // State management
  // ============================================================================

  void _updateState(BotState newState) {
    if (_state != newState) {
      _state = newState;
      _logger.d('🔄 State: $_state');
      notifyListeners();
    }
  }

  void _updateEmotion(BotEmotion newEmotion) {
    if (_emotion != newEmotion) {
      _emotion = newEmotion;
      _logger.d('😊 Emotion: $_emotion');
      notifyListeners();
    }
  }

  void _addMessage(ChatMessage message) {
    _messages.add(message);
    if (_messages.length > 100) {
      _messages.removeAt(0); // Keep only last 100 messages
    }
  }

  /// Clear messages
  void clearMessages() {
    _messages.clear();
    notifyListeners();
  }

  // ============================================================================
  // Cleanup
  // ============================================================================

  @override
  void dispose() {
    _ttsSubscription?.cancel();
    _asrSubscription?.cancel();
    _audioDataSubscription?.cancel();
    _vadSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _ttsPlaybackSubscription?.cancel(); // ← ADD THIS

    _wsService?.dispose();
    _audioService.dispose();
    _vadService.dispose();
    _ttsPlayback.dispose(); // ← ADD THIS
    super.dispose();
  }
}

/// Chat message model
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({required this.text, required this.isUser, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();
}
