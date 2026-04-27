import '../../../services/chat_service.dart' show ChatFileMeta, ChatPlaceShareParsed, ChatService;

/// Краткая подпись содержимого сообщения (для reply / превью), без сети.
String chatMessageSnippetForReply(Map<String, dynamic> m) {
  if (m['deleted_at'] != null) {
    return '';
  }
  final String bodyRaw = (m['body'] as String?) ?? '';
  final String? imageUrl = ChatService.imageUrlFromMessageBody(bodyRaw);
  final ChatFileMeta? fileMeta = ChatService.fileMetaFromMessageBody(bodyRaw);
  if (imageUrl != null && imageUrl.isNotEmpty) {
    return '[Фото]';
  }
  if (fileMeta != null) {
    return fileMeta.isImage ? '[Фото]' : fileMeta.name;
  }
  final ChatPlaceShareParsed? ps = ChatService.parsePlaceShareBody(bodyRaw);
  if (ps != null) {
    final String h = ps.headline.trim();
    return h.isEmpty ? '📍 Заведение' : h;
  }
  final String t = bodyRaw.trim();
  if (t.length > 160) {
    return '${t.substring(0, 157)}…';
  }
  return t;
}
