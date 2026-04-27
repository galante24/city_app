import 'package:flutter/foundation.dart';

/// Состояние провода чат-API (только [BackendMode.rest] / Socket.IO).
enum ChatWireStatus {
  /// Ещё не трогали / нет rest.
  idle,

  /// Соединяемся.
  connecting,

  /// Сокет online.
  connected,

  /// Потеря, повтор.
  reconnecting,

  /// Сеть/API недоступны после ретраев.
  offline,

  /// Ошибка (например, нет токена).
  error,
}

/// Уведомляет UI (тонкая полоса) без лишних rebuld всего чата.
class ChatConnectionController extends ChangeNotifier {
  ChatConnectionController._();
  static final ChatConnectionController instance = ChatConnectionController._();

  ChatWireStatus _status = ChatWireStatus.idle;
  String? _lastLog;

  ChatWireStatus get status => _status;
  String? get lastLog => _lastLog;

  void setStatus(ChatWireStatus s, {String? log}) {
    if (_status == s) {
      if (log == null) {
        return;
      }
      if (log == _lastLog) {
        return;
      }
    }
    _status = s;
    if (log != null) {
      _lastLog = log;
    }
    if (kDebugMode && log != null) {
      // ignore: avoid_print
      print('[ChatWire] $s: $log');
    }
    notifyListeners();
  }

  void reset() {
    _status = ChatWireStatus.idle;
    _lastLog = null;
    notifyListeners();
  }
}
