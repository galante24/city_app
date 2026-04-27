import 'package:meta/meta.dart';

/// Данные для полоски «ответ на» внутри пузырька.
@immutable
class ChatReplyStripData {
  const ChatReplyStripData({
    required this.targetMessageId,
    required this.authorLabel,
    required this.snippet,
    required this.isOriginalDeleted,
  });

  final String targetMessageId;
  final String authorLabel;
  final String snippet;
  final bool isOriginalDeleted;

  /// [original] — строка оригинала из кэша ленты, если есть.
  static ChatReplyStripData? fromMessageRow(
    Map<String, dynamic> m, {
    Map<String, dynamic>? original,
  }) {
    final String? rid = m['reply_to_message_id']?.toString();
    if (rid == null || rid.isEmpty) {
      return null;
    }
    final String rawLabel = (m['reply_author_label'] as String?)?.trim() ?? '';
    final String author = rawLabel.isNotEmpty ? rawLabel : 'Сообщение';
    final String rawSnip = (m['reply_snippet'] as String?)?.trim() ?? '';
    // reply_snippet в БД — кэст для превью; `original` — актуальная строка, если в памяти.
    final bool del = original != null && original['deleted_at'] != null;
    final String snippet =
        del ? 'Сообщение удалено' : (rawSnip.isNotEmpty ? rawSnip : '…');
    return ChatReplyStripData(
      targetMessageId: rid,
      authorLabel: author,
      snippet: snippet,
      isOriginalDeleted: del,
    );
  }
}
