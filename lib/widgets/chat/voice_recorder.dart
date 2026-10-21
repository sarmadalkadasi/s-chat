import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

/// A compact, WhatsApp-style voice-note recorder.
///
/// Opens as a modal bottom sheet anchored to the screen, so scrolling the chat
/// behind it does not move the recorder. The returned value is the recorded
/// file path, or null if the user deletes/cancels the recording.
class VoiceRecorder extends StatefulWidget {
  const VoiceRecorder({super.key});

  static Future<String?> show(BuildContext context) {
    FocusManager.instance.primaryFocus?.unfocus();
    return showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => const VoiceRecorder(),
    );
  }

  @override
  State<VoiceRecorder> createState() => VoiceRecorderState();
}

class VoiceRecorderState extends State<VoiceRecorder> {
  late final AudioRecorder _recorder;
  final AudioPlayer _player = AudioPlayer();

  Timer? _timer;
  StreamSubscription<dynamic>? _amplitudeSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<void>? _completeSubscription;

  int _elapsedSeconds = 0;
  bool _isStarting = true;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isPreview = false;
  bool _isPlaying = false;
  bool _isClosing = false;

  String? _recordingPath;
  String? _error;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;

  final List<double> _waveform = List<double>.generate(
    36,
    (index) => 0.16 + (index % 5) * 0.055,
  );

  @override
  void initState() {
    super.initState();
    _recorder = AudioRecorder();
    _listenToPlayer();
    unawaited(_startRecording());
  }

