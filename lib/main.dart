import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_constants.dart';
import 'widgets/soft_tab_header.dart';
import 'widgets/weather_app_bar_action.dart';
import 'app_update_check.dart';
import 'config/supabase_config.dart';
import 'config/supabase_ready.dart';
import 'screens/auth_screen.dart';
import 'main_tab_index.dart';
import 'screens/chats_list_screen.dart';
import 'services/chat_unread_badge.dart';
import 'services/message_notification_service.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/schedule_screen.dart';
import 'screens/vacancies_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseAnonKey);
  supabaseAppReady = true;
  await MessageNotificationService.instance.init();
  runApp(const CityApp());
}

class CityApp extends StatelessWidget {
  const CityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Лесосибирск',
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
      home: const _AuthStateGate(),
    );
  }
}

class _AuthStateGate extends StatelessWidget {
  const _AuthStateGate();

  @override
  Widget build(BuildContext context) {
    if (!supabaseAppReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (BuildContext context, AsyncSnapshot<AuthState> snap) {
        final Session? session = Supabase.instance.client.auth.currentSession;
        if (session == null) {
          return const AuthScreen();
        }
        return const MainNavigation();
      },
    );
  }
}

/// Главный экран с нижними табами (после авторизации).
typedef MainNavigation = MainScaffold;

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    ChatUnreadBadge.start();
    MessageNotificationService.instance.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(checkForAppUpdates(context));
      }
    });
  }

  static const List<Widget> _stackChildren = <Widget>[
    HomeScreen(),
    ScheduleScreen(),
    ServicesGridScreen(),
    ChatsListScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return MainTabIndex(
      index: _currentIndex,
      child: Scaffold(
        body: IndexedStack(index: _currentIndex, children: _stackChildren),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (int i) {
            setState(() => _currentIndex = i);
            if (i == 3) {
              unawaited(ChatUnreadBadge.refresh());
            }
          },
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shadowColor: const Color(0x14000000),
          elevation: 8,
          indicatorColor: kPrimaryBlue.withValues(alpha: 0.18),
          // На телефоне длинные подписи (Расписание) не ломают строку.
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          destinations: <Widget>[
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home, color: kPrimaryBlue),
              label: 'Главная',
            ),
            const NavigationDestination(
              icon: Icon(Icons.schedule_outlined),
              selectedIcon: Icon(Icons.schedule, color: kPrimaryBlue),
              label: 'Расписание',
            ),
            const NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view, color: kPrimaryBlue),
              label: 'Сервисы',
            ),
            NavigationDestination(
              icon: ValueListenableBuilder<bool>(
                valueListenable: ChatUnreadBadge.hasUnread,
                builder: (BuildContext context, bool v, _) {
                  return Badge(
                    isLabelVisible: v,
                    backgroundColor: const Color(0xFFE53935),
                    child: const Icon(Icons.chat_bubble_outline),
                  );
                },
              ),
              selectedIcon: ValueListenableBuilder<bool>(
                valueListenable: ChatUnreadBadge.hasUnread,
                builder: (BuildContext context, bool v, _) {
                  return Badge(
                    isLabelVisible: v,
                    backgroundColor: const Color(0xFFE53935),
                    child: const Icon(Icons.chat_bubble, color: kPrimaryBlue),
                  );
                },
              ),
              label: 'Чаты',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person, color: kPrimaryBlue),
              label: 'Аккаунт',
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Сервисы — Bento Grid
// ---------------------------------------------------------------------------

const Color _kBentoScaffoldBg = Color(0xFFF5F5F7);

class _ServiceCategory {
  const _ServiceCategory({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.cardColor,
    required this.iconAndTitleColor,
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;
  final Color cardColor;
  final Color iconAndTitleColor;
}

class ServicesGridScreen extends StatelessWidget {
  const ServicesGridScreen({super.key});

  static const List<_ServiceCategory> _categories = <_ServiceCategory>[
    _ServiceCategory(
      id: 'jobs',
      label: 'Вакансии',
      description: 'Найдите подходящую работу или сотрудников',
      icon: Icons.work_rounded,
      cardColor: Color(0xFFE1F4FD),
      iconAndTitleColor: Color(0xFF0288D1),
    ),
    _ServiceCategory(
      id: 'food',
      label: 'Еда',
      description: 'Рестораны, кафе и доставка еды к вам',
      icon: Icons.local_dining_rounded,
      cardColor: Color(0xFFFFECDE),
      iconAndTitleColor: Color(0xFFE67E4A),
    ),
    _ServiceCategory(
      id: 'services',
      label: 'Услуги',
      description: 'Различные услуги для вашего комфорта',
      icon: Icons.build_rounded,
      cardColor: Color(0xFFE2F2E3),
      iconAndTitleColor: Color(0xFF3D9B4C),
    ),
    _ServiceCategory(
      id: 'sell',
      label: 'Продам',
      description: 'Объявления о продаже товаров',
      icon: Icons.shopping_bag_rounded,
      cardColor: Color(0xFFFEE1EC),
      iconAndTitleColor: Color(0xFFD13F7A),
    ),
    _ServiceCategory(
      id: 'free',
      label: 'Даром',
      description: 'Отдавайте и находите вещи бесплатно',
      icon: Icons.card_giftcard_rounded,
      cardColor: Color(0xFFFFF4D8),
      iconAndTitleColor: Color(0xFFCC8500),
    ),
    _ServiceCategory(
      id: 'estate',
      label: 'Недвижимость',
      description: 'Покупка, аренда и продажа недвижимости',
      icon: Icons.home_rounded,
      cardColor: Color(0xFFEEE8F8),
      iconAndTitleColor: Color(0xFF7E57C2),
    ),
  ];

  void _onCategoryTap(BuildContext context, _ServiceCategory c) {
    if (c.id == 'food') {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => const FoodPlacesScreen(),
        ),
      );
    } else if (c.id == 'jobs') {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => const VacanciesScreen(),
        ),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${c.label} — в разработке')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBentoScaffoldBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SoftTabHeader(
            title: 'Сервисы',
            trailing: SoftHeaderWeatherWithAction(
              action: Icon(
                Icons.grid_view_rounded,
                size: 28,
                color: kSoftHeaderActionIconColor,
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.72,
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
  const _BentoServiceCard({required this.category, required this.onTap});

  static const Color _kDescriptionColor = Color(0xFF6C6C70);

  final _ServiceCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: category.cardColor,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        splashColor: category.iconAndTitleColor.withValues(alpha: 0.12),
        highlightColor: category.iconAndTitleColor.withValues(alpha: 0.08),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color(0xFF0A0A0A).withValues(alpha: 0.05),
            ),
          ),
          child: Stack(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 36),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        category.icon,
                        size: 28,
                        color: category.iconAndTitleColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      category.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        color: category.iconAndTitleColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Text(
                        category.description,
                        textAlign: TextAlign.center,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          height: 1.25,
                          color: _kDescriptionColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 6,
                bottom: 6,
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 24,
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
        backgroundColor: Colors.white,
        foregroundColor: kSoftHeaderTitleColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Назад',
        ),
      ),
      body: const Center(
        child: Text(
          'Пока нет заведений',
          style: TextStyle(fontSize: 16, color: Color(0xFF6C6C70)),
        ),
      ),
    );
  }
}
