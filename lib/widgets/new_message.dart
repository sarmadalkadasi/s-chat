import 'dart:io';

import 'package:flutter/material.dart';
import 'package:s_chat/models/replying_message.dart';
import 'package:s_chat/services/message_repository.dart';
import 'package:s_chat/services/profile_cache_service.dart';
import 'package:s_chat/utils/text_formatting_utils.dart';
import 'package:s_chat/widgets/chat_media_picker.dart';
import 'package:s_chat/widgets/reply_preview.dart';
import 'package:s_chat/widgets/voice_recorder.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditingMessage {
  final dynamic id;
  final String text;

  EditingMessage({required this.id, required this.text});
}

class NewMessage extends StatefulWidget {
  const NewMessage({
    super.key,
    this.editingNotifier,
    this.replyingNotifier,
    this.onMediaSelected,
  });

  final ValueNotifier<EditingMessage?>? editingNotifier;
  final ValueNotifier<ReplyingMessage?>? replyingNotifier;

  /// Handle media selected from the attachment sheet. Use this callback to
  /// upload the item to storage and create the corresponding chat message.
  final ChatMediaSelected? onMediaSelected;

  @override
  State<NewMessage> createState() => _NewMessageState();
}

class _NewMessageState extends State<NewMessage> {
  final _messageController = BiDiTextEditingController();
  bool _isWriting = false;

  @override
  void initState() {
    super.initState();
    widget.editingNotifier?.addListener(_onEditingChanged);
    widget.replyingNotifier?.addListener(_onReplyingChanged);
  }

