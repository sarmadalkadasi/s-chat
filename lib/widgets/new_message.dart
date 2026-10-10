import 'package:cloud_firestore/cloud_firestore.dart';
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

    // send message to firebase
    final uid = Supabase.instance.client.auth.currentUser!.id;
    await FirebaseFirestore.instance.collection('chat_messages').add({
      'chat_id': 1,
      'user_id': uid,
      'text': enteredMessage,
      'media': null,
      'createdAt': Timestamp.now(),
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
