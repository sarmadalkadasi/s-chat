import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:s_chat/models/chat_item.dart';
import 'package:s_chat/models/chat_message.dart';
import 'package:s_chat/services/crypto_service.dart';
import 'package:s_chat/services/profile_cache_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Current local sync phase for a media message.
/// The standard Supabase Storage upload API used below does not expose byte-level
/// progress, so `uploading` is represented by an indeterminate progress bar.
enum MediaSyncPhase { queued, uploading, savingMessage }

class MediaSyncStatus {
  final MediaSyncPhase phase;

  const MediaSyncStatus(this.phase);
}

class MessageRepository {
  MessageRepository._();
  static final MessageRepository instance = MessageRepository._();

  static const int pageSize = 30;

  /// Shown instead of a body that could not be decrypted.
  static const String decryptionFailedText = '🔒 فشل فك تشفير هذه الرسالة';

  /// Create this as a PRIVATE bucket in Supabase Storage.
  static const String mediaStorageBucket = 'chat-media';

  final CryptoService _crypto = CryptoService.instance;

  final StreamController<List<ChatMessage>> _messagesController =
      StreamController<List<ChatMessage>>.broadcast();

  final StreamController<bool> _isOnlineController =
      StreamController<bool>.broadcast();
  final StreamController<Map<String, MediaSyncStatus>> _mediaSyncController =
      StreamController<Map<String, MediaSyncStatus>>.broadcast();
  final Map<String, MediaSyncStatus> _mediaSyncStatuses = {};

  List<ChatMessage> _messages = [];
  List<Map<String, dynamic>> _outbox = [];
  RealtimeChannel? _realtimeChannel;

  bool _isLoadingOlder = false;
  bool _hasMoreOlderMessages = true;
  bool _initialized = false;
  Future<void>? _initFuture;
  bool _isProcessingOutbox = false;
  bool _isOnline = true;
  DateTime? _lastReadTimestamp;
  final List<ChatItem> _customGroups = [];

  Stream<List<ChatMessage>> get messagesStream => _messagesController.stream;
  Stream<bool> get isOnlineStream => _isOnlineController.stream;
  Stream<Map<String, MediaSyncStatus>> get mediaSyncStatusStream =>
      _mediaSyncController.stream;
  Map<String, MediaSyncStatus> get mediaSyncStatuses =>
      Map.unmodifiable(_mediaSyncStatuses);
  List<ChatMessage> get currentMessages => List.unmodifiable(_messages);

  void _setMediaSyncStatus(String messageId, MediaSyncPhase phase) {
    _mediaSyncStatuses[messageId] = MediaSyncStatus(phase);
    if (!_mediaSyncController.isClosed) {
      _mediaSyncController.add(Map.unmodifiable(_mediaSyncStatuses));
    }
  }

  void _clearMediaSyncStatus(String messageId) {
    if (_mediaSyncStatuses.remove(messageId) != null &&
        !_mediaSyncController.isClosed) {
      _mediaSyncController.add(Map.unmodifiable(_mediaSyncStatuses));
    }
  }

  bool get isLoadingOlder => _isLoadingOlder;
  bool get hasMoreOlderMessages => _hasMoreOlderMessages;
  bool get isOnline => _isOnline;
  DateTime? get lastReadTimestamp => _lastReadTimestamp;

  Future<File?> get _cacheFile async {
    if (kIsWeb) return null;
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/s_chat_data');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return File('${cacheDir.path}/messages_cache.json');
  }

  Future<File?> get _outboxFile async {
    if (kIsWeb) return null;
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/s_chat_data');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return File('${cacheDir.path}/offline_outbox.json');
  }

