import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_ready.dart';
import '../services/chat_service.dart';
import 'add_group_member_screen.dart';

class GroupChatInfoScreen extends StatefulWidget {
  const GroupChatInfoScreen({
    super.key,
    required this.conversationId,
    required this.title,
    required this.isOpen,
  });

  final String conversationId;
  final String title;
  final bool isOpen;

  @override
  State<GroupChatInfoScreen> createState() => _GroupChatInfoScreenState();
}

class _GroupChatInfoScreenState extends State<GroupChatInfoScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  String? _myRole;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (!supabaseAppReady) {
      return;
    }
    setState(() => _loading = true);
    _myRole = await ChatService.getMyRoleInConversation(widget.conversationId);
    _rows = await ChatService.fetchParticipantsWithProfiles(
      widget.conversationId,
    );
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  bool get _isOwner => _myRole == 'owner';

  String _line(Map<String, dynamic> m) {
    final String fn = (m['first_name'] as String?)?.trim() ?? '';
    final String ln = (m['last_name'] as String?)?.trim() ?? '';
    final String u = (m['username'] as String?)?.trim() ?? '';
    final String name = ('$fn $ln').trim();
    if (name.isNotEmpty) {
      return u.isNotEmpty ? '$name (@$u)' : name;
    }
    return u.isNotEmpty ? '@$u' : (m['user_id'] as String? ?? '');
  }

  Future<void> _remove(String userId, String role) async {
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) {
      return;
    }
    if (userId == me) {
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext c) => AlertDialog(
          title: const Text('Выйти из группы?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Нет'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Да'),
            ),
          ],
        ),
      );
      if (ok == true) {
        try {
          await ChatService.removeGroupParticipant(widget.conversationId, me);
          if (mounted) {
            Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
          }
        } on Object {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Не удалось выйти')));
          }
        }
      }
      return;
    }
    if (role == 'owner') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Создателя нельзя исключить')),
        );
      }
      return;
    }
    if (_myRole == 'moderator' && (role == 'owner' || role == 'moderator')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Модератор не может это сделать')),
        );
      }
      return;
    }
    final bool? ok2 = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Исключить из группы?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Да'),
          ),
        ],
      ),
    );
    if (ok2 == true) {
      try {
        await ChatService.removeGroupParticipant(widget.conversationId, userId);
        await _reload();
      } on Object {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Ошибка')));
        }
      }
    }
  }

  Future<void> _toggleMod(String userId, bool toMod) async {
    try {
      await ChatService.setGroupModerator(
        widget.conversationId,
        userId,
        isModerator: toMod,
      );
      await _reload();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Не удалось')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Участники'),
        actions: <Widget>[
          if (!_loading)
            IconButton(
              onPressed: () async {
                final bool? changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (BuildContext c) => AddGroupMemberScreen(
                      conversationId: widget.conversationId,
                      isOpen: widget.isOpen,
                      myRole: _myRole,
                    ),
                  ),
                );
                if (changed == true) {
                  await _reload();
                }
              },
              icon: const Icon(Icons.person_add_outlined),
              tooltip: 'Добавить',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: <Widget>[
                ListTile(
                  title: Text(widget.title),
                  subtitle: Text(
                    widget.isOpen
                        ? 'Открытая группа'
                        : 'Закрытая группа (приглашения)',
                  ),
                ),
                const Divider(),
                ..._rows.map((Map<String, dynamic> m) {
                  final String uid = m['user_id'] as String? ?? '';
                  final String role = (m['role'] as String?) ?? 'member';
                  final String? me =
                      Supabase.instance.client.auth.currentUser?.id;
                  return ListTile(
                    title: Text(_line(m)),
                    subtitle: Text(
                      role == 'owner'
                          ? 'Создатель'
                          : (role == 'moderator' ? 'Модератор' : 'Участник'),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (_isOwner && role != 'owner') ...<Widget>[
                          TextButton(
                            onPressed: () =>
                                _toggleMod(uid, role != 'moderator'),
                            child: Text(
                              role == 'moderator' ? 'Снять' : 'Модератор',
                            ),
                          ),
                        ],
                        if (uid != me &&
                            role != 'owner' &&
                            (_isOwner ||
                                (_myRole == 'moderator' && role == 'member')))
                          IconButton(
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: Color(0xFFC62828),
                            ),
                            onPressed: () => _remove(uid, role),
                            tooltip: 'Исключить',
                          ),
                        if (uid == me)
                          TextButton(
                            onPressed: () => _remove(uid, role),
                            child: const Text('Выйти'),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
