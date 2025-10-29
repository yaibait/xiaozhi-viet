import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:logger/logger.dart';
import 'opus_service.dart';

/// TTS Playback Service - SMOOTH STREAMING VERSION
/// Optimized to eliminate stuttering between chunks
class TtsPlaybackService {
  final Logger _logger = Logger();

  // Audio player with improved buffering
  final AudioPlayer _player = AudioPlayer();

  // Opus decoder
  final OpusService _opusService = OpusService();

  // State
  bool _isPlaying = false;
  bool _isInitialized = false;

  // Smooth streaming state
  int _currentSessionId = 0;
  int _totalFramesReceived = 0;
  int _totalChunksCreated = 0;
  final List<Int16List> _currentChunk = [];
  Timer? _chunkTimer;
  bool _isProcessingChunk = false;

  // ✅ OPTIMIZED: Configuration for smooth playback
  static const int FRAMES_PER_CHUNK = 10; // 600ms per chunk (smoother)
  static const int MIN_FRAMES_TO_START = 4; // Start after 240ms (better buffer)
  static const int AUTO_FLUSH_DELAY_MS = 400; // Wait 400ms for more frames

  // Streams
  final StreamController<bool> _playbackStateController =
      StreamController<bool>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();

  // ✅ OPTIMIZED: Concatenated audio source queue
  ConcatenatingAudioSource? _playlist;
  bool _isInitializingPlaylist = false;

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
      _logger.i('🔊 Initializing TTS playback service (SMOOTH STREAMING)...');

      // Initialize Opus decoder
      await _opusService.initialize();

      // ✅ OPTIMIZED: Configure player for smooth playback
      await _player.setSpeed(1.0);
      await _player.setVolume(1.0);

      // Setup player callbacks
      _player.playbackEventStream.listen((event) {
        _positionController.add(event.updatePosition);
      });

      _player.playerStateStream.listen((state) {
        final wasPlaying = _isPlaying;
        _isPlaying = state.playing;

        if (wasPlaying != _isPlaying) {
          _playbackStateController.add(_isPlaying);
        }

        if (state.processingState == ProcessingState.completed) {
          _logger.i('✅ Playback completed');
          _isPlaying = false;
          _playbackStateController.add(false);
        }
      });

