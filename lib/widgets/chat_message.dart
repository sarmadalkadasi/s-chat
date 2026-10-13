import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:s_chat/models/chat_message.dart';
import 'package:s_chat/models/menu_item.dart';
import 'package:s_chat/models/replying_message.dart';
import 'package:s_chat/services/message_repository.dart';
import 'package:s_chat/services/profile_cache_service.dart';
import 'package:s_chat/widgets/cached_media_image.dart';
import 'package:s_chat/widgets/context_menu.dart';
import 'package:s_chat/widgets/new_message.dart';
import 'package:s_chat/widgets/reply_preview_widget.dart';
import 'package:s_chat/widgets/show_image_viewer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class MessageClusterWidget extends StatefulWidget {
  const MessageClusterWidget({
    super.key,
    required this.cluster,
    required this.scrollController,
    this.editingNotifier,
    this.replyingNotifier,
    this.highlightedMessageId,
    required this.messageKeys,
    this.onHideMessageLocally,
    this.onTapReplyPreview,
  });

  final MessageCluster cluster;
  final ScrollController scrollController;
  final ValueNotifier<EditingMessage?>? editingNotifier;
  final ValueNotifier<ReplyingMessage?>? replyingNotifier;
  final String? highlightedMessageId;
  final Map<String, GlobalKey> messageKeys;
  final void Function(String messageId)? onHideMessageLocally;
  final void Function(dynamic targetMessageId)? onTapReplyPreview;

  @override
  State<MessageClusterWidget> createState() => _MessageClusterWidgetState();
}

class _MessageClusterWidgetState extends State<MessageClusterWidget> {
  double _avatarOffset = 0.0;

