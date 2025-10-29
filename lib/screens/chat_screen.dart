import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/bot_provider.dart';

/// Chat screen - màn hình phụ
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0A0E27),
      appBar: AppBar(
        backgroundColor: Color(0xFF1A1F3A),
        title: Text('Chat'),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline),
            onPressed: () {
              context.read<BotProvider>().clearMessages();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Message list
          Expanded(
            child: Consumer<BotProvider>(
              builder: (context, bot, child) {
                return ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.all(16),
                  itemCount: bot.messages.length,
                  itemBuilder: (context, index) {
                    final message = bot.messages[index];
                    return _buildMessageBubble(message);
                  },
                );
              },
            ),
          ),
          
          // Input area
          _buildInputArea(context),
        ],
      ),
    );
  }
  
  Widget _buildMessageBubble(ChatMessage message) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: message.isUser ? Colors.blue : Colors.grey.shade800,
          borderRadius: BorderRadius.circular(20),
        ),
        constraints: BoxConstraints(maxWidth: 280),
        child: Text(
          message.text,
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
  
  Widget _buildInputArea(BuildContext context) {
    final bot = context.watch<BotProvider>();
    
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF1A1F3A),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          // Text field
          Expanded(
            child: TextField(
              controller: _textController,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: TextStyle(color: Colors.white38),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onSubmitted: (_) => _sendMessage(context),
            ),
          ),
          
          SizedBox(width: 8),
          
          // Send button
          CircleAvatar(
            backgroundColor: Colors.blue,
            child: IconButton(
              icon: Icon(Icons.send, color: Colors.white),
              onPressed: bot.isConnected ? () => _sendMessage(context) : null,
            ),
          ),
        ],
      ),
    );
  }
  
  void _sendMessage(BuildContext context) {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    
    context.read<BotProvider>().sendTextMessage(text);
    _textController.clear();
    
    // Scroll to bottom
    Future.delayed(Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }
}
