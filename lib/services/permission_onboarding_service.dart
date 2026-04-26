import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kPermissionOnboardingDone = 'permission_onboarding_v1_done';

/// Первый запуск: пояснение и запрос прав (уведомления, медиа, контакты).
class PermissionOnboardingService {
  PermissionOnboardingService._();

  static Future<bool> isDone() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    return p.getBool(_kPermissionOnboardingDone) ?? false;
  }

  static Future<void> markDone() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setBool(_kPermissionOnboardingDone, true);
  }

  /// Вызывать из [MainScaffold] после авторизации (есть [BuildContext]).
  static Future<void> requestIfNeeded(BuildContext context) async {
    if (kIsWeb) {
      return;
    }
    if (await isDone()) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    final bool? go = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext c) {
        return AlertDialog(
          title: const Text('Доступы'),
          content: const Text(
            'Для полноценной работы нам нужен доступ к уведомлениям и файлам '
            '(фото в профиле, чатах и заведениях), а также к контактам для '
            'социальных функций.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Позже'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Продолжить'),
            ),
          ],
        );
      },
    );
    if (go != true) {
      await markDone();
      return;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      final PermissionStatus n = await Permission.notification.request();
      if (n.isPermanentlyDenied && context.mounted) {
        await _maybeOpenSettingsHint(context);
      }
    }

    if (Platform.isAndroid) {
      await Permission.photos.request();
      if (await Permission.photos.isDenied) {
        await Permission.storage.request();
      }
    } else if (Platform.isIOS) {
      await Permission.photos.request();
    }

    await Permission.contacts.request();

    await markDone();
  }

  static Future<void> _maybeOpenSettingsHint(BuildContext context) async {
    if (!context.mounted) {
      return;
    }
    final bool? open = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Уведомления'),
        content: const Text(
          'Уведомления отключены в настройках системы. Открыть настройки приложения?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Открыть'),
          ),
        ],
      ),
    );
    if (open == true) {
      await openAppSettings();
    }
  }
}
