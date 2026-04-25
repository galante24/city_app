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
      final PostgrestResponse<dynamic> r = await c.rpc('find_user_id_by_phone_e164',
          params: <String, dynamic>{'p_phone': phoneE164});
      if (r.data == null) {
        return null;
      }
      return r.data.toString();
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
      final PostgrestResponse<dynamic> r = await c
          .rpc('find_user_id_by_email', params: <String, dynamic>{'lookup': email.trim()});
      if (r.data == null) {
        return null;
      }
      return r.data.toString();
    } on Exception {
      return null;
    }
  }

  static Future<String> getOrCreateDirectConversation(String otherUserId) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    final PostgrestResponse<dynamic> r = await c.rpc(
      'get_or_create_direct_conversation',
      params: <String, dynamic>{'p_other': otherUserId},
    );
    final Object? id = r.data;
    if (id == null) {
      throw StateError('Не удалось создать чат');
    }
    return id.toString();
  }

  static String _orEqIn(String col, List<String> ids) {
    return ids.map((String id) => '$col.eq.$id').join(',');
  }

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
        .select('conversation_id')
        .eq('user_id', me);
    final List<String> convIds = part
        .map((dynamic e) => (e as Map<String, dynamic>)['conversation_id']?.toString())
        .whereType<String>()
        .toList();
    if (convIds.isEmpty) {
      return <ConversationListItem>[];
    }
    final List<dynamic> convRows =
        await c.from('conversations').select().or(_orEqIn('id', convIds));
    final List<dynamic> allPart = await c
        .from('conversation_participants')
        .select('conversation_id, user_id')
        .or(_orEqIn('conversation_id', convIds));
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
    final List<dynamic> profRows = await c
        .from('profiles')
        .select('id, first_name, last_name, phone_e164')
        .or(_orEqIn('id', uids.toList()));
    final Map<String, Map<String, dynamic>> profById = <String, Map<String, dynamic>>{
      for (final Map<String, dynamic> p in profRows.cast<Map<String, dynamic>>())
        p['id']!.toString(): p
    };
    final List<ConversationListItem> out = <ConversationListItem>[];
    for (final Map<String, dynamic> row in convRows.cast<Map<String, dynamic>>()) {
      final String cid = row['id']!.toString();
      String? otherId;
      for (final dynamic p in allPart) {
        final Map<String, dynamic> m = p as Map<String, dynamic>;
        if (m['conversation_id']?.toString() == cid) {
          final String? uid = m['user_id']?.toString();
          if (uid != null && uid != me) {
            otherId = uid;
            break;
          }
        }
      }
      final String title = _titleForOther(otherId, profById);
      final String? preview = row['last_message_preview'] as String?;
      final String? updated =
          (row['last_message_at'] as String?) ?? (row['updated_at'] as String?);
      int sortMs = 0;
      if (updated != null && updated.isNotEmpty) {
        try {
          sortMs = DateTime.parse(updated).toLocal().millisecondsSinceEpoch;
        } on Object {
          sortMs = 0;
        }
      }
      out.add(
        ConversationListItem(
          id: cid,
          title: title,
          subtitle: preview ?? 'Нет сообщений',
          timeText: _formatListTime(updated),
          sortKeyMs: sortMs,
          otherUserId: otherId,
        ),
      );
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
