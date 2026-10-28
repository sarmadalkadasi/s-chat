import 'package:flutter/material.dart';
import 'package:s_chat/screens/auth.dart';
import 'package:s_chat/screens/chat.dart';
import 'package:s_chat/screens/splash.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final ValueNotifier<ThemeMode> themeModeNotifier =
    ValueNotifier<ThemeMode>(ThemeMode.system);

final _lightColorScheme = ColorScheme.fromSeed(
  seedColor: const Color(0xFF075E54),
  brightness: Brightness.light,
);

final _darkColorScheme = ColorScheme.fromSeed(
  seedColor: const Color(0xFF00A884),
  brightness: Brightness.dark,
  surface: const Color(0xFF111B21),
  primaryContainer: const Color(0xFF202C33),
);

class SChat extends StatelessWidget {
  const SChat({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    final user = Supabase.instance.client.auth.currentUser;

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, currentThemeMode, _) {
        return MaterialApp(
          title: 'SChat',
          debugShowCheckedModeBanner: false,
          themeMode: currentThemeMode,
          theme: ThemeData().copyWith(
            colorScheme: _lightColorScheme,
            scaffoldBackgroundColor: const Color(0xFFF0F2F5),
          ),
          darkTheme: ThemeData.dark().copyWith(
            colorScheme: _darkColorScheme,
            scaffoldBackgroundColor: const Color(0xFF111B21),
          ),
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
      },
    );
  }
}
