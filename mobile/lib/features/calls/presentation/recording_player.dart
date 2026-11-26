import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../data/calls_repository.dart';

/// Plays a call recording from a short-lived signed URL (fetched on first play,
/// so recording access is permission-checked and audit-logged by the backend).
class RecordingPlayer extends ConsumerStatefulWidget {
  const RecordingPlayer({super.key, required this.recordingId});

  final String recordingId;

  @override
  ConsumerState<RecordingPlayer> createState() => _RecordingPlayerState();
}

class _RecordingPlayerState extends ConsumerState<RecordingPlayer> {
  final _player = AudioPlayer();
  final _subs = <StreamSubscription<dynamic>>[];
  bool _loaded = false;
  bool _loading = false;
  String? _error;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _subs
      ..add(
        _player.positionStream.listen((p) {
          if (mounted) setState(() => _position = p);
        }),
      )
      ..add(
        _player.durationStream.listen((d) {
          if (mounted) setState(() => _duration = d ?? Duration.zero);
        }),
      )
      ..add(
        _player.playerStateStream.listen((s) {
          if (mounted) setState(() => _playing = s.playing && s.processingState != ProcessingState.completed);
          if (s.processingState == ProcessingState.completed) {
            _player.pause();
            _player.seek(Duration.zero);
          }
        }),
      );
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    if (!_loaded) {
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        final signed = await ref.read(callsRepositoryProvider).recordingUrl(widget.recordingId);
        await _player.setUrl(signed.url);
        _loaded = true;
      } catch (e) {
        setState(() => _error = e is ApiException ? e.friendlyMessage : 'Couldn\'t load the recording.');
        return;
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
    unawaited(_player.play());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton.filled(
              tooltip: _playing ? 'Pause' : 'Play recording',
              onPressed: _loading ? null : _toggle,
              icon: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_playing ? Icons.pause : Icons.play_arrow),
            ),
            Expanded(
              child: Slider(
                value: _position.inMilliseconds.clamp(0, max.toInt()).toDouble(),
                max: max,
                onChanged: _loaded ? (v) => _player.seek(Duration(milliseconds: v.toInt())) : null,
              ),
            ),
            Text('${formatTimer(_position)} / ${formatTimer(_duration)}', style: theme.textTheme.labelSmall),
          ],
        ),
        if (_error != null) Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
      ],
    );
  }
}
