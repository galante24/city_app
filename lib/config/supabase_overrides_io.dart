import 'dart:convert';
import 'dart:io';

/// `api_keys.json` в текущей рабочей директории (как при `flutter run` из корня проекта).
Future<Map<String, String>?> readApiKeysJsonFromProjectRoot() async {
  try {
    final File f = File('api_keys.json');
    if (!await f.exists()) {
      return null;
    }
    final Object? decoded = jsonDecode(await f.readAsString());
    if (decoded is! Map) {
      return null;
    }
    final Map<dynamic, dynamic> m = decoded;
    final String? u = m['SUPABASE_URL']?.toString();
    final String? k = m['SUPABASE_ANON_KEY']?.toString();
    if (u == null || k == null) {
      return null;
    }
    return <String, String>{
      'SUPABASE_URL': u.trim(),
      'SUPABASE_ANON_KEY': k.trim(),
    };
  } on Object {
    return null;
  }
}
