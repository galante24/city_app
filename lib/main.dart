import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_constants.dart';
import 'config/admin_config.dart';
import 'config/supabase_config.dart';
import 'config/supabase_ready.dart';
import 'data/city_data_service.dart';
import 'screens/admin_email_auth_screen.dart';
import 'screens/ferry_admin_screen.dart';
import 'screens/home_screen.dart';
import 'screens/phone_auth_screen.dart';
import 'screens/schedule_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: kSupabaseUrl,
    anonKey: kSupabaseAnonKey,
  );
  supabaseAppReady = true;
  runApp(const CityApp());
}

class CityApp extends StatelessWidget {
  const CityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Город',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kPrimaryBlue,
          primary: kPrimaryBlue,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: kPrimaryBlue,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: kPrimaryBlue,
          foregroundColor: Colors.white,
        ),
      ),
      home: const MainScaffold(),
    );
  }
}

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  static const List<Widget> _pages = <Widget>[
    HomeScreen(),
    ScheduleScreen(),
    ServicesGridScreen(),
    ChatsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (int i) {
          setState(() => _currentIndex = i);
        },
        indicatorColor: kPrimaryBlue.withValues(alpha: 0.2),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: kPrimaryBlue),
            label: 'Главная',
          ),
          NavigationDestination(
            icon: Icon(Icons.schedule_outlined),
            selectedIcon: Icon(Icons.schedule, color: kPrimaryBlue),
            label: 'Расписание',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view, color: kPrimaryBlue),
            label: 'Сервисы',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble, color: kPrimaryBlue),
            label: 'Чаты',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: kPrimaryBlue),
            label: 'Профиль',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Сервисы — Bento Grid
// ---------------------------------------------------------------------------

const Color _kBentoScaffoldBg = Color(0xFFF5F5F7);
const Color _kServiceFerryCardBg = Color(0xFFFFFFFF);
const Color _kServiceFerryTextSecondary = Color(0xFF6C6C70);
const Color _kServiceFerryTextPrimary = Color(0xFF1C1C1E);

class _ServiceCategory {
  const _ServiceCategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.cardColor,
    required this.iconAndTitleColor,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color cardColor;
  final Color iconAndTitleColor;
}

class ServicesGridScreen extends StatefulWidget {
  const ServicesGridScreen({super.key});

  @override
  State<ServicesGridScreen> createState() => _ServicesGridScreenState();
}

class _ServicesGridScreenState extends State<ServicesGridScreen> {
  FerryStatusRow? _ferry;
  bool _loadingFerry = true;

