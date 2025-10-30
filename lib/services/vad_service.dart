import 'dart:async';
import 'dart:typed_data';
import 'package:logger/logger.dart';
import 'dart:math' as math;

/// Voice Activity Detection (VAD) service - IMPROVED VERSION
/// Detects when user is speaking vs silence with adaptive threshold and debouncing
class VadService {
  final Logger _logger = Logger();

  // VAD configuration
  double _energyThreshold = 0.02; // Base energy threshold for speech detection
  int _minSpeechFrames = 3; // Minimum frames to confirm speech
  int _minSilenceFrames = 10; // Minimum frames to confirm silence

  // ✅ NEW: Debouncing configuration
  int _maxNoiseFramesInSilence = 2; // Allow up to 2 noise frames during silence
  int _maxSilenceFramesInSpeech =
      2; // Allow up to 2 silence frames during speech

  // ✅ NEW: Adaptive threshold
  bool _enableAdaptiveThreshold = true;
  double _noiseFloor = 0.0;
  double _adaptiveMultiplier = 2.0; // Threshold = noiseFloor * multiplier
  List<double> _recentEnergies = [];
  int _maxRecentEnergies = 30; // Keep last 30 frames for noise estimation

  // State
  bool _isSpeaking = false;
  int _speechFrameCount = 0;
  int _silenceFrameCount = 0;

  // ✅ NEW: Debouncing counters
  int _noiseFramesInSilence = 0;
  int _silenceFramesInSpeech = 0;

  // Streams
  final StreamController<bool> _vadStateController =
      StreamController<bool>.broadcast();
  final StreamController<VadEvent> _vadEventController =
      StreamController<VadEvent>.broadcast();

  // Public streams
  Stream<bool> get vadStateStream => _vadStateController.stream;
  Stream<VadEvent> get vadEventStream => _vadEventController.stream;

  // Getters
  bool get isSpeaking => _isSpeaking;
  double get currentThreshold => _enableAdaptiveThreshold
      ? _noiseFloor * _adaptiveMultiplier
      : _energyThreshold;
  double get noiseFloor => _noiseFloor;

  VadServiceImproved({
    double? energyThreshold,
    int? minSpeechFrames,
    int? minSilenceFrames,
    bool? enableAdaptiveThreshold,
    int? maxNoiseFramesInSilence,
    int? maxSilenceFramesInSpeech,
  }) {
    _energyThreshold = energyThreshold ?? _energyThreshold;
    _minSpeechFrames = minSpeechFrames ?? _minSpeechFrames;
    _minSilenceFrames = minSilenceFrames ?? _minSilenceFrames;
    _enableAdaptiveThreshold =
        enableAdaptiveThreshold ?? _enableAdaptiveThreshold;
    _maxNoiseFramesInSilence =
        maxNoiseFramesInSilence ?? _maxNoiseFramesInSilence;
    _maxSilenceFramesInSpeech =
        maxSilenceFramesInSpeech ?? _maxSilenceFramesInSpeech;

    _logger.i('🎙️ VAD initialized (Improved)');
    _logger.d('   Base threshold: $_energyThreshold');
    _logger.d('   Min speech frames: $_minSpeechFrames');
    _logger.d('   Min silence frames: $_minSilenceFrames');
    _logger.d('   Adaptive threshold: $_enableAdaptiveThreshold');
    _logger.d('   Max noise in silence: $_maxNoiseFramesInSilence');
  }

  /// Process audio frame for VAD
  void processFrame(Int16List pcm) {
    final energy = _calculateEnergy(pcm);

    // ✅ Update noise floor estimation
    if (_enableAdaptiveThreshold) {
      _updateNoiseFloor(energy);
    }

    // Determine threshold
    final threshold = _enableAdaptiveThreshold
        ? _noiseFloor * _adaptiveMultiplier
        : _energyThreshold;

    final hasVoice = energy > threshold;

    if (!_isSpeaking) {
      // Currently in SILENCE state
      if (hasVoice) {
        _speechFrameCount++;
        _noiseFramesInSilence++;

        // ✅ IMPROVED: Only reset silence if too many noise frames
        if (_noiseFramesInSilence > _maxNoiseFramesInSilence) {
          _silenceFrameCount = 0;
          _noiseFramesInSilence = 0;
        }

        // Confirm speech start
        if (_speechFrameCount >= _minSpeechFrames) {
          _isSpeaking = true;
          _speechFrameCount = 0;
          _silenceFrameCount = 0;
          _noiseFramesInSilence = 0;
          _silenceFramesInSpeech = 0;

          _vadStateController.add(true);
          _vadEventController.add(VadEvent.speechStart);
          _logger.d(
            '🎤 Speech detected (energy: ${energy.toStringAsFixed(4)}, threshold: ${threshold.toStringAsFixed(4)})',
          );
        }
      } else {
        // True silence
        _silenceFrameCount++;
        _speechFrameCount = 0;
        _noiseFramesInSilence = 0;
      }
    } else {
      // Currently in SPEECH state
      if (!hasVoice) {
        _silenceFrameCount++;
        _silenceFramesInSpeech++;

        // ✅ IMPROVED: Only reset speech if too many silence frames
        if (_silenceFramesInSpeech > _maxSilenceFramesInSpeech) {
          _speechFrameCount = 0;
          _silenceFramesInSpeech = 0;
        }

        // Confirm speech end
        if (_silenceFrameCount >= _minSilenceFrames) {
          _isSpeaking = false;
          _speechFrameCount = 0;
          _silenceFrameCount = 0;
          _noiseFramesInSilence = 0;
          _silenceFramesInSpeech = 0;

          _vadStateController.add(false);
          _vadEventController.add(VadEvent.speechEnd);
          _logger.d('🔇 Silence detected');
        }
      } else {
        // Continued speech
        _speechFrameCount++;
        _silenceFrameCount = 0;
        _silenceFramesInSpeech = 0;
      }
    }
  }

