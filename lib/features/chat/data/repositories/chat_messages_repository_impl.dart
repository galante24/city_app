import 'package:uuid/uuid.dart';

import '../../../../core/auth/auth_port.dart';
import '../../domain/chat_message.dart';
import '../../domain/chat_message_row_event.dart';
import '../../domain/chat_messages_repository.dart';
import '../datasources/chat_messages_remote_datasource.dart';

class ChatMessagesRepositoryImpl implements ChatMessagesRepository {
  ChatMessagesRepositoryImpl(this._ds, this._auth);

  final ChatMessagesRemoteDataSource _ds;
  final AuthPort _auth;

  @override
  Future<List<ChatMessage>> fetchMessagesPage({
    required String conversationId,
    int limit = 50,
    String? beforeCreatedAtIso,
  }) {
    return _ds.fetchMessagesPage(
      conversationId: conversationId,
      limit: limit,
      beforeCreatedAtIso: beforeCreatedAtIso,
    );
  }

  @override
  Future<ChatMessage?> fetchMessageById(
    String messageId, {
    required String conversationId,
  }) {
    return _ds.fetchMessageById(
      messageId,
      conversationId: conversationId,
    );
  }

  @override
  Stream<ChatMessageRowEvent> watchChatMessageRows(String conversationId) {
    return _ds.watchChatMessageRows(conversationId);
  }

  @override
  Future<void> sendTextMessage({
    required String conversationId,
    required String body,
    String? forwardedFromUserId,
    String? forwardedFromLabel,
    String? replyToMessageId,
    String? replySnippet,
    String? replyAuthorId,
    String? replyAuthorLabel,
  }) async {
    final String? uid = _auth.currentUserId;
    if (uid == null) {
      throw StateError('Нет сессии');
    }
    await _ds.sendTextMessage(
      conversationId: conversationId,
      senderId: uid,
      body: body,
      clientRequestId: const Uuid().v4(),
      forwardedFromUserId: forwardedFromUserId,
      forwardedFromLabel: forwardedFromLabel,
      replyToMessageId: replyToMessageId,
      replySnippet: replySnippet,
      replyAuthorId: replyAuthorId,
      replyAuthorLabel: replyAuthorLabel,
    );
  }

  @override
  Future<void> sendVoiceMessage({
    required String conversationId,
    required String filePath,
    required int durationMs,
    String? replyToMessageId,
    String? replySnippet,
    String? replyAuthorId,
    String? replyAuthorLabel,
  }) async {
    final String? uid = _auth.currentUserId;
    if (uid == null) {
      throw StateError('Нет сессии');
    }
    await _ds.sendVoiceMessage(
      conversationId: conversationId,
      senderId: uid,
      filePath: filePath,
      durationMs: durationMs,
      replyToMessageId: replyToMessageId,
      replySnippet: replySnippet,
      replyAuthorId: replyAuthorId,
      replyAuthorLabel: replyAuthorLabel,
    );
  }

  @override
  Future<void> ackMessageDelivery({
    required String conversationId,
    required String messageId,
  }) {
    return _ds.ackMessageDelivery(
      conversationId: conversationId,
      messageId: messageId,
    );
  }

  @override
  Future<void> softDeleteMessage(String messageId) {
    return _ds.softDeleteMessage(messageId);
  }
}
