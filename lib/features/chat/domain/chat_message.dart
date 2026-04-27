import 'dart:convert';

import 'package:meta/meta.dart';

import '../api/chat_media_url.dart';

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    this.createdAt,
    this.forwardedFromUserId,
    this.forwardedFromLabel,
    this.replyToMessageId,
    this.replySnippet,
    this.replyAuthorId,
    this.replyAuthorLabel,
    this.deletedAt,
    this.messageType,
    this.mediaUrl,
    this.mediaDurationMs,
    this.deliveryStatus,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String body;
  final String? createdAt;
  final String? forwardedFromUserId;
  final String? forwardedFromLabel;
  final String? replyToMessageId;
  final String? replySnippet;
  final String? replyAuthorId;
  final String? replyAuthorLabel;
  final String? deletedAt;
  /// `text` | `image` | `voice` (сервер) или [legacy] из [body] `!voice:`.
  final String? messageType;
  final String? mediaUrl;
  final int? mediaDurationMs;
  /// `sent` | `delivered` (REST / chat-api).
  final String? deliveryStatus;

  static int? _parseInt(dynamic v) {
    if (v == null) {
      return null;
    }
    if (v is int) {
      return v;
    }
    if (v is num) {
      return v.toInt();
    }
    return int.tryParse(v.toString());
  }

  /// URL для `just_audio` (полный https или через [kApiBaseUrl]).
  static String? voicePlayUrlFromRow(Map<String, dynamic> m) {
    if (m['deleted_at'] != null) {
      return null;
    }
    String? t = m['message_type']?.toString();
    String? u = m['media_url']?.toString();
    if (t == 'voice' && u != null && u.isNotEmpty) {
      return resolveChatMediaUrl(u);
    }
    final LegacyVoice? leg = _parseVoiceLegacy(
      (m['body'] as String?) ?? '',
    );
    if (leg != null) {
      return resolveChatMediaUrl(leg.url);
    }
    return null;
  }

  static int? voiceDurationMsFromRow(Map<String, dynamic> m) {
    if (m['deleted_at'] != null) {
      return null;
    }
    if (m['message_type']?.toString() == 'voice') {
      final int? d = _parseInt(m['media_duration_ms']);
      if (d != null) {
        return d;
      }
    }
    return _parseVoiceLegacy((m['body'] as String?) ?? '')?.durationMs;
  }

  static const String _voiceLegacyPrefix = '!voice:';

  static LegacyVoice? _parseVoiceLegacy(String body) {
    final String t = body.trim();
    if (!t.startsWith(_voiceLegacyPrefix)) {
      return null;
    }
    final String rest = t.substring(_voiceLegacyPrefix.length).trim();
    try {
      final Object? j = json.decode(rest);
      if (j is! Map) {
        return null;
      }
      final String? u = j['u']?.toString();
      if (u == null || u.isEmpty) {
        return null;
      }
      final num? sec = j['s'] is num
          ? j['s'] as num
          : num.tryParse('${j['s']}');
      return LegacyVoice(
        url: u,
        durationMs: sec == null
            ? null
            : (sec * 1000).round().clamp(0, 3600000),
      );
    } on Object {
      return null;
    }
  }

  factory ChatMessage.fromMap(Map<String, dynamic> m) {
    String? msgType = m['message_type'] as String?;
    String? mUrl = m['media_url'] as String?;
    int? mDur = _parseInt(m['media_duration_ms']);
    String body = (m['body'] as String?) ?? '';
    if (msgType == null || msgType.isEmpty) {
      final LegacyVoice? leg = _parseVoiceLegacy(body);
      if (leg != null) {
        msgType = 'voice';
        mUrl = leg.url;
        mDur = leg.durationMs;
      } else {
        msgType = 'text';
      }
    }
    return ChatMessage(
      id: m['id']?.toString() ?? '',
      conversationId: m['conversation_id']?.toString() ?? '',
      senderId: m['sender_id']?.toString() ?? '',
      body: body,
      createdAt: m['created_at']?.toString(),
      forwardedFromUserId: m['forwarded_from_user_id']?.toString(),
      forwardedFromLabel: m['forwarded_from_label'] as String?,
      replyToMessageId: m['reply_to_message_id']?.toString(),
      replySnippet: m['reply_snippet'] as String?,
      replyAuthorId: m['reply_author_id']?.toString(),
      replyAuthorLabel: m['reply_author_label'] as String?,
      deletedAt: m['deleted_at']?.toString(),
      messageType: msgType,
      mediaUrl: mUrl,
      mediaDurationMs: mDur,
      deliveryStatus: m['delivery_status']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'body': body,
      if (createdAt != null) 'created_at': createdAt,
      if (forwardedFromUserId != null) 'forwarded_from_user_id': forwardedFromUserId,
      if (forwardedFromLabel != null) 'forwarded_from_label': forwardedFromLabel,
      if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
      if (replySnippet != null) 'reply_snippet': replySnippet,
      if (replyAuthorId != null) 'reply_author_id': replyAuthorId,
      if (replyAuthorLabel != null) 'reply_author_label': replyAuthorLabel,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (messageType != null) 'message_type': messageType,
      if (mediaUrl != null) 'media_url': mediaUrl,
      if (mediaDurationMs != null) 'media_duration_ms': mediaDurationMs,
      if (deliveryStatus != null) 'delivery_status': deliveryStatus,
    };
  }
}

class LegacyVoice {
  const LegacyVoice({required this.url, this.durationMs});
  final String url;
  final int? durationMs;
}
