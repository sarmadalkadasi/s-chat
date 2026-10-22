import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:s_chat/models/chat_item.dart';
import 'package:s_chat/services/message_repository.dart';
import 'package:s_chat/widgets/chat/cached_media_image.dart';

class ChatList extends StatefulWidget {
  const ChatList({super.key, this.onSelectChat});

  final void Function(ChatItem chat)? onSelectChat;

  @override
  State<ChatList> createState() => _ChatListState();
}

class _ChatListState extends State<ChatList> {
  late Future<List<ChatItem>> _chatsFuture;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _refreshChats();
  }

  void _refreshChats() {
    setState(() {
      _chatsFuture = MessageRepository.instance.fetchAvailableChats();
    });
  }

  String _formatTimestamp(DateTime? dateTime) {
    if (dateTime == null) return '';
    final local = dateTime.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final date = DateTime(local.year, local.month, local.day);

    if (date == today) {
      return DateFormat('h:mm a').format(local);
    } else if (date == yesterday) {
      return 'Yesterday';
    } else if (now.year == local.year) {
      return DateFormat('E, MMM d').format(local);
    } else {
      return DateFormat('MMM d, yyyy').format(local);
    }
  }

  Widget _buildAvatar(BuildContext context, ChatItem chat) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (chat.isGroup && chat.avatarUrl.trim().isEmpty) {
      return Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colorScheme.primaryContainer,
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.6),
            width: 1.5,
          ),
        ),
        child: Icon(
          Icons.groups_rounded,
          color: colorScheme.onPrimaryContainer,
          size: 26,
        ),
      );
    }

    return Stack(
      children: [
        Container(
          width: 50,
          height: 50,
          padding: const EdgeInsets.all(2.0),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.greenAccent.shade400, width: 1.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: chat.avatarUrl.isNotEmpty
                ? CachedMediaImage(
                    imageUrl: chat.avatarUrl,
                    width: 46,
                    height: 46,
                    fit: BoxFit.cover,
                    placeholder: _buildInitialsFallback(context, chat.name),
                    errorWidget: _buildInitialsFallback(context, chat.name),
                  )
                : _buildInitialsFallback(context, chat.name),
          ),
        ),
        if (chat.isOnline)
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: Colors.tealAccent.shade400,
                shape: BoxShape.circle,
                border: Border.all(color: colorScheme.surface, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInitialsFallback(BuildContext context, String name) {
    final colorScheme = Theme.of(context).colorScheme;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      color: colorScheme.primaryContainer,
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        // Search Bar (Telegram/WhatsApp style)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: TextField(
            onChanged: (value) {
              setState(() {
                _searchQuery = value.trim().toLowerCase();
              });
            },
            decoration: InputDecoration(
              hintText: 'Search chats & groups...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.6,
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 10.0,
                horizontal: 16.0,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24.0),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        // Chat list body
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              _refreshChats();
              await _chatsFuture;
            },
            child: FutureBuilder<List<ChatItem>>(
              future: _chatsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Failed to load chats',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.error,
                      ),
                    ),
                  );
                }

                final allChats = snapshot.data ?? [];
                final filteredChats = _searchQuery.isEmpty
                    ? allChats
                    : allChats.where((chat) {
                        return chat.name.toLowerCase().contains(_searchQuery) ||
                            chat.lastMessage.toLowerCase().contains(
                              _searchQuery,
                            );
                      }).toList();

                if (filteredChats.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 48,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _searchQuery.isEmpty
                              ? 'No conversations found'
                              : 'No matches for "$_searchQuery"',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: filteredChats.length,
                  separatorBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(left: 78.0, right: 16.0),
                    child: Divider(
                      height: 1,
                      thickness: 0.5,
                      color: colorScheme.outline.withValues(alpha: 0.2),
                    ),
                  ),
                  itemBuilder: (context, index) {
                    final chat = filteredChats[index];
                    final formattedTime = _formatTimestamp(
                      chat.lastMessageTime,
                    );

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 6.0,
                      ),
                      leading: _buildAvatar(context, chat),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              chat.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (formattedTime.isNotEmpty) ...[
                            const SizedBox(width: 8),
                              Text(
                                formattedTime,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: chat.unreadCount > 0
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant,
                                  fontWeight: chat.unreadCount > 0
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                          ],
                        ],
                      ),
                      subtitle: Row(
                        children: [
                          Expanded(
                            child: Text(
                              chat.lastMessage,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (chat.unreadCount > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7.0,
                                vertical: 2.0,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${chat.unreadCount}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      onTap: () {
                        widget.onSelectChat?.call(chat);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
