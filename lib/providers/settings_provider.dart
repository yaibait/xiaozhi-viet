import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'dart:async';
import 'package:logger/logger.dart';

class SettingsProvider extends ChangeNotifier {
  final Logger _logger = Logger();

  // Settings state
  bool _keepScreenOn = false;
  bool _autoDimScreen = true;
  double _normalBrightness = 1.0;
  double _dimmedBrightness = 0.3;
  int _dimDelaySeconds = 30;

  // Private
  Timer? _dimTimer;
  DateTime? _lastInteractionTime;
  bool _isScreenDimmed = false;
  double? _originalBrightness;

  // Getters
  bool get keepScreenOn => _keepScreenOn;
  bool get autoDimScreen => _autoDimScreen;
  double get normalBrightness => _normalBrightness;
  double get dimmedBrightness => _dimmedBrightness;
  int get dimDelaySeconds => _dimDelaySeconds;
  bool get isScreenDimmed => _isScreenDimmed;

  SettingsProvider() {
    _loadSettings();
  }

  /// Load settings from SharedPreferences
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      _keepScreenOn = prefs.getBool('keep_screen_on') ?? false;
      _autoDimScreen = prefs.getBool('auto_dim_screen') ?? true;
      _normalBrightness = prefs.getDouble('normal_brightness') ?? 1.0;
      _dimmedBrightness = prefs.getDouble('dimmed_brightness') ?? 0.3;
      _dimDelaySeconds = prefs.getInt('dim_delay_seconds') ?? 30;

      // Apply settings
      await _applyKeepScreenOn();
      if (_autoDimScreen) {
        _startDimTimer();
      }

      // Get current brightness
      try {
        _originalBrightness = await ScreenBrightness().current;
      } catch (e) {
        _logger.e('❌ Failed to get current brightness: $e');
      }

      notifyListeners();
    } catch (e) {
      _logger.e('❌ Error loading settings: $e');
    }
  }

  /// Toggle keep screen on
  Future<void> toggleKeepScreenOn() async {
    _keepScreenOn = !_keepScreenOn;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('keep_screen_on', _keepScreenOn);

    await _applyKeepScreenOn();

    _logger.i('🔆 Keep screen on: $_keepScreenOn');
    notifyListeners();
  }

  /// Apply keep screen on setting
  Future<void> _applyKeepScreenOn() async {
    try {
      if (_keepScreenOn) {
        await WakelockPlus.enable();
        _logger.i('✅ Wakelock enabled');
      } else {
        await WakelockPlus.disable();
        _logger.i('✅ Wakelock disabled');
      }
    } catch (e) {
      _logger.e('❌ Error applying wakelock: $e');
    }
  }

  /// Toggle auto dim screen
  Future<void> toggleAutoDimScreen() async {
    _autoDimScreen = !_autoDimScreen;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_dim_screen', _autoDimScreen);

    if (_autoDimScreen) {
      _startDimTimer();
    } else {
      _stopDimTimer();
      // Restore brightness if dimmed
      if (_isScreenDimmed) {
        await _restoreBrightness();
      }
    }

    _logger.i('🔆 Auto dim screen: $_autoDimScreen');
    notifyListeners();
  }

  /// Set dim delay in seconds
  Future<void> setDimDelay(int seconds) async {
    _dimDelaySeconds = seconds;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('dim_delay_seconds', seconds);

    // Restart timer if auto dim is enabled
    if (_autoDimScreen) {
      _stopDimTimer();
      _startDimTimer();
    }

    _logger.i('⏱️ Dim delay set to: $seconds seconds');
    notifyListeners();
  }

  /// Set normal brightness (0.0 - 1.0)
  Future<void> setNormalBrightness(double brightness) async {
    _normalBrightness = brightness.clamp(0.0, 1.0);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('normal_brightness', _normalBrightness);

    // Apply immediately if not dimmed
    if (!_isScreenDimmed) {
      await _setBrightness(_normalBrightness);
    }

    notifyListeners();
  }

  /// Set dimmed brightness (0.0 - 1.0)
  Future<void> setDimmedBrightness(double brightness) async {
    _dimmedBrightness = brightness.clamp(0.0, 1.0);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('dimmed_brightness', _dimmedBrightness);

    // Apply immediately if currently dimmed
    if (_isScreenDimmed) {
      await _setBrightness(_dimmedBrightness);
    }

    notifyListeners();
  }

  /// User interaction detected - reset dim timer
  void onUserInteraction() {
    _lastInteractionTime = DateTime.now();

    // Restore brightness if dimmed
    if (_isScreenDimmed) {
      _restoreBrightness();
    }

    // Restart timer
    if (_autoDimScreen) {
      _stopDimTimer();
      _startDimTimer();
    }
  }

  /// Start dim timer
  void _startDimTimer() {
    _lastInteractionTime = DateTime.now();

    _dimTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_lastInteractionTime == null) return;

      final elapsed = DateTime.now()
          .difference(_lastInteractionTime!)
          .inSeconds;

      if (elapsed >= _dimDelaySeconds && !_isScreenDimmed) {
        _dimScreen();
      }
    });

    _logger.i('⏱️ Dim timer started (delay: $_dimDelaySeconds seconds)');
  }

  /// Stop dim timer
  void _stopDimTimer() {
    _dimTimer?.cancel();
    _dimTimer = null;
    _logger.i('⏱️ Dim timer stopped');
  }

  /// Dim the screen
  Future<void> _dimScreen() async {
    if (_isScreenDimmed) return;

    try {
      await _setBrightness(_dimmedBrightness);
      _isScreenDimmed = true;
      _logger.i('🌙 Screen dimmed to: $_dimmedBrightness');
      notifyListeners();
    } catch (e) {
      _logger.e('❌ Error dimming screen: $e');
    }
  }

  /// Restore brightness
  Future<void> _restoreBrightness() async {
    if (!_isScreenDimmed) return;

    try {
      await _setBrightness(_normalBrightness);
      _isScreenDimmed = false;
      _logger.i('☀️ Screen brightness restored to: $_normalBrightness');
      notifyListeners();
    } catch (e) {
      _logger.e('❌ Error restoring brightness: $e');
    }
  }

  /// Set screen brightness
  Future<void> _setBrightness(double brightness) async {
    try {
      await ScreenBrightness().setScreenBrightness(brightness);
    } catch (e) {
      _logger.e('❌ Error setting brightness: $e');
    }
  }

  /// Reset brightness to system default
  Future<void> resetBrightnessToSystem() async {
    try {
      await ScreenBrightness().resetScreenBrightness();
      _isScreenDimmed = false;
      _logger.i('🔄 Brightness reset to system default');
      notifyListeners();
    } catch (e) {
      _logger.e('❌ Error resetting brightness: $e');
    }
  }

  @override
  void dispose() {
    _stopDimTimer();

    // Disable wakelock on dispose
    WakelockPlus.disable();

    // Reset brightness to system default
    resetBrightnessToSystem();

    super.dispose();
  }
}