      _isInitialized = true;
      _logger.i('✅ TTS playback service initialized (SMOOTH STREAMING)');
    } catch (e) {
      _logger.e('❌ Failed to initialize TTS service: $e');
    }
  }

  // ============================================================================
  // Smooth Streaming Methods
  // ============================================================================

  /// Start new streaming session
  void startNewSession() {
    _currentSessionId++;
    _totalFramesReceived = 0;
    _totalChunksCreated = 0;
    _currentChunk.clear();
    _isProcessingChunk = false;

    _logger.i('🆕 Starting new smooth streaming session: $_currentSessionId');

    // Stop current playback
    if (_isPlaying) {
      _player.stop();
    }

    // Reset playlist
    _playlist = null;
    _isInitializingPlaylist = false;

    // Cancel timers
    _chunkTimer?.cancel();
    _chunkTimer = null;
  }

  /// Add Opus frame (will auto-create chunks and play smoothly)
  Future<void> addOpusFrame(Uint8List opusData) async {
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

      // Add to current chunk
      _currentChunk.add(pcmData);
      _totalFramesReceived++;

      _logger.d(
        '📊 Frame #$_totalFramesReceived (chunk: ${_currentChunk.length}/${FRAMES_PER_CHUNK})',
      );

      // ✅ OPTIMIZED: Create chunks with better timing
      if (_currentChunk.length >= FRAMES_PER_CHUNK) {
        // Chunk is full, create immediately
        await _createAndAddChunk();
      } else if (_currentChunk.length >= MIN_FRAMES_TO_START && !_isPlaying) {
        // Start playing early if not playing yet
        _logger.i(
          '🚀 Starting playback (${_currentChunk.length} frames buffered)...',
        );
        await _createAndAddChunk();
      }

      // Reset auto-flush timer
      _resetChunkTimer();
    } catch (e) {
      _logger.e('❌ Error adding Opus frame: $e');
    }
  }

  /// Create chunk and add to concatenating playlist
  Future<void> _createAndAddChunk() async {
    if (_currentChunk.isEmpty || _isProcessingChunk) return;

    _isProcessingChunk = true;

    try {
      // Combine frames
      final combinedPcm = _combineFrames(_currentChunk);

      // Create WAV file
      final wavFile = await _createWavFile(combinedPcm);

      _totalChunksCreated++;
      _logger.i(
        '✅ Chunk #$_totalChunksCreated created (${_currentChunk.length} frames, ${wavFile.lengthSync()} bytes)',
      );

      // Clear current chunk
      _currentChunk.clear();

      // ✅ OPTIMIZED: Add to concatenating playlist
      await _addToPlaylist(wavFile.path);
    } catch (e) {
      _logger.e('❌ Error creating chunk: $e');
    } finally {
      _isProcessingChunk = false;
    }
  }

  /// ✅ OPTIMIZED: Add chunk to concatenating playlist for gapless playback
  Future<void> _addToPlaylist(String filePath) async {
    try {
      if (_playlist == null) {
        // First chunk - create playlist and start playing
        _logger.i('🎵 Creating playlist with first chunk...');

        _playlist = ConcatenatingAudioSource(
          useLazyPreparation: false, // Prepare immediately
          children: [AudioSource.uri(Uri.file(filePath))],
        );

        await _player.setAudioSource(_playlist!);
        await _player.play();

        _isPlaying = true;
        _playbackStateController.add(true);

        _logger.i('▶️ Started playing first chunk');
      } else {
        // Add to existing playlist (gapless!)
        _logger.d('➕ Adding chunk to playlist...');

        await _playlist!.add(AudioSource.uri(Uri.file(filePath)));

        _logger.d('✅ Chunk added to playlist (total: ${_playlist!.length})');
      }
    } catch (e) {
      _logger.e('❌ Error adding to playlist: $e');
    }
  }

  /// Reset auto-flush timer
  void _resetChunkTimer() {
    _chunkTimer?.cancel();

    _chunkTimer = Timer(Duration(milliseconds: AUTO_FLUSH_DELAY_MS), () {
      if (_currentChunk.isNotEmpty) {
        _logger.i('⏱️ Auto-flushing ${_currentChunk.length} frames...');
        _createAndAddChunk();
      }
    });
  }

  /// Flush any remaining frames
  Future<void> flushRemainingFrames() async {
    _chunkTimer?.cancel();

    if (_currentChunk.isNotEmpty) {
      _logger.i('🔚 Flushing final ${_currentChunk.length} frames...');
      await _createAndAddChunk();
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
      final tempDir = await getTemporaryDirectory();
      final wavPath =
          '${tempDir.path}/tts_smooth_${DateTime.now().millisecondsSinceEpoch}.wav';
      final file = File(wavPath);

      // WAV header parameters
      const sampleRate = 16000;
      const numChannels = 1;
      const bitsPerSample = 16;

      final dataSize = pcmData.length * 2;
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
      header.setUint32(16, 16, Endian.little);
      header.setUint16(20, 1, Endian.little);
      header.setUint16(22, numChannels, Endian.little);
      header.setUint32(24, sampleRate, Endian.little);
      header.setUint32(
        28,
        sampleRate * numChannels * bitsPerSample ~/ 8,
        Endian.little,
      );
      header.setUint16(32, numChannels * bitsPerSample ~/ 8, Endian.little);
      header.setUint16(34, bitsPerSample, Endian.little);

      // data chunk
      header.setUint8(36, 0x64); // 'd'
      header.setUint8(37, 0x61); // 'a'
      header.setUint8(38, 0x74); // 't'
      header.setUint8(39, 0x61); // 'a'
      header.setUint32(40, dataSize, Endian.little);

      // Write file
      final headerBytes = header.buffer.asUint8List();
      final pcmBytes = Uint8List.view(pcmData.buffer);
      await file.writeAsBytes([...headerBytes, ...pcmBytes]);

      return file;
    } catch (e) {
      _logger.e('❌ Error creating WAV file: $e');
      rethrow;
    }
  }

  // ============================================================================
  // Control Methods
  // ============================================================================

  /// Stop playback
  Future<void> stop() async {
    try {
      _chunkTimer?.cancel();

      await _player.stop();

      _isPlaying = false;
      _playlist = null;
      _currentChunk.clear();

      _logger.i('🛑 Playback stopped');
    } catch (e) {
      _logger.e('❌ Error stopping playback: $e');
    }
  }

  /// Get stream info
  Map<String, dynamic> getStreamInfo() {
    return {
      'session_id': _currentSessionId,
      'total_frames_received': _totalFramesReceived,
      'total_chunks_created': _totalChunksCreated,
      'current_chunk_size': _currentChunk.length,
      'playlist_length': _playlist?.length ?? 0,
      'is_playing': _isPlaying,
      'estimated_duration_ms': _totalFramesReceived * 60,
    };
  }

  // ============================================================================
  // Cleanup
  // ============================================================================

  Future<void> dispose() async {
    _chunkTimer?.cancel();

    await stop();
    await _player.dispose();

    _playbackStateController.close();
    _positionController.close();

    _opusService.dispose();

    _logger.i('🧹 TTS playback service disposed');
  }
}
