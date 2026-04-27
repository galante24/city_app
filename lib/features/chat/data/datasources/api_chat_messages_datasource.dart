import 'package:dio/dio.dart';
import 'package:path/path.dart' as path_lib;
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../../../../config/app_secrets.dart';
import '../../../../core/auth/auth_port.dart';
import '../../domain/chat_exceptions.dart';
import '../../domain/chat_message.dart';
import '../../domain/chat_message_row_event.dart';
import '../api/chat_realtime_hub.dart';
import 'chat_messages_remote_datasource.dart';

/// REST + WebSocket, совместим с [ChatMessage.toMap] и chat-api (Nest/ваш FastAPI).
class ApiChatMessagesDataSource implements ChatMessagesRemoteDataSource {
  ApiChatMessagesDataSource({
    required this.baseUrl,
    required this.auth,
    ChatMessagesRealtimeHub? hub,
  }) : _hub = hub ?? ChatMessagesRealtimeHub(baseUrl: baseUrl, auth: auth);

  final String baseUrl;
  final AuthPort auth;
  final ChatMessagesRealtimeHub _hub;

  static final Map<String, _ListCache> _listCache = <String, _ListCache>{};

  String get _root => baseUrl.replaceAll(RegExp(r'/$'), '');
  String get _v1 => '$_root/v1';

  late final Dio _dio = _buildDio();

