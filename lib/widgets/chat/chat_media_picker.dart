import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Media type selected from the chat attachment sheet.
enum ChatAttachmentKind { image, video, file, audio }

/// A selected chat attachment. [path] is usually a temporary/local file path.
/// Upload the file to your storage service before saving it as a chat message.
class ChatAttachment {
  const ChatAttachment({
    required this.kind,
    required this.name,
    this.path,
    this.url,
    this.sizeBytes,
  });

  final ChatAttachmentKind kind;
  final String name;
  final String? path;
  final String? url;
  final int? sizeBytes;
}

typedef ChatMediaSelected = void Function(List<ChatAttachment> attachments);

enum _AttachmentAction {
  gallery,
  camera,
  video,
  recordVideo,
  files,
  audio,
}

/// A lightweight replacement for `full_picker`.
///
/// Uses `image_picker` for photos/videos and `file_picker` for documents/audio.
/// Voice notes use the small `record` plugin directly. Image cropping and
/// video compression are intentionally omitted to avoid extra dependencies.
class ChatMediaPicker {
  const ChatMediaPicker._();

  static Future<void> show({
    required BuildContext context,
    required ChatMediaSelected onSelected,
  }) async {
    final action = await showModalBottomSheet<_AttachmentAction>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _AttachmentSheet(
        onSelect: (value) => Navigator.of(sheetContext).pop(value),
      ),
    );

    if (action == null || !context.mounted) return;


    try {
      final attachments = await _pick(context, action);
      if (attachments.isNotEmpty && context.mounted) {
        onSelected(attachments);
      }
    } on PlatformException catch (error) {
      if (context.mounted) {
        _showError(context, error.message ?? 'Could not open the media picker.');
      }
    } catch (error) {
      if (context.mounted) {
        _showError(context, 'Could not select media: $error');
      }
    }
  }

  static Future<List<ChatAttachment>> _pick(
    BuildContext context,
    _AttachmentAction action,
  ) async {
    final imagePicker = ImagePicker();

    switch (action) {
      case _AttachmentAction.gallery:
        final images = await imagePicker.pickMultiImage(imageQuality: 90);
        return images
            .map(
              (file) => ChatAttachment(
                kind: ChatAttachmentKind.image,
                name: file.name,
                path: file.path,
              ),
            )
            .toList(growable: false);

      case _AttachmentAction.camera:
        final file = await imagePicker.pickImage(
          source: ImageSource.camera,
          imageQuality: 90,
        );
        if (file == null) return const [];
        return [
          ChatAttachment(
            kind: ChatAttachmentKind.image,
            name: file.name,
            path: file.path,
          ),
        ];

      case _AttachmentAction.video:
        final file = await imagePicker.pickVideo(
          source: ImageSource.gallery,
        );
        if (file == null) return const [];
        return [
          ChatAttachment(
            kind: ChatAttachmentKind.video,
            name: file.name,
            path: file.path,
          ),
        ];

      case _AttachmentAction.recordVideo:
        final file = await imagePicker.pickVideo(
          source: ImageSource.camera,
        );
        if (file == null) return const [];
        return [
          ChatAttachment(
            kind: ChatAttachmentKind.video,
            name: file.name,
            path: file.path,
          ),
        ];

      case _AttachmentAction.files:
        final files = await _pickPlatformFiles(type: FileType.any);
        return files
            .map(_fromPlatformFile)
            .toList(growable: false);

      case _AttachmentAction.audio:
        final files = await _pickPlatformFiles(type: FileType.audio);
        return files
            .map(
              (file) => ChatAttachment(
                kind: ChatAttachmentKind.audio,
                name: file.name,
                path: file.path,
                sizeBytes: _platformFileSize(file),
              ),
            )
            .toList(growable: false);
    }
  }

  /// versions (FilePickerResult) without loading file contents into memory.
  static Future<List<PlatformFile>> _pickPlatformFiles({
    required FileType type,
  }) async {
    final dynamic result = await FilePicker.pickFiles(type: type);
    if (result == null) return const [];
    if (result is List<PlatformFile>) return result;

    // Compatibility with file_picker versions that return FilePickerResult.
    try {
      final dynamic files = result.files;
      if (files is List<PlatformFile>) return files;
    } catch (_) {
      // Return an empty selection if the result shape is unexpected.
    }
    return const [];
  }

  static int? _platformFileSize(PlatformFile file) {
    final dynamic dynamicFile = file;
    try {
      final dynamic length = dynamicFile.lengthSync();
      if (length is int) return length;
    } catch (_) {
      // Older versions expose `size` instead of `lengthSync()`.
    }
    try {
      final dynamic size = dynamicFile.size;
      if (size is int) return size;
    } catch (_) {
      // Size metadata is optional.
    }
    return null;
  }

  static ChatAttachment _fromPlatformFile(PlatformFile file) {
    final extension = (file.extension ?? '').toLowerCase();
    const audioExtensions = {
      'aac', 'm4a', 'mp3', 'oga', 'ogg', 'opus', 'wav', 'flac', 'wma'
    };
    const videoExtensions = {
      '3gp', 'avi', 'm4v', 'mkv', 'mov', 'mp4', 'mpeg', 'mpg', 'webm', 'wmv'
    };

    final kind = audioExtensions.contains(extension)
        ? ChatAttachmentKind.audio
        : videoExtensions.contains(extension)
            ? ChatAttachmentKind.video
            : ChatAttachmentKind.file;

    return ChatAttachment(
      kind: kind,
      name: file.name,
      path: file.path,
      sizeBytes: _platformFileSize(file),
    );
  }

  static void _showError(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _AttachmentSheet extends StatelessWidget {
  const _AttachmentSheet({required this.onSelect});

  final ValueChanged<_AttachmentAction> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final items = <_AttachmentTileData>[
      _AttachmentTileData(
        action: _AttachmentAction.gallery,
        icon: Icons.photo_library_rounded,
        title: 'Gallery',
        color: Colors.purple,
      ),
      _AttachmentTileData(
        action: _AttachmentAction.camera,
        icon: Icons.camera_alt_rounded,
        title: 'Camera',
        color: Colors.deepOrange,
      ),
      _AttachmentTileData(
        action: _AttachmentAction.video,
        icon: Icons.video_library_rounded,
        title: 'Video',
        color: Colors.blue,
      ),
      _AttachmentTileData(
        action: _AttachmentAction.recordVideo,
        icon: Icons.videocam_rounded,
        title: 'Record video',
        color: Colors.red,
      ),
      _AttachmentTileData(
        action: _AttachmentAction.files,
        icon: Icons.insert_drive_file_rounded,
        title: 'Document',
        color: Colors.teal,
      ),
      _AttachmentTileData(
        action: _AttachmentAction.audio,
        icon: Icons.headphones_rounded,
        title: 'Audio file',
        color: Colors.indigo,
      ),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withAlpha(100),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Share media',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.95,
              ),
              itemBuilder: (context, index) {
                final item = items[index];
                return _AttachmentTile(
                  item: item,
                  onTap: () => onSelect(item.action),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentTileData {
  const _AttachmentTileData({
    required this.action,
    required this.icon,
    required this.title,
    required this.color,
  });

  final _AttachmentAction action;
  final IconData icon;
  final String title;
  final Color color;
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.item,
    required this.onTap,
  });

  final _AttachmentTileData item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.surfaceContainerHighest.withAlpha(100),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: item.color.withAlpha(28),
                  shape: BoxShape.circle,
                ),
                child: Icon(item.icon, color: item.color, size: 25),
              ),
              const SizedBox(height: 9),
              Text(
                item.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
