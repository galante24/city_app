import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/conversation_list_item.dart';
import '../../screens/home_screen.dart' show SocialPost;
import '../../services/chat_service.dart';
import '../../services/feed_service.dart';

/// Выбор активного чата и отправка карточки-превью поста.
Future<void> showFeedShareToChatDialog({
  required BuildContext context,
  required FeedService feed,
  required SocialPost post,
}) async {
  final List<ConversationListItem> items =
      await ChatService.listConversations();
  if (!context.mounted) {
    return;
  }
  if (items.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Нет активных чатов')));
    return;
  }
  final ConversationListItem? picked = await showDialog<ConversationListItem>(
    context: context,
    builder: (BuildContext ctx) {
      return AlertDialog(
        title: const Text('Поделиться в чате'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: items.length,
            itemBuilder: (_, int i) {
              final ConversationListItem it = items[i];
              return ListTile(
                title: Text(it.title),
                subtitle: it.subtitle.isNotEmpty ? Text(it.subtitle) : null,
                onTap: () => Navigator.pop(ctx, it),
              );
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
        ],
      );
    },
  );
  if (picked == null || !context.mounted) {
    return;
  }
  final String body = ChatService.buildFeedPostShareBody(
    postId: post.id,
    title: post.title,
    thumbUrl: post.imageUrls.isNotEmpty ? post.imageUrls.first : post.mediaUrl,
  );
  try {
    await ChatService.sendMessage(picked.id, body);
  } on Object catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не отправлено: $e')));
    }
    return;
  }
  final String? actorId = Supabase.instance.client.auth.currentUser?.id;
  final String? authorId = post.userId;
  if (actorId != null &&
      authorId != null &&
      authorId.isNotEmpty &&
      authorId != actorId) {
    try {
      await feed.notifyRepost(
        postAuthorId: authorId,
        postId: post.id,
        titleSnippet: post.title,
      );
    } on Object {
      // уведомление — вторично
    }
  }
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Отправлено в чат')));
  }
}
