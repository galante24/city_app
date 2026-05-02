import 'dart:io' show Platform;
import 'dart:async' show Timer, TimeoutException, unawaited;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_card_styles.dart';
import '../app_constants.dart';
import '../config/supabase_ready.dart';
import '../main_tab_index.dart';
import '../widgets/city_network_image.dart';
import '../models/conversation_list_item.dart';
import '../services/chat_service.dart';
import '../services/chat_unread_badge.dart';
import '../services/notification_prefs.dart';
import 'contact_picker_page.dart';
import 'create_group_screen.dart';
import 'user_chat_thread_screen.dart';

/// Мягкая подсветка аватарки на тёмном экране чатов.
Widget _chatsDarkAvatarGlow(Widget child) {
  return Container(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: kPortalGold.withValues(alpha: 0.34),
          blurRadius: 16,
          spreadRadius: 0.45,
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.2),
          blurRadius: 9,
          spreadRadius: -3,
        ),
        BoxShadow(
          color: kPrimaryBlue.withValues(alpha: 0.16),
          blurRadius: 7,
          spreadRadius: -2,
        ),
      ],
    ),
    child: child,
  );
}

/// Изумрудное свечение аватарок только в светлом списке чатов.
Widget _chatsLightAvatarGlow(Widget child) {
  return Container(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: kEmeraldGlow.withValues(alpha: 0.38),
          blurRadius: 14,
          spreadRadius: 0.35,
        ),
        BoxShadow(
          color: kEmeraldGlow.withValues(alpha: 0.14),
          blurRadius: 22,
          spreadRadius: 1,
        ),
      ],
    ),
    child: child,
  );
}

