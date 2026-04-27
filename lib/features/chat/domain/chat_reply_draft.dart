import 'package:meta/meta.dart';

/// Ожидаемый ответ: выбранное сообщение + снимок для БД и шапки над полем ввода.
@immutable
class ChatReplyDraft {
  const ChatReplyDraft({
    required this.targetMessageId,
    required this.authorUserId,
    required this.authorLabel,
    required this.snippet,
  });

  final String targetMessageId;
  final String authorUserId;
  final String authorLabel;
  final String snippet;
}
