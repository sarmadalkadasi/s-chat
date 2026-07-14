import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:s_chat/widgets/message_bubble.dart';

final authenticatedUserId = FirebaseAuth.instance.currentUser!.uid;

class ChatMessages extends StatefulWidget {
  const ChatMessages({super.key});

  @override
  State<ChatMessages> createState() => _ChatMessagesState();
}

class _ChatMessagesState extends State<ChatMessages> {
  // Sync Profile Cache: Stores profile structures locally
  final Map<String, Map<String, dynamic>> _profileCache = {};

  // Tracks active network requests to avoid redundant simultaneous Firestore fetches
  final Set<String> _pendingFetches = {};

  /// Synchronously returns cached user data or schedules a fetch in the background.
  /// This eliminates the asynchronous microtask delay inside the UI rendering path.
  Map<String, dynamic>? _getProfileSync(String userId) {
    if (_profileCache.containsKey(userId)) {
      return _profileCache[userId];
    }

    // Schedule background fetch if not already pulling data
    if (!_pendingFetches.contains(userId)) {
      _pendingFetches.add(userId);

      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get()
          .then((doc) {
        if (mounted) {
          setState(() {
            _profileCache[userId] = doc.data() ?? {};
            _pendingFetches.remove(userId);
          });
        }
      })
          .catchError((_) {
        if (mounted) {
          setState(() {
            _pendingFetches.remove(userId);
          });
        }
      });
    }
    return null; // Return null temporarily; state change will trigger a fast redraw
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('chat_messages')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (ctx, chatSnapshot) {
        if (chatSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (chatSnapshot.hasError || !chatSnapshot.hasData || chatSnapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No messages found...'));
        }

        final chatDocs = chatSnapshot.data!.docs;

        return ListView.builder(
          reverse: true,
          itemCount: chatDocs.length,
          // Crucial for performance: caches pixels outside viewport to prevent layout thrashing
          cacheExtent: 300,
          itemBuilder: (context, index) {
            final chatMessage = chatDocs[index].data();
            final messageText = chatMessage['text'] ?? '';
            final String messageUserId = chatMessage['user_id'] ?? '';
            final isMe = authenticatedUserId == messageUserId;

            // --- TELEGRAM AVATAR GROUPING LOGIC ---
            bool showAvatar = false;
            if (!isMe) {
              if (index == 0) {
                showAvatar = true;
              } else {
                final nextMessageUserId = chatDocs[index - 1].data()['user_id'];
                if (messageUserId != nextMessageUserId) {
                  showAvatar = true;
                }
              }
            }

            final messageTimestamp = chatMessage['createdAt'] as Timestamp?;
            final formattedTime = messageTimestamp != null
                ? DateFormat('h:mm a').format(messageTimestamp.toDate())
                : '';

            // --- SYNCHRONOUS PROFILE LOOKUP ---
            final userData = _getProfileSync(messageUserId);
            final userName = userData?['username'] ?? 'Anonymous';
            final userImage = userData?['image_url'] ?? '';

            return MessageBubble(
              key: ValueKey(chatDocs[index].id), // Helps Flutter recycle elements accurately
              message: messageText,
              isMe: isMe,
              time: formattedTime,
              uname: userName,
              userImage: userImage,
              showAvatar: showAvatar,
            );
          },
        );
      },
    );
  }
}