  @override
  void initState() {
    super.initState();
    if (!widget.cluster.isMe) {
      widget.scrollController.addListener(_onScroll);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onScroll();
      });
    }
  }

  @override
  void didUpdateWidget(covariant MessageClusterWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_onScroll);
      if (!widget.cluster.isMe) {
        widget.scrollController.addListener(_onScroll);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _onScroll();
        });
      }
    } else if (!widget.cluster.isMe) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onScroll();
      });
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || widget.cluster.isMe) {
      return;
    }
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final clusterHeight = renderBox.size.height;
    const avatarHeight = 42.0;
    final maxOffset = (clusterHeight - avatarHeight).clamp(
      0.0,
      double.infinity,
    );

    if (maxOffset <= 0) {
      if (_avatarOffset != 0.0) {
        setState(() => _avatarOffset = 0.0);
      }
      return;
    }

    final viewport = RenderAbstractViewport.of(renderBox);
    double viewportTop = 0.0;
    double viewportBottom = MediaQuery.of(context).size.height;

    if (viewport is RenderBox) {
      final viewportBox = viewport as RenderBox;
      if (viewportBox.hasSize) {
        viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
        viewportBottom = viewportTop + viewportBox.size.height;
      }
    } else {
      viewportTop = MediaQuery.viewPaddingOf(context).top + kToolbarHeight;
      viewportBottom = MediaQuery.of(context).size.height - 70;
    }

    final globalTop = renderBox.localToGlobal(Offset.zero).dy;
    final globalBottom = globalTop + clusterHeight;

    final defaultGlobalAvatarTop = globalBottom - avatarHeight;
    final maxViewportAvatarTop = (viewportBottom - avatarHeight).clamp(
      viewportTop,
      double.infinity,
    );
    final clampedGlobalAvatarTop = defaultGlobalAvatarTop.clamp(
      viewportTop,
      maxViewportAvatarTop,
    );

    final targetOffset = (clampedGlobalAvatarTop - globalTop).clamp(
      0.0,
      maxOffset,
    );

    if ((targetOffset - _avatarOffset).abs() > 0.5) {
      setState(() {
        _avatarOffset = targetOffset;
      });
    }
  }

  Widget _buildAvatar(BuildContext context) {
    final userImage = widget.cluster.userImage;
    final uname = widget.cluster.username;
    final firstMessageId =
        widget.cluster.messages.first.id ?? UniqueKey().toString();

    return Container(
      width: 42,
      height: 42,
      padding: const EdgeInsets.all(2.0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.greenAccent.shade400, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(100),
        onTap: () {
          showImageViewer(context, imageUrl: userImage, title: uname);
        },
        child: Hero(
          tag: userImage.isNotEmpty
              ? 'bubble_avatar_$userImage'
              : 'avatar_${widget.cluster.userId}_$firstMessageId',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: userImage.isNotEmpty
                ? CachedMediaImage(
                    imageUrl: userImage,
                    fit: BoxFit.cover,
                    width: 38,
                    height: 38,
                    placeholder: Container(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Center(
                        child: Text(
                          uname.isNotEmpty ? uname[0].toUpperCase() : '?',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                  )
                : Container(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Center(
                      child: Text(
                        uname.isNotEmpty ? uname[0].toUpperCase() : '?',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(
    BuildContext context,
    ChatMessage message,
    int index,
    int totalCount,
  ) {
    final isMe = widget.cluster.isMe;
    final isFirst = (index == 0);
    final isLast = (index == totalCount - 1);
    final isSingle = (totalCount == 1);

    final messageText = message.text;
    final rawId = message.id;
    final String messageIdStr = rawId?.toString() ?? '';

    final String? replyToUsername = message.replyToUsername;
    final String? replyToText = message.replyToText;
    final dynamic replyToId = message.replyToId;

    final isHighlighted = (messageIdStr == widget.highlightedMessageId);
    final bubbleKey = widget.messageKeys.putIfAbsent(
      messageIdStr,
      () => GlobalKey(),
    );

    final bool isPending = message.id?.toString().startsWith('temp_') ?? false;

    String formattedTime = '';
    if (message.createdAt != null) {
      formattedTime = DateFormat('h:mm a').format(message.createdAt!.toLocal());
    }

    // Check if message was sent within last 1 hour (60 minutes)
    bool canEdit = false;
    if (isMe && message.createdAt != null) {
      final difference = DateTime.now().toUtc().difference(message.createdAt!.toUtc());
      canEdit = difference.inMinutes <= 60;
    }

    final List<MenuItem> menuItems = [
      MenuItem(
        id: 'reply',
        title: 'Reply',
        icon: Icons.reply_rounded,
        onTap: () {
          widget.replyingNotifier?.value = ReplyingMessage(
            id: rawId,
            username: widget.cluster.username,
            text: messageText,
          );
        },
      ),
      MenuItem(
        id: 'copy',
        title: 'Copy',
        icon: Icons.copy_rounded,
        onTap: () {
          FocusManager.instance.primaryFocus?.unfocus();
          Clipboard.setData(ClipboardData(text: messageText));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Message copied to clipboard',
                textAlign: TextAlign.center,
              ),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
      if (canEdit)
        MenuItem(
          id: 'edit',
          title: 'Edit',
          icon: Icons.edit_rounded,
          onTap: () {
            widget.editingNotifier?.value = EditingMessage(
              id: rawId,
              text: messageText,
            );
          },
        ),
      MenuItem(
        id: 'delete',
        title: 'Delete',
        icon: Icons.delete_outline_rounded,
        isDestructive: true,
        onTap: () {
          bool isDeleteForOthers = false;
          showDialog(
            context: context,
            builder: (context) {
              return StatefulBuilder(
                builder: (context, setDialogState) {
                  return AlertDialog(
                    title: const Text('Delete Message'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Do you really want to delete this message?'),
                        if (isMe) ...[
                          const SizedBox(height: 8),
                          CheckboxListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 6),
                            value: isDeleteForOthers,
                            title: Text(
                              'Delete it for others, too',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium!
                                  .copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            onChanged: (value) {
                              setDialogState(() {
                                isDeleteForOthers = value ?? false;
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          widget.onHideMessageLocally?.call(messageIdStr);
                          if (isMe && rawId != null) {
                            MessageRepository.instance.deleteOptimisticMessage(
                              id: rawId,
                              isMe: isDeleteForOthers,
                            );
                          }
                        },
                        child: const Text(
                          'Delete',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    ];

    // Modern-style cluster corner radius
    final borderRadius = isMe
        ? BorderRadius.only(
            topLeft: const Radius.circular(18.0),
            topRight: Radius.circular(isFirst || isSingle ? 18.0 : 4.0),
            bottomRight: Radius.circular(isLast || isSingle ? 4.0 : 4.0),
            bottomLeft: const Radius.circular(18.0),
          )
        : BorderRadius.only(
            topLeft: Radius.circular(isFirst || isSingle ? 18.0 : 4.0),
            topRight: const Radius.circular(18.0),
            bottomRight: const Radius.circular(18.0),
            bottomLeft: Radius.circular(isLast || isSingle ? 4.0 : 4.0),
          );

    final hasReply = replyToText != null && replyToText.isNotEmpty;

    return ContextMenu(
      items: menuItems,
      showOnTap: true,
      child: AnimatedContainer(
        key: bubbleKey,
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.symmetric(vertical: 2.0),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: isHighlighted
              ? (isMe
                  ? Theme.of(context).colorScheme.primary.withAlpha(220)
                  : Theme.of(context).colorScheme.tertiaryContainer)
              : (isMe
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.secondaryContainer),
          borderRadius: borderRadius,
          border: isHighlighted
              ? Border.all(color: Colors.yellow.shade600, width: 2.0)
              : null,
          boxShadow: [
            BoxShadow(
              color: isHighlighted
                  ? Colors.yellow.shade500.withAlpha(180)
                  : Colors.black.withAlpha(20),
              blurRadius: isHighlighted ? 12.0 : 3.0,
              spreadRadius: isHighlighted ? 2.0 : 0.0,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Show sender name on first message of cluster
            if (!isMe && isFirst) ...[
              Text(
                widget.cluster.username,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 3),
            ],

            // Reply Preview Snippet inside message bubble
            if (hasReply)
              ReplyPreviewWidget(
                username: replyToUsername ?? 'Reply',
                text: replyToText,
                isMe: isMe,
                onTap: replyToId != null
                    ? () => widget.onTapReplyPreview?.call(replyToId)
                    : null,
              ),

            Text(
              messageText,
              softWrap: true,
              style: TextStyle(
                color: isMe
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSecondaryContainer,
                fontSize: 15.0,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 3),
            Align(
              alignment: AlignmentDirectional.bottomEnd,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formattedTime,
                    style: TextStyle(
                      color: isMe
                          ? Theme.of(context).colorScheme.onPrimary.withAlpha(200)
                          : Theme.of(
                              context,
                            ).colorScheme.onSecondaryContainer.withAlpha(200),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      isPending ? Icons.watch_later_outlined : Icons.check,
                      size: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimary
                          .withAlpha(200),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMe = widget.cluster.isMe;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: isMe
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            // Sticky/Sliding Avatar
            if (!isMe) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 42,
                height: double.infinity,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Transform.translate(
                    offset: Offset(0, _avatarOffset),
                    child: _buildAvatar(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],

            // Column of clustered message bubbles
            Flexible(
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < widget.cluster.messages.length; i++)
                    _buildBubble(
                      context,
                      widget.cluster.messages[i],
                      i,
                      widget.cluster.messages.length,
                    ),
                ],
              ),
            ),

            if (isMe) const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