  Future<void> saveUserSession({
    required String userId,
    required String username,
    required String userImage,
  }) async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/s_chat_data/user_session.json');
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsString(
        json.encode({
          'user_id': userId,
          'username': username,
          'user_image': userImage,
        }),
      );
    } catch (_) {}
  }

  Future<Map<String, String>?> getCachedUserSession() async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/s_chat_data/user_session.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final Map<String, dynamic> data = json.decode(content);
          return {
            'user_id': data['user_id'] ?? '',
            'username': data['username'] ?? '',
            'user_image': data['user_image'] ?? '',
          };
        }
      }
    } catch (_) {}
    return null;
  }

  /// Id of the signed-in user, falling back to the cached session so the app
  /// can still decrypt messages while it works offline.
  Future<String?> currentUserId() async {
    try {
      final current = Supabase.instance.client.auth.currentUser?.id;
      if (current != null && current.isNotEmpty) return current;
    } catch (_) {
      // Supabase is not available, so the cached session is used instead.
    }
    final cached = (await getCachedUserSession())?['user_id'];
    if (cached != null && cached.isNotEmpty) return cached;
    return null;
  }

  /// Builds a [ChatMessage] from a raw database row.
  ///
  /// Rows written by an encrypted client carry an `iv` column; their body is
  /// decrypted here so the rest of the app only ever sees plain text.
  Future<ChatMessage> decodeMessage(Map<String, dynamic> row) async {
    final message = ChatMessage.fromMap(row);
    final iv = message.iv;
    if (iv == null || iv.isEmpty) return message;

    final myUserId = await currentUserId();
    if (myUserId == null) return message.copyWith(text: decryptionFailedText);

    final String? plain;
    if (message.isGroup && message.chatId != null) {
      plain = await _crypto.decryptFromGroupSender(
        groupId: message.chatId!,
        senderUserId: message.userId,
        myUserId: myUserId,
        encryptedText: message.cleanText,
        iv: iv,
      );
    } else {
      final peerUserId = _peerUserIdOf(message, myUserId);
      if (peerUserId == null) {
        return message.copyWith(text: decryptionFailedText);
      }

      plain = await _crypto.decryptFromPeer(
        myUserId: myUserId,
        peerUserId: peerUserId,
        encryptedText: message.cleanText,
        iv: iv,
      );
    }

    if (plain == null) return message.copyWith(text: decryptionFailedText);

    final payload = _decodePayload(plain);
    return message.copyWith(
      text: ChatMessage.encodeChatText(
        text: payload.text,
        chatId: message.chatId,
        recipientId: message.recipientId,
      ),
      replyToText: payload.replyToText,
    );
  }

  /// Decrypts every row of a database result.
  Future<List<ChatMessage>> _decodeAll(List<dynamic> rows) async {
    final messages = <ChatMessage>[];
    for (final row in rows) {
      if (row is Map) {
        messages.add(await decodeMessage(Map<String, dynamic>.from(row)));
      }
    }
    return messages;
  }

  /// Encrypts a message body for a direct chat or group chat using Signal Protocol Sender Keys.
  Future<({String text, String? iv})> _encryptForPeer({
    required String myUserId,
    required String? peerUserId,
    required String text,
    required String? replyToText,
    required String? chatId,
  }) async {
    if (peerUserId != null && peerUserId.isNotEmpty) {
      final encrypted = await _crypto.encryptForPeer(
        myUserId: myUserId,
        peerUserId: peerUserId,
        plainText: jsonEncode({'t': text, 'r': replyToText}),
      );
      if (encrypted != null) {
        return (
          text: ChatMessage.encodeChatText(
            text: encrypted.text,
            chatId: chatId,
            recipientId: peerUserId,
          ),
          iv: encrypted.iv,
        );
      }
    } else if (chatId != null && chatId.startsWith('group_')) {
      final encryptedGroup = await _crypto.encryptForGroup(
        groupId: chatId,
        myUserId: myUserId,
        plainText: jsonEncode({'t': text, 'r': replyToText}),
      );
      if (encryptedGroup != null) {
        return (
          text: ChatMessage.encodeChatText(
            text: encryptedGroup.text,
            chatId: chatId,
            recipientId: null,
          ),
          iv: encryptedGroup.iv,
        );
      }
    }

    return (
      text: ChatMessage.encodeChatText(
        text: text,
        chatId: chatId,
        recipientId: peerUserId,
      ),
      iv: null,
    );
  }

  /// Splits the decrypted payload into the body and the quoted reply text.
  ({String text, String? replyToText}) _decodePayload(String plain) {
    try {
      final decoded = jsonDecode(plain);
      if (decoded is Map) {
        return (
          text: decoded['t']?.toString() ?? '',
          replyToText: decoded['r']?.toString(),
        );
      }
    } catch (_) {
      // Not a JSON payload, so the decrypted value is the body itself.
    }
    return (text: plain, replyToText: null);
  }

  /// The other participant of a direct chat.
  String? _peerUserIdOf(ChatMessage message, String myUserId) {
    if (message.userId != myUserId) return message.userId;
    return message.recipientId;
  }

  Future<File?> get _lastReadFile async {
    if (kIsWeb) return null;
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/s_chat_data');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return File('${cacheDir.path}/last_read_timestamp.json');
  }

  Future<void> _loadLastReadTimestamp() async {
    if (kIsWeb) return;
    try {
      final file = await _lastReadFile;
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final Map<String, dynamic> data = json.decode(content);
          final raw = data['last_read_timestamp'];
          if (raw is String) {
            _lastReadTimestamp = DateTime.tryParse(raw);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> updateLastReadTimestamp([DateTime? timestamp]) async {
    final newTime = timestamp ?? DateTime.now().toUtc();
    _lastReadTimestamp = newTime;
    if (kIsWeb) return;
    try {
      final file = await _lastReadFile;
      if (file != null) {
        await file.writeAsString(
          json.encode({'last_read_timestamp': newTime.toIso8601String()}),
        );
      }
    } catch (_) {}
  }

  static String getDirectChatId(String user1, String user2) {
    return user1.compareTo(user2) <= 0
        ? 'dm_${user1}_$user2'
        : 'dm_${user2}_$user1';
  }

  Future<File?> get _usersCacheFile async {
    if (kIsWeb) return null;
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/s_chat_data');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return File('${cacheDir.path}/users_cache.json');
  }

  Future<void> _saveUsersToDiskCache(List<Map<String, dynamic>> users) async {
    if (kIsWeb) return;
    try {
      final file = await _usersCacheFile;
      if (file != null) {
        await file.writeAsString(json.encode(users));
      }
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _loadUsersFromDiskCache() async {
    if (kIsWeb) return [];
    try {
      final file = await _usersCacheFile;
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> list = json.decode(content);
          return list.cast<Map<String, dynamic>>();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<File?> get _groupsCacheFile async {
    if (kIsWeb) return null;
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/s_chat_data');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return File('${cacheDir.path}/groups_cache.json');
  }

  Future<void> _saveGroupsToDiskCache(List<Map<String, dynamic>> groups) async {
    if (kIsWeb) return;
    try {
      final file = await _groupsCacheFile;
      if (file != null) {
        await file.writeAsString(json.encode(groups));
      }
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _loadGroupsFromDiskCache() async {
    if (kIsWeb) return [];
    try {
      final file = await _groupsCacheFile;
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> list = json.decode(content);
          return list.cast<Map<String, dynamic>>();
        }
      }
    } catch (_) {}
    return [];
  }

  /// Fetches available chats (users & groups) from Supabase and pairs with latest messages
  Future<List<ChatItem>> fetchAvailableChats() async {
    final List<ChatItem> chats = [];
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';

    List<Map<String, dynamic>> usersData = [];

    try {
      final response = await Supabase.instance.client
          .from('users')
          .select('id, username, image_url, public_key');

      final List<dynamic> rawList = response as List<dynamic>;
      usersData = rawList.map((e) => Map<String, dynamic>.from(e)).toList();
      await _saveUsersToDiskCache(usersData);
    } catch (e) {
      debugPrint('Offline or error fetching users from Supabase: $e');
      usersData = await _loadUsersFromDiskCache();

      final Map<String, Map<String, dynamic>> extractedUsers = {
        for (final u in usersData) u['id'].toString(): u,
      };

      for (final m in _messages) {
        if (m.userId.isNotEmpty &&
            m.userId != currentUserId &&
            !extractedUsers.containsKey(m.userId)) {
          extractedUsers[m.userId] = {
            'id': m.userId,
            'username': m.username.isNotEmpty ? m.username : 'Anonymous',
            'image_url': m.userImage,
          };
        }
      }

      usersData = extractedUsers.values.toList();
    }

    for (final userData in usersData) {
      final id = userData['id']?.toString() ?? '';
      if (id == currentUserId || id.isEmpty) continue;

      final username = userData['username']?.toString() ?? 'Anonymous';
      final imageUrl = userData['image_url']?.toString() ?? '';
      final publicKey = userData['public_key']?.toString() ?? '';

      if (publicKey.isNotEmpty) {
        _crypto.cachePublicKey(id, publicKey);
      }

      ChatMessage? lastMsg;
      for (int i = _messages.length - 1; i >= 0; i--) {
        final m = _messages[i];
        if (m.matchesChat(
          activeChatId: id,
          isGroup: false,
          currentUserId: currentUserId,
        )) {
          lastMsg = m;
          break;
        }
      }

      chats.add(
        ChatItem(
          id: id,
          name: username,
          avatarUrl: imageUrl,
          lastMessage: lastMsg?.displayText ?? 'Tap to start chatting',
          lastMessageTime: lastMsg?.createdAt,
          unreadCount: 0,
          isGroup: false,
          isOnline: _isOnline,
        ),
      );
    }

    // Fetch groups from Supabase 'groups' table online or local disk cache offline
    List<Map<String, dynamic>> groupsData = [];
    try {
      final groupsResponse = await Supabase.instance.client
          .from('groups')
          .select('id, name, image_url, is_private, created_at');

      final List<dynamic> rawGroups = groupsResponse as List<dynamic>;
      groupsData = rawGroups.map((e) => Map<String, dynamic>.from(e)).toList();
      await _saveGroupsToDiskCache(groupsData);
    } catch (e) {
      debugPrint('Offline or error fetching groups from Supabase: $e');
      groupsData = await _loadGroupsFromDiskCache();
    }

    // Fetch group members from Supabase 'group_members' table
    final Map<String, List<String>> groupMembersMap = {};
    try {
      final membersResponse = await Supabase.instance.client
          .from('group_members')
          .select('group_id, user_id');
      final List<dynamic> rawMembers = membersResponse as List<dynamic>;
      for (final item in rawMembers) {
        final gId = item['group_id']?.toString() ?? '';
        final uId = item['user_id']?.toString() ?? '';
        if (gId.isNotEmpty && uId.isNotEmpty) {
          groupMembersMap.putIfAbsent(gId, () => []).add(uId);
        }
      }
    } catch (e) {
      debugPrint('Offline or error fetching group members from Supabase: $e');
    }

    for (final groupMap in groupsData) {
      final id = groupMap['id']?.toString() ?? '';
      final name = groupMap['name']?.toString() ?? 'Group';
      final imageUrl = groupMap['image_url']?.toString() ?? '';
      final isPrivate = groupMap['is_private'] == true;
      final ownerId = groupMap['created_by']?.toString() ?? '';
      final memberIds = groupMembersMap[id] ?? (ownerId.isNotEmpty ? [ownerId] : []);

      ChatMessage? lastMsg;
      for (int i = _messages.length - 1; i >= 0; i--) {
        final m = _messages[i];
        if (m.matchesChat(
          activeChatId: id,
          isGroup: true,
          currentUserId: currentUserId,
        )) {
          lastMsg = m;
          break;
        }
      }

      final groupItem = ChatItem(
        id: id,
        name: name,
        avatarUrl: imageUrl,
        lastMessage: lastMsg?.displayText ?? 'Group created',
        lastMessageTime: lastMsg?.createdAt,
        unreadCount: 0,
        isGroup: true,
        isPrivate: isPrivate,
        isOnline: _isOnline,
        ownerId: ownerId,
        memberIds: memberIds,
      );

      if (!chats.any((c) => c.id == id)) {
        chats.insert(0, groupItem);
      }
    }

    for (final group in _customGroups) {
      if (!chats.any((c) => c.id == group.id)) {
        ChatMessage? lastMsg;
        for (int i = _messages.length - 1; i >= 0; i--) {
          final m = _messages[i];
          if (m.matchesChat(
            activeChatId: group.id,
            isGroup: true,
            currentUserId: currentUserId,
          )) {
            lastMsg = m;
            break;
          }
        }

        chats.insert(
          0,
          group.copyWith(
            lastMessage: lastMsg?.displayText ?? group.lastMessage,
            lastMessageTime: lastMsg?.createdAt ?? group.lastMessageTime,
          ),
        );
      }
    }

    chats.sort((a, b) {
      if (a.lastMessageTime == null) return 1;
      if (b.lastMessageTime == null) return -1;
      return b.lastMessageTime!.compareTo(a.lastMessageTime!);
    });

    return chats;
  }

  /// Uploads group image to Supabase Storage 'user_images' bucket
  Future<String> uploadGroupImage(File imageFile, String groupId) async {
    try {
      final imagePath = 'group_$groupId.jpg';
      await Supabase.instance.client.storage
          .from('user_images')
          .upload(
            imagePath,
            imageFile,
            fileOptions: const FileOptions(upsert: true),
          );
      final rawUrl = Supabase.instance.client.storage
          .from('user_images')
          .getPublicUrl(imagePath);
      return '$rawUrl?t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      debugPrint('Error uploading group image: $e');
      return '';
    }
  }

  /// Creates a new custom group chat and persists to Supabase 'groups' and 'group_members' tables
  Future<ChatItem> createGroup({
    required String groupName,
    String? imageUrl,
  }) async {
    final currentUserId =
        Supabase.instance.client.auth.currentUser?.id ?? 'anon';
    final groupId = 'group_${DateTime.now().millisecondsSinceEpoch}';
    final name = groupName.trim().isEmpty ? 'New Group' : groupName.trim();
    final imgUrl = imageUrl ?? '';

    final newGroup = ChatItem(
      id: groupId,
      name: name,
      avatarUrl: imgUrl,
      lastMessage: 'Group created',
      lastMessageTime: DateTime.now(),
      unreadCount: 0,
      isGroup: true,
      isOnline: true,
      ownerId: currentUserId,
      memberIds: [currentUserId],
    );

    _customGroups.insert(0, newGroup);

    final cached = await _loadGroupsFromDiskCache();
    cached.insert(0, {
      'id': groupId,
      'name': name,
      'image_url': imgUrl,
      'created_by': currentUserId,
      'is_private': false,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    await _saveGroupsToDiskCache(cached);

    try {
      await Supabase.instance.client.from('groups').upsert({
        'id': groupId,
        'name': name,
        'image_url': imgUrl,
        'created_by': currentUserId,
        'is_private': false,
      });
    } catch (e) {
      debugPrint('Error inserting group row to Supabase: $e');
    }

    try {
      await Supabase.instance.client.from('group_members').upsert({
        'group_id': groupId,
        'user_id': currentUserId,
        'role': 'owner',
      }, onConflict: 'group_id, user_id');
    } catch (e) {
      debugPrint('Error inserting group_members owner row to Supabase: $e');
    }

    unawaited(_crypto.distributeSenderKey(
      groupId: groupId,
      myUserId: currentUserId,
      memberIds: newGroup.memberIds,
    ));

    return newGroup;
  }

  /// Adds user IDs to a group
  Future<void> addUsersToGroup({
    required String groupId,
    required List<String> userIds,
  }) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final index = _customGroups.indexWhere((g) => g.id == groupId);
    if (index != -1) {
      final old = _customGroups[index];
      final updatedMembers = {...old.memberIds, ...userIds}.toList();
      _customGroups[index] = old.copyWith(memberIds: updatedMembers);
    }

    try {
      final records = userIds
          .map((uid) => {'group_id': groupId, 'user_id': uid, 'role': 'member'})
          .toList();

      await Supabase.instance.client
          .from('group_members')
          .upsert(records, onConflict: 'group_id, user_id');

      if (currentUserId.isNotEmpty) {
        unawaited(_crypto.distributeSenderKey(
          groupId: groupId,
          myUserId: currentUserId,
          memberIds: userIds,
        ));
      }
    } catch (e) {
      debugPrint('Error adding users to group_members in Supabase: $e');
    }
  }

  /// Updates group name, image_url, and/or privacy
  Future<ChatItem?> updateGroupSettings({
    required String groupId,
    String? newName,
    String? newImageUrl,
    bool? isPrivate,
  }) async {
    final Map<String, dynamic> updates = {};
    if (newName != null && newName.trim().isNotEmpty) {
      updates['name'] = newName.trim();
    }
    if (newImageUrl != null && newImageUrl.trim().isNotEmpty) {
      updates['image_url'] = newImageUrl.trim();
    }
    if (isPrivate != null) {
      updates['is_private'] = isPrivate;
    }

    if (updates.isEmpty) return null;

    final index = _customGroups.indexWhere((g) => g.id == groupId);
    ChatItem? updatedGroup;
    if (index != -1) {
      _customGroups[index] = _customGroups[index].copyWith(
        name: updates['name'] as String?,
        avatarUrl: updates['image_url'] as String?,
        isPrivate: isPrivate ?? _customGroups[index].isPrivate,
      );
      updatedGroup = _customGroups[index];
    }

    try {
      await Supabase.instance.client
          .from('groups')
          .update(updates)
          .eq('id', groupId);
    } catch (e) {
      debugPrint('Error updating group settings in Supabase: $e');
    }

    return updatedGroup;
  }

  /// Checks whether a group name is already taken in local cache or Supabase
  Future<bool> isGroupNameTaken(String name, {String? excludeGroupId}) async {
    final trimmed = name.trim().toLowerCase();
    if (trimmed.isEmpty) return false;

    for (final g in _customGroups) {
      if (g.id != excludeGroupId && g.name.trim().toLowerCase() == trimmed) {
        return true;
      }
    }

    try {
      final List<dynamic> results = await Supabase.instance.client
          .from('groups')
          .select('id, name')
          .ilike('name', name.trim());

      for (final item in results) {
        final id = item['id']?.toString() ?? '';
        if (id != excludeGroupId) {
          return true;
        }
      }
    } catch (_) {}

    return false;
  }

  /// Permanently deletes a group from Supabase 'groups' table and local cache
  Future<void> deleteGroup({required String groupId}) async {
    _customGroups.removeWhere((g) => g.id == groupId);

    final cached = await _loadGroupsFromDiskCache();
    cached.removeWhere((g) => g['id'] == groupId);
    await _saveGroupsToDiskCache(cached);

    try {
      await Supabase.instance.client.from('groups').delete().eq('id', groupId);
    } catch (e) {
      debugPrint('Error deleting group from Supabase: $e');
    }
  }

  /// Clears local messages view and cache for the conversation
  Future<void> clearConversationMessages({
    String? activeChatId,
    bool isGroup = false,
    String? currentUserId,
  }) async {
    if (activeChatId != null && currentUserId != null) {
      _messages.removeWhere(
        (m) => m.matchesChat(
          activeChatId: activeChatId,
          isGroup: isGroup,
          currentUserId: currentUserId,
        ),
      );
    } else {
      _messages.clear();
    }
    _messagesController.add(List.unmodifiable(_messages));
    await _saveToDiskCache();
  }

  /// Initialize cache/outbox once. Concurrent callers await the same future,
  /// preventing a newly queued item from racing against loading the old outbox.
  Future<void> init() {
    if (_initFuture != null) return _initFuture!;
    _initFuture = _initialize();
    return _initFuture!;
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _loadLastReadTimestamp();
    await _loadFromDiskCache();
    await _loadOutboxFromDisk();

    // Fetching and syncing stay asynchronous so the local UI isn't network-bound.
    unawaited(_fetchInitialMessages());
    unawaited(_processOfflineOutbox());
    _setupRealtimeSubscription();

    Timer.periodic(const Duration(seconds: 10), (_) {
      if (_outbox.isNotEmpty) unawaited(_processOfflineOutbox());
    });
  }

  Future<void> _loadFromDiskCache() async {
    if (kIsWeb) return;
    try {
      final file = await _cacheFile;
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> jsonList = json.decode(content);
          _messages = jsonList.map((e) => ChatMessage.fromMap(e)).toList();
          _sortMessagesChronologically();
          _messagesController.add(_messages);
        }
      }
    } catch (e) {
      debugPrint('Error loading disk cache: $e');
    }
  }

  Future<void> _saveToDiskCache() async {
    if (kIsWeb) return;
    try {
      final file = await _cacheFile;
      if (file == null) return;
      final jsonList = _messages
          .map(
            (m) => {
              'id': m.id,
              'user_id': m.userId,
              'text': m.text,
              'username': m.username,
              'user_image': m.userImage,
              'created_at': m.createdAt?.toUtc().toIso8601String(),
              'reply_to_id': m.replyToId,
              'reply_to_username': m.replyToUsername,
              'reply_to_text': m.replyToText,
              'chat_id': m.chatId,
              'recipient_id': m.recipientId,
              'iv': m.iv,
            },
          )
          .toList();
      await file.writeAsString(json.encode(jsonList));
    } catch (e) {
      debugPrint('Error saving disk cache: $e');
    }
  }

  Future<void> _loadOutboxFromDisk() async {
    if (kIsWeb) return;
    try {
      final file = await _outboxFile;
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> jsonList = json.decode(content);
          _outbox = jsonList.cast<Map<String, dynamic>>();
          for (final item in _outbox) {
            if (item['action'] == 'insert_media') {
              final tempId = item['temp_id']?.toString();
              if (tempId != null && tempId.isNotEmpty) {
                _mediaSyncStatuses[tempId] = const MediaSyncStatus(
                  MediaSyncPhase.queued,
                );
              }
            }
          }
          if (_mediaSyncStatuses.isNotEmpty && !_mediaSyncController.isClosed) {
            _mediaSyncController.add(Map.unmodifiable(_mediaSyncStatuses));
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading outbox from disk: $e');
    }
  }

  Future<void> _saveOutboxToDisk() async {
    if (kIsWeb) return;
    try {
      final file = await _outboxFile;
      if (file != null) {
        await file.writeAsString(json.encode(_outbox));
      }
    } catch (e) {
      debugPrint('Error saving outbox to disk: $e');
    }
  }

  void _sortMessagesChronologically() {
    _messages.sort((a, b) {
      if (a.createdAt == null) return -1;
      if (b.createdAt == null) return 1;
      return a.createdAt!.compareTo(b.createdAt!);
    });
  }

  Future<void> _fetchInitialMessages() async {
    try {
      final response = await Supabase.instance.client
          .from('chat_messages')
          .select()
          .order('created_at', ascending: false)
          .range(0, pageSize - 1);

      _isOnline = true;
      _isOnlineController.add(true);

      final List<dynamic> docs = response as List<dynamic>;
      final fetchedMessages = await _decodeAll(docs);

      if (fetchedMessages.length < pageSize) {
        _hasMoreOlderMessages = false;
      }

      _mergeMessages(fetchedMessages);
      await _saveToDiskCache();
    } catch (e) {
      _isOnline = false;
      _isOnlineController.add(false);
      debugPrint('Offline or network error fetching initial messages: $e');
    }
  }

  /// Paginate and load the next batch of older messages when scrolling up
  Future<bool> loadOlderMessages() async {
    if (_isLoadingOlder || !_hasMoreOlderMessages || !_isOnline) return false;

    _isLoadingOlder = true;
    try {
      final currentOffset = _messages.length;
      final response = await Supabase.instance.client
          .from('chat_messages')
          .select()
          .order('created_at', ascending: false)
          .range(currentOffset, currentOffset + pageSize - 1);

      final List<dynamic> docs = response as List<dynamic>;
      if (docs.isEmpty) {
        _hasMoreOlderMessages = false;
        _isLoadingOlder = false;
        return false;
      }

      final olderMessages = await _decodeAll(docs);
      if (olderMessages.length < pageSize) {
        _hasMoreOlderMessages = false;
      }

      _mergeMessages(olderMessages);
      await _saveToDiskCache();
      _isLoadingOlder = false;
      return true;
    } catch (e) {
      debugPrint('Error loading older messages: $e');
      _isLoadingOlder = false;
      return false;
    }
  }

  /// Optimistically adds a new message to local UI state instantly (0ms), then queues for network sync
  Future<void> sendOptimisticMessage({
    required String text,
    required String userId,
    required String username,
    required String userImage,
    String? chatId,
    String? recipientId,
    dynamic replyToId,
    String? replyToUsername,
    String? replyToText,
  }) async {
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now().toUtc();
    final encodedText = ChatMessage.encodeChatText(
      text: text,
      chatId: chatId,
      recipientId: recipientId,
    );

    final optimisticMsg = ChatMessage(
      id: tempId,
      userId: userId,
      text: encodedText,
      username: username,
      userImage: userImage,
      createdAt: now,
      chatId: chatId,
      recipientId: recipientId,
      replyToId: replyToId,
      replyToUsername: replyToUsername,
      replyToText: replyToText,
    );

    // 1. Instantly append to local messages list (0ms delay)
    _mergeMessages([optimisticMsg]);
    await _saveToDiskCache();

    // Distribute Group Sender Key if this is a group message
    if (chatId != null && chatId.startsWith('group_')) {
      final activeGroup = _customGroups.firstWhere(
        (g) => g.id == chatId,
        orElse: () => ChatItem(
          id: chatId,
          name: 'Group',
          avatarUrl: '',
          lastMessage: '',
        ),
      );
      unawaited(_crypto.distributeSenderKey(
        groupId: chatId,
        myUserId: userId,
        memberIds: activeGroup.memberIds.isNotEmpty
            ? activeGroup.memberIds
            : [userId],
      ));
    }

    // 2. Encrypt the body for the peer and queue it in the offline outbox.
    final wire = await _encryptForPeer(
      myUserId: userId,
      peerUserId: recipientId,
      text: text,
      replyToText: replyToText,
      chatId: chatId,
    );

    final outboxItem = {
      'action': 'insert',
      'temp_id': tempId,
      'chat_id': chatId,
      'recipient_id': recipientId,
      'data': {
        'user_id': userId,
        'text': wire.text,
        if (wire.iv != null) 'iv': wire.iv,
        'username': username,
        'user_image': userImage,
        'created_at': now.toIso8601String(),
        if (replyToId != null) ...{
          'reply_to_id': replyToId,
          'reply_to_username': replyToUsername,
          // The quoted text travels inside the encrypted payload.
          if (wire.iv == null) 'reply_to_text': replyToText,
        },
      },
    };

    _outbox.add(outboxItem);
    await _saveOutboxToDisk();

    // 3. Process outbox
    _processOfflineOutbox();
  }

  /// Queues an attachment using the same optimistic cache and outbox as text.
  ///
  /// The original file is copied into application documents before the UI is
  /// updated, so a temporary recorder/picker file cannot disappear before the
  /// device reconnects. Supabase Storage upload + `chat_messages` insert are
  /// then processed by `_processOfflineOutbox` when the network is available.
  Future<void> sendOptimisticMedia({
    required String kind,
    required String name,
    String? path,
    String? url,
    int? sizeBytes,
    String? chatId,
    String? recipientId,
    dynamic replyToId,
    String? replyToUsername,
    String? replyToText,
  }) async {
    await init();

    final currentUser = Supabase.instance.client.auth.currentUser;
    final cachedSession = await getCachedUserSession();

    String userId = currentUser?.id ?? cachedSession?['user_id'] ?? '';
    String username = cachedSession?['username'] ?? '';
    String userImage = cachedSession?['user_image'] ?? '';

    if (currentUser != null && (username.isEmpty || userImage.isEmpty)) {
      final metadata = currentUser.userMetadata;
      if (username.isEmpty) username = metadata?['username']?.toString() ?? '';
      if (userImage.isEmpty) {
        userImage = metadata?['image_url']?.toString() ?? '';
      }

      if (username.isEmpty || userImage.isEmpty) {
        final profile = ProfileCacheService.instance.getCached(currentUser.id);
        if (profile != null) {
          if (username.isEmpty) {
            username = profile['username']?.toString() ?? 'User';
          }
          if (userImage.isEmpty) {
            userImage = profile['image_url']?.toString() ?? '';
          }
        }
      }
    }

    if (username.isEmpty) username = 'User';
    if (userId.isEmpty) userId = 'guest_user';

    await saveUserSession(
      userId: userId,
      username: username,
      userImage: userImage,
    );

    final tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';
    final createdAt = DateTime.now().toUtc();
    String? durablePath;
    String? storagePath;

    if (kind != 'url') {
      if (path == null || path.trim().isEmpty) {
        throw ArgumentError(
          'A local file path is required for $kind attachments.',
        );
      }
      durablePath = await _copyMediaToPersistentStorage(path, tempId, name);
      storagePath = '${_safePathPart(userId)}/$tempId/${_safeFileName(name)}';
    } else if (url == null || url.trim().isEmpty) {
      throw ArgumentError('A URL is required for link attachments.');
    }

    final localPayload = <String, dynamic>{
      'v': 1,
      'kind': kind,
      'name': name,
      'status': 'pending',
      'local_path': ?durablePath,
      'url': ?url,
      'storage_path': ?storagePath,
      'size_bytes': ?sizeBytes,
      'chat_id': ?chatId,
      'recipient_id': ?recipientId,
    };
    final encodedText = ChatMessage.encodeMediaText(localPayload);

    final optimisticMessage = ChatMessage(
      id: tempId,
      userId: userId,
      text: encodedText,
      username: username,
      userImage: userImage,
      createdAt: createdAt,
      chatId: chatId,
      recipientId: recipientId,
      replyToId: replyToId,
      replyToUsername: replyToUsername,
      replyToText: replyToText,
    );

    // 1. Show the attachment immediately and persist it in the local cache.
    _mergeMessages([optimisticMessage]);
    await _saveToDiskCache();

    // 2. Put the durable local path and metadata in the existing offline queue.
    _outbox.add({
      'action': 'insert_media',
      'temp_id': tempId,
      'kind': kind,
      'name': name,
      'local_path': durablePath,
      'storage_path': storagePath,
      'url': url,
      'size_bytes': sizeBytes,
      'chat_id': chatId,
      'recipient_id': recipientId,
      'uploaded': false,
      'data': {
        'user_id': userId,
        'text': encodedText,
        'username': username,
        'user_image': userImage,
        'created_at': createdAt.toIso8601String(),
        if (replyToId != null) ...{
          'reply_to_id': replyToId,
          'reply_to_username': replyToUsername,
          'reply_to_text': replyToText,
        },
      },
    });
    await _saveOutboxToDisk();
    _setMediaSyncStatus(tempId, MediaSyncPhase.queued);

    // 3. This returns immediately when offline; the queue retries later.
    unawaited(_processOfflineOutbox());
  }

  Future<String> _copyMediaToPersistentStorage(
    String sourcePath,
    String tempId,
    String displayName,
  ) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException(
        'Selected attachment no longer exists',
        sourcePath,
      );
    }

    final appDirectory = await getApplicationDocumentsDirectory();
    final target = File(
      '${appDirectory.path}${Platform.pathSeparator}s_chat_data'
      '${Platform.pathSeparator}pending_media${Platform.pathSeparator}$tempId'
      '${Platform.pathSeparator}${_safeFileName(displayName)}',
    );
    await target.parent.create(recursive: true);

    if (source.absolute.path == target.absolute.path) return target.path;
    await source.copy(target.path);
    return target.path;
  }

  String _safeFileName(String input) {
    final leaf = input.split(RegExp(r'[/\\]')).last.trim();
    final cleaned = leaf.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? 'attachment' : cleaned;
  }

  String _safePathPart(String input) {
    final cleaned = input.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return cleaned.isEmpty ? 'unknown_user' : cleaned;
  }

  String _mediaContentType(String kind, String name) {
    final extension = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    switch (kind) {
      case 'audio':
        if (extension == 'mp3') return 'audio/mpeg';
        if (extension == 'wav') return 'audio/wav';
        if (extension == 'ogg' || extension == 'opus') return 'audio/ogg';
        return 'audio/mp4'; // Recorder outputs AAC in an M4A container.
      case 'image':
        if (extension == 'png') return 'image/png';
        if (extension == 'webp') return 'image/webp';
        if (extension == 'gif') return 'image/gif';
        return 'image/jpeg';
      case 'video':
        if (extension == 'mov') return 'video/quicktime';
        if (extension == 'webm') return 'video/webm';
        return 'video/mp4';
      default:
        return 'application/octet-stream';
    }
  }

  /// Optimistically edits an existing message in local UI state instantly (0ms), then queues for network sync
  Future<void> editOptimisticMessage({
    required dynamic id,
    required String newText,
  }) async {
    final idStr = id.toString();
    final index = _messages.indexWhere((m) => m.id.toString() == idStr);

    if (index != -1) {
      final oldMsg = _messages[index];

      // Encrypt the new body first. A message that is already encrypted stays
      // encrypted, so the queued update carries a fresh nonce.
      final wire = await _encryptForPeer(
        myUserId: oldMsg.userId,
        peerUserId: oldMsg.recipientId,
        text: newText,
        replyToText: oldMsg.replyToText,
        chatId: oldMsg.chatId,
      );

      if (oldMsg.iv != null && wire.iv == null) {
        // The body is encrypted on the server but the peer key is not
        // available right now, so the update is postponed instead of leaking
        // the plain text.
        debugPrint('MessageRepository: edit skipped, peer key unavailable');
        return;
      }

      final updatedMsg = ChatMessage(
        id: oldMsg.id,
        userId: oldMsg.userId,
        text: ChatMessage.encodeChatText(
          text: newText,
          chatId: oldMsg.chatId,
          recipientId: oldMsg.recipientId,
        ),
        username: oldMsg.username,
        userImage: oldMsg.userImage,
        createdAt: oldMsg.createdAt,
        replyToId: oldMsg.replyToId,
        replyToUsername: oldMsg.replyToUsername,
        replyToText: oldMsg.replyToText,
        chatId: oldMsg.chatId,
        recipientId: oldMsg.recipientId,
        iv: wire.iv,
      );

      // 1. Instantly update local list (0ms delay)
      _messages[index] = updatedMsg;
      _messagesController.add(_messages);
      await _saveToDiskCache();

      // 2. Queue in outbox
      _outbox.add({
        'action': 'update',
        'id': id,
        'data': {'text': wire.text, if (wire.iv != null) 'iv': wire.iv},
      });
      await _saveOutboxToDisk();

      _processOfflineOutbox();
    }
  }

  /// Optimistically deletes a message locally, then queues for network sync
  Future<void> deleteOptimisticMessage({
    required dynamic id,
    required bool isMe,
  }) async {
    final idStr = id.toString();
    _messages.removeWhere((m) => m.id.toString() == idStr);
    _messagesController.add(_messages);
    await _saveToDiskCache();

    if (idStr.startsWith('temp_')) {
      // A queued item has no server ID yet. Remove its insert action instead
      // of queuing a database DELETE for a temporary ID that cannot exist there.
      final pendingItems = _outbox
          .where((item) => item['temp_id']?.toString() == idStr)
          .toList(growable: false);
      _outbox.removeWhere((item) => item['temp_id']?.toString() == idStr);
      _clearMediaSyncStatus(idStr);
      for (final item in pendingItems) {
        final localPath = item['local_path'] as String?;
        if (localPath != null) {
          try {
            final file = File(localPath);
            if (await file.exists()) await file.parent.delete(recursive: true);
          } catch (_) {
            // Local cleanup is best-effort; the queue item is still removed.
          }
        }
      }
      await _saveOutboxToDisk();
      return;
    }

    if (isMe) {
      _outbox.add({'action': 'delete', 'id': id});
      await _saveOutboxToDisk();
      _processOfflineOutbox();
    }
  }

  /// Processes queued outbox actions sequentially when internet connection is active
  Future<void> _processOfflineOutbox() async {
    if (_isProcessingOutbox || _outbox.isEmpty) return;
    _isProcessingOutbox = true;

    while (_outbox.isNotEmpty) {
      final item = _outbox.first;
      final action = item['action'];

      try {
        if (action == 'insert') {
          final tempId = item['temp_id'];
          final Map<String, dynamic> insertData = Map<String, dynamic>.from(
            item['data'],
          );

          final response = await Supabase.instance.client
              .from('chat_messages')
              .insert(insertData)
              .select()
              .maybeSingle();

          if (response != null) {
            _messages.removeWhere((m) => m.id.toString() == tempId);
            final confirmedMsg = await decodeMessage(response);
            _mergeMessages([confirmedMsg]);
            await _saveToDiskCache();
          }
        } else if (action == 'insert_media') {
          final tempId = item['temp_id']?.toString() ?? '';
          _setMediaSyncStatus(tempId, MediaSyncPhase.uploading);
          final kind = item['kind']?.toString() ?? 'file';
          final name = item['name']?.toString() ?? 'Attachment';
          final localPath = item['local_path'] as String?;
          final storagePath = item['storage_path'] as String?;
          final originalUrl = item['url'] as String?;
          final Map<String, dynamic> insertData = Map<String, dynamic>.from(
            item['data'] as Map,
          );

          if (kind != 'url') {
            if (localPath == null || storagePath == null) {
              throw StateError(
                'Queued media is missing its local or storage path.',
              );
            }
            final localFile = File(localPath);
            if (!await localFile.exists()) {
              throw FileSystemException(
                'Queued media file is missing',
                localPath,
              );
            }

            // Persist this flag so a successful upload is not repeated if the
            // following database insert fails. Upsert also covers a crash
            // between upload completion and saving the flag.
            if (item['uploaded'] != true) {
              await Supabase.instance.client.storage
                  .from(mediaStorageBucket)
                  .upload(
                    storagePath,
                    localFile,
                    fileOptions: FileOptions(
                      contentType: _mediaContentType(kind, name),
                      upsert: true,
                    ),
                  );
              item['uploaded'] = true;
              await _saveOutboxToDisk();
            }
          }

          // Do not send device-local paths to Supabase. Other devices receive
          // the storage object path and make a signed URL when they need it.
          final serverPayload = <String, dynamic>{
            'v': 1,
            'kind': kind,
            'name': name,
            'status': 'sent',
            if (kind == 'url') 'url': ?originalUrl,
            'storage_path': ?storagePath,
            if (item['size_bytes'] is int) 'size_bytes': item['size_bytes'],
            if (item['chat_id'] != null) 'chat_id': item['chat_id'],
            if (item['recipient_id'] != null)
              'recipient_id': item['recipient_id'],
          };
          insertData['text'] = ChatMessage.encodeMediaText(serverPayload);
          _setMediaSyncStatus(tempId, MediaSyncPhase.savingMessage);

          final response = await Supabase.instance.client
              .from('chat_messages')
              .insert(insertData)
              .select()
              .maybeSingle();

          if (response == null) {
            throw StateError(
              'Supabase did not return the inserted media message.',
            );
          }

          // Replace the local temporary row with the server row, but retain the
          // sender's local media copy so it can be played/viewed offline.
          _messages.removeWhere((m) => m.id.toString() == tempId);
          var confirmedMessage = await decodeMessage(response);
          if (localPath != null && confirmedMessage.mediaPayload != null) {
            final localPayload = <String, dynamic>{
              ...confirmedMessage.mediaPayload!,
              'local_path': localPath,
            };
            confirmedMessage = confirmedMessage.copyWith(
              text: ChatMessage.encodeMediaText(localPayload),
            );
          }
          _mergeMessages([confirmedMessage]);
          await _saveToDiskCache();
        } else if (action == 'update') {
          final id = item['id'];
          final Map<String, dynamic> updateData = Map<String, dynamic>.from(
            item['data'],
          );

          await Supabase.instance.client
              .from('chat_messages')
              .update(updateData)
              .eq('id', id);
        } else if (action == 'delete') {
          final id = item['id'];
          await Supabase.instance.client
              .from('chat_messages')
              .delete()
              .eq('id', id);
        }

        _outbox.removeAt(0);
        if (action == 'insert_media') {
          final tempId = item['temp_id']?.toString();
          if (tempId != null && tempId.isNotEmpty) {
            _clearMediaSyncStatus(tempId);
          }
        }
        await _saveOutboxToDisk();
        _isOnline = true;
        _isOnlineController.add(true);
      } catch (e) {
        debugPrint('Outbox item failed (offline or sync error): $e');
        _isOnline = false;
        _isOnlineController.add(false);
        if (action == 'insert_media') {
          final tempId = item['temp_id']?.toString();
          if (tempId != null && tempId.isNotEmpty) {
            _setMediaSyncStatus(tempId, MediaSyncPhase.queued);
          }
        }
        break; // Pause outbox processing until the next retry.
      }
    }

    _isProcessingOutbox = false;
  }

  void _mergeMessages(List<ChatMessage> newMessages) {
    final Map<String, ChatMessage> map = {
      for (var m in _messages) m.id.toString(): m,
    };
    for (var incoming in newMessages) {
      final key = incoming.id.toString();
      final existing = map[key];

      // Realtime updates contain the remote metadata but not this device's
      // local cache path. Preserve that path so attachments remain usable
      // offline on the sending device.
      final existingLocalPath = existing?.mediaLocalPath;
      if (existingLocalPath != null &&
          incoming.mediaPayload != null &&
          incoming.mediaLocalPath == null) {
        final payload = <String, dynamic>{
          ...incoming.mediaPayload!,
          'local_path': existingLocalPath,
        };
        map[key] = incoming.copyWith(
          text: ChatMessage.encodeMediaText(payload),
        );
      } else {
        map[key] = incoming;
      }
    }
    _messages = map.values.toList();
    _sortMessagesChronologically();
    _messagesController.add(_messages);
  }

  void _setupRealtimeSubscription() {
    try {
      _realtimeChannel?.unsubscribe();
      _realtimeChannel = Supabase.instance.client
          .channel('public:chat_messages')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'chat_messages',
            callback: (payload) {
              unawaited(_handleRealtimePayload(payload));
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Realtime subscription error (offline): $e');
    }
  }

  Future<void> _handleRealtimePayload(PostgresChangePayload payload) async {
    if (payload.eventType == PostgresChangeEvent.insert) {
      final newMsg = await decodeMessage(payload.newRecord);
      _mergeMessages([newMsg]);
      _saveToDiskCache();
    } else if (payload.eventType == PostgresChangeEvent.update) {
      final updatedMsg = await decodeMessage(payload.newRecord);
      _mergeMessages([updatedMsg]);
      _saveToDiskCache();
    } else if (payload.eventType == PostgresChangeEvent.delete) {
      final deletedId = payload.oldRecord['id']?.toString();
      if (deletedId != null) {
        _messages.removeWhere((m) => m.id.toString() == deletedId);
        _messagesController.add(_messages);
        _saveToDiskCache();
      }
    }
  }

  void dispose() {
    _realtimeChannel?.unsubscribe();
    _messagesController.close();
    _isOnlineController.close();
    _mediaSyncController.close();
  }
}
