import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_constants.dart';
import '../config/supabase_ready.dart';
import '../models/conversation_list_item.dart';
import '../services/chat_service.dart';
import '../utils/phone_normalize.dart';
import 'user_chat_thread_screen.dart';

/// Список чатов, поиск, кнопка «новый чат» (контакты на телефоне или email).
class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  final TextEditingController _search = TextEditingController();
  String _q = '';
  bool _loading = true;
  List<ConversationListItem> _all = <ConversationListItem>[];

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChange);
    _load();
  }

  void _onSearchChange() {
    setState(() => _q = _search.text.trim().toLowerCase());
  }

  @override
  void dispose() {
    _search.removeListener(_onSearchChange);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!supabaseAppReady) {
      setState(() {
        _loading = false;
        _all = <ConversationListItem>[];
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final List<ConversationListItem> r = await ChatService.listConversations();
      if (mounted) {
        setState(() => _all = r);
      }
    } on Object {
      if (mounted) {
        setState(() => _all = <ConversationListItem>[]);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<ConversationListItem> get _filtered {
    if (_q.isEmpty) {
      return _all;
    }
    return _all
        .where(
          (ConversationListItem c) =>
              c.title.toLowerCase().contains(_q) || c.subtitle.toLowerCase().contains(_q),
        )
        .toList();
  }

  static bool get _isMobile {
    if (kIsWeb) {
      return false;
    }
    return Platform.isAndroid || Platform.isIOS;
  }

  Future<void> _openAddChat() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext c) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Center(
                  child: Text(
                    'Новый чат',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_isMobile)
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(c).pop();
                      _openContacts();
                    },
                    icon: const Icon(Icons.contacts_outlined),
                    label: const Text('Выбрать из контактов'),
                  ),
                if (_isMobile) const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(c).pop();
                    _openAddByEmail();
                  },
                  icon: const Icon(Icons.alternate_email_outlined),
                  label: const Text('Найти по email'),
                ),
                if (!_isMobile)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'С телефона: откроется список контактов. В веб-версии — только по email.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF6B6B70)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAddByEmail() async {
    final TextEditingController email = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Email в приложении'),
        content: TextField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Почта пользователя',
            hintText: 'friend@mail.ru',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Найти'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      return;
    }
    final String em = email.text.trim();
    if (em.isEmpty || !em.contains('@')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Введите корректный email')),
        );
      }
      return;
    }
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) {
      return;
    }
    final String? other = await ChatService.findUserIdByEmail(em);
    if (other == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Пользователь с таким email не найден в приложении'),
          ),
        );
      }
      return;
    }
    if (other == me) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Это ваш адрес — выберите другого')),
        );
      }
      return;
    }
    try {
      final String conv = await ChatService.getOrCreateDirectConversation(other);
      final String name = (await ChatService.displayNameForUserId(other)) ?? 'Чат';
      if (!mounted) {
        return;
      }
      await _load();
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext c) => UserChatThreadScreen(
            conversationId: conv,
            title: name,
          ),
        ),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть чат')),
        );
      }
    }
  }

  Future<void> _openContacts() async {
    if (!_isMobile) {
      return;
    }
    final bool granted = await FlutterContacts.requestPermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Нужен доступ к контактам (настройки приложения)'),
          ),
        );
      }
      return;
    }
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => const _ContactPickerPage(),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!supabaseAppReady) {
      return const Scaffold(
        body: Center(child: Text('Supabase не настроен')),
      );
    }
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 16,
        title: const Text(
          'Чаты',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: false,
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Поиск по чатам',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF8E8E93)),
                filled: true,
                fillColor: const Color(0xFFF2F2F7),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _filtered.isEmpty
                        ? ListView(
                            children: <Widget>[
                              const SizedBox(height: 64),
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 56,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Center(
                                child: Text(
                                  _all.isEmpty
                                      ? 'Нет чатов. Нажмите +, чтобы написать кому-то'
                                      : 'Ничего не найдено',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Color(0xFF6B6B70),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            itemCount: _filtered.length,
                            padding: const EdgeInsets.only(top: 4, bottom: 80),
                            separatorBuilder: (BuildContext c, int i) => const Padding(
                              padding: EdgeInsets.only(left: 80),
                              child: Divider(
                                height: 1,
                                thickness: 1,
                                color: Color(0xFFE8E8ED),
                              ),
                            ),
                            itemBuilder: (BuildContext c, int i) {
                              final ConversationListItem item = _filtered[i];
                              return _ChatListTile(
                                item: item,
                                onTap: () {
                                  Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (BuildContext c) => UserChatThreadScreen(
                                        conversationId: item.id,
                                        title: item.title,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddChat,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ChatListTile extends StatelessWidget {
  const _ChatListTile({required this.item, required this.onTap});

  final ConversationListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                backgroundColor: kPrimaryBlue.withValues(alpha: 0.2),
                child: Text(
                  item.title.isNotEmpty
                      ? item.title[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: kPrimaryBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                        ),
                        if (item.timeText.isNotEmpty)
                          Text(
                            item.timeText,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF8A8A8E),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B6B70),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactPickerPage extends StatefulWidget {
  const _ContactPickerPage();

  @override
  State<_ContactPickerPage> createState() => _ContactPickerPageState();
}

class _ContactPickerPageState extends State<_ContactPickerPage> {
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
    return '${c.displayName} ${c.phones.map((Phone p) => p.number).join(' ')}'.toLowerCase();
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
                        leading: const CircleAvatar(
                          child: Icon(Icons.person),
                        ),
                        title: Text(cont.displayName),
                        subtitle: Text(
                          cont.phones.isEmpty
                              ? 'Нет номера'
                              : cont.phones.map((Phone p) => p.number).join(', '),
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
          const SnackBar(content: Text('Не удалось разобрать номер. Укажите +7 в профиле у друга.')),
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
              'Пользователь с таким номером не в приложении. Пусть добавит тот же номер в «Профиль».',
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
    try {
      final String conv = await ChatService.getOrCreateDirectConversation(other);
      final String name = (await ChatService.displayNameForUserId(other)) ?? c.displayName;
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      if (!context.mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext c) => UserChatThreadScreen(
            conversationId: conv,
            title: name,
          ),
        ),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть чат')),
        );
      }
    }
  }
}
