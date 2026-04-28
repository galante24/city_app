import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_constants.dart';

/// Диалог «Доступно обновление» → открывает [apkUrl] во внешнем браузере/загрузчике (без автоустановки).
Future<void> showAppUpdateDialog(
  BuildContext context, {
  required String localLabel,
  required int remoteBuildCode,
  required String apkUrl,
  String? remoteVersionLabel,
  bool forceUpdate = false,
}) {
  final String suffix =
      remoteVersionLabel != null && remoteVersionLabel.isNotEmpty
      ? '(версия $remoteVersionLabel, сборка №$remoteBuildCode)'
      : '(сборка №$remoteBuildCode)';
  return showDialog<void>(
    context: context,
    barrierDismissible: !forceUpdate,
    builder: (BuildContext dialogContext) {
      return PopScope(
        canPop: !forceUpdate,
        child: AlertDialog(
          title: const Text('Доступно обновление'),
          content: Text(
            'Выпущена новая сборка $suffix.\n'
            'Ваша версия: $localLabel.\n\n'
            'Скачайте APK по ссылке и установите вручную.',
          ),
          actions: <Widget>[
            if (!forceUpdate)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Позже'),
              ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                final Uri uri = Uri.parse(apkUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: kPrimaryBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Обновить'),
            ),
          ],
        ),
      );
    },
  );
}
