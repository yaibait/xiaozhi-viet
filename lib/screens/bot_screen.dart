import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/bot_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/bot_avatar.dart';
import '../widgets/voice_button.dart';
import '../widgets/text_display.dart';
import 'chat_screen.dart';

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
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenHeight < 700;

    return Scaffold(
      backgroundColor: Color(0xFF0A0E27),
      body: SafeArea(
        child: Consumer2<BotProvider, SettingsProvider>(
          builder: (context, bot, settings, child) {
            return GestureDetector(
              // ✅ Detect user interactions for auto-dim
              onTap: () => settings.onUserInteraction(),
              onPanUpdate: (_) => settings.onUserInteraction(),
              behavior: HitTestBehavior.translucent,
              child: Stack(
                children: [
                  // Background gradient
                  _buildBackground(),

                  // Main content - sử dụng Column với Flexible thay vì Spacer
                  Column(
                    children: [
                      // Top bar - fixed height
                      _buildTopBar(context, bot),

                      // Demo mode banner - fixed height
                      if (bot.isDemoMode) _buildDemoBanner(context, bot),

                      // Flexible space top
                      Flexible(
                        flex: isSmallScreen ? 1 : 2,
                        child: SizedBox.shrink(),
                      ),

                      // Bot avatar - dynamic size based on screen
                      _buildBotAvatar(bot, isSmallScreen),

                      SizedBox(height: isSmallScreen ? 16 : 32),

                      // Text display - constrained height
                      _buildTextDisplay(bot, isSmallScreen),

                      // Flexible space bottom (larger)
                      Flexible(
                        flex: isSmallScreen ? 2 : 3,
                        child: SizedBox.shrink(),
                      ),

                      // Voice button
                      _buildVoiceButton(bot, settings),

                      SizedBox(height: isSmallScreen ? 16 : 32),

                      // Bottom buttons
                      _buildBottomButtons(bot),

                      SizedBox(height: isSmallScreen ? 16 : 20),
                    ],
                  ),

                  // Activation overlay
                  if (!bot.isActivated) _buildActivationOverlay(bot),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Demo mode banner
  Widget _buildDemoBanner(BuildContext context, BotProvider bot) {
    final isSmallScreen = MediaQuery.of(context).size.height < 700;

    return Container(
          margin: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 12 : 16,
            vertical: isSmallScreen ? 6 : 8,
          ),
          padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade700, Colors.blue.shade900],
            ),
            borderRadius: BorderRadius.circular(isSmallScreen ? 10 : 12),
            border: Border.all(color: Colors.blue.shade300, width: 2),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: Colors.white,
                size: isSmallScreen ? 18 : 20,
              ),
              SizedBox(width: isSmallScreen ? 10 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Đang dùng Bot Demo',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: isSmallScreen ? 13 : 14,
                      ),
                    ),
                    if (!isSmallScreen) ...[
                      SizedBox(height: 4),
                      Text(
                        'Nâng cấp lên Bot của bạn để có trải nghiệm tốt hơn',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 8),
              InkWell(
                onTap: () {
                  _showUpgradeDialog(context, bot);
                },
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 10 : 12,
                    vertical: isSmallScreen ? 5 : 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Nâng cấp',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.bold,
                      fontSize: isSmallScreen ? 11 : 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        )
        .animate(onPlay: (controller) => controller.repeat())
        .shimmer(duration: 2000.ms, color: Colors.white.withOpacity(0.2));
  }

  /// Show upgrade dialog
  void _showUpgradeDialog(BuildContext context, BotProvider bot) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF1A1F3A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.rocket_launch, color: Colors.blue),
            SizedBox(width: 12),
            Text(
              'Nâng cấp lên Bot của bạn',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Với Bot của bạn, bạn sẽ có:',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            SizedBox(height: 12),
            _buildBenefit('Tùy chỉnh hoàn toàn theo ý bạn'),
            _buildBenefit('Giọng nói và tính cách riêng'),
            _buildBenefit('Lưu trữ lịch sử hội thoại'),
            _buildBenefit('Không giới hạn sử dụng'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Để sau', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await bot.switchToMyBot();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text('Nâng cấp ngay'),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefit(String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
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

  /// Top bar với connection status và Settings button
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

          // Right buttons
          Row(
            children: [
              // Settings button
              IconButton(
                icon: Icon(Icons.settings, color: Colors.white70),
                onPressed: () {
                  Navigator.pushNamed(context, '/settings');
                },
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
        ],
      ),
    );
  }

  /// Bot avatar với animations
  Widget _buildBotAvatar(BotProvider bot, bool isSmallScreen) {
    // Tính toán kích thước avatar dựa trên cả chiều cao và chiều rộng
    double avatarSize = isSmallScreen ? 120.0 : 180.0;

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
            child: BotAvatar(emotion: bot.emotion, size: avatarSize),
          ),
        );
      },
    );
  }

  /// Text display
  Widget _buildTextDisplay(BotProvider bot, bool isSmallScreen) {
    return Container(
      constraints: BoxConstraints(
        minHeight: isSmallScreen ? 60 : 80,
        maxHeight: isSmallScreen ? 100 : 120,
      ),
      padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 20 : 32),
      child: TextDisplay(
        text: bot.isSpeaking ? bot.currentTtsText : bot.currentAsrText,
        isUser: !bot.isSpeaking,
      ),
    );
  }

  /// Voice button with user interaction tracking
  Widget _buildVoiceButton(BotProvider bot, SettingsProvider settings) {
    return GestureDetector(
      onTap: () {
        settings.onUserInteraction();
        if (bot.isConnected) {
          bot.toggleListening();
        }
      },
      child: VoiceButton(
        isListening: bot.isListening,
        isConnected: bot.isConnected,
        onTap: () {
          settings.onUserInteraction();
          if (bot.isConnected) {
            bot.toggleListening();
          }
        },
      ),
    );
  }

  /// Bottom buttons
  Widget _buildBottomButtons(BotProvider bot) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Auto voice mode toggle
          _buildActionButton(
            icon: bot.autoVoiceMode ? Icons.mic_off : Icons.mic,
            label: bot.autoVoiceMode ? 'Tắt Auto' : 'Bật Auto',
            onPressed: bot.isConnected ? () => bot.toggleAutoVoiceMode() : null,
            color: bot.autoVoiceMode ? Colors.red : Colors.green,
          ),

          // Clear messages
          _buildActionButton(
            icon: Icons.delete_outline,
            label: 'Xóa',
            onPressed: bot.messages.isNotEmpty
                ? () => bot.clearMessages()
                : null,
            color: Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required Color color,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmallScreen = MediaQuery.of(context).size.height < 700;

        return InkWell(
          onTap: onPressed,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 16 : 20,
              vertical: isSmallScreen ? 10 : 12,
            ),
            decoration: BoxDecoration(
              color: onPressed != null
                  ? color.withOpacity(0.2)
                  : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(isSmallScreen ? 16 : 20),
              border: Border.all(
                color: onPressed != null ? color : Colors.grey.shade800,
                width: 2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: onPressed != null ? color : Colors.grey.shade700,
                  size: isSmallScreen ? 18 : 20,
                ),
                SizedBox(width: isSmallScreen ? 6 : 8),
                Text(
                  label,
                  style: TextStyle(
                    color: onPressed != null ? color : Colors.grey.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: isSmallScreen ? 13 : 14,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Activation overlay
  Widget _buildActivationOverlay(BotProvider bot) {
    return Container(
      color: Colors.black.withOpacity(0.9),
      child: Center(
        child: Container(
          margin: EdgeInsets.all(32),
          padding: EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade900, Colors.purple.shade900],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.5),
                blurRadius: 30,
                spreadRadius: 10,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.qr_code_2, size: 80, color: Colors.white),
              SizedBox(height: 24),
              Text(
                'Kích hoạt Bot',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Quét mã QR bằng ứng dụng Xiaozhi hoặc nhập mã sau:',
                style: TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 24),
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  bot.activationCode ?? 'Loading...',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                  ),
                ),
              ),
              SizedBox(height: 24),
              Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Đang chờ kích hoạt...',
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                  .animate(onPlay: (controller) => controller.repeat())
                  .fadeIn(duration: 1000.ms)
                  .then()
                  .fadeOut(duration: 1000.ms),
            ],
          ),
        ),
      ),
    );
  }
}
