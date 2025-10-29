import 'dart:typed_data';
import 'package:logger/logger.dart';
import 'package:opus_dart/opus_dart.dart' as opus_dart;
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;

/// Opus codec service for encoding/decoding audio
class OpusService {
  final Logger _logger = Logger();
  static bool _opusLibraryInitialized = false; // flag toàn cục
  opus_dart.SimpleOpusEncoder? _encoder;
  opus_dart.SimpleOpusDecoder? _decoder;

  static const int sampleRate = 16000;
  static const int channels = 1;
  static const int frameDuration = 60; // ms
  static const int frameSize =
      (sampleRate * frameDuration) ~/ 1000; // 960 mẫu với 60ms

  bool _initialized = false;
  bool get isInitialized => _initialized;
  static Future<void> initOpusLibrary() async {
    if (_opusLibraryInitialized) return;

    try {
      final lib = await opus_flutter.load();
      opus_dart.initOpus(lib);
      _opusLibraryInitialized = true;
      print('✅ Opus library initialized');
    } catch (e) {
      print('❌ Failed to initOpus: $e');
    }
  }

  /// Initialize Opus encoder and decoder
  Future<void> initialize() async {
    if (_initialized) return; // nếu đã init, bỏ qua
    try {
      _logger.i('🎵 Initializing Opus codec...');
      if (!_opusLibraryInitialized) {
        await initOpusLibrary();
      }

      _encoder = opus_dart.SimpleOpusEncoder(
        sampleRate: sampleRate,
        channels: channels,
        application: opus_dart.Application.voip,
      );

      _decoder = opus_dart.SimpleOpusDecoder(
        sampleRate: sampleRate,
        channels: channels,
      );

      _initialized = true;
      _logger.i('✅ Opus codec initialized');
      _logger.d('   Sample rate: $sampleRate Hz');
      _logger.d('   Frame size: $frameSize samples');
    } catch (e) {
      _logger.e('❌ Failed to initialize Opus: $e');
      _initialized = false;
    }
  }

  /// Encode a single frame (auto pad/truncate)
  Uint8List? encode(Int16List pcm) {
    if (!_initialized || _encoder == null) {
      _logger.e('❌ Opus encoder not initialized');
      return null;
    }

    try {
      if (pcm.length != frameSize) {
        _logger.w('⚠️ PCM frame size mismatch: ${pcm.length} != $frameSize');
        // Chuẩn hoá độ dài frame
        final fixed = Int16List(frameSize);
        if (pcm.length < frameSize) {
          fixed.setAll(0, pcm); // pad 0
        } else {
          fixed.setAll(0, pcm.sublist(0, frameSize)); // cắt bớt
        }
        pcm = fixed;
      }

      return _encoder!.encode(input: pcm);
    } catch (e) {
      _logger.e('❌ Opus encode error: $e');
      return null;
    }
  }

  /// Encode toàn bộ dữ liệu PCM (tự chia frame)
  List<Uint8List> encodeFrames(Int16List pcm) {
    if (!_initialized || _encoder == null) {
      _logger.e('❌ Encoder not initialized');
      return [];
    }

    final frames = <Uint8List>[];
    for (int i = 0; i < pcm.length; i += frameSize) {
      final end = (i + frameSize < pcm.length) ? (i + frameSize) : pcm.length;
      final frame = pcm.sublist(i, end);
      final encoded = encode(Int16List.fromList(frame));
      if (encoded != null) frames.add(encoded);
    }

    return frames;
  }

  /// Decode Opus to PCM16
  Int16List? decode(Uint8List opusData) {
    if (!_initialized || _decoder == null) {
      _logger.e('❌ Opus decoder not initialized');
      return null;
    }

    try {
      return _decoder!.decode(input: opusData);
    } catch (e) {
      _logger.e('❌ Opus decode error: $e');
      return null;
    }
  }

  /// Decode multiple frames
  Int16List decodeFrames(List<Uint8List> frames) {
    final allPcm = <int>[];
    for (var frame in frames) {
      final decoded = decode(frame);
      if (decoded != null) {
        allPcm.addAll(decoded);
      }
    }
    return Int16List.fromList(allPcm);
  }

  void dispose() {
    _encoder = null;
    _decoder = null;
    _initialized = false;
    _logger.i('🧹 Opus service disposed');
  }
}
