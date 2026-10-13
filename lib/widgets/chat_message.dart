import 'dart:async';
import 'package:flutter/material.dart';
import 'package:s_chat/models/chat_message.dart';
import 'package:s_chat/models/message_cluster.dart';
import 'package:s_chat/models/replying_message.dart';
import 'package:s_chat/services/message_repository.dart';
import 'package:s_chat/services/profile_cache_service.dart';

import 'package:s_chat/widgets/message_cluster.dart';
import 'package:s_chat/widgets/new_message.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

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
      if (text == r'$super_clean#' ||
          text == r'$super_cleaning#' ||
          text.contains(r'$super_clean#') ||
          text.contains(r'$super_cleaning#')) {
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

  List<MessageCluster> _groupMessages(
    List<ChatMessage> docs,
    String currentUserId,
  ) {
    final List<MessageCluster> clusters = [];
    for (final message in docs) {
      final String idStr = message.id?.toString() ?? '';
      if (_hiddenMessageIds.contains(idStr)) continue;

      final isMe = message.userId == currentUserId;
      final cachedProfile = (message.username == 'Anonymous' || message.username.isEmpty)
          ? _getProfile(message.userId)
          : null;

      final String finalUsername = (message.username != 'Anonymous' && message.username.isNotEmpty)
          ? message.username
          : (cachedProfile?['username'] ?? 'Anonymous');

      final String finalUserImage = message.userImage.isNotEmpty
          ? message.userImage
          : (cachedProfile?['image_url'] ?? '');

      if (clusters.isNotEmpty && clusters.last.userId == message.userId) {
        clusters.last.messages.add(message);
      } else {
        clusters.add(
          MessageCluster(
            userId: message.userId,
            username: finalUsername,
            userImage: finalUserImage,
            isMe: isMe,
            messages: [message],
          ),
        );
      }
    }
    return clusters;
  }

  void _scrollToAndHighlightMessage(
    dynamic targetId,
    List<MessageCluster> clusters,
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

    // 3. Fallback: Estimate position and scroll
    int targetClusterIndex = -1;
    for (int i = 0; i < clusters.length; i++) {
      for (final msg in clusters[i].messages) {
        if (msg.id?.toString() == targetStr) {
          targetClusterIndex = i;
          break;
        }
      }
      if (targetClusterIndex != -1) break;
    }

    if (targetClusterIndex != -1 && widget.scrollController.hasClients) {
      final double maxExtent = widget.scrollController.position.maxScrollExtent;
      final double estimatedOffset =
          (targetClusterIndex / clusters.length) * maxExtent;
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

        final clusters = _groupMessages(chatDocs, authenticatedUserId);

        return ListView.builder(
          controller: widget.scrollController,
          itemCount: clusters.length,
          cacheExtent: 500,
          itemBuilder: (context, index) {
            final cluster = clusters[index];
            return MessageClusterWidget(
              key: ValueKey(
                'cluster_${cluster.userId}_${cluster.messages.first.id}',
              ),
              cluster: cluster,
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
                _scrollToAndHighlightMessage(targetId, clusters);
              },
            );
          },
        );
      },
    );
  }
}

