import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'app_navigator_key.dart';
import 'app_constants.dart'
    show
        kAuthBackgroundAsset,
        kDarkThemeBackgroundAsset,
        kLightThemeBackgroundAsset;
import 'firebase_messaging_background.dart';
import 'services/app_theme_controller.dart';
import 'theme/city_theme.dart' show CityTheme;
import 'widgets/clean_screen_header.dart';
import 'widgets/weather_app_bar_action.dart';
import 'app_update_check.dart';
import 'config/app_secrets.dart';
import 'config/supabase_ready.dart';
import 'core/auth/app_auth.dart';
import 'core/auth/supabase_auth_port.dart';
import 'services/supabase_secure_storage.dart';
import 'services/supabase_session_migration.dart';
import 'screens/auth_screen.dart';
import 'main_shell_navigation.dart';
import 'main_tab_index.dart';
import 'widgets/city_main_navigation_bar.dart';
import 'screens/chats_list_screen.dart';
import 'services/chat_unread_badge.dart';
import 'services/city_data_service.dart';
import 'services/message_notification_service.dart';
import 'services/incoming_share_coordinator.dart';
import 'services/permission_onboarding_service.dart';
import 'services/push_notification_service.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/schedule_screen.dart';
import 'screens/real_estate_screen.dart';
import 'screens/vacancies_screen.dart';
import 'screens/places_list_screen.dart';
import 'screens/tasks_list_screen.dart';

Future<void> main() async {
  if (kSentryDsn.isNotEmpty) {
    await SentryFlutter.init((SentryFlutterOptions options) {
      options.dsn = kSentryDsn;
      options.tracesSampleRate = kDebugMode ? 1.0 : 0.12;
      options.environment = kDebugMode ? 'debug' : 'release';
    }, appRunner: _runApp);
  } else {
    await _runApp();
  }
}

Future<void> _runApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  syncCompileTimeSupabaseIntoResolved();
  // При «запечённых» в бандл ключах не трогаем диск/HTTP — мгновенный старт (Zero-Lag).
  if (!kHasCompileTimeSupabaseDartDefines) {
    await loadSupabaseRuntimeConfigIfMissing();
  }
  if (!kIsWeb) {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: <SystemUiOverlay>[SystemUiOverlay.bottom],
    );
  }
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  timeago.setLocaleMessages('ru', timeago.RuMessages());
  if (!kAreSupabaseSecretsConfigured) {
    debugPrint(
      'Конфигурация Supabase: пустые или плейсхолдерные SUPABASE_URL / SUPABASE_ANON_KEY '
      '(ожидаются const String.fromEnvironment либо api_keys.json после load).',
    );
    runApp(const _AppWithoutSupabase());
    return;
  }
  final String sessionKey = authSessionStorageKeyForUrl(kSupabaseProjectUrl);
  await migrateLegacySupabaseSessionToSecure(sessionKey);

  // В SDK нужен корень проекта https://<ref>.supabase.co (без /rest/v1/).
  // В secrets можно вставить URL из Dashboard с хвостом /rest/v1 — срезаем в [app_secrets].
  if (kDebugMode) {
    debugPrint('SUPABASE_URL for SDK (normalized): $kSupabaseProjectUrl');
  }

  await Supabase.initialize(
    url: kSupabaseProjectUrl,
    anonKey: kSupabaseAnonKey,
    authOptions: FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      autoRefreshToken: true,
      localStorage: createAuthLocalStorage(sessionKey),
      pkceAsyncStorage: createPkceAsyncStorage(),
    ),
    debug: kDebugMode,
  );
  supabaseAppReady = true;
  AppAuth.register(SupabaseAuthPort(Supabase.instance.client));
  await PushNotificationService.instance.initialize();
  await MessageNotificationService.instance.init();
  await appThemeController.load();
  runApp(const CityApp());
}

