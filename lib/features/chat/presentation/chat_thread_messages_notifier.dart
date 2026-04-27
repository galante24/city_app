import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../data/message_sync_ledger.dart';
import '../domain/chat_message.dart';
import '../domain/chat_message_row_event.dart';
import '../domain/chat_messages_repository.dart';

/// Лента: нормализованное хранение `messageIds` + `messagesById` + per-row версия для
/// гранулярных [Selector] в UI, пагинация + Realtime.
class ChatThreadMessagesNotifier extends ChangeNotifier {
  ChatThreadMessagesNotifier({
    required this.conversationId,
    required ChatMessagesRepository repository,
    String? ownUserId,
  })  : _repo = repository,
        _ownUserId = ownUserId {
    // ignore: discarded_futures
    _bootstrap();
  }

  final String conversationId;
  final ChatMessagesRepository _repo;
  final String? _ownUserId;

  static const int kPageSize = 50;
  static const int kMaxMessagesInMemory = 800;

  final List<String> _messageIds = <String>[];
  final Map<String, Map<String, dynamic>> _byId =
      <String, Map<String, dynamic>>{};
  final Map<String, int> _rowVersion = <String, int>{};

  bool _initialLoading = true;
  bool _loadingOlder = false;
  bool _hasMoreOlder = true;
  Object? _error;
  StreamSubscription<ChatMessageRowEvent>? _rowEventSub;
  final MessageSyncLedger _sync = MessageSyncLedger();
  bool _disposed = false;

  int get messageCount => _messageIds.length;

  UnmodifiableListView<String> get messageIdsUnmodifiable =>
      UnmodifiableListView<String>(_messageIds);

  UnmodifiableListView<Map<String, dynamic>> get messages =>
      UnmodifiableListView<Map<String, dynamic>>(
        _messageIds.map((String id) => _byId[id]!).toList(),
      );

  /// Упорядоченные строки (для пересылки, снапшотов) — O(n) копия.
  List<Map<String, dynamic>> get orderedMessageRows => _messageIds
      .map((String id) => _byId[id]!)
      .toList(growable: false);

  String? get firstMessageId =>
      _messageIds.isEmpty ? null : _messageIds.first;
  String? get lastMessageId =>
      _messageIds.isEmpty ? null : _messageIds.last;

  String messageIdAtIndex(int index) {
    if (index < 0 || index >= _messageIds.length) {
      throw StateError(
        'messageIdAtIndex: index $index, length ${_messageIds.length}',
      );
    }
    return _messageIds[index];
  }

  /// Сбой версий при смене строки: только для этой строки перерисуется [Selector].
  int messageVersion(String id) => _rowVersion[id] ?? 0;

  String canonicalMessageId(String anyId) =>
      _sync.registry.canonicalMessageId(anyId);

  String? linkedMessageId(String anyId) => _sync.registry.otherSideId(anyId);

  /// Вызвать при оптимистичной вставке (тот же body/sender) до прихода INSERT с сервера.
  void registerOptimisticSend(
    String localId, {
    required String senderId,
    required String body,
  }) {
    if (_disposed) {
      return;
    }
    _sync.registerOptimisticMessage(
      localId: localId,
      senderId: senderId,
      body: body,
    );
  }

  /// Текущая лента + кэш догруженного по id (для reply-strip).
  Map<String, dynamic>? messageById(String id) {
    if (id.isEmpty) {
      return null;
    }
    final String? alt = _sync.registry.otherSideId(id);
    return _byId[id] ?? (alt != null ? _byId[alt] : null);
  }

  void _bumpMessage(String id) {
    if (id.isEmpty) {
      return;
    }
    _rowVersion[id] = (_rowVersion[id] ?? 0) + 1;
  }

  /// Подтянуть одну строку в кэш (оригинал ответа), без обязанности быть в [ordered] ленте.
  Future<void> ensureMessageLoadedForReply(String messageId) async {
    if (_disposed) {
      return;
    }
    final String id = messageId.trim();
    if (id.isEmpty || _byId.containsKey(id)) {
      return;
    }
    try {
      final ChatMessage? row = await _repo.fetchMessageById(
        id,
        conversationId: conversationId,
      );
      if (row == null || _disposed) {
        return;
      }
      if (row.conversationId != conversationId) {
        return;
      }
      _byId[id] = _cloneRow(row.toMap());
      _bumpMessage(id);
      _safeNotify();
    } on Object {
      // тихо: сниппет в строке остаётся единственным подсказом
    }
  }