  void _listenToPlayer() {
    _durationSubscription = _player.onDurationChanged.listen((duration) {
      if (!mounted) return;
      setState(() => _playbackDuration = duration);
    });

    _positionSubscription = _player.onPositionChanged.listen((position) {
      if (!mounted) return;
      setState(() => _playbackPosition = position);
    });

    _playerStateSubscription = _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _isPlaying = state == PlayerState.playing);
    });

    _completeSubscription = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _playbackPosition = Duration.zero;
      });
      unawaited(_player.seek(Duration.zero));
    });
  }

  Future<void> _startRecording() async {
    try {
      final allowed = await _recorder.hasPermission();
      if (!allowed) {
        if (mounted) {
          setState(() {
            _isStarting = false;
            _error = 'Microphone permission was denied.';
          });
        }
        return;
      }

      final path = '${Directory.systemTemp.path}${Platform.pathSeparator}'
          's_chat_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );

      if (!mounted || _isClosing) {
        await _recorder.cancel();
        return;
      }

      setState(() {
        _isStarting = false;
        _isRecording = true;
        _error = null;
      });
      _startTimer();
      _listenToAmplitude();
    } catch (error) {
      if (mounted) {
        setState(() {
          _isStarting = false;
          _isRecording = false;
          _error = 'Could not start recording: $error';
        });
      }
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isRecording) return;
      setState(() => _elapsedSeconds++);
    });
  }

  void _listenToAmplitude() {
    unawaited(_amplitudeSubscription?.cancel());
    _amplitudeSubscription = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 120))
        .listen((amplitude) {
      if (!mounted || !_isRecording) return;

      // record returns dBFS values; map them to a visual bar height.
      final level = ((amplitude.current + 60.0) / 60.0)
          .clamp(0.10, 1.0)
          .toDouble();
      setState(() {
        _waveform.add(level);
        if (_waveform.length > 36) _waveform.removeAt(0);
      });
    }, onError: (_) {
      // Recording should continue if live amplitude is unsupported.
    });
  }

  Future<void> _togglePauseResume() async {
    try {
      if (_isRecording) {
        await _recorder.pause();
        _timer?.cancel();
        await _amplitudeSubscription?.cancel();
        if (!mounted) return;
        setState(() {
          _isRecording = false;
          _isPaused = true;
        });
      } else if (_isPaused) {
        await _recorder.resume();
        if (!mounted) return;
        setState(() {
          _isRecording = true;
          _isPaused = false;
          _error = null;
        });
        _startTimer();
        _listenToAmplitude();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not pause/resume recording: $error');
      }
    }
  }

  Future<void> _stopForPreview() async {
    if (!_isRecording && !_isPaused) return;

    try {
      _timer?.cancel();
      await _amplitudeSubscription?.cancel();
      final path = await _recorder.stop();

      if (path == null || path.isEmpty) {
        if (mounted) {
          setState(() {
            _isRecording = false;
            _isPaused = false;
            _error = 'The recording could not be saved.';
          });
        }
        return;
      }

      _recordingPath = path;
      if (mounted) {
        setState(() {
          _isRecording = false;
          _isPaused = false;
          _isPreview = true;
          _error = null;
        });
      }

      await _player.setSource(DeviceFileSource(path));
      final duration = await _player.getDuration();
      if (mounted && duration != null) {
        setState(() => _playbackDuration = duration);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _isPaused = false;
          _isPreview = _recordingPath != null;
          _error = 'Could not prepare audio preview: $error';
        });
      }
    }
  }

  Future<void> _togglePlayback() async {
    final path = _recordingPath;
    if (path == null) return;

    try {
      if (_isPlaying) {
        await _player.pause();
      } else {
        if (_playbackDuration > Duration.zero &&
            _playbackPosition >= _playbackDuration) {
          await _player.seek(Duration.zero);
        }
        await _player.resume();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not play recording: $error');
      }
    }
  }

  Future<void> _seekPlayback(double value) async {
    final target = Duration(milliseconds: value.round());
    try {
      await _player.seek(target);
    } catch (_) {
      // Keep the preview controls available if seeking is unsupported.
    }
  }

  Future<void> _sendRecording() async {
    if (_isClosing) return;
    _isClosing = true;

    try {
      _timer?.cancel();
      await _amplitudeSubscription?.cancel();

      String? path = _recordingPath;
      if (!_isPreview && (_isRecording || _isPaused)) {
        path = await _recorder.stop();
        _recordingPath = path;
      }

      if (path == null || path.isEmpty) {
        _isClosing = false;
        if (mounted) {
          setState(() => _error = 'Record a voice message before sending.');
        }
        return;
      }

      _isRecording = false;
      _isPaused = false;
      await _player.stop();
      if (mounted) Navigator.of(context).pop<String>(path);
    } catch (error) {
      _isClosing = false;
      if (mounted) {
        setState(() => _error = 'Could not finish recording: $error');
      }
    }
  }

  Future<void> _deleteRecording() async {
    if (_isClosing) return;
    _isClosing = true;
    _timer?.cancel();

    try {
      await _amplitudeSubscription?.cancel();
      await _player.stop();

      if (_isRecording || _isPaused) {
        await _recorder.cancel();
      }

      final path = _recordingPath;
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    } catch (_) {
      // Close the sheet even if native cleanup fails.
    }

    _isRecording = false;
    _isPaused = false;
    if (mounted) Navigator.of(context).pop<String>(null);
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String get _elapsedLabel =>
      _formatDuration(Duration(seconds: _elapsedSeconds));

  Widget _buildWaveform(Color color) {
    return SizedBox(
      height: 34,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final level in _waveform)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  height: 5 + (level * 27),
                  decoration: BoxDecoration(
                    color: color.withAlpha(170),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaybackSlider(BuildContext context) {
    final maxMs = (_playbackDuration.inMilliseconds > 0
            ? _playbackDuration.inMilliseconds
            : _elapsedSeconds * 1000)
        .clamp(1, 1 << 31)
        .toDouble();
    final currentMs = _playbackPosition.inMilliseconds
        .clamp(0, maxMs.toInt())
        .toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            min: 0,
            max: maxMs,
            value: currentMs,
            onChanged: _playbackDuration > Duration.zero ? _seekPlayback : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_playbackPosition),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              Text(
                _formatDuration(
                  _playbackDuration > Duration.zero
                      ? _playbackDuration
                      : Duration(seconds: _elapsedSeconds),
                ),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _disposeAudioResources() async {
    if (_isRecording || _isPaused) {
      try {
        await _recorder.cancel();
      } catch (_) {
        // The recorder may already have stopped.
      }
    }
    try {
      await _recorder.dispose();
    } catch (_) {
      // Best-effort cleanup.
    }
    try {
      await _player.dispose();
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_amplitudeSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    unawaited(_positionSubscription?.cancel());
    unawaited(_playerStateSubscription?.cancel());
    unawaited(_completeSubscription?.cancel());
    unawaited(_disposeAudioResources());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final canSend = _isPreview || _isRecording || _isPaused;
    final canControlRecording = _isRecording || _isPaused;

    final status = _isStarting
        ? 'Starting microphone…'
        : _error != null
            ? 'Voice message'
            : _isRecording
                ? 'Recording voice message'
                : _isPaused
                    ? 'Recording paused'
                    : _isPreview
                        ? 'Preview voice message'
                        : 'Voice message';

    return Material(
      color: colors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.onSurfaceVariant.withAlpha(100),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: (_error == null ? colors.primary : colors.error)
                          .withAlpha(22),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isPreview
                          ? Icons.graphic_eq_rounded
                          : Icons.mic_rounded,
                      color: _error == null ? colors.primary : colors.error,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _isPreview
                              ? '${_formatDuration(_playbackPosition)} / '
                                  '${_formatDuration(_playbackDuration > Duration.zero ? _playbackDuration : Duration(seconds: _elapsedSeconds))}'
                              : _elapsedLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.error,
                    ),
                  ),
                )
              else if (_isPreview)
                _buildPlaybackSlider(context)
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _buildWaveform(colors.primary),
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Delete recording',
                    onPressed: _deleteRecording,
                    icon: const Icon(Icons.delete_outline_rounded),
                    color: colors.error,
                  ),
                  const Spacer(),
                  if (canControlRecording) ...[
                    IconButton.filledTonal(
                      tooltip: _isRecording
                          ? 'Pause recording'
                          : 'Resume recording',
                      onPressed: _togglePauseResume,
                      icon: Icon(
                        _isRecording ? Icons.pause_rounded : Icons.mic_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Stop and preview',
                      onPressed: _stopForPreview,
                      icon: const Icon(Icons.stop_rounded),
                    ),
                  ],
                  if (_isPreview) ...[
                    IconButton.filledTonal(
                      tooltip: _isPlaying
                          ? 'Pause playback'
                          : 'Play recording',
                      onPressed: _togglePlayback,
                      icon: Icon(
                        _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                  ],
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: canSend ? _sendRecording : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(50, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: const StadiumBorder(),
                    ),
                    child: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
