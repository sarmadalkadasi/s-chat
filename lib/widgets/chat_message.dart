import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:s_chat/widgets/message_bubble.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MessageCluster {
  final String userId;
  final String username;
  final String userImage;
  final bool isMe;
  final List<Map<String, dynamic>> messages;

  MessageCluster({
    required this.userId,
    required this.username,
    required this.userImage,
    required this.isMe,
    required this.messages,
  });
}

class ChatMessages extends StatefulWidget {
  const ChatMessages({super.key, required this.scrollController});

  final ScrollController scrollController;

  @override
  State<ChatMessages> createState() => _ChatMessagesState();
}

class _ChatMessagesState extends State<ChatMessages> {
  static const double _atBottomThreshold = 200;
  bool _isAtBottom = true;
  int _lastMessageCount = 0;
  bool _hasInitialScrolled = false;

  // Single persistent stream to prevent reload on scroll or rebuild
  late final Stream<List<Map<String, dynamic>>> _messagesStream;

  // Local cache for user profiles
  final Map<String, Map<String, dynamic>> _profileCache = {};
  final Set<String> _pendingFetches = {};

  void _onScroll() {
    if (!widget.scrollController.hasClients) return;
    final position = widget.scrollController.position;
    // With top-to-bottom list, maxScrollExtent is the bottom and 0 is the top.
    final distanceFromBottom = position.maxScrollExtent - position.pixels;
    _isAtBottom = distanceFromBottom <= _atBottomThreshold;
  }

  @override
  void initState() {
    super.initState();
    // Chronological order: oldest at top, newest at bottom Modern style)
    _messagesStream = Supabase.instance.client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true);

    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
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
    List<Map<String, dynamic>> chatDocs,
    String currentUserId,
  ) {
    if (!widget.scrollController.hasClients || chatDocs.isEmpty) return;
    final messageCount = chatDocs.length;

    // 1. Initial open: guarantee jumping to the bottom to show the last message
    if (!_hasInitialScrolled) {
      _scrollToBottom(animate: false);
      _hasInitialScrolled = true;
      _lastMessageCount = messageCount;
      return;
    }

    // 2. When a new message arrives:
    if (messageCount > _lastMessageCount) {
      final isLastFromMe = chatDocs.last['user_id'] == currentUserId;
      // Scroll to bottom if I sent a new message OR if user was already at the bottom
      if (_isAtBottom || isLastFromMe) {
        _scrollToBottom(animate: true);
      }
    }
    _lastMessageCount = messageCount;
  }

  Map<String, dynamic>? _getProfile(String userId) {
    if (userId.isEmpty) return null;
    if (_profileCache.containsKey(userId)) {
      return _profileCache[userId];
    }

    if (!_pendingFetches.contains(userId)) {
      _pendingFetches.add(userId);
      Supabase.instance.client
          .from('users')
          .select('username, image_url')
          .eq('id', userId)
          .maybeSingle()
          .then((data) {
            if (mounted) {
              setState(() {
                _profileCache[userId] =
                    data ?? {'username': 'Anonymous', 'image_url': ''};
                _pendingFetches.remove(userId);
              });
            }
          })
          .catchError((_) {
            if (mounted) {
              setState(() {
                _profileCache[userId] = {
                  'username': 'Anonymous',
                  'image_url': '',
                };
                _pendingFetches.remove(userId);
              });
            }
          });
    }
    return null;
  }

  List<MessageCluster> _groupMessages(
    List<Map<String, dynamic>> docs,
    String currentUserId,
  ) {
    final List<MessageCluster> clusters = [];
    for (final doc in docs) {
      final String userId = doc['user_id'] ?? '';
      final isMe = userId == currentUserId;
      final cachedProfile =
          (doc['username'] == null || doc['username'].toString().isEmpty)
          ? _getProfile(userId)
          : null;
      final String username =
          doc['username'] ?? cachedProfile?['username'] ?? 'Anonymous';
      final String userImage =
          doc['user_image'] ??
          doc['image_url'] ??
          cachedProfile?['image_url'] ??
          '';

      // Group consecutive messages by sender
      if (clusters.isNotEmpty && clusters.last.userId == userId) {
        clusters.last.messages.add(doc);
      } else {
        clusters.add(
          MessageCluster(
            userId: userId,
            username: username,
            userImage: userImage,
            isMe: isMe,
            messages: [doc],
          ),
        );
      }
    }
    return clusters;
  }

  @override
  Widget build(BuildContext context) {
    final authenticatedUserId =
        Supabase.instance.client.auth.currentUser?.id ?? '';

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _messagesStream,
      builder: (ctx, chatSnapshot) {
        if (chatSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (chatSnapshot.hasError ||
            !chatSnapshot.hasData ||
            chatSnapshot.data!.isEmpty) {
          return const Center(child: Text('No messages found...'));
        }

        final chatDocs = chatSnapshot.data!;
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
                'cluster_${cluster.userId}_${cluster.messages.first['id']}',
              ),
              cluster: cluster,
              scrollController: widget.scrollController,
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
  });

  final MessageCluster cluster;
  final ScrollController scrollController;

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
        widget.cluster.messages.first['id'] ?? UniqueKey().toString();

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
          showProfileImageViewer(context, imageUrl: userImage, username: uname);
        },
        child: Hero(
          tag: userImage.isNotEmpty
              ? 'bubble_avatar_$userImage'
              : 'avatar_${widget.cluster.userId}_$firstMessageId',
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Theme.of(context).colorScheme.primaryContainer,
              image: userImage.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(userImage),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: userImage.isEmpty
                ? Center(
                    child: Text(
                      uname.isNotEmpty ? uname[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(
    BuildContext context,
    Map<String, dynamic> messageDoc,
    int index,
    int totalCount,
  ) {
    final isMe = widget.cluster.isMe;
    final isFirst = (index == 0);
    final isLast = (index == totalCount - 1);
    final isSingle = (totalCount == 1);

    final messageText = messageDoc['text'] ?? '';
    final rawTimestamp = messageDoc['created_at'] ?? messageDoc['createdAt'];
    String formattedTime = '';
    if (rawTimestamp != null) {
      DateTime? dateTime;
      if (rawTimestamp is DateTime) {
        dateTime = rawTimestamp;
      } else if (rawTimestamp is String) {
        dateTime = DateTime.tryParse(rawTimestamp);
      }
      if (dateTime != null) {
        formattedTime = DateFormat('h:mm a').format(dateTime.toLocal());
      }
    }

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

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2.0),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.72,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: isMe
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 3.0,
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
            child: Text(
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
          ),
        ],
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
