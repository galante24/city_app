import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../../config/app_secrets.dart';
import '../../../../core/auth/auth_port.dart';
import '../../domain/chat_message_row_event.dart';
import 'chat_connection_controller.dart';

/// Один сокет на [baseUrl], комнаты по `conversationId` (события `join` / `leave`).
class ChatMessagesRealtimeHub {
  ChatMessagesRealtimeHub({
    required this.baseUrl,
    required this.auth,
  });

  final String baseUrl;
  final AuthPort auth;

  final Map<String, StreamController<ChatMessageRowEvent>> _controllers = {};
  final Set<String> _activeRooms = {};
  io.Socket? _socket;
  int _reconnectFailCount = 0;
  static const int _maxSocketFails = 24;

  Uri get _root => Uri.parse(baseUrl.replaceAll(RegExp(r'/$'), ''));
  String get _namespaceUrl {
    // Nest: @WebSocketGateway({ namespace: '/ws' })
    return '$_root/ws';
  }

  void _log(String m) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[ChatWS] $m');
    }
  }

  Stream<ChatMessageRowEvent> events(String conversationId) {
    return _controllers.putIfAbsent(
      conversationId,
      () {
        return StreamController<ChatMessageRowEvent>.broadcast(
          onListen: () {
            unawaited(_onRoomAdd(conversationId));
          },
          onCancel: () {
            unawaited(_onRoomRemove(conversationId));
          },
        );
      },
    ).stream;
  }

  Future<void> _onRoomAdd(String conversationId) async {
    _activeRooms.add(conversationId);
    await _ensureConnected();
    if (_socket?.connected == true) {
      _socket?.emit('join', <String, dynamic>{'conversationId': conversationId});
    }
  }

  Future<void> _onRoomRemove(String conversationId) async {
    if (_activeRooms.remove(conversationId)) {
      final StreamController<ChatMessageRowEvent>? c = _controllers.remove(conversationId);
      await c?.close();
    }
    if (_socket?.connected == true) {
      _socket?.emit('leave', <String, dynamic>{'conversationId': conversationId});
    }
    if (_activeRooms.isEmpty) {
      _disposeSocket();
    }
  }

  Future<void> _ensureConnected() async {
    if (_socket?.connected == true) {
      ChatConnectionController.instance.setStatus(ChatWireStatus.connected);
      return;
    }
    final String? t = kChatApiBearer.isNotEmpty
        ? kChatApiBearer
        : await auth.getChatApiAccessToken();
    if (t == null || t.isEmpty) {
      ChatConnectionController.instance.setStatus(
        ChatWireStatus.error,
        log: 'Нет токена для WebSocket (войдите в аккаунт или CHAT_API_BEARER)',
      );
      return;
    }
    ChatConnectionController.instance.setStatus(ChatWireStatus.connecting);
    _socket?.dispose();
    _socket = io.io(
      _namespaceUrl,
      io.OptionBuilder()
          .setPath('/socket.io')
          .setTransports(<String>['websocket', 'polling'])
          .setAuth(<String, dynamic>{'token': t})
          .setReconnectionAttempts(24)
          .setReconnectionDelay(500)
          .setReconnectionDelayMax(30000)
          .setRandomizationFactor(0.5)
          .enableReconnection()
          .setTimeout(25000)
          .build(),
    );
    _socket!.onConnect((_) {
      _reconnectFailCount = 0;
      ChatConnectionController.instance.setStatus(ChatWireStatus.connected);
      for (final String id in _activeRooms) {
        _socket?.emit('join', <String, dynamic>{'conversationId': id});
      }
    });
    _socket!.onDisconnect((_) {
      if (_activeRooms.isNotEmpty) {
        ChatConnectionController.instance.setStatus(
          ChatWireStatus.reconnecting,
          log: 'socket disconnect',
        );
      }
    });
    _socket!.onConnectError((dynamic e) {
      _reconnectFailCount++;
      if (_reconnectFailCount >= _maxSocketFails) {
        ChatConnectionController.instance.setStatus(
          ChatWireStatus.offline,
          log: e.toString(),
        );
      } else {
        ChatConnectionController.instance.setStatus(
          ChatWireStatus.reconnecting,
          log: e.toString(),
        );
      }
    });
    _socket!.on('message', _onMessagePayload);
  }

  void _onMessagePayload(dynamic data) {
    if (data is! Map) {
      return;
    }
    final Map<String, dynamic> m = _stringMap(data);
    final String? event = m['event'] as String?;
    final String? conv = m['conversation_id'] as String?;
    if (conv == null || event == null) {
      return;
    }
    final Object? rec = m['record'];
    if (rec is! Map) {
      return;
    }
    final Map<String, dynamic> recMap = _stringMap(rec);
    final StreamController<ChatMessageRowEvent>? c = _controllers[conv];
    if (c == null || c.isClosed) {
      return;
    }
    try {
      if (event == 'insert') {
        c.add(ChatMessageRowEvent.insert(recMap));
      } else if (event == 'update') {
        c.add(
          ChatMessageRowEvent.update(
            recMap,
            <String, dynamic>{},
          ),
        );
      } else if (event == 'delete') {
        c.add(
          ChatMessageRowEvent.delete(
            recMap,
          ),
        );
      }
    } on Object catch (e) {
      _log('map event: $e');
    }
  }

  Map<String, dynamic> _stringMap(Map<dynamic, dynamic> src) {
    return Map<String, dynamic>.from(
      src.map((dynamic k, dynamic v) {
        if (k is! String) {
          return MapEntry<String, Object?>(k.toString(), v);
        }
        if (v is Map) {
          return MapEntry<String, Object?>(k, _stringMap(v));
        }
        return MapEntry<String, Object?>(k, v);
      }),
    );
  }

  void _disposeSocket() {
    if (_socket != null) {
      _socket?.disconnect();
      _socket?.dispose();
      _socket = null;
    }
    if (_activeRooms.isEmpty) {
      ChatConnectionController.instance.setStatus(ChatWireStatus.idle, log: 'все комнаты закрыты');
    }
  }

  void dispose() {
    for (final StreamController<ChatMessageRowEvent> c in _controllers.values) {
      if (!c.isClosed) {
        c.close();
      }
    }
    _controllers.clear();
    _activeRooms.clear();
    _disposeSocket();
  }
}
