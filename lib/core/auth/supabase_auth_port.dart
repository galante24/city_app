import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_secrets.dart';

import 'auth_port.dart';

class SupabaseAuthPort implements AuthPort {
  SupabaseAuthPort(this._client);

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<String?> getChatApiAccessToken() async {
    if (kChatApiBearer.isNotEmpty) {
      return kChatApiBearer;
    }
    return _client.auth.currentSession?.accessToken;
  }

  @override
  Future<bool> refreshChatApiSession() async {
    if (kChatApiBearer.isNotEmpty) {
      return true;
    }
    final AuthResponse r = await _client.auth.refreshSession();
    return r.session != null;
  }
}
