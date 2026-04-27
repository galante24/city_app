// Классификация локальных данных (в проекте нет Drift/Hive для чатов):
//
// Публичные / допустимые в SharedPreferences: тема, onboarding, mute-списки.
// Сессия Supabase: FlutterSecureStorage через кастомный LocalStorage.
// При добавлении локальной БД: не класть токены в plaintext-таблицы.

library;
