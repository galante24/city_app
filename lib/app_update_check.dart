import 'package:flutter/material.dart';

import 'app_update/app_update_entry_io.dart' if (dart.library.html) 'app_update/app_update_entry_web.dart' as e;

export 'app_update/app_update_supabase.dart' show checkForAppUpdateViaSupabase;

/// Стартовая проверка: Android + [UPDATE_MANIFEST_URL] → OTA с VPS, иначе (в т.ч. iOS) — Supabase [app_config].
Future<void> checkForAppUpdates(BuildContext context) =>
    e.checkForAppUpdates(context);
