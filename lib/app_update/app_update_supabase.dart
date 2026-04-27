import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_ready.dart';
import '../widgets/app_update_dialog.dart';

/// Проверка по таблице [app_config] (legacy), если OTA по [UPDATE_MANIFEST_URL] не настроен.
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
        .select('version_code, download_url')
        .eq('id', 'default')
        .maybeSingle();
    if (row == null) {
      return;
    }
    final Object? vc = row['version_code'];
    final int? remote = vc is int ? vc : int.tryParse(vc.toString().trim());
    if (remote == null || remote <= local) {
      return;
    }
    final String? downloadUrl = row['download_url'] as String?;
    final String url = downloadUrl == null ? '' : downloadUrl.trim();
    if (url.isEmpty) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    await showAppUpdateDialog(
      context,
      localLabel: localLabel,
      remoteBuildCode: remote,
      downloadUrl: url,
    );
  } on Object {
    // сеть/таблица — не мешаем запуску
  }
}
