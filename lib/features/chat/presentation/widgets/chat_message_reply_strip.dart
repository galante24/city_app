import 'package:flutter/material.dart';

import '../../../../app_constants.dart' show kPrimaryBlue;
import '../../domain/chat_reply_strip_data.dart';

/// Внутри пузырька: превью «ответ на сообщение» (1–2 строки + полоска).
class ChatMessageReplyStrip extends StatelessWidget {
  const ChatMessageReplyStrip({
    super.key,
    required this.data,
    required this.outgoing,
    required this.onPressed,
  });

  final ChatReplyStripData data;
  final bool outgoing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color bar = outgoing
        ? Colors.white.withValues(alpha: 0.55)
        : kPrimaryBlue.withValues(alpha: 0.5);
    final Color titleC =
        outgoing ? Colors.white.withValues(alpha: 0.95) : kPrimaryBlue;
    final Color textC = outgoing
        ? Colors.white.withValues(alpha: 0.8)
        : cs.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: bar,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        data.authorLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: titleC,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        data.snippet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.2,
                          color: data.isOriginalDeleted
                              ? (outgoing
                                  ? Colors.white54
                                  : cs.onSurfaceVariant.withValues(alpha: 0.7))
                              : textC,
                          fontStyle: data.isOriginalDeleted
                              ? FontStyle.italic
                              : null,
                        ),
                      ),
                    ],
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
