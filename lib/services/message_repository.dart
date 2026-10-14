import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:s_chat/models/chat_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MessageRepository {
  MessageRepository._();
  static final MessageRepository instance = MessageRepository._();

  static const int pageSize = 30;

  final StreamController<List<ChatMessage>> _messagesController =
      StreamController<List<ChatMessage>>.broadcast();

  final StreamController<bool> _isOnlineController =
      StreamController<bool>.broadcast();

  List<ChatMessage> _messages = [];
  List<Map<String, dynamic>> _outbox = [];
  RealtimeChannel? _realtimeChannel;

  bool _isLoadingOlder = false;
  bool _hasMoreOlderMessages = true;
  bool _initialized = false;
  bool _isProcessingOutbox = false;
  bool _isOnline = true;
  DateTime? _lastReadTimestamp;

  Stream<List<ChatMessage>> get messagesStream => _messagesController.stream;
  Stream<bool> get isOnlineStream => _isOnlineController.stream;
  List<ChatMessage> get currentMessages => List.unmodifiable(_messages);
  bool get isLoadingOlder => _isLoadingOlder;
  bool get hasMoreOlderMessages => _hasMoreOlderMessages;
  bool get isOnline => _isOnline;
  DateTime? get lastReadTimestamp => _lastReadTimestamp;

  Future<File> get _cacheFile async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/s_chat_data');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return File('${cacheDir.path}/messages_cache.json');
  }

  Future<File> get _outboxFile async {
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
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/s_chat_data/user_session.json');
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsString(json.encode({
        'user_id': userId,
        'username': username,
        'user_image': userImage,
      }));
    } catch (_) {}
  }

  Future<Map<String, String>?> getCachedUserSession() async {
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

  Future<File> get _lastReadFile async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/s_chat_data');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return File('${cacheDir.path}/last_read_timestamp.json');
  }

  Future<void> _loadLastReadTimestamp() async {
    try {
      final file = await _lastReadFile;
      if (await file.exists()) {
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
    try {
      final file = await _lastReadFile;
      await file.writeAsString(json.encode({
        'last_read_timestamp': newTime.toIso8601String(),
      }));
    } catch (_) {}
  }

  /// Initialize offline cache, outbox queue, initial fetch, and Realtime subscription
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Load last read timestamp
    await _loadLastReadTimestamp();

    // 1. Load offline disk cache immediately (0ms instant UI)
    await _loadFromDiskCache();

    // 2. Load offline outbox queue
    await _loadOutboxFromDisk();

    // 3. Fetch initial messages from Supabase online
    _fetchInitialMessages();

    // 4. Process pending outbox queue
    _processOfflineOutbox();

    // 5. Setup Realtime subscription
    _setupRealtimeSubscription();

    // 6. Periodic sync & outbox retry loop (every 10s)
    Timer.periodic(const Duration(seconds: 10), (_) {
      if (_outbox.isNotEmpty) {
        _processOfflineOutbox();
      }
    });
  }

  Future<void> _loadFromDiskCache() async {
    try {
      final file = await _cacheFile;
      if (await file.exists()) {
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
    try {
      final file = await _cacheFile;
      final jsonList = _messages
          .map((m) => {
                'id': m.id,
                'user_id': m.userId,
                'text': m.text,
                'username': m.username,
                'user_image': m.userImage,
                'created_at': m.createdAt?.toUtc().toIso8601String(),
                'reply_to_id': m.replyToId,
                'reply_to_username': m.replyToUsername,
                'reply_to_text': m.replyToText,
              })
          .toList();
      await file.writeAsString(json.encode(jsonList));
    } catch (e) {
      debugPrint('Error saving disk cache: $e');
    }
  }

  Future<void> _loadOutboxFromDisk() async {
    try {
      final file = await _outboxFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> jsonList = json.decode(content);
          _outbox = jsonList.cast<Map<String, dynamic>>();
        }
      }
    } catch (e) {
      debugPrint('Error loading outbox from disk: $e');
    }
  }

  Future<void> _saveOutboxToDisk() async {
    try {
      final file = await _outboxFile;
      await file.writeAsString(json.encode(_outbox));
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
      final fetchedMessages = docs.map((e) => ChatMessage.fromMap(e)).toList();

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

      final olderMessages = docs.map((e) => ChatMessage.fromMap(e)).toList();
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
    dynamic replyToId,
    String? replyToUsername,
    String? replyToText,
  }) async {
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now().toUtc();

    final optimisticMsg = ChatMessage(
      id: tempId,
      userId: userId,
      text: text,
      username: username,
      userImage: userImage,
      createdAt: now,
      replyToId: replyToId,
      replyToUsername: replyToUsername,
      replyToText: replyToText,
    );

    // 1. Instantly append to local messages list (0ms delay)
    _mergeMessages([optimisticMsg]);
    await _saveToDiskCache();

    // 2. Queue in offline outbox
    final outboxItem = {
      'action': 'insert',
      'temp_id': tempId,
      'data': {
        'user_id': userId,
        'text': text,
        'username': username,
        'user_image': userImage,
        'created_at': now.toIso8601String(),
        if (replyToId != null) ...{
          'reply_to_id': replyToId,
          'reply_to_username': replyToUsername,
          'reply_to_text': replyToText,
        },
      },
    };

    _outbox.add(outboxItem);
    await _saveOutboxToDisk();

    // 3. Process outbox
    _processOfflineOutbox();
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
      final updatedMsg = ChatMessage(
        id: oldMsg.id,
        userId: oldMsg.userId,
        text: newText,
        username: oldMsg.username,
        userImage: oldMsg.userImage,
        createdAt: oldMsg.createdAt,
        replyToId: oldMsg.replyToId,
        replyToUsername: oldMsg.replyToUsername,
        replyToText: oldMsg.replyToText,
      );

      // 1. Instantly update local list (0ms delay)
      _messages[index] = updatedMsg;
      _messagesController.add(_messages);
      await _saveToDiskCache();

      // 2. Queue in outbox
      _outbox.add({
        'action': 'update',
        'id': id,
        'data': {'text': newText},
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

    if (isMe) {
      _outbox.add({
        'action': 'delete',
        'id': id,
      });
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
          final Map<String, dynamic> insertData =
              Map<String, dynamic>.from(item['data']);

          final response = await Supabase.instance.client
              .from('chat_messages')
              .insert(insertData)
              .select()
              .maybeSingle();

          if (response != null) {
            _messages.removeWhere((m) => m.id.toString() == tempId);
            final confirmedMsg = ChatMessage.fromMap(response);
            _mergeMessages([confirmedMsg]);
            await _saveToDiskCache();
          }
        } else if (action == 'update') {
          final id = item['id'];
          final Map<String, dynamic> updateData =
              Map<String, dynamic>.from(item['data']);

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
        await _saveOutboxToDisk();
        _isOnline = true;
        _isOnlineController.add(true);
      } catch (e) {
        debugPrint('Outbox item failed (offline): $e');
        _isOnline = false;
        _isOnlineController.add(false);
        break; // Pause outbox processing until network is restored
      }
    }

    _isProcessingOutbox = false;
  }

  void _mergeMessages(List<ChatMessage> newMessages) {
    final Map<String, ChatMessage> map = {
      for (var m in _messages) m.id.toString(): m
    };
    for (var m in newMessages) {
      map[m.id.toString()] = m;
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
              _handleRealtimePayload(payload);
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Realtime subscription error (offline): $e');
    }
  }

  void _handleRealtimePayload(PostgresChangePayload payload) {
    if (payload.eventType == PostgresChangeEvent.insert) {
      final newMsg = ChatMessage.fromMap(payload.newRecord);
      _mergeMessages([newMsg]);
      _saveToDiskCache();
    } else if (payload.eventType == PostgresChangeEvent.update) {
      final updatedMsg = ChatMessage.fromMap(payload.newRecord);
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
  }
}
