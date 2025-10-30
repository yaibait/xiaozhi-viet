import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Welcome screen - Chọn giữa Demo Bot và My Bot
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0E27), Color(0xFF1A1F3A), Color(0xFF0A0E27)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              children: [
                Spacer(flex: 1),

                // Logo/Title
                _buildHeader(),

                SizedBox(height: 60),

                // Demo Bot Button
                _buildDemoButton(context),

                SizedBox(height: 24),

                // My Bot Button
                _buildMyBotButton(context),

                Spacer(flex: 2),

                // Footer
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Bot Icon
        Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [Colors.blue, Colors.purple]),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 30,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: Icon(Icons.smart_toy, size: 60, color: Colors.white),
            )
            .animate(onPlay: (controller) => controller.repeat())
            .shimmer(duration: 2000.ms, color: Colors.white.withOpacity(0.3))
            .shake(duration: 3000.ms, hz: 0.5, curve: Curves.easeInOut),

        SizedBox(height: 24),

        // Title
        Text(
          'Chào mừng đến với',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),

        SizedBox(height: 8),

        Text(
          'Voice Bot AI',
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.5, end: 0),
      ],
    );
  }

  Widget _buildDemoButton(BuildContext context) {
    return InkWell(
          onTap: () => _onDemoBot(context),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue, Colors.blue.shade700],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.4),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                Icon(Icons.rocket_launch, size: 48, color: Colors.white),
                SizedBox(height: 16),
                Text(
                  'Dùng thử Bot Demo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Trải nghiệm ngay không cần cấu hình',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        )
        .animate()
        .fadeIn(duration: 600.ms, delay: 200.ms)
        .slideX(begin: -0.3, end: 0);
  }

  Widget _buildMyBotButton(BuildContext context) {
    return InkWell(
          onTap: () => _onMyBot(context),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Icon(Icons.settings_suggest, size: 48, color: Colors.white),
                SizedBox(height: 16),
                Text(
                  'Cấu hình Bot của bạn',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Kích hoạt và tùy chỉnh bot riêng',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        )
        .animate()
        .fadeIn(duration: 600.ms, delay: 300.ms)
        .slideX(begin: 0.3, end: 0);
  }

  Widget _buildFooter() {
    return Text(
      'Powered by AI Voice Technology',
      style: TextStyle(color: Colors.white30, fontSize: 12),
    ).animate().fadeIn(duration: 600.ms, delay: 400.ms);
  }

  void _onDemoBot(BuildContext context) {
    // Navigate to bot screen with demo credentials
    Navigator.pushReplacementNamed(
      context,
      '/bot',
      arguments: {'mode': 'demo'},
    );
  }

  void _onMyBot(BuildContext context) {
    // Navigate to activation/bot screen with my bot mode
    Navigator.pushReplacementNamed(
      context,
      '/bot',
      arguments: {'mode': 'mybot'},
    );
  }
}
