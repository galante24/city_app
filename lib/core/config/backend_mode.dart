import '../../config/app_secrets.dart';

/// Какой транспорт использует [ChatMessagesRepository] и связанные datasources.
enum BackendMode {
  supabase,
  /// REST к VPS: см. [kApiBaseUrl] и [lib/features/chat/api/chat_messages_rest_contract.dart].
  rest,
}

BackendMode parseBackendMode() {
  switch (kBackendModeEnv.trim().toLowerCase()) {
    case 'rest':
    case 'api':
    case 'vps':
      return BackendMode.rest;
    case 'supabase':
    case '':
    default:
      return BackendMode.supabase;
  }
}
