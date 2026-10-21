import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:s_chat/models/chat_message.dart';
import 'package:s_chat/services/message_repository.dart';
import 'package:s_chat/widgets/chat/image_viewer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Renders a chat attachment encoded in [ChatMessage.text].
///
/// Audio supports local playback for queued/sent-by-this-device media and a
/// signed Supabase Storage URL for media sent by another device. The bucket is
/// private; no permanent public URLs are stored in chat messages.
class ChatMediaMessageBubble extends StatefulWidget {
  const ChatMediaMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
  });

  final ChatMessage message;
  final bool isMe;

  @override
  State<ChatMediaMessageBubble> createState() =>
      _ChatMediaMessageBubbleState();
}

class _ChatMediaMessageBubbleState extends State<ChatMediaMessageBubble> {
  late final AudioPlayer _audioPlayer;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<void>? _completeSubscription;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isLoadingAudio = false;
  bool _audioSourceLoaded = false;
  bool _audioEnded = false;
  String? _audioError;
  Future<String?>? _signedImageUrlFuture;

  ChatMessage get _message => widget.message;

  String? get _existingLocalPath {
    final path = _message.mediaLocalPath;
    if (path == null || path.isEmpty) return null;
    try {
      return File(path).existsSync() ? path : null;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _positionSubscription = _audioPlayer.onPositionChanged.listen((value) {
      if (mounted) setState(() => _position = value);
    });
    _durationSubscription = _audioPlayer.onDurationChanged.listen((value) {
      if (mounted) setState(() => _duration = value);
    });
    _stateSubscription = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    _completeSubscription = _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
        _audioEnded = true;
      });
      unawaited(_audioPlayer.seek(Duration.zero));
    });
    _refreshSignedImageUrl();
  }

  @override
  void didUpdateWidget(covariant ChatMediaMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.message.text != widget.message.text) {
      _refreshSignedImageUrl();
      _audioError = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _audioSourceLoaded = false;
      _audioEnded = false;
    }
  }

  void _refreshSignedImageUrl() {
    if (_message.mediaKind != 'image' ||
        _existingLocalPath != null ||
        _message.mediaStoragePath == null) {
      _signedImageUrlFuture = null;
      return;
    }
    _signedImageUrlFuture = _createSignedUrl(_message.mediaStoragePath!);
  }

  Future<String?> _createSignedUrl(String storagePath) async {
    try {
      return await Supabase.instance.client.storage
          .from(MessageRepository.mediaStorageBucket)
          .createSignedUrl(storagePath, 60 * 60);
    } catch (_) {
      return null;
    }
  }

  Future<void> _toggleAudio() async {
    if (_isLoadingAudio) return;

    if (_isPlaying) {
      await _audioPlayer.pause();
      return;
    }

    setState(() {
      _isLoadingAudio = true;
      _audioError = null;
    });

    try {
      if (_audioSourceLoaded && !_audioEnded) {
        await _audioPlayer.resume();
      } else {
        final localPath = _existingLocalPath;
        if (localPath != null) {
          await _audioPlayer.play(DeviceFileSource(localPath));
        } else if (_message.mediaStoragePath != null) {
          final signedUrl = await _createSignedUrl(_message.mediaStoragePath!);
          if (signedUrl == null || signedUrl.isEmpty) {
            throw StateError('Could not access this audio while offline.');
          }
          await _audioPlayer.play(UrlSource(signedUrl));
        } else if (_message.mediaUrl != null) {
          await _audioPlayer.play(UrlSource(_message.mediaUrl!));
        } else {
          throw StateError('The audio file is not available on this device.');
        }
        _audioSourceLoaded = true;
        _audioEnded = false;
      }
    } catch (error) {
      if (mounted) {
        setState(() => _audioError = 'Audio unavailable');
      }
    } finally {
      if (mounted) setState(() => _isLoadingAudio = false);
    }
  }

  Future<void> _seekAudio(double value) async {
    final target = Duration(milliseconds: value.round());
    await _audioPlayer.seek(target);
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildAudio() {
    final maxMs = _duration.inMilliseconds.toDouble();
    final currentMs = _position.inMilliseconds.toDouble().clamp(
      0.0,
      maxMs > 0 ? maxMs : 1.0,
    ).toDouble();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 270),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filledTonal(
            onPressed: _isLoadingAudio ? null : _toggleAudio,
            icon: _isLoadingAudio
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
            tooltip: _isPlaying ? 'Pause voice message' : 'Play voice message',
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.graphic_eq_rounded, size: 17),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        _audioError ?? 'Voice message',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 10,
                    ),
                  ),
                  child: Slider(
                    value: currentMs,
                    min: 0,
                    max: maxMs > 0 ? maxMs : 1,
                    onChanged: maxMs > 0
                        ? (value) => _seekAudio(value)
                        : null,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(
                        _duration > Duration.zero ? _position : Duration.zero,
                      ),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(
                      _formatDuration(_duration),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImage() {
    final localPath = _existingLocalPath;
    if (localPath != null) {
      return InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ImageViewer(
              imageUrl: localPath,
              imageType: ImageType.file,
            ),
          ),
        ),
        child: Hero(
          tag: localPath,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(localPath),
              width: 240,
              height: 190,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _unavailableTile(Icons.image_rounded, 'Photo'),
            ),
          ),
        ),
      );
    }

    final future = _signedImageUrlFuture;
    if (future == null) return _unavailableTile(Icons.image_rounded, 'Photo');

    return FutureBuilder<String?>(
      future: future,
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            width: 240,
            height: 150,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (url == null || url.isEmpty) {
          return _unavailableTile(Icons.image_rounded, 'Photo unavailable offline');
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            url,
            width: 240,
            height: 190,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _unavailableTile(Icons.image_rounded, 'Photo unavailable'),
          ),
        );
      },
    );
  }

  Widget _buildFileLike({required IconData icon, required String label}) {
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            backgroundColor: colors.primaryContainer,
            child: Icon(icon, color: colors.onPrimaryContainer),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(
                  'Attachment',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _unavailableTile(IconData icon, String label) {
    return Container(
      width: 240,
      height: 100,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 30), const SizedBox(height: 6), Text(label)],
      ),
    );
  }

  Widget _buildContent() {
    switch (_message.mediaKind) {
      case 'audio':
        return _buildAudio();
      case 'image':
        return _buildImage();
      case 'video':
        return _buildFileLike(icon: Icons.videocam_rounded, label: _message.mediaName);
      case 'url':
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: SelectableText(_message.mediaUrl ?? _message.mediaName),
        );
      case 'file':
      default:
        return _buildFileLike(icon: Icons.insert_drive_file_rounded, label: _message.mediaName);
    }
  }

  @override
  void dispose() {
    unawaited(_positionSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    unawaited(_stateSubscription?.cancel());
    unawaited(_completeSubscription?.cancel());
    unawaited(_audioPlayer.dispose());
    super.dispose();
  }

  Widget _buildSyncStatus(MediaSyncStatus? status) {
    if (!_message.isPending) return const SizedBox.shrink();

    final phase = status?.phase ?? MediaSyncPhase.queued;
    final colors = Theme.of(context).colorScheme;
    final bool isBusy = phase == MediaSyncPhase.uploading ||
        phase == MediaSyncPhase.savingMessage;

    final String label;
    switch (phase) {
      case MediaSyncPhase.uploading:
        label = 'Uploading media…';
        break;
      case MediaSyncPhase.savingMessage:
        label = 'Finishing message…';
        break;
      case MediaSyncPhase.queued:
        label = MessageRepository.instance.isOnline
            ? 'Queued to send'
            : 'Waiting for connection';
        break;
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 270),
      child: Padding(
        padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isBusy)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: colors.primary,
                    ),
                  )
                else
                  Icon(
                    Icons.schedule_rounded,
                    size: 13,
                    color: colors.onSurfaceVariant,
                  ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (isBusy) ...[
              const SizedBox(height: 5),
              const LinearProgressIndicator(minHeight: 2),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = MessageRepository.instance;
    final messageId = _message.id?.toString() ?? '';

    return StreamBuilder<Map<String, MediaSyncStatus>>(
      stream: repository.mediaSyncStatusStream,
      initialData: repository.mediaSyncStatuses,
      builder: (context, snapshot) {
        final statuses = snapshot.data ?? const <String, MediaSyncStatus>{};
        final status = statuses[messageId];

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildContent(),
              _buildSyncStatus(status),
            ],
          ),
        );
      },
    );
  }
}
