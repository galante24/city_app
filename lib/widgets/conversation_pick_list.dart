import 'package:flutter/material.dart';

import '../app_constants.dart';
import '../config/supabase_ready.dart';
import 'city_network_image.dart';
import '../models/conversation_list_item.dart';
import '../services/chat_service.dart';

/// Список бесед для выбора (пересылка, «поделиться» в чат).
class ConversationPickList extends StatelessWidget {
  const ConversationPickList({
    super.key,
    this.excludeConversationId,
    required this.onPick,
    required this.emptyMessage,
  });

  final String? excludeConversationId;
  final ValueChanged<ConversationListItem> onPick;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    if (!supabaseAppReady) {
      return const Center(child: Text('Supabase не настроен'));
    }

    return FutureBuilder<List<ConversationListItem>>(
      future: ChatService.listConversations(),
      builder:
          (BuildContext c, AsyncSnapshot<List<ConversationListItem>> snap) {
        if (snap.hasError) {
          return Center(child: Text('Ошибка: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final List<ConversationListItem> list = snap.data!
            .where(
              (ConversationListItem e) =>
                  excludeConversationId == null ||
                  e.id != excludeConversationId,
            )
            .toList();
        if (list.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
              ),
            ),
          );
        }
        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (BuildContext context, int index) => Divider(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.5),
          ),
          itemBuilder: (BuildContext c, int i) {
            final ConversationListItem item = list[i];
            return Material(
              color: cs.surface,
              child: InkWell(
                onTap: () => onPick(item),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: <Widget>[
                      CircleAvatar(
                        backgroundColor: kPrimaryBlue.withValues(alpha: 0.2),
                        child: item.isGroup
                            ? const Icon(
                                Icons.group,
                                color: kPrimaryBlue,
                                size: 22,
                              )
                            : (item.otherAvatarUrl != null &&
                                      item.otherAvatarUrl!.isNotEmpty
                                  ? CityNetworkImage.avatar(
                                      context: c,
                                      imageUrl: item.otherAvatarUrl,
                                      diameter: 40,
                                    )
                                  : Text(
                                      item.title.isNotEmpty
                                          ? item.title[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: kPrimaryBlue,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color: cs.onSurfaceVariant,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
