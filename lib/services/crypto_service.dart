import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ciphertext produced by [CryptoService.encryptForPeer] or [CryptoService.encryptForGroup].
class EncryptedPayload {
  /// Base64 of `cipherText || mac`.
  final String text;

  /// Base64 of the AES-GCM nonce.
  final String iv;

  const EncryptedPayload({required this.text, required this.iv});
}

/// End-to-end encryption for direct (1-to-1) and group chats (Signal Protocol Sender Keys).
class CryptoService {
  CryptoService._();

  /// Shared instance, so the key caches are reused across the whole app.
  static final CryptoService instance = CryptoService._();

  static const String _privateKeyPrefix = 'private_key_';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  final KeyExchangeAlgorithm _keyExchange = X25519();
  final Cipher _cipher = AesGcm.with256bits();

  /// Public keys already fetched from Supabase, keyed by user id.
  final Map<String, String> _publicKeys = {};

  /// Shared secrets already derived, keyed by `<myUserId>:<peerUserId>`.
  final Map<String, SecretKey> _sharedSecrets = {};

  /// Sender keys derived per group and sender: `<groupId>:<senderUserId>`.
  final Map<String, SecretKey> _senderKeys = {};

  /// Resolved lazily, so the service can be used before Supabase is ready.
  SupabaseClient get _supabase => Supabase.instance.client;

  /// Creates the key pair on first use and publishes the public key so peers
  /// are able to encrypt messages for this user.
  Future<void> initUserKeys(String userId) async {
    if (userId.isEmpty) return;

    final publicKey = await localPublicKey(userId);
    if (publicKey == null) return;

    try {
      final updated = await _supabase
          .from('users')
          .update({'public_key': publicKey})
          .eq('id', userId)
          .select('id');

      if (updated.isEmpty) {
        await _supabase.from('users').upsert({
          'id': userId,
          'public_key': publicKey,
        });
      }
      _publicKeys[userId] = publicKey;
    } catch (e) {
      debugPrint('CryptoService: could not publish public key: $e');
    }
  }

  /// Makes sure this device owns a key pair for [userId] and returns the public key
  Future<String?> localPublicKey(String userId) async {
    if (userId.isEmpty) return null;

    final seed = await _privateKeySeed(userId);
    if (seed == null) return null;

    return _publicKeyOfSeed(seed);
  }

  /// Registers a public key that is already known, so it is not fetched again.
  void cachePublicKey(String userId, String publicKey) {
    if (userId.isEmpty || publicKey.isEmpty) return;
    _publicKeys[userId] = publicKey;
  }

  /// Drops the cached keys, so they are fetched and derived again.
  @visibleForTesting
  void reset() {
    _publicKeys.clear();
    _sharedSecrets.clear();
    _senderKeys.clear();
  }

  /// Public key of [userId] as stored in the `users` table.
  Future<String?> publicKeyOf(String userId) async {
    if (userId.isEmpty) return null;

    final cached = _publicKeys[userId];
    if (cached != null) return cached;

    try {
      final row = await _supabase
          .from('users')
          .select('public_key')
          .eq('id', userId)
          .maybeSingle();
      final key = row?['public_key']?.toString();
      if (key != null && key.isNotEmpty) {
        _publicKeys[userId] = key;
        return key;
      }
    } catch (e) {
      debugPrint('CryptoService: could not read public key: $e');
    }
    return null;
  }

  /// Encrypts [plainText] for 1-to-1 direct message using ECDH shared secret.
  Future<EncryptedPayload?> encryptForPeer({
    required String myUserId,
    required String peerUserId,
    required String plainText,
  }) async {
    final sharedSecret = await _sharedSecret(myUserId, peerUserId);
    if (sharedSecret == null) return null;

    try {
      final secretBox = await _cipher.encrypt(
        utf8.encode(plainText),
        secretKey: sharedSecret,
      );
      return EncryptedPayload(
        text: base64Encode([...secretBox.cipherText, ...secretBox.mac.bytes]),
        iv: base64Encode(secretBox.nonce),
      );
    } catch (e) {
      debugPrint('CryptoService: encryption failed: $e');
      return null;
    }
  }

