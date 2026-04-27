import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

/// Мини-плеер для голосового вложения (кэш URL в [AudioPlayer]).
class ChatVoiceMessageBubble extends StatefulWidget {
  const ChatVoiceMessageBubble({
    super.key,
    required this.playUrl,
    this.durationMs,
    required this.outgoing,
    required this.incomingUnread,
  });

  final String playUrl;
  final int? durationMs;
  final bool outgoing;
  final bool incomingUnread;

  @override
  State<ChatVoiceMessageBubble> createState() => _ChatVoiceMessageBubbleState();
}

class _ChatVoiceMessageBubbleState extends State<ChatVoiceMessageBubble> {
  late final AudioPlayer _player = AudioPlayer();
  bool _busy = false;

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      if (_player.playing) {
        await _player.pause();
      } else {
        await _player.setUrl(widget.playUrl);
        await _player.play();
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _label() {
    final int? ms = widget.durationMs;
    if (ms == null || ms <= 0) {
      return 'Голосовое';
    }
    final int s = (ms + 500) ~/ 1000;
    final int m = s ~/ 60;
    final int r = s % 60;
    if (m > 0) {
      return '$m:${r.toString().padLeft(2, '0')}';
    }
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color fg = widget.outgoing ? Colors.white : cs.onSurface;
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (BuildContext context, AsyncSnapshot<PlayerState> snap) {
        final bool playing = snap.data?.playing ?? false;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: _busy ? null : _toggle,
              icon: _busy
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: fg,
                      ),
                    )
                  : Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: fg,
                      size: 32,
                    ),
            ),
            const SizedBox(width: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _label(),
                  style: TextStyle(
                    color: fg,
                    fontSize: 14,
                    fontWeight: widget.incomingUnread
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
                SizedBox(
                  width: 120,
                  height: 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: playing ? null : 0,
                      backgroundColor: fg.withValues(alpha: 0.25),
                      valueColor: AlwaysStoppedAnimation<Color>(fg),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
