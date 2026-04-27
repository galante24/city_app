import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// PKCE / вспомогательные ключи GoTrue в защищённом хранилище (не SharedPreferences).
class SecureGotrueAsyncStorage extends GotrueAsyncStorage {
  SecureGotrueAsyncStorage();

  static const FlutterSecureStorage _s = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  @override
  Future<String?> getItem({required String key}) => _s.read(key: key);

  @override
  Future<void> removeItem({required String key}) => _s.delete(key: key);

  @override
  Future<void> setItem({
    required String key,
    required String value,
  }) =>
      _s.write(key: key, value: value);
}

/// Сессия Supabase в [FlutterSecureStorage]. Для **web** оставляем поведение пакета (ограничения браузера).
class SecureSupabaseLocalStorage extends LocalStorage {
  SecureSupabaseLocalStorage({required this.persistSessionKey});

  final String persistSessionKey;

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async {
    final String? v = await _storage.read(key: persistSessionKey);
    return v != null && v.isNotEmpty;
  }

  @override
  Future<String?> accessToken() => _storage.read(key: persistSessionKey);

  @override
  Future<void> removePersistedSession() =>
      _storage.delete(key: persistSessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: persistSessionKey, value: persistSessionString);
}

/// [LocalStorage] для сессии: на iOS/Android/desktop — Keychain/Keystore; на web — SharedPreferences.
LocalStorage createAuthLocalStorage(String persistSessionKey) {
  if (kIsWeb) {
    return SharedPreferencesLocalStorage(persistSessionKey: persistSessionKey);
  }
  return SecureSupabaseLocalStorage(persistSessionKey: persistSessionKey);
}

GotrueAsyncStorage createPkceAsyncStorage() {
  if (kIsWeb) {
    return SharedPreferencesGotrueAsyncStorage();
  }
  return SecureGotrueAsyncStorage();
}
