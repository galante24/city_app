/// Данные для подписи и аватара участника в групповом пузырьке.
class GroupChatSenderDisplay {
  const GroupChatSenderDisplay({
    required this.profileTitle,
    required this.bubbleLabel,
    this.avatarUrl,
  });

  final String profileTitle;
  final String bubbleLabel;
  final String? avatarUrl;

  static const GroupChatSenderDisplay placeholder = GroupChatSenderDisplay(
    profileTitle: 'Участник',
    bubbleLabel: '…',
  );

  static GroupChatSenderDisplay fromRow(Map<String, dynamic>? row) {
    if (row == null) {
      return placeholder;
    }
    final String? uname = (row['username'] as String?)?.trim();
    final String fn = (row['first_name'] as String?)?.trim() ?? '';
    final String ln = (row['last_name'] as String?)?.trim() ?? '';
    final String full = ('$fn $ln').trim();
    final String profileTitle = full.isNotEmpty
        ? full
        : (uname != null && uname.isNotEmpty ? '@$uname' : 'Участник');
    final String bubbleLabel = (uname != null && uname.isNotEmpty)
        ? '@$uname'
        : (full.isNotEmpty ? full : 'Участник');
    final String? av = (row['avatar_url'] as String?)?.trim();
    return GroupChatSenderDisplay(
      profileTitle: profileTitle,
      bubbleLabel: bubbleLabel,
      avatarUrl: (av != null && av.isNotEmpty) ? av : null,
    );
  }
}
