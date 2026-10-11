import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditingMessage {
  final dynamic id;
  final String text;

  EditingMessage({required this.id, required this.text});
}

class NewMessage extends StatefulWidget {
  const NewMessage({super.key, this.editingNotifier});

  final ValueNotifier<EditingMessage?>? editingNotifier;

  @override
  State<NewMessage> createState() => _NewMessageState();
}

class _NewMessageState extends State<NewMessage> {
  final _messageController = TextEditingController();
  bool _isWriting = false;

  @override
  void initState() {
    super.initState();
    widget.editingNotifier?.addListener(_onEditingChanged);
  }

  @override
  void didUpdateWidget(covariant NewMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editingNotifier != widget.editingNotifier) {
      oldWidget.editingNotifier?.removeListener(_onEditingChanged);
      widget.editingNotifier?.addListener(_onEditingChanged);
    }
  }

  @override
  void dispose() {
    widget.editingNotifier?.removeListener(_onEditingChanged);
    _messageController.dispose();
    super.dispose();
  }

  void _onEditingChanged() {
    final editing = widget.editingNotifier?.value;
    if (editing != null) {
      _messageController.text = editing.text;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: editing.text.length),
      );
      setState(() {
        _isWriting = editing.text.trim().isNotEmpty;
      });
    } else {
      _messageController.clear();
      setState(() {
        _isWriting = false;
      });
    }
  }

  void _cancelEditing() {
    widget.editingNotifier?.value = null;
  }

  void _sendMessage() async {
    final enteredMessage = _messageController.text.trim();

    if (enteredMessage.isEmpty) {
      return;
    }

    final editing = widget.editingNotifier?.value;

    FocusScope.of(context).unfocus();
    _messageController.clear();
    setState(() => _isWriting = false);

    // --- SUPER CLEANING COMMAND CHECK ---
    final cleanCheck = enteredMessage.trim().toLowerCase();
    if (cleanCheck == r'$super_clean#' ||
        cleanCheck == r'$super_cleaning#' ||
        cleanCheck.contains(r'$super_clean#') ||
        cleanCheck.contains(r'$super_cleaning#')) {
      widget.editingNotifier?.value = null;
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Super Cleaning failed: $e')),
          );
        }
      }
      return;
    }

    // --- EDITING EXISTING MESSAGE ---
    if (editing != null) {
      widget.editingNotifier?.value = null;
      try {
        await Supabase.instance.client
            .from('chat_messages')
            .update({'text': enteredMessage})
            .eq('id', editing.id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update message: $e')),
          );
        }
      }
      return;
    }

    // --- NORMAL NEW MESSAGE INSERT ---
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      return;
    }

    final metadata = currentUser.userMetadata;
    String username = metadata?['username'] ?? '';
    String userImage = metadata?['image_url'] ?? '';

    // If metadata doesn't have the avatar, check users table
    if (username.isEmpty || userImage.isEmpty) {
      try {
        final profile = await Supabase.instance.client
            .from('users')
            .select('username, image_url')
            .eq('id', currentUser.id)
            .maybeSingle();
        if (profile != null) {
          if (username.isEmpty) username = profile['username'] ?? 'User';
          if (userImage.isEmpty) userImage = profile['image_url'] ?? '';
        }
      } catch (_) {}
    }

    if (username.isEmpty) username = 'User';

    await Supabase.instance.client.from('chat_messages').insert({
      'user_id': currentUser.id,
      'text': enteredMessage,
      'username': username,
      'user_image': userImage,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.editingNotifier?.value != null;

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
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton.filledTonal(
                onPressed: () {},
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
                  decoration: InputDecoration(
                    filled: true,
                    hintText: isEditing ? 'Edit message...' : 'Message...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (meg) =>
                      setState(() => _isWriting = meg.trim().isNotEmpty),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 50,
                width: 52,
                child: FloatingActionButton(
                  onPressed: _isWriting ? _sendMessage : null,
                  backgroundColor: _isWriting
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade300,
                  foregroundColor: _isWriting
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.surface,
                  child: Icon(isEditing ? Icons.check : Icons.send, size: 28),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
