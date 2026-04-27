import 'package:meta/meta.dart';

/// Событие строки `chat_messages` с сервера (после Realtime → репозиторий).
@immutable
class ChatMessageRowEvent {
  const ChatMessageRowEvent._({
    required this.isInsert,
    required this.isUpdate,
    required this.isDelete,
    this.newRecord,
    this.oldRecord,
  });

  factory ChatMessageRowEvent.insert(Map<String, dynamic> newRecord) {
    return ChatMessageRowEvent._(
      isInsert: true,
      isUpdate: false,
      isDelete: false,
      newRecord: newRecord,
    );
  }

  factory ChatMessageRowEvent.update(
    Map<String, dynamic> newRecord,
    Map<String, dynamic> oldRecord,
  ) {
    return ChatMessageRowEvent._(
      isInsert: false,
      isUpdate: true,
      isDelete: false,
      newRecord: newRecord,
      oldRecord: oldRecord,
    );
  }

  factory ChatMessageRowEvent.delete(Map<String, dynamic> oldRecord) {
    return ChatMessageRowEvent._(
      isInsert: false,
      isUpdate: false,
      isDelete: true,
      oldRecord: oldRecord,
    );
  }

  final bool isInsert;
  final bool isUpdate;
  final bool isDelete;
  final Map<String, dynamic>? newRecord;
  final Map<String, dynamic>? oldRecord;
}
