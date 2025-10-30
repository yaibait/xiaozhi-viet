import 'dart:async';
import 'dart:typed_data';
import 'package:logger/logger.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'opus_service.dart';
import 'package:opus_dart/opus_dart.dart';

/// Audio service để record và playback với Opus codec
class AudioService {
  final Logger _logger = Logger();
  static const String TAG = "AudioUtil";
  static const int SAMPLE_RATE = 16000;
  static const int CHANNELS = 1;
  static const int FRAME_DURATION = 60; // 毫秒
  // Opus相关
  static final _encoder = SimpleOpusEncoder(
    sampleRate: SAMPLE_RATE,
    channels: CHANNELS,
    application: Application.voip,
  );
  // Recording
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  StreamSubscription? _recordingSubscription;

  // Playback
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;

  // Opus codec
  final OpusService _opusService = OpusService();

  // Streams
  final StreamController<Uint8List> _audioDataController =
      StreamController<Uint8List>.broadcast();
  final StreamController<Int16List> _pcmDataController =
      StreamController<Int16List>.broadcast(); // For VAD
  final StreamController<double> _volumeLevelController =
      StreamController<double>.broadcast();
  final StreamController<bool> _recordingStateController =
      StreamController<bool>.broadcast();

  // Public streams
  Stream<Uint8List> get audioDataStream => _audioDataController.stream;
  Stream<Int16List> get pcmDataStream => _pcmDataController.stream; // For VAD
  Stream<double> get volumeLevelStream => _volumeLevelController.stream;
  Stream<bool> get recordingStateStream => _recordingStateController.stream;

  // Getters
  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;

  AudioService();

  Future<void> init() async {
    _logger.i('🎤 Initializing audio service...');

    // Check permissions
    if (await _recorder.hasPermission()) {
      _logger.i('✅ Microphone permission granted');
    } else {
      _logger.w('⚠️ No microphone permission');
    }

    // Initialize Opus
    await _opusService.initialize();
  }

  // ============================================================================
  // Recording
  // ============================================================================
  /// 将PCM数据编码为Opus格式
  static Future<Uint8List?> encodeToOpus(Uint8List pcmData) async {
    try {
      // 删除频繁日志
      // 转换PCM数据为Int16List (小端字节序，与Android一致)
      final Int16List pcmInt16 = Int16List.fromList(
        List.generate(
          pcmData.length ~/ 2,
          (i) => (pcmData[i * 2]) | (pcmData[i * 2 + 1] << 8),
        ),
      );

      // 确保数据长度符合Opus要求（必须是2.5ms、5ms、10ms、20ms、40ms或60ms的采样数）
      final int samplesPerFrame = (SAMPLE_RATE * FRAME_DURATION) ~/ 1000;

      Uint8List encoded;

      // 处理过短的数据
      if (pcmInt16.length < samplesPerFrame) {
        // 对于过短的数据，可以通过添加静音来填充到所需长度
        final Int16List paddedData = Int16List(samplesPerFrame);
        for (int i = 0; i < pcmInt16.length; i++) {
          paddedData[i] = pcmInt16[i];
        }

        // 编码填充后的数据
        encoded = Uint8List.fromList(_encoder.encode(input: paddedData));
      } else {
        // 对于足够长的数据，裁剪到精确的帧长度
        encoded = Uint8List.fromList(
          _encoder.encode(input: pcmInt16.sublist(0, samplesPerFrame)),
        );
      }

      return encoded;
    } catch (e, stackTrace) {
      // print('$TAG: Opus编码失败: $e');
      print(stackTrace);
      return null;
    }
  }

  /// Start recording với streaming
  Future<bool> startRecording({
    int sampleRate = 16000,
    int numChannels = 1,
    int bitRate = 16000,
  }) async {
    if (_isRecording) {
      _logger.w('⚠️ Already recording');
      return false;
    }
    if (!_opusService.isInitialized) {
      _logger.i('🎵 Initializing Opus before recording...');
      await _opusService.initialize(); // gọi nhưng chỉ init 1 lần
    }
    try {
      _logger.i('🎤 Starting recording...');

      // Check permission
      if (!await _recorder.hasPermission()) {
        _logger.e('❌ No microphone permission');
        return false;
      }

      // Start recording with streaming
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits, // PCM16 for Opus encoding
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 128000,
        ),
      );

      // Khai báo thêm buffer tạm để gom mẫu âm thanh
      final List<int> _pcmBuffer = [];

