import 'dart:convert';

/// A chat message stored locally and in the Supabase `chat_messages` table.
///
/// Media messages are encoded in the existing `text` column with a versioned
/// marker. This preserves compatibility with the current table schema while
/// allowing newer clients to render attachments instead of raw JSON.
class ChatMessage {
  static const String mediaTextPrefix = '[[s_chat_media_v1]]';
  static const String metaPrefix = '[[s_chat_meta:';
  static const String metaSuffix = ']]';

  final dynamic id;
  final String userId;
  final String text;
  final String username;
  final String userImage;
  final DateTime? createdAt;
  final dynamic replyToId;
  final String? replyToUsername;
  final String? replyToText;
  final String? chatId;
  final String? recipientId;

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
    this.chatId,
    this.recipientId,
  });

  /// Serializes attachment metadata into the existing message text field.
  static String encodeMediaText(Map<String, dynamic> payload) {
    return '$mediaTextPrefix${jsonEncode(payload)}';
  }

  /// Encodes text with target chat metadata into the text field.
  static String encodeChatText({
    required String text,
    String? chatId,
    String? recipientId,
  }) {
    if ((chatId == null || chatId.isEmpty) &&
        (recipientId == null || recipientId.isEmpty)) {
      return text;
    }
    final meta = <String, dynamic>{
      if (chatId != null && chatId.isNotEmpty) 'chat_id': chatId,
      if (recipientId != null && recipientId.isNotEmpty)
        'recipient_id': recipientId,
    };
    return '$metaPrefix${jsonEncode(meta)}$metaSuffix$text';
  }

  /// Extracts metadata envelope from a text message or media message payload.
  static Map<String, dynamic>? extractMeta(String text) {
    if (text.startsWith(mediaTextPrefix)) {
      try {
        final decoded = jsonDecode(text.substring(mediaTextPrefix.length));
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
      return null;
    }
    if (text.startsWith(metaPrefix)) {
      final closeIdx = text.indexOf(metaSuffix);
      if (closeIdx != -1) {
        try {
          final jsonStr = text.substring(metaPrefix.length, closeIdx);
          final decoded = jsonDecode(jsonStr);
          if (decoded is Map<String, dynamic>) return decoded;
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        } catch (_) {}
      }
    }
    return null;
  }

  /// Returns metadata only when [text] contains our media marker.
  Map<String, dynamic>? get mediaPayload {
    if (!text.startsWith(mediaTextPrefix)) return null;
    try {
      final decoded = jsonDecode(text.substring(mediaTextPrefix.length));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // A malformed marker should not crash the chat list.
    }
    return null;
  }

  bool get isMediaMessage => mediaPayload != null;

  bool get isGroup => chatId?.startsWith('group_') == true;

  String get mediaKind => (mediaPayload?['kind'] as String?) ?? 'file';

  String get mediaName => (mediaPayload?['name'] as String?) ?? 'Attachment';

  String? get mediaLocalPath => mediaPayload?['local_path'] as String?;

  String? get mediaStoragePath => mediaPayload?['storage_path'] as String?;

  String? get mediaUrl => mediaPayload?['url'] as String?;

  String get mediaStatus =>
      (mediaPayload?['status'] as String?) ?? 'sent';

  /// Returns the human-readable text without metadata prefix.
  String get cleanText {
    if (text.startsWith(metaPrefix)) {
      final closeIdx = text.indexOf(metaSuffix);
      if (closeIdx != -1) {
        return text.substring(closeIdx + metaSuffix.length);
      }
    }
    return text;
  }

  /// User-facing text used for replies, copy, and preview snippets.
  String get displayText {
    final payload = mediaPayload;
    if (payload == null) return cleanText;

    switch ((payload['kind'] as String?) ?? 'file') {
      case 'audio':
        return 'Voice message';
      case 'image':
        return 'Photo';
      case 'video':
        return 'Video';
      case 'url':
        return (payload['url'] as String?) ?? 'Link';
      case 'file':
      default:
        return (payload['name'] as String?) ?? 'File';
    }
  }

  bool get isPending =>
      id?.toString().startsWith('temp_') == true || mediaStatus == 'pending';

  /// Determines whether this message belongs to the specified chat conversation.
  bool matchesChat({
    required String activeChatId,
    required bool isGroup,
    required String currentUserId,
  }) {
    if (isGroup) {
      // In a group chat: message MUST have been explicitly sent to this group!
      return chatId == activeChatId;
    }

    // In a direct 1-to-1 conversation with [activeChatId]:
    // 1. Group messages must NEVER appear in private user chats.
    if (this.isGroup) return false;

    // 2. If chatId matches the direct chat identifier:
    if (chatId != null && chatId!.isNotEmpty) {
      final directId = user1CompareUser2(currentUserId, activeChatId);
      return chatId == directId || chatId == activeChatId;
    }

    // 3. If recipientId is specified:
    if (recipientId != null && recipientId!.isNotEmpty) {
      return (userId == currentUserId && recipientId == activeChatId) ||
          (userId == activeChatId && recipientId == currentUserId);
    }

    // 4. Legacy fallback: sent directly by the active contact, not in any group
    return userId == activeChatId;
  }

  static String user1CompareUser2(String u1, String u2) {
    return u1.compareTo(u2) <= 0 ? 'dm_${u1}_$u2' : 'dm_${u2}_$u1';
  }

  ChatMessage copyWithText(String newText) {
    return ChatMessage(
      id: id,
      userId: userId,
      text: newText,
      username: username,
      userImage: userImage,
      createdAt: createdAt,
      replyToId: replyToId,
      replyToUsername: replyToUsername,
      replyToText: replyToText,
      chatId: chatId,
      recipientId: recipientId,
    );
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    final rawDate = map['created_at'] ?? map['createdAt'];
    DateTime? parsedDate;
    if (rawDate is DateTime) {
      parsedDate = rawDate;
    } else if (rawDate is String) {
      parsedDate = DateTime.tryParse(rawDate);
    }

    final rawText = (map['text'] ?? '').toString();
    final meta = extractMeta(rawText);

    final resolvedChatId =
        map['chat_id']?.toString() ?? meta?['chat_id']?.toString();
    final resolvedRecipientId =
        map['recipient_id']?.toString() ?? meta?['recipient_id']?.toString();

    return ChatMessage(
      id: map['id'],
      userId: map['user_id'] ?? '',
      text: rawText,
      username: map['username'] ?? 'Anonymous',
      userImage: map['user_image'] ?? map['image_url'] ?? '',
      createdAt: parsedDate,
      replyToId: map['reply_to_id'],
      replyToUsername: map['reply_to_username'],
      replyToText: map['reply_to_text'],
      chatId: resolvedChatId,
      recipientId: resolvedRecipientId,
    );
  }
}
