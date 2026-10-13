import 'package:flutter/material.dart';
import 'package:s_chat/models/replying_message.dart';
import 'package:s_chat/services/message_repository.dart';
import 'package:s_chat/widgets/chat_message.dart';
import 'package:s_chat/widgets/new_message.dart';
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

  bool _canJump = false;

  static const double _jumpButtonThreshold = 200;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
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

  void _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
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
          IconButton(
            onPressed: _signOut,
            icon: const Icon(Icons.power_settings_new),
          ),
        ],
      ),
      floatingActionButton: AnimatedSlide(
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
        child: Column(
          children: [
            Expanded(
              child: ChatMessages(
                scrollController: _scrollController,
                editingNotifier: _editingNotifier,
                replyingNotifier: _replyingNotifier,
              ),
            ),
            NewMessage(
              editingNotifier: _editingNotifier,
              replyingNotifier: _replyingNotifier,
            ),
          ],
        ),
      ),
    );
  }
}
