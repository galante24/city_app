import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:city_app/app_constants.dart';
import 'package:city_app/config/supabase_ready.dart';
import 'package:city_app/screens/feed_post_detail_screen.dart';
import 'package:city_app/services/chat_service.dart' show ChatFeedShareParsed;
import 'package:city_app/services/feed_service.dart';
import 'package:city_app/widgets/city_network_image.dart';

/// Превью поста ленты в пузырьке чата.
class ChatFeedShareCard extends StatelessWidget {
  const ChatFeedShareCard({
    super.key,
    required this.share,
    required this.outgoing,
    required this.cs,
    required this.incomingUnread,
  });

  final ChatFeedShareParsed share;
  final bool outgoing;
  final ColorScheme cs;
  final bool incomingUnread;

  @override
  Widget build(BuildContext context) {
    final String? photo = share.thumbUrl?.trim();
    final Color cardBg = outgoing
        ? Colors.white.withValues(alpha: 0.97)
        : const Color(0xFFE8F4FF);
    final Color borderCol = kPrimaryBlue.withValues(
      alpha: outgoing ? 0.38 : 0.42,
    );
    final Color titleCol = outgoing ? kPrimaryBlue : const Color(0xFF1565C0);
    final double cardMaxW = MediaQuery.sizeOf(context).width * 0.68;
    const double thumb = 76;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: 200,
        maxWidth: cardMaxW.clamp(200, 400),
      ),
      child: Material(
        color: cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: borderCol),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            if (!supabaseAppReady) {
              return;
            }
            final FeedService? feed = FeedService.tryOf(
              Supabase.instance.client,
            );
            if (feed == null) {
              return;
            }
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    FeedPostDetailScreen(postId: share.postId, feed: feed),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                photo != null && photo.isNotEmpty
                    ? CityNetworkImage.square(
                        imageUrl: photo,
                        size: thumb,
                        borderRadius: 10,
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: thumb,
                          height: thumb,
                          child: ColoredBox(
                            color: kPrimaryBlue.withValues(alpha: 0.12),
                            child: Icon(
                              Icons.article_outlined,
                              color: titleCol,
                              size: 36,
                            ),
                          ),
                        ),
                      ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Лента города',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                      Text(
                        share.headline,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: incomingUnread
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: titleCol,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Открыть',
                        style: TextStyle(
                          fontSize: 12,
                          color: titleCol.withValues(alpha: 0.85),
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
