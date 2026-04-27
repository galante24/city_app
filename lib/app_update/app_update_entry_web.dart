import 'package:flutter/material.dart';

import 'app_update_supabase.dart';

Future<void> checkForAppUpdates(BuildContext context) {
  return checkForAppUpdateViaSupabase(context);
}
