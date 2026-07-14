import 'package:cloud_firestore/cloud_firestore.dart';

class Message {
  const Message({
    required this.chatId,
    required this.userId,
    required this.text,
    required this.mediaUrl,
    required this.createdAt,
  });
  final String chatId;
  final String userId;
  final String text;
  final String mediaUrl;
  final Timestamp createdAt;
}
