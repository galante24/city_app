/// Базовая ошибка REST чат-API.
class ChatApiException implements Exception {
  ChatApiException(
    this.message, {
    this.code,
    this.statusCode,
  });
  final String message;
  final String? code;
  final int? statusCode;
  @override
  String toString() => message;
}

/// Сеть / тайм-аут.
class ChatApiNetworkException extends ChatApiException {
  ChatApiNetworkException(this.dioType, [String message = 'Сеть недоступна']) : super(message);
  final String? dioType;
}

/// Бизнес-ошибки слоя чата (не Postgrest напрямую в UI).
class ChatFloodException implements Exception {
  ChatFloodException([this.message = 'Слишком много сообщений. Подождите немного.']);

  final String message;

  @override
  String toString() => message;
}
