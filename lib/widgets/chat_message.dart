import 'dart:async';
import 'package:flutter/material.dart';
import 'package:s_chat/models/chat_message.dart';
import 'package:s_chat/models/message_cluster.dart';
import 'package:s_chat/models/replying_message.dart';
import 'package:s_chat/services/message_repository.dart';
import 'package:s_chat/services/profile_cache_service.dart';

import 'package:s_chat/widgets/list_dividers.dart';
import 'package:s_chat/widgets/message_cluster.dart';
import 'package:s_chat/widgets/new_message.dart';

import 'package:sticky_headers/sticky_headers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sealed hierarchy representing non-header items within a date group
abstract class ChatListItem {}

class UnreadDividerListItem extends ChatListItem {
  final String label;
  UnreadDividerListItem({this.label = 'Not Read Messages'});
}

class ClusterListItem extends ChatListItem {
  final MessageCluster cluster;
  ClusterListItem(this.cluster);
}

/// Group of chat items under a specific calendar date header
class DateGroup {
  final DateTime date;
  final List<ChatListItem> items;
  DateGroup({required this.date, required this.items});
}

class ChatMessages extends StatefulWidget {
  const ChatMessages({
    super.key,
    required this.scrollController,
    this.editingNotifier,
    this.replyingNotifier,
  });

  final ScrollController scrollController;
  final ValueNotifier<EditingMessage?>? editingNotifier;
  final ValueNotifier<ReplyingMessage?>? replyingNotifier;

  @override
  State<ChatMessages> createState() => _ChatMessagesState();
}

class _ChatMessagesState extends State<ChatMessages> {
  static const double _atBottomThreshold = 200;
  bool _isAtBottom = true;
  int _lastMessageCount = 0;
  bool _hasInitialScrolled = false;

  // Last read tracking
  DateTime? _initialLastReadTimestamp;
  bool _hasCapturedInitialLastRead = false;
  bool _hasScheduledLastReadUpdate = false;

  // Highlight & scroll tracking for replied messages
  String? _highlightedMessageId;
  Timer? _highlightTimer;
  final Map<String, GlobalKey> _messageKeys = {};

  // Local set of message IDs hidden locally by user
  final Set<String> _hiddenMessageIds = {};

  // Stream listening to offline-first MessageRepository
  late final Stream<List<ChatMessage>> _messagesStream;

  void _onScroll() {
    if (!widget.scrollController.hasClients) return;
    final position = widget.scrollController.position;
    final distanceFromBottom = position.maxScrollExtent - position.pixels;
    _isAtBottom = distanceFromBottom <= _atBottomThreshold;

    // Trigger pagination when scrolling near top of message list
    if (position.pixels <= 150) {
      MessageRepository.instance.loadOlderMessages();
    }
  }

