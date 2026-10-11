import 'package:flutter/material.dart';
import 'package:s_chat/screens/auth.dart';
import 'package:s_chat/screens/chat.dart';
import 'package:s_chat/screens/splash.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _colorScheme = ColorScheme.fromSeed(
  seedColor: const Color(0xFF075E54),
  brightness: Brightness.light,
);

class SChat extends StatelessWidget {
  const SChat({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SChat',
      debugShowCheckedModeBanner: false,

      theme: ThemeData().copyWith(colorScheme: _colorScheme),
      home: StreamBuilder(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SplashScreen();
          }
          if (snapshot.data?.session != null) {
            return const ChatScreen();
          }
          return const AuthScreen();
        },
      ),
    );
  }
}
