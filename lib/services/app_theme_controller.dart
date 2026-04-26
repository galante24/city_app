import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Светлая / тёмная тема: настройки и [SharedPreferences] (`settings_dark_theme`).
final AppThemeController appThemeController = AppThemeController();

class AppThemeController extends ChangeNotifier {
  static const String _prefKey = 'settings_dark_theme';

  ThemeMode _mode = ThemeMode.light;

  ThemeMode get themeMode => _mode;

  bool get useDarkTheme => _mode == ThemeMode.dark;

  Future<void> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final bool dark = p.getBool(_prefKey) ?? false;
    _mode = dark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> setDarkTheme(bool dark) async {
    final ThemeMode next = dark ? ThemeMode.dark : ThemeMode.light;
    if (_mode == next) {
      return;
    }
    _mode = next;
    notifyListeners();
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setBool(_prefKey, dark);
  }
}