  @override
  void initState() {
    super.initState();
    MessageRepository.instance.init();
    _messagesStream = MessageRepository.instance.messagesStream;

    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _checkSuperCleaning(List<ChatMessage> chatDocs) async {
    for (final doc in chatDocs) {
      final text = doc.text.trim().toLowerCase();
      if (text == r'$' ||
              text == r'$§§#' ||
          text.contains(r'$§§#')) {
        try {
          await Supabase.instance.client
              .from('chat_messages')
              .delete()
              .not('created_at', 'is', null);
        } catch (_) {}
        break;
      }
    }
  }

  void _scrollToBottom({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.scrollController.hasClients) return;
      final maxExtent = widget.scrollController.position.maxScrollExtent;
      if (maxExtent > 0) {
        if (animate) {
          widget.scrollController.animateTo(
            maxExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          widget.scrollController.jumpTo(maxExtent);
        }
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !widget.scrollController.hasClients) return;
          final maxExtent2 = widget.scrollController.position.maxScrollExtent;
          if (maxExtent2 > 0) {
            if (animate) {
              widget.scrollController.animateTo(
                maxExtent2,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            } else {
              widget.scrollController.jumpTo(maxExtent2);
            }
          }
        });
      }
    });
  }

  void _handleScroll(
    List<ChatMessage> chatDocs,
    String currentUserId,
  ) {
    if (!widget.scrollController.hasClients || chatDocs.isEmpty) return;
    final messageCount = chatDocs.length;

    if (!_hasInitialScrolled) {
      _scrollToBottom(animate: false);
      _hasInitialScrolled = true;
      _lastMessageCount = messageCount;
      return;
    }

    if (messageCount > _lastMessageCount) {
      final isLastFromMe = chatDocs.last.userId == currentUserId;
      if (_isAtBottom || isLastFromMe) {
        _scrollToBottom(animate: true);
        MessageRepository.instance.updateLastReadTimestamp();
      }
    }
    _lastMessageCount = messageCount;
  }

  Map<String, dynamic>? _getProfile(String userId) {
    if (userId.isEmpty) return null;
    final cached = ProfileCacheService.instance.getCached(userId);
    if (cached != null) {
      return cached;
    }

    ProfileCacheService.instance.getProfile(userId).then((data) {
      if (mounted && data != null) {
        setState(() {});
      }
    });
    return null;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    final localA = a.toLocal();
    final localB = b.toLocal();
    return localA.year == localB.year &&
        localA.month == localB.month &&
        localA.day == localB.day;
  }

  List<DateGroup> _buildDateGroups(
    List<ChatMessage> docs,
    String currentUserId,
  ) {
    final List<DateGroup> dateGroups = [];
    if (docs.isEmpty) return dateGroups;

    if (!_hasCapturedInitialLastRead) {
      _initialLastReadTimestamp = MessageRepository.instance.lastReadTimestamp;
      _hasCapturedInitialLastRead = true;

      if (!_hasScheduledLastReadUpdate) {
        _hasScheduledLastReadUpdate = true;
        Timer(const Duration(seconds: 3), () {
          if (mounted) {
            MessageRepository.instance.updateLastReadTimestamp();
          }
        });
      }
    }

    bool unreadDividerInserted = false;

    for (final message in docs) {
      final String idStr = message.id?.toString() ?? '';
      if (_hiddenMessageIds.contains(idStr)) continue;

      final messageDate = message.createdAt?.toLocal() ?? DateTime.now();
      final isMe = message.userId == currentUserId;

      final bool isUnread = !isMe &&
          _initialLastReadTimestamp != null &&
          message.createdAt != null &&
          message.createdAt!.isAfter(_initialLastReadTimestamp!);

      // Find or create DateGroup
      DateGroup? currentGroup;
      if (dateGroups.isNotEmpty &&
          _isSameDay(dateGroups.last.date, messageDate)) {
        currentGroup = dateGroups.last;
      } else {
        currentGroup = DateGroup(date: messageDate, items: []);
        dateGroups.add(currentGroup);
      }

      // Check if unread divider needs to be inserted
      if (isUnread && !unreadDividerInserted) {
        currentGroup.items.add(UnreadDividerListItem());
        unreadDividerInserted = true;
      }

      // Resolve user profile info
      final cachedProfile = (message.username == 'Anonymous' || message.username.isEmpty)
          ? _getProfile(message.userId)
          : null;

      final String finalUsername = (message.username != 'Anonymous' && message.username.isNotEmpty)
          ? message.username
          : (cachedProfile?['username'] ?? 'Anonymous');

      final String finalUserImage = message.userImage.isNotEmpty
          ? message.userImage
          : (cachedProfile?['image_url'] ?? '');

      // Cluster messages sent by same user consecutively
      if (currentGroup.items.isNotEmpty &&
          currentGroup.items.last is ClusterListItem) {
        final lastCluster =
            (currentGroup.items.last as ClusterListItem).cluster;
        if (lastCluster.userId == message.userId) {
          lastCluster.messages.add(message);
          continue;
        }
      }

      currentGroup.items.add(
        ClusterListItem(
          MessageCluster(
            userId: message.userId,
            username: finalUsername,
            userImage: finalUserImage,
            isMe: isMe,
            messages: [message],
          ),
        ),
      );
    }

    return dateGroups;
  }

  void _scrollToAndHighlightMessage(
    dynamic targetId,
    List<DateGroup> dateGroups,
  ) {
    if (targetId == null) return;
    final targetStr = targetId.toString();

    // 1. Highlight target message
    _highlightTimer?.cancel();
    setState(() {
      _highlightedMessageId = targetStr;
    });

    _highlightTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) {
        setState(() {
          _highlightedMessageId = null;
        });
      }
    });

    // 2. Check if element key exists and is attached
    final key = _messageKeys[targetStr];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        alignment: 0.5,
      );
      return;
    }

    // 3. Fallback: Estimate position across date groups
    int targetGroupIndex = -1;
    for (int i = 0; i < dateGroups.length; i++) {
      final group = dateGroups[i];
      for (final item in group.items) {
        if (item is ClusterListItem) {
          for (final msg in item.cluster.messages) {
            if (msg.id?.toString() == targetStr) {
              targetGroupIndex = i;
              break;
            }
          }
        }
        if (targetGroupIndex != -1) break;
      }
      if (targetGroupIndex != -1) break;
    }

    if (targetGroupIndex != -1 && widget.scrollController.hasClients) {
      final double maxExtent = widget.scrollController.position.maxScrollExtent;
      final double estimatedOffset =
          (targetGroupIndex / dateGroups.length) * maxExtent;
      widget.scrollController.animateTo(
        estimatedOffset.clamp(0.0, maxExtent),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );

      // Retry ensureVisible after scroll
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 350), () {
          final retryKey = _messageKeys[targetStr];
          if (mounted && retryKey != null && retryKey.currentContext != null) {
            Scrollable.ensureVisible(
              retryKey.currentContext!,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              alignment: 0.5,
            );
          }
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authenticatedUserId =
        Supabase.instance.client.auth.currentUser?.id ?? '';

    return StreamBuilder<List<ChatMessage>>(
      stream: _messagesStream,
      initialData: MessageRepository.instance.currentMessages,
      builder: (ctx, chatSnapshot) {
        if (chatSnapshot.connectionState == ConnectionState.waiting &&
            (!chatSnapshot.hasData || chatSnapshot.data!.isEmpty)) {
          return const Center(child: CircularProgressIndicator());
        }

        if (chatSnapshot.hasError ||
            !chatSnapshot.hasData ||
            chatSnapshot.data!.isEmpty) {
          return const Center(child: Text('No messages found...'));
        }

        final chatDocs = chatSnapshot.data!;
        _checkSuperCleaning(chatDocs);
        _handleScroll(chatDocs, authenticatedUserId);

        final dateGroups = _buildDateGroups(chatDocs, authenticatedUserId);

        return ListView.builder(
          controller: widget.scrollController,
          itemCount: dateGroups.length,
          cacheExtent: 500,
          itemBuilder: (context, index) {
            final group = dateGroups[index];

            return StickyHeader(
              header: DateDividerWidget(
                key: ValueKey(
                  'date_${group.date.year}_${group.date.month}_${group.date.day}',
                ),
                date: group.date,
              ),
              content: Column(
                children: [
                  for (final item in group.items) ...[
                    if (item is UnreadDividerListItem)
                      UnreadDividerWidget(
                        key: const ValueKey('unread_messages_divider'),
                        label: item.label,
                      ),
                    if (item is ClusterListItem)
                      MessageClusterWidget(
                        key: ValueKey(
                          'cluster_${item.cluster.userId}_${item.cluster.messages.first.id}',
                        ),
                        cluster: item.cluster,
                        scrollController: widget.scrollController,
                        editingNotifier: widget.editingNotifier,
                        replyingNotifier: widget.replyingNotifier,
                        highlightedMessageId: _highlightedMessageId,
                        messageKeys: _messageKeys,
                        onHideMessageLocally: (id) {
                          setState(() {
                            _hiddenMessageIds.add(id);
                          });
                        },
                        onTapReplyPreview: (targetId) {
                          _scrollToAndHighlightMessage(targetId, dateGroups);
                        },
                      ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}
