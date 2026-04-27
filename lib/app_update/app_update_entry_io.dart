import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../config/app_secrets.dart';
import 'app_update_supabase.dart';
import 'vps_ota_runner.dart';

/// Не вызывать с web/Windows desktop без проверок: web компилируется с другим entry.
Future<void> checkForAppUpdates(BuildContext context) async {
  if (!context.mounted) {
    return;
  }
  if (Platform.isAndroid) {
    if (kUpdateManifestUrl.trim().isNotEmpty) {
      await runVpsOtaIfConfigured(context);
      return;
    }
  }
  await checkForAppUpdateViaSupabase(context);
}
