import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:logger/logger.dart';
import 'opus_service.dart';

/// TTS Playback Service
/// Handles decoding Opus and playing TTS audio from server
class TtsPlaybackService {
  final Logger _logger = Logger();

  // Audio player
  final AudioPlayer _player = AudioPlayer();

  // Opus decoder
  final OpusService _opusService = OpusService();

  // State
  bool _isPlaying = false;
  bool _isInitialized = false;

  // Audio buffer
  final List<Int16List> _audioBuffer = [];

  // Streams
  final StreamController<bool> _playbackStateController =
      StreamController<bool>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();

  // Public streams
  Stream<bool> get playbackStateStream => _playbackStateController.stream;
  Stream<Duration> get positionStream => _positionController.stream;

  // Getters
  bool get isPlaying => _isPlaying;
  bool get isInitialized => _isInitialized;

  TtsPlaybackService() {
    _init();
  }

  Future<void> _init() async {
    try {
      _logger.i('🔊 Initializing TTS playback service...');

      // Initialize Opus decoder
      _opusService.initialize();

      // Setup player callbacks
      _player.playbackEventStream.listen((event) {
        _positionController.add(event.updatePosition);
      });

      _player.playerStateStream.listen((state) {
        _isPlaying = state.playing;
        _playbackStateController.add(state.playing);

        if (state.processingState == ProcessingState.completed) {
          _logger.i('✅ Playback completed');
          _isPlaying = false;
          _playbackStateController.add(false);
        }
      });

      _isInitialized = true;
      _logger.i('✅ TTS playback service initialized');
    } catch (e) {
      _logger.e('❌ Failed to initialize TTS service: $e');
    }
  }

  // ============================================================================
  // Playback Methods
  // ============================================================================

  /// Play single Opus frame
  Future<void> playOpusFrame(Uint8List opusData) async {
    if (!_isInitialized) {
      _logger.e('❌ TTS service not initialized');
      return;
    }

    try {
      // Decode Opus to PCM
      final pcmData = _opusService.decode(opusData);
      if (pcmData == null) {
        _logger.e('❌ Failed to decode Opus data');
        return;
      }

      // Add to buffer
      _audioBuffer.add(pcmData);

      _logger.d('🔊 Buffered audio frame: ${pcmData.length} samples');
    } catch (e) {
      _logger.e('❌ Error processing Opus frame: $e');
    }
  }

  /// Play buffered audio
  Future<void> playBuffer() async {
    if (_audioBuffer.isEmpty) {
      _logger.w('⚠️ Audio buffer is empty');
      return;
    }

    try {
      _logger.i('🔊 Playing buffered audio (${_audioBuffer.length} frames)...');

      // Combine all PCM frames
      final combinedPcm = _combineFrames(_audioBuffer);

      // Create WAV file
      final wavFile = await _createWavFile(combinedPcm);

      // Play WAV file
      await _player.setFilePath(wavFile.path);
      await _player.play();

      _isPlaying = true;
      _logger.i('✅ Playing audio...');

      // Clear buffer after playing
      _audioBuffer.clear();
    } catch (e) {
      _logger.e('❌ Error playing buffer: $e');
      _isPlaying = false;
    }
  }

  /// Play Opus audio stream (multiple frames)
  Future<void> playOpusStream(List<Uint8List> opusFrames) async {
    if (!_isInitialized) {
      _logger.e('❌ TTS service not initialized');
      return;
    }

    try {
      _logger.i('🔊 Playing Opus stream (${opusFrames.length} frames)...');

      // Decode all frames
      final pcmFrames = <Int16List>[];
      for (var opus in opusFrames) {
        final pcm = _opusService.decode(opus);
        if (pcm != null) {
          pcmFrames.add(pcm);
        }
      }

      if (pcmFrames.isEmpty) {
        _logger.e('❌ No valid PCM data');
        return;
      }

      // Combine frames
      final combinedPcm = _combineFrames(pcmFrames);

      // Create WAV file
      final wavFile = await _createWavFile(combinedPcm);

      // Play
      await _player.setFilePath(wavFile.path);
      await _player.play();

      _isPlaying = true;
    } catch (e) {
      _logger.e('❌ Error playing stream: $e');
      _isPlaying = false;
    }
  }

  /// Stop playback
  Future<void> stop() async {
    try {
      await _player.stop();
      _isPlaying = false;
      _audioBuffer.clear();
      _logger.i('🛑 Playback stopped');
    } catch (e) {
      _logger.e('❌ Error stopping playback: $e');
    }
  }

