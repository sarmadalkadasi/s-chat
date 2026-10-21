import 'dart:async';

import 'package:flutter/material.dart';
import 'package:s_chat/models/chat_item.dart';
import 'package:s_chat/models/replying_message.dart';
import 'package:s_chat/services/local_notification_manager.dart';
import 'package:s_chat/services/message_repository.dart';
import 'package:s_chat/widgets/chat/chat_list.dart';
import 'package:s_chat/widgets/chat/chat_media_picker.dart';
import 'package:s_chat/widgets/chat/chat_message.dart';
import 'package:s_chat/widgets/chat/new_message.dart';
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
      final availableChats =
          await MessageRepository.instance.fetchAvailableChats();
      final target = availableChats.firstWhere(
        (c) => c.id == chatId,
        orElse: () => ChatItem(
          id: chatId,
          name: 'Chat',
          avatarUrl: '',
          lastMessage: '',
        ),
      );
      if (mounted) {
        setState(() {
          _selectedChat = target;
          LocalNotificationManager.setActiveChatId(target.id);
        });
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
    final group = await showDialog<ChatItem>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.groups_rounded, color: Colors.teal),
              SizedBox(width: 8),
              Text('New Group'),
            ],
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Enter group name...',
              labelText: 'Group Name',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  final created = await MessageRepository.instance.createGroup(
                    groupName: name,
                  );
                  if (context.mounted) {
                    Navigator.pop(context, created);
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (group != null && mounted) {
      setState(() {
        _selectedChat = group;
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
        chatId = MessageRepository.getDirectChatId(currentUserId, activeChat.id);
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
      case 'toggle_privacy':
        if (activeChat != null && activeChat.isGroup) {
          _toggleGroupPrivacy(activeChat);
        }
        break;
      case 'add_users':
        if (activeChat != null && activeChat.isGroup) {
          _showAddUsersDialog(activeChat);
        }
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
                  const Icon(Icons.report_problem_outlined, color: Colors.amber),
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
                    ...reasons.map(
                      (reason) {
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
                      },
                    ),
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

  void _toggleGroupPrivacy(ChatItem activeChat) {
    final newPrivacy = !activeChat.isPrivate;
    setState(() {
      _selectedChat = activeChat.copyWith(isPrivate: newPrivacy);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newPrivacy
              ? '${activeChat.name} is now a Private Group'
              : '${activeChat.name} is now a Public Group',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showAddUsersDialog(ChatItem activeChat) async {
    final searchController = TextEditingController();
    final availableChats = await MessageRepository.instance.fetchAvailableChats();
    final candidateUsers = availableChats.where((c) => !c.isGroup).toList();
    final selectedUserIds = <String>{};

    if (!mounted) return;

    final added = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filter = searchController.text.trim().toLowerCase();
            final filteredCandidates = filter.isEmpty
                ? candidateUsers
                : candidateUsers
                    .where((u) => u.name.toLowerCase().contains(filter))
                    .toList();

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.person_add_rounded, color: Colors.teal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Add Users to ${activeChat.name}',
                      style: const TextStyle(fontSize: 18),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search users...',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: filteredCandidates.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text('No users found'),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filteredCandidates.length,
                              itemBuilder: (context, index) {
                                final user = filteredCandidates[index];
                                final isSelected =
                                    selectedUserIds.contains(user.id);
                                return CheckboxListTile(
                                  dense: true,
                                  title: Text(user.name),
                                  subtitle: Text(
                                    user.isOnline ? 'Online' : 'Offline',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: user.isOnline
                                          ? Colors.teal
                                          : Colors.grey,
                                    ),
                                  ),
                                  value: isSelected,
                                  onChanged: (checked) {
                                    setDialogState(() {
                                      if (checked == true) {
                                        selectedUserIds.add(user.id);
                                      } else {
                                        selectedUserIds.remove(user.id);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
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
                  onPressed: selectedUserIds.isEmpty
                      ? null
                      : () => Navigator.pop(context, true),
                  child: Text('Add (${selectedUserIds.length})'),
                ),
              ],
            );
          },
        );
      },
    );

    if (added == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added ${selectedUserIds.length} user${selectedUserIds.length > 1 ? 's' : ''} to ${activeChat.name}',
          ),
          duration: const Duration(seconds: 2),
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
                    if (activeChat.isGroup)
                      CircleAvatar(
                        radius: 18,
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        child: const Icon(Icons.groups_rounded, size: 20),
                      )
                    else if (activeChat.avatarUrl.isNotEmpty)
                      CircleAvatar(
                        radius: 18,
                        backgroundImage: NetworkImage(activeChat.avatarUrl),
                      )
                    else
                      CircleAvatar(
                        radius: 18,
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        child: Text(
                          activeChat.name.isNotEmpty
                              ? activeChat.name[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activeChat.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          Row(
                            children: [
                              if (activeChat.isGroup && activeChat.isPrivate) ...[
                                const Icon(Icons.lock_rounded, size: 12, color: Colors.teal),
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
                          Icon(Icons.logout_rounded, size: 20, color: Colors.redAccent),
                          SizedBox(width: 12),
                          Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
                        ],
                      ),
                    ),
                  ];
                }

                return [
                  if (activeChat.isGroup) ...[
                    const PopupMenuItem(
                      value: 'add_users',
                      child: Row(
                        children: [
                          Icon(Icons.person_add_rounded, size: 20),
                          SizedBox(width: 12),
                          Text('Add Users'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'toggle_privacy',
                      child: Row(
                        children: [
                          Icon(
                            activeChat.isPrivate
                                ? Icons.lock_open_rounded
                                : Icons.lock_outline_rounded,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            activeChat.isPrivate
                                ? 'Make Group Public'
                                : 'Make Group Private',
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                  ],
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
                        Icon(Icons.logout_rounded, size: 20, color: Colors.redAccent),
                        SizedBox(width: 12),
                        Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
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
                    setState(() {
                      _selectedChat = chat;
                      LocalNotificationManager.setActiveChatId(chat.id);
                    });
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
