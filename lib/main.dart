import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/bot_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/welcome_screen.dart';
import 'screens/bot_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  runApp(const XiaozhiBotApp());
}

class XiaozhiBotApp extends StatelessWidget {
  const XiaozhiBotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BotProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(
        title: 'Xiaozhi Bot',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        // ✅ Sử dụng home thay vì initialRoute để kiểm tra trạng thái
        home: SplashScreen(),
        routes: {
          '/welcome': (context) => WelcomeScreen(),
          '/bot': (context) => BotScreenWrapper(),
          '/settings': (context) => SettingsScreen(),
        },
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

/// Splash screen để kiểm tra xem đã kích hoạt bot chưa
class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkActivationStatus();
  }

  Future<void> _checkActivationStatus() async {
    // Đợi một chút cho animation
    await Future.delayed(Duration(milliseconds: 500));

    final prefs = await SharedPreferences.getInstance();
    final hasActivatedOwnBot = prefs.getBool('has_activated_own_bot') ?? false;

    if (!mounted) return;

    if (hasActivatedOwnBot) {
      // ✅ Đã kích hoạt bot riêng -> Vào thẳng màn hình bot
      Navigator.pushReplacementNamed(
        context,
        '/bot',
        arguments: {'mode': 'mybot'},
      );
    } else {
      // ❌ Chưa kích hoạt -> Hiển thị màn hình welcome
      Navigator.pushReplacementNamed(context, '/welcome');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Màn hình loading đơn giản
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0E27), Color(0xFF1A1F3A), Color(0xFF0A0E27)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Bot Icon
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Colors.blue, Colors.purple],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 30,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: Icon(Icons.smart_toy, size: 50, color: Colors.white),
              ),
              SizedBox(height: 24),
              // Loading indicator
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
              SizedBox(height: 16),
              Text(
                'Đang khởi động...',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wrapper to handle bot initialization with mode
class BotScreenWrapper extends StatefulWidget {
  @override
  _BotScreenWrapperState createState() => _BotScreenWrapperState();
}

class _BotScreenWrapperState extends State<BotScreenWrapper> {
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_initialized) {
      _initialized = true;
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      final mode = args?['mode'] ?? 'mybot';

      // Initialize bot with selected mode
      final bot = Provider.of<BotProvider>(context, listen: false);
      bot.initialize(mode: mode);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BotScreen();
  }
}
