import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_constants.dart';
import '../services/chat_unread_badge.dart';

/// Нижняя панель табов — та же, что на главном экране после авторизации.
/// Тёмная тема: полоса без размытия (производительность). Светлая: прозрачная
/// полоса с изумрудным ореолом у активной иконки.
class CityMainNavigationBar extends StatelessWidget {
  const CityMainNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const List<String> _labels = <String>[
    'Главная',
    'Расписание',
    'Сервисы',
    'Чаты',
    'Аккаунт',
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    if (dark) {
      return _DarkDockNavBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        labels: _labels,
      );
    }

    return _LightDockNavBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      labels: _labels,
    );
  }
}

/// Тёмное нижнее меню прижато к низу: [Align] здесь нельзя — см. комментарий в [build].
class _DarkDockNavBar extends StatelessWidget {
  const _DarkDockNavBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.labels,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<String> labels;

  static const BorderRadius _topRadius = BorderRadius.vertical(
    top: Radius.circular(20),
  );

  static Color get _muted => Colors.white.withValues(alpha: 0.66);

  Widget _chatIcon({required bool selected}) {
    final Color c = selected ? kPortalGold : _muted;
    final IconData shape = selected
        ? Icons.chat_bubble_rounded
        : Icons.chat_bubble_outline;
    final Widget raw = Icon(shape, color: c, size: 24);
    return ValueListenableBuilder<bool>(
      valueListenable: ChatUnreadBadge.hasUnread,
      builder: (BuildContext context, bool v, _) {
        return Badge(
          isLabelVisible: v,
          backgroundColor: const Color(0xFFE53935),
          alignment: Alignment.topRight,
          offset: selected ? const Offset(4, -4) : const Offset(3, -5),
          child: raw,
        );
      },
    );
  }

