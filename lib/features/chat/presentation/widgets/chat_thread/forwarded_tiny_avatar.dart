import 'package:flutter/material.dart';

import 'package:city_app/app_constants.dart';
import 'package:city_app/features/chat/presentation/chat_user_profile_cache.dart';
import 'package:city_app/widgets/city_network_image.dart';

/// Аватар в шапке «Переслано от …» — профиль из [ChatUserProfileCache], без [FutureBuilder] в списке.
class ChatForwardedTinyAvatar extends StatelessWidget {
  const ChatForwardedTinyAvatar({
    super.key,
    required this.userId,
    required this.outgoing,
  });

  final String userId;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: ChatUserProfileCache.I.listenable(userId),
      builder: (BuildContext context, Map<String, dynamic>? row, _) {
        final String? url = (row?['avatar_url'] as String?)?.trim();
        final String fn = (row?['first_name'] as String?)?.trim() ?? '';
        final String un = (row?['username'] as String?)?.trim() ?? '';
        final String letter =
            (fn.isNotEmpty
                    ? fn[0]
                    : (un.isNotEmpty ? un.replaceAll('@', '')[0] : '?'))
                .toUpperCase();
        final String nameSeed = <String>[
          fn,
          un.replaceAll('@', ''),
        ].where((String e) => e.isNotEmpty).join(' ');
        return CircleAvatar(
          radius: 11,
          backgroundColor: outgoing
              ? Colors.white.withValues(alpha: 0.25)
              : kPrimaryBlue.withValues(alpha: 0.2),
          child: url != null && url.isNotEmpty
              ? CityNetworkImage.avatar(
                  context: context,
                  imageUrl: url,
                  diameter: 22,
                  placeholderName: nameSeed.isNotEmpty ? nameSeed : letter,
                )
              : Text(
                  letter,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: outgoing ? Colors.white : kPrimaryBlue,
                  ),
                ),
        );
      },
    );
  }
}
