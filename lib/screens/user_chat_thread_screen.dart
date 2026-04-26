import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_constants.dart';
import '../config/supabase_ready.dart';
import '../models/conversation_list_item.dart';
import '../services/chat_service.dart';
import '../services/chat_unread_badge.dart';
import 'group_chat_info_screen.dart';

class UserChatThreadScreen extends StatefulWidget {
  const UserChatThreadScreen({
    super.key,
    required this.conversationId,
    required this.title,
    this.listItem,
  });

  final String conversationId;
  final String title;
  final ConversationListItem? listItem;

  @override
  State<UserChatThreadScreen> createState() => _UserChatThreadScreenState();
}

class _UserChatThreadScreenState extends State<UserChatThreadScreen> {
  final TextEditingController _input = TextEditingController();
  bool _sending = false;
  String _headerTitle = '';
  bool? _isGroup;
  bool? _isOpen;
  String? _myRole;
  Timer? _readDebounce;
  /// Курсор «прочитано до» (для стиля входящих + галочек исходящих).
  DateTime? _myReadCursor;
  Map<String, DateTime?> _otherReadByUser = <String, DateTime?>{};

  @override
  void initState() {
    super.initState();
    _headerTitle = widget.title;
    _isGroup = widget.listItem?.isGroup;
    _isOpen = widget.listItem?.isOpen;
    _myRole = widget.listItem?.myRole;
    _loadMeta();
    unawaited(_bootstrapReadState());
  }

  Future<void> _loadMeta() async {
    if (widget.listItem == null) {
      final Map<String, dynamic>? row = await ChatService.fetchConversation(widget.conversationId);
      if (row != null && mounted) {
        setState(() {
          _isGroup = row['is_group'] as bool? ?? !(row['is_direct'] as bool? ?? true);
          _isOpen = row['is_open'] as bool?;
          if (_isGroup == true) {
            _headerTitle = (row['group_name'] as String?)?.trim() ?? 'Группа';
          }
        });
      }
      final String? r = await ChatService.getMyRoleInConversation(widget.conversationId);
      if (mounted) {
        setState(() => _myRole = r ?? _myRole);
      }
    }
  }

  @override
  void dispose() {
    _readDebounce?.cancel();
    _input.dispose();
    unawaited(ChatUnreadBadge.refresh());
    super.dispose();
  }

  Future<void> _bootstrapReadState() async {
    if (!supabaseAppReady) {
      return;
    }
    final DateTime? first = await ChatService.getMyLastReadInConversation(widget.conversationId);
    if (mounted) {
      setState(() => _myReadCursor = first);
    }
    await ChatService.markConversationRead(widget.conversationId);
    final DateTime? after = await ChatService.getMyLastReadInConversation(widget.conversationId);
    final Map<String, DateTime?> other =
        await ChatService.getOtherParticipantsLastReadMap(widget.conversationId);
    if (mounted) {
      setState(() {
        _myReadCursor = after ?? _myReadCursor;
        _otherReadByUser = other;
      });
    }
    await ChatUnreadBadge.refresh();
  }

