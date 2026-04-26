import 'package:shared_preferences/shared_preferences.dart';

const String _kGlobalOff = 'notifications_globally_disabled';
const String _kMuted = 'notification_muted_conversation_ids';

class NotificationPrefs {
  NotificationPrefs._();

  static Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  /// Если true — пуш-уведомления о сообщениях не показываются.
  static Future<bool> areGloballyDisabled() async {
    final SharedPreferences p = await _p;
    return p.getBool(_kGlobalOff) ?? false;
  }

  static Future<void> setGloballyDisabled(bool value) async {
    final SharedPreferences p = await _p;
    await p.setBool(_kGlobalOff, value);
  }

  static Future<Set<String>> _mutedSet() async {
    final SharedPreferences p = await _p;
    return p.getStringList(_kMuted)?.toSet() ?? <String>{};
  }

  static Future<bool> isConversationMuted(String conversationId) async {
    final Set<String> s = await _mutedSet();
    return s.contains(conversationId);
  }

  static Future<Set<String>> allMutedConversationIds() async {
    return _mutedSet();
  }

  static Future<void> setConversationMuted(
    String conversationId,
    bool muted,
  ) async {
    final SharedPreferences p = await _p;
    final Set<String> s = p.getStringList(_kMuted)?.toSet() ?? <String>{};
    if (muted) {
      s.add(conversationId);
    } else {
      s.remove(conversationId);
    }
    await p.setStringList(_kMuted, s.toList());
  }
}
