import '../services/chat_service.dart';

/// Черновик пересылки: автор оригинала и тело без обёртки.
class ChatForwardDraft {
  const ChatForwardDraft({
    required this.originalSenderId,
    required this.originalSenderLabel,
    required this.innerBody,
  });

  final String originalSenderId;
  final String originalSenderLabel;
  final String innerBody;

  String get previewSnippet {
    final String t = innerBody.trim();
    if (t.startsWith(ChatService.imageMessagePrefix)) {
      return '📷 Фото';
    }
    if (t.startsWith(ChatService.fileMessagePrefix)) {
      final ChatFileMeta? m = ChatService.fileMetaFromMessageBody(t);
      return m == null ? '📎 Файл' : m.name;
    }
    final ChatPlaceShareParsed? ps = ChatService.parsePlaceShareBody(t);
    if (ps != null) {
      final String h = ps.headline.trim();
      if (h.isEmpty) {
        return '📍 Заведение';
      }
      return h.length > 80 ? '${h.substring(0, 77)}…' : h;
    }
    if (t.length > 90) {
      return '${t.substring(0, 87)}…';
    }
    return t;
  }
}
