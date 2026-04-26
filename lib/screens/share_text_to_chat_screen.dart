import 'dart:async';

import 'package:flutter/material.dart';

import '../app_navigator_key.dart';
import '../models/conversation_list_item.dart';
import '../services/chat_service.dart';
import '../services/chat_unread_badge.dart';
import '../widgets/conversation_pick_list.dart';

/// Отправка текста из системного «Поделиться» в выбранный чат или группу.
class ShareTextToChatScreen extends StatefulWidget {
  const ShareTextToChatScreen({super.key, required this.sharedText});

  final String sharedText;

  @override
  State<ShareTextToChatScreen> createState() => _ShareTextToChatScreenState();
}

class _ShareTextToChatScreenState extends State<ShareTextToChatScreen> {
  bool _sending = false;

  Future<void> _sendTo(ConversationListItem item) async {
    if (_sending) {
      return;
    }
    final String t = widget.sharedText.trim();
    if (t.isEmpty) {
      return;
    }
    setState(() => _sending = true);
    try {
      await ChatService.sendMessage(item.id, t);
      unawaited(ChatUnreadBadge.refresh());
      final NavigatorState? nav = rootNavigatorKey.currentState;
      if (nav != null && nav.canPop()) {
        nav.pop();
      }
      final String okTitle = item.title;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final BuildContext? rootCtx = rootNavigatorKey.currentContext;
        if (rootCtx != null) {
          ScaffoldMessenger.of(rootCtx).showSnackBar(
            SnackBar(content: Text('Отправлено в «$okTitle»')),
          );
        }
      });
    } on Object catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final BuildContext? rootCtx = rootNavigatorKey.currentContext;
        if (rootCtx != null) {
          ScaffoldMessenger.of(rootCtx).showSnackBar(
            SnackBar(content: Text('Не удалось отправить: $e')),
          );
        }
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String preview = widget.sharedText.trim();
    final String short = preview.length > 280
        ? '${preview.substring(0, 277)}…'
        : preview;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Отправить в чат'),
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Material(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Сообщение',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      short,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Выберите чат или группу',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ),
          if (_sending)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ConversationPickList(
              excludeConversationId: null,
              emptyMessage:
                  'Нет чатов. Создайте диалог или группу в разделе «Чаты».',
              onPick: _sendTo,
            ),
          ),
        ],
      ),
    );
  }
}
