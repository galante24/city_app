import 'package:meta/meta.dart';

/// Ссылка на медиа (этап структуры: не блокирует UI, загрузка отдельно).
@immutable
class ChatMessageMediaRef {
  const ChatMessageMediaRef({
    this.thumbnailUrl,
    this.fullUrl,
    this.localPath,
    this.isLoading = false,
  });

  final String? thumbnailUrl;
  final String? fullUrl;
  final String? localPath;
  final bool isLoading;
}
