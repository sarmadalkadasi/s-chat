import 'package:flutter/material.dart';
import 'package:s_chat/widgets/chat_message.dart';
import 'package:s_chat/widgets/new_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'S Chat',
          style: Theme.of(context).textTheme.titleLarge!.copyWith(
            fontFamily: 'Audiowide',
            fontStyle: FontStyle.italic,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => Supabase.instance.client.auth.signOut(),
            icon: Icon(Icons.power_settings_new),
          ),
        ],
      ),
      body: SafeArea(
        child: const Column(
          children: [
            Expanded(child: ChatMessages()),
            NewMessage(),
          ],
        ),
      ),
    );
  }
}
