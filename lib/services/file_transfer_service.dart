import 'dart:async';
import 'dart:io';

class FileTransferService {
  FileTransferService._();
  static final FileTransferService instance = FileTransferService._();

  static const int defaultChunkSize = 64 * 1024; // 64 KB chunks

  /// Telegram-style chunked stream downloader with progress updates and atomic rename
  Future<File?> downloadFileChunked({
    required String url,
    required File targetFile,
    int chunkSize = defaultChunkSize,
    void Function(double progress)? onProgress,
  }) async {
    final partFile = File('${targetFile.path}.part');
    final client = HttpClient();

    try {
      final uri = Uri.tryParse(url);
      if (uri == null) return null;

      final request = await client.getUrl(uri);
      final response = await request.close();

      if (response.statusCode != 200) {
        client.close();
        return null;
      }

      final contentLength = response.contentLength;
      int downloadedBytes = 0;

      final partSink = partFile.openWrite();

      await for (final chunk in response) {
        partSink.add(chunk);
        downloadedBytes += chunk.length;
        if (contentLength > 0 && onProgress != null) {
          onProgress(downloadedBytes / contentLength);
        }
      }

      await partSink.flush();
      await partSink.close();

      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await partFile.rename(targetFile.path);
      client.close();

      return targetFile;
    } catch (e) {
      client.close();
      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
      return null;
    }
  }
}
