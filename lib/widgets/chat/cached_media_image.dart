import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:s_chat/services/media_cache_service.dart';

class CachedMediaImage extends StatefulWidget {
  const CachedMediaImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  State<CachedMediaImage> createState() => _CachedMediaImageState();
}

class _CachedMediaImageState extends State<CachedMediaImage> {
  File? _cachedFile;
  Uint8List? _memoryBytes;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  @override
  void didUpdateWidget(covariant CachedMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _loadMedia();
    }
  }

  void _loadMedia() async {
    if (widget.imageUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
      return;
    }

    // Fast path 1: memory cache (0ms instant)
    final mem = MediaCacheService.instance.getFromMemory(widget.imageUrl);
    if (mem != null) {
      if (mounted) {
        setState(() {
          _memoryBytes = mem;
          _isLoading = false;
          _hasError = false;
        });
      }
      return;
    }

    // Fast path 2 / Chunked download path
    final file = await MediaCacheService.instance.getMediaFile(
      widget.imageUrl,
    );
    if (!mounted) return;

    if (file != null && await file.exists()) {
      setState(() {
        _cachedFile = file;
        _isLoading = false;
        _hasError = false;
      });
    } else {
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_memoryBytes != null) {
      return Image.memory(
        _memoryBytes!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
      );
    }

    if (_cachedFile != null && !kIsWeb) {
      return Image.file(
        _cachedFile!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
      );
    }

    if (_isLoading) {
      return widget.placeholder ??
          SizedBox(
            width: widget.width,
            height: widget.height,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.0),
              ),
            ),
          );
    }

    if (_hasError) {
      return widget.errorWidget ??
          SizedBox(
            width: widget.width,
            height: widget.height,
            child: const Icon(Icons.broken_image, size: 24, color: Colors.grey),
          );
    }

    return const SizedBox.shrink();
  }
}
