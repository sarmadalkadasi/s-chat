import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:s_chat/models/chat_item.dart';
import 'package:s_chat/models/chat_message.dart';
import 'package:s_chat/widgets/chat/chat_list.dart';

void main() {
  group('ChatList Widget Tests', () {
    test('ChatItem model initializes correctly', () {
      final now = DateTime.now();
      final item = ChatItem(
        id: '1',
        name: 'Alice',
        avatarUrl: 'https://example.com/avatar.jpg',
        lastMessage: 'Hello there!',
        lastMessageTime: now,
        unreadCount: 2,
        isGroup: false,
        isOnline: true,
      );

      expect(item.id, '1');
      expect(item.name, 'Alice');
      expect(item.lastMessage, 'Hello there!');
      expect(item.unreadCount, 2);
      expect(item.isGroup, false);
      expect(item.isOnline, true);
      expect(item.isPrivate, false);
    });

    test('ChatItem copyWith works correctly', () {
      final item = ChatItem(
        id: 'group_1',
        name: 'Developers',
        avatarUrl: '',
        lastMessage: 'Hello team',
        isGroup: true,
        isPrivate: false,
      );

      final updated = item.copyWith(isPrivate: true, name: 'Core Devs');
      expect(updated.id, 'group_1');
      expect(updated.name, 'Core Devs');
      expect(updated.isGroup, true);
      expect(updated.isPrivate, true);
    });

    testWidgets('ChatList renders search bar and loads list view', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatList(),
          ),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search chats & groups...'), findsOneWidget);
    });

    test('ChatMessage separation: group messages do not leak into private chats and vice versa', () {
      final groupMsg = ChatMessage(
        id: '1',
        userId: 'user_alice',
        text: ChatMessage.encodeChatText(
          text: 'Hello group!',
          chatId: 'group_flutter_devs',
        ),
        username: 'Alice',
        userImage: '',
        chatId: 'group_flutter_devs',
      );

      final directMsg = ChatMessage(
        id: '2',
        userId: 'user_alice',
        text: ChatMessage.encodeChatText(
          text: 'Hey Bob, private message',
          chatId: 'dm_user_alice_user_bob',
          recipientId: 'user_bob',
        ),
        username: 'Alice',
        userImage: '',
        chatId: 'dm_user_alice_user_bob',
        recipientId: 'user_bob',
      );

      // Group message checks:
      expect(groupMsg.isGroup, true);
      expect(groupMsg.cleanText, 'Hello group!');
      expect(
        groupMsg.matchesChat(
          activeChatId: 'group_flutter_devs',
          isGroup: true,
          currentUserId: 'user_bob',
        ),
        true,
      );
      // Group message must NEVER show in private chats!
      expect(
        groupMsg.matchesChat(
          activeChatId: 'user_alice',
          isGroup: false,
          currentUserId: 'user_bob',
        ),
        false,
      );
      expect(
        groupMsg.matchesChat(
          activeChatId: 'group_other',
          isGroup: true,
          currentUserId: 'user_bob',
        ),
        false,
      );

      // Direct message checks:
      expect(directMsg.isGroup, false);
      expect(directMsg.cleanText, 'Hey Bob, private message');
      // Direct message must show in direct chat with user_alice
      expect(
        directMsg.matchesChat(
          activeChatId: 'user_alice',
          isGroup: false,
          currentUserId: 'user_bob',
        ),
        true,
      );
      // Direct message must NEVER show in group chats!
      expect(
        directMsg.matchesChat(
          activeChatId: 'group_flutter_devs',
          isGroup: true,
          currentUserId: 'user_bob',
        ),
        false,
      );
    });
  });
}