  void _scheduleReadSync() {
    _readDebounce?.cancel();
    _readDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!supabaseAppReady) {
        return;
      }
      await ChatService.markConversationRead(widget.conversationId);
      if (!mounted) {
        return;
      }
      final DateTime? after = await ChatService.getMyLastReadInConversation(widget.conversationId);
      final Map<String, DateTime?> other =
          await ChatService.getOtherParticipantsLastReadMap(widget.conversationId);
      if (mounted) {
        setState(() {
          _myReadCursor = after ?? _myReadCursor;
          _otherReadByUser = other;
        });
      }
      await ChatUnreadBadge.refresh();
    });
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

  bool _canDeleteMessage(Map<String, dynamic> m, String? me) {
    if (me == null) {
      return false;
    }
    final String? sid = m['sender_id']?.toString();
    final bool deleted = m['deleted_at'] != null;
    if (deleted) {
      return false;
    }
    if (sid == me) {
      return true;
    }
    if (_isGroup == true) {
      return _myRole == 'owner' || _myRole == 'moderator';
    }
    return false;
  }

  Future<void> _deleteMessage(String messageId) async {
    try {
      await ChatService.softDeleteMessage(messageId);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось удалить')),
        );
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
    final bool isGroup = _isGroup == true;

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
          _headerTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: <Widget>[
          if (isGroup)
            IconButton(
              icon: const Icon(Icons.group_outlined, color: kPrimaryBlue),
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (BuildContext c) => GroupChatInfoScreen(
                      conversationId: widget.conversationId,
                      title: _headerTitle,
                      isOpen: _isOpen ?? false,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: _MessagesList(
              conversationId: widget.conversationId,
              me: me,
              timeLabel: _timeLabel,
              canDeleteMessage: _canDeleteMessage,
              onDelete: _deleteMessage,
              myReadAt: _myReadCursor,
              otherReadByUser: _otherReadByUser,
              onStreamChanged: _scheduleReadSync,
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
                      hintText: isGroup ? 'Сообщение в группе…' : 'Сообщение…',
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

class _MessagesList extends StatefulWidget {
  const _MessagesList({
    required this.conversationId,
    required this.me,
    required this.timeLabel,
    required this.canDeleteMessage,
    required this.onDelete,
    required this.myReadAt,
    required this.otherReadByUser,
    required this.onStreamChanged,
  });

  final String conversationId;
  final String? me;
  final String Function(String? iso) timeLabel;
  final bool Function(Map<String, dynamic> m, String? me) canDeleteMessage;
  final void Function(String messageId) onDelete;
  final DateTime? myReadAt;
  final Map<String, DateTime?> otherReadByUser;
  final VoidCallback onStreamChanged;

  @override
  State<_MessagesList> createState() => _MessagesListState();
}

class _MessagesListState extends State<_MessagesList> {
  String? _dataSig;

  @override
  Widget build(BuildContext context) {
    if (widget.me == null) {
      return const Center(child: Text('Нет сессии'));
    }
    final String me = widget.me!;
    final Stream<List<Map<String, dynamic>>>? stream = ChatService.watchMessages(widget.conversationId);
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
        final List<Map<String, dynamic>> raw = s.data ?? <Map<String, dynamic>>[];
        final List<Map<String, dynamic>> rows = ChatService.dedupeChatMessagesById(raw);
        final String sig = rows.isEmpty
            ? '0'
            : '${rows.length}:${rows.last['id']}:${rows.first['id']}';
        if (sig != _dataSig) {
          _dataSig = sig;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onStreamChanged();
          });
        }
        if (rows.isEmpty) {
          return const Center(
            child: Text(
              'Пока нет сообщений',
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
            final bool isDeleted = m['deleted_at'] != null;
            final String text = isDeleted
                ? 'Сообщение удалено'
                : (m['body'] as String?) ?? '';
            final DateTime? createdAt = _tryParse(m['created_at'] as String?);
            final bool incomingUnread = !mine &&
                !isDeleted &&
                createdAt != null &&
                widget.myReadAt != null &&
                createdAt.isAfter(widget.myReadAt!);
            final bool myReadByPeer = mine && !isDeleted && createdAt != null
                ? _peersReadMessage(widget.otherReadByUser, createdAt)
                : false;
            return Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: GestureDetector(
                onLongPress: widget.canDeleteMessage(m, me)
                    ? () {
                        showModalBottomSheet<void>(
                          context: context,
                          builder: (BuildContext bc) {
                            return SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  ListTile(
                                    leading: const Icon(Icons.delete_outline, color: Color(0xFFC62828)),
                                    title: const Text('Удалить сообщение'),
                                    onTap: () {
                                      Navigator.pop(bc);
                                      widget.onDelete(m['id']!.toString());
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      }
                    : null,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.82,
                  ),
                  decoration: BoxDecoration(
                    color: isDeleted
                        ? const Color(0xFFE8E8ED)
                        : (mine
                            ? kPrimaryBlue
                            : (incomingUnread ? const Color(0xFFF0F7FF) : Colors.white)),
                    border: incomingUnread
                        ? const Border(
                            left: BorderSide(
                              color: kPrimaryBlue,
                              width: 3,
                            ),
                          )
                        : null,
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
                          color: isDeleted
                              ? const Color(0xFF6B6B70)
                              : (mine ? Colors.white : const Color(0xFF1A1C1C)),
                          fontSize: 15,
                          fontWeight: incomingUnread ? FontWeight.w600 : null,
                          fontStyle: isDeleted ? FontStyle.italic : null,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          if (mine && !isDeleted) ...<Widget>[
                            Icon(
                              myReadByPeer ? Icons.done_all : Icons.done,
                              size: 15,
                              color: myReadByPeer
                                  ? const Color(0xFFB3E0FF)
                                  : Colors.white.withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            widget.timeLabel(m['created_at'] as String?),
                            style: TextStyle(
                              color: mine
                                  ? Colors.white.withValues(alpha: 0.75)
                                  : const Color(0xFF8A8A8E),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

DateTime? _tryParse(String? iso) {
  if (iso == null || iso.isEmpty) {
    return null;
  }
  return DateTime.tryParse(iso);
}

/// Хотя бы один собеседник «дочитал» до [msgAt].
bool _peersReadMessage(Map<String, DateTime?> otherReadByUser, DateTime msgAt) {
  if (otherReadByUser.isEmpty) {
    return false;
  }
  for (final DateTime? t in otherReadByUser.values) {
    if (t != null && !t.isBefore(msgAt)) {
      return true;
    }
  }
  return false;
}
