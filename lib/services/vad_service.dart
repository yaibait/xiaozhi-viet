import 'dart:async';
import 'dart:typed_data';
import 'package:logger/logger.dart';

/// Voice Activity Detection (VAD) service
/// Detects when user is speaking vs silence
class VadService {
  final Logger _logger = Logger();
  
  // VAD configuration
  double _energyThreshold = 0.02; // Energy threshold for speech detection
  int _minSpeechFrames = 3;       // Minimum frames to confirm speech
  int _minSilenceFrames = 10;     // Minimum frames to confirm silence
  
  // State
  bool _isSpeaking = false;
  int _speechFrameCount = 0;
  int _silenceFrameCount = 0;
  
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
  
  VadService({
    double? energyThreshold,
    int? minSpeechFrames,
    int? minSilenceFrames,
  }) {
    _energyThreshold = energyThreshold ?? _energyThreshold;
    _minSpeechFrames = minSpeechFrames ?? _minSpeechFrames;
    _minSilenceFrames = minSilenceFrames ?? _minSilenceFrames;
    
    _logger.i('🎙️ VAD initialized');
    _logger.d('   Energy threshold: $_energyThreshold');
    _logger.d('   Min speech frames: $_minSpeechFrames');
    _logger.d('   Min silence frames: $_minSilenceFrames');
  }
  
  /// Process audio frame for VAD
  void processFrame(Int16List pcm) {
    final energy = _calculateEnergy(pcm);
    final hasVoice = energy > _energyThreshold;
    
    if (hasVoice) {
      _speechFrameCount++;
      _silenceFrameCount = 0;
      
      // Confirm speech start
      if (!_isSpeaking && _speechFrameCount >= _minSpeechFrames) {
        _isSpeaking = true;
        _vadStateController.add(true);
        _vadEventController.add(VadEvent.speechStart);
        _logger.d('🎤 Speech detected');
      }
    } else {
      _silenceFrameCount++;
      _speechFrameCount = 0;
      
      // Confirm speech end
      if (_isSpeaking && _silenceFrameCount >= _minSilenceFrames) {
        _isSpeaking = false;
        _vadStateController.add(false);
        _vadEventController.add(VadEvent.speechEnd);
        _logger.d('🔇 Silence detected');
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
    
    final rms = sum / pcm.length;
    return rms.squareRoot;
  }
  
  /// Reset VAD state
  void reset() {
    _isSpeaking = false;
    _speechFrameCount = 0;
    _silenceFrameCount = 0;
    _logger.d('🔄 VAD reset');
  }
  
  /// Update configuration
  void updateConfig({
    double? energyThreshold,
    int? minSpeechFrames,
    int? minSilenceFrames,
  }) {
    if (energyThreshold != null) _energyThreshold = energyThreshold;
    if (minSpeechFrames != null) _minSpeechFrames = minSpeechFrames;
    if (minSilenceFrames != null) _minSilenceFrames = minSilenceFrames;
    
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
enum VadEvent {
  speechStart,
  speechEnd,
}

// Math helper for square root
extension on double {
  double get squareRoot {
    if (this == 0) return 0;
    if (this < 0) return 0;
    
    double x = this;
    double y = 1;
    double e = 0.000001;
    
    while ((x - y).abs() > e) {
      x = (x + y) / 2;
      y = this / x;
    }
    
    return x;
  }
}
