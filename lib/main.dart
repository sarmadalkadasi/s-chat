import 'dart:async';
import 'package:flutter/material.dart';
import 'package:s_chat/s_chat.dart';
import 'package:s_chat/services/local_notification_manager.dart';
import 'package:s_chat/services/message_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://xchbrnfkuiozonulvfoi.supabase.co',
    publishableKey: 'sb_secret_lJTya6AdqldBwl9N2RVRSA_A91WyK5I',
  );
  // Initialize notifications
  await LocalNotificationManager.initialize();

  // Pre-load offline messages and outbox before UI renders
  await MessageRepository.instance.init();

  // Start watching for incoming messages
  listenToIncomingMessages();
  runApp(const SChat());
}

StreamSubscription? _incomingMessagesSubscription;

void listenToIncomingMessages() {
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    final session = data.session;
    if (session != null) {
      _incomingMessagesSubscription?.cancel();
      bool isFirstLoad = true; // ignore the initial history pull

      _incomingMessagesSubscription = Supabase.instance.client
          .from('chat_messages')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .limit(1)
          .listen(
            (messages) {
              // If the stream just woke up, skip processing the existing latest message
              if (isFirstLoad) {
                isFirstLoad = false;
                return;
              }

              if (messages.isEmpty) return;

              final latestMessage = messages.first;
              final currentUserId =
                  Supabase.instance.client.auth.currentUser?.id;
              final String senderId = latestMessage['user_id'] ?? '';
              final String messageText = latestMessage['text'] ?? '';
              final String username = latestMessage['username'] ?? 'Anonymous';

              // Notify only if someone else sent it
              if (senderId != currentUserId && messageText.isNotEmpty) {
                LocalNotificationManager.showNotification(
                  title: username,
                  body: messageText,
                );
              }
            },
            onError: (error) {
              debugPrint('Incoming messages stream error: $error');
            },
          );
    } else {
      _incomingMessagesSubscription?.cancel();
      _incomingMessagesSubscription = null;
    }
  });
}
