import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:s_chat/models/chat_item.dart';
import 'package:s_chat/models/replying_message.dart';
import 'package:s_chat/screens/group_settings.dart';
import 'package:s_chat/services/crypto_service.dart';
import 'package:s_chat/services/local_notification_manager.dart';
import 'package:s_chat/services/message_repository.dart';
import 'package:s_chat/utils/app_alerts.dart';
import 'package:s_chat/widgets/chat/chat_list.dart';
import 'package:s_chat/widgets/chat/chat_media_picker.dart';
import 'package:s_chat/widgets/chat/chat_message.dart';
import 'package:s_chat/widgets/chat/image_viewer.dart';
import 'package:s_chat/widgets/chat/new_message.dart';
import 'package:s_chat/widgets/user/user_image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<EditingMessage?> _editingNotifier =
      ValueNotifier<EditingMessage?>(null);
  final ValueNotifier<ReplyingMessage?> _replyingNotifier =
      ValueNotifier<ReplyingMessage?>(null);

  ChatItem? _selectedChat;
  bool _canJump = false;
  static const double _jumpButtonThreshold = 200;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    LocalNotificationManager.setOnNotificationTap((chatId) async {
      final availableChats = await MessageRepository.instance
          .fetchAvailableChats();
      final target = availableChats.firstWhere(
        (c) => c.id == chatId,
        orElse: () =>
            ChatItem(id: chatId, name: 'Chat', avatarUrl: '', lastMessage: ''),
      );
      if (mounted) {
        setState(() {
          _selectedChat = target;
          LocalNotificationManager.setActiveChatId(target.id);
        });
        await _loadReceiverPublicKey();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _editingNotifier.dispose();
    _replyingNotifier.dispose();
    super.dispose();
  }

  /// Warms up the public key cache of the selected chat, so the first message
  /// can be encrypted without waiting for an extra round trip.
  Future<void> _loadReceiverPublicKey() async {
    final chat = _selectedChat;
    if (chat == null || chat.isGroup) return;

    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (chat.id.isEmpty || chat.id == currentUserId) return;

    await CryptoService.instance.publicKeyOf(chat.id);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final distanceFromBottom = position.maxScrollExtent - position.pixels;
    final shouldShow = distanceFromBottom > _jumpButtonThreshold;
    if (shouldShow != _canJump) {
      setState(() => _canJump = shouldShow);
    }
  }

  void _jumpToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
  }

  Future<void> _showCreateGroupDialog() async {
    final controller = TextEditingController();
    File? pickedImage;
    bool isCreating = false;

    final group = await showDialog<ChatItem>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.groups_rounded, color: Colors.teal),
                SizedBox(width: 8),
                Text('New Group'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AbsorbPointer(
                    absorbing: isCreating,
                    child: UserImagePicker(
                      onSelectImage: (file) {
                        pickedImage = file;
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    enabled: !isCreating,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Enter group name...',
                      labelText: 'Group Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isCreating ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isCreating
                    ? null
                    : () async {
                        final name = controller.text.trim();
                        if (name.isEmpty) return;

                        setDialogState(() {
                          isCreating = true;
                        });

                        final isTaken = await MessageRepository.instance
                            .isGroupNameTaken(name);
                        if (isTaken) {
                          if (context.mounted) {
                            AppAlerts.showSnackBar(
                              context,
                              'A group named "$name" already exists. Please choose a different name.',
                              isError: true,
                            );
                          }
                          setDialogState(() {
                            isCreating = false;
                          });
                          return;
                        }

                        final tempGroupId =
                            'group_${DateTime.now().millisecondsSinceEpoch}';
                        String imageUrl = '';
                        if (pickedImage != null) {
                          imageUrl = await MessageRepository.instance
                              .uploadGroupImage(pickedImage!, tempGroupId);
                        }

                        final created = await MessageRepository.instance
                            .createGroup(groupName: name, imageUrl: imageUrl);
                        setState(() {
                          isCreating = false;
                        });

                        if (context.mounted) {
                          Navigator.pop(context, created);
                        }
                      },
                child: isCreating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create'),
              ),
            ],
          ),
        );
      },
    );

    if (group != null && mounted) {
      setState(() {
        _selectedChat = group;
        LocalNotificationManager.setActiveChatId(group.id);
      });
    }
  }

  Future<void> _queueMediaAttachments(List<ChatAttachment> attachments) async {
    final replying = _replyingNotifier.value;
    final activeChat = _selectedChat;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final String? chatId;
    final String? recipientId;
    if (activeChat != null) {
      if (activeChat.isGroup) {
        chatId = activeChat.id;
        recipientId = null;
      } else {
        chatId = MessageRepository.getDirectChatId(
          currentUserId,
          activeChat.id,
        );
        recipientId = activeChat.id;
      }
    } else {
      chatId = null;
      recipientId = null;
    }

    for (final attachment in attachments) {
      try {
        await MessageRepository.instance.sendOptimisticMedia(
          kind: attachment.kind.name,
          name: attachment.name,
          path: attachment.path,
          url: attachment.url,
          sizeBytes: attachment.sizeBytes,
          chatId: chatId,
          recipientId: recipientId,
          replyToId: replying?.id,
          replyToUsername: replying?.username,
          replyToText: replying?.text,
        );
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not queue attachment: $error')),
        );
      }
    }

    if (replying != null && identical(_replyingNotifier.value, replying)) {
      _replyingNotifier.value = null;
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  void _handleMenuAction(String value, ChatItem? activeChat) {
    switch (value) {
      case 'new_group':
        _showCreateGroupDialog();
        break;
      case 'clear_chat':
        _showClearChatDialog();
        break;
      case 'report':
        _showReportDialog(activeChat);
        break;
      case 'sign_out':
        _signOut();
        break;
    }
  }

  Future<void> _showClearChatDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('Clear Chat?'),
            ],
          ),
          content: const Text(
            'Are you sure you want to clear all messages in this conversation? '
            'This will clear your local chat view.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      final activeChat = _selectedChat;
      final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
      await MessageRepository.instance.clearConversationMessages(
        activeChatId: activeChat?.id,
        isGroup: activeChat?.isGroup ?? false,
        currentUserId: currentUserId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chat cleared'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _showReportDialog(ChatItem? activeChat) async {
    final reasons = [
      'Spam',
      'Inappropriate Content',
      'Harassment or Bullying',
      'Scam or Fraud',
      'Hate Speech',
      'Other',
    ];
    String selectedReason = reasons.first;
    final detailsController = TextEditingController();

    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(
                    Icons.report_problem_outlined,
                    color: Colors.amber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      activeChat != null
                          ? 'Report ${activeChat.name}'
                          : 'Report an Issue',
                      style: const TextStyle(fontSize: 18),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Why are you reporting this?',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ...reasons.map((reason) {
                      final isSelected = selectedReason == reason;
                      return InkWell(
                        onTap: () {
                          setDialogState(() => selectedReason = reason);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 6.0,
                            horizontal: 4.0,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 20,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.outline,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  reason,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    TextField(
                      controller: detailsController,
                      decoration: const InputDecoration(
                        labelText: 'Additional details (optional)',
                        hintText: 'Describe the issue...',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Submit Report'),
                ),
              ],
            );
          },
        );
      },
    );

    if (submitted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Report submitted for "$selectedReason". Thank you for keeping our community safe.',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeChat = _selectedChat;

    return PopScope(
      canPop: activeChat == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && activeChat != null) {
          setState(() {
            _selectedChat = null;
            LocalNotificationManager.setActiveChatId(null);
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: activeChat != null
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() {
                      _selectedChat = null;
                      LocalNotificationManager.setActiveChatId(null);
                    });
                  },
                )
              : null,
          title: activeChat != null
              ? Row(
                  children: [
                    InkWell(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ImageViewer(imageType: ImageType.network,imageUrl: activeChat.avatarUrl,),),),
                      child: Hero(
                        tag: activeChat.avatarUrl,
                        child: (activeChat.isGroup)
                            ? CircleAvatar(
                                radius: 18,
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                backgroundImage: activeChat.avatarUrl.isNotEmpty
                                    ? NetworkImage(activeChat.avatarUrl)
                                    : null,
                                child: activeChat.avatarUrl.isEmpty
                                    ? const Icon(Icons.groups_rounded, size: 20)
                                    : null,
                              )
                            : (activeChat.avatarUrl.isNotEmpty)
                            ? CircleAvatar(
                                radius: 18,
                                backgroundImage: NetworkImage(
                                  activeChat.avatarUrl,
                                ),
                              )
                            : CircleAvatar(
                                radius: 18,
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                child: Text(
                                  activeChat.name.isNotEmpty
                                      ? activeChat.name[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () async {
                          if (activeChat.isGroup) {
                            final currentUserId = Supabase
                                    .instance.client.auth.currentUser?.id ??
                                '';
                            final isOwner = activeChat.ownerId.isEmpty ||
                                activeChat.isOwner(currentUserId);
                            if (!isOwner) {
                              AppAlerts.showSnackBar(
                                context,
                                'Only the group owner can manage group settings.',
                                isError: true,
                              );
                              return;
                            }

                            final result = await Navigator.push<dynamic>(
                              context,
                              MaterialPageRoute(
                                builder: (ctx) =>
                                    GroupSettingsScreen(group: activeChat),
                              ),
                            );
                            if (context.mounted) {
                              if (result == 'deleted') {
                                setState(() {
                                  _selectedChat = null;
                                  LocalNotificationManager.setActiveChatId(null);
                                });
                                AppAlerts.showSnackBar(context, 'Group deleted');
                              } else if (result is ChatItem) {
                                setState(() {
                                  _selectedChat = result;
                                });
                              }
                            }
                          }
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              activeChat.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Row(
                              children: [
                                if (activeChat.isGroup &&
                                    activeChat.isPrivate) ...[
                                  const Icon(
                                    Icons.lock_rounded,
                                    size: 12,
                                    color: Colors.teal,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  activeChat.isGroup
                                      ? (activeChat.isPrivate
                                            ? 'Private Group'
                                            : 'Group Conversation')
                                      : 'Direct Message',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.teal,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'S Chat',
                      style: Theme.of(context).textTheme.titleLarge!.copyWith(
                        fontFamily: 'Audiowide',
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    StreamBuilder<bool>(
                      stream: MessageRepository.instance.isOnlineStream,
                      initialData: MessageRepository.instance.isOnline,
                      builder: (context, snapshot) {
                        final isOnline = snapshot.data ?? true;
                        return Text(
                          isOnline ? 'Online' : 'Connecting...',
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'Audiowide',
                            color: isOnline ? Colors.teal : Colors.orange,
                          ),
                        );
                      },
                    ),
                  ],
                ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: 'More options',
              onSelected: (value) => _handleMenuAction(value, activeChat),
              itemBuilder: (context) {
                if (activeChat == null) {
                  return [
                    const PopupMenuItem(
                      value: 'new_group',
                      child: Row(
                        children: [
                          Icon(Icons.group_add_rounded, size: 20),
                          SizedBox(width: 12),
                          Text('New Group'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'report',
                      child: Row(
                        children: [
                          Icon(Icons.report_problem_outlined, size: 20),
                          SizedBox(width: 12),
                          Text('Report an Issue'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'sign_out',
                      child: Row(
                        children: [
                          Icon(
                            Icons.logout_rounded,
                            size: 20,
                            color: Colors.redAccent,
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Sign Out',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ],
                      ),
                    ),
                  ];
                }

                return [
                  const PopupMenuItem(
                    value: 'clear_chat',
                    child: Row(
                      children: [
                        Icon(Icons.delete_sweep_outlined, size: 20),
                        SizedBox(width: 12),
                        Text('Clear Chat'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'report',
                    child: Row(
                      children: [
                        Icon(Icons.report_problem_outlined, size: 20),
                        SizedBox(width: 12),
                        Text('Report'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'sign_out',
                    child: Row(
                      children: [
                        Icon(
                          Icons.logout_rounded,
                          size: 20,
                          color: Colors.redAccent,
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Sign Out',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ],
                    ),
                  ),
                ];
              },
            ),
          ],
        ),
        floatingActionButton: activeChat == null
            ? FloatingActionButton(
                heroTag: 'fab_new_group',
                onPressed: _showCreateGroupDialog,
                tooltip: 'New Group',
                child: const Icon(Icons.group_add_rounded),
              )
            : AnimatedSlide(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                offset: _canJump ? Offset.zero : const Offset(0, 2),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: _canJump ? 1 : 0,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 64),
                    child: FloatingActionButton.small(
                      heroTag: 'fab_jump_bottom',
                      onPressed: _jumpToBottom,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.arrow_downward),
                    ),
                  ),
                ),
              ),
        body: SafeArea(
          child: activeChat == null
              ? ChatList(
                  onSelectChat: (chat) {
                    final currentUserId =
                        Supabase.instance.client.auth.currentUser?.id ?? '';
                    if (chat.isGroup && chat.isPrivate) {
                      final isAuthorized = chat.ownerId.isEmpty ||
                          chat.isOwner(currentUserId) ||
                          chat.memberIds.contains(currentUserId);
                      if (!isAuthorized) {
                        AppAlerts.showSnackBar(
                          context,
                          'This is a private group. Only invited members can access it.',
                          isError: true,
                        );
                        return;
                      }
                    }

                    setState(() {
                      _selectedChat = chat;
                      LocalNotificationManager.setActiveChatId(chat.id);
                    });
                    unawaited(_loadReceiverPublicKey());
                  },
                )
              : Column(
                  children: [
                    Expanded(
                      child: ChatMessages(
                        scrollController: _scrollController,
                        editingNotifier: _editingNotifier,
                        replyingNotifier: _replyingNotifier,
                        activeChat: activeChat,
                      ),
                    ),
                    NewMessage(
                      editingNotifier: _editingNotifier,
                      replyingNotifier: _replyingNotifier,
                      activeChat: activeChat,
                      onMediaSelected: (attachments) {
                        unawaited(_queueMediaAttachments(attachments));
                      },
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
