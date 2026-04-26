import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_navigator_key.dart';
import 'services/app_theme_controller.dart';
import 'theme/city_theme.dart' show CityTheme;
import 'widgets/soft_tab_header.dart';
import 'widgets/weather_app_bar_action.dart';
import 'app_update_check.dart';
import 'config/supabase_config.dart';
import 'config/supabase_ready.dart';
import 'screens/auth_screen.dart';
import 'main_shell_navigation.dart';
import 'main_tab_index.dart';
import 'widgets/city_main_navigation_bar.dart';
import 'screens/chats_list_screen.dart';
import 'services/chat_unread_badge.dart';
import 'services/message_notification_service.dart';
import 'services/incoming_share_coordinator.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/schedule_screen.dart';
import 'screens/real_estate_screen.dart';
import 'screens/vacancies_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseAnonKey);
  supabaseAppReady = true;
  await MessageNotificationService.instance.init();
  await appThemeController.load();
  runApp(const CityApp());
}

class CityApp extends StatelessWidget {
  const CityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appThemeController,
      builder: (BuildContext context, Widget? _) {
        return MaterialApp(
          navigatorKey: rootNavigatorKey,
          title: 'Лесосибирск',
          debugShowCheckedModeBanner: false,
          theme: CityTheme.light(),
          darkTheme: CityTheme.dark(),
          themeMode: appThemeController.themeMode,
          home: const _AuthStateGate(),
        );
      },
    );
  }
}

class _AuthStateGate extends StatefulWidget {
  const _AuthStateGate();

  @override
  State<_AuthStateGate> createState() => _AuthStateGateState();
}

class _AuthStateGateState extends State<_AuthStateGate> {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      unawaited(IncomingShareCoordinator.init());
    }
  }

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
  late final PageController _pageController;

  static const Duration _tabAnimDuration = Duration(milliseconds: 340);
  static const Curve _tabAnimCurve = Curves.easeOutCubic;

  @override
  void initState() {
    super.initState();
    MainShellNavigation.register(_onTabSelected);
    _pageController = PageController(initialPage: _currentIndex);
    ChatUnreadBadge.start();
    MessageNotificationService.instance.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(checkForAppUpdates(context));
        if (!kIsWeb) {
          IncomingShareCoordinator.tryFlushPendingShare();
        }
      }
    });
  }

  @override
  void dispose() {
    MainShellNavigation.unregister();
    _pageController.dispose();
    super.dispose();
  }

  void _onTabSelected(int i) {
    if (i == _currentIndex) {
      return;
    }
    setState(() => _currentIndex = i);
    unawaited(
      _pageController.animateToPage(
        i,
        duration: _tabAnimDuration,
        curve: _tabAnimCurve,
      ),
    );
    if (i == 3) {
      unawaited(ChatUnreadBadge.refresh());
    }
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
        body: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: List<Widget>.generate(
            _stackChildren.length,
            (int i) => _KeepAliveTab(
              key: ValueKey<int>(i),
              child: _stackChildren[i],
            ),
          ),
        ),
        bottomNavigationBar: CityMainNavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _onTabSelected,
        ),
      ),
    );
  }
}

/// Чтобы [PageView] не сбрасывал скролл и состояние невидимых вкладок.
class _KeepAliveTab extends StatefulWidget {
  const _KeepAliveTab({super.key, required this.child});

  final Widget child;

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

// ---------------------------------------------------------------------------
// Сервисы — Bento Grid
// ---------------------------------------------------------------------------

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
    } else if (c.id == 'estate') {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => const RealEstateScreen(),
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SoftTabHeader(
            title: 'Сервисы',
            trailing: SoftHeaderWeatherWithAction(
              action: Icon(
                Icons.grid_view_rounded,
                size: 28,
                color: softHeaderTrailingIconColor(context),
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
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = category.iconAndTitleColor;
    final Color cardBg = dark
        ? Color.alphaBlend(
            accent.withValues(alpha: 0.12),
            CityTheme.kDarkSurface,
          )
        : category.cardColor;
    final Color borderColor = dark
        ? accent.withValues(alpha: 0.55)
        : const Color(0xFF0A0A0A).withValues(alpha: 0.05);
    final List<BoxShadow> outerGlow = dark
        ? <BoxShadow>[
            BoxShadow(
              color: accent.withValues(alpha: 0.38),
              blurRadius: 12,
              spreadRadius: 0,
            ),
            BoxShadow(
              color: accent.withValues(alpha: 0.14),
              blurRadius: 22,
              spreadRadius: -4,
              offset: const Offset(0, 4),
            ),
          ]
        : const <BoxShadow>[];
    final Color iconTileBg = dark
        ? Color.alphaBlend(
            accent.withValues(alpha: 0.28),
            CityTheme.kDarkScaffold,
          )
        : Colors.white;
    final List<BoxShadow> iconShadows = dark
        ? <BoxShadow>[
            BoxShadow(
              color: accent.withValues(alpha: 0.22),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ]
        : const <BoxShadow>[
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ];
    final Color titleColor = dark ? cs.onSurface : accent;
    final Color descColor = dark ? cs.onSurfaceVariant : _kDescriptionColor;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: outerGlow,
      ),
      child: Material(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          splashColor: accent.withValues(alpha: 0.12),
          highlightColor: accent.withValues(alpha: 0.08),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: borderColor,
                width: dark ? 1.25 : 1,
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
                          color: iconTileBg,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: iconShadows,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          category.icon,
                          size: 28,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 10),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Text(
                          category.label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                            color: titleColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: Text(
                          category.description,
                          textAlign: TextAlign.center,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            height: 1.25,
                            color: descColor,
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
                    color: accent,
                  ),
                ),
              ],
            ),
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SoftTabHeader(
            leading: const SoftHeaderBackButton(),
            title: 'Заведения',
            trailing: SoftHeaderWeatherWithAction(
              action: Icon(
                Icons.restaurant_rounded,
                size: 28,
                color: softHeaderTrailingIconColor(context),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'Пока нет заведений',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
