import 'dart:io' show Platform;

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_constants.dart';
import '../config/supabase_ready.dart';
import '../main_tab_index.dart';
import '../widgets/soft_tab_header.dart';
import '../widgets/weather_app_bar_action.dart';
import '../models/conversation_list_item.dart';
import '../services/chat_service.dart';
import '../services/chat_unread_badge.dart';
import '../services/notification_prefs.dart';
import 'contact_picker_page.dart';
import 'create_group_screen.dart';
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
  bool _loading = false;

  /// Чаты грузим только при первом открытии вкладки «Чаты» (не на старте приложения).
  bool _autoLoadScheduled = false;
  List<ConversationListItem> _all = <ConversationListItem>[];
  Set<String> _mutedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!supabaseAppReady || _autoLoadScheduled) {
      return;
    }
    if (MainTabIndex.maybeOf(context) != 3) {
      return;
    }
    _autoLoadScheduled = true;
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
        _mutedIds = <String>{};
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final List<ConversationListItem> r =
          await ChatService.listConversations();
      final Set<String> muted = await NotificationPrefs.allMutedConversationIds();
      if (mounted) {
        setState(() {
          _all = r;
          _mutedIds = muted;
        });
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() => _all = <ConversationListItem>[]);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.message.isNotEmpty ? e.message : 'Не удалось загрузить чаты',
            ),
          ),
        );
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

  Future<void> _onChatLongPress(ConversationListItem item) async {
    final bool muted = await NotificationPrefs.isConversationMuted(item.id);
    if (!mounted) {
      return;
    }
    final bool isOwner = item.myRole == 'owner';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext c) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              ListTile(
                leading: Icon(
                  muted
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  color: kPrimaryBlue,
                ),
                title: Text(
                  muted ? 'Включить уведомления' : 'Отключить уведомления',
                ),
                onTap: () async {
                  await NotificationPrefs.setConversationMuted(item.id, !muted);
                  if (mounted) {
                    setState(() {
                      if (!muted) {
                        _mutedIds.add(item.id);
                      } else {
                        _mutedIds.remove(item.id);
                      }
                    });
                  }
                  if (c.mounted) {
                    Navigator.of(c).pop();
                  }
                  if (!mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        muted
                            ? 'Уведомления для этого чата снова включены'
                            : 'Уведомления для этого чата отключены',
                      ),
                    ),
                  );
                },
              ),
              if (item.isGroup)
                ListTile(
                  leading: const Icon(Icons.exit_to_app, color: kPrimaryBlue),
                  title: const Text('Покинуть чат'),
                  onTap: () async {
                    final bool? ok = await showDialog<bool>(
                      context: c,
                      builder: (BuildContext c2) => AlertDialog(
                        title: const Text('Покинуть чат?'),
                        content: const Text(
                          'Вы больше не будете видеть эту переписку в списке.',
                        ),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () => Navigator.of(c2).pop(false),
                            child: const Text('Отмена'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(c2).pop(true),
                            child: const Text('Покинуть'),
                          ),
                        ],
                      ),
                    );
                    if (c.mounted) {
                      Navigator.of(c).pop();
                    }
                    if (ok == true) {
                      try {
                        await ChatService.leaveGroupConversation(item.id);
                        if (!mounted) {
                          return;
                        }
                        await _load();
                        if (!mounted) {
                          return;
                        }
                        await ChatUnreadBadge.refresh();
                        if (!mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Вы вышли из чата')),
                        );
                      } on Object catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Не выйти из чата: $e')),
                          );
                        }
                      }
                    }
                  },
                ),
              if (!item.isGroup)
                ListTile(
                  leading: const Icon(
                    Icons.delete_sweep_outlined,
                    color: kPrimaryBlue,
                  ),
                  title: const Text('Очистить историю'),
                  onTap: () async {
                    final bool? ok = await showDialog<bool>(
                      context: c,
                      builder: (BuildContext c2) => AlertDialog(
                        title: const Text('Очистить историю?'),
                        content: const Text(
                          'Все сообщения в этом чате будут удалены. Собеседник сможет писать снова; сам чат в списке останется.',
                        ),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () => Navigator.of(c2).pop(false),
                            child: const Text('Отмена'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(c2).pop(true),
                            child: const Text('Очистить'),
                          ),
                        ],
                      ),
                    );
                    if (c.mounted) {
                      Navigator.of(c).pop();
                    }
                    if (ok == true) {
                      try {
                        await ChatService.clearConversationHistory(item.id);
                        if (!mounted) {
                          return;
                        }
                        await _load();
                        if (!mounted) {
                          return;
                        }
                        await ChatUnreadBadge.refresh();
                        if (!mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('История очищена')),
                        );
                      } on Object catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
                        }
                      }
                    }
                  },
                ),
              if (!item.isGroup || isOwner)
                ListTile(
                  leading: const Icon(
                    Icons.delete_forever,
                    color: Color(0xFFE53935),
                  ),
                  title: const Text('Удалить чат'),
                  onTap: () async {
                    final String extra = item.isGroup
                        ? 'Группу и все сообщения нельзя будет восстановить для всех.'
                        : 'Переписка удалится у вас и у собеседника, сообщения сотрутся.';
                    final bool? ok = await showDialog<bool>(
                      context: c,
                      builder: (BuildContext c2) => AlertDialog(
                        title: const Text('Удалить чат?'),
                        content: Text(extra),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () => Navigator.of(c2).pop(false),
                            child: const Text('Отмена'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFE53935),
                            ),
                            onPressed: () => Navigator.of(c2).pop(true),
                            child: const Text('Удалить'),
                          ),
                        ],
                      ),
                    );
                    if (c.mounted) {
                      Navigator.of(c).pop();
                    }
                    if (ok == true) {
                      try {
                        await ChatService.deleteConversationCompletely(item.id);
                        if (!mounted) {
                          return;
                        }
                        await _load();
                        if (!mounted) {
                          return;
                        }
                        await ChatUnreadBadge.refresh();
                        if (!mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Чат удалён')),
                        );
                      } on Object catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                item.isGroup
                                    ? 'Только владелец группы может удалить её целиком: $e'
                                    : 'Ошибка: $e',
                              ),
                            ),
                          );
                        }
                      }
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  List<ConversationListItem> get _filtered {
    if (_q.isEmpty) {
      return _all;
    }
    return _all
        .where(
          (ConversationListItem c) =>
              c.title.toLowerCase().contains(_q) ||
              c.subtitle.toLowerCase().contains(_q),
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
                Center(
                  child: Text(
                    'Новый чат',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(c).colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(c).pop();
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (BuildContext c2) => const CreateGroupScreen(),
                      ),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(c).colorScheme.secondaryContainer,
                    foregroundColor: Theme.of(
                      c,
                    ).colorScheme.onSecondaryContainer,
                  ),
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Создать группу'),
                ),
                const SizedBox(height: 8),
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
                    _openNicknameSearch();
                  },
                  icon: const Icon(Icons.alternate_email_outlined),
                  label: const Text('Найти по нику (@)'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(c).pop();
                    _openAddByEmail();
                  },
                  icon: const Icon(Icons.mail_outline),
                  label: const Text('Найти по email'),
                ),
                if (!_isMobile)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'С телефона: контакты или ник. В веб-версии — по нику или email.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(c).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openNicknameSearch() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext c) =>
            const ContactPickerPage(initialNickMode: true),
      ),
    );
    await _load();
    await ChatUnreadBadge.refresh();
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
      final String conv = await ChatService.getOrCreateDirectConversation(
        other,
      );
      final String name =
          (await ChatService.displayNameForUserId(other)) ?? 'Чат';
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
            listItem: null,
          ),
        ),
      );
      if (mounted) {
        await _load();
        await ChatUnreadBadge.refresh();
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Не удалось открыть чат')));
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
        builder: (BuildContext c) => const ContactPickerPage(),
      ),
    );
    await _load();
    await ChatUnreadBadge.refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!supabaseAppReady) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SoftTabHeader(
              title: 'Чаты',
              trailing: SoftHeaderWeatherWithAction(
                action: Icon(
                  Icons.chat_outlined,
                  color: softHeaderTrailingIconColor(context),
                  size: 26,
                ),
              ),
            ),
            const Expanded(
              child: Center(child: Text('Supabase не настроен')),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SoftTabHeader(
            title: 'Чаты',
            trailing: SoftHeaderWeatherWithAction(
              action: IconButton(
                icon: Icon(
                  Icons.add_circle_outline,
                  color: softHeaderTrailingIconColor(context),
                  size: 28,
                ),
                onPressed: _openAddChat,
                tooltip: 'Новый чат',
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Поиск по чатам',
                      hintStyle: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      filled: true,
                      fillColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 4,
                      ),
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
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                          .withValues(alpha: 0.5),
                                    ),
                                    const SizedBox(height: 16),
                                    Center(
                                      child: Text(
                                        _all.isEmpty
                                            ? 'Нет чатов. Нажмите «+» сверху, чтобы написать кому-то'
                                            : 'Ничего не найдено',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : ListView.separated(
                                  itemCount: _filtered.length,
                                  padding:
                                      const EdgeInsets.only(top: 4, bottom: 80),
                                  separatorBuilder: (BuildContext c, int i) =>
                                      Padding(
                                        padding: const EdgeInsets.only(left: 80),
                                        child: Divider(
                                          height: 1,
                                          thickness: 1,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outlineVariant
                                              .withValues(alpha: 0.5),
                                        ),
                                      ),
                                  itemBuilder: (BuildContext c, int i) {
                                    final ConversationListItem item =
                                        _filtered[i];
                                    return _ChatListTile(
                                      item: item,
                                      notificationsMuted:
                                          _mutedIds.contains(item.id),
                                      onLongPress: () {
                                        unawaited(_onChatLongPress(item));
                                      },
                                      onTap: () async {
                                        await Navigator.of(context).push<void>(
                                          MaterialPageRoute<void>(
                                            builder: (BuildContext c) =>
                                                UserChatThreadScreen(
                                              conversationId: item.id,
                                              title: item.title,
                                              listItem: item,
                                            ),
                                          ),
                                        );
                                        if (!mounted) {
                                          return;
                                        }
                                        await _load();
                                        await ChatUnreadBadge.refresh();
                                      },
                                    );
                                  },
                                ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatListTile extends StatelessWidget {
  const _ChatListTile({
    required this.item,
    required this.notificationsMuted,
    required this.onTap,
    required this.onLongPress,
  });

  final ConversationListItem item;
  final bool notificationsMuted;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                backgroundColor: kPrimaryBlue.withValues(alpha: 0.2),
                child: item.isGroup
                    ? const Icon(Icons.group, color: kPrimaryBlue, size: 22)
                    : Text(
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
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: item.hasUnread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        if (item.hasUnread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: const BoxDecoration(
                              color: Color(0xFFE53935),
                              shape: BoxShape.circle,
                            ),
                          ),
                        if (notificationsMuted) ...<Widget>[
                          Icon(
                            Icons.notifications_off_outlined,
                            size: 20,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (item.timeText.isNotEmpty)
                          Text(
                            item.timeText,
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurfaceVariant,
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