  /// Подгружает старые страницы, затем при необходимости одну строку по API.
  Future<void> loadUntilMessage(String messageId) async {
    if (_messageIds.contains(messageId)) {
      return;
    }
    int guard = 0;
    while (
        !_messageIds.contains(messageId) && _hasMoreOlder && guard < 50) {
      if (_disposed) {
        return;
      }
      await loadOlder();
      guard++;
    }
    if (_messageIds.contains(messageId) || _disposed) {
      return;
    }
    try {
      final ChatMessage? row = await _repo.fetchMessageById(
        messageId,
        conversationId: conversationId,
      );
      if (row == null || _disposed) {
        return;
      }
      if (row.conversationId != conversationId) {
        return;
      }
      final String id = row.id;
      if (id.isEmpty) {
        return;
      }
      if (!_messageIds.contains(id)) {
        _ingestRemoteRow(row.toMap());
        _trimToMax();
      }
      _safeNotify();
    } on Object {
      // не мешаем навигации: лента без этой строки
    }
  }

  bool get initialLoading => _initialLoading;
  bool get loadingOlder => _loadingOlder;
  bool get hasMoreOlder => _hasMoreOlder;
  Object? get error => _error;

  Future<void> _bootstrap() async {
    try {
      await _loadInitial();
    } on Object catch (e) {
      _error = e;
    } finally {
      _initialLoading = false;
      _safeNotify();
    }
    await _subscribe();
  }

  /// API: от новых к старым; UI: [oldest ... newest] снизу новые.
  Future<void> _loadInitial() async {
    final List<ChatMessage> desc = await _repo.fetchMessagesPage(
      conversationId: conversationId,
      limit: kPageSize,
    );
    _messageIds.clear();
    _byId.clear();
    _rowVersion.clear();
    for (int i = desc.length - 1; i >= 0; i--) {
      final ChatMessage m = desc[i];
      if (m.id.isNotEmpty) {
        _ingestRemoteRow(m.toMap());
      }
    }
    _hasMoreOlder = desc.length >= kPageSize;
  }

  /// Подгрузка к верху (более старые). Контроллер списка компенсирует offset.
  Future<void> loadOlder() async {
    if (_disposed ||
        _loadingOlder ||
        !_hasMoreOlder ||
        _messageIds.isEmpty) {
      return;
    }
    _loadingOlder = true;
    _safeNotify();
    final String oldestId = _messageIds.first;
    final String? oldestIso = _byId[oldestId]?['created_at']?.toString();
    if (oldestIso == null) {
      _loadingOlder = false;
      _hasMoreOlder = false;
      _safeNotify();
      return;
    }
    try {
      final List<ChatMessage> desc = await _repo.fetchMessagesPage(
        conversationId: conversationId,
        limit: kPageSize,
        beforeCreatedAtIso: oldestIso,
      );
      if (desc.isEmpty) {
        _hasMoreOlder = false;
      } else {
        for (int i = desc.length - 1; i >= 0; i--) {
          final ChatMessage m = desc[i];
          if (m.id.isNotEmpty && !_byId.containsKey(m.id)) {
            _ingestRemoteRow(m.toMap());
          }
        }
        if (desc.length < kPageSize) {
          _hasMoreOlder = false;
        }
        _trimToMax();
      }
    } on Object catch (e) {
      _error = e;
    } finally {
      _loadingOlder = false;
      _safeNotify();
    }
  }

  void _trimToMax() {
    while (_messageIds.length > kMaxMessagesInMemory) {
      final String id = _messageIds.removeAt(0);
      _byId.remove(id);
      _rowVersion.remove(id);
    }
  }

  Future<void> _subscribe() async {
    if (_disposed || _ownUserId == null) {
      return;
    }
    await _rowEventSub?.cancel();
    _rowEventSub = _repo.watchChatMessageRows(conversationId).listen(
      _onRowEvent,
      onError: (Object e, StackTrace _) {
        if (_disposed) {
          return;
        }
        _error = e;
        _safeNotify();
      },
    );
  }

  final Set<String> _ackedDelivery = <String>{};

