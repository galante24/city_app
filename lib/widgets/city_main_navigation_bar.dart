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
    final Color navBg =
        theme.navigationBarTheme.backgroundColor ?? cs.surface;
    final Color navIconMuted =
        dark ? CityTheme.kDarkNavIconMuted : cs.onSurface.withValues(alpha: 0.7);

    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      backgroundColor: navBg,
      surfaceTintColor: Colors.transparent,
      shadowColor: dark ? Colors.black54 : const Color(0x14000000),
      elevation: 8,
      indicatorColor: kPrimaryBlue.withValues(
        alpha: dark ? 0.35 : 0.18,
      ),
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      destinations: <Widget>[
        NavigationDestination(
          icon: Icon(Icons.home_outlined, color: navIconMuted),
          selectedIcon: Icon(Icons.home, color: cs.primary),
          label: 'Главная',
        ),
        NavigationDestination(
          icon: Icon(Icons.schedule_outlined, color: navIconMuted),
          selectedIcon: Icon(Icons.schedule, color: cs.primary),
          label: 'Расписание',
        ),
        NavigationDestination(
          icon: Icon(Icons.grid_view_outlined, color: navIconMuted),
          selectedIcon: Icon(Icons.grid_view, color: cs.primary),
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
                child: Icon(Icons.chat_bubble, color: cs.primary),
              );
            },
          ),
          label: 'Чаты',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline, color: navIconMuted),
          selectedIcon: Icon(Icons.person, color: cs.primary),
          label: 'Аккаунт',
        ),
      ],
    );
  }
}
