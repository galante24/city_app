import 'dart:convert';

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
    await c
        .from('profiles')
        .update(<String, dynamic>{
          'phone_e164': (t == null || t.isEmpty) ? null : t,
        })
        .eq('id', uid);
  }

  static Future<String?> findUserIdByPhoneE164(String phoneE164) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      return null;
    }
    try {
      final dynamic r = await c.rpc(
        'find_user_id_by_phone_e164',
        params: <String, dynamic>{'p_phone': phoneE164},
      );
      final Object? p = _rpcPayload(r);
      if (p == null) {
        return null;
      }
      return p.toString();
    } on Exception {
      return null;
    }
  }

  /// Точное совпадение [profiles.username] без учёта регистра; ввод с @ или без.
  static Future<String?> findUserIdByUsername(String rawNick) async {
    String s = rawNick.trim();
    while (s.startsWith('@')) {
      s = s.substring(1).trim();
    }
    if (s.isEmpty) {
      return null;
    }
    final String needle = s.toLowerCase();
    final List<Map<String, dynamic>> rows = await searchProfilesForChat(s);
    for (final Map<String, dynamic> m in rows) {
      final String? u = (m['username'] as String?)?.trim();
      if (u != null && u.toLowerCase() == needle) {
        return m['id']?.toString();
      }
    }
    return null;
  }

  static Future<String?> findUserIdByEmail(String email) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      return null;
    }
    try {
      final dynamic r = await c.rpc(
        'find_user_id_by_email',
        params: <String, dynamic>{'lookup': email.trim()},
      );
      final Object? p = _rpcPayload(r);
      if (p == null) {
        return null;
      }
      return p.toString();
    } on Exception {
      return null;
    }
  }

  static Future<String> getOrCreateDirectConversation(
    String otherUserId,
  ) async {
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

  static Map<String, Map<String, dynamic>> _parseLastPreviewRpc(dynamic raw) {
    try {
      final Object? d = _rpcPayload(raw);
      if (d is! List) {
        return <String, Map<String, dynamic>>{};
      }
      final Map<String, Map<String, dynamic>> out =
          <String, Map<String, dynamic>>{};
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
      for (final String k in <String>[
        'id',
        'create_group_conversation',
        'get_or_create_direct_conversation',
      ]) {
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
    final List<dynamic> convAndPart =
        await Future.wait<dynamic>(<Future<dynamic>>[
          c.from('conversations').select().inFilter('id', convIds),
          c
              .from('conversation_participants')
              .select('conversation_id, user_id, role')
              .inFilter('conversation_id', convIds),
          fetchUnreadConversationIds(),
        ]);
    final List<dynamic> convRows = convAndPart[0] as List<dynamic>;
    final List<dynamic> allPart = convAndPart[1] as List<dynamic>;
    final Set<String> unreadIds = <String>{};
    if (convAndPart.length > 2) {
      final Object? u = convAndPart[2];
      if (u is Set) {
        for (final Object? e in u) {
          if (e != null) {
            unreadIds.add(e.toString());
          }
        }
      }
    }
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
    final bool anyMissingPreview = convRows.cast<Map<String, dynamic>>().any((
      Map<String, dynamic> r,
    ) {
      final String? p = r['last_message_preview'] as String?;
      return p == null || p.trim().isEmpty;
    });
    // Без phone_e164: номер не подтягивать в списке чатов; превью по RPC — только если в строке пусто.
    final List<dynamic> profAndOpt = await Future.wait<dynamic>(
      <Future<dynamic>>[
        c
            .from('profiles')
            .select('id, first_name, last_name, username, avatar_url')
            .inFilter('id', uids.toList()),
        if (anyMissingPreview)
          c.rpc(
            'conversation_last_message_previews',
            params: <String, dynamic>{'p_conv_ids': convIds},
          )
        else
          Future<dynamic>.value(null),
      ],
    );
    final List<dynamic> profRows = profAndOpt[0] as List<dynamic>;
    final Map<String, Map<String, dynamic>> lastMsgByConv = anyMissingPreview
        ? _parseLastPreviewRpc(profAndOpt[1])
        : <String, Map<String, dynamic>>{};
    final Map<String, Map<String, dynamic>> profById =
        <String, Map<String, dynamic>>{
          for (final Map<String, dynamic> p
              in profRows.cast<Map<String, dynamic>>())
            p['id']!.toString(): p,
        };
    final List<ConversationListItem> out = <ConversationListItem>[];
    for (final Map<String, dynamic> row
        in convRows.cast<Map<String, dynamic>>()) {
      final String cid = row['id']!.toString();
      final bool isGroup =
          row['is_group'] as bool? ?? !(row['is_direct'] as bool? ?? true);
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
      final String subtitleText = (preview != null && preview.isNotEmpty)
          ? previewTextForList(preview)
          : 'Нет сообщений';
      if (isGroup) {
        out.add(
          ConversationListItem(
            id: cid,
            title: (gname != null && gname.isNotEmpty) ? gname : 'Группа',
            subtitle: subtitleText,
            timeText: _formatListTime(updated),
            sortKeyMs: sortMs,
            isGroup: true,
            isOpen: row['is_open'] as bool?,
            myRole: myRole,
            groupName: gname,
            hasUnread: unreadIds.contains(cid),
          ),
        );
      } else {
        out.add(
          ConversationListItem(
            id: cid,
            title: _titleForOther(otherId, profById),
            subtitle: subtitleText,
            timeText: _formatListTime(updated),
            sortKeyMs: sortMs,
            otherUserId: otherId,
            otherAvatarUrl: _avatarForUser(otherId, profById),
            isGroup: false,
            myRole: myRole,
            hasUnread: unreadIds.contains(cid),
          ),
        );
      }
    }
    out.sort(
      (ConversationListItem a, ConversationListItem b) =>
          b.sortKeyMs.compareTo(a.sortKeyMs),
    );
    return out;
  }

  static String? _avatarForUser(
    String? userId,
    Map<String, Map<String, dynamic>> profById,
  ) {
    if (userId == null) {
      return null;
    }
    final String? u =
        (profById[userId]?['avatar_url'] as String?)?.trim();
    return (u != null && u.isNotEmpty) ? u : null;
  }

  static String _titleForOther(
    String? otherId,
    Map<String, Map<String, dynamic>> profById,
  ) {
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

  /// Подзаголовок в списке чатов (картинка вместо `!img:https://...`).
  static String previewTextForList(String? raw) {
    final String t = (raw ?? '').trim();
    if (t.isEmpty) {
      return '';
    }
    if (t.startsWith(imageMessagePrefix)) {
      return 'Изображение';
    }
    if (fileMetaFromMessageBody(t) != null) {
      return 'Файл';
    }
    return t;
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

  /// Realtime-стрим иногда дублирует строки — оставляем по одной записи на [id], порядок по [created_at].
  static List<Map<String, dynamic>> dedupeChatMessagesById(
    List<Map<String, dynamic>>? rows,
  ) {
    if (rows == null || rows.isEmpty) {
      return <Map<String, dynamic>>[];
    }
    final Map<String, Map<String, dynamic>> byId =
        <String, Map<String, dynamic>>{};
    for (final Map<String, dynamic> m in rows) {
      final String? id = m['id']?.toString();
      if (id != null) {
        byId[id] = m;
      }
    }
    final List<Map<String, dynamic>> out = byId.values.toList();
    out.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      final String? ca = a['created_at'] as String?;
      final String? cb = b['created_at'] as String?;
      if (ca == null) {
        return -1;
      }
      if (cb == null) {
        return 1;
      }
      try {
        return DateTime.parse(ca).compareTo(DateTime.parse(cb));
      } on Object {
        return 0;
      }
    });
    return out;
  }

  static Future<Set<String>> fetchUnreadConversationIds() async {
    final SupabaseClient? c = _c;
    if (c == null) {
      return <String>{};
    }
    try {
      final dynamic r = await c.rpc('get_unread_conversation_ids');
      if (r is List) {
        return r.map((dynamic e) => e.toString()).toSet();
      }
      if (r is String) {
        // редко: пустой массив
        return <String>{};
      }
    } on Object {
      return <String>{};
    }
    return <String>{};
  }

  static Future<bool> fetchHasUnreadMessages() async {
    final SupabaseClient? c = _c;
    if (c == null) {
      return false;
    }
    try {
      final dynamic r = await c.rpc('has_unread_messages_for_me');
      if (r is bool) {
        return r;
      }
    } on Object {
      return false;
    }
    return false;
  }

  static Future<DateTime?> getMyLastReadInConversation(
    String conversationId,
  ) async {
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
        .select('last_read_at')
        .eq('conversation_id', conversationId)
        .eq('user_id', me)
        .maybeSingle();
    final Object? raw = row?['last_read_at'];
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    return null;
  }

  static Future<void> markConversationRead(String conversationId) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      return;
    }
    try {
      await c.rpc(
        'mark_conversation_read',
        params: <String, dynamic>{'p_conversation_id': conversationId},
      );
    } on Object {
      // миграция ещё не на сервере — тихо
    }
  }

  /// [user_id] остальных участников → время их last_read (для «галочек»).
  static Future<Map<String, DateTime?>> getOtherParticipantsLastReadMap(
    String conversationId,
  ) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      return <String, DateTime?>{};
    }
    final String? me = c.auth.currentUser?.id;
    if (me == null) {
      return <String, DateTime?>{};
    }
    final List<dynamic> rows = await c
        .from('conversation_participants')
        .select('user_id, last_read_at')
        .eq('conversation_id', conversationId)
        .neq('user_id', me);
    final Map<String, DateTime?> out = <String, DateTime?>{};
    for (final dynamic e in rows) {
      final Map<String, dynamic> m = e as Map<String, dynamic>;
      final String? uid = m['user_id']?.toString();
      if (uid == null) {
        continue;
      }
      final Object? raw = m['last_read_at'];
      if (raw is String) {
        out[uid] = DateTime.tryParse(raw);
      } else {
        out[uid] = null;
      }
    }
    return out;
  }

  static Stream<List<Map<String, dynamic>>>? watchMessages(
    String conversationId,
  ) {
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

  /// Префикс тела сообщения для вложенного изображения (публичный URL).
  static const String imageMessagePrefix = '!img:';

  /// Вложение: base64url(JSON {u, n, m}).
  static const String fileMessagePrefix = '!file:b64:';

  static String buildFileMessageBody({
    required String publicUrl,
    required String fileName,
    required String mimeType,
  }) {
    final String payload = jsonEncode(<String, String>{
      'u': publicUrl,
      'n': fileName,
      'm': mimeType,
    });
    return '$fileMessagePrefix${base64Url.encode(utf8.encode(payload))}';
  }

  /// Разбор [buildFileMessageBody]; при ошибке — null.
  static ChatFileMeta? fileMetaFromMessageBody(String body) {
    if (!body.startsWith(fileMessagePrefix)) {
      return null;
    }
    try {
      final String b64 = body.substring(fileMessagePrefix.length).trim();
      final String jsonStr = utf8.decode(base64Url.decode(b64));
      final Object? dec = jsonDecode(jsonStr);
      if (dec is! Map<String, dynamic>) {
        return null;
      }
      final String u = (dec['u'] as String?)?.trim() ?? '';
      if (u.isEmpty) {
        return null;
      }
      return ChatFileMeta(
        url: u,
        name: (dec['n'] as String?)?.trim() ?? 'файл',
        mime: (dec['m'] as String?)?.trim() ?? 'application/octet-stream',
      );
    } on Object {
      return null;
    }
  }

  static Future<void> sendFileMessage(
    String conversationId,
    ChatFileMeta meta,
  ) async {
    return sendMessage(
      conversationId,
      buildFileMessageBody(
        publicUrl: meta.url,
        fileName: meta.name,
        mimeType: meta.mime,
      ),
    );
  }

  /// Сообщения беседы (от новых к старым), для вкладок профиля и галереи.
  static Future<List<Map<String, dynamic>>> fetchChatMessagesNewestFirst(
    String conversationId, {
    int limit = 400,
  }) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      return <Map<String, dynamic>>[];
    }
    try {
      final List<dynamic> rows = await c
          .from('chat_messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: false)
          .limit(limit);
      return rows.cast<Map<String, dynamic>>();
    } on Object {
      return <Map<String, dynamic>>[];
    }
  }

  /// До 5 URL для шапки профиля: [avatarUrl] + последние фото из чата от [peerUserId].
  static List<String> peerGalleryUrls({
    required String peerUserId,
    String? avatarUrl,
    required List<Map<String, dynamic>> messagesNewestFirst,
  }) {
    final List<String> out = <String>[];
    final Set<String> seen = <String>{};
    void add(String? u) {
      final String? t = u?.trim();
      if (t == null || t.isEmpty || seen.contains(t)) {
        return;
      }
      seen.add(t);
      out.add(t);
    }

    add(avatarUrl);
    for (final Map<String, dynamic> m in messagesNewestFirst) {
      if (out.length >= 5) {
        break;
      }
      if (m['sender_id']?.toString() != peerUserId) {
        continue;
      }
      if (m['deleted_at'] != null) {
        continue;
      }
      final String body = (m['body'] as String?) ?? '';
      add(imageUrlFromMessageBody(body));
    }
    return out;
  }

  static Future<void> sendMessage(
    String conversationId,
    String body, {
    String? forwardedFromUserId,
    String? forwardedFromLabel,
  }) async {
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
    final Map<String, dynamic> row = <String, dynamic>{
      'conversation_id': conversationId,
      'sender_id': uid,
      'body': t,
    };
    final String? fwdId = forwardedFromUserId?.trim();
    final String? fwdLabel = forwardedFromLabel?.trim();
    if (fwdId != null &&
        fwdId.isNotEmpty &&
        fwdLabel != null &&
        fwdLabel.isNotEmpty) {
      row['forwarded_from_user_id'] = fwdId;
      row['forwarded_from_label'] = fwdLabel;
    }
    await c.from('chat_messages').insert(row);
  }

  /// Копирует сообщения без метки «переслано от» (устаревший сценарий).
  static Future<void> forwardMessageBodies(
    String toConversationId,
    List<String> bodies,
  ) async {
    for (final String raw in bodies) {
      final String t = raw.trim();
      if (t.isEmpty) {
        continue;
      }
      await sendMessage(toConversationId, t);
    }
  }

  static Future<void> sendImageMessage(
    String conversationId,
    String publicImageUrl,
  ) async {
    final String u = publicImageUrl.trim();
    if (u.isEmpty) {
      return;
    }
    return sendMessage(conversationId, '$imageMessagePrefix$u');
  }

  static String? imageUrlFromMessageBody(String body) {
    if (!body.startsWith(imageMessagePrefix)) {
      return null;
    }
    final String u = body.substring(imageMessagePrefix.length).trim();
    if (u.isEmpty) {
      return null;
    }
    return u;
  }

  static Future<void> setMyUsername(String? username) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    await c.rpc(
      'set_my_username',
      params: <String, dynamic>{'p_username': username},
    );
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

  static Future<void> addGroupParticipant(
    String conversationId,
    String userId,
  ) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    await c.rpc(
      'add_group_participant',
      params: <String, dynamic>{
        'p_conversation_id': conversationId,
        'p_user_id': userId,
      },
    );
  }

  static Future<void> removeGroupParticipant(
    String conversationId,
    String userId,
  ) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    await c.rpc(
      'remove_group_participant',
      params: <String, dynamic>{
        'p_conversation_id': conversationId,
        'p_user_id': userId,
      },
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
    await c.rpc(
      'soft_delete_group_message',
      params: <String, dynamic>{'p_message_id': messageId},
    );
  }

  static Future<List<Map<String, dynamic>>> searchProfilesForChat(
    String query,
  ) async {
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

  static Future<Map<String, dynamic>?> fetchConversation(
    String conversationId,
  ) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      return null;
    }
    return c
        .from('conversations')
        .select()
        .eq('id', conversationId)
        .maybeSingle();
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
    final Map<String, Map<String, dynamic>> byU =
        <String, Map<String, dynamic>>{
          for (final Map<String, dynamic> p
              in profs.cast<Map<String, dynamic>>())
            p['id']!.toString(): p,
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
    final Map<String, dynamic>? row = await c
        .from('profiles')
        .select('first_name, last_name')
        .eq('id', userId)
        .maybeSingle();
    if (row == null) {
      return 'Пользователь';
    }
    final String fn = (row['first_name'] as String?)?.trim() ?? '';
    final String ln = (row['last_name'] as String?)?.trim() ?? '';
    final String t = ('$fn $ln').trim();
    return t.isNotEmpty ? t : 'Пользователь';
  }

  /// Только личный чат: удалить все сообщения, беседа остаётся.
  static Future<void> clearConversationHistory(String conversationId) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    await c.rpc(
      'clear_conversation_history',
      params: <String, dynamic>{'p_conversation_id': conversationId},
    );
  }

  /// Личный: любой участник. Группа: только владелец.
  static Future<void> deleteConversationCompletely(
    String conversationId,
  ) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    await c.rpc(
      'delete_conversation_completely',
      params: <String, dynamic>{'p_conversation_id': conversationId},
    );
  }

  static Future<void> leaveGroupConversation(String conversationId) async {
    final SupabaseClient? c = _c;
    if (c == null) {
      throw StateError('Supabase не готов');
    }
    final String? me = c.auth.currentUser?.id;
    if (me == null) {
      throw StateError('Нет сессии');
    }
    await removeGroupParticipant(conversationId, me);
  }

  /// Короткое имя беседы для уведомления.
  static Future<String> titleForNotification(String conversationId) async {
    final Map<String, dynamic>? row = await fetchConversation(conversationId);
    if (row == null) {
      return 'Чат';
    }
    final bool isGroup =
        row['is_group'] as bool? ?? !(row['is_direct'] as bool? ?? true);
    if (isGroup) {
      final String? g = (row['group_name'] as String?)?.trim();
      return (g != null && g.isNotEmpty) ? g : 'Группа';
    }
    final String? other = await otherParticipantId(conversationId);
    if (other == null) {
      return 'Чат';
    }
    return await displayNameForUserId(other) ?? 'Чат';
  }
}

/// Мета вложения в теле сообщения [ChatService.fileMessagePrefix].
class ChatFileMeta {
  const ChatFileMeta({
    required this.url,
    required this.name,
    required this.mime,
  });

  final String url;
  final String name;
  final String mime;

  bool get isImage =>
      mime.toLowerCase().startsWith('image/') ||
      _imageName(name);

  bool get isVideo =>
      mime.toLowerCase().startsWith('video/') ||
      _videoName(name);

  static bool _imageName(String n) {
    final String l = n.toLowerCase();
    return l.endsWith('.png') ||
        l.endsWith('.jpg') ||
        l.endsWith('.jpeg') ||
        l.endsWith('.gif') ||
        l.endsWith('.webp');
  }

  static bool _videoName(String n) {
    final String l = n.toLowerCase();
    return l.endsWith('.mp4') ||
        l.endsWith('.webm') ||
        l.endsWith('.mov') ||
        l.endsWith('.mkv');
  }
}
