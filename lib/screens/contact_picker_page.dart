import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class _ContactPickerPageState extends State<ContactPickerPage> {
  bool _loading = true;
  List<Contact> _contacts = <Contact>[];
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
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

  String _searchText(Contact c) {
    return '${c.displayName} ${c.phones.map((Phone p) => p.number).join(' ')}'
        .toLowerCase();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
        title: const Text('Контакты'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(12),
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
      ),
    );
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
    if (widget.returnUserIdOnly) {
      if (mounted) {
        Navigator.of(context).pop<String>(other);
      }
      return;
    }
    try {
      final String conv = await ChatService.getOrCreateDirectConversation(
        other,
      );
      final String name =
          (await ChatService.displayNameForUserId(other)) ?? c.displayName;
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
}
