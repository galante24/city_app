import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_ready.dart';
import 'chat_service.dart';

/// Бейдж «есть непрочитанные» на вкладке «Чаты»: RPC + Realtime.
class ChatUnreadBadge {
  ChatUnreadBadge._();

  static final ValueNotifier<bool> hasUnread = ValueNotifier<bool>(false);

  static RealtimeChannel? _channel;
  static bool _started = false;
  static Timer? _refreshDebounce;

  static Future<void> refresh() async {
    if (!supabaseAppReady) {
      hasUnread.value = false;
      return;
    }
    hasUnread.value = await ChatService.fetchHasUnreadMessages();
  }

  static void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 200), () {
      unawaited(refresh());
    });
  }

  static void start() {
    if (!supabaseAppReady || _started) {
      return;
    }
    _started = true;
    unawaited(refresh());
    final SupabaseClient client = Supabase.instance.client;
    _channel = client.channel('chat_unread_badge');
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          callback: (PostgresChangePayload _) {
            _scheduleRefresh();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'conversation_participants',
          callback: (PostgresChangePayload _) {
            _scheduleRefresh();
          },
        )
        .subscribe();
  }

  static void resetOnLogout() {
    // ignore: unawaited_futures
    _channel?.unsubscribe();
    _channel = null;
    _started = false;
    _refreshDebounce?.cancel();
    hasUnread.value = false;
  }
}
