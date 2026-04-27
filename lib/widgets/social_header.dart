import 'package:flutter/material.dart';

import '../app_constants.dart';
import '../navigation/open_user_profile.dart';
import '../services/city_data_service.dart';
import '../utils/author_embed.dart';
import 'city_network_image.dart';
import '../utils/social_time_format.dart';

/// Единый блок «аватар + имя + время»; тап по аватару или имени → профиль.
class SocialHeader extends StatelessWidget {
  const SocialHeader({
    super.key,
    required this.userId,
    this.author,
    this.createdAt,
    this.dense = false,
  });

  final String userId;
  final Map<String, dynamic>? author;
  final DateTime? createdAt;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final double avatarR = dense ? 18.0 : 22.0;
    final String timeStr = formatSocialTimestamp(createdAt);

    void openProfile() {
      openUserProfile(
        context,
        userId,
        fallbackName: authorFullNameFromMap(author),
      );
    }

    Widget avatarFromMap(Map<String, dynamic>? m) {
      final String? url = authorAvatarUrlFromMap(m);
      final String letter = authorFullNameFromMap(m).isNotEmpty
          ? authorFullNameFromMap(m)[0].toUpperCase()
          : '?';
      if (url != null && url.isNotEmpty) {
        final double d = avatarR * 2;
        return CircleAvatar(
          radius: avatarR,
          backgroundColor: kPrimaryBlue.withValues(alpha: 0.14),
          child: CityNetworkImage.avatar(
            context: context,
            imageUrl: url,
            diameter: d,
          ),
        );
      }
      return CircleAvatar(
        radius: avatarR,
        backgroundColor: kPrimaryBlue.withValues(alpha: 0.14),
        child: Text(
          letter,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: kPrimaryBlue,
            fontSize: dense ? 13 : 15,
          ),
        ),
      );
    }

    if (author != null) {
      return InkWell(
        onTap: openProfile,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: dense ? 2 : 4, horizontal: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              avatarFromMap(author),
              SizedBox(width: dense ? 8 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            authorFullNameFromMap(author),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: dense ? 13 : 15,
                              color: cs.onSurface,
                              height: 1.2,
                            ),
                          ),
                        ),
                        if (timeStr.isNotEmpty) ...<Widget>[
                          const SizedBox(width: 8),
                          Text(
                            timeStr,
                            style: TextStyle(
                              fontSize: dense ? 11 : 12,
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: CityDataService.fetchProfileRow(userId),
      builder: (BuildContext c, AsyncSnapshot<Map<String, dynamic>?> snap) {
        final Map<String, dynamic>? m = snap.data;
        return InkWell(
          onTap: openProfile,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding:
                EdgeInsets.symmetric(vertical: dense ? 2 : 4, horizontal: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                avatarFromMap(m),
                SizedBox(width: dense ? 8 : 10),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          authorFullNameFromMap(m),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: dense ? 13 : 15,
                            color: cs.onSurface,
                            height: 1.2,
                          ),
                        ),
                      ),
                      if (timeStr.isNotEmpty) ...<Widget>[
                        const SizedBox(width: 8),
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: dense ? 11 : 12,
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
