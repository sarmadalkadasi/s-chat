import 'package:flutter_test/flutter_test.dart';
import 'package:s_chat/models/chat_message.dart';

void main() {
  test('the routing envelope survives an encrypted body', () {
    final encoded = ChatMessage.encodeChatText(
      text: 'BASE64CIPHERTEXT',
      chatId: 'dm_user_a_user_b',
      recipientId: 'user_b',
    );

    final meta = ChatMessage.extractMeta(encoded);
    expect(meta?['chat_id'], 'dm_user_a_user_b');
    expect(meta?['recipient_id'], 'user_b');

    final message = ChatMessage.fromMap({
      'id': 1,
      'user_id': 'user_a',
      'text': encoded,
      'username': 'A',
      'user_image': '',
      'iv': 'BASE64NONCE',
    });
    expect(message.cleanText, 'BASE64CIPHERTEXT');
    expect(message.iv, 'BASE64NONCE');
    expect(message.chatId, 'dm_user_a_user_b');
    expect(message.recipientId, 'user_b');
  });

  test('a row without an iv stays a plain message', () {
    final message = ChatMessage.fromMap({
      'id': 1,
      'user_id': 'user_a',
      'text': 'hello',
      'username': 'A',
      'user_image': '',
    });
    expect(message.iv, isNull);
    expect(message.text, 'hello');
  });

  test('copyWith only replaces the given values', () {
    final message = ChatMessage(
      id: 1,
      userId: 'user_a',
      text: 'hello',
      username: 'A',
      userImage: '',
      replyToText: 'quoted',
      iv: 'NONCE',
    );

    final updated = message.copyWith(text: 'new text');
    expect(updated.text, 'new text');
    expect(updated.replyToText, 'quoted');
    expect(updated.iv, 'NONCE');
    expect(updated.id, 1);
  });
}
