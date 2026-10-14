import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:s_chat/models/chat_message.dart';
import 'package:s_chat/models/menu_item.dart';
import 'package:s_chat/models/message_cluster.dart';
import 'package:s_chat/models/replying_message.dart';
import 'package:s_chat/services/message_repository.dart';
import 'package:s_chat/widgets/cached_media_image.dart';
import 'package:s_chat/widgets/context_menu.dart';
import 'package:s_chat/widgets/expandable_formatted_text.dart';
import 'package:s_chat/widgets/new_message.dart';
import 'package:s_chat/widgets/reply_preview.dart';
import 'package:s_chat/widgets/show_image_viewer.dart';

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

  Widget _buildAvatarFallback(BuildContext context, String uname) {
    return Container(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Center(
        child: Text(
          uname.isNotEmpty ? uname[0].toUpperCase() : '?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
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
                    placeholder: _buildAvatarFallback(context, uname),
                    errorWidget: _buildAvatarFallback(context, uname),
                  )
                : _buildAvatarFallback(context, uname),
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

            ExpandableFormattedText(
              text: message.text,
              isMe: isMe,
              previewCharacters: 500,
            ),
            const SizedBox(height: 3),
            Align(
              alignment: AlignmentDirectional.bottomEnd,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isMe) ...[
                    Icon(
                      isPending ? Icons.watch_later_outlined : Icons.check,
                      size: 14,
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimary
                          .withAlpha(200),
                    ),
                    const Spacer(),
                  ],
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
        isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          // Avatar for incoming messages.
          if (!isMe) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 42,
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

          // Message bubbles in this cluster.
          Flexible(
            fit: FlexFit.loose,
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0;
                i < widget.cluster.messages.length;
                i++)
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
    );
  }
}
