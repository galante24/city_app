import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_constants.dart';
import '../services/chat_service.dart';
import 'contact_picker_page.dart';

/// Поиск по имени/фамилии, контакты, пользователи из личек — добавление в группу.
class AddGroupMemberScreen extends StatefulWidget {
  const AddGroupMemberScreen({
    super.key,
    required this.conversationId,
    required this.isOpen,
    this.myRole,
  });

  final String conversationId;
  final bool isOpen;
  final String? myRole;

  @override
  State<AddGroupMemberScreen> createState() => _AddGroupMemberScreenState();
}

class _AddGroupMemberScreenState extends State<AddGroupMemberScreen> {
  final TextEditingController _q = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  List<Map<String, dynamic>> _results = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _dmBuddies = <Map<String, dynamic>>[];
  bool _loadDm = true;

  bool get _canAdd {
    if (widget.isOpen) {
      return true;
    }
    final String? r = widget.myRole;
    return r == 'owner' || r == 'moderator';
  }

  static bool get _isMobile {
    if (kIsWeb) {
      return false;
    }
    return Platform.isAndroid || Platform.isIOS;
  }

  @override
  void initState() {
    super.initState();
    _loadDmBuddies();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _loadDmBuddies() async {
    final List<String> ids = await ChatService.listDirectPartnerUserIds();
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final String id in ids) {
      if (id == me) {
        continue;
      }
      final String? n = await ChatService.displayNameForUserId(id);
      out.add(<String, dynamic>{'id': id, 'name': n ?? id});
    }
    if (mounted) {
      setState(() {
        _dmBuddies = out;
        _loadDm = false;
      });
    }
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search());
  }

  Future<void> _search() async {
    final String t = _q.text.trim();
    if (t.isEmpty) {
      setState(() => _results = <Map<String, dynamic>>[]);
      return;
    }
    setState(() => _searching = true);
    final List<Map<String, dynamic>> r = await ChatService.searchProfilesForChat(t);
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    if (mounted) {
      setState(() {
        _searching = false;
        _results = r
            .where((Map<String, dynamic> m) => m['id']?.toString() != me)
            .toList();
      });
    }
  }

  Future<void> _add(String userId) async {
    if (!_canAdd) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('В закрытой группе приглашают модераторы и создатель')),
        );
      }
      return;
    }
    try {
      await ChatService.addGroupParticipant(widget.conversationId, userId);
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Участник добавлен')),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось добавить')),
        );
      }
    }
  }

  Future<void> _openContacts() async {
    final String? id = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (BuildContext c) => const ContactPickerPage(returnUserIdOnly: true),
      ),
    );
    if (id != null && mounted) {
      await _add(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canAdd) {
      return Scaffold(
        appBar: AppBar(title: const Text('Добавить')),
        body: const Center(
          child: Text('В этой закрытой группе только создатель и модераторы приглашают участников'),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Добавить в группу'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _q,
            onChanged: (_) {
              setState(() {});
              _onQueryChanged();
            },
            decoration: const InputDecoration(
              labelText: 'Поиск по имени, фамилии или @нику',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
          ),
          if (_searching) const LinearProgressIndicator(),
          if (_q.text.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            const Text('Результаты', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            ..._results.map(
              (Map<String, dynamic> m) {
                final String id = m['id']?.toString() ?? '';
                final String fn = (m['first_name'] as String?)?.trim() ?? '';
                final String ln = (m['last_name'] as String?)?.trim() ?? '';
                final String u = (m['username'] as String?)?.trim() ?? '';
                final String line = [fn, ln].where((e) => e.isNotEmpty).join(' ').trim();
                return ListTile(
                  title: Text(line.isNotEmpty ? line : (u.isNotEmpty ? '@$u' : '—')),
                  subtitle: u.isNotEmpty ? Text('@$u') : null,
                  trailing: IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                    ),
                    onPressed: () => _add(id),
                    icon: const Icon(Icons.person_add_outlined, color: kPrimaryBlue),
                  ),
                );
              },
            ),
          ],
          if (!_loadDm) ...<Widget>[
            const SizedBox(height: 20),
            const Text('Из личных чатов', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            if (_dmBuddies.isEmpty)
              const Text(
                'Пока нет собеседников в личке',
                style: TextStyle(color: Color(0xFF6B6B70)),
              )
            else
              ..._dmBuddies.map(
                (Map<String, dynamic> b) {
                  final String id = b['id'] as String? ?? '';
                  return ListTile(
                    title: Text(b['name'] as String? ?? ''),
                    trailing: IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                      ),
                      onPressed: () => _add(id),
                      icon: const Icon(Icons.person_add_outlined, color: kPrimaryBlue),
                    ),
                  );
                },
              ),
          ] else
            const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
          if (_isMobile) ...<Widget>[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _openContacts,
              icon: const Icon(Icons.contacts_outlined),
              label: const Text('Контакты телефона'),
            ),
          ],
        ],
      ),
    );
  }
}