  /// Decrypts a 1-to-1 message encrypted for [peerUserId].
  Future<String?> decryptFromPeer({
    required String myUserId,
    required String peerUserId,
    required String encryptedText,
    required String iv,
  }) async {
    var sharedSecret = await _sharedSecret(myUserId, peerUserId);
    if (sharedSecret == null) return null;

    var clear = await _decrypt(sharedSecret, encryptedText, iv);
    if (clear != null) return clear;

    _publicKeys.remove(peerUserId);
    _sharedSecrets.remove('$myUserId:$peerUserId');
    sharedSecret = await _sharedSecret(myUserId, peerUserId);
    if (sharedSecret == null) return null;

    return _decrypt(sharedSecret, encryptedText, iv);
  }

  /// Retrieves or generates a local Sender Key for [groupId] and [myUserId]
  Future<SecretKey?> getOrCreateSenderKey(String groupId, String myUserId) async {
    if (groupId.isEmpty || myUserId.isEmpty) return null;
    final cacheKey = '$groupId:$myUserId';
    final cached = _senderKeys[cacheKey];
    if (cached != null) return cached;

    final storageKey = 'sender_key_${groupId}_$myUserId';
    final stored = await _storage.read(key: storageKey);
    if (stored != null && stored.isNotEmpty) {
      try {
        final keyBytes = base64Decode(stored);
        final secretKey = SecretKey(keyBytes);
        _senderKeys[cacheKey] = secretKey;
        return secretKey;
      } catch (_) {}
    }

    final newSecretKey = await _cipher.newSecretKey();
    final keyBytes = await newSecretKey.extractBytes();
    await _storage.write(key: storageKey, value: base64Encode(keyBytes));
    _senderKeys[cacheKey] = newSecretKey;
    return newSecretKey;
  }

  /// Encrypts [plainText] for [groupId] using [myUserId]'s Sender Key
  Future<EncryptedPayload?> encryptForGroup({
    required String groupId,
    required String myUserId,
    required String plainText,
  }) async {
    final senderKey = await getOrCreateSenderKey(groupId, myUserId);
    if (senderKey == null) return null;

    try {
      final secretBox = await _cipher.encrypt(
        utf8.encode(plainText),
        secretKey: senderKey,
      );
      return EncryptedPayload(
        text: base64Encode([...secretBox.cipherText, ...secretBox.mac.bytes]),
        iv: base64Encode(secretBox.nonce),
      );
    } catch (e) {
      debugPrint('CryptoService: group encryption failed: $e');
      return null;
    }
  }

  /// Decrypts a group message sent by [senderUserId] using that sender's Sender Key
  Future<String?> decryptFromGroupSender({
    required String groupId,
    required String senderUserId,
    required String myUserId,
    required String encryptedText,
    required String iv,
  }) async {
    final cacheKey = '$groupId:$senderUserId';
    var senderKey = _senderKeys[cacheKey];

    if (senderKey == null) {
      if (senderUserId == myUserId) {
        senderKey = await getOrCreateSenderKey(groupId, myUserId);
      } else {
        try {
          final row = await _supabase
              .from('group_sender_keys')
              .select('encrypted_key, iv')
              .eq('group_id', groupId)
              .eq('sender_id', senderUserId)
              .eq('recipient_id', myUserId)
              .maybeSingle();

          if (row != null) {
            final encKey = row['encrypted_key']?.toString();
            final keyIv = row['iv']?.toString();
            if (encKey != null && keyIv != null) {
              final rawKeyBase64 = await decryptFromPeer(
                myUserId: myUserId,
                peerUserId: senderUserId,
                encryptedText: encKey,
                iv: keyIv,
              );
              if (rawKeyBase64 != null) {
                final keyBytes = base64Decode(rawKeyBase64);
                senderKey = SecretKey(keyBytes);
                _senderKeys[cacheKey] = senderKey;
              }
            }
          }
        } catch (e) {
          debugPrint('CryptoService: could not fetch group sender key: $e');
        }
      }
    }

    if (senderKey == null) return null;
    return _decrypt(senderKey, encryptedText, iv);
  }

