import 'package:shared_preferences/shared_preferences.dart';

/// Локальный кэш каналов уведомлений (дублирует [profiles] до синхронизации).
abstract final class NotificationChannelPrefs {
  static const String _kChat = 'profile_notify_chat_messages';
  static const String _kFeed = 'profile_notify_feed_engagement';
  static const String _kNews = 'profile_notify_news_feed';

  static Future<void> saveLocal({
    required bool chat,
    required bool feed,
    required bool news,
  }) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setBool(_kChat, chat);
    await p.setBool(_kFeed, feed);
    await p.setBool(_kNews, news);
  }

  static Future<void> applyFromProfileRow(Map<String, dynamic>? row) async {
    if (row == null) {
      return;
    }
    await saveLocal(
      chat: row['notify_chat_messages'] != false,
      feed: row['notify_feed_engagement'] != false,
      news: row['notify_news_feed'] != false,
    );
  }

  /// Значения по умолчанию true, если в prefs ещё не писали.
  static Future<({bool chat, bool feed, bool news})> readLocal() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    return (
      chat: p.getBool(_kChat) ?? true,
      feed: p.getBool(_kFeed) ?? true,
      news: p.getBool(_kNews) ?? true,
    );
  }
}
