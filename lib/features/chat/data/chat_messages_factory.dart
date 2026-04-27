import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/app_secrets.dart';
import '../../../config/supabase_ready.dart';
import '../../../core/auth/app_auth.dart';
import '../../../core/auth/auth_port.dart';
import '../../../core/config/backend_mode.dart';
import '../domain/chat_messages_repository.dart';
import 'api/chat_realtime_hub.dart';
import 'datasources/api_chat_messages_datasource.dart';
import 'datasources/chat_messages_remote_datasource.dart';
import 'datasources/supabase_chat_messages_datasource.dart';
import 'repositories/chat_messages_repository_impl.dart';

/// Собирает [ChatMessagesRepository] в зависимости от [kBackendModeEnv] / Supabase.
class ChatMessagesFactory {
  ChatMessagesFactory._();

  static ApiChatMessagesDataSource? _cachedApiDs;
  static String? _cachedApiBase;
  static ChatMessagesRealtimeHub? _sharedRestHub;

  static ChatMessagesRemoteDataSource? tryDataSource() {
    final BackendMode mode = parseBackendMode();
    if (mode == BackendMode.supabase) {
      _cachedApiDs?.disposeHub();
      _cachedApiDs = null;
      _cachedApiBase = null;
      _sharedRestHub = null;
      if (!supabaseAppReady) {
        return null;
      }
      return SupabaseChatMessagesDataSource(Supabase.instance.client);
    }
    final String base = kApiBaseUrl.trim();
    if (base.isEmpty) {
      return null;
    }
    if (_cachedApiBase != null && _cachedApiBase != base) {
      _cachedApiDs?.disposeHub();
      _cachedApiDs = null;
      _sharedRestHub = null;
    }
    _cachedApiBase = base;
    _sharedRestHub ??= ChatMessagesRealtimeHub(baseUrl: base, auth: AppAuth.I);
    _cachedApiDs ??= ApiChatMessagesDataSource(
      baseUrl: base,
      auth: AppAuth.I,
      hub: _sharedRestHub!,
    );
    return _cachedApiDs;
  }

  /// [auth] по умолчанию [AppAuth.I]; можно подставить мок в тестах.
  static ChatMessagesRepository? tryRepository({AuthPort? auth}) {
    final ChatMessagesRemoteDataSource? ds = tryDataSource();
    if (ds == null) {
      return null;
    }
    return ChatMessagesRepositoryImpl(ds, auth ?? AppAuth.I);
  }
}