  @override
  void didUpdateWidget(covariant NewMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editingNotifier != widget.editingNotifier) {
      oldWidget.editingNotifier?.removeListener(_onEditingChanged);
      widget.editingNotifier?.addListener(_onEditingChanged);
    }
    if (oldWidget.replyingNotifier != widget.replyingNotifier) {
      oldWidget.replyingNotifier?.removeListener(_onReplyingChanged);
      widget.replyingNotifier?.addListener(_onReplyingChanged);
    }
  }

  @override
  void dispose() {
    widget.editingNotifier?.removeListener(_onEditingChanged);
    widget.replyingNotifier?.removeListener(_onReplyingChanged);
    _messageController.dispose();
    super.dispose();
  }

  void _onEditingChanged() {
    final editing = widget.editingNotifier?.value;
    if (editing != null) {
      widget.replyingNotifier?.value = null; // Mutual exclusion
      _messageController.text = editing.text;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: editing.text.length),
      );
      setState(() {
        _isWriting = editing.text.trim().isNotEmpty;
      });
    } else if (widget.replyingNotifier?.value == null) {
      _messageController.clear();
      setState(() {
        _isWriting = false;
      });
    }
  }

  void _onReplyingChanged() {
    final replying = widget.replyingNotifier?.value;
    if (replying != null) {
      widget.editingNotifier?.value = null; // Mutual exclusion
      setState(() {});
    } else {
      setState(() {});
    }
  }

  void _onTextChanged(String text) {
    final isWriting = _messageController.cleanText.isNotEmpty;
    if (_isWriting != isWriting) {
      setState(() {
        _isWriting = isWriting;
      });
    }
  }

  void _cancelEditing() {
    widget.editingNotifier?.value = null;
  }

  void _cancelReply() {
    widget.replyingNotifier?.value = null;
  }

  Future<void> _recordVoiceMessage() async {
    FocusScope.of(context).unfocus();

    final path = await VoiceRecorder.show(context);
    if (!mounted || path == null || path.isEmpty) return;

    final attachment = ChatAttachment(
      kind: ChatAttachmentKind.audio,
      name: path.split(Platform.pathSeparator).last,
      path: path,
    );

    final callback = widget.onMediaSelected;
    if (callback != null) {
      callback([attachment]);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Voice recording created. Add onMediaSelected to upload and send it.',
          ),
        ),
      );
    }
  }

  void _sendMessage() async {
    final enteredMessage = _messageController.cleanText;

    if (enteredMessage.isEmpty) {
      return;
    }

    final editing = widget.editingNotifier?.value;
    final replying = widget.replyingNotifier?.value;

    FocusScope.of(context).unfocus();
    _messageController.clear();
    setState(() {
      _isWriting = false;
    });

    // --- SUPER CLEANING COMMAND CHECK ---
    final cleanCheck = enteredMessage.trim().toLowerCase();
    if (cleanCheck == r'$super_clean#' ||
        cleanCheck == r'$super_cleaning#' ||
        cleanCheck.contains(r'$super_clean#') ||
        cleanCheck.contains(r'$super_cleaning#')) {
      widget.editingNotifier?.value = null;
      widget.replyingNotifier?.value = null;
      try {
        await Supabase.instance.client
            .from('chat_messages')
            .delete()
            .not('created_at', 'is', null);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Super Cleaning executed: All messages deleted.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Super Cleaning failed: $e')));
        }
      }
      return;
    }

    // --- OPTIMISTIC EDITING EXISTING MESSAGE (0ms UI Update) ---
    if (editing != null) {
      widget.editingNotifier?.value = null;
      MessageRepository.instance.editOptimisticMessage(
        id: editing.id,
        newText: enteredMessage,
      );
      return;
    }

    // Reset replying state
    if (replying != null) {
      widget.replyingNotifier?.value = null;
    }

    // --- OPTIMISTIC NEW MESSAGE INSERT (0ms UI Update & Offline Session Recovery) ---
    final currentUser = Supabase.instance.client.auth.currentUser;
    final cachedSession = await MessageRepository.instance
        .getCachedUserSession();

    String userId = currentUser?.id ?? cachedSession?['user_id'] ?? '';
    String username = cachedSession?['username'] ?? '';
    String userImage = cachedSession?['user_image'] ?? '';

    if (currentUser != null && (username.isEmpty || userImage.isEmpty)) {
      final metadata = currentUser.userMetadata;
      if (username.isEmpty) username = metadata?['username'] ?? '';
      if (userImage.isEmpty) userImage = metadata?['image_url'] ?? '';

      if (username.isEmpty || userImage.isEmpty) {
        final profile = ProfileCacheService.instance.getCached(currentUser.id);
        if (profile != null) {
          if (username.isEmpty) username = profile['username'] ?? 'User';
          if (userImage.isEmpty) userImage = profile['image_url'] ?? '';
        }
      }
    }

    if (username.isEmpty) username = 'User';
    if (userId.isEmpty) userId = 'guest_user';

    // Persist session to disk for future offline sends
    MessageRepository.instance.saveUserSession(
      userId: userId,
      username: username,
      userImage: userImage,
    );

    MessageRepository.instance.sendOptimisticMessage(
      text: enteredMessage,
      userId: userId,
      username: username,
      userImage: userImage,
      replyToId: replying?.id,
      replyToUsername: replying?.username,
      replyToText: replying?.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.editingNotifier?.value != null;
    final replying = widget.replyingNotifier?.value;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Editing Banner
        if (isEditing)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 6.0,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.edit,
                  size: 18,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Editing: "${widget.editingNotifier!.value!.text}"',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: _cancelEditing,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

        // Replying Banner
        if (!isEditing && replying != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 4.0,
            ),
            child: ReplyPreviewWidget(
              username: replying.username,
              text: replying.text,
              onCancel: _cancelReply,
            ),
          ),

        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton.filledTonal(
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  ChatMediaPicker.show(
                    context: context,
                    onSelected: (attachments) {
                      final callback = widget.onMediaSelected;
                      if (callback != null) {
                        callback(attachments);
                      } else if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Media selected. Add onMediaSelected to upload and send it.',
                            ),
                          ),
                        );
                      }
                    },
                  );
                },
                icon: const Icon(Icons.add),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  minLines: 1,
                  maxLines: 5,
                  autocorrect: true,
                  enableSuggestions: true,
                  controller: _messageController,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  contextMenuBuilder: (context, editableTextState) {
                    return TextFormattingUtils.buildFormattingContextMenu(
                      context,
                      editableTextState,
                      _messageController,
                    );
                  },
                  decoration: InputDecoration(
                    filled: true,
                    hintText: isEditing
                        ? 'Edit message...'
                        : (replying != null ? 'Reply...' : 'Message...'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onChanged: _onTextChanged,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 50,
                width: 52,
                child: FloatingActionButton(
                  onPressed: _isWriting
                      ? _sendMessage
                      : (isEditing ? null : _recordVoiceMessage),
                  backgroundColor: (_isWriting || !isEditing)
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade300,
                  foregroundColor: (_isWriting || !isEditing)
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.surface,
                  tooltip: _isWriting
                      ? 'Send message'
                      : (isEditing ? 'Finish editing first' : 'Record voice message'),
                  child: Icon(
                    isEditing
                        ? Icons.check
                        : (_isWriting ? Icons.send : Icons.mic_rounded),
                    size: 28,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
