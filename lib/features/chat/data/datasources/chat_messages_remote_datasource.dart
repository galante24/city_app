import '../../domain/chat_message.dart';
import '../../domain/chat_message_row_event.dart';

/// Низкоуровневый источник сообщений чата: Supabase или HTTP/WSS (VPS).
abstract class ChatMessagesRemoteDataSource {
  Future<List<ChatMessage>> fetchMessagesPage({
    required String conversationId,
    int limit = 50,
    String? beforeCreatedAtIso,
  });

  Future<ChatMessage?> fetchMessageById(
    String messageId, {
    required String conversationId,
  });

  Stream<ChatMessageRowEvent> watchChatMessageRows(String conversationId);

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
  });

  /// Подтвердить доставку чужого сообщения (REST; Supabase — no-op).
  Future<void> ackMessageDelivery({
    required String conversationId,
    required String messageId,
  });

  /// Вложение голоса (VPS/REST: multipart + сообщение; Supabase — legacy или не реализовано).
  Future<void> sendVoiceMessage({
    required String conversationId,
    required String senderId,
    required String filePath,
    required int durationMs,
    String? replyToMessageId,
    String? replySnippet,
    String? replyAuthorId,
    String? replyAuthorLabel,
  });

  Future<void> softDeleteMessage(String messageId);
}
