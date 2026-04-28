import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_ready.dart';
import '../widgets/app_update_dialog.dart';

/// Обновление по таблице [app_config]. Строка `id = 'default'`.
///
/// Колонки: `version_code`, `download_url`, `apk_url`, `version`, `force_update`.
/// Ссылку на установку берём из `apk_url`, если пусто — из `download_url`.
Future<void> checkForAppUpdateViaSupabase(BuildContext context) async {
  if (!supabaseAppReady) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  try {
    final PackageInfo info = await PackageInfo.fromPlatform();
    final int local = int.tryParse(info.buildNumber) ?? 0;
    final String localLabel = '${info.version} (${info.buildNumber})';

    final Map<String, dynamic>? row = await Supabase.instance.client
        .from('app_config')
        .select('version_code, download_url, apk_url, version, force_update')
        .eq('id', 'default')
        .maybeSingle();
    if (row == null) {
      return;
    }
    final Object? vc = row['version_code'];
    final int? remote = vc is int ? vc : int.tryParse(vc.toString().trim());
    final String? apkUrlPrimary =
        _nonEmpty(row['apk_url']) ?? _nonEmpty(row['download_url']);

    final bool forced = row['force_update'] == true;
    final String? vr = _nonEmpty(row['version']);

    if (apkUrlPrimary == null || apkUrlPrimary.isEmpty) {
      return;
    }

    final bool newerBuildAvailable = remote != null && remote > local;
    if (!newerBuildAvailable) {
      return;
    }

    if (!context.mounted) {
      return;
    }
    await showAppUpdateDialog(
      context,
      localLabel: localLabel,
      remoteBuildCode: remote,
      apkUrl: apkUrlPrimary,
      remoteVersionLabel: vr,
      forceUpdate: forced,
    );
  } on Object {
    // Сеть/tаблица — не блокируем запуск
  }
}

String? _nonEmpty(Object? raw) {
  if (raw == null) return null;
  final String s = raw.toString().trim();
  return s.isEmpty ? null : s;
}
