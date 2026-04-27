import 'package:flutter/material.dart';

import '../../../../app_constants.dart' show kPrimaryBlue;
import '../../domain/chat_reply_draft.dart';

/// Панель «Ответ на…» над полем ввода.
class ChatReplyDraftBanner extends StatelessWidget {
  const ChatReplyDraftBanner({
    super.key,
    required this.draft,
    required this.onCancel,
  });

  final ChatReplyDraft draft;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 0, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.reply_rounded, color: kPrimaryBlue, size: 22),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Ответ · ${draft.authorLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    draft.snippet,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Отменить ответ',
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}
