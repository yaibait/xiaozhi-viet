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
  StreamSubscription? _pcmDataSubscription; // For VAD
  StreamSubscription? _vadSubscription;
  StreamSubscription? _connectionStateSubscription;
  StreamSubscription? _ttsPlaybackSubscription;
  StreamSubscription? _recordingStateSubscription; // ✅ FIX 5: Thêm subscription
  // Auto voice detection mode
  bool _autoVoiceMode = false;
  bool _isMonitoringVoice = false;
  StreamSubscription? _autoVoiceSubscription;
  Timer? _autoRestartTimer;
  Timer? _autoListeningCheckTimer;
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
  bool get autoVoiceMode => _autoVoiceMode;
  bool get isMonitoringVoice => _isMonitoringVoice;
  VadService get vadService => _vadService;
  AudioService get audioService => _audioService;
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
      // Chỉ gửi audio đến server khi đang listening
      if (_state == BotState.listening) {
        _wsService?.sendAudio(opusData);
      }
    });

    // PCM data stream for VAD processing
    _pcmDataSubscription = _audioService.pcmDataStream.listen(
      (pcmData) {
        // Luôn luôn process VAD để phát hiện giọng nói
        _vadService.processFrame(pcmData);
      },
      onError: (error) {
        _logger.e('❌ PCM stream error: $error');
      },
      onDone: () {
        _logger.w('⚠️ PCM stream closed');
        // Nếu auto mode đang bật, restart recording
        if (_autoVoiceMode && _isMonitoringVoice) {
          _logger.i(
            '🔄 PCM stream closed, restarting recording for auto mode...',
          );
          Future.delayed(Duration(milliseconds: 100), () async {
            if (_autoVoiceMode && _isMonitoringVoice) {
              await _audioService.startRecording();
            }
          });
        }
      },
    );

    // TTS Audio stream - ✅ CHUNKED STREAMING VERSION
    _wsService!.onIncomingAudio((opusData) {
      _logger.d('🔊 Received TTS audio: ${opusData.length} bytes');

      // ✅ Add frame to streaming (sẽ tự động tạo chunk và play)
      _ttsPlayback.addOpusFrame(opusData);
    });

    // ✅ FIX 2: TTS Playback state - với state check và auto mode restart
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

          // ✅ FIX: Khi bot nói xong trong auto mode, reset VAD để sẵn sàng
          if (_autoVoiceMode && _isMonitoringVoice) {
            _logger.i(
              '🔄 Auto mode: Bot finished speaking, ready for next input',
            );
            _vadService.reset();
          }
        }
      }
      notifyListeners();
    });

    // ✅ FIX 1: VAD stream - với mode check và timeout
    _vadSubscription = _vadService.vadEventStream.listen((event) {
      _logger.d(
        '🔊 VAD Event: $event (state: $_state, autoMode: $_autoVoiceMode)',
      );
      // ✅ CRITICAL: Skip nếu auto mode đang bật (auto listener sẽ xử lý)
      if (_autoVoiceMode) {
        _logger.d('⏭️ Auto mode active, skipping manual VAD handler');
        return;
      }
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
  // Auto Voice Mode
  // ============================================================================

  /// Enable auto voice mode - tự động phát hiện và bắt đầu lắng nghe
  Future<void> enableAutoVoiceMode() async {
    if (!_isConnected) {
      _logger.w('⚠️ Not connected - cannot enable auto voice mode');
      return;
    }

    if (_autoVoiceMode) {
      _logger.w('⚠️ Auto voice mode already enabled');
      return;
    }

    _logger.i('🤖 Enabling auto voice mode...');
    _autoVoiceMode = true;

    // Bắt đầu monitoring voice activity
    await _startVoiceMonitoring();

    notifyListeners();
  }

  /// Disable auto voice mode
  Future<void> disableAutoVoiceMode() async {
    if (!_autoVoiceMode) {
      _logger.w('⚠️ Auto voice mode already disabled');
      return;
    }

    _logger.i('🛑 Disabling auto voice mode...');
    _autoVoiceMode = false;

    // Dừng monitoring
    await _stopVoiceMonitoring();

    // Nếu đang listening thì stop
    if (_state == BotState.listening) {
      await stopListening();
    }

    notifyListeners();
  }

  /// Toggle auto voice mode
  Future<void> toggleAutoVoiceMode() async {
    if (_autoVoiceMode) {
      await disableAutoVoiceMode();
    } else {
      await enableAutoVoiceMode();
    }
  }

  /// Bắt đầu monitoring voice activity
  Future<void> _startVoiceMonitoring() async {
    if (_isMonitoringVoice) {
      _logger.w('⚠️ Already monitoring voice');
      return;
    }

    try {
      _logger.i('👂 Starting voice monitoring...');
      _isMonitoringVoice = true;

      // Reset VAD service
      _vadService.reset();

      // Bắt đầu recording để monitor
      final recordingStarted = await _audioService.startRecording();
      if (!recordingStarted) {
        _logger.e('❌ Failed to start recording for monitoring');
        _isMonitoringVoice = false;
        return;
      }
      _logger.i('✅ Recording started for monitoring');

      // Subscribe to VAD events cho auto mode
      _autoVoiceSubscription = _vadService.vadEventStream.listen(
        (event) {
          if (!_autoVoiceMode) {
            _logger.d('⚠️ VAD event but auto mode disabled, ignoring');
            return;
          }

          _logger.i('🔊 Auto VAD Event: $event (state: $_state)');

          if (event == VadEvent.speechStart) {
            _logger.i('🎤 Auto: Speech detected - starting listening');

            // Tự động bắt đầu listening khi phát hiện giọng nói
            if (_state == BotState.idle || _state == BotState.speaking) {
              _autoStartListening();
            } else {
              _logger.d(
                '⚠️ Auto: Not in idle/speaking state, current: $_state',
              );
            }
          } else if (event == VadEvent.speechEnd) {
            _logger.d('🔇 Auto: Speech ended');

            // Trong auto mode, khi speech end thì auto stop và quay về monitoring
            if (_state == BotState.listening) {
              _autoStopListening();
            } else {
              _logger.d('⚠️ Auto: Not in listening state, current: $_state');
            }
          }
        },
        onError: (error) {
          _logger.e('❌ Auto VAD subscription error: $error');
        },
        onDone: () {
          _logger.w('⚠️ Auto VAD subscription closed');
        },
      );

      _logger.i('✅ Voice monitoring started');
      notifyListeners();
    } catch (e) {
      _logger.e('❌ Error starting voice monitoring: $e');
      _isMonitoringVoice = false;
    }
  }

  /// Dừng monitoring voice activity
  Future<void> _stopVoiceMonitoring() async {
    if (!_isMonitoringVoice) {
      return;
    }

    try {
      _logger.i('🛑 Stopping voice monitoring...');

      // Cancel subscription
      _autoVoiceSubscription?.cancel();
      _autoVoiceSubscription = null;

      // Cancel timers
      _autoRestartTimer?.cancel();
      _autoRestartTimer = null;
      _autoListeningCheckTimer?.cancel();
      _autoListeningCheckTimer = null;

      // ✅ FIX: LUÔN stop recording khi tắt monitoring
      await _audioService.stopRecording();

      _isMonitoringVoice = false;
      _logger.i('✅ Voice monitoring stopped');
      notifyListeners();
    } catch (e) {
      _logger.e('❌ Error stopping voice monitoring: $e');
    }
  }

  /// Auto start listening khi phát hiện giọng nói
  Future<void> _autoStartListening() async {
    try {
      _logger.i('🤖 Auto starting listening...');

      // Clear old audio buffer
      _ttsPlayback.startNewSession();

      // Update state
      _updateState(BotState.listening);
      _updateEmotion(BotEmotion.listening);

      // Send start listening to server với auto mode
      await _wsService!.sendStartListening(ListeningMode.autoStop);

      // ✅ FIX: Recording đã chạy rồi từ monitoring, KHÔNG cần start lại
      // Chỉ cần đảm bảo là nó vẫn đang chạy
      if (!_audioService.isRecording) {
        _logger.w('⚠️ Recording stopped unexpectedly, restarting...');
        await _audioService.startRecording();
      }

      _logger.i('✅ Auto listening started');
      notifyListeners();
    } catch (e) {
      _logger.e('❌ Error auto starting listening: $e');
    }
  }

  /// Auto stop listening khi hết giọng nói
  Future<void> _autoStopListening() async {
    try {
      _logger.i('🤖 Auto stopping listening...');

      // Send stop listening to server
      await _wsService!.sendStopListening();

      // Update state
      _updateState(BotState.thinking);
      _updateEmotion(BotEmotion.thinking);

      _logger.i('✅ Auto listening stopped');

      // Wait for response
      await Future.delayed(Duration(milliseconds: 200));

      // Flush remaining frames
      await _ttsPlayback.flushRemainingFrames();

      // ✅ FIX: Đợi bot nói xong rồi mới ready cho input tiếp
      // Thay vì dùng timer, listen vào TTS playback state
      notifyListeners();
    } catch (e) {
      _logger.e('❌ Error auto stopping listening: $e');
    }
  }

  // ============================================================================
  // Cleanup
  // ============================================================================

  @override
  void dispose() {
    // Cancel timers
    _vadSpeechEndTimer?.cancel(); // ✅ FIX 1: Cancel VAD timer
    _autoRestartTimer?.cancel();
    _autoListeningCheckTimer?.cancel();

    // Cancel subscriptions
    _ttsSubscription?.cancel();
    _asrSubscription?.cancel();
    _audioDataSubscription?.cancel();
    _pcmDataSubscription?.cancel();
    _vadSubscription?.cancel();
    _autoVoiceSubscription?.cancel();
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