/// Экран «Конфигурация»: нет валидных ключей после [loadSupabaseRuntimeConfigIfMissing].
class _AppWithoutSupabase extends StatelessWidget {
  const _AppWithoutSupabase();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Конфигурация',
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('Конфигурация')),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Нет рабочих ключей Supabase: const String.fromEnvironment '
            '(SUPABASE_URL и SUPABASE_ANON_KEY) пусты или плейсхолдеры, '
            'и не удалось подставить api_keys.json (диск / web).\n\n'
            'Для web ключи должны быть переданы на этапе flutter build web '
            '(--dart-define или --dart-define-from-file), иначе они не попадут в JS-бандл.\n\n'
            'См. workflow .github/workflows/github-pages.yml и api_keys.example.json.',
          ),
        ),
      ),
    );
  }
}

/// Полноэкранное изображение фона тёмной темы (без [Positioned] — его оборачивает родитель).
class _CityLightBackdropImage extends StatelessWidget {
  const _CityLightBackdropImage();

  /// Фиксированный decode: без [MediaQuery] слой не пересчитывает кэш при каждом билде навигатора.
  static const int _kDecodeW = 1080;
  static const int _kDecodeH = 1920;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      kLightThemeBackgroundAsset,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.none,
      isAntiAlias: false,
      gaplessPlayback: true,
      cacheWidth: kIsWeb ? null : _kDecodeW,
      cacheHeight: kIsWeb ? null : _kDecodeH,
      errorBuilder:
          (BuildContext context, Object error, StackTrace? stackTrace) {
            return const ColoredBox(color: Color(0xFFE8F0EC));
          },
    );
  }
}

class _CityDarkBackdropImage extends StatelessWidget {
  const _CityDarkBackdropImage();

  static const int _kDecodeW = 1080;
  static const int _kDecodeH = 1920;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      kDarkThemeBackgroundAsset,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.none,
      isAntiAlias: false,
      gaplessPlayback: true,
      cacheWidth: kIsWeb ? null : _kDecodeW,
      cacheHeight: kIsWeb ? null : _kDecodeH,
      errorBuilder:
          (BuildContext context, Object error, StackTrace? stackTrace) {
            return const ColoredBox(color: CityTheme.kDarkScaffold);
          },
    );
  }
}

/// Фон логина / регистрации (снимается из дерева после входа + evict кэша).
class _CityAuthBackdropImage extends StatelessWidget {
  const _CityAuthBackdropImage();

  static const int _kDecodeW = 1080;
  static const int _kDecodeH = 1920;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      kAuthBackgroundAsset,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: FilterQuality.none,
      isAntiAlias: false,
      gaplessPlayback: true,
      cacheWidth: kIsWeb ? null : _kDecodeW,
      cacheHeight: kIsWeb ? null : _kDecodeH,
      errorBuilder:
          (BuildContext context, Object error, StackTrace? stackTrace) {
            return const ColoredBox(color: Color(0xFF4A7BA7));
          },
    );
  }
}

class CityApp extends StatefulWidget {
  const CityApp({super.key});

  @override
  State<CityApp> createState() => _CityAppState();
}