      // Process audio chunks
      _recordingSubscription = stream.listen(
        (chunk) async {
          if (chunk.isNotEmpty && chunk.length % 2 == 0) {
            // Convert to PCM Int16List for VAD
            final Int16List pcmInt16 = Int16List.fromList(
              List.generate(
                chunk.length ~/ 2,
                (i) => (chunk[i * 2]) | (chunk[i * 2 + 1] << 8),
              ),
            );

            // Emit PCM data for VAD processing
            _pcmDataController.add(pcmInt16);
            // _logger.d('🎤 PCM emitted: ${pcmInt16.length} samples'); // Uncomment for debug

            // Encode to Opus for server
            final opusData = await encodeToOpus(chunk);
            if (opusData != null) {
              _audioDataController.add(opusData);
            }
          }
        },
        onError: (error) {
          _logger.e('❌ Recording error: $error');
          _isRecording = false;
          _recordingStateController.add(false);
          stopRecording();
        },
        onDone: () {
          _logger.w('⚠️ Recording stream done (closed)');
          _isRecording = false;
          _recordingStateController.add(false);
          _pcmBuffer.clear();
        },
      );
      _isRecording = true;
      _recordingStateController.add(true);
      _logger.i('✅ Recording started');

      return true;
    } catch (e) {
      _logger.e('❌ Failed to start recording: $e');
      return false;
    }
  }

  /// Stop recording
  Future<void> stopRecording() async {
    if (!_isRecording) return;

    try {
      _logger.i('🛑 Stopping recording...');

      await _recordingSubscription?.cancel();
      await _recorder.stop();

      _isRecording = false;
      _recordingStateController.add(false);

      _logger.i('✅ Recording stopped');
    } catch (e) {
      _logger.e('❌ Error stopping recording: $e');
    }
  }

  /// Pause recording
  Future<void> pauseRecording() async {
    if (!_isRecording) return;

    try {
      await _recorder.pause();
      _logger.i('⏸️ Recording paused');
    } catch (e) {
      _logger.e('❌ Error pausing recording: $e');
    }
  }

  /// Resume recording
  Future<void> resumeRecording() async {
    try {
      await _recorder.resume();
      _logger.i('▶️ Recording resumed');
    } catch (e) {
      _logger.e('❌ Error resuming recording: $e');
    }
  }

  // ============================================================================
  // Playback
  // ============================================================================

  /// Play Opus audio data
  Future<void> playOpusAudio(Uint8List opusData) async {
    try {
      _logger.d('🔊 Playing Opus audio: ${opusData.length} bytes');

      // Decode Opus to PCM
      final pcmData = _opusService.decode(opusData);
      if (pcmData == null) {
        _logger.e('❌ Failed to decode Opus audio');
        return;
      }

      // Convert Int16List to Uint8List
      final bytes = Uint8List.view(pcmData.buffer);

      // Play using just_audio
      // Note: just_audio requires a proper audio file format
      // For raw PCM, we'd need to create a WAV header or use a different method
      // This is a simplified version - you may need audio_session package

      _isPlaying = true;
      _logger.i('🔊 Playing audio...');

      // TODO: Implement proper PCM playback
      // Options:
      // 1. Use audioplayers with raw PCM support
      // 2. Create WAV file with header
      // 3. Use platform channels for native playback

      _isPlaying = false;
    } catch (e) {
      _logger.e('❌ Error playing audio: $e');
      _isPlaying = false;
    }
  }

  /// Play audio from URL
  Future<void> playFromUrl(String url) async {
    try {
      _logger.i('🔊 Playing from URL: $url');

      await _player.setUrl(url);
      await _player.play();

      _isPlaying = true;
    } catch (e) {
      _logger.e('❌ Error playing from URL: $e');
    }
  }

  /// Stop playback
  Future<void> stopPlayback() async {
    try {
      await _player.stop();
      _isPlaying = false;
      _logger.i('🛑 Playback stopped');
    } catch (e) {
      _logger.e('❌ Error stopping playback: $e');
    }
  }

  // ============================================================================
  // Utils
  // ============================================================================

  /// Calculate volume level (RMS) from PCM data
  double _calculateVolume(Int16List pcm) {
    if (pcm.isEmpty) return 0.0;

    // Calculate RMS
    double sum = 0;
    for (var sample in pcm) {
      sum += sample * sample;
    }

    final rms = Math.sqrt(sum / pcm.length);

    // Normalize to 0.0 - 1.0
    const maxAmplitude = 32768.0; // Max value for int16
    return (rms / maxAmplitude).clamp(0.0, 1.0);
  }

  /// Get current volume
  Future<double> getCurrentVolume() async {
    // TODO: Implement amplitude detection during recording
    return 0.0;
  }

  // ============================================================================
  // Cleanup
  // ============================================================================

  Future<void> dispose() async {
    await stopRecording();
    await stopPlayback();

    await _recordingSubscription?.cancel();
    await _recorder.dispose();
    await _player.dispose();

    _audioDataController.close();
    _pcmDataController.close();
    _volumeLevelController.close();
    _recordingStateController.close();

    _logger.i('🧹 Audio service disposed');
  }
}

// Math helper
class Math {
  static double sqrt(double x) => x < 0 ? 0 : x.squareRoot;
}

extension on double {
  double get squareRoot {
    if (this == 0) return 0;
    double x = this;
    double y = 1;
    double e = 0.000001;

    while (x - y > e) {
      x = (x + y) / 2;
      y = this / x;
    }

    return x;
  }
}
