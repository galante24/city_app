import 'package:flutter/material.dart';

import '../app_constants.dart';

/// Переходы при [Navigator.push]: горизонтальный слайд на телефонах, лёгкий fade на десктопе.
const PageTransitionsTheme kCityPageTransitions = PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    TargetPlatform.android: CupertinoPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
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
      scaffoldBackgroundColor: const Color(0xFFF5F5F7),
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
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cs.surface,
        indicatorColor: kPrimaryBlue.withValues(alpha: 0.18),
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? kPrimaryBlue
                : cs.onSurface.withValues(alpha: 0.75),
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? kPrimaryBlue
                : cs.onSurface.withValues(alpha: 0.7),
            size: 24,
          ),
        ),
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
    final ColorScheme cs = ColorScheme.fromSeed(
      seedColor: kPrimaryBlue,
      primary: kPrimaryBlue,
      brightness: Brightness.dark,
    ).copyWith(
      surface: kDarkSurface,
      onSurface: kDarkOnSurface,
      onSurfaceVariant: kDarkOnSurfaceVariant,
      surfaceContainerLowest: kDarkScaffold,
      surfaceContainerLow: const Color(0xFF252525),
      surfaceContainer: kDarkSurface,
      surfaceContainerHigh: kDarkSurface,
      surfaceContainerHighest: const Color(0xFF2C2C2C),
      outline: const Color(0xFF3D3D3D),
      outlineVariant: const Color(0xFF404040),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: cs,
      pageTransitionsTheme: kCityPageTransitions,
      scaffoldBackgroundColor: kDarkScaffold,
      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        centerTitle: true,
        elevation: 0,
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
