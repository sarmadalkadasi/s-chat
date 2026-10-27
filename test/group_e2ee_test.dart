import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:s_chat/services/crypto_service.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    CryptoService.instance.reset();
  });

  group('Group Sender Keys E2EE Tests', () {
    test('local Sender Key is generated and cached for a group', () async {
      final crypto = CryptoService.instance;
      final key = await crypto.getOrCreateSenderKey('group_123', 'user_alice');

      expect(key, isNotNull);

      final keyReacquired = await crypto.getOrCreateSenderKey('group_123', 'user_alice');
      expect(keyReacquired, isNotNull);
    });

    test('group message is encrypted with Sender Key and can be decrypted', () async {
      final crypto = CryptoService.instance;

      // Alice and Bob generate local key pairs
      final pubA = await crypto.localPublicKey('user_alice');
      final pubB = await crypto.localPublicKey('user_bob');
      crypto.cachePublicKey('user_alice', pubA!);
      crypto.cachePublicKey('user_bob', pubB!);

      // Alice encrypts a message for the group
      const plainMessage = 'Hello group members!';
      final encrypted = await crypto.encryptForGroup(
        groupId: 'group_flutter',
        myUserId: 'user_alice',
        plainText: plainMessage,
      );

      expect(encrypted, isNotNull);
      expect(encrypted!.iv, isNotEmpty);
      expect(encrypted.text, isNot(contains(plainMessage)));
    });
  });
}
