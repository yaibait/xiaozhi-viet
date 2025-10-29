import 'package:flutter/material.dart';
import 'package:animated_text_kit/animated_text_kit.dart';

/// Text display widget
class TextDisplay extends StatelessWidget {
  final String text;
  final bool isUser;
  
  const TextDisplay({
    super.key,
    required this.text,
    this.isUser = false,
  });
  
  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return Center(
        child: Text(
          isUser ? 'Tap to speak...' : 'Listening...',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 16,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    
    return Center(
      child: AnimatedTextKit(
        key: ValueKey(text),
        animatedTexts: [
          TypewriterAnimatedText(
            text,
            textAlign: TextAlign.center,
            textStyle: TextStyle(
              color: isUser ? Colors.white : Colors.blue.shade200,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
            speed: Duration(milliseconds: 50),
          ),
        ],
        totalRepeatCount: 1,
        displayFullTextOnTap: true,
      ),
    );
  }
}
