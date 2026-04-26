import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_constants.dart';
import '../services/chat_service.dart';
import '../utils/phone_normalize.dart';
import 'user_chat_thread_screen.dart';

/// [returnUserIdOnly] — вернуть id через `Navigator.pop(id)` для добавления в группу;
/// иначе открыть/создать личный чат.
class ContactPickerPage extends StatefulWidget {
  const ContactPickerPage({super.key, this.returnUserIdOnly = false});

  final bool returnUserIdOnly;

  @override
  State<ContactPickerPage> createState() => _ContactPickerPageState();
}

enum _PickerMode { contacts, byUsername }

class _ContactPickerPageState extends State<ContactPickerPage> {
  bool _loading = true;
  List<Contact> _contacts = <Contact>[];
  final TextEditingController _search = TextEditingController();

  _PickerMode _mode = _PickerMode.contacts;
  final TextEditingController _nickSearch = TextEditingController();
  Timer? _nickDebounce;
  bool _nickLoading = false;
  List<Map<String, dynamic>> _nickResults = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _nickSearch.addListener(_onNickQueryChanged);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );
    } on Object {
      _contacts = <Contact>[];
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  static String _nickQueryForApi(String raw) {
    String s = raw.trim();
    while (s.startsWith('@')) {
      s = s.substring(1).trim();
    }
    return s;
  }

  void _onNickQueryChanged() {
    final String q = _nickQueryForApi(_nickSearch.text);
    if (q.isEmpty) {
      _nickDebounce?.cancel();
      if (mounted) {
        setState(() {
          _nickResults = <Map<String, dynamic>>[];
          _nickLoading = false;
        });
      }
      return;
    }
    _nickDebounce?.cancel();
    _nickDebounce = Timer(const Duration(milliseconds: 400), _runNickSearch);
  }

  Future<void> _runNickSearch() async {
    final String q = _nickQueryForApi(_nickSearch.text);
    if (q.isEmpty) {
      return;
    }
    if (mounted) {
      setState(() => _nickLoading = true);
    }
    final List<Map<String, dynamic>> r =
        await ChatService.searchProfilesForChat(q);
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    if (mounted) {
      setState(() {
        _nickLoading = false;
        _nickResults = r
            .where((Map<String, dynamic> m) => m['id']?.toString() != me)
            .toList();
      });
    }
  }

  String _displayNameFromProfile(Map<String, dynamic> m) {
    final String fn = (m['first_name'] as String?)?.trim() ?? '';
    final String ln = (m['last_name'] as String?)?.trim() ?? '';
    final String t = ('$fn $ln').trim();
    return t.isNotEmpty ? t : 'Пользователь';
  }

  String _atUsername(Map<String, dynamic> m) {
    final String u = (m['username'] as String?)?.trim() ?? '';
    return u.isEmpty ? '—' : '@$u';
  }

  String _searchText(Contact c) {
    return '${c.displayName} ${c.phones.map((Phone p) => p.number).join(' ')}'
        .toLowerCase();
  }

  @override
  void dispose() {
    _nickDebounce?.cancel();
    _nickSearch.removeListener(_onNickQueryChanged);
    _nickSearch.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _openDirectChatWithUserId(
    String otherUserId, {
    required String titleFallback,
  }) async {
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    if (otherUserId == me) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нельзя написать самому себе')),
        );
      }
      return;
    }
    if (widget.returnUserIdOnly) {
      if (mounted) {
        Navigator.of(context).pop<String>(otherUserId);
      }
      return;
    }
    try {
      final String conv =
          await ChatService.getOrCreateDirectConversation(otherUserId);
      final String name =
          (await ChatService.displayNameForUserId(otherUserId)) ??
              titleFallback;
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      if (!context.mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext c) =>
              UserChatThreadScreen(conversationId: conv, title: name),
        ),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Не удалось открыть чат')));
      }
    }
  }

  Future<void> _onPickProfileRow(Map<String, dynamic> m) async {
    final String id = m['id']?.toString() ?? '';
    if (id.isEmpty) {
      return;
    }
    final String nick = _atUsername(m);
    final String title =
        nick != '—' ? nick : _displayNameFromProfile(m);
    await _openDirectChatWithUserId(id, titleFallback: title);
  }

  Future<void> _onPick(Contact c) async {
    if (c.phones.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('У контакта нет телефона')),
        );
      }
      return;
    }
    String? e164;
    for (final Phone p in c.phones) {
      e164 = normalizePhoneToE164Ru(p.number);
      if (e164 != null) {
        break;
      }
    }
    if (e164 == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось разобрать номер.')),
        );
      }
      return;
    }
    final String? other = await ChatService.findUserIdByPhoneE164(e164);
    if (other == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Пользователь с таким номером не в приложении. Добавьте номер в «Профиль».',
            ),
          ),
        );
      }
      return;
    }
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    if (other == me) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Это ваш номер в профиле')),
        );
      }
      return;
    }
    await _openDirectChatWithUserId(other, titleFallback: c.displayName);
  }

  @override
  Widget build(BuildContext context) {
    final String lq = _search.text.toLowerCase();
    final List<Contact> list = _loading
        ? <Contact>[]
        : _contacts
              .where((Contact c) => lq.isEmpty || _searchText(c).contains(lq))
              .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Новый чат'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SegmentedButton<_PickerMode>(
              segments: const <ButtonSegment<_PickerMode>>[
                ButtonSegment<_PickerMode>(
                  value: _PickerMode.contacts,
                  label: Text('Контакты'),
                  icon: Icon(Icons.perm_contact_calendar_outlined, size: 18),
                ),
                ButtonSegment<_PickerMode>(
                  value: _PickerMode.byUsername,
                  label: Text('По нику'),
                  icon: Icon(Icons.alternate_email, size: 18),
                ),
              ],
              selected: <_PickerMode>{_mode},
              onSelectionChanged: (Set<_PickerMode> next) {
                setState(() => _mode = next.first);
              },
            ),
          ),
          Expanded(
            child: _mode == _PickerMode.contacts
                ? _buildContactsTab(list)
                : _buildNickTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildContactsTab(List<Contact> list) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Поиск в контактах',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (BuildContext c, int i) {
                    final Contact cont = list[i];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(cont.displayName),
                      subtitle: Text(
                        cont.phones.isEmpty
                            ? 'Нет номера'
                            : cont.phones
                                  .map((Phone p) => p.number)
                                  .join(', '),
                      ),
                      onTap: () => _onPick(cont),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildNickTab() {
    final String apiQ = _nickQueryForApi(_nickSearch.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: TextField(
            controller: _nickSearch,
            textInputAction: TextInputAction.search,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: 'Поиск по нику (@nickname или без @)',
              prefixIcon: Icon(Icons.alternate_email),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              isDense: true,
            ),
          ),
        ),
        if (_nickLoading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: apiQ.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Введите ник, как в профиле (с @ или без). '
                      'Он совпадает с полем «Ник в чате».',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: Color(0xFF6C6C70),
                        height: 1.35,
                      ),
                    ),
                  ),
                )
              : _nickResults.isEmpty && !_nickLoading
              ? const Center(
                  child: Text(
                    'Никого не найдено',
                    style: TextStyle(fontSize: 16, color: Color(0xFF6C6C70)),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _nickResults.length,
                  separatorBuilder: (_, int _) => const Divider(height: 1),
                  itemBuilder: (BuildContext c, int i) {
                    final Map<String, dynamic> m = _nickResults[i];
                    final String name = _displayNameFromProfile(m);
                    final String at = _atUsername(m);
                    final String initialSrc =
                        name != 'Пользователь' ? name : (at != '—' ? at : '?');
                    final String initial = initialSrc.isEmpty
                        ? '?'
                        : initialSrc[0].toUpperCase();
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: kPrimaryBlue.withValues(alpha: 0.15),
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: kPrimaryBlue,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        at,
                        style: TextStyle(
                          color: at == '—'
                              ? const Color(0xFF6C6C70)
                              : kPrimaryBlue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onTap: () => _onPickProfileRow(m),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
