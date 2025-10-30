import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/bot_provider.dart';
import '../widgets/bot_avatar.dart';
import '../widgets/voice_button.dart';
import '../widgets/text_display.dart';
import 'chat_screen.dart';
import '../widgets/auto_mode_diagnostic.dart';

/// Main bot screen - Màn hình chính với bot animation
class BotScreen extends StatefulWidget {
  const BotScreen({super.key});

  @override
  State<BotScreen> createState() => _BotScreenState();
}

class _BotScreenState extends State<BotScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _bounceController;

  @override
  void initState() {
    super.initState();

    // Pulse animation for listening state
    _pulseController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Bounce animation for speaking state
    _bounceController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0A0E27),
      body: SafeArea(
        child: Consumer<BotProvider>(
          builder: (context, bot, child) {
            return Stack(
              children: [
                // Background gradient
                _buildBackground(),

                // Main content
                Column(
                  children: [
                    // Top bar
                    _buildTopBar(context, bot),

                    Spacer(flex: 1),

                    // Bot avatar
                    _buildBotAvatar(bot),

                    SizedBox(height: 40),

                    // Text display
                    _buildTextDisplay(bot),

                    Spacer(flex: 2),

                    // Voice button
                    _buildVoiceButton(bot),

                    SizedBox(height: 40),

                    // Bottom buttons
                    _buildBottomButtons(bot),

                    SizedBox(height: 20),
                  ],
                ),
                DiagnosticToggleButton(),
                // Activation overlay
                if (!bot.isActivated) _buildActivationOverlay(bot),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Background gradient
  Widget _buildBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A0E27), Color(0xFF1A1F3A), Color(0xFF0A0E27)],
        ),
      ),
    );
  }

  /// Top bar với connection status
  Widget _buildTopBar(BuildContext context, BotProvider bot) {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Connection & Monitoring status
          Row(
            children: [
              // Connection status
              Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: bot.isConnected ? Colors.green : Colors.red,
                    ),
                  )
                  .animate(onPlay: (controller) => controller.repeat())
                  .fadeIn(duration: 500.ms)
                  .then()
                  .fadeOut(duration: 500.ms),
              SizedBox(width: 8),
              Text(
                bot.isConnected ? 'Connected' : 'Disconnected',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),

              // Auto mode indicator
              if (bot.autoVoiceMode) ...[
                SizedBox(width: 16),
                Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.greenAccent, width: 1),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.mic, color: Colors.greenAccent, size: 12),
                          SizedBox(width: 4),
                          Text(
                            'Auto Mode',
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                    .animate(onPlay: (controller) => controller.repeat())
                    .shimmer(
                      duration: 2000.ms,
                      color: Colors.greenAccent.withOpacity(0.3),
                    ),
              ],
            ],
          ),

          // Chat button
          IconButton(
            icon: Icon(Icons.chat_bubble_outline, color: Colors.white70),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ChatScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Bot avatar với animations
  Widget _buildBotAvatar(BotProvider bot) {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseController, _bounceController]),
      builder: (context, child) {
        double scale = 1.0;
        double opacity = 1.0;

        if (bot.state == BotState.listening) {
          scale = 1.0 + (_pulseController.value * 0.2);
          opacity = 0.7 + (_pulseController.value * 0.3);
        } else if (bot.state == BotState.speaking) {
          scale = 1.0 + (_bounceController.value * 0.1);
        }

        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: BotAvatar(emotion: bot.emotion, size: 200),
          ),
        );
      },
    );
  }

  /// Text display area
  Widget _buildTextDisplay(BotProvider bot) {
    return Container(
      height: 120,
      padding: EdgeInsets.symmetric(horizontal: 32),
      child: TextDisplay(
        text: bot.isSpeaking ? bot.currentTtsText : bot.currentAsrText,
        isUser: !bot.isSpeaking,
      ),
    );
  }

  /// Voice button
  Widget _buildVoiceButton(BotProvider bot) {
    return VoiceButton(
      isListening: bot.isListening,
      isConnected: bot.isConnected,
      onTap: () {
        if (bot.isConnected) {
          bot.toggleListening();
        }
      },
    );
  }

  /// Bottom buttons
  Widget _buildBottomButtons(BotProvider bot) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Auto Voice Mode
        _buildIconButton(
          icon: bot.autoVoiceMode ? Icons.mic : Icons.mic_off,
          label: 'Auto Mode',
          color: bot.autoVoiceMode ? Colors.greenAccent : Colors.white54,
          isActive: bot.autoVoiceMode,
          onTap: () {
            bot.toggleAutoVoiceMode();
          },
        ),

        SizedBox(width: 40),

        // Settings
        _buildIconButton(
          icon: Icons.settings,
          label: 'Settings',
          onTap: () {
            // TODO: Open settings
          },
        ),

        SizedBox(width: 40),

        // Clear messages
        _buildIconButton(
          icon: Icons.delete_outline,
          label: 'Clear',
          onTap: () {
            bot.clearMessages();
          },
        ),
      ],
    );
  }

  /// Icon button widget
  Widget _buildIconButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
    bool isActive = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(isActive ? 12 : 0),
            decoration: isActive
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.greenAccent.withOpacity(0.2),
                    border: Border.all(color: Colors.greenAccent, width: 2),
                  )
                : null,
            child: Icon(icon, color: color ?? Colors.white54, size: 24),
          ),
          SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color ?? Colors.white54,
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  /// Activation overlay
  Widget _buildActivationOverlay(BotProvider bot) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, color: Colors.white, size: 80)
                .animate(onPlay: (controller) => controller.repeat())
                .scale(duration: 1000.ms)
                .then()
                .scale(begin: Offset(1.2, 1.2), end: Offset(1.0, 1.0)),

            SizedBox(height: 40),

            Text(
              'Device Activation Required',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

            SizedBox(height: 20),

            if (bot.activationCode != null) ...[
              Text(
                'Enter this code at',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),

              SizedBox(height: 8),

              Text(
                'xiaozhi.me/console',
                style: TextStyle(
                  color: Colors.blue,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

              SizedBox(height: 30),

              Container(
                    padding: EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white30),
                    ),
                    child: Text(
                      bot.activationCode!.split('').join('  '),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                      ),
                    ),
                  )
                  .animate(onPlay: (controller) => controller.repeat())
                  .shimmer(duration: 2000.ms, color: Colors.white24),

              SizedBox(height: 40),

              Text(
                    'Waiting for activation...',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  )
                  .animate(onPlay: (controller) => controller.repeat())
                  .fadeIn(duration: 1000.ms)
                  .then()
                  .fadeOut(duration: 1000.ms),
            ],
          ],
        ),
      ),
    );
  }
}
