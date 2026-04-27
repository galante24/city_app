import 'chat_message.dart';
import 'chat_message_row_event.dart';

/// Доступ к сообщениям одной беседы: снимок + поток **строк** (без прямой подписки UI на канал).
///
/// Реализации: Supabase REST/Realtime, либо свой HTTP + WebSocket (см. datasources).
abstract class ChatMessagesRepository {
  /// Последние [limit] сообщений (от нового к старому в ответе).
  Future<List<ChatMessage>> fetchMessagesPage({
    required String conversationId,
    int limit = 50,
    String? beforeCreatedAtIso,
  });

  /// Одна строка по id (для догрузки оригинала ответа, scroll-to, и т.п.).
  Future<ChatMessage?> fetchMessageById(
    String messageId, {
    required String conversationId,
  });

  /// События с сервера (Realtime / SSE / WS). UI не использует транспорт напрямую.
  Stream<ChatMessageRowEvent> watchChatMessageRows(String conversationId);

  Future<void> sendTextMessage({
    required String conversationId,
    required String body,
    String? forwardedFromUserId,
    String? forwardedFromLabel,
    String? replyToMessageId,
    String? replySnippet,
    String? replyAuthorId,
    String? replyAuthorLabel,
  });

  /// Голосовое (только [BackendMode.rest] + загрузка на VPS; см. [ChatService.sendVoiceMessage]).
  Future<void> sendVoiceMessage({
    required String conversationId,
    required String filePath,
    required int durationMs,
    String? replyToMessageId,
    String? replySnippet,
    String? replyAuthorId,
    String? replyAuthorLabel,
  });

  /// Мягкое удаление (на Supabase — RPC [soft_delete_group_message]).
  Future<void> softDeleteMessage(String messageId);

  /// Подтвердить доставку входящего (REST: POST delivery-ack).
  Future<void> ackMessageDelivery({
    required String conversationId,
    required String messageId,
  });
}