/// Список чатов, поиск, кнопка «новый чат» (контакты на телефоне или ник).
class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  static const Duration _kListLoadTimeout = Duration(seconds: 10);

  final TextEditingController _search = TextEditingController();
  String _q = '';
  bool _loading = false;

  /// Чаты грузим только при первом открытии вкладки «Чаты» (не на старте приложения).
  bool _autoLoadScheduled = false;
  List<ConversationListItem> _all = <ConversationListItem>[];
  Set<String> _mutedIds = <String>{};
  bool _listLoadFailedOrTimeout = false;
  Timer? _waitSupabaseTimer;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryScheduleChatsLoad();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tryScheduleChatsLoad();
  }

  /// Вкладка «Чаты» + готовый Supabase; без дублирующих подписок на список.
  void _tryScheduleChatsLoad() {
    if (!mounted || _autoLoadScheduled) {
      return;
    }
    if (MainTabIndex.maybeOf(context) != 3) {
      return;
    }
    if (!supabaseAppReady) {
      _waitSupabaseTimer?.cancel();
      _waitSupabaseTimer = Timer(const Duration(milliseconds: 400), () {
        if (mounted) {
          _tryScheduleChatsLoad();
        }
      });
      return;
    }
    _waitSupabaseTimer?.cancel();
    _waitSupabaseTimer = null;
    _autoLoadScheduled = true;
    unawaited(_load());
  }

  void _onSearchChange() {
    setState(() => _q = _search.text.trim().toLowerCase());
  }

  @override
  void dispose() {
    _waitSupabaseTimer?.cancel();
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
        _listLoadFailedOrTimeout = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _listLoadFailedOrTimeout = false;
    });
    try {
      final List<ConversationListItem> r = await ChatService.listConversations()
          .timeout(_kListLoadTimeout);
      final Set<String> muted =
          await NotificationPrefs.allMutedConversationIds().timeout(
            _kListLoadTimeout,
            onTimeout: () => <String>{},
          );
      if (mounted) {
        setState(() {
          _all = r;
          _mutedIds = muted;
          _listLoadFailedOrTimeout = false;
        });
      }
    } on TimeoutException catch (_) {
      if (mounted) {
        setState(() {
          _all = <ConversationListItem>[];
          _mutedIds = <String>{};
          _listLoadFailedOrTimeout = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось загрузить чаты за 10 с. Проверьте сеть.'),
          ),
        );
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() {
          _all = <ConversationListItem>[];
          _listLoadFailedOrTimeout = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.message.isNotEmpty ? e.message : 'Не удалось загрузить чаты',
            ),
          ),
        );
      }
    } on Object catch (_) {
      if (mounted) {
        setState(() {
          _all = <ConversationListItem>[];
          _listLoadFailedOrTimeout = true;
        });
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
                if (!_isMobile)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'С телефона: контакты или ник. В веб-версии — по нику.',
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
    final TextEditingController nick = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Ник в приложении'),
        content: TextField(
          controller: nick,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.none,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Ник пользователя',
            hintText: '@username или username',
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
    final String raw = nick.text.trim();
    if (raw.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Введите ник')));
      }
      return;
    }
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) {
      return;
    }
    final String? other = await ChatService.findUserIdByUsername(raw);
    if (other == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Пользователь с таким ником не найден в приложении'),
          ),
        );
      }
      return;
    }
    if (other == me) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Это ваш ник — выберите другого')),
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
            directPeerUserId: other,
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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    if (!supabaseAppReady) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        body: isDark
            ? SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _chatsDarkTitleRow(context),
                      const Spacer(),
                      Text(
                        'Supabase не настроен',
                        style: GoogleFonts.montserrat(
                          fontSize: 15,
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _chatsLightTitleRow(context),
                      const Spacer(),
                      Text(
                        'Supabase не настроен',
                        style: GoogleFonts.montserrat(
                          fontSize: 15,
                          color: kPineGreen.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      );
    }
    if (isDark) {
      return _buildDarkPortalChats(context);
    }
    return _buildLightPortalChats(context);
  }

  Widget _chatsLightTitleRow(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Text(
          'Чаты',
          style: GoogleFonts.montserrat(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1.05,
            color: kPineGreen,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(bottom: 4),
          decoration: const BoxDecoration(
            color: kPrimaryBlue,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }

  /// Заголовок «Чаты» + синяя точка в стиле референса.
  Widget _chatsDarkTitleRow(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Text(
          'Чаты',
          style: GoogleFonts.montserrat(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1.05,
            color: Colors.white,
            shadows: const <Shadow>[
              Shadow(
                color: Color(0x59000000),
                offset: Offset(0, 1),
                blurRadius: 3,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(bottom: 4),
          decoration: const BoxDecoration(
            color: kPrimaryBlue,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }

  Scaffold _buildLightPortalChats(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: _chatsLightTitleRow(context),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _ChatsLightSearchBar(
                  controller: _search,
                  onAddPressed: _openAddChat,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints bc) {
                    final double panelH = _darkChatCloudHeight(
                      bc.maxHeight.clamp(0, 2000),
                    );
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: _lightGlassChatsPanel(
                          context,
                          panelHeight: panelH,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Высота «облака» диалогов: растёт с числом чатов (как в референсе), не более [maxExtent].
  double _darkChatCloudHeight(double maxExtent) {
    const double minCloud = 128;
    const double loadingH = 164;
    const double emptyH = 204;
    const double innerVertical = 22;
    const double tileExtent = 98;
    const double dividerPx = 1;
    final double cap = maxExtent * 0.92;
    if (_loading) {
      return loadingH.clamp(minCloud, cap);
    }
    if (_filtered.isEmpty) {
      return emptyH.clamp(minCloud, cap * 0.48);
    }
    final int n = _filtered.length;
    final double separators = n > 0 ? (n - 1) * dividerPx : 0;
    final double intrinsic = innerVertical + n * tileExtent + separators;
    return intrinsic.clamp(minCloud, cap);
  }

  Scaffold _buildDarkPortalChats(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: _chatsDarkTitleRow(context),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _ChatsGlassSearchBar(
                  controller: _search,
                  onAddPressed: _openAddChat,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints bc) {
                    final double panelH = _darkChatCloudHeight(
                      bc.maxHeight.clamp(0, 2000),
                    );
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: _darkGlassChatsPanel(
                          context,
                          panelHeight: panelH,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _darkGlassChatsPanel(
    BuildContext context, {
    required double panelHeight,
  }) {
    final BorderRadius radius = BorderRadius.circular(22);
    return SizedBox(
      width: double.infinity,
      height: panelHeight,
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF121820).withValues(alpha: 0.88),
            borderRadius: radius,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.095),
              width: 1,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.26),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: _loading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(color: kPortalGold),
                  ),
                )
              : RefreshIndicator(
                  color: kPortalGold,
                  backgroundColor: const Color(0xFF1A1F28),
                  displacement: 28,
                  onRefresh: _load,
                  child: _filtered.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: const EdgeInsets.fromLTRB(18, 32, 18, 24),
                          children: <Widget>[
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 44,
                              color: Colors.white.withValues(alpha: 0.32),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _listLoadFailedOrTimeout && _all.isEmpty
                                  ? 'Чаты не найдены'
                                  : _all.isEmpty
                                  ? 'Нет чатов. Нажмите «+» в строке поиска, чтобы написать кому-то'
                                  : 'Ничего не найдено',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.montserrat(
                                fontSize: 14,
                                height: 1.35,
                                color: Colors.white.withValues(alpha: 0.68),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          addAutomaticKeepAlives: true,
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
                          itemCount: _filtered.length,
                          separatorBuilder: (BuildContext c, int i) => Divider(
                            height: 1,
                            thickness: 1,
                            indent: 70,
                            endIndent: 12,
                            color: Colors.white.withValues(alpha: 0.065),
                          ),
                          itemBuilder: (BuildContext c, int i) {
                            final ConversationListItem item = _filtered[i];
                            return _ChatListTile(
                              item: item,
                              style: _ChatListTileStyle.darkGlass,
                              notificationsMuted: _mutedIds.contains(item.id),
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
      ),
    );
  }

  Widget _lightGlassChatsPanel(
    BuildContext context, {
    required double panelHeight,
  }) {
    final BorderRadius radius = BorderRadius.circular(22);
    return SizedBox(
      width: double.infinity,
      height: panelHeight,
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: radius,
            border: Border.all(
              color: kPineGreen.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: _loading
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: CircularProgressIndicator(
                      color: kEmeraldGlow,
                      strokeWidth: 2.5,
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: kEmeraldGlow,
                  backgroundColor: Colors.white,
                  displacement: 28,
                  onRefresh: _load,
                  child: _filtered.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: const EdgeInsets.fromLTRB(18, 32, 18, 24),
                          children: <Widget>[
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 44,
                              color: kNavOliveMuted.withValues(alpha: 0.65),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _listLoadFailedOrTimeout && _all.isEmpty
                                  ? 'Чаты не найдены'
                                  : _all.isEmpty
                                  ? 'Нет чатов. Нажмите «+» в строке поиска, чтобы написать кому-то'
                                  : 'Ничего не найдено',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.montserrat(
                                fontSize: 14,
                                height: 1.35,
                                color: kPineGreen.withValues(alpha: 0.72),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          addAutomaticKeepAlives: true,
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
                          itemCount: _filtered.length,
                          separatorBuilder: (BuildContext c, int i) => Divider(
                            height: 1,
                            thickness: 1,
                            indent: 70,
                            endIndent: 12,
                            color: kPineGreen.withValues(alpha: 0.08),
                          ),
                          itemBuilder: (BuildContext c, int i) {
                            final ConversationListItem item = _filtered[i];
                            return _ChatListTile(
                              item: item,
                              style: _ChatListTileStyle.lightPortal,
                              notificationsMuted: _mutedIds.contains(item.id),
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
      ),
    );
  }
}

class _ChatsGlassSearchBar extends StatelessWidget {
  const _ChatsGlassSearchBar({
    required this.controller,
    required this.onAddPressed,
  });

  final TextEditingController controller;
  final VoidCallback onAddPressed;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(14);
    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF0D1118).withValues(alpha: 0.88),
          borderRadius: radius,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.search,
                  size: 22,
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  textInputAction: TextInputAction.search,
                  style: GoogleFonts.montserrat(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.94),
                    height: 1.25,
                  ),
                  cursorColor: kPortalGold,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Поиск по чатам',
                    hintStyle: GoogleFonts.montserrat(
                      fontSize: 15,
                      color: Colors.white.withValues(alpha: 0.45),
                      height: 1.25,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: onAddPressed,
                tooltip: 'Новый чат',
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.add,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 26,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatsLightSearchBar extends StatelessWidget {
  const _ChatsLightSearchBar({
    required this.controller,
    required this.onAddPressed,
  });

  final TextEditingController controller;
  final VoidCallback onAddPressed;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(14);
    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: radius,
          border: Border.all(
            color: kPineGreen.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.search, size: 22, color: kNavOliveMuted),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  textInputAction: TextInputAction.search,
                  style: GoogleFonts.montserrat(
                    fontSize: 15,
                    color: kPineGreen,
                    height: 1.25,
                  ),
                  cursorColor: kEmeraldGlow,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Поиск по чатам',
                    hintStyle: GoogleFonts.montserrat(
                      fontSize: 15,
                      color: kNavOliveMuted.withValues(alpha: 0.85),
                      height: 1.25,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: onAddPressed,
                tooltip: 'Новый чат',
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.add, color: kPineGreen, size: 26),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ChatListTileStyle { cloudCard, darkGlass, lightPortal }

class _ChatListTile extends StatelessWidget {
  const _ChatListTile({
    required this.item,
    required this.style,
    required this.notificationsMuted,
    required this.onTap,
    required this.onLongPress,
  });

  final ConversationListItem item;
  final _ChatListTileStyle style;
  final bool notificationsMuted;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  Widget _wrapChatsGlow(Widget child) {
    if (style == _ChatListTileStyle.lightPortal) {
      return _chatsLightAvatarGlow(child);
    }
    return _chatsDarkAvatarGlow(child);
  }

  Widget _leadAvatar(BuildContext context) {
    const double d = 48;
    if (style == _ChatListTileStyle.cloudCard) {
      const double diameter = 40;
      return CircleAvatar(
        backgroundColor: kPrimaryBlue.withValues(alpha: 0.2),
        child: item.isGroup
            ? const Icon(Icons.group, color: kPrimaryBlue, size: 22)
            : (item.otherAvatarUrl != null && item.otherAvatarUrl!.isNotEmpty
                  ? CityNetworkImage.avatar(
                      context: context,
                      imageUrl: item.otherAvatarUrl,
                      diameter: diameter,
                      placeholderName: item.title,
                    )
                  : Text(
                      item.title.isNotEmpty ? item.title[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: kPrimaryBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    )),
      );
    }

    final double iconSize = 26.0;
    if (item.isGroup) {
      final LinearGradient grad = style == _ChatListTileStyle.lightPortal
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[kPineGreenDark, kEmeraldGlow, Color(0xFF5CB894)],
              stops: <double>[0, 0.52, 1],
            )
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                const Color(0xFF6B5340),
                kPortalGold.withValues(alpha: 0.92),
                const Color(0xFF8B7355),
              ],
              stops: const <double>[0, 0.55, 1],
            );
      return _wrapChatsGlow(
        Container(
          width: d,
          height: d,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: grad),
          child: Icon(
            Icons.groups_rounded,
            size: iconSize,
            color: Colors.white.withValues(alpha: 0.92),
          ),
        ),
      );
    }
    if (item.otherAvatarUrl != null && item.otherAvatarUrl!.isNotEmpty) {
      return _wrapChatsGlow(
        SizedBox(
          width: d,
          height: d,
          child: CityNetworkImage.avatar(
            context: context,
            imageUrl: item.otherAvatarUrl,
            diameter: d,
            placeholderName: item.title,
          ),
        ),
      );
    }
    final String ch = item.title.isNotEmpty ? item.title[0].toUpperCase() : '?';
    final BoxDecoration letterDeco = style == _ChatListTileStyle.lightPortal
        ? const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[kPineGreenDark, kEmeraldGlow],
            ),
          )
        : const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFF505050), Color(0xFF2A2A2C)],
            ),
          );
    return _wrapChatsGlow(
      Container(
        width: d,
        height: d,
        decoration: letterDeco,
        alignment: Alignment.center,
        child: Text(
          ch,
          style: GoogleFonts.montserrat(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.92),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return switch (style) {
      _ChatListTileStyle.cloudCard => _buildCloudCardTile(context),
      _ChatListTileStyle.darkGlass => _buildDarkGlassTile(context),
      _ChatListTileStyle.lightPortal => _buildLightGlassTile(context),
    };
  }

  Widget _buildCloudCardTile(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return CloudInkCard(
      onTap: onTap,
      onLongPress: onLongPress,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _leadAvatar(context),
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
    );
  }

  Widget _buildDarkGlassTile(BuildContext context) {
    final Color titleBlend =
        Color.lerp(Colors.white.withValues(alpha: 0.94), kPortalGold, 0.12) ??
        Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        splashColor: kPortalGold.withValues(alpha: 0.08),
        highlightColor: Colors.white.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _leadAvatar(context),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.montserrat(
                                fontSize: 15.5,
                                fontWeight: item.hasUnread
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: titleBlend,
                              ),
                            ),
                          ),
                        ),
                        if (item.hasUnread)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, left: 4),
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFFE53935),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        if (notificationsMuted) ...<Widget>[
                          Padding(
                            padding: const EdgeInsets.only(top: 2, left: 2),
                            child: Icon(
                              Icons.notifications_off_outlined,
                              size: 18,
                              color: Colors.white.withValues(alpha: 0.45),
                            ),
                          ),
                          const SizedBox(width: 2),
                        ],
                        if (item.timeText.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              item.timeText,
                              style: GoogleFonts.montserrat(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w400,
                                color: Colors.white.withValues(alpha: 0.52),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.montserrat(
                        fontSize: 13.5,
                        height: 1.2,
                        color: Colors.white.withValues(alpha: 0.62),
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

  Widget _buildLightGlassTile(BuildContext context) {
    final Color titleC =
        Color.lerp(kPineGreen, kEmeraldGlow, 0.08) ?? kPineGreen;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        splashColor: kEmeraldGlow.withValues(alpha: 0.12),
        highlightColor: kPineGreen.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _leadAvatar(context),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.montserrat(
                                fontSize: 15.5,
                                fontWeight: item.hasUnread
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: titleC,
                              ),
                            ),
                          ),
                        ),
                        if (item.hasUnread)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, left: 4),
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFFE53935),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        if (notificationsMuted) ...<Widget>[
                          Padding(
                            padding: const EdgeInsets.only(top: 2, left: 2),
                            child: Icon(
                              Icons.notifications_off_outlined,
                              size: 18,
                              color: kNavOliveMuted,
                            ),
                          ),
                          const SizedBox(width: 2),
                        ],
                        if (item.timeText.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              item.timeText,
                              style: GoogleFonts.montserrat(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w400,
                                color: kNavOliveMuted.withValues(alpha: 0.88),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.montserrat(
                        fontSize: 13.5,
                        height: 1.2,
                        color: kNavOliveMuted.withValues(alpha: 0.92),
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
