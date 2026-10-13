import 'package:s_chat/models/chat_message.dart';

class MessageCluster {
  final String userId;
  final String username;
  final String userImage;
  final bool isMe;
  final List<ChatMessage> messages;

  MessageCluster({
    required this.userId,
    required this.username,
    required this.userImage,
    required this.isMe,
    required this.messages,
  });
}