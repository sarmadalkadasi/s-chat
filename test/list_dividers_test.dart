import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:s_chat/models/chat_message.dart';
import 'package:s_chat/models/message_cluster.dart';
import 'package:s_chat/widgets/list_dividers.dart';
import 'package:s_chat/widgets/message_cluster.dart';
import 'package:sticky_headers/sticky_headers.dart';

void main() {
  group('List Dividers Tests', () {
    testWidgets('DateDividerWidget renders Today for current date', (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DateDividerWidget(date: now),
          ),
        ),
      );

      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('DateDividerWidget renders Yesterday for previous day', (tester) async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DateDividerWidget(date: yesterday),
          ),
        ),
      );

      expect(find.text('Yesterday'), findsOneWidget);
    });

    testWidgets('UnreadDividerWidget renders "Not Read Messages" banner', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UnreadDividerWidget(label: 'Not Read Messages'),
          ),
        ),
      );

      expect(find.text('Not Read Messages'), findsOneWidget);
      expect(find.byIcon(Icons.mark_chat_unread_outlined), findsOneWidget);
    });

    testWidgets('StickyHeader renders header and content correctly', (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                StickyHeader(
                  header: DateDividerWidget(date: now),
                  content: const Text('Sticky Content'),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Sticky Content'), findsOneWidget);
    });

    testWidgets('MessageClusterWidget renders fallback avatar when no user image URL', (tester) async {
      final scrollController = ScrollController();
      final Map<String, GlobalKey> messageKeys = {};

      final cluster = MessageCluster(
        userId: 'user_1',
        username: 'Alice',
        userImage: '',
        isMe: false,
        messages: [
          ChatMessage(
            id: '1',
            userId: 'user_1',
            text: 'Hello from Alice',
            username: 'Alice',
            userImage: '',
            createdAt: DateTime.now(),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: scrollController,
              children: [
                MessageClusterWidget(
                  cluster: cluster,
                  scrollController: scrollController,
                  messageKeys: messageKeys,
                ),
              ],
            ),
          ),
        ),
      );

      // Check user initial 'A' in avatar fallback container
      expect(find.text('A'), findsOneWidget);
      expect(find.text('Hello from Alice'), findsOneWidget);

      scrollController.dispose();
    });
  });
}