  Widget _profileIcon({required bool selected}) {
    final Color c = selected ? kPortalGold : _muted;
    return SizedBox(
      height: 26,
      width: 32,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: <Widget>[
          Icon(
            selected ? Icons.person_rounded : Icons.person_outline_rounded,
            color: c,
            size: 24,
          ),
          Positioned(
            right: -1,
            top: -2,
            child: Icon(Icons.auto_awesome, size: 10.5, color: c),
          ),
        ],
      ),
    );
  }

  Widget _iconForIndex(int index, {required bool selected}) {
    return switch (index) {
      0 => Icon(
        selected ? Icons.home_rounded : Icons.home_outlined,
        color: selected ? kPortalGold : _muted,
        size: 24,
      ),
      1 => Icon(
        selected ? Icons.schedule_rounded : Icons.schedule_outlined,
        color: selected ? kPortalGold : _muted,
        size: 24,
      ),
      2 => Icon(
        selected ? Icons.grid_view_rounded : Icons.grid_view_outlined,
        color: selected ? kPortalGold : _muted,
        size: 24,
      ),
      3 => _chatIcon(selected: selected),
      4 => _profileIcon(selected: selected),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final Widget dock = SizedBox(
      width: double.infinity,
      child: ClipRRect(
        borderRadius: _topRadius,
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: _topRadius,
            color: const Color(0xFF0F141C).withValues(alpha: 0.96),
            border: Border(
              top: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List<Widget>.generate(labels.length, (int i) {
                return Expanded(
                  child: _DockNavTile(
                    selected: selectedIndex == i,
                    label: labels[i],
                    icon: _iconForIndex(i, selected: selectedIndex == i),
                    onTap: () => onDestinationSelected(i),
                    variant: _DockNavVariant.dark,
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );

    return SafeArea(top: false, minimum: EdgeInsets.zero, child: dock);
  }
}

enum _DockNavVariant { dark, light }

class _DockNavTile extends StatelessWidget {
  const _DockNavTile({
    required this.selected,
    required this.label,
    required this.icon,
    required this.onTap,
    required this.variant,
  });

  final bool selected;
  final String label;
  final Widget icon;
  final VoidCallback onTap;
  final _DockNavVariant variant;

  Color get _accent =>
      variant == _DockNavVariant.dark ? kPortalGold : kPineGreen;

  Color get _selectedFill => variant == _DockNavVariant.dark
      ? const Color(0xFFFFD700).withValues(alpha: 0.14)
      : kEmeraldGlow.withValues(alpha: 0.12);

  Color get _selectedBorder => variant == _DockNavVariant.dark
      ? kPortalGold.withValues(alpha: 0.38)
      : kEmeraldGlow.withValues(alpha: 0.35);

  List<BoxShadow>? get _selectedShadow {
    if (!selected) {
      return null;
    }
    if (variant == _DockNavVariant.dark) {
      return <BoxShadow>[
        BoxShadow(
          color: kPortalGold.withValues(alpha: 0.26),
          blurRadius: 10,
          spreadRadius: -1,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: kEmeraldGlow.withValues(alpha: 0.24),
          blurRadius: 16,
          spreadRadius: -2,
          offset: Offset.zero,
        ),
      ];
    }
    return <BoxShadow>[
      BoxShadow(
        color: kEmeraldGlow.withValues(alpha: 0.42),
        blurRadius: 16,
        spreadRadius: 0,
        offset: Offset.zero,
      ),
      BoxShadow(
        color: kEmeraldGlow.withValues(alpha: 0.18),
        blurRadius: 26,
        spreadRadius: 1,
        offset: const Offset(0, 2),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final Widget main = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(
        horizontal: selected ? 8 : 5,
        vertical: selected ? 5 : 3,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: selected ? _selectedFill : Colors.transparent,
        border: Border.all(
          color: selected ? _selectedBorder : Colors.transparent,
        ),
        boxShadow: _selectedShadow,
      ),
      child: icon,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: _accent.withValues(alpha: 0.12),
        highlightColor: variant == _DockNavVariant.dark
            ? Colors.white.withValues(alpha: 0.04)
            : kPineGreen.withValues(alpha: 0.06),
        child: Padding(
          padding: EdgeInsets.zero,
          child: Tooltip(
            message: label,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  main,
                  if (selected)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.montserrat(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          height: 1.05,
                          color: _accent,
                          letterSpacing: -0.1,
                          shadows: variant == _DockNavVariant.dark
                              ? <Shadow>[
                                  Shadow(
                                    color: kPortalGold.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    offset: Offset.zero,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LightDockNavBar extends StatelessWidget {
  const _LightDockNavBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.labels,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<String> labels;

  static const BorderRadius _topRadius = BorderRadius.vertical(
    top: Radius.circular(20),
  );

  /// Неактивные иконки: контраст к лесу и к полупрозрачной белой панели.
  static const Color _inactiveIcon = Color(0xFF4A5D46);

  Widget _chatIcon({required bool selected}) {
    final Color c = selected ? kPineGreen : _inactiveIcon;
    final IconData shape = selected
        ? Icons.chat_bubble_rounded
        : Icons.chat_bubble_outline;
    final Widget raw = Icon(shape, color: c, size: 24);
    return ValueListenableBuilder<bool>(
      valueListenable: ChatUnreadBadge.hasUnread,
      builder: (BuildContext context, bool v, _) {
        return Badge(
          isLabelVisible: v,
          backgroundColor: const Color(0xFFE53935),
          alignment: Alignment.topRight,
          offset: selected ? const Offset(4, -4) : const Offset(3, -5),
          child: raw,
        );
      },
    );
  }

  Widget _profileIcon({required bool selected}) {
    final Color c = selected ? kPineGreen : _inactiveIcon;
    return SizedBox(
      height: 26,
      width: 32,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: <Widget>[
          Icon(
            selected ? Icons.person_rounded : Icons.person_outline_rounded,
            color: c,
            size: 24,
          ),
          Positioned(
            right: -1,
            top: -2,
            child: Icon(Icons.auto_awesome, size: 10.5, color: c),
          ),
        ],
      ),
    );
  }

  Widget _iconForIndex(int index, {required bool selected}) {
    return switch (index) {
      0 => Icon(
        selected ? Icons.home_rounded : Icons.home_outlined,
        color: selected ? kPineGreen : _inactiveIcon,
        size: 24,
      ),
      1 => Icon(
        selected ? Icons.schedule_rounded : Icons.schedule_outlined,
        color: selected ? kPineGreen : _inactiveIcon,
        size: 24,
      ),
      2 => Icon(
        selected ? Icons.grid_view_rounded : Icons.grid_view_outlined,
        color: selected ? kPineGreen : _inactiveIcon,
        size: 24,
      ),
      3 => _chatIcon(selected: selected),
      4 => _profileIcon(selected: selected),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final Widget dock = SizedBox(
      width: double.infinity,
      child: ClipRRect(
        borderRadius: _topRadius,
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: _topRadius,
            color: Colors.white.withValues(alpha: 0.96),
            border: Border(
              top: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List<Widget>.generate(labels.length, (int i) {
                return Expanded(
                  child: _DockNavTile(
                    selected: selectedIndex == i,
                    label: labels[i],
                    icon: _iconForIndex(i, selected: selectedIndex == i),
                    onTap: () => onDestinationSelected(i),
                    variant: _DockNavVariant.light,
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );

    return SafeArea(top: false, minimum: EdgeInsets.zero, child: dock);
  }
}
