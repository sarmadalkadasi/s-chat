import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileCacheService {
  ProfileCacheService._();
  static final ProfileCacheService instance = ProfileCacheService._();

  final Map<String, Map<String, dynamic>> _cache = {};
  final Map<String, Future<Map<String, dynamic>?>> _pending = {};

  Map<String, dynamic>? getCached(String userId) {
    return _cache[userId];
  }

  Future<Map<String, dynamic>?> getProfile(String userId) async {
    if (userId.isEmpty) return null;

    if (_cache.containsKey(userId)) {
      return _cache[userId];
    }

    if (_pending.containsKey(userId)) {
      return _pending[userId];
    }

    final future = Supabase.instance.client
        .from('users')
        .select('username, image_url')
        .eq('id', userId)
        .maybeSingle()
        .then((data) {
          final profile = data ?? {'username': 'Anonymous', 'image_url': ''};
          _cache[userId] = profile;
          _pending.remove(userId);
          return profile;
        })
        .catchError((_) {
          final fallback = {'username': 'Anonymous', 'image_url': ''};
          _cache[userId] = fallback;
          _pending.remove(userId);
          return fallback;
        });

    _pending[userId] = future;
    return future;
  }
}