  static const List<_ServiceCategory> _categories = <_ServiceCategory>[
    _ServiceCategory(
      id: 'jobs',
      label: 'Вакансии',
      icon: Icons.work_rounded,
      cardColor: Color(0xFFE1F4FD),
      iconAndTitleColor: Color(0xFF0288D1),
    ),
    _ServiceCategory(
      id: 'food',
      label: 'Еда',
      icon: Icons.restaurant_rounded,
      cardColor: Color(0xFFFFECDE),
      iconAndTitleColor: Color(0xFFE67E4A),
    ),
    _ServiceCategory(
      id: 'services',
      label: 'Услуги',
      icon: Icons.build_rounded,
      cardColor: Color(0xFFE2F2E3),
      iconAndTitleColor: Color(0xFF3D9B4C),
    ),
    _ServiceCategory(
      id: 'sell',
      label: 'Продам',
      icon: Icons.shopping_bag_rounded,
      cardColor: Color(0xFFFEE1EC),
      iconAndTitleColor: Color(0xFFD13F7A),
    ),
    _ServiceCategory(
      id: 'free',
      label: 'Даром',
      icon: Icons.card_giftcard_rounded,
      cardColor: Color(0xFFFFF4D8),
      iconAndTitleColor: Color(0xFFCC8500),
    ),
    _ServiceCategory(
      id: 'estate',
      label: 'Недвижимость',
      icon: Icons.home_rounded,
      cardColor: Color(0xFFEEE8F8),
      iconAndTitleColor: Color(0xFF7E57C2),
    ),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_loadFerry());
  }

  Future<void> _loadFerry() async {
    final FerryStatusRow? f = await CityDataService.fetchFerryStatus();
    if (mounted) {
      setState(() {
        _ferry = f;
        _loadingFerry = false;
      });
    }
  }

  void _onCategoryTap(BuildContext context, _ServiceCategory c) {
    if (c.id == 'food') {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => const FoodPlacesScreen(),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${c.label} — в разработке')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final String ferryText = _ferry == null
        ? (_loadingFerry
            ? 'Загрузка расписания...'
            : 'Нет данных в таблице schedules')
        : _ferry!.statusText;
    final String? ferryTime = _ferry?.timeText;
    final bool ferryRun = _ferry == null || _ferry!.isRunning;

    return Scaffold(
      backgroundColor: _kBentoScaffoldBg,
      appBar: AppBar(
        title: const Text('Сервисы'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Material(
            color: _kServiceFerryCardBg,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: <Widget>[
                  Icon(
                    ferryRun
                        ? Icons.directions_boat_filled
                        : Icons.portable_wifi_off,
                    color: ferryRun ? const Color(0xFF2ECC71) : Colors.orange[800]!,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Паром (из schedules)',
                          style: TextStyle(
                            fontSize: 12,
                            color: _kServiceFerryTextSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ferryText,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _kServiceFerryTextPrimary,
                          ),
                        ),
                        if (ferryTime != null && ferryTime.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            ferryTime,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_loadingFerry)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      onPressed: () {
                        unawaited(_loadFerry());
                      },
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Обновить',
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.95,
              ),
              itemCount: _categories.length,
              itemBuilder: (BuildContext context, int index) {
                final _ServiceCategory c = _categories[index];
                return _BentoServiceCard(
                  category: c,
                  onTap: () => _onCategoryTap(context, c),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BentoServiceCard extends StatelessWidget {
  const _BentoServiceCard({
    required this.category,
    required this.onTap,
  });

  final _ServiceCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: category.cardColor,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: category.iconAndTitleColor.withValues(alpha: 0.12),
        highlightColor: category.iconAndTitleColor.withValues(alpha: 0.08),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF0A0A0A).withValues(alpha: 0.04),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                category.icon,
                size: 44,
                color: category.iconAndTitleColor,
              ),
              const SizedBox(height: 12),
              Text(
                category.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  color: category.iconAndTitleColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FoodPlacesScreen extends StatelessWidget {
  const FoodPlacesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBentoScaffoldBg,
      appBar: AppBar(
        title: const Text('Заведения'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Назад',
        ),
      ),
      body: const Center(
        child: Text(
          'Пока нет заведений',
          style: TextStyle(
            fontSize: 16,
            color: Color(0xFF6C6C70),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Чаты
// ---------------------------------------------------------------------------

const Color _kChatsListBg = Color(0xFFFFFFFF);
const Color _kChatsHeaderText = Color(0xFF1A1A1A);
const Color _kChatsTimeGrey = Color(0xFF8A8A8E);
const Color _kChatsSubGrey = Color(0xFF6B6B70);
const Color _kChatsOnline = Color(0xFF2ECC71);
const Color _kChatsDivider = Color(0xFFE8E8ED);

Color _messengerColorForName(String name) {
  const List<Color> colors = <Color>[
    Color(0xFF5C6BC0),
    Color(0xFF7E57C2),
    Color(0xFF26A69A),
    Color(0xFFEF6C00),
    Color(0xFFD84315),
    Color(0xFF00897B),
  ];
  int h = 0;
  for (final int c in name.codeUnits) {
    h = (h + c) * 17;
  }
  return colors[h.abs() % colors.length];
}

String _messengerFirstLetter(String title) {
  for (int i = 0; i < title.length; i++) {
    final int u = title.codeUnitAt(i);
    if (u > 32) {
      return title[i].toUpperCase();
    }
  }
  return '?';
}

enum _MessengerChatType { support, group, work, direct }

class _ChatPreview {
  const _ChatPreview({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.unread,
    required this.type,
  });

  final String id;
  final String title;
  final String subtitle;
  final String time;
  final int unread;
  final _MessengerChatType type;
}

class _MessengerAvatar extends StatelessWidget {
  const _MessengerAvatar({required this.preview});

  final _ChatPreview preview;

  @override
  Widget build(BuildContext context) {
    const double r = 26;
    switch (preview.type) {
      case _MessengerChatType.support:
        return CircleAvatar(
          radius: r,
          backgroundColor: kPrimaryBlue.withValues(alpha: 0.12),
          child: const Icon(
            Icons.support_agent_rounded,
            size: 28,
            color: kPrimaryBlue,
          ),
        );
      case _MessengerChatType.group:
        return CircleAvatar(
          radius: r,
          backgroundColor: const Color(0xFFFFF0E0),
          child: const Icon(
            Icons.groups_rounded,
            size: 28,
            color: Color(0xFFE67E4A),
          ),
        );
      case _MessengerChatType.work:
        return CircleAvatar(
          radius: r,
          backgroundColor: const Color(0xFFEEE8F8),
          child: const Icon(
            Icons.work_history_rounded,
            size: 26,
            color: Color(0xFF7E57C2),
          ),
        );
      case _MessengerChatType.direct:
        return CircleAvatar(
          radius: r,
          backgroundColor: _messengerColorForName(preview.title),
          child: Text(
            _messengerFirstLetter(preview.title),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
    }
  }
}

class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  static const List<_ChatPreview> _chats = <_ChatPreview>[
    _ChatPreview(
      id: 'sup',
      title: 'Служба поддержки',
      subtitle: 'Мы на связи 24/7',
      time: '14:45',
      unread: 1,
      type: _MessengerChatType.support,
    ),
    _ChatPreview(
      id: 'nbr',
      title: 'Соседи',
      subtitle: 'Анна: кто-нибудь был на ярмарке?',
      time: '12:10',
      unread: 0,
      type: _MessengerChatType.group,
    ),
    _ChatPreview(
      id: 'job',
      title: 'Работа · курьер',
      subtitle: 'Вы: спасибо, посмотрю вакансию',
      time: 'вчера',
      unread: 3,
      type: _MessengerChatType.work,
    ),
    _ChatPreview(
      id: 'dm',
      title: 'Мария К.',
      subtitle: 'Передам ключи вечером, ок?',
      time: '09:30',
      unread: 0,
      type: _MessengerChatType.direct,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kChatsListBg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: _kChatsListBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        titleSpacing: 16,
        title: const Text(
          'Чаты',
          style: TextStyle(
            color: _kChatsHeaderText,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: false,
      ),
      body: ListView.separated(
        itemCount: _chats.length,
        padding: const EdgeInsets.only(top: 4),
        separatorBuilder: (BuildContext context, int index) {
          return const Padding(
            padding: EdgeInsets.only(left: 80),
            child: Divider(
              height: 1,
              thickness: 1,
              color: _kChatsDivider,
            ),
          );
        },
        itemBuilder: (BuildContext context, int i) {
          final _ChatPreview c = _chats[i];
          return _MessengerChatRow(
            preview: c,
            onTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => ChatThreadScreen(
                    title: c.title,
                    type: c.type,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MessengerChatRow extends StatelessWidget {
  const _MessengerChatRow({
    required this.preview,
    required this.onTap,
  });

  final _ChatPreview preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kChatsListBg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _MessengerAvatar(preview: preview),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Expanded(
                          child: Row(
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  preview.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: _kChatsHeaderText,
                                  ),
                                ),
                              ),
                              if (preview.type == _MessengerChatType.support) ...<Widget>[
                                const SizedBox(width: 6),
                                const Text(
                                  'Онлайн',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: _kChatsOnline,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          preview.time,
                          style: const TextStyle(
                            fontSize: 13,
                            color: _kChatsTimeGrey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        if (preview.type == _MessengerChatType.group) ...<Widget>[
                          const Icon(
                            Icons.groups_rounded,
                            size: 14,
                            color: _kChatsSubGrey,
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (preview.type == _MessengerChatType.work) ...<Widget>[
                          const Icon(
                            Icons.badge_outlined,
                            size: 14,
                            color: _kChatsSubGrey,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            preview.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              color: _kChatsSubGrey,
                              height: 1.25,
                            ),
                          ),
                        ),
                        if (preview.unread > 0) ...<Widget>[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            constraints: const BoxConstraints(minWidth: 20),
                            decoration: BoxDecoration(
                              color: kPrimaryBlue,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                preview.unread > 99
                                    ? '99+'
                                    : preview.unread.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
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

class _ChatMessage {
  const _ChatMessage(this.text, this.mine, this.time);
  final String text;
  final bool mine;
  final String time;
}

class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({
    super.key,
    required this.title,
    required this.type,
  });

  final String title;
  final _MessengerChatType type;

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final TextEditingController _input = TextEditingController();
  final List<_ChatMessage> _messages = <_ChatMessage>[];

  @override
  void initState() {
    super.initState();
    if (widget.type == _MessengerChatType.support) {
      _messages.addAll(const <_ChatMessage>[
        _ChatMessage('Здравствуйте! Напишите, чем можем помочь.', false, '14:32'),
        _ChatMessage('Как сменить адрес в профиле?', true, '14:40'),
        _ChatMessage('Откройте Профиль → Изменить и укажите новый адрес.', false, '14:45'),
      ]);
    } else if (widget.type == _MessengerChatType.group) {
      _messages.addAll(const <_ChatMessage>[
        _ChatMessage('Собрание 15 апреля — кто пойдёт?', false, '10:00'),
        _ChatMessage('Я +1', true, '10:05'),
        _ChatMessage('Анна: кто-нибудь был на ярмарке?', false, '12:10'),
      ]);
    } else if (widget.type == _MessengerChatType.work) {
      _messages.addAll(const <_ChatMessage>[
        _ChatMessage('Вакансия «курьер» ещё актуальна?', true, '10:00'),
        _ChatMessage('Да, пишите в личные данные. График гибкий.', false, '10:15'),
        _ChatMessage('Спасибо, посмотрю вакансию', true, '10:20'),
      ]);
    } else {
      _messages.addAll(const <_ChatMessage>[
        _ChatMessage('Привет! Напомни, во сколько встреча?', true, '09:00'),
        _ChatMessage('К 19:00 у подъезда', false, '09:10'),
        _ChatMessage('Передам ключи вечером, ок?', false, '09:25'),
      ]);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send() {
    final String t = _input.text.trim();
    if (t.isEmpty) {
      return;
    }
    setState(() {
      _messages.add(
        _ChatMessage(
          t,
          true,
          TimeOfDay.now().format(context),
        ),
      );
    });
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: _kChatsListBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kPrimaryBlue),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: <Widget>[
            if (widget.type == _MessengerChatType.support)
              const CircleAvatar(
                radius: 18,
                backgroundColor: Color(0xFFE3F2FD),
                child: Icon(
                  Icons.support_agent_rounded,
                  size: 22,
                  color: kPrimaryBlue,
                ),
              )
            else if (widget.type == _MessengerChatType.group)
              const CircleAvatar(
                radius: 18,
                backgroundColor: Color(0xFFFFF0E0),
                child: Icon(
                  Icons.groups_rounded,
                  size: 22,
                  color: Color(0xFFE67E4A),
                ),
              )
            else if (widget.type == _MessengerChatType.work)
              const CircleAvatar(
                radius: 18,
                backgroundColor: Color(0xFFEEE8F8),
                child: Icon(
                  Icons.work_history_rounded,
                  size: 20,
                  color: Color(0xFF7E57C2),
                ),
              )
            else
              CircleAvatar(
                radius: 18,
                backgroundColor: _messengerColorForName(widget.title),
                child: Text(
                  _messengerFirstLetter(widget.title),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _kChatsHeaderText,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (widget.type == _MessengerChatType.support)
                    const Text(
                      'в сети',
                      style: TextStyle(
                        color: _kChatsOnline,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else if (widget.type == _MessengerChatType.group)
                    const Text(
                      'группа',
                      style: TextStyle(
                        color: _kChatsSubGrey,
                        fontSize: 12,
                      ),
                    )
                  else if (widget.type == _MessengerChatType.work)
                    const Text(
                      'вакансия',
                      style: TextStyle(
                        color: _kChatsSubGrey,
                        fontSize: 12,
                      ),
                    )
                  else
                    const Text(
                      'личный чат',
                      style: TextStyle(
                        color: _kChatsSubGrey,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              itemCount: _messages.length,
              itemBuilder: (BuildContext context, int i) {
                final _ChatMessage m = _messages[i];
                return _MessageBubble(
                  text: m.text,
                  time: m.time,
                  mine: m.mine,
                );
              },
            ),
          ),
          Material(
            color: _kChatsListBg,
            elevation: 2,
            shadowColor: const Color(0x14000000),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          hintText: 'Сообщение',
                          filled: true,
                          fillColor: Color(0xFFF0F0F0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(20)),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: kPrimaryBlue,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _send,
                      icon: const Icon(Icons.send_rounded, size: 22),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.text,
    required this.time,
    required this.mine,
  });

  final String text;
  final String time;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: mine ? kPrimaryBlue : const Color(0xFFFFFFFF),
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
                  color: mine ? Colors.white : _kChatsHeaderText,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                time,
                style: TextStyle(
                  color: mine
                      ? Colors.white.withValues(alpha: 0.75)
                      : _kChatsTimeGrey,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Профиль
// ---------------------------------------------------------------------------

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String firstName = 'Иван';
  String lastName = 'Иванов';
  String birthDate = '15.05.1990';

  Future<void> _signOut() async {
    if (!supabaseAppReady) {
      return;
    }
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Вы вышли из аккаунта')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final User? user =
        supabaseAppReady ? Supabase.instance.client.auth.currentUser : null;
    final String? phone = user?.phone;
    final String? email = user?.email;
    final bool isEmailAdmin = CityDataService.isCurrentUserAdminSync();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Center(
            child: CircleAvatar(
              radius: 48,
              backgroundColor: kPrimaryBlue,
              child: Icon(Icons.person, size: 56, color: Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '$firstName $lastName',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Center(
            child: Text(
              birthDate,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'Аккаунт администратора',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (phone != null)
                    Text(
                      'Телефон: $phone',
                      style: TextStyle(color: Colors.grey[700], fontSize: 14),
                    ),
                  if (email != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      'Email: $email',
                      style: TextStyle(color: Colors.grey[700], fontSize: 14),
                    ),
                  ],
                  if (phone == null && email == null)
                    const Text(
                      'Войдите по SMS или email администратора, чтобы публиковать новости и менять расписание.',
                      style: TextStyle(fontSize: 14),
                    ),
                  if (isEmailAdmin)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Роль администратора активна ($kAdministratorEmail).',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF2E7D32),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  if (user == null) ...<Widget>[
                    FilledButton(
                      onPressed: () async {
                        final bool? ok = await Navigator.of(context).push<bool>(
                          MaterialPageRoute<bool>(
                            builder: (BuildContext c) => const PhoneAuthScreen(),
                          ),
                        );
                        if (ok == true && mounted) {
                          setState(() {});
                        }
                      },
                      child: const Text('Войти по номеру телефона'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () async {
                        final bool? ok = await Navigator.of(context).push<bool>(
                          MaterialPageRoute<bool>(
                            builder: (BuildContext c) =>
                                const AdminEmailAuthScreen(),
                          ),
                        );
                        if (ok == true && mounted) {
                          setState(() {});
                        }
                      },
                      child: const Text('Войти (email администратора)'),
                    ),
                  ] else ...<Widget>[
                    OutlinedButton(
                      onPressed: _signOut,
                      child: const Text('Выйти'),
                    ),
                    const SizedBox(height: 8),
                    if (email == null)
                      OutlinedButton(
                        onPressed: () async {
                          final bool? ok = await Navigator.of(context).push<bool>(
                            MaterialPageRoute<bool>(
                              builder: (BuildContext c) =>
                                  const AdminEmailAuthScreen(),
                            ),
                          );
                          if (ok == true && mounted) {
                            setState(() {});
                          }
                        },
                        child: const Text('Сменить на вход по email (админ)'),
                      ),
                    if (email == null) const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.directions_boat, color: kPrimaryBlue),
                      title: const Text('Расписание парома (полный экран)'),
                      subtitle: const Text('То же, что и «карандаш» на главной'),
                      onTap: () async {
                        if (!CityDataService.isCurrentUserAdminSync()) {
                          if (!context.mounted) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Нужен вход под $kAdministratorEmail (Профиль → email)',
                              ),
                            ),
                          );
                          return;
                        }
                        final bool? saved = await Navigator.of(context).push<bool>(
                          MaterialPageRoute<bool>(
                            builder: (BuildContext c) => const FerryAdminScreen(),
                          ),
                        );
                        if (saved == true && mounted) {
                          setState(() {});
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Данные',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: kPrimaryBlue,
            ),
          ),
          const SizedBox(height: 8),
          _ProfileRow(label: 'Имя', value: firstName),
          _ProfileRow(label: 'Фамилия', value: lastName),
          _ProfileRow(label: 'Дата рождения', value: birthDate),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (ctx) {
                    final fn = TextEditingController(text: firstName);
                    final ln = TextEditingController(text: lastName);
                    final bd = TextEditingController(text: birthDate);
                    return Padding(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 8,
                        bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Изменить данные',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: fn,
                            decoration: const InputDecoration(
                              labelText: 'Имя',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: ln,
                            decoration: const InputDecoration(
                              labelText: 'Фамилия',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: bd,
                            decoration: const InputDecoration(
                              labelText: 'Дата рождения',
                              border: OutlineInputBorder(),
                              hintText: 'ДД.ММ.ГГГГ',
                            ),
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: () {
                              setState(() {
                                firstName = fn.text.trim().isEmpty
                                    ? firstName
                                    : fn.text.trim();
                                lastName = ln.text.trim().isEmpty
                                    ? lastName
                                    : ln.text.trim();
                                birthDate = bd.text.trim().isEmpty
                                    ? birthDate
                                    : bd.text.trim();
                              });
                              Navigator.pop(ctx);
                            },
                            child: const Text('Сохранить'),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: kPrimaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Изменить', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        subtitle: Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}
