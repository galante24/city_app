import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_card_styles.dart';
import '../app_constants.dart';
import '../services/chat_service.dart';
import '../services/city_data_service.dart';
import '../services/task_push_service.dart';
import '../services/task_service.dart';
import '../utils/author_embed.dart';
import '../utils/mention_utils.dart';
import '../utils/social_time_format.dart';
import '../widgets/social_comment_tile.dart';
import '../widgets/social_header.dart';
import '../widgets/soft_tab_header.dart';
import '../widgets/weather_app_bar_action.dart';
import 'user_chat_thread_screen.dart';

class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({
    super.key,
    required this.row,
    required this.accent,
  });

  final Map<String, dynamic> row;
  final Color accent;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _commentsKey = GlobalKey();
  final TextEditingController _commentInput = TextEditingController();
  final FocusNode _commentFocus = FocusNode();

  bool _busy = false;
  bool? _canDelete;
  List<Map<String, dynamic>> _comments = <Map<String, dynamic>>[];
  bool _commentsLoading = true;

  String get _id => widget.row['id']?.toString() ?? '';
  String get _authorId => widget.row['author_id']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_resolveCanDelete());
    unawaited(_loadComments());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _commentInput.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    if (_id.isEmpty) {
      return;
    }
    setState(() => _commentsLoading = true);
    final List<Map<String, dynamic>> list = await TaskService.fetchComments(_id);
    if (mounted) {
      setState(() {
        _comments = list;
        _commentsLoading = false;
      });
    }
  }

  Future<void> _resolveCanDelete() async {
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) {
      if (mounted) {
        setState(() => _canDelete = false);
      }
      return;
    }
    if (_authorId == me) {
      if (mounted) {
        setState(() => _canDelete = true);
      }
      return;
    }
    if (CityDataService.isCurrentUserAdminSync()) {
      if (mounted) {
        setState(() => _canDelete = true);
      }
      return;
    }
    final Map<String, dynamic>? p = await CityDataService.fetchProfileRow(me);
    final bool admin = p?['is_admin'] == true;
    if (mounted) {
      setState(() => _canDelete = admin);
    }
  }

  Future<void> _openChat() async {
    if (_authorId.isEmpty) {
      return;
    }
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) {
      return;
    }
    if (_authorId == me) {
      return;
    }
    setState(() => _busy = true);
    try {
      final String conv = await ChatService.getOrCreateDirectConversation(
        _authorId,
      );
      final String name =
          (await ChatService.displayNameForUserId(_authorId)) ?? 'Чат';
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext c) => UserChatThreadScreen(
            conversationId: conv,
            title: name,
            listItem: null,
            directPeerUserId: _authorId,
          ),
        ),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть чат')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _call(String phone) async {
    final Uri? uri = _telUri(phone);
    if (uri == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Некорректный номер')),
        );
      }
      return;
    }
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Не удалось открыть звонок'),
            ),
          );
        }
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Звонок: $e')),
        );
      }
    }
  }

  static Uri? _telUri(String raw) {
    final String d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) {
      return null;
    }
    if (d.length == 11 && d.startsWith('7')) {
      return Uri.parse('tel:+$d');
    }
    if (d.length == 10) {
      return Uri.parse('tel:+7$d');
    }
    return Uri.parse('tel:${raw.trim()}');
  }

  void _scrollToComments() {
    final BuildContext? ctx = _commentsKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: 0.1,
      );
    }
  }

  void _insertMention(String snippet) {
    final String s = snippet.trim();
    if (s.isEmpty) {
      return;
    }
    final TextEditingValue v = _commentInput.value;
    final String next = '${v.text}$s';
    _commentInput.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _commentFocus.requestFocus();
  }

  Future<void> _sendComment() async {
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы комментировать')),
      );
      return;
    }
    final String t = _commentInput.text.trim();
    if (t.isEmpty || _id.isEmpty) {
      return;
    }
    try {
      final List<String> mentioned =
          await resolveMentionedUserIds(t);
      final List<String> targets = mentioned
          .where((String id) => id != me)
          .toList();
      await TaskService.addComment(_id, t);
      if (!mounted) {
        return;
      }
      _commentInput.clear();
      FocusScope.of(context).unfocus();
      await _loadComments();
      final String taskTitle =
          (widget.row['title'] as String?)?.trim() ?? 'Задача';
      if (targets.isNotEmpty) {
        unawaited(
          TaskPushService.notifyMentionsIfNeeded(
            taskId: _id,
            taskTitle: taskTitle,
            mentionedUserIds: targets,
          ),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Комментарий: $e')),
        );
      }
    }
  }

  String? _formatTaskPrice(dynamic raw) {
    if (raw == null) {
      return null;
    }
    final num? n = raw is num ? raw : num.tryParse(raw.toString());
    if (n == null || n <= 0) {
      return null;
    }
    final NumberFormat fmt = NumberFormat.currency(
      locale: 'ru',
      symbol: '₽',
      decimalDigits: 0,
    );
    return fmt.format(n);
  }

  Future<void> _delete() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) {
        return AlertDialog(
          title: const Text('Удалить объявление?'),
          content: const Text('Запись будет удалена без восстановления.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );
    if (ok != true) {
      return;
    }
    setState(() => _busy = true);
    try {
      await TaskService.deleteById(_id);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Удалено')),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String title = widget.row['title'] as String? ?? '';
    final String desc = widget.row['description'] as String? ?? '';
    final String phoneRaw = (widget.row['phone'] as String? ?? '').trim();
    final bool hasPhone = phoneRaw.isNotEmpty;
    final String? priceLabel = _formatTaskPrice(widget.row['price']);
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    final bool isOwner = me != null && me == _authorId;
    final bool showChat = me != null && !isOwner && _authorId.isNotEmpty;
    final bool showCall = hasPhone && !isOwner;

    final ColorScheme cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SoftTabHeader(
            leading: const SoftHeaderBackButton(),
            title: 'Задача',
            trailing: SoftHeaderWeatherWithAction(
              action: _canDelete == true
                  ? IconButton(
                      onPressed: _busy ? null : _delete,
                      icon: Icon(
                        Icons.delete_outline,
                        color: softHeaderTrailingIconColor(context),
                        size: 26,
                      ),
                      tooltip: 'Удалить',
                    )
                  : null,
            ),
          ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              children: <Widget>[
                if (_authorId.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Container(
                      decoration: cloudCardDecoration(context, radius: 18),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: SocialHeader(
                        userId: _authorId,
                        author: authorMapFromRow(widget.row),
                        createdAt: parseIsoUtc(
                          widget.row['created_at'] as String?,
                        ),
                      ),
                    ),
                  ),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                    height: 1.2,
                  ),
                ),
                if (priceLabel != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    priceLabel,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF2E7D32),
                      height: 1.1,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  decoration: cloudCardDecoration(context, radius: 18),
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    desc,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: cs.onSurface.withValues(alpha: 0.92),
                    ),
                  ),
                ),
                if (showCall) ...<Widget>[
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => unawaited(_call(phoneRaw)),
                    icon: const Icon(Icons.phone_in_talk_rounded),
                    label: const Text(
                      'Позвонить',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  key: _commentsKey,
                  children: <Widget>[
                    Icon(Icons.forum_outlined, color: widget.accent, size: 26),
                    const SizedBox(width: 8),
                    Text(
                      'Комментарии и вопросы',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Публичное обсуждение под объявлением',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                if (_commentsLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_comments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Пока нет комментариев',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  )
                else
                  ..._comments.map((Map<String, dynamic> m) {
                    final String uid = m['user_id']?.toString() ?? '';
                    final String text = (m['text'] as String?) ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SocialCommentTile(
                        userId: uid,
                        bodyText: text,
                        author: authorMapFromRow(m),
                        createdAtIso: m['created_at'] as String?,
                        onMentionInsert: _insertMention,
                      ),
                    );
                  }),
                const SizedBox(height: 8),
                if (me != null)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Expanded(
                        child: Container(
                          decoration:
                              cloudCardDecoration(context, radius: 14),
                          child: TextField(
                            controller: _commentInput,
                            focusNode: _commentFocus,
                            minLines: 1,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText:
                                  'Уточняющий вопрос… (@ник для упоминания)',
                              filled: true,
                              fillColor: Colors.transparent,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _sendComment,
                        style: FilledButton.styleFrom(
                          backgroundColor: kPrimaryBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Icon(Icons.send_rounded),
                      ),
                    ],
                  )
                else
                  Text(
                    'Войдите, чтобы оставить комментарий',
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 120),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Material(
          elevation: 8,
          color: cs.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              children: <Widget>[
                if (showChat)
                  Expanded(
                    child: _ContactPillButton(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: 'Написать\nв чат',
                      color: kPrimaryBlue,
                      onTap: _busy ? null : _openChat,
                    ),
                  ),
                if (showChat && showCall) const SizedBox(width: 10),
                if (showCall)
                  Expanded(
                    child: _ContactPillButton(
                      icon: Icons.phone_in_talk_rounded,
                      label: 'Позвонить',
                      color: const Color(0xFF2E7D32),
                      onTap: _busy ? null : () => unawaited(_call(phoneRaw)),
                    ),
                  ),
                if ((showChat || showCall)) const SizedBox(width: 10),
                Expanded(
                  child: _ContactPillButton(
                    icon: Icons.comment_outlined,
                    label: 'Комментарии',
                    color: const Color(0xFF6A1B9A),
                    onTap: _scrollToComments,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactPillButton extends StatelessWidget {
  const _ContactPillButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool enabled = onTap != null;
    return Material(
      color: enabled ? color.withValues(alpha: 0.12) : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: enabled
                  ? color.withValues(alpha: 0.45)
                  : cs.outline.withValues(alpha: 0.3),
              width: 1.2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 28,
                color: enabled ? color : cs.onSurfaceVariant,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  color: enabled ? color : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
