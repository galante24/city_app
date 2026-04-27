import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    show FlutterSecureStorage, IOSOptions, KeychainAccessibility;
import 'package:shared_preferences/shared_preferences.dart';

/// Однократный перенос сессии из старого SharedPreferences в [FlutterSecureStorage].
Future<void> migrateLegacySupabaseSessionToSecure(String persistSessionKey) async {
  if (kIsWeb) {
    return;
  }
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final String? legacy = prefs.getString(persistSessionKey);
  if (legacy == null || legacy.isEmpty) {
    return;
  }
  const FlutterSecureStorage secure = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  final String? existing = await secure.read(key: persistSessionKey);
  if (existing != null && existing.isNotEmpty) {
    await prefs.remove(persistSessionKey);
    return;
  }
  await secure.write(key: persistSessionKey, value: legacy);
  await prefs.remove(persistSessionKey);
}
