import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_constants.dart';
import 'config/supabase_config.dart';
import 'config/supabase_ready.dart';
import 'services/city_data_service.dart';
import 'screens/auth_screen.dart';
import 'screens/chats_list_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
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
      home: const _AuthStateGate(),
    );
  }
}

class _AuthStateGate extends StatelessWidget {
  const _AuthStateGate();

  @override
  Widget build(BuildContext context) {
    if (!supabaseAppReady) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
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

  static const List<Widget> _pages = <Widget>[
    HomeScreen(),
    ScheduleScreen(),
    ServicesGridScreen(),
    ChatsListScreen(),
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

