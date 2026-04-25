/// Элемент списка чатов (модель для UI).
class ConversationListItem {
  const ConversationListItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.timeText,
    required this.sortKeyMs,
    this.otherUserId,
    this.isGroup = false,
    this.isOpen,
    this.myRole,
    this.groupName,
  });

  final String id;
  final String title;
  final String subtitle;
  final String timeText;
  final int sortKeyMs;
  /// Собеседник в личном чате.
  final String? otherUserId;
  final bool isGroup;
  /// Только для группы: открытая (любой участник добавляет) или закрытая.
  final bool? isOpen;
  /// Роль текущего пользователя: owner | moderator | member.
  final String? myRole;
  final String? groupName;

  bool get canModerate =>
      myRole == 'owner' || myRole == 'moderator';
}
