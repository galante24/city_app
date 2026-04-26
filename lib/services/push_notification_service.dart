import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../firebase_options.dart';
import 'city_data_service.dart';
import 'message_notification_service.dart';
import 'notification_delivery_policy.dart';
import 'notification_navigation_handler.dart';
import 'notification_prefs.dart';
import 'open_chat_tracker.dart';
import 'place_service.dart';

/// FCM: токен в Supabase, foreground/background, открытие чата по тапу.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  String? _lastToken;
  StreamSubscription<AuthState>? _authSub;

  bool get isFirebaseReady =>
      !kIsWeb &&
      DefaultFirebaseOptions.isConfigured &&
      Firebase.apps.isNotEmpty;

  /// Если токен зарегистрирован — дублирующие баннеры из Supabase Realtime отключаем.
  bool get shouldSuppressRealtimeBanner =>
      isFirebaseReady && (_lastToken != null && _lastToken!.isNotEmpty);

  Future<void> initialize() async {
    if (kIsWeb || !DefaultFirebaseOptions.isConfigured) {
      if (kDebugMode) {
        debugPrint(
          '[Push] Пропуск: веб или нет dart-define / firebase_options.',
        );
      }
      return;
    }
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint('[Push] Firebase.initializeApp: ${e.message}');
      }
      return;
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('[Push] Firebase.initializeApp: $e');
      }
      return;
    }

    final FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    if (Platform.isAndroid) {
      await Permission.notification.request();
    }
    final NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    if (kDebugMode) {
      debugPrint('[Push] iOS permission: ${settings.authorizationStatus}');
    }

    await _syncTokenToSupabase();

    FirebaseMessaging.instance.onTokenRefresh.listen((String t) {
      _lastToken = t;
      NotificationDeliveryPolicy.suppressRealtimeChatBanners = true;
      unawaited(PlaceService.updateMyFcmToken(t));
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage m) {
      unawaited(_onForegroundMessage(m));
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage m) {
      unawaited(NotificationNavigationHandler.handleFcmData(m.data));
    });

    final RemoteMessage? initial = await messaging.getInitialMessage();
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(
          NotificationNavigationHandler.handleFcmData(initial.data),
        );
      });
    }

    _authSub?.cancel();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((
      AuthState data,
    ) {
      if (data.session != null) {
        unawaited(CityDataService.refreshNotificationsEnabledCache());
        unawaited(_syncTokenToSupabase());
      } else {
        _lastToken = null;
        NotificationDeliveryPolicy.suppressRealtimeChatBanners = false;
      }
    });
  }

  Future<void> _syncTokenToSupabase() async {
    final Session? session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      return;
    }
    try {
      final String? t = await FirebaseMessaging.instance.getToken();
      if (t != null && t.isNotEmpty) {
        _lastToken = t;
        await PlaceService.updateMyFcmToken(t);
        NotificationDeliveryPolicy.suppressRealtimeChatBanners = true;
      }
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('[Push] getToken: $e');
      }
    }
  }

  Future<void> _onForegroundMessage(RemoteMessage m) async {
    if (!await CityDataService.areNotificationsEnabledForCurrentUser()) {
      return;
    }
    final Map<String, dynamic> data = m.data;
    final String type = data['type']?.toString() ?? '';
    if (type == NotificationNavigationHandler.payloadTypeChat) {
      final String conv = data['conversation_id']?.toString() ?? '';
      if (conv.isEmpty) {
        return;
      }
      if (OpenChatTracker.isThisChatOpen(conv)) {
        return;
      }
      if (await NotificationPrefs.isConversationMuted(conv)) {
        return;
      }
      final String title =
          m.notification?.title ?? data['sender_title']?.toString() ?? 'Чат';
      final String body =
          m.notification?.body ?? data['body_preview']?.toString() ?? '';
      final String navTitle =
          data['chat_title']?.toString() ?? title;
      await MessageNotificationService.instance.showChatNotification(
        title: title,
        body: body.isEmpty ? 'Новое сообщение' : body,
        payload: jsonEncode(<String, dynamic>{
          'type': NotificationNavigationHandler.payloadTypeChat,
          'conversation_id': conv,
          'title': navTitle,
        }),
      );
    } else if (type == NotificationNavigationHandler.payloadTypePlace) {
      final String placeId = data['place_id']?.toString() ?? '';
      if (placeId.isEmpty) {
        return;
      }
      final String title =
          m.notification?.title ?? data['place_title']?.toString() ?? 'Заведение';
      final String body =
          m.notification?.body ?? data['body_preview']?.toString() ?? '';
      await MessageNotificationService.instance.showPlacePostNotification(
        title: title,
        body: body.isEmpty ? 'Новая запись' : body,
        payload: jsonEncode(<String, dynamic>{
          'type': NotificationNavigationHandler.payloadTypePlace,
          'place_id': placeId,
        }),
      );
    }
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    _authSub = null;
  }
}