  /// Encrypts and distributes local Sender Key to all group [memberIds]
  Future<void> distributeSenderKey({
    required String groupId,
    required String myUserId,
    required List<String> memberIds,
  }) async {
    final senderKey = await getOrCreateSenderKey(groupId, myUserId);
    if (senderKey == null) return;

    final keyBytes = await senderKey.extractBytes();
    final rawKeyBase64 = base64Encode(keyBytes);

    List<String> targetMembers = List.from(memberIds);
    if (targetMembers.length <= 1) {
      try {
        final rows = await _supabase
            .from('group_members')
            .select('user_id')
            .eq('group_id', groupId);
        for (final row in rows as List<dynamic>) {
          final uid = row['user_id']?.toString();
          if (uid != null && uid.isNotEmpty && !targetMembers.contains(uid)) {
            targetMembers.add(uid);
          }
        }
      } catch (e) {
        debugPrint('CryptoService: failed to query group_members: $e');
      }
    }

    for (final memberId in targetMembers) {
      if (memberId == myUserId || memberId.isEmpty) continue;

      final encryptedKey = await encryptForPeer(
        myUserId: myUserId,
        peerUserId: memberId,
        plainText: rawKeyBase64,
      );

      if (encryptedKey != null) {
        try {
          await _supabase.from('group_sender_keys').upsert({
            'group_id': groupId,
            'sender_id': myUserId,
            'recipient_id': memberId,
            'encrypted_key': encryptedKey.text,
            'iv': encryptedKey.iv,
          });
        } catch (e) {
          debugPrint('CryptoService: failed to distribute sender key to $memberId: $e');
        }
      }
    }
  }

  Future<String?> _decrypt(
    SecretKey sharedSecret,
    String encryptedText,
    String iv,
  ) async {
    try {
      final payload = base64Decode(encryptedText);
      final macLength = _cipher.macAlgorithm.macLength;
      if (payload.length < macLength) return null;

      final secretBox = SecretBox(
        payload.sublist(0, payload.length - macLength),
        nonce: base64Decode(iv),
        mac: Mac(payload.sublist(payload.length - macLength)),
      );
      final clearBytes = await _cipher.decrypt(
        secretBox,
        secretKey: sharedSecret,
      );
      return utf8.decode(clearBytes);
    } catch (e) {
      debugPrint('CryptoService: decryption failed: $e');
      return null;
    }
  }

  Future<List<int>?> _privateKeySeed(String userId) async {
    final storageKey = '$_privateKeyPrefix$userId';
    final stored = await _storage.read(key: storageKey);
    if (stored != null && stored.isNotEmpty) {
      try {
        return base64Decode(stored);
      } catch (_) {}
    }

    final keyPair = await _keyExchange.newKeyPair() as SimpleKeyPair;
    final seed = await keyPair.extractPrivateKeyBytes();
    await _storage.write(key: storageKey, value: base64Encode(seed));
    return seed;
  }

  Future<String?> _publicKeyOfSeed(List<int> seed) async {
    try {
      final keyPair = await _keyExchange.newKeyPairFromSeed(
        seed,
      ) as SimpleKeyPair;
      final publicKey = await keyPair.extractPublicKey();
      return base64Encode(publicKey.bytes);
    } catch (e) {
      debugPrint('CryptoService: invalid private key: $e');
      return null;
    }
  }

  Future<SecretKey?> _sharedSecret(String myUserId, String peerUserId) async {
    if (myUserId.isEmpty || peerUserId.isEmpty) return null;

    final cacheKey = '$myUserId:$peerUserId';
    final cached = _sharedSecrets[cacheKey];
    if (cached != null) return cached;

    final peerPublicKey = await publicKeyOf(peerUserId);
    if (peerPublicKey == null) return null;

    final stored = await _storage.read(key: '$_privateKeyPrefix$myUserId');
    if (stored == null || stored.isEmpty) return null;

    try {
      final keyPair = await _keyExchange.newKeyPairFromSeed(
        base64Decode(stored),
      );
      final secret = await _keyExchange.sharedSecretKey(
        keyPair: keyPair,
        remotePublicKey: SimplePublicKey(
          base64Decode(peerPublicKey),
          type: KeyPairType.x25519,
        ),
      );
      _sharedSecrets[cacheKey] = secret;
      return secret;
    } catch (e) {
      debugPrint('CryptoService: key exchange failed: $e');
      return null;
    }
  }
}
