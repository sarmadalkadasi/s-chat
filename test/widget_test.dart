import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:s_chat/widgets/message_bubble.dart';

void main() {
  testWidgets('MessageBubble renders message text and username', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: 'Hello world',
            isMe: false,
            time: '10:00 AM',
            uname: 'Alice',
            userImage: '',
            showAvatar: true,
          ),
        ),
      ),
    );

    expect(find.text('Hello world'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('10:00 AM'), findsOneWidget);
  });
}
