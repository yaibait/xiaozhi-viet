import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/bot_provider.dart';
import 'screens/bot_screen.dart';

void main() {
  runApp(const XiaozhiBotApp());
}

class XiaozhiBotApp extends StatelessWidget {
  const XiaozhiBotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BotProvider()..initialize(),
      child: MaterialApp(
        title: 'Xiaozhi Bot',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        home: const BotScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
