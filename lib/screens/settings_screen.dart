import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight < 700;
    final horizontalPadding = isSmallScreen ? 16.0 : 20.0;
    final verticalSpacing = isSmallScreen ? 12.0 : 16.0;

    return Scaffold(
      backgroundColor: Color(0xFF0A0E27),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Cài đặt',
          style: TextStyle(
            color: Colors.white,
            fontSize: isSmallScreen ? 20 : 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          // Notify user interaction on any scroll
          return GestureDetector(
            onTap: () => settings.onUserInteraction(),
            onPanUpdate: (_) => settings.onUserInteraction(),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF0A0E27),
                    Color(0xFF1A1F3A),
                    Color(0xFF0A0E27),
                  ],
                ),
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(horizontalPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Screen Management Section
                    _buildSectionHeader(
                      icon: Icons.smartphone,
                      title: 'Quản lý màn hình',
                      color: Colors.blue,
                      isSmallScreen: isSmallScreen,
                    ),
                    SizedBox(height: verticalSpacing),

                    // Keep Screen On
                    _buildSettingCard(
                      icon: Icons.light_mode,
                      title: 'Giữ màn hình luôn sáng',
                      subtitle: 'Màn hình không tự động tắt',
                      trailing: Switch(
                        value: settings.keepScreenOn,
                        onChanged: (_) {
                          settings.toggleKeepScreenOn();
                          settings.onUserInteraction();
                        },
                        activeColor: Colors.blue,
                      ),
                      isSmallScreen: isSmallScreen,
                    ),

                    SizedBox(height: verticalSpacing * 0.75),

                    // Auto Dim Screen
                    _buildSettingCard(
                      icon: Icons.brightness_6,
                      title: 'Tự động giảm độ sáng',
                      subtitle: 'Tiết kiệm pin khi không tương tác',
                      trailing: Switch(
                        value: settings.autoDimScreen,
                        onChanged: (_) {
                          settings.toggleAutoDimScreen();
                          settings.onUserInteraction();
                        },
                        activeColor: Colors.blue,
                      ),
                      isSmallScreen: isSmallScreen,
                    ),

                    // Dim Settings (only show if auto dim is enabled)
                    if (settings.autoDimScreen) ...[
                      SizedBox(height: verticalSpacing * 1.25),
                      _buildSectionHeader(
                        icon: Icons.tune,
                        title: 'Cài đặt độ sáng',
                        color: Colors.purple,
                        isSmallScreen: isSmallScreen,
                      ),
                      SizedBox(height: verticalSpacing),

                      // Dim Delay
                      _buildDimDelayCard(settings, isSmallScreen),

                      SizedBox(height: verticalSpacing * 0.75),

                      // Normal Brightness
                      _buildBrightnessCard(
                        title: 'Độ sáng bình thường',
                        value: settings.normalBrightness,
                        onChanged: (value) {
                          settings.setNormalBrightness(value);
                          settings.onUserInteraction();
                        },
                        color: Colors.amber,
                        isSmallScreen: isSmallScreen,
                      ),

                      SizedBox(height: verticalSpacing * 0.75),

                      // Dimmed Brightness
                      _buildBrightnessCard(
                        title: 'Độ sáng khi giảm',
                        value: settings.dimmedBrightness,
                        onChanged: (value) {
                          settings.setDimmedBrightness(value);
                          settings.onUserInteraction();
                        },
                        color: Colors.indigo,
                        isSmallScreen: isSmallScreen,
                      ),
                    ],

                    SizedBox(height: verticalSpacing * 1.25),

                    // Status Info
                    _buildStatusCard(settings, isSmallScreen),

                    SizedBox(height: verticalSpacing * 1.25),

                    // Reset Button
                    _buildResetButton(context, settings, isSmallScreen),

                    SizedBox(height: verticalSpacing),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required Color color,
    required bool isSmallScreen,
  }) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(isSmallScreen ? 6 : 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: isSmallScreen ? 18 : 20),
        ),
        SizedBox(width: isSmallScreen ? 10 : 12),
        Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontSize: isSmallScreen ? 16 : 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
    required bool isSmallScreen,
  }) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isSmallScreen ? 8 : 10),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(isSmallScreen ? 10 : 12),
            ),
            child: Icon(
              icon,
              color: Colors.blue,
              size: isSmallScreen ? 20 : 24,
            ),
          ),
          SizedBox(width: isSmallScreen ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isSmallScreen ? 14 : 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: isSmallScreen ? 12 : 13,
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _buildDimDelayCard(SettingsProvider settings, bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.timer,
                color: Colors.orange,
                size: isSmallScreen ? 18 : 20,
              ),
              SizedBox(width: 8),
              Text(
                'Thời gian chờ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Spacer(),
              Text(
                '${settings.dimDelaySeconds}s',
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: isSmallScreen ? 8 : 12),
          Text(
            'Giảm độ sáng sau khi không tương tác',
            style: TextStyle(
              color: Colors.white60,
              fontSize: isSmallScreen ? 12 : 13,
            ),
          ),
          SizedBox(height: isSmallScreen ? 12 : 16),
          Slider(
            value: settings.dimDelaySeconds.toDouble(),
            min: 10,
            max: 300,
            divisions: 29,
            activeColor: Colors.orange,
            inactiveColor: Colors.white.withOpacity(0.2),
            onChanged: (value) {
              settings.setDimDelay(value.round());
              settings.onUserInteraction();
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '10s',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: isSmallScreen ? 11 : 12,
                ),
              ),
              Text(
                '5 phút',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: isSmallScreen ? 11 : 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBrightnessCard({
    required String title,
    required double value,
    required ValueChanged<double> onChanged,
    required Color color,
    required bool isSmallScreen,
  }) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                value > 0.5 ? Icons.wb_sunny : Icons.nightlight_round,
                color: color,
                size: isSmallScreen ? 18 : 20,
              ),
              SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Spacer(),
              Text(
                '${(value * 100).round()}%',
                style: TextStyle(
                  color: color,
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: isSmallScreen ? 12 : 16),
          Slider(
            value: value,
            min: 0.1,
            max: 1.0,
            divisions: 9,
            activeColor: color,
            inactiveColor: Colors.white.withOpacity(0.2),
            onChanged: onChanged,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '10%',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: isSmallScreen ? 11 : 12,
                ),
              ),
              Text(
                '100%',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: isSmallScreen ? 11 : 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(SettingsProvider settings, bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: settings.isScreenDimmed
              ? [Colors.indigo.withOpacity(0.3), Colors.purple.withOpacity(0.3)]
              : [Colors.green.withOpacity(0.3), Colors.teal.withOpacity(0.3)],
        ),
        borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
      ),
      child: Row(
        children: [
          Icon(
            settings.isScreenDimmed ? Icons.dark_mode : Icons.wb_sunny,
            color: Colors.white,
            size: isSmallScreen ? 28 : 32,
          ),
          SizedBox(width: isSmallScreen ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trạng thái hiện tại',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: isSmallScreen ? 12 : 13,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  settings.isScreenDimmed
                      ? 'Màn hình đang giảm độ sáng'
                      : 'Màn hình sáng bình thường',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isSmallScreen ? 14 : 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResetButton(
    BuildContext context,
    SettingsProvider settings,
    bool isSmallScreen,
  ) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          _showResetDialog(context, settings);
        },
        icon: Icon(Icons.restore, size: isSmallScreen ? 18 : 20),
        label: Text(
          'Đặt lại về mặc định hệ thống',
          style: TextStyle(fontSize: isSmallScreen ? 13 : 14),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red.withOpacity(0.2),
          foregroundColor: Colors.red,
          padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 12 : 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.red.withOpacity(0.5)),
          ),
        ),
      ),
    );
  }

  void _showResetDialog(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF1A1F3A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Đặt lại cài đặt', style: TextStyle(color: Colors.white)),
        content: Text(
          'Độ sáng sẽ được đặt lại về mặc định của hệ thống. Bạn có chắc chắn?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Hủy', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () {
              settings.resetBrightnessToSystem();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Đã đặt lại độ sáng về mặc định'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Đặt lại'),
          ),
        ],
      ),
    );
  }
}