  void _onRowEvent(ChatMessageRowEvent e) {
    if (_disposed) {
      return;
    }
    _maybeAckPeerDelivery(e);
    final Set<String> mat = _messageIds.toSet();
    final List<MessageSyncCommand> cmds = _sync.process(
      event: e,
      materializedServerIds: mat,
    );
    for (final MessageSyncCommand c in cmds) {
      if (c is MessageSyncUpsert) {
        _ingestRemoteRow(c.row);
      } else if (c is MessageSyncDelete) {
        _removeById(c.serverId);
      } else if (c is MessageSyncRekey) {
        _rekeyRow(c.localId, c.serverId, c.row);
      }
    }
    _trimToMax();
    _safeNotify();
  }

  void _removeById(String id) {
    _messageIds.remove(id);
    _byId.remove(id);
    _rowVersion.remove(id);
  }

  void _rekeyRow(
    String localId,
    String serverId,
    Map<String, dynamic> row,
  ) {
    final int i = _messageIds.indexOf(localId);
    _byId.remove(localId);
    _rowVersion.remove(localId);
    _byId[serverId] = _cloneRow(row);
    _bumpMessage(serverId);
    if (i >= 0) {
      _messageIds[i] = serverId;
    } else if (!_messageIds.contains(serverId)) {
      _insertSorted(serverId);
    }
  }

  Map<String, dynamic> _cloneRow(Map<String, dynamic> rec) {
    return Map<String, dynamic>.from(rec);
  }

  void _ingestRemoteRow(Map<String, dynamic> rec) {
    final String? id = rec['id']?.toString();
    if (id == null) {
      return;
    }
    if (_byId.containsKey(id)) {
      _byId[id] = _cloneRow(<String, dynamic>{..._byId[id]!, ...rec});
    } else {
      _byId[id] = _cloneRow(rec);
    }
    _bumpMessage(id);
    if (_messageIds.contains(id)) {
      return;
    }
    _insertSorted(id);
  }

  void _maybeAckPeerDelivery(ChatMessageRowEvent e) {
    if (!e.isInsert || _ownUserId == null) {
      return;
    }
    final Map<String, dynamic>? rec = e.newRecord;
    if (rec == null) {
      return;
    }
    final String? sid = rec['sender_id']?.toString();
    if (sid == null || sid == _ownUserId) {
      return;
    }
    final String? id = rec['id']?.toString();
    if (id == null || id.isEmpty) {
      return;
    }
    if (_ackedDelivery.contains(id)) {
      return;
    }
    _ackedDelivery.add(id);
    // ignore: discarded_futures
    _repo.ackMessageDelivery(conversationId: conversationId, messageId: id).then(
      (_) => null,
      onError: (Object _, StackTrace st) {
        if (!_disposed) {
          _ackedDelivery.remove(id);
        }
      },
    );
  }

  int _compareCreatedThenId(String aId, String bId) {
    final Map<String, dynamic>? a = _byId[aId];
    final Map<String, dynamic>? b = _byId[bId];
    final String? ca = a?['created_at'] as String?;
    final String? cb = b?['created_at'] as String?;
    if (ca == null && cb == null) {
      return aId.compareTo(bId);
    }
    if (ca == null) {
      return -1;
    }
    if (cb == null) {
      return 1;
    }
    final int c = DateTime.parse(ca).compareTo(DateTime.parse(cb));
    if (c != 0) {
      return c;
    }
    return aId.compareTo(bId);
  }

  void _insertSorted(String id) {
    if (_messageIds.isEmpty) {
      _messageIds.add(id);
      return;
    }
    int lo = 0;
    int hi = _messageIds.length;
    while (lo < hi) {
      final int mid = (lo + hi) >> 1;
      final int cmp = _compareCreatedThenId(_messageIds[mid], id);
      if (cmp < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    _messageIds.insert(lo, id);
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // ignore: unawaited_futures
    _rowEventSub?.cancel();
    _rowEventSub = null;
    super.dispose();
  }
}

/// @deprecated оставлено для существующих вызовов; предпочтительно [ChatThreadMessagesNotifier.orderedMessageRows].
@Deprecated('Используйте orderedMessageRows у нотификатора')
List<Map<String, dynamic>> mergeChatMessageRows(
  List<Map<String, dynamic>>? rows,
) {
  if (rows == null || rows.isEmpty) {
    return <Map<String, dynamic>>[];
  }
  final Map<String, Map<String, dynamic>> byId = <String, Map<String, dynamic>>{};
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
    return DateTime.parse(ca).compareTo(DateTime.parse(cb));
  });
  return out;
}
