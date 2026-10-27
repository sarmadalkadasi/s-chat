import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

class MediaCompressionService {
  MediaCompressionService._();
  static final MediaCompressionService instance = MediaCompressionService._();

  /// Compresses raw image bytes to standard display dimensions & PNG/JPEG format
  Future<Uint8List?> compressImageBytes({
    required Uint8List rawBytes,
    int targetWidth = 1024,
    int targetHeight = 1024,
  }) async {
    try {
      final codec = await ui.instantiateImageCodec(
        rawBytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      return rawBytes;
    }
  }

  /// Compresses an image file before upload
  Future<File> compressImageFile({
    required File inputFile,
    int targetWidth = 1024,
    int targetHeight = 1024,
  }) async {
    if (kIsWeb) return inputFile;
    try {
      final bytes = await inputFile.readAsBytes();
      final compressed = await compressImageBytes(
        rawBytes: bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      if (compressed == null || compressed.isEmpty) return inputFile;

      final tempDir = Directory.systemTemp;
      final compressedFile = File(
        '${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      return await compressedFile.writeAsBytes(compressed);
    } catch (_) {
      return inputFile;
    }
  }
}
