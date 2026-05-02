import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/chat_exceptions.dart';
import '../../domain/chat_message.dart';
import '../../domain/chat_message_row_event.dart';
import 'chat_messages_remote_datasource.dart';

/// Один Realtime-канал на [conversationId] для всех подписчиков (без дублей).
final Map<String, _SupabaseChatRowsRealtimeHub> _supabaseChatRowsHubByConv =
    <String, _SupabaseChatRowsRealtimeHub>{};

class _SupabaseChatRowsRealtimeHub {
  _SupabaseChatRowsRealtimeHub({
    required SupabaseClient client,
    required this.conversationId,
    required void Function() onLastListenerRemoved,
  }) : _client = client,
       _onLastListenerRemoved = onLastListenerRemoved {
    _controller = StreamController<ChatMessageRowEvent>.broadcast(
      onCancel: () {
        if (!_controller.hasListener) {
          _dispose();
        }
      },
    );
    final RealtimeChannel ch = _client.channel('chat_msg_rows:$conversationId');
    _channel = ch;
    ch
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (PostgresChangePayload p) {
            final ChatMessageRowEvent? e =
                SupabaseChatMessagesDataSource._rowEventFromPayload(p);
            if (e != null && !_controller.isClosed) {
              _controller.add(e);
            }
          },
        )
        .subscribe();
  }

  final SupabaseClient _client;
  final String conversationId;
  final void Function() _onLastListenerRemoved;

  RealtimeChannel? _channel;
  late final StreamController<ChatMessageRowEvent> _controller;
  bool _tornDown = false;

  Stream<ChatMessageRowEvent> get stream => _controller.stream;

  void _dispose() {
    if (_tornDown) {
      return;
    }
    _tornDown = true;
    _channel?.unsubscribe();
    _channel = null;
    _onLastListenerRemoved();
    if (!_controller.isClosed) {
      _controller.close();
    }
  }
}

class SupabaseChatMessagesDataSource implements ChatMessagesRemoteDataSource {
  SupabaseChatMessagesDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<List<ChatMessage>> fetchMessagesPage({
    required String conversationId,
    int limit = 50,
    String? beforeCreatedAtIso,
  }) async {
    var q = _client
        .from('chat_messages')
        .select()
        .eq('conversation_id', conversationId);
    if (beforeCreatedAtIso != null && beforeCreatedAtIso.isNotEmpty) {
      q = q.lt('created_at', beforeCreatedAtIso);
    }
    final List<dynamic> rows = await q
        .order('created_at', ascending: false)
        .limit(limit);
    return rows
        .map(
          (dynamic e) =>
              ChatMessage.fromMap(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  @override
  Future<ChatMessage?> fetchMessageById(
    String messageId, {
    required String conversationId,
  }) async {
    final String trimmed = messageId.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final List<dynamic> rows = await _client
        .from('chat_messages')
        .select()
        .eq('id', trimmed)
        .eq('conversation_id', conversationId)
        .limit(1);
    if (rows.isEmpty) {
      return null;
    }
    return ChatMessage.fromMap(Map<String, dynamic>.from(rows.first as Map));
  }

  @override
  Stream<ChatMessageRowEvent> watchChatMessageRows(String conversationId) {
    return _supabaseChatRowsHubByConv
        .putIfAbsent(
          conversationId,
          () => _SupabaseChatRowsRealtimeHub(
            client: _client,
            conversationId: conversationId,
            onLastListenerRemoved: () {
              _supabaseChatRowsHubByConv.remove(conversationId);
            },
          ),
        )
        .stream;
  }

  static ChatMessageRowEvent? _rowEventFromPayload(PostgresChangePayload p) {
    switch (p.eventType) {
      case PostgresChangeEvent.insert:
        final Map<String, dynamic>? n = _asMap(p.newRecord);
        if (n == null) {
          return null;
        }
        return ChatMessageRowEvent.insert(n);
      case PostgresChangeEvent.update:
        final Map<String, dynamic>? n = _asMap(p.newRecord);
        if (n == null) {
          return null;
        }
        return ChatMessageRowEvent.update(
          n,
          _asMap(p.oldRecord) ?? <String, dynamic>{},
        );
      case PostgresChangeEvent.delete:
        final Map<String, dynamic> o =
            _asMap(p.oldRecord) ?? <String, dynamic>{};
        return ChatMessageRowEvent.delete(o);
      default:
        return null;
    }
  }

  static Map<String, dynamic>? _asMap(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  @override
  Future<void> sendTextMessage({
    required String conversationId,
    required String senderId,
    required String body,
    String? clientRequestId,
    String? forwardedFromUserId,
    String? forwardedFromLabel,
    String? replyToMessageId,
    String? replySnippet,
    String? replyAuthorId,
    String? replyAuthorLabel,
  }) async {
    final String t = body.trim();
    if (t.isEmpty) {
      return;
    }
    final Map<String, dynamic> row = <String, dynamic>{
      'conversation_id': conversationId,
      'sender_id': senderId,
      'body': t,
    };
    final String? fwdId = forwardedFromUserId?.trim();
    final String? fwdLabel = forwardedFromLabel?.trim();
    if (fwdId != null &&
        fwdId.isNotEmpty &&
        fwdLabel != null &&
        fwdLabel.isNotEmpty) {
      row['forwarded_from_user_id'] = fwdId;
      row['forwarded_from_label'] = fwdLabel;
    }
    final String? repId = replyToMessageId?.trim();
    if (repId != null && repId.isNotEmpty) {
      row['reply_to_message_id'] = repId;
      final String? sn = replySnippet?.trim();
      if (sn != null && sn.isNotEmpty) {
        row['reply_snippet'] = sn.length > 500 ? sn.substring(0, 500) : sn;
      }
      final String? ra = replyAuthorId?.trim();
      if (ra != null && ra.isNotEmpty) {
        row['reply_author_id'] = ra;
      }
      final String? al = replyAuthorLabel?.trim();
      if (al != null && al.isNotEmpty) {
        row['reply_author_label'] = al.length > 200 ? al.substring(0, 200) : al;
      }
    }
    try {
      await _client.from('chat_messages').insert(row);
    } on PostgrestException catch (e) {
      final String msg = e.message.toLowerCase();
      if (e.code == 'P0001' &&
          (msg.contains('rate') ||
              msg.contains('chat_rate_limited') ||
              msg.contains('limited'))) {
        throw ChatFloodException();
      }
      rethrow;
    }
  }

  @override
  Future<void> ackMessageDelivery({
    required String conversationId,
    required String messageId,
  }) async {}

  @override
  Future<void> sendVoiceMessage({
    required String conversationId,
    required String senderId,
    required String filePath,
    required int durationMs,
    String? replyToMessageId,
    String? replySnippet,
    String? replyAuthorId,
    String? replyAuthorLabel,
  }) async {
    throw UnsupportedError(
      'Голос в режиме Supabase: используйте BACKEND_MODE=rest и API_BASE_URL, '
      'или загрузку в storage вручную.',
    );
  }

  @override
  Future<void> softDeleteMessage(String messageId) async {
    await _client.rpc(
      'soft_delete_group_message',
      params: <String, dynamic>{'p_message_id': messageId},
    );
  }
}
