class ChatItem {
  final String id;
  final String name;
  final String avatarUrl;
  final String lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final bool isGroup;
  final bool isOnline;
  final bool isPrivate;
  final String ownerId;
  final List<String> memberIds;

  ChatItem({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.isGroup = false,
    this.isOnline = true,
    this.isPrivate = false,
    this.ownerId = '',
    this.memberIds = const [],
  });

  bool isOwner(String userId) {
    if (userId.isEmpty) return false;
    return ownerId == userId;
  }

  ChatItem copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isGroup,
    bool? isOnline,
    bool? isPrivate,
    String? ownerId,
    List<String>? memberIds,
  }) {
    return ChatItem(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isGroup: isGroup ?? this.isGroup,
      isOnline: isOnline ?? this.isOnline,
      isPrivate: isPrivate ?? this.isPrivate,
      ownerId: ownerId ?? this.ownerId,
      memberIds: memberIds ?? this.memberIds,
    );
  }
}
