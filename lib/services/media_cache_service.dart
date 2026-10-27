import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:s_chat/services/file_transfer_service.dart';

class MediaCacheService {
  MediaCacheService._();
  static final MediaCacheService instance = MediaCacheService._();

  final Map<String, Uint8List> _memoryCache = {};
  final Map<String, Future<File?>> _pendingDownloads = {};

  String _getCacheKey(String url) {
    return base64Url.encode(utf8.encode(url)).replaceAll('=', '');
  }

  Future<File?> _getCacheFile(String url) async {
    if (kIsWeb) return null;
    final key = _getCacheKey(url);
    final dir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${dir.path}/s_chat_media_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return File('${cacheDir.path}/$key');
  }

  Uint8List? getFromMemory(String url) {
    return _memoryCache[url];
  }

  Future<File?> getMediaFile(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    if (url.isEmpty || kIsWeb) return null;

    // 1. Check memory cache
    if (_memoryCache.containsKey(url)) {
      final file = await _getCacheFile(url);
      if (file != null && await file.exists()) return file;
    }

    // 2. Check local disk cache
    final cacheFile = await _getCacheFile(url);
    if (cacheFile != null && await cacheFile.exists() && await cacheFile.length() > 0) {
      try {
        final bytes = await cacheFile.readAsBytes();
        _memoryCache[url] = bytes;
        return cacheFile;
      } catch (_) {}
    }

    if (cacheFile == null) return null;

    // 3. Deduplicate pending in-flight downloads
    if (_pendingDownloads.containsKey(url)) {
      return _pendingDownloads[url];
    }

    final downloadFuture = FileTransferService.instance
        .downloadFileChunked(
          url: url,
          targetFile: cacheFile,
          onProgress: onProgress,
        )
        .then((file) async {
          if (file != null && await file.exists()) {
            try {
              final bytes = await file.readAsBytes();
              _memoryCache[url] = bytes;
            } catch (_) {}
          }
          _pendingDownloads.remove(url);
          return file;
        })
        .catchError((_) {
          _pendingDownloads.remove(url);
          return null;
        });

    _pendingDownloads[url] = downloadFuture;
    return downloadFuture;
  }
}
