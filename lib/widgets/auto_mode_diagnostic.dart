import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/bot_provider.dart';

/// Diagnostic overlay để debug Auto Mode
/// Hiển thị thông tin real-time về VAD, recording, state
class AutoModeDiagnostic extends StatefulWidget {
  @override
  _AutoModeDiagnosticState createState() => _AutoModeDiagnosticState();
}

class _AutoModeDiagnosticState extends State<AutoModeDiagnostic> {
  Timer? _updateTimer;
  int _vadEventCount = 0;
  int _pcmFrameCount = 0;
  DateTime? _lastVadEvent;
  DateTime? _lastPcmFrame;

  @override
  void initState() {
    super.initState();
    _setupListeners();

    // Update UI every second
    _updateTimer = Timer.periodic(Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _setupListeners() {
    final bot = Provider.of<BotProvider>(context, listen: false);

    // Count VAD events
    bot.vadService.vadEventStream.listen((_) {
      setState(() {
        _vadEventCount++;
        _lastVadEvent = DateTime.now();
      });
    });

    // Count PCM frames
    bot.audioService.pcmDataStream.listen((_) {
      _pcmFrameCount++;
      _lastPcmFrame = DateTime.now();

      // Update UI every 30 frames
      if (_pcmFrameCount % 30 == 0) {
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BotProvider>(
      builder: (context, bot, child) {
        final vadConfig = bot.vadService.getConfig();
        final timeSinceLastVad = _lastVadEvent != null
            ? DateTime.now().difference(_lastVadEvent!).inSeconds
            : null;
        final timeSinceLastPcm = _lastPcmFrame != null
            ? DateTime.now().difference(_lastPcmFrame!).inSeconds
            : null;

        return Container(
          padding: EdgeInsets.all(12),
          margin: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.bug_report, color: Colors.green, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'AUTO MODE DIAGNOSTIC',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),

              Divider(color: Colors.green),

              // Status
              _buildRow(
                'Auto Mode',
                bot.autoVoiceMode ? 'ON' : 'OFF',
                bot.autoVoiceMode ? Colors.green : Colors.red,
              ),
              _buildRow(
                'Monitoring',
                bot.isMonitoringVoice ? 'YES' : 'NO',
                bot.isMonitoringVoice ? Colors.green : Colors.red,
              ),
              _buildRow(
                'Recording',
                bot.audioService.isRecording ? 'YES' : 'NO',
                bot.audioService.isRecording ? Colors.green : Colors.red,
              ),
              _buildRow(
                'State',
                bot.state.toString().split('.').last.toUpperCase(),
                _getStateColor(bot.state),
              ),
              _buildRow(
                'Connected',
                bot.isConnected ? 'YES' : 'NO',
                bot.isConnected ? Colors.green : Colors.red,
              ),

              Divider(color: Colors.green),

              // Counters
              _buildRow('VAD Events', '$_vadEventCount', Colors.white),
              _buildRow('PCM Frames', '$_pcmFrameCount', Colors.white),
              _buildRow(
                'Last VAD',
                timeSinceLastVad != null ? '${timeSinceLastVad}s ago' : 'Never',
                timeSinceLastVad != null && timeSinceLastVad < 5
                    ? Colors.green
                    : Colors.orange,
              ),
              _buildRow(
                'Last PCM',
                timeSinceLastPcm != null ? '${timeSinceLastPcm}s ago' : 'Never',
                timeSinceLastPcm != null && timeSinceLastPcm < 2
                    ? Colors.green
                    : Colors.red,
              ),

              Divider(color: Colors.green),

              // VAD Config
              _buildRow(
                'VAD Speaking',
                '${vadConfig['is_speaking']}',
                vadConfig['is_speaking'] ? Colors.green : Colors.white,
              ),
              _buildRow(
                'Speech Count',
                '${vadConfig['speech_frame_count']}',
                Colors.white,
              ),
              _buildRow(
                'Silence Count',
                '${vadConfig['silence_frame_count']}',
                Colors.white,
              ),
              _buildRow(
                'Energy Threshold',
                '${vadConfig['energy_threshold']}',
                Colors.white,
              ),

              // Warnings
              if (bot.autoVoiceMode && !bot.audioService.isRecording)
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.red, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '⚠️ Recording stopped! Auto mode won\'t work.',
                            style: TextStyle(color: Colors.red, fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (bot.autoVoiceMode &&
                  timeSinceLastPcm != null &&
                  timeSinceLastPcm > 3)
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '⚠️ No PCM data for ${timeSinceLastPcm}s. Check microphone!',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRow(String label, String value, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$label:', style: TextStyle(color: Colors.grey, fontSize: 11)),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStateColor(BotState state) {
    switch (state) {
      case BotState.idle:
        return Colors.white;
      case BotState.listening:
        return Colors.blue;
      case BotState.thinking:
        return Colors.orange;
      case BotState.speaking:
        return Colors.green;
      case BotState.error:
        return Colors.red;
    }
  }
}

/// Simple button để toggle diagnostic
class DiagnosticToggleButton extends StatefulWidget {
  @override
  _DiagnosticToggleButtonState createState() => _DiagnosticToggleButtonState();
}

class _DiagnosticToggleButtonState extends State<DiagnosticToggleButton> {
  bool _showDiagnostic = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Toggle button
        Positioned(
          top: 100,
          right: 16,
          child: FloatingActionButton(
            mini: true,
            backgroundColor: Colors.green.withOpacity(0.8),
            child: Icon(Icons.bug_report, size: 20),
            onPressed: () {
              setState(() {
                _showDiagnostic = !_showDiagnostic;
              });
            },
          ),
        ),

        // Diagnostic overlay
        if (_showDiagnostic)
          Positioned(
            top: 150,
            right: 16,
            left: 16,
            child: AutoModeDiagnostic(),
          ),
      ],
    );
  }
}
