import 'package:flutter/material.dart';

import '../media_progressive_image.dart';

/// Собирает URL вложений комментария: [feed_comments.image_urls] и опционально [media_urls].
List<String> commentMediaUrlsFromRow(Map<String, dynamic> row) {
  Iterable<String> fromKey(String key) sync* {
    final Object? raw = row[key];
    if (raw is List<dynamic>) {
      for (final Object? e in raw) {
        final String s = e?.toString().trim() ?? '';
        if (s.isNotEmpty) {
          yield s;
        }
      }
    }
  }

  final Set<String> seen = <String>{};
  final List<String> out = <String>[];
  for (final String s in <String>[
    ...fromKey('image_urls'),
    ...fromKey('media_urls'),
  ]) {
    if (seen.add(s)) {
      out.add(s);
    }
  }
  return out;
}

/// Блок превью вложений комментария: [FeedCommentAttachmentGrid] + [FeedFullscreenGallery] по тапу.
class CommentItem extends StatelessWidget {
  const CommentItem({
    super.key,
    required this.urls,
    this.thumb = 120,
    this.maxAttachmentHeight = 200,
  });

  final List<String> urls;
  final double thumb;

  /// Высота ячейки при нескольких вложениях.
  final double maxAttachmentHeight;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) {
      return const SizedBox.shrink();
    }
    return FeedCommentAttachmentGrid(
      urls: urls,
      thumb: thumb,
      maxTileHeight: maxAttachmentHeight,
    );
  }
}
