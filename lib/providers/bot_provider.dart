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
import '../services/tts_playback_service.dart';

/// Bot states
enum BotState { idle, listening, thinking, speaking, error }

/// Bot emotions
enum BotEmotion { neutral, happy, thinking, listening, speaking, sad, error }

/// Main Bot Provider - FIXED VERSION
class BotProvider extends ChangeNotifier {
  final Logger _logger = Logger();

  // Services
  XiaozhiConfig? _config;
  XiaozhiWebSocketService? _wsService;
  ActivationService? _activationService;
  final AudioService _audioService = AudioService();
  final VadService _vadService = VadService();
  final TtsPlaybackService _ttsPlayback = TtsPlaybackService();

  // State
  BotState _state = BotState.idle;
  BotState _stateBeforeDisconnect =
      BotState.idle; // ✅ FIX 4: Lưu state trước disconnect
  BotEmotion _emotion = BotEmotion.neutral;
  bool _isActivated = false;
  bool _isConnected = false;
  String? _activationCode;

  // ✅ FIX 1: Thêm field để lưu listening mode
  ListeningMode _currentListeningMode = ListeningMode.autoStop;

  // ✅ FIX 3: Thêm lock để tránh race condition
  bool _isTransitioning = false;

  // ✅ FIX 1: Thêm timer cho VAD timeout
  Timer? _vadSpeechEndTimer;

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
  StreamSubscription? _ttsPlaybackSubscription;
  StreamSubscription? _recordingStateSubscription; // ✅ FIX 5: Thêm subscription

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

