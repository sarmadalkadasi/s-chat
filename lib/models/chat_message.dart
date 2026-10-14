import 'dart:convert';

/// A chat message stored locally and in the Supabase `chat_messages` table.
///
/// Media messages are encoded in the existing `text` column with a versioned
/// marker. This preserves compatibility with the current table schema while
/// allowing newer clients to render attachments instead of raw JSON.
class ChatMessage {
  static const String mediaTextPrefix = '[[s_chat_media_v1]]';

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

  /// Serializes attachment metadata into the existing message text field.
  static String encodeMediaText(Map<String, dynamic> payload) {
    return '$mediaTextPrefix${jsonEncode(payload)}';
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

  String get mediaKind => (mediaPayload?['kind'] as String?) ?? 'file';

  String get mediaName => (mediaPayload?['name'] as String?) ?? 'Attachment';

  String? get mediaLocalPath => mediaPayload?['local_path'] as String?;

  String? get mediaStoragePath => mediaPayload?['storage_path'] as String?;

  String? get mediaUrl => mediaPayload?['url'] as String?;

  String get mediaStatus =>
      (mediaPayload?['status'] as String?) ?? 'sent';

  /// User-facing text used for replies, copy, and preview snippets.
  String get displayText {
    final payload = mediaPayload;
    if (payload == null) return text;

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
