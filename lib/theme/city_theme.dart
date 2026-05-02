import 'package:flutter/material.dart';

import '../app_constants.dart';

/// Переходы в светлой теме.
const PageTransitionsTheme kCityPageTransitions = PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    // Как в тёмной теме: без Cupertino-слоя на Android — дешевле при полноэкранном фоне.
    TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.fuchsia: FadeUpwardsPageTransitionsBuilder(),
    TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
  },
);

/// В тёмой теме под полноэкранным фоном тяжёлые переходы (Cupertino / Zoom) дают просадки FPS.
/// Лёгкий сдвиг снизу ([FadeUpwardsPageTransitionsBuilder]) на Android обычно плавнее.
const PageTransitionsTheme kCityPageTransitionsDark = PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.fuchsia: FadeUpwardsPageTransitionsBuilder(),
    TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
  },
);

/// Темы приложения: общий seed [kPrimaryBlue], фон скролла как у «мягких» экранов.
abstract final class CityTheme {
  static ThemeData light() {
    final ColorScheme cs = ColorScheme.fromSeed(
      seedColor: kPrimaryBlue,
      primary: kPrimaryBlue,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      pageTransitionsTheme: kCityPageTransitions,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      cardColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: kPineGreen,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: kPineGreen),
        titleTextStyle: TextStyle(
          color: kPineGreen,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: kPrimaryBlue.withValues(alpha: 0.18),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? kPineGreen
                : kNavOliveMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? kPineGreen
                : kNavOliveMuted,
            size: 24,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return kEmeraldGlow;
          }
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return kEmeraldGlow.withValues(alpha: 0.38);
          }
          return null;
        }),
      ),
    );
  }

  /// Фон экрана и «мягкие» блоки — как в референсе (#121212 / #1E1E1E).
  static const Color kDarkScaffold = Color(0xFF121212);
  static const Color kDarkSurface = Color(0xFF1E1E1E);
  static const Color kDarkOnSurface = Color(0xFFF5F5F7);
  static const Color kDarkOnSurfaceVariant = Color(0xFF9E9E9E);
  static const Color kDarkNavBar = Color(0xFF000000);
  static const Color kDarkNavIconMuted = Color(0xFFB0B0B0);

  static ThemeData dark() {
    final ColorScheme cs =
        ColorScheme.fromSeed(
          seedColor: kPrimaryBlue,
          primary: kPrimaryBlue,
          brightness: Brightness.dark,
        ).copyWith(
          surface: kDarkSurface,
          onSurface: kDarkOnSurface,
          onSurfaceVariant: kDarkOnSurfaceVariant,
          surfaceContainerLowest: kDarkSurface,
          surfaceContainerLow: kDarkSurface,
          surfaceContainer: kDarkSurface,
          surfaceContainerHigh: kDarkSurface,
          surfaceContainerHighest: kDarkSurface,
          outline: const Color(0xFF3D3D3D),
          outlineVariant: const Color(0xFF404040),
        );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: cs,
      pageTransitionsTheme: kCityPageTransitionsDark,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      cardColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: cs.onSurface,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: kDarkNavBar,
        indicatorColor: kPrimaryBlue.withValues(alpha: 0.28),
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? kDarkOnSurface
                : kDarkOnSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? kPrimaryBlue
                : kDarkNavIconMuted,
            size: 24,
          ),
        ),
      ),
    );
  }
}
