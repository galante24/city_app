import 'package:meta/meta.dart';

import '../domain/chat_message_row_event.dart';

/// Команда применения к in-memory ленте (нотификатор выполняет).
@immutable
sealed class MessageSyncCommand {
  const MessageSyncCommand();
}

/// idempotent upsert по server id
@immutable
class MessageSyncUpsert extends MessageSyncCommand {
  const MessageSyncUpsert(this.serverId, this.row);
  final String serverId;
  final Map<String, dynamic> row;
}

@immutable
class MessageSyncDelete extends MessageSyncCommand {
  const MessageSyncDelete(this.serverId);
  final String serverId;
}

/// Заменить ключ local → server (оптимистичное сообщение получило uuid).
@immutable
class MessageSyncRekey extends MessageSyncCommand {
  const MessageSyncRekey({
    required this.localId,
    required this.serverId,
    required this.row,
  });
  final String localId;
  final String serverId;
  final Map<String, dynamic> row;
}

/// localId (клиент) ↔ serverId (Postgres) — скролл, ответ, dedupe.
class MessageIdRegistry {
  String? _serverForLocal(String local) => _localToServer[local];
  String? _localForServer(String server) => _serverToLocal[server];

  final Map<String, String> _localToServer = <String, String>{};
  final Map<String, String> _serverToLocal = <String, String>{};

  void link({required String localId, required String serverId}) {
    if (localId.isEmpty || serverId.isEmpty || localId == serverId) {
      return;
    }
    _localToServer[localId] = serverId;
    _serverToLocal[serverId] = localId;
  }

  void unlinkLocal(String localId) {
    final String? s = _localToServer.remove(localId);
    if (s != null) {
      _serverToLocal.remove(s);
    }
  }

  /// Для ключа/скролла: всегда server id, если отмаплен.
  String canonicalMessageId(String anyId) {
    if (anyId.isEmpty) {
      return anyId;
    }
    return _serverForLocal(anyId) ?? anyId;
  }

  String? otherSideId(String anyId) {
    return _serverForLocal(anyId) ?? _localForServer(anyId);
  }

  /// Лента хранит local **или** server id — дедupe для UPDATE/DELETE.
  bool inMaterializedSet(Set<String> materialized, String serverId) {
    if (serverId.isEmpty) {
      return false;
    }
    if (materialized.contains(serverId)) {
      return true;
    }
    final String? l = _serverToLocal[serverId];
    return l != null && materialized.contains(l);
  }
}

/// Буфер «update до insert» + идемпотентность; WebSocket **не** трогает UI —
/// только через [MessageSyncCommand] в нотификаторе.
class MessageSyncLedger {
  MessageSyncLedger({MessageIdRegistry? registry})
      : registry = registry ?? MessageIdRegistry();

  final MessageIdRegistry registry;

  /// server id → смерженные поля, пока строки нет в ленте
  final Map<String, Map<String, dynamic>> _pendingRemote =
      <String, Map<String, dynamic>>{};

  /// (sender_id, bodyNorm, timeBucket) → localId для [tryLinkInsertToLocal]
  final Map<String, String> _optimisticFingerprints = <String, String>{};

  static String? _idOf(Map<String, dynamic>? m) {
    if (m == null) {
      return null;
    }
    return m['id']?.toString();
  }

  void registerOptimisticMessage({
    required String localId,
    required String senderId,
    required String body,
  }) {
    final String fp = _fp(senderId, body);
    _optimisticFingerprints[fp] = localId;
  }

  void clearOptimisticByLocalId(String localId) {
    _optimisticFingerprints.removeWhere(
      (String k, String v) => v == localId,
    );
  }

  String _fp(String senderId, String body) {
    return '$senderId|${body.trim().hashCode}';
  }

  /// Дедуп: один server id = один upsert, последняя запись выигрывает.
  static Map<String, dynamic> _cloneRow(Map<String, dynamic> m) {
    return Map<String, dynamic>.from(m);
  }

  static Map<String, dynamic>? _mergePending(
    Map<String, dynamic>? a,
    Map<String, dynamic> b,
  ) {
    if (a == null) {
      return _cloneRow(b);
    }
    final Map<String, dynamic> o = _cloneRow(a);
    o.addAll(b);
    return o;
  }

  List<MessageSyncCommand> process({
    required ChatMessageRowEvent event,
    required Set<String> materializedServerIds,
  }) {
    if (event.isDelete) {
      final String? id = _idOf(event.oldRecord);
      if (id == null) {
        return <MessageSyncCommand>[];
      }
      _pendingRemote.remove(id);
      return <MessageSyncCommand>[MessageSyncDelete(id)];
    }

    if (event.isUpdate) {
      final String? id = _idOf(event.newRecord) ?? _idOf(event.oldRecord);
      if (id == null) {
        return <MessageSyncCommand>[];
      }
      final Map<String, dynamic> next = _mergePending(
        _pendingRemote.remove(id),
        event.newRecord!,
      )!;
      if (!registry.inMaterializedSet(materializedServerIds, id)) {
        _pendingRemote[id] = next;
        return <MessageSyncCommand>[];
      }
      return <MessageSyncCommand>[MessageSyncUpsert(id, next)];
    }

    if (event.isInsert) {
      final String? id = _idOf(event.newRecord);
      if (id == null) {
        return <MessageSyncCommand>[];
      }
      final Map<String, dynamic> next = _mergePending(
        _pendingRemote.remove(id),
        event.newRecord!,
      )!;

      final String? sender = next['sender_id']?.toString();
      final String body = (next['body'] as String?)?.trim() ?? '';
      if (sender != null && body.isNotEmpty) {
        final String fp = _fp(sender, body);
        final String? local = _optimisticFingerprints.remove(fp);
        if (local != null && local != id) {
          registry.link(localId: local, serverId: id);
          return <MessageSyncCommand>[
            MessageSyncRekey(localId: local, serverId: id, row: next),
          ];
        }
      }

      return <MessageSyncCommand>[MessageSyncUpsert(id, next)];
    }

    return <MessageSyncCommand>[];
  }
}
