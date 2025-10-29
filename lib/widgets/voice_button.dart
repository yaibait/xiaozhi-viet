import 'package:flutter/material.dart';

/// Voice button để bắt đầu/dừng listening
class VoiceButton extends StatelessWidget {
  final bool isListening;
  final bool isConnected;
  final VoidCallback onTap;
  
  const VoiceButton({
    super.key,
    required this.isListening,
    required this.isConnected,
    required this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isConnected ? onTap : null,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 300),
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isListening ? Colors.red : Colors.blue,
          boxShadow: [
            BoxShadow(
              color: (isListening ? Colors.red : Colors.blue).withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: isListening ? 10 : 5,
            ),
          ],
        ),
        child: Icon(
          isListening ? Icons.stop : Icons.mic,
          color: Colors.white,
          size: 40,
        ),
      ),
    );
  }
}
