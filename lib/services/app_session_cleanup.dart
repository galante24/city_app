import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_ready.dart';
import 'chat_unread_badge.dart';
import 'message_notification_service.dart';

/// Безопасный выход: сессия GoTrue, FCM, realtime-подписки служебных сервисов.
class AppSessionCleanup {
  AppSessionCleanup._();

  static Future<void> signOutEverywhere() async {
    if (!supabaseAppReady) {
      return;
    }
    try {
      await Supabase.instance.client.auth.signOut();
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('signOut: $e');
      }
    }

    MessageNotificationService.instance.resetOnLogout();
    ChatUnreadBadge.resetOnLogout();

    if (kIsWeb) {
      return;
    }
    try {
      await FirebaseMessaging.instance.deleteToken();
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('FCM deleteToken: $e');
      }
    }
  }
}
