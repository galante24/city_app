import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_constants.dart';
import '../config/supabase_ready.dart';
import '../services/chat_service.dart';

class UserChatThreadScreen extends StatefulWidget {
  const UserChatThreadScreen({
    super.key,
    required this.conversationId,
    required this.title,
  });

  final String conversationId;
  final String title;

  @override
  State<UserChatThreadScreen> createState() => _UserChatThreadScreenState();
}

class _UserChatThreadScreenState extends State<UserChatThreadScreen> {
  final TextEditingController _input = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  String _timeLabel(String? iso) {
    if (iso == null || iso.isEmpty) {
      return '';
    }
    try {
      final DateTime d = DateTime.parse(iso).toLocal();
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } on Object {
      return '';
    }
  }

  Future<void> _send() async {
    if (!supabaseAppReady) {
      return;
    }
    final String t = _input.text.trim();
    if (t.isEmpty || _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      await ChatService.sendMessage(widget.conversationId, t);
      _input.clear();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось отправить')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!supabaseAppReady) {
      return const Scaffold(
        body: Center(child: Text('Supabase не настроен')),
      );
    }
    final String? me = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kPrimaryBlue),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: _MessagesList(
              conversationId: widget.conversationId,
              me: me,
              timeLabel: _timeLabel,
            ),
          ),
          Container(
            color: Colors.white,
            padding: EdgeInsets.fromLTRB(8, 4, 8, 4 + MediaQuery.viewPaddingOf(context).bottom),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Сообщение…',
                      filled: true,
                      fillColor: const Color(0xFFF0F0F0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessagesList extends StatelessWidget {
  const _MessagesList({
    required this.conversationId,
    required this.me,
    required this.timeLabel,
  });

  final String conversationId;
  final String? me;
  final String Function(String? iso) timeLabel;

  @override
  Widget build(BuildContext context) {
    if (me == null) {
      return const Center(child: Text('Нет сессии'));
    }
    final Stream<List<Map<String, dynamic>>>? stream = ChatService.watchMessages(conversationId);
    if (stream == null) {
      return const Center(child: Text('Нет соединения'));
    }
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (BuildContext c, AsyncSnapshot<List<Map<String, dynamic>>> s) {
        if (s.hasError) {
          return Center(child: Text('Ошибка: ${s.error}'));
        }
        if (!s.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final List<Map<String, dynamic>> rows = s.data ?? <Map<String, dynamic>>[];
        if (rows.isEmpty) {
          return const Center(
            child: Text(
              'Пока нет сообщений — напишите первым',
              style: TextStyle(color: Color(0xFF6B6B70)),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: rows.length,
          itemBuilder: (BuildContext context, int i) {
            final Map<String, dynamic> m = rows[i];
            final String? sid = m['sender_id']?.toString();
            final bool mine = sid == me;
            final String text = (m['body'] as String?) ?? '';
            return Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.82,
                ),
                decoration: BoxDecoration(
                  color: mine ? kPrimaryBlue : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(mine ? 16 : 4),
                    bottomRight: Radius.circular(mine ? 4 : 16),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: const Color(0xFF0A0A0A).withValues(alpha: 0.04),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      text,
                      style: TextStyle(
                        color: mine ? Colors.white : const Color(0xFF1A1A1A),
                        fontSize: 15,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeLabel(m['created_at'] as String?),
                      style: TextStyle(
                        color: mine
                            ? Colors.white.withValues(alpha: 0.75)
                            : const Color(0xFF8A8A8E),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
