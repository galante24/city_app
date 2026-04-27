/// Текущий пользователь; для REST чата [getChatApiAccessToken] — Bearer.
abstract class AuthPort {
  String? get currentUserId;

  /// JWT/токен для `Authorization: Bearer` к chat API.
  /// По умолчанию — сессия Supabase; иначе задайте [kChatApiBearer] при сборке.
  Future<String?> getChatApiAccessToken();

  /// Обновить сессию (например после 401) и получить новый access token.
  /// Для [kChatApiBearer] — [true] без сети.
  Future<bool> refreshChatApiSession();
}

/// Заглушка, пока сессия недоступна.
class UnauthenticatedAuthPort implements AuthPort {
  const UnauthenticatedAuthPort();

  @override
  String? get currentUserId => null;

  @override
  Future<String?> getChatApiAccessToken() async => null;

  @override
  Future<bool> refreshChatApiSession() async => false;
}
