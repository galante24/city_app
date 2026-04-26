import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_constants.dart';

/// Диалог «Доступно обновление» с переходом по [downloadUrl].
Future<void> showAppUpdateDialog(
  BuildContext context, {
  required String localLabel,
  required int remoteBuildCode,
  required String downloadUrl,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Доступно обновление'),
        content: Text(
          'Выпущена новая сборка (№$remoteBuildCode). '
          'Ваша версия: $localLabel.\n\n'
          'Скачайте и установите APK по ссылке.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Позже'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final Uri uri = Uri.parse(downloadUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: kPrimaryBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Скачать'),
          ),
        ],
      );
    },
  );
}
