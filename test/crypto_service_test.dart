import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:s_chat/services/crypto_service.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    CryptoService.instance.reset();
  });

  test('a message encrypted for a peer is decrypted by that peer', () async {
    final crypto = CryptoService.instance;

    final publicKeyA = await crypto.localPublicKey('user_a');
    final publicKeyB = await crypto.localPublicKey('user_b');
    expect(publicKeyA, isNotNull);
    expect(publicKeyB, isNotNull);

    crypto.cachePublicKey('user_a', publicKeyA!);
    crypto.cachePublicKey('user_b', publicKeyB!);

    const message = 'Hello, this is a secret!';
    final encrypted = await crypto.encryptForPeer(
      myUserId: 'user_a',
      peerUserId: 'user_b',
      plainText: message,
    );
    expect(encrypted, isNotNull);
    expect(encrypted!.iv, isNotEmpty);
    expect(encrypted.text, isNot(contains(message)));

    final decrypted = await crypto.decryptFromPeer(
      myUserId: 'user_b',
      peerUserId: 'user_a',
      encryptedText: encrypted.text,
      iv: encrypted.iv,
    );
    expect(decrypted, message);
  });

  test('a message cannot be decrypted by a third party', () async {
    final crypto = CryptoService.instance;

    final publicKeyA = await crypto.localPublicKey('user_a');
    final publicKeyB = await crypto.localPublicKey('user_b');
    final publicKeyC = await crypto.localPublicKey('user_c');
    crypto.cachePublicKey('user_a', publicKeyA!);
    crypto.cachePublicKey('user_b', publicKeyB!);
    crypto.cachePublicKey('user_c', publicKeyC!);

    final encrypted = await crypto.encryptForPeer(
      myUserId: 'user_a',
      peerUserId: 'user_b',
      plainText: 'secret',
    );

    final decrypted = await crypto.decryptFromPeer(
      myUserId: 'user_c',
      peerUserId: 'user_a',
      encryptedText: encrypted!.text,
      iv: encrypted.iv,
    );
    expect(decrypted, isNull);
  });

  test('a tampered message is rejected', () async {
    final crypto = CryptoService.instance;

    final publicKeyA = await crypto.localPublicKey('user_a');
    final publicKeyB = await crypto.localPublicKey('user_b');
    crypto.cachePublicKey('user_a', publicKeyA!);
    crypto.cachePublicKey('user_b', publicKeyB!);

    final encrypted = await crypto.encryptForPeer(
      myUserId: 'user_a',
      peerUserId: 'user_b',
      plainText: 'secret',
    );

    final tampered = '${encrypted!.text.substring(0, encrypted.text.length - 4)}AAAA';
    final decrypted = await crypto.decryptFromPeer(
      myUserId: 'user_b',
      peerUserId: 'user_a',
      encryptedText: tampered,
      iv: encrypted.iv,
    );
    expect(decrypted, isNull);
  });

  test('the same text produces a different ciphertext every time', () async {
    final crypto = CryptoService.instance;

    final publicKeyA = await crypto.localPublicKey('user_a');
    final publicKeyB = await crypto.localPublicKey('user_b');
    crypto.cachePublicKey('user_a', publicKeyA!);
    crypto.cachePublicKey('user_b', publicKeyB!);

    final first = await crypto.encryptForPeer(
      myUserId: 'user_a',
      peerUserId: 'user_b',
      plainText: 'same text',
    );
    final second = await crypto.encryptForPeer(
      myUserId: 'user_a',
      peerUserId: 'user_b',
      plainText: 'same text',
    );

    expect(first!.text, isNot(second!.text));
    expect(first.iv, isNot(second.iv));
  });
}
