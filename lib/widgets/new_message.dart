import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NewMessage extends StatefulWidget {
  const NewMessage({super.key});

  @override
  State<NewMessage> createState() => _NewMessageState();
}

class _NewMessageState extends State<NewMessage> {
  final _messageController = TextEditingController();
  bool _isWriting = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    final enteredMessage = _messageController.text.trim();

    if (enteredMessage.isEmpty) {
      return;
    }
    FocusScope.of(context).unfocus();
    _messageController.clear();
    setState(() => _isWriting = false);

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
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        spacing: 8,
        children: [
          IconButton.filledTonal(onPressed: () {}, icon: Icon(Icons.add)),
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
                hintText: 'Message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
              ),
              onChanged: (meg) =>
                  setState(() => _isWriting = meg.trim().isNotEmpty),
            ),
          ),
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
              child: Icon(Icons.send, size: 30),
            ),
          ),
        ],
      ),
    );
  }
}
