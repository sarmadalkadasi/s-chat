class ChatMessage {
  final dynamic id;
  final String userId;
  final String text;
  final String username;
  final String userImage;
  final DateTime? createdAt;
  final dynamic replyToId;
  final String? replyToUsername;
  final String? replyToText;

  ChatMessage({
    required this.id,
    required this.userId,
    required this.text,
    required this.username,
    required this.userImage,
    this.createdAt,
    this.replyToId,
    this.replyToUsername,
    this.replyToText,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    final rawDate = map['created_at'] ?? map['createdAt'];
    DateTime? parsedDate;
    if (rawDate is DateTime) {
      parsedDate = rawDate;
    } else if (rawDate is String) {
      parsedDate = DateTime.tryParse(rawDate);
    }

    return ChatMessage(
      id: map['id'],
      userId: map['user_id'] ?? '',
      text: map['text'] ?? '',
      username: map['username'] ?? 'Anonymous',
      userImage: map['user_image'] ?? map['image_url'] ?? '',
      createdAt: parsedDate,
      replyToId: map['reply_to_id'],
      replyToUsername: map['reply_to_username'],
      replyToText: map['reply_to_text'],
    );
  }
}
