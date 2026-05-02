import 'package:flutter/material.dart';

import '../app_constants.dart';

/// Маркер: поля ввода внутри «таблетки» без собственных рамок.
class SettingsTabletFieldScope extends InheritedWidget {
  const SettingsTabletFieldScope({super.key, required super.child});

  static bool borderlessFields(BuildContext context) {
    return context.getInheritedWidgetOfExactType<SettingsTabletFieldScope>() !=
        null;
  }

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) => false;
}

/// Стандартная карточка настроек / профиля: скругление 26px, без blur.
class SettingsTabletCard extends StatelessWidget {
  const SettingsTabletCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = dark
        ? const Color(0xFF121820).withValues(alpha: 0.88)
        : Colors.white.withValues(alpha: 0.85);
    final Color border = dark
        ? Colors.white.withValues(alpha: 0.1)
        : kPineGreen.withValues(alpha: 0.1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SettingsTabletFieldScope(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: border),
          ),
          child: Padding(
            padding: padding,
            child: Theme(
              data: Theme.of(context).copyWith(
                inputDecorationTheme: const InputDecorationTheme(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  filled: false,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