class _CityAppState extends State<CityApp> {
  StreamSubscription<AuthState>? _authSub;
  bool? _prevHadSession;

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
    appThemeController.addListener(_onTheme);
  }

  void _onTheme() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    appThemeController.removeListener(_onTheme);
    super.dispose();
  }

  void _maybeEvictAuthBackdropImage({required bool hadSession}) {
    if (_prevHadSession == false && hadSession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        PaintingBinding.instance.imageCache.evict(
          const AssetImage(kAuthBackgroundAsset),
          includeLive: true,
        );
      });
    }
    _prevHadSession = hadSession;
  }

  @override
  Widget build(BuildContext context) {
    final Session? session = Supabase.instance.client.auth.currentSession;
    final bool hadSession = session != null;
    _maybeEvictAuthBackdropImage(hadSession: hadSession);
    final bool useDark = appThemeController.useDarkTheme;

    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Лесосибирск',
      debugShowCheckedModeBanner: false,
      theme: CityTheme.light().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
        cardColor: Colors.transparent,
      ),
      darkTheme: CityTheme.dark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
        cardColor: Colors.transparent,
      ),
      themeMode: appThemeController.themeMode,
      builder: (BuildContext context, Widget? child) {
        final String backdropKey = hadSession
            ? (useDark ? 'app_dark' : 'app_light')
            : 'auth';
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: SizedBox.expand(
                      key: ValueKey<String>(backdropKey),
                      child: hadSession
                          ? (useDark
                                ? const _CityDarkBackdropImage()
                                : const _CityLightBackdropImage())
                          : const _CityAuthBackdropImage(),
                    ),
                  ),
                ),
              ),
            ),
            child ?? const SizedBox.shrink(),
          ],
        );
      },
      home: const _AuthStateGate(),
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
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Theme(
          data: Theme.of(context).copyWith(canvasColor: Colors.transparent),
          child: const Center(child: CircularProgressIndicator()),
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

  @override
  void initState() {
    super.initState();
    MainShellNavigation.register(_onTabSelected);
    ChatUnreadBadge.start();
    MessageNotificationService.instance.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(checkForAppUpdates(context));
        if (!kIsWeb) {
          IncomingShareCoordinator.tryFlushPendingShare();
          unawaited(PermissionOnboardingService.requestIfNeeded(context));
          unawaited(CityDataService.refreshNotificationsEnabledCache());
        }
      }
    });
  }

  @override
  void dispose() {
    MainShellNavigation.unregister();
    super.dispose();
  }

  void _onTabSelected(int i) {
    if (i == _currentIndex) {
      return;
    }
    setState(() => _currentIndex = i);
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
        resizeToAvoidBottomInset: false,
        extendBody: true,
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        body: IndexedStack(
          index: _currentIndex,
          children: List<Widget>.generate(
            _stackChildren.length,
            (int i) =>
                _KeepAliveTab(key: ValueKey<int>(i), child: _stackChildren[i]),
          ),
        ),
        bottomNavigationBar: Builder(
          builder: (BuildContext context) {
            final bool dark = Theme.of(context).brightness == Brightness.dark;
            final Color dockBg = dark ? const Color(0xFF0F141C) : Colors.white;
            return ColoredBox(
              color: dockBg,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: Colors.grey.withValues(alpha: 0.35),
                  ),
                  CityMainNavigationBar(
                    selectedIndex: _currentIndex,
                    onDestinationSelected: _onTabSelected,
                  ),
                ],
              ),
            );
          },
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
      label: 'Подработка',
      description:
          'Разовые поручения: помощь с переездом, вывоз мусора и другие задачи',
      icon: Icons.work_history_outlined,
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
    /// Вкладка «Сервисы» в [PageView]; пуш через корневой [Navigator] приложения.
    void pushRoute(Widget screen) {
      final NavigatorState? nav = rootNavigatorKey.currentState;
      if (nav != null && nav.mounted) {
        unawaited(
          nav.push<void>(
            MaterialPageRoute<void>(builder: (BuildContext _) => screen),
          ),
        );
        return;
      }
      final BuildContext? ctx = rootNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        unawaited(
          Navigator.of(ctx, rootNavigator: true).push<void>(
            MaterialPageRoute<void>(builder: (BuildContext _) => screen),
          ),
        );
      }
    }

    if (c.id == 'food') {
      pushRoute(const PlacesListScreen());
    } else if (c.id == 'jobs') {
      pushRoute(const VacanciesScreen());
    } else if (c.id == 'estate') {
      pushRoute(const RealEstateScreen());
    } else if (c.id == 'services') {
      pushRoute(const TasksListScreen());
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${c.label} — в разработке')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CleanFloatingHeader(
            title: 'Сервисы',
            trailing: SoftHeaderWeatherWithAction(
              action: Icon(
                Icons.grid_view_rounded,
                size: 28,
                color: cleanHeaderIconColor(context),
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
              border: Border.all(color: borderColor, width: dark ? 1.25 : 1),
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
                        child: Icon(category.icon, size: 28, color: accent),
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
