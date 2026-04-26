import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_navigator_key.dart';
import '../screens/share_text_to_chat_screen.dart';

/// Текст из системного меню «Поделиться», пока пользователь не отправил в чат.
class IncomingShareBus {
  IncomingShareBus._();

  static String? pendingText;

  static String? extractText(List<SharedMediaFile> list) {
    if (list.isEmpty) {
      return null;
    }
    for (final SharedMediaFile f in list) {
      if (f.type == SharedMediaType.text && f.path.isNotEmpty) {
        return f.path;
      }
      if (f.type == SharedMediaType.url && f.path.isNotEmpty) {
        return f.path;
      }
    }
    return null;
  }
}

/// Подписка на [ReceiveSharingIntent] (Android / iOS).
class IncomingShareCoordinator {
  IncomingShareCoordinator._();

  static bool _inited = false;

  static Future<void> init() async {
    if (kIsWeb || _inited) {
      return;
    }
    _inited = true;
    try {
      final List<SharedMediaFile> initial =
          await ReceiveSharingIntent.instance.getInitialMedia();
      final String? t = IncomingShareBus.extractText(initial);
      if (t != null && t.trim().isNotEmpty) {
        IncomingShareBus.pendingText = t.trim();
      }
      await ReceiveSharingIntent.instance.reset();
    } on Object {
      // плагин может быть недоступен на десктопе и т.д.
    }

    ReceiveSharingIntent.instance.getMediaStream().listen((
      List<SharedMediaFile> list,
    ) async {
      final String? t = IncomingShareBus.extractText(list);
      if (t == null || t.trim().isEmpty) {
        return;
      }
      IncomingShareBus.pendingText = t.trim();
      try {
        await ReceiveSharingIntent.instance.reset();
      } on Object {
        // ignore
      }
      tryFlushPendingShare();
    });
  }

  /// Вызов после входа и из [MainScaffold] в post-frame.
  static void tryFlushPendingShare() {
    if (kIsWeb) {
      return;
    }
    final BuildContext? ctx = rootNavigatorKey.currentContext;
    if (ctx == null) {
      return;
    }
    final String? raw = IncomingShareBus.pendingText;
    if (raw == null || raw.isEmpty) {
      return;
    }
    if (Supabase.instance.client.auth.currentSession == null) {
      return;
    }
    IncomingShareBus.pendingText = null;
    unawaited(
      Navigator.of(ctx).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (BuildContext c) => ShareTextToChatScreen(sharedText: raw),
        ),
      ),
    );
  }
}
