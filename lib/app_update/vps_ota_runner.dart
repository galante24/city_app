import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_secrets.dart';
import '../services/ota/ota_models.dart';
import '../services/ota/vps_ota_service.dart';
import '../widgets/ota/ota_vps_update_dialog.dart';

/// Проверка OTA с VPS: только при [kUpdateManifestUrl] и [Platform.isAndroid] (см. [runVpsOtaFromPostFrame]).
Future<void> runVpsOtaIfConfigured(BuildContext context) async {
  if (kUpdateManifestUrl.trim().isEmpty) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  try {
    final PackageInfo info = await PackageInfo.fromPlatform();
    final int local = int.tryParse(info.buildNumber) ?? 0;
    final OtaUpdateManifest? raw = await VpsOtaService.loadManifest();
    if (raw == null) {
      return;
    }
    final OtaUpdateManifest? update = VpsOtaService.filterByLocalBuild(
      m: raw,
      localCode: local,
    );
    if (update == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    final String localLabel = '${info.version} (${info.buildNumber})';
    await showOtaVpsUpdateDialog(
      context,
      localLabel: localLabel,
      localBuildCode: local,
      manifest: update,
    );
  } on OtaException catch (e) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('OTA manifest: $e');
    }
  } on Object catch (e) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('OTA: $e');
    }
  }
}
