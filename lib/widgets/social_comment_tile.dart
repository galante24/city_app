import 'package:flutter/material.dart';

import '../app_card_styles.dart';
import '../services/city_data_service.dart';
import '../utils/mention_utils.dart';
import '../utils/social_time_format.dart';
import 'social_header.dart';

/// Облачный комментарий: [SocialHeader] + отделённый текст; тап по тексту — упоминание.
class SocialCommentTile extends StatelessWidget {
  const SocialCommentTile({
    super.key,
    required this.userId,
    required this.bodyText,
    this.author,
    this.createdAtIso,
    required this.onMentionInsert,
  });

  final String userId;
  final String bodyText;
  final Map<String, dynamic>? author;
  final String? createdAtIso;
  final void Function(String mentionSnippet) onMentionInsert;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final DateTime? at = parseIsoUtc(createdAtIso);
    return Container(
      decoration: cloudCardDecoration(context, radius: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SocialHeader(
              userId: userId,
              author: author,
              createdAt: at,
              dense: true,
            ),
            if (bodyText.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () async {
                    final Map<String, dynamic>? p =
                        await CityDataService.fetchProfileRow(userId);
                    onMentionInsert(mentionInsertionFromProfile(p));
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 2),
                    child: Text(
                      bodyText,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
