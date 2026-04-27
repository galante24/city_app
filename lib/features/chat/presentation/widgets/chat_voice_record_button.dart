import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Кнопка: удержание — запись, свайп влево — отмена, отпускание — отправка.
class ChatVoiceRecordButton extends StatefulWidget {
  const ChatVoiceRecordButton({
    super.key,
    required this.onSend,
    required this.onCancel,
    this.enabled = true,
  });

  final Future<void> Function(String filePath, int durationMs) onSend;
  final void Function() onCancel;
  final bool enabled;

  @override
  State<ChatVoiceRecordButton> createState() => _ChatVoiceRecordButtonState();
}

class _ChatVoiceRecordButtonState extends State<ChatVoiceRecordButton> {
  final AudioRecorder _rec = AudioRecorder();
  bool _down = false;
  bool _cancel = false;
  double _startX = 0;
  late final Stopwatch _sw = Stopwatch();
  String? _path;
  Timer? _tick;
  int _tenths = 0;

  @override
  void dispose() {
    _tick?.cancel();
    unawaited(_rec.dispose());
    super.dispose();
  }

  Future<void> _arm(PointerDownEvent e) async {
    if (!widget.enabled) {
      return;
    }
    _down = true;
    _cancel = false;
    _startX = e.position.dx;
    setState(() {});
    if (!await _rec.hasPermission()) {
      final PermissionStatus st = await Permission.microphone.request();
      if (!st.isGranted) {
        if (mounted) {
          setState(() => _down = false);
        }
        return;
      }
    }
    final Directory d = await getTemporaryDirectory();
    _path = '${d.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _sw
      ..reset()
      ..start();
    _tenths = 0;
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) {
        setState(() {
          _tenths = _sw.elapsedMilliseconds ~/ 100;
        });
      }
    });
    await _rec.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: _path!,
    );
  }

  void _move(PointerMoveEvent e) {
    if (!_down) {
      return;
    }
    final bool next = (e.position.dx - _startX) < -72;
    if (next != _cancel) {
      setState(() => _cancel = next);
    }
  }

  Future<void> _end(PointerUpEvent e) async {
    if (!_down) {
      return;
    }
    _down = false;
    _tick?.cancel();
    _tick = null;
    final int ms = _sw.elapsedMilliseconds;
    _sw.stop();
    final String? p = _path;
    setState(() {});
    if (p == null) {
      return;
    }
    await _rec.stop();
    if (_cancel) {
      try {
        final File f = File(p);
        if (f.existsSync()) {
          f.deleteSync();
        }
      } on Object {
        // ignore
      }
      _path = null;
      widget.onCancel();
      return;
    }
    if (ms < 600) {
      try {
        final File f = File(p);
        if (f.existsSync()) {
          f.deleteSync();
        }
      } on Object {
        // ignore
      }
      _path = null;
      return;
    }
    await widget.onSend(p, ms);
    _path = null;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    if (_down) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_cancel)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                'Отпустить для отмены',
                style: TextStyle(
                  color: cs.error,
                  fontSize: 12,
                ),
              ),
            ),
          _MiniWaveform(phase: _tenths, cancel: _cancel),
          const SizedBox(width: 6),
          Text(
            '${(_tenths / 10).floor()}:${(_tenths % 10)}',
            style: TextStyle(
              color: _cancel ? cs.error : cs.primary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }
    return Listener(
      onPointerDown: (PointerDownEvent e) {
        unawaited(_arm(e));
      },
      onPointerMove: _move,
      onPointerUp: _end,
      onPointerCancel: (_) {
        if (_down) {
          unawaited(_end(PointerUpEvent(position: Offset.zero)));
        }
      },
      child: Material(
        color: Colors.transparent,
        child: IconButton.filledTonal(
          onPressed: () {},
          icon: const Icon(Icons.mic_rounded),
          tooltip: 'Удерживайте для записи',
        ),
      ),
    );
  }
}

class _MiniWaveform extends StatelessWidget {
  const _MiniWaveform({required this.phase, required this.cancel});

  final int phase;
  final bool cancel;

  @override
  Widget build(BuildContext context) {
    final Color c = cancel
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(8, (int i) {
        final double h = 4.0 + 12 * (0.5 + 0.5 * math.sin(phase * 0.4 + i * 0.7));
        return Container(
          width: 3,
          height: h,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