  Dio _buildDio() {
    final Dio d = Dio(
      BaseOptions(
        baseUrl: _v1,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 1),
        validateStatus: (int? c) => c != null && c < 500,
        headers: <String, String>{'Content-Type': 'application/json'},
      ),
    );
    d.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions o, handler) async {
          if (kChatApiBearer.isNotEmpty) {
            o.headers['Authorization'] = 'Bearer $kChatApiBearer';
          } else {
            final String? t = await auth.getChatApiAccessToken();
            if (t == null || t.isEmpty) {
              return handler.reject(
                DioException(
                  requestOptions: o,
                  error: 'Нет access token (CHAT_API_BEARER / сессия)',
                  type: DioExceptionType.unknown,
                ),
              );
            }
            o.headers['Authorization'] = 'Bearer $t';
          }
          if (o.data is! FormData) {
            o.headers['Content-Type'] = Headers.jsonContentType;
          } else {
            o.headers.remove('Content-Type');
          }
          return handler.next(o);
        },
        onResponse: (Response<dynamic> r, ResponseInterceptorHandler h) async {
          if (r.statusCode != 401) {
            return h.next(r);
          }
          final RequestOptions o = r.requestOptions;
          if (o.extra['__authRetried__'] == true) {
            return h.next(r);
          }
          if (kChatApiBearer.isNotEmpty) {
            return h.next(r);
          }
          final bool ok = await auth.refreshChatApiSession();
          if (!ok) {
            return h.next(r);
          }
          o.extra['__authRetried__'] = true;
          final String? t = await auth.getChatApiAccessToken();
          if (t == null || t.isEmpty) {
            return h.next(r);
          }
          o.headers['Authorization'] = 'Bearer $t';
          try {
            final Response<dynamic> res = await d.fetch<dynamic>(o);
            return h.resolve(res);
          } on DioException catch (e) {
            return h.reject(e);
          }
        },
        onError: (DioException e, handler) {
          if (kDebugMode) {
            // ignore: avoid_print
            print(
              '[ChatAPI] ${e.requestOptions.method} ${e.requestOptions.uri} ${e.message}',
            );
          }
          return handler.next(e);
        },
      ),
    );
    return d;
  }

  void _throwForResponse(int? code, Object? data) {
    if (data is Map && data['error'] is Map) {
      final Map<dynamic, dynamic> err =
          data['error']! as Map<dynamic, dynamic>;
      final String? co = err['code']?.toString();
      final String msg = err['message']?.toString() ?? 'Ошибка API';
      if (code == 429) {
        throw ChatFloodException();
      }
      throw ChatApiException(msg, code: co, statusCode: code);
    }
    if (code == 429) {
      throw ChatFloodException();
    }
    if (code == 400 || code == 403 || code == 404) {
      throw ChatApiException('HTTP $code', statusCode: code);
    }
    throw ChatApiException('HTTP ${code ?? "?"}', statusCode: code);
  }

  String _key(String c, int l, String? b) => '$c|$l|${b ?? ""}';

  @override
  Future<List<ChatMessage>> fetchMessagesPage({
    required String conversationId,
    int limit = 50,
    String? beforeCreatedAtIso,
  }) async {
    final String k = _key(conversationId, limit, beforeCreatedAtIso);
    final int now = DateTime.now().millisecondsSinceEpoch;
    final _ListCache? c = _listCache[k];
    if (c != null && now - c.atMs < 2000) {
      return c.items;
    }
    try {
      final Response<dynamic> r = await _dio.get(
        'conversations/$conversationId/messages',
        queryParameters: <String, dynamic>{
          'limit': limit,
          if (beforeCreatedAtIso != null && beforeCreatedAtIso.isNotEmpty)
            'before': beforeCreatedAtIso,
        },
      );
      if (r.statusCode != 200) {
        _throwForResponse(r.statusCode, r.data);
      }
      final Object? d = r.data;
      if (d is! Map) {
        throw ChatApiException('list: неверный JSON');
      }
      final Object? it = d['items'];
      if (it is! List) {
        throw ChatApiException('list: нет items');
      }
      final List<ChatMessage> out = <ChatMessage>[];
      for (final Object? e in it) {
        if (e is Map) {
          out.add(ChatMessage.fromMap(_norm(e)));
        }
      }
      _listCache[k] = _ListCache(out, now);
      _listCache['fallback::$conversationId'] = _ListCache(out, now);
      return out;
    } on DioException catch (e) {
      if (_isNetwork(e)) {
        final _ListCache? f = _listCache['fallback::$conversationId'];
        if (f != null) {
          if (kDebugMode) {
            // ignore: avoid_print
            print('[ChatAPI] list fallback: ${e.type}');
          }
          return f.items;
        }
        throw ChatApiNetworkException(e.type.toString());
      }
      rethrow;
    } on ChatApiException {
      rethrow;
    } on Object catch (e) {
      throw ChatApiException(e.toString());
    } finally {
      _pruneListCache();
    }
  }

  @override
  Future<ChatMessage?> fetchMessageById(
    String messageId, {
    required String conversationId,
  }) async {
    try {
      final Response<dynamic> r = await _dio.get(
        'conversations/$conversationId/messages/$messageId',
      );
      if (r.statusCode == 404) {
        return null;
      }
      if (r.statusCode != 200) {
        _throwForResponse(r.statusCode, r.data);
      }
      if (r.data is! Map) {
        return null;
      }
      return ChatMessage.fromMap(_norm(r.data! as Map<dynamic, dynamic>));
    } on DioException catch (e) {
      if (_isNetwork(e)) {
        return null;
      }
      rethrow;
    } on Object {
      rethrow;
    }
  }

  @override
  Stream<ChatMessageRowEvent> watchChatMessageRows(String conversationId) {
    return _hub.events(conversationId);
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
    if (auth.currentUserId != null && auth.currentUserId != senderId) {
      if (kDebugMode) {
        // ignore: avoid_print
        print(
          '[ChatAPI] send: senderId != currentUser, продолжение с id из репозитория',
        );
      }
    }
    final Map<String, dynamic> p = <String, dynamic>{'body': body};
    if (clientRequestId != null && clientRequestId.isNotEmpty) {
      p['client_request_id'] = clientRequestId;
    }
    if (forwardedFromUserId != null) {
      p['forwarded_from_user_id'] = forwardedFromUserId;
    }
    if (forwardedFromLabel != null) {
      p['forwarded_from_label'] = forwardedFromLabel;
    }
    if (replyToMessageId != null) {
      p['reply_to_message_id'] = replyToMessageId;
    }
    if (replySnippet != null) {
      p['reply_snippet'] = replySnippet;
    }
    if (replyAuthorId != null) {
      p['reply_author_id'] = replyAuthorId;
    }
    if (replyAuthorLabel != null) {
      p['reply_author_label'] = replyAuthorLabel;
    }
    try {
      final Response<dynamic> r = await _dio.post(
        'conversations/$conversationId/messages',
        data: p,
      );
      if (r.statusCode == 201 || r.statusCode == 200) {
        final Object? m = (r.data is Map) ? (r.data as Map)['message'] : r.data;
        if (m is Map) {
          final List<ChatMessage> conv = <ChatMessage>[
            ChatMessage.fromMap(_norm(Map<dynamic, dynamic>.from(m))),
          ];
          _listCache['fallback::$conversationId'] = _ListCache(
            conv,
            DateTime.now().millisecondsSinceEpoch,
          );
        }
        return;
      }
      _throwForResponse(r.statusCode, r.data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        throw ChatFloodException();
      }
      if (_isNetwork(e)) {
        throw ChatApiNetworkException(e.type.toString());
      }
      rethrow;
    }
  }

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
    if (auth.currentUserId != null && auth.currentUserId != senderId) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[ChatAPI] sendVoice: senderId != currentUser');
      }
    }
    final String name = path_lib.basename(filePath);
    final FormData form = FormData.fromMap(<String, dynamic>{
      'file': await MultipartFile.fromFile(
        filePath,
        filename: name,
      ),
    });
    final Response<dynamic> up;
    try {
      up = await _dio.post<dynamic>(
        'upload/voice',
        data: form,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        throw ChatFloodException();
      }
      if (_isNetwork(e)) {
        throw ChatApiNetworkException(e.type.toString());
      }
      rethrow;
    }
    if (up.statusCode != 200 && up.statusCode != 201) {
      _throwForResponse(up.statusCode, up.data);
    }
    final Object? d = up.data;
    if (d is! Map) {
      throw ChatApiException('upload: неверный ответ');
    }
    final String? mediaPath = d['path'] as String? ?? d['url'] as String?;
    if (mediaPath == null || mediaPath.isEmpty) {
      throw ChatApiException('upload: нет path/url');
    }
    final String rel = mediaPath.startsWith('http') ? _pathFromUrl(mediaPath) : mediaPath;
    final Map<String, dynamic> body = <String, dynamic>{
      'body': 'Voice message',
      'message_type': 'voice',
      'media_url': rel.startsWith('/') ? rel : '/$rel',
      'media_duration_ms': durationMs,
      'client_request_id': const Uuid().v4(),
    };
    if (replyToMessageId != null) {
      body['reply_to_message_id'] = replyToMessageId;
    }
    if (replySnippet != null) {
      body['reply_snippet'] = replySnippet;
    }
    if (replyAuthorId != null) {
      body['reply_author_id'] = replyAuthorId;
    }
    if (replyAuthorLabel != null) {
      body['reply_author_label'] = replyAuthorLabel;
    }
    final Response<dynamic> r = await _dio.post(
      'conversations/$conversationId/messages',
      data: body,
    );
    if (r.statusCode == 201 || r.statusCode == 200) {
      final Object? m = (r.data is Map) ? (r.data as Map)['message'] : r.data;
      if (m is Map) {
        _listCache['fallback::$conversationId'] = _ListCache(
          <ChatMessage>[
            ChatMessage.fromMap(_norm(Map<dynamic, dynamic>.from(m))),
          ],
          DateTime.now().millisecondsSinceEpoch,
        );
      }
      return;
    }
    _throwForResponse(r.statusCode, r.data);
  }

  @override
  Future<void> ackMessageDelivery({
    required String conversationId,
    required String messageId,
  }) async {
    try {
      final Response<dynamic> r = await _dio.post<dynamic>(
        'conversations/$conversationId/messages/$messageId/delivery-ack',
        options: Options(
          validateStatus: (int? s) => s != null && s < 500,
        ),
      );
      if (r.statusCode == 200 || r.statusCode == 404) {
        return;
      }
      _throwForResponse(r.statusCode, r.data);
    } on DioException catch (e) {
      if (_isNetwork(e)) {
        return;
      }
      rethrow;
    }
  }

  static String _pathFromUrl(String u) {
    final Uri? uri = Uri.tryParse(u);
    if (uri == null) {
      return u;
    }
    return uri.path;
  }

  @override
  Future<void> softDeleteMessage(String messageId) async {
    try {
      final Response<dynamic> r = await _dio.post(
        'messages/$messageId/soft-delete',
        options: Options(validateStatus: (int? s) => s == 200 || s == 201 || s == 204),
      );
      if (r.statusCode != 204 && r.statusCode != 200 && r.statusCode != 201) {
        throw ChatApiException('softDelete: ${r.statusCode}');
      }
    } on DioException catch (e) {
      if (_isNetwork(e)) {
        throw ChatApiNetworkException(e.type.toString());
      }
      rethrow;
    }
  }

  void disposeHub() {
    _hub.dispose();
  }

  bool _isNetwork(DioException e) {
    return e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError;
  }

  void _pruneListCache() {
    if (_listCache.length < 200) {
      return;
    }
    _listCache.removeWhere(
      (String k, _ListCache v) =>
          DateTime.now().millisecondsSinceEpoch - v.atMs > 120000,
    );
  }

  static Map<String, dynamic> _norm(Map<dynamic, dynamic> m) {
    return Map<String, dynamic>.from(
      m.map(
        (dynamic k, dynamic v) => MapEntry<String, Object?>(k.toString(), v),
      ),
    );
  }
}

class _ListCache {
  _ListCache(this.items, this.atMs);
  final List<ChatMessage> items;
  final int atMs;
}