  /// Pause playback
  Future<void> pause() async {
    try {
      await _player.pause();
      _logger.i('⏸️ Playback paused');
    } catch (e) {
      _logger.e('❌ Error pausing playback: $e');
    }
  }

  /// Resume playback
  Future<void> resume() async {
    try {
      await _player.play();
      _logger.i('▶️ Playback resumed');
    } catch (e) {
      _logger.e('❌ Error resuming playback: $e');
    }
  }

  // ============================================================================
  // Helper Methods
  // ============================================================================

  /// Combine multiple PCM frames
  Int16List _combineFrames(List<Int16List> frames) {
    final totalLength = frames.fold<int>(0, (sum, frame) => sum + frame.length);
    final combined = Int16List(totalLength);

    var offset = 0;
    for (var frame in frames) {
      combined.setAll(offset, frame);
      offset += frame.length;
    }

    return combined;
  }

  /// Create WAV file from PCM data
  Future<File> _createWavFile(Int16List pcmData) async {
    try {
      // Get temporary directory
      final tempDir = await getTemporaryDirectory();
      final wavPath =
          '${tempDir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.wav';
      final file = File(wavPath);

      // WAV header parameters
      const sampleRate = 16000;
      const numChannels = 1;
      const bitsPerSample = 16;

      final dataSize = pcmData.length * 2; // 2 bytes per sample (int16)
      final fileSize = 36 + dataSize;

      // Create WAV header
      final header = ByteData(44);

      // RIFF chunk
      header.setUint8(0, 0x52); // 'R'
      header.setUint8(1, 0x49); // 'I'
      header.setUint8(2, 0x46); // 'F'
      header.setUint8(3, 0x46); // 'F'
      header.setUint32(4, fileSize, Endian.little);
      header.setUint8(8, 0x57); // 'W'
      header.setUint8(9, 0x41); // 'A'
      header.setUint8(10, 0x56); // 'V'
      header.setUint8(11, 0x45); // 'E'

      // fmt chunk
      header.setUint8(12, 0x66); // 'f'
      header.setUint8(13, 0x6D); // 'm'
      header.setUint8(14, 0x74); // 't'
      header.setUint8(15, 0x20); // ' '
      header.setUint32(16, 16, Endian.little); // fmt chunk size
      header.setUint16(20, 1, Endian.little); // audio format (PCM)
      header.setUint16(22, numChannels, Endian.little);
      header.setUint32(24, sampleRate, Endian.little);
      header.setUint32(
        28,
        sampleRate * numChannels * bitsPerSample ~/ 8,
        Endian.little,
      ); // byte rate
      header.setUint16(
        32,
        numChannels * bitsPerSample ~/ 8,
        Endian.little,
      ); // block align
      header.setUint16(34, bitsPerSample, Endian.little);

      // data chunk
      header.setUint8(36, 0x64); // 'd'
      header.setUint8(37, 0x61); // 'a'
      header.setUint8(38, 0x74); // 't'
      header.setUint8(39, 0x61); // 'a'
      header.setUint32(40, dataSize, Endian.little);

      // Write header + PCM data
      final headerBytes = header.buffer.asUint8List();
      final pcmBytes = Uint8List.view(pcmData.buffer);

      await file.writeAsBytes([...headerBytes, ...pcmBytes]);

      _logger.d('✅ Created WAV file: $wavPath (${file.lengthSync()} bytes)');

      return file;
    } catch (e) {
      _logger.e('❌ Error creating WAV file: $e');
      rethrow;
    }
  }

  /// Clear audio buffer
  void clearBuffer() {
    _audioBuffer.clear();
    _logger.d('🧹 Audio buffer cleared');
  }

  /// Get buffer info
  Map<String, dynamic> getBufferInfo() {
    return {
      'frames': _audioBuffer.length,
      'total_samples': _audioBuffer.fold<int>(
        0,
        (sum, frame) => sum + frame.length,
      ),
      'duration_ms':
          (_audioBuffer.fold<int>(0, (sum, frame) => sum + frame.length) / 16)
              .round(),
    };
  }

  // ============================================================================
  // Cleanup
  // ============================================================================

  Future<void> dispose() async {
    await stop();
    await _player.dispose();

    _playbackStateController.close();
    _positionController.close();

    _opusService.dispose();

    _logger.i('🧹 TTS playback service disposed');
  }
}
