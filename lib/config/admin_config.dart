import 'app_secrets.dart';

/// Email-ы админов **только** для UI (кнопки, подсказки). Реальные права — в RLS/политиках Supabase.
Set<String> get kAdministratorEmails {
  if (kAdminEmailsEnv.isEmpty) {
    return <String>{};
  }
  return kAdminEmailsEnv
      .split(',')
      .map((String e) => e.trim().toLowerCase())
      .where((String e) => e.isNotEmpty)
      .toSet();
}

const String kAdministratorEmailHint = 'admin@example.com';