  Future<void> initialize({String? deviceId, String? clientId}) async {
    try {
      _logger.i('🤖 Initializing bot...');
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

      if (savedDeviceId == null) {
        await prefs.setString('device_id', finalDeviceId);
      }
      if (savedClientId == null) {
        await prefs.setString('client_id', finalClientId);
      }

      _config = XiaozhiConfig(
        deviceId: finalDeviceId,
        clientId: finalClientId,
        serialNumber: finalserialNumber,
        hmacKey: finalHmacKey,
      );

      _activationService = ActivationService(_config!);
      _wsService = XiaozhiWebSocketService(_config!);

      _setupWebSocketCallbacks();

      _logger.i('📡 Checking activation status...');
      final response = await _activationService!.checkOtaStatus();

      if (response.needsActivation) {
        _activationCode = response.verificationCode;
        _isActivated = false;
        _updateEmotion(BotEmotion.neutral);
        _logger.i('🔑 Need activation: $_activationCode');
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
    final u = uuid.v4().replaceAll('-', '');
    final part1 = u.substring(0, 8);
    final part2 = u.substring(20, 32);
    return 'SN-${part1}-${part2}';
  }

  String _generateHmacKey() {
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
    final bytes = List<int>.generate(6, (_) => rnd.nextInt(256));
    int first = bytes[0];
    first = first & 0xFE;
    if (locallyAdministered) {
      first = first | 0x02;
    } else {
      first = first & 0xFD;
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

      // ✅ FIX 2: CHỈ update state nếu không đang listening
      if (_state != BotState.listening) {
        _updateState(BotState.speaking);
        _updateEmotion(BotEmotion.speaking);
      }

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

      // ✅ FIX 4: Xử lý connection loss
      if (state == ConnectionState.disconnected && !_isConnected) {
        _handleConnectionLoss();
      }

      notifyListeners();
    });

    // Audio data stream
    _audioDataSubscription = _audioService.audioDataStream.listen((opusData) {
      _wsService?.sendAudio(opusData);
    });

    // TTS Audio stream - ✅ CHUNKED STREAMING VERSION
    _wsService!.onIncomingAudio((opusData) {
      _logger.d('🔊 Received TTS audio: ${opusData.length} bytes');

      // ✅ Add frame to streaming (sẽ tự động tạo chunk và play)
      _ttsPlayback.addOpusFrame(opusData);
    });

    // ✅ FIX 2: TTS Playback state - với state check
    _ttsPlaybackSubscription = _ttsPlayback.playbackStateStream.listen((
      isPlaying,
    ) {
      if (isPlaying) {
        // CHỈ update nếu không đang listening
        if (_state != BotState.listening) {
          _updateState(BotState.speaking);
          _updateEmotion(BotEmotion.speaking);
        }
      } else {
        // CHỈ về idle nếu đang speaking
        if (_state == BotState.speaking) {
          _updateState(BotState.idle);
          _updateEmotion(BotEmotion.happy);
        }
      }
      notifyListeners();
    });

    // ✅ FIX 1: VAD stream - với mode check và timeout
    _vadSubscription = _vadService.vadEventStream.listen((event) {
      if (event == VadEvent.speechStart) {
        _logger.d('🎤 Speech started');

        // Hủy timer nếu đang chờ
        _vadSpeechEndTimer?.cancel();
        _vadSpeechEndTimer = null;

        _updateEmotion(BotEmotion.listening);
      } else if (event == VadEvent.speechEnd) {
        _logger.d('🔇 Speech ended');

        // CHỈ auto-stop nếu mode là autoStop
        if (_state == BotState.listening &&
            _currentListeningMode == ListeningMode.autoStop) {
          // Hủy timer cũ nếu có
          _vadSpeechEndTimer?.cancel();

          // Thêm timeout 1.5s để tránh dừng quá sớm
          _vadSpeechEndTimer = Timer(Duration(milliseconds: 1500), () {
            if (_state == BotState.listening) {
              _logger.i('⏱️ VAD timeout - stopping listening');
              stopListening();
            }
          });
        }
      }
    });

    // ✅ FIX 5: Recording state stream - sync với bot state
    _recordingStateSubscription = _audioService.recordingStateStream.listen((
      isRecording,
    ) {
      if (!isRecording && _state == BotState.listening) {
        _logger.w('⚠️ Recording stopped unexpectedly while in listening state');
        _updateState(BotState.error);
        _updateEmotion(BotEmotion.error);
        notifyListeners();
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

        // ✅ FIX 4: Restore state nếu đang listening trước khi mất kết nối
        if (_stateBeforeDisconnect == BotState.listening) {
          _logger.i('🔄 Restoring listening state after reconnection');
          await startListening(mode: _currentListeningMode);
        } else {
          _updateState(BotState.idle);
          _updateEmotion(BotEmotion.happy);
        }

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

  /// ✅ FIX 4: Handle connection loss
  void _handleConnectionLoss() {
    _logger.w('⚠️ Connection lost');
    _stateBeforeDisconnect = _state;

    // Dừng recording nếu đang listening
    if (_state == BotState.listening) {
      _audioService.stopRecording();
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

  /// ✅ FIX 1 & 3: Start listening với lock và mode tracking
  Future<void> startListening({
    ListeningMode mode = ListeningMode.autoStop,
  }) async {
    // ✅ FIX 3: Check lock
    if (_isTransitioning) {
      _logger.w('⚠️ Already transitioning state');
      return;
    }

    if (!_isConnected) {
      _logger.w('⚠️ Not connected');
      return;
    }

    _isTransitioning = true; // Lock

    try {
      _logger.i('🎤 Starting listening (mode: $mode)...');

      // ✅ FIX AUDIO: Clear old audio buffer trước khi start listening mới
      _ttsPlayback.startNewSession();

      // ✅ FIX 1: Lưu listening mode
      _currentListeningMode = mode;

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
    } finally {
      _isTransitioning = false; // ✅ FIX 3: Unlock
    }
  }

  /// ✅ STREAMING VERSION: Stop listening (đơn giản hơn nhiều!)
  Future<void> stopListening() async {
    // ✅ FIX 3: Check lock
    if (_isTransitioning) {
      _logger.w('⚠️ Already transitioning state');
      return;
    }

    _isTransitioning = true; // Lock

    try {
      _logger.i('🛑 Stopping listening...');

      // Hủy VAD timer nếu có
      _vadSpeechEndTimer?.cancel();
      _vadSpeechEndTimer = null;

      // Stop audio recording
      await _audioService.stopRecording();

      // Send stop listening to server
      await _wsService!.sendStopListening();

      // Update state
      _updateState(BotState.thinking);
      _updateEmotion(BotEmotion.thinking);

      _logger.i('✅ Listening stopped');

      // ✅ STREAMING: Không cần waitForAudio() nữa!
      // Audio sẽ tự động stream và play từng chunk khi frames đến
      // Chỉ cần đợi một chút để đảm bảo nhận frames đầu tiên
      await Future.delayed(Duration(milliseconds: 200));

      // Check stream status
      final streamInfo = _ttsPlayback.getStreamInfo();
      _logger.i('📊 Stream info: $streamInfo');

      // Đợi thêm để nhận tất cả frames
      await Future.delayed(Duration(milliseconds: 500));

      // Flush remaining frames (phần cuối cùng)
      await _ttsPlayback.flushRemainingFrames();

      notifyListeners();
    } catch (e) {
      _logger.e('❌ Error stopping listening: $e');
    } finally {
      _isTransitioning = false; // ✅ FIX 3: Unlock
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

      _addMessage(ChatMessage(text: text, isUser: true));
      await _wsService!.sendTextMessage(text);

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
      _messages.removeAt(0);
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
    // Cancel timers
    _vadSpeechEndTimer?.cancel(); // ✅ FIX 1: Cancel VAD timer

    // Cancel subscriptions
    _ttsSubscription?.cancel();
    _asrSubscription?.cancel();
    _audioDataSubscription?.cancel();
    _vadSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _ttsPlaybackSubscription?.cancel();
    _recordingStateSubscription?.cancel(); // ✅ FIX 5

    // Dispose services
    _wsService?.dispose();
    _audioService.dispose();
    _vadService.dispose();
    _ttsPlayback.dispose();

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
