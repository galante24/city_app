import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../app_constants.dart';
import '../services/chat_unread_badge.dart';
import '../theme/city_theme.dart' show CityTheme;

/// Нижняя панель табов — та же, что на главном экране после авторизации.
class CityMainNavigationBar extends StatelessWidget {
  const CityMainNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool dark = theme.brightness == Brightness.dark;
    final Color navBg = theme.navigationBarTheme.backgroundColor ?? cs.surface;
    final Color navIconMuted = dark
        ? CityTheme.kDarkNavIconMuted
        : cs.onSurface.withValues(alpha: 0.7);
    final Color selectedAccent = dark ? kPortalGold : cs.primary;

    final Widget bar = NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      backgroundColor: dark ? Colors.transparent : navBg,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: dark ? 0 : 8,
      indicatorColor: dark
          ? kPortalGold.withValues(alpha: 0.25)
          : kPrimaryBlue.withValues(alpha: 0.18),
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      destinations: <Widget>[
        NavigationDestination(
          icon: Icon(Icons.home_outlined, color: navIconMuted),
          selectedIcon: Icon(Icons.home_rounded, color: selectedAccent),
          label: 'Главная',
        ),
        NavigationDestination(
          icon: Icon(Icons.schedule_outlined, color: navIconMuted),
          selectedIcon: Icon(Icons.schedule_rounded, color: selectedAccent),
          label: 'Расписание',
        ),
        NavigationDestination(
          icon: Icon(Icons.grid_view_outlined, color: navIconMuted),
          selectedIcon: Icon(Icons.grid_view_rounded, color: selectedAccent),
          label: 'Сервисы',
        ),
        NavigationDestination(
          icon: ValueListenableBuilder<bool>(
            valueListenable: ChatUnreadBadge.hasUnread,
            builder: (BuildContext context, bool v, _) {
              return Badge(
                isLabelVisible: v,
                backgroundColor: const Color(0xFFE53935),
                child: Icon(Icons.chat_bubble_outline, color: navIconMuted),
              );
            },
          ),
          selectedIcon: ValueListenableBuilder<bool>(
            valueListenable: ChatUnreadBadge.hasUnread,
            builder: (BuildContext context, bool v, _) {
              return Badge(
                isLabelVisible: v,
                backgroundColor: const Color(0xFFE53935),
                child: Icon(Icons.chat_bubble_rounded, color: selectedAccent),
              );
            },
          ),
          label: 'Чаты',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline, color: navIconMuted),
          selectedIcon: Icon(Icons.person_rounded, color: selectedAccent),
          label: 'Аккаунт',
        ),
      ],
    );

    if (!dark) {
      return bar;
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.4),
          child: bar,
        ),
      ),
    );
  }
}
