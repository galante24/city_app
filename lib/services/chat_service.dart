import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_ready.dart';
import '../models/conversation_list_item.dart';

/// Личные чаты + сообщения (Supabase: conversations, chat_messages, …).
class ChatService {
  ChatService._();

  static SupabaseClient? get _c {
    if (!supabaseAppReady) {
      return null;
    }
    return Supabase.instance.client;
  }

  /// Сохранить телефон в [profiles.phone_e164] (для поиска по контактам).
  static Future<void> setMyPhoneE164(String? phoneE164) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    final String uid = c.auth.currentUser?.id ?? '';
    if (uid.isEmpty) {
      throw StateError('Нет сессии');
    }
    final String? t = phoneE164?.trim();
    await c.from('profiles').update(<String, dynamic>{
      'phone_e164': (t == null || t.isEmpty) ? null : t,
    }).eq('id', uid);
  }

  static Future<String?> findUserIdByPhoneE164(String phoneE164) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      return null;
    }
    try {
      final dynamic r = await c.rpc('find_user_id_by_phone_e164',
          params: <String, dynamic>{'p_phone': phoneE164});
      final Object? p = _rpcPayload(r);
      if (p == null) {
        return null;
      }
      return p.toString();
    } on Exception {
      return null;
    }
  }

  static Future<String?> findUserIdByEmail(String email) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      return null;
    }
    try {
      final dynamic r = await c
          .rpc('find_user_id_by_email', params: <String, dynamic>{'lookup': email.trim()});
      final Object? p = _rpcPayload(r);
      if (p == null) {
        return null;
      }
      return p.toString();
    } on Exception {
      return null;
    }
  }

  static Future<String> getOrCreateDirectConversation(String otherUserId) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    final dynamic r = await c.rpc(
      'get_or_create_direct_conversation',
      params: <String, dynamic>{'p_other': otherUserId},
    );
    final Object? id = _rpcPayload(r);
    if (id == null) {
      throw StateError('Не удалось создать чат');
    }
    return id.toString();
  }

  /// Без [PostgrestFilterBuilder.count] `rpc` отдаёт payload напрямую, не [PostgrestResponse].
  static Object? _rpcPayload(dynamic result) {
    if (result == null) {
      return null;
    }
    if (result is PostgrestResponse) {
      return result.data;
    }
    return result;
  }

  static Future<Map<String, Map<String, dynamic>>> _fetchLastMessagePreviews(
    SupabaseClient c,
    List<String> convIds,
  ) async {
    if (convIds.isEmpty) {
      return <String, Map<String, dynamic>>{};
    }
    try {
      final dynamic r = await c.rpc(
        'conversation_last_message_previews',
        params: <String, dynamic>{'p_conv_ids': convIds},
      );
      final Object? d = _rpcPayload(r);
      if (d is! List) {
        return <String, Map<String, dynamic>>{};
      }
      final Map<String, Map<String, dynamic>> out = <String, Map<String, dynamic>>{};
      for (final dynamic e in d) {
        if (e is Map<String, dynamic>) {
          final String? cid = e['conversation_id']?.toString();
          if (cid != null) {
            out[cid] = e;
          }
        }
      }
      return out;
    } on Object {
      return <String, Map<String, dynamic>>{};
    }
  }

  /// PostgREST у RPC со скаляром (uuid) обычно отдаёт строку; в редких случаях — [uuid] или map.
  static String _uuidFromRpcData(Object? data) {
    if (data == null) {
      return '';
    }
    if (data is String) {
      final String s = data.trim();
      return (s == 'null' || s.isEmpty) ? '' : s;
    }
    if (data is List) {
      if (data.isEmpty) {
        return '';
      }
      return _uuidFromRpcData(data.first);
    }
    if (data is Map) {
      for (final String k in <String>['id', 'create_group_conversation', 'get_or_create_direct_conversation']) {
        final Object? v = data[k];
        if (v != null) {
          final String s = _uuidFromRpcData(v);
          if (s.isNotEmpty) {
            return s;
          }
        }
      }
    }
    final String t = data.toString().trim();
    if (t.isEmpty || t == 'null') {
      return '';
    }
    return t;
  }

  /// PostgREST `.or('id.eq.uuid,...')` с UUID ломает разбор; используем [PostgrestFilterBuilder.inFilter].
  static Future<List<ConversationListItem>> listConversations() async {
    final SupabaseClient? c = _c;
    if (c == null) {
      return <ConversationListItem>[];
    }
    final String? me = c.auth.currentUser?.id;
    if (me == null) {
      return <ConversationListItem>[];
    }
    final List<dynamic> part = await c
        .from('conversation_participants')
        .select('conversation_id, role')
        .eq('user_id', me);
    final Map<String, String> myRoleByConv = <String, String>{};
    final List<String> convIds = <String>[];
    for (final dynamic e in part) {
      final Map<String, dynamic> m = e as Map<String, dynamic>;
      final String? id = m['conversation_id']?.toString();
      if (id != null) {
        convIds.add(id);
        myRoleByConv[id] = (m['role'] as String?)?.trim() ?? 'member';
      }
    }
    if (convIds.isEmpty) {
      return <ConversationListItem>[];
    }
    final List<dynamic> convRows =
        await c.from('conversations').select().inFilter('id', convIds);
    final List<dynamic> allPart = await c
        .from('conversation_participants')
        .select('conversation_id, user_id, role')
        .inFilter('conversation_id', convIds);
    final Set<String> uids = <String>{};
    for (final dynamic e in allPart) {
      final String? u = (e as Map<String, dynamic>)['user_id']?.toString();
      if (u != null) {
        uids.add(u);
      }
    }
    if (uids.isEmpty) {
      return <ConversationListItem>[];
    }
    // Без phone_e164: номер не подтягивать в списке чатов (только владелец в своём профиле).
    final List<dynamic> profRows = await c
        .from('profiles')
        .select('id, first_name, last_name, username')
        .inFilter('id', uids.toList());
    final Map<String, Map<String, dynamic>> lastMsgByConv =
        await _fetchLastMessagePreviews(c, convIds);
    final Map<String, Map<String, dynamic>> profById = <String, Map<String, dynamic>>{
      for (final Map<String, dynamic> p in profRows.cast<Map<String, dynamic>>())
        p['id']!.toString(): p
    };
    final List<ConversationListItem> out = <ConversationListItem>[];
    for (final Map<String, dynamic> row in convRows.cast<Map<String, dynamic>>()) {
      final String cid = row['id']!.toString();
      final bool isGroup = row['is_group'] as bool? ?? !(row['is_direct'] as bool? ?? true);
      final String? myRole = myRoleByConv[cid];
      String? otherId;
      for (final dynamic p in allPart) {
        final Map<String, dynamic> m = p as Map<String, dynamic>;
        if (m['conversation_id']?.toString() == cid) {
          final String? uid = m['user_id']?.toString();
          if (uid != null && uid != me) {
            otherId = uid;
            if (!(row['is_group'] as bool? ?? false)) {
              break;
            }
          }
        }
      }
      final String? gname = (row['group_name'] as String?)?.trim();
      String? preview = (row['last_message_preview'] as String?)?.trim();
      if (preview == null || preview.isEmpty) {
        final String? fromRpc = lastMsgByConv[cid]?['body_preview'] as String?;
        if (fromRpc != null && fromRpc.trim().isNotEmpty) {
          preview = fromRpc.trim();
        }
      }
      String? updated = (row['last_message_at'] as String?)?.trim();
      if (updated == null || updated.isEmpty) {
        updated = (row['updated_at'] as String?)?.trim();
      }
      final String? lastAtRpc = lastMsgByConv[cid]?['last_at'] as String?;
      if (lastAtRpc != null && lastAtRpc.isNotEmpty) {
        if (updated == null || updated.isEmpty) {
          updated = lastAtRpc;
        } else {
          try {
            if (DateTime.parse(lastAtRpc).isAfter(DateTime.parse(updated))) {
              updated = lastAtRpc;
            }
          } on Object {
            /* keep updated */
          }
        }
      }
      int sortMs = 0;
      if (updated != null && updated.isNotEmpty) {
        try {
          sortMs = DateTime.parse(updated).toLocal().millisecondsSinceEpoch;
        } on Object {
          sortMs = 0;
        }
      }
      if (isGroup) {
        out.add(
          ConversationListItem(
            id: cid,
            title: (gname != null && gname.isNotEmpty) ? gname : 'Группа',
            subtitle: (preview != null && preview.isNotEmpty) ? preview : 'Нет сообщений',
            timeText: _formatListTime(updated),
            sortKeyMs: sortMs,
            isGroup: true,
            isOpen: row['is_open'] as bool?,
            myRole: myRole,
            groupName: gname,
          ),
        );
      } else {
        out.add(
          ConversationListItem(
            id: cid,
            title: _titleForOther(otherId, profById),
            subtitle: (preview != null && preview.isNotEmpty) ? preview : 'Нет сообщений',
            timeText: _formatListTime(updated),
            sortKeyMs: sortMs,
            otherUserId: otherId,
            isGroup: false,
            myRole: myRole,
          ),
        );
      }
    }
    out.sort(
        (ConversationListItem a, ConversationListItem b) => b.sortKeyMs.compareTo(a.sortKeyMs));
    return out;
  }

  static String _titleForOther(String? otherId, Map<String, Map<String, dynamic>> profById) {
    if (otherId == null) {
      return 'Чат';
    }
    final Map<String, dynamic>? p = profById[otherId];
    if (p == null) {
      return 'Пользователь';
    }
    final String fn = (p['first_name'] as String?)?.trim() ?? '';
    final String ln = (p['last_name'] as String?)?.trim() ?? '';
    final String t = ('$fn $ln').trim();
    if (t.isNotEmpty) {
      return t;
    }
    return 'Пользователь';
  }

  static String _formatListTime(String? iso) {
    if (iso == null || iso.isEmpty) {
      return '';
    }
    try {
      final DateTime d = DateTime.parse(iso).toLocal();
      final DateTime n = DateTime.now();
      if (d.year == n.year && d.month == n.month && d.day == n.day) {
        return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      }
      return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
    } on Object {
      return '';
    }
  }

  static Stream<List<Map<String, dynamic>>>? watchMessages(String conversationId) {
    final SupabaseClient? c = _c;
    if (c == null) {
      return null;
    }
    return c
        .from('chat_messages')
        .stream(primaryKey: const <String>['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true);
  }

  static Future<void> sendMessage(String conversationId, String body) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    final String? uid = c.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('Нет сессии');
    }
    final String t = body.trim();
    if (t.isEmpty) {
      return;
    }
    await c.from('chat_messages').insert(<String, dynamic>{
      'conversation_id': conversationId,
      'sender_id': uid,
      'body': t,
    });
  }

  static Future<void> setMyUsername(String? username) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    await c.rpc('set_my_username', params: <String, dynamic>{'p_username': username});
  }

  static Future<String> createGroupConversation({
    required String title,
    required bool isOpen,
  }) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    final String trimmed = title.trim();
    final dynamic r = await c.rpc(
      'create_group_conversation',
      params: <String, dynamic>{'p_title': title, 'p_is_open': isOpen},
    );
    String id = _uuidFromRpcData(_rpcPayload(r));
    if (id.isEmpty) {
      id = await _recoverNewGroupConversationId(c, trimmed);
    }
    if (id.isEmpty) {
      throw StateError(
        'Пустой ответ create_group_conversation. Проверьте, что в Supabase выполнена миграция (FINAL_all_in_one_chats_and_groups.sql) и веб-версия задеплоена.',
      );
    }
    return id;
  }

  static Future<String> _recoverNewGroupConversationId(
    SupabaseClient c,
    String groupNameTrimmed,
  ) async {
    final String? me = c.auth.currentUser?.id;
    if (me == null) {
      return '';
    }
    try {
      final List<dynamic> rows = await c
          .from('conversations')
          .select('id')
          .eq('is_group', true)
          .eq('group_name', groupNameTrimmed)
          .eq('created_by', me)
          .order('created_at', ascending: false)
          .limit(1);
      if (rows.isEmpty) {
        return '';
      }
      return (rows.first as Map<String, dynamic>)['id']!.toString();
    } on Object {
      return '';
    }
  }

  static Future<void> addGroupParticipant(String conversationId, String userId) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    await c.rpc(
      'add_group_participant',
      params: <String, dynamic>{'p_conversation_id': conversationId, 'p_user_id': userId},
    );
  }

  static Future<void> removeGroupParticipant(String conversationId, String userId) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    await c.rpc(
      'remove_group_participant',
      params: <String, dynamic>{'p_conversation_id': conversationId, 'p_user_id': userId},
    );
  }

  static Future<void> setGroupModerator(
    String conversationId,
    String userId, {
    required bool isModerator,
  }) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    await c.rpc(
      'set_group_moderator',
      params: <String, dynamic>{
        'p_conversation_id': conversationId,
        'p_user_id': userId,
        'p_moderator': isModerator,
      },
    );
  }

  static Future<void> softDeleteMessage(String messageId) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    await c.rpc('soft_delete_group_message', params: <String, dynamic>{'p_message_id': messageId});
  }

  static Future<List<Map<String, dynamic>>> searchProfilesForChat(String query) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      return <Map<String, dynamic>>[];
    }
    if (query.trim().isEmpty) {
      return <Map<String, dynamic>>[];
    }
    final dynamic r = await c.rpc(
      'search_profiles_for_chat',
      params: <String, dynamic>{'p_query': query.trim(), 'p_limit': 20},
    );
    final Object? d = _rpcPayload(r);
    if (d is List) {
      return d.cast<Map<String, dynamic>>();
    }
    return <Map<String, dynamic>>[];
  }

  static Future<List<String>> listDirectPartnerUserIds() async {
    final SupabaseClient? c = _c;
    if (c == null) {
      return <String>[];
    }
    final dynamic r = await c.rpc('list_direct_partner_user_ids');
    final Object? d = _rpcPayload(r);
    if (d is List) {
      return List<String>.from(d.map((dynamic e) => e.toString()));
    }
    return <String>[];
  }

  static Future<Map<String, dynamic>?> fetchConversation(String conversationId) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      return null;
    }
    return c.from('conversations').select().eq('id', conversationId).maybeSingle();
  }

  static Future<List<Map<String, dynamic>>> fetchParticipantsWithProfiles(
    String conversationId,
  ) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      return <Map<String, dynamic>>[];
    }
    final List<dynamic> parts = await c
        .from('conversation_participants')
        .select('user_id, role')
        .eq('conversation_id', conversationId);
    if (parts.isEmpty) {
      return <Map<String, dynamic>>[];
    }
    final List<String> uids = parts
        .map((dynamic e) => (e as Map<String, dynamic>)['user_id']?.toString())
        .whereType<String>()
        .toList();
    final List<dynamic> profs = await c
        .from('profiles')
        .select('id, first_name, last_name, username')
        .inFilter('id', uids);
    final Map<String, Map<String, dynamic>> byU = <String, Map<String, dynamic>>{
      for (final Map<String, dynamic> p in profs.cast<Map<String, dynamic>>()) p['id']!.toString(): p
    };
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final dynamic p in parts) {
      final Map<String, dynamic> m = p as Map<String, dynamic>;
      final String? uid = m['user_id']?.toString();
      if (uid == null) {
        continue;
      }
      final Map<String, dynamic>? pr = byU[uid];
      out.add(<String, dynamic>{
        'user_id': uid,
        'role': m['role'],
        'first_name': pr?['first_name'],
        'last_name': pr?['last_name'],
        'username': pr?['username'],
      });
    }
    return out;
  }

  static Future<String?> getMyRoleInConversation(String conversationId) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      return null;
    }
    final String? me = c.auth.currentUser?.id;
    if (me == null) {
      return null;
    }
    final Map<String, dynamic>? row = await c
        .from('conversation_participants')
        .select('role')
        .eq('conversation_id', conversationId)
        .eq('user_id', me)
        .maybeSingle();
    return row?['role'] as String?;
  }

  static Future<String?> otherParticipantId(String conversationId) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      return null;
    }
    final String? me = c.auth.currentUser?.id;
    if (me == null) {
      return null;
    }
    final List<dynamic> rows = await c
        .from('conversation_participants')
        .select('user_id')
        .eq('conversation_id', conversationId);
    for (final dynamic e in rows) {
      final String? u = (e as Map<String, dynamic>)['user_id']?.toString();
      if (u != null && u != me) {
        return u;
      }
    }
    return null;
  }

  static Future<String?> displayNameForUserId(String userId) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      return null;
    }
    final Map<String, dynamic>? row =
        await c.from('profiles').select('first_name, last_name').eq('id', userId).maybeSingle();
    if (row == null) {
      return 'Пользователь';
    }
    final String fn = (row['first_name'] as String?)?.trim() ?? '';
    final String ln = (row['last_name'] as String?)?.trim() ?? '';
    final String t = ('$fn $ln').trim();
    return t.isNotEmpty ? t : 'Пользователь';
  }
}
