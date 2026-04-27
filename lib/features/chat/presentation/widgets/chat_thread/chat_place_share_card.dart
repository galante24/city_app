import 'package:flutter/material.dart';

import 'package:city_app/app_constants.dart';
import 'package:city_app/features/chat/presentation/chat_place_share_resolution_cache.dart';
import 'package:city_app/services/chat_service.dart' show ChatPlaceShareParsed;
import 'package:city_app/widgets/city_network_image.dart';

/// Превью заведения в пузырьке; один [Future] на share через [ChatPlaceShareResolutionCache].
class ChatPlaceShareCard extends StatelessWidget {
  const ChatPlaceShareCard({
    super.key,
    required this.share,
    required this.outgoing,
    required this.cs,
    required this.incomingUnread,
  });

  final ChatPlaceShareParsed share;
  final bool outgoing;
  final ColorScheme cs;
  final bool incomingUnread;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ChatPlaceShareResolved?>(
      future: ChatPlaceShareResolutionCache.I.futureFor(share),
      builder: (BuildContext context, AsyncSnapshot<ChatPlaceShareResolved?> snap) {
        final ChatPlaceShareResolved? res = snap.data;
        final String title = (res?.title ?? share.headline).trim();
        final String? photo = res?.photoUrl ?? share.thumbUrl;
        final String openId = res?.placeId ?? share.directPlaceId ?? '';
        final bool waitingLegacy = share.legacyPostId != null &&
            share.legacyPostId!.isNotEmpty &&
            snap.connectionState == ConnectionState.waiting;
        final bool canOpen = openId.isNotEmpty;

        final Color cardBg = outgoing
            ? Colors.white.withValues(alpha: 0.97)
            : const Color(0xFFE2F2E3);
        final Color borderCol =
            kPrimaryBlue.withValues(alpha: outgoing ? 0.38 : 0.42);
        final Color titleCol =
            outgoing ? kPrimaryBlue : const Color(0xFF2E7D32);
        final Color actionCol =
            outgoing ? kPrimaryBlue.withValues(alpha: 0.9) : kPrimaryBlue;
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
                              child: const Icon(
                                Icons.store_rounded,
                                color: kPrimaryBlue,
                                size: 32,
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
                          title.isEmpty ? 'Заведение' : title,
                          maxLines: 2,
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
                        const SizedBox(height: 6),
                        if (waitingLegacy && !canOpen)
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: titleCol,
                            ),
                          )
                        else
                          Text(
                            canOpen ? 'Перейти' : 'Недоступно',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: canOpen ? actionCol : cs.onSurfaceVariant,
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
  }
}
