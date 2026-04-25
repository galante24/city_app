import 'package:flutter/material.dart';

/// Текущий индекс нижнего меню (для отложенной загрузки вкладок).
class MainTabIndex extends InheritedWidget {
  const MainTabIndex({super.key, required this.index, required super.child});

  final int index;

  static int? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<MainTabIndex>()?.index;
  }

  @override
  bool updateShouldNotify(covariant MainTabIndex o) {
    return index != o.index;
  }
}
