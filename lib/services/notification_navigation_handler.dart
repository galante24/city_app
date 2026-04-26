import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_navigator_key.dart';
import '../screens/place_detail_screen.dart';
import '../screens/user_chat_thread_screen.dart';

/// Открытие экранов по нажатию на локальное / FCM-уведомление.
class NotificationNavigationHandler {
  NotificationNavigationHandler._();

  static const String payloadTypeChat = 'chat';
  static const String payloadTypePlace = 'place_post';

  /// JSON: { "type": "chat", "conversation_id", "title" } или place_post.
  static Future<void> handlePayload(String? raw) async {
    if (raw == null || raw.isEmpty) {
      return;
    }
    Map<String, dynamic>? map;
    try {
      map = jsonDecode(raw) as Map<String, dynamic>?;
    } on Object {
      return;
    }
    if (map == null) {
      return;
    }
    final String type = map['type']?.toString() ?? '';
    if (type == payloadTypeChat) {
      final String conv = map['conversation_id']?.toString() ?? '';
      final String title = map['title']?.toString() ?? 'Чат';
      if (conv.isEmpty) {
        return;
      }
      await _openChat(conv, title);
    } else if (type == payloadTypePlace) {
      final String placeId = map['place_id']?.toString() ?? '';
      if (placeId.isEmpty) {
        return;
      }
      await _openPlace(placeId);
    }
  }

  static Future<void> handleFcmData(Map<String, dynamic> data) async {
    final String type = data['type']?.toString() ?? '';
    if (type == payloadTypeChat) {
      await handlePayload(jsonEncode(<String, dynamic>{
        'type': payloadTypeChat,
        'conversation_id': data['conversation_id']?.toString() ?? '',
        'title': data['chat_title']?.toString() ?? 'Чат',
      }));
    } else if (type == payloadTypePlace) {
      await handlePayload(jsonEncode(<String, dynamic>{
        'type': payloadTypePlace,
        'place_id': data['place_id']?.toString() ?? '',
      }));
    }
  }

  static Future<void> _openChat(String conversationId, String title) async {
    final NavigatorState? nav = rootNavigatorKey.currentState;
    if (nav == null) {
      return;
    }
    await nav.push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => UserChatThreadScreen(
          conversationId: conversationId,
          title: title,
          listItem: null,
        ),
      ),
    );
  }

  static Future<void> _openPlace(String placeId) async {
    final NavigatorState? nav = rootNavigatorKey.currentState;
    if (nav == null) {
      return;
    }
    await nav.push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => PlaceDetailScreen(placeId: placeId),
      ),
    );
  }
}
