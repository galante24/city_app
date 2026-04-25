/// Элемент списка чатов (модель для UI).
class ConversationListItem {
  const ConversationListItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.timeText,
    required this.sortKeyMs,
    this.otherUserId,
  });

  final String id;
  final String title;
  final String subtitle;
  final String timeText;
  final int sortKeyMs;
  final String? otherUserId;
}
