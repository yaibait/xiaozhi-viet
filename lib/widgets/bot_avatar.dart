import 'package:flutter/material.dart';
import '../providers/bot_provider.dart';

/// Bot avatar widget với emotions
class BotAvatar extends StatelessWidget {
  final BotEmotion emotion;
  final double size;
  
  const BotAvatar({
    super.key,
    required this.emotion,
    this.size = 200,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: _getGradient(),
        boxShadow: [
          BoxShadow(
            color: _getColor().withOpacity(0.5),
            blurRadius: 30,
            spreadRadius: 10,
          ),
        ],
      ),
      child: Center(
        child: _getEmotionIcon(),
      ),
    );
  }
  
  /// Get gradient theo emotion
  LinearGradient _getGradient() {
    switch (emotion) {
      case BotEmotion.happy:
        return LinearGradient(
          colors: [Colors.green.shade300, Colors.green.shade600],
        );
      case BotEmotion.listening:
        return LinearGradient(
          colors: [Colors.blue.shade300, Colors.blue.shade600],
        );
      case BotEmotion.speaking:
        return LinearGradient(
          colors: [Colors.purple.shade300, Colors.purple.shade600],
        );
      case BotEmotion.thinking:
        return LinearGradient(
          colors: [Colors.orange.shade300, Colors.orange.shade600],
        );
      case BotEmotion.sad:
        return LinearGradient(
          colors: [Colors.grey.shade400, Colors.grey.shade700],
        );
      case BotEmotion.error:
        return LinearGradient(
          colors: [Colors.red.shade300, Colors.red.shade600],
        );
      default:
        return LinearGradient(
          colors: [Colors.teal.shade300, Colors.teal.shade600],
        );
    }
  }
  
  /// Get color theo emotion
  Color _getColor() {
    switch (emotion) {
      case BotEmotion.happy:
        return Colors.green;
      case BotEmotion.listening:
        return Colors.blue;
      case BotEmotion.speaking:
        return Colors.purple;
      case BotEmotion.thinking:
        return Colors.orange;
      case BotEmotion.sad:
        return Colors.grey;
      case BotEmotion.error:
        return Colors.red;
      default:
        return Colors.teal;
    }
  }
  
  /// Get icon theo emotion
  Widget _getEmotionIcon() {
    IconData iconData;
    
    switch (emotion) {
      case BotEmotion.happy:
        iconData = Icons.mood;
        break;
      case BotEmotion.listening:
        iconData = Icons.hearing;
        break;
      case BotEmotion.speaking:
        iconData = Icons.record_voice_over;
        break;
      case BotEmotion.thinking:
        iconData = Icons.psychology;
        break;
      case BotEmotion.sad:
        iconData = Icons.sentiment_dissatisfied;
        break;
      case BotEmotion.error:
        iconData = Icons.error_outline;
        break;
      default:
        iconData = Icons.face;
    }
    
    return Icon(
      iconData,
      size: size * 0.5,
      color: Colors.white,
    );
  }
}
