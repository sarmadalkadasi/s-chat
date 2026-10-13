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
    final session = Supabase.instance.client.auth.currentSession;
    final user = Supabase.instance.client.auth.currentUser;

    return MaterialApp(
      title: 'SChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData().copyWith(colorScheme: _colorScheme),
      home: (session != null || user != null)
          ? const ChatScreen()
          : StreamBuilder<AuthState>(
              stream: Supabase.instance.client.auth.onAuthStateChange,
              builder: (context, snapshot) {
                if (snapshot.data?.session != null ||
                    Supabase.instance.client.auth.currentUser != null) {
                  return const ChatScreen();
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SplashScreen();
                }
                return const AuthScreen();
              },
            ),
    );
  }
}