  /// ✅ NEW: Update noise floor using exponential moving average
  void _updateNoiseFloor(double energy) {
    _recentEnergies.add(energy);

    // Keep only recent energies
    if (_recentEnergies.length > _maxRecentEnergies) {
      _recentEnergies.removeAt(0);
    }

    // Calculate noise floor as 20th percentile of recent energies
    if (_recentEnergies.length >= 10) {
      final sorted = List<double>.from(_recentEnergies)..sort();
      final percentile20Index = (sorted.length * 0.2).floor();
      _noiseFloor = sorted[percentile20Index];

      // Ensure minimum threshold
      if (_noiseFloor < 0.005) {
        _noiseFloor = 0.005;
      }
    }
  }

  /// Calculate energy (RMS) of audio frame
  double _calculateEnergy(Int16List pcm) {
    if (pcm.isEmpty) return 0.0;

    double sum = 0;
    for (var sample in pcm) {
      final normalized = sample / 32768.0; // Normalize to -1.0 to 1.0
      sum += normalized * normalized;
    }

    final rms = math.sqrt(sum / pcm.length);
    return rms;
  }

  /// Reset VAD state
  void reset() {
    _isSpeaking = false;
    _speechFrameCount = 0;
    _silenceFrameCount = 0;
    _noiseFramesInSilence = 0;
    _silenceFramesInSpeech = 0;
    _logger.d('🔄 VAD reset');
  }

  /// ✅ NEW: Hard reset including noise floor
  void hardReset() {
    reset();
    _recentEnergies.clear();
    _noiseFloor = 0.0;
    _logger.d('🔄 VAD hard reset (including noise floor)');
  }

  /// Update configuration
  void updateConfig({
    double? energyThreshold,
    int? minSpeechFrames,
    int? minSilenceFrames,
    bool? enableAdaptiveThreshold,
    double? adaptiveMultiplier,
    int? maxNoiseFramesInSilence,
    int? maxSilenceFramesInSpeech,
  }) {
    if (energyThreshold != null) _energyThreshold = energyThreshold;
    if (minSpeechFrames != null) _minSpeechFrames = minSpeechFrames;
    if (minSilenceFrames != null) _minSilenceFrames = minSilenceFrames;
    if (enableAdaptiveThreshold != null)
      _enableAdaptiveThreshold = enableAdaptiveThreshold;
    if (adaptiveMultiplier != null) _adaptiveMultiplier = adaptiveMultiplier;
    if (maxNoiseFramesInSilence != null)
      _maxNoiseFramesInSilence = maxNoiseFramesInSilence;
    if (maxSilenceFramesInSpeech != null)
      _maxSilenceFramesInSpeech = maxSilenceFramesInSpeech;

    _logger.i('⚙️ VAD config updated');
  }

  /// Get current configuration
  Map<String, dynamic> getConfig() {
    return {
      'energy_threshold': _energyThreshold,
      'min_speech_frames': _minSpeechFrames,
      'min_silence_frames': _minSilenceFrames,
      'is_speaking': _isSpeaking,
      'speech_frame_count': _speechFrameCount,
      'silence_frame_count': _silenceFrameCount,
      'enable_adaptive': _enableAdaptiveThreshold,
      'noise_floor': _noiseFloor,
      'current_threshold': currentThreshold,
      'adaptive_multiplier': _adaptiveMultiplier,
      'max_noise_in_silence': _maxNoiseFramesInSilence,
      'max_silence_in_speech': _maxSilenceFramesInSpeech,
    };
  }

  /// Dispose
  void dispose() {
    _vadStateController.close();
    _vadEventController.close();
    _logger.i('🧹 VAD service disposed');
  }
}

/// VAD events
enum VadEvent { speechStart, speechEnd }
