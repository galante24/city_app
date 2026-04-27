import 'auth_port.dart';

/// Глобальная привязка [AuthPort] (регистрация в [main] после инициализации драйвера).
class AppAuth {
  AppAuth._();

  static AuthPort _port = const UnauthenticatedAuthPort();

  static void register(AuthPort port) {
    _port = port;
  }

  static AuthPort get I => _port;
}
