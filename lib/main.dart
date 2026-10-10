import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:s_chat/s_chat.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:s_chat/services/local_notification_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Supabase.initialize(
    url: 'https://xchbrnfkuiozonulvfoi.supabase.co',
    publishableKey: 'sb_secret_lJTya6AdqldBwl9N2RVRSA_A91WyK5I',
  );
  // Initialize notifications
  await LocalNotificationManager.initialize();

  // Start watching for incoming messages
  listenToIncomingMessages();
  runApp(const SChat());
}

void listenToIncomingMessages() {
  final currentUserId = Supabase.instance.client.auth.currentUser?.id;
  bool isFirstLoad = true; // ignore the initial history pull

  FirebaseFirestore.instance
      .collection('chat_messages')
      .orderBy('createdAt', descending: true)
      .limit(1)
      .snapshots()
      .listen((snapshot) {
    // If the stream just woke up, skip processing the existing latest message
    if (isFirstLoad) {
      isFirstLoad = false;
      return;
    }

    if (snapshot.docs.isEmpty) return;

    final latestDoc = snapshot.docs.first;
    final data = latestDoc.data();

    final String senderId = data['user_id'] ?? '';
    final String messageText = data['text'] ?? '';
    final String username = data['username'] ?? 'Anonymous';

    // Notify only if someone else sent it
    if (senderId != currentUserId && messageText.isNotEmpty) {
      LocalNotificationManager.showNotification(
        title: username,
        body: messageText,
      );
    }
  });
}

