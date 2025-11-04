import 'package:flutter/material.dart';
import 'package:roomie/presentation/screens/chat/chat_screen.dart';

class GroupChatScreen extends StatelessWidget {
  const GroupChatScreen({super.key, required this.group});

  final Map<String, dynamic> group;

  @override
  Widget build(BuildContext context) {
    return ChatScreen(chatData: group, chatType: 'group');
  }
}
