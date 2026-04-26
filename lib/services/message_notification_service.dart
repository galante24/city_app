import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_ready.dart';
import 'chat_service.dart';
import 'notification_prefs.dart';
import 'open_chat_tracker.dart';

/// Локальные уведомления о новых входящих сообщениях (Realtime + flutter_local_notifications).
class MessageNotificationService {
  MessageNotificationService._();
  static final MessageNotificationService instance =
      MessageNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  RealtimeChannel? _channel;
  bool _started = false;
  int _idCounter = 0;

  Future<void> init() async {
    if (kIsWeb) {
      return;
    }
    if (Platform.isAndroid) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'chat_messages',
        'Сообщения',
        description: 'Уведомления о новых сообщениях в чатах',
        importance: Importance.high,
        showBadge: true,
      );
      final AndroidFlutterLocalNotificationsPlugin? android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(channel);
    }
    const AndroidInitializationSettings android = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const DarwinInitializationSettings ios = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      final IOSFlutterLocalNotificationsPlugin? iosP = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      await iosP?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  int _nextNotifyId() {
    _idCounter = (_idCounter + 1) & 0x3fffffff;
    if (_idCounter == 0) {
      _idCounter = 1;
    }
    return _idCounter;
  }

  Future<void> _onMessageInsert(PostgresChangePayload payload) async {
    if (kIsWeb) {
      return;
    }
    if (!supabaseAppReady) {
      return;
    }
    if (await NotificationPrefs.areGloballyDisabled()) {
      return;
    }
    final Map<String, dynamic> rec = Map<String, dynamic>.from(
      payload.newRecord as Map<dynamic, dynamic>,
    );
    final String? convId = rec['conversation_id']?.toString();
    final String? senderId = rec['sender_id']?.toString();
    if (convId == null || senderId == null) {
      return;
    }
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null || senderId == me) {
      return;
    }
    if (OpenChatTracker.isThisChatOpen(convId)) {
      return;
    }
    if (await NotificationPrefs.isConversationMuted(convId)) {
      return;
    }
    String body = (rec['body'] as String?)?.trim() ?? '';
    if (body.startsWith(ChatService.imageMessagePrefix)) {
      body = '📷 Фото';
    }
    if (body.isEmpty) {
      body = 'Новое сообщение';
    }
    if (body.length > 180) {
      body = '${body.substring(0, 177)}…';
    }
    unawaited(_showForConversation(convId, body));
  }

  Future<void> _showForConversation(String conversationId, String body) async {
    try {
      final String title = await ChatService.titleForNotification(
        conversationId,
      );
      const AndroidNotificationDetails android = AndroidNotificationDetails(
        'chat_messages',
        'Сообщения',
        channelDescription: 'Входящие сообщения',
        importance: Importance.max,
        priority: Priority.high,
      );
      const DarwinNotificationDetails ios = DarwinNotificationDetails();
      const NotificationDetails details = NotificationDetails(
        android: android,
        iOS: ios,
      );
      await _plugin.show(_nextNotifyId(), title, body, details);
    } on Object {
      /* сеть/RLS: не падаем */
    }
  }

  void start() {
    if (kIsWeb || !supabaseAppReady || _started) {
      return;
    }
    _started = true;
    final SupabaseClient client = Supabase.instance.client;
    _channel = client.channel('message_notification_inserts');
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          callback: (PostgresChangePayload p) {
            unawaited(_onMessageInsert(p));
          },
        )
        .subscribe();
  }
}
