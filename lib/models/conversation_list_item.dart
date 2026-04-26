/// Элемент списка чатов (модель для UI).
class ConversationListItem {
  const ConversationListItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.timeText,
    required this.sortKeyMs,
    this.otherUserId,
    this.otherAvatarUrl,
    this.isGroup = false,
    this.isOpen,
    this.myRole,
    this.groupName,
    this.hasUnread = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final String timeText;
  final int sortKeyMs;

  /// Собеседник в личном чате.
  final String? otherUserId;

  /// Аватар собеседника (если есть в [profiles.avatar_url]).
  final String? otherAvatarUrl;
  final bool isGroup;

  /// Только для группы: открытая (любой участник добавляет) или закрытая.
  final bool? isOpen;

  /// Роль текущего пользователя: owner | moderator | member.
  final String? myRole;
  final String? groupName;

  /// Входящие непрочитанные (есть сообщения от других после [last_read_at]).
  final bool hasUnread;

  bool get canModerate => myRole == 'owner' || myRole == 'moderator';
}
