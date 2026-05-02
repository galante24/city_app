import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'feed/feed_fullscreen_gallery.dart';

/// Логические px → пиксели растра для [memCacheWidth] / [memCacheHeight].
int progressiveImageMemDim(
  BuildContext context,
  double logicalPx, {
  int maxPx = 2048,
}) {
  final double dpr = MediaQuery.devicePixelRatioOf(context);
  return (logicalPx * dpr).round().clamp(1, maxPx);
}

/// Shimmer в форме прямоугольника (плейсхолдер под превью).
class MediaShimmerBox extends StatelessWidget {
  const MediaShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 0,
    this.baseColor,
    this.highlightColor,
  });

  final double width;
  final double height;
  final double borderRadius;
  final Color? baseColor;
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color b =
        baseColor ?? (dark ? const Color(0xFF2A2F36) : const Color(0xFFE4E8EC));
    final Color h =
        highlightColor ??
        (dark ? const Color(0xFF3D4450) : const Color(0xFFF2F5F8));
    final Widget box = Shimmer.fromColors(
      baseColor: b,
      highlightColor: h,
      period: const Duration(milliseconds: 1200),
      child: ColoredBox(
        color: Colors.white,
        child: SizedBox(width: width, height: height),
      ),
    );
    if (borderRadius <= 0) {
      return SizedBox(width: width, height: height, child: box);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(width: width, height: height, child: box),
    );
  }
}

/// [CachedNetworkImage] с Shimmer, FadeIn и ограничением декода по памяти.
class ProgressiveCachedImage extends StatelessWidget {
  const ProgressiveCachedImage({
    super.key,
    required this.imageUrl,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 0,
    this.fadeDuration = const Duration(milliseconds: 380),
    this.memCacheMaxPx = 2048,

    /// Верхний предел декодированной высоты в пикселях растра (экономия памяти).
    this.memCacheHeightMaxPx,
    this.filterQuality = FilterQuality.low,
  });

  final String imageUrl;
  final double width;
  final double height;
  final BoxFit fit;
  final double borderRadius;
  final Duration fadeDuration;
  final int memCacheMaxPx;
  final int? memCacheHeightMaxPx;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    final int mw = progressiveImageMemDim(context, width, maxPx: memCacheMaxPx);
    int mh = progressiveImageMemDim(context, height, maxPx: memCacheMaxPx);
    final int? cap = memCacheHeightMaxPx;
    if (cap != null && mh > cap) {
      mh = cap;
    }
    final Widget img = CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      filterQuality: filterQuality,
      fadeInDuration: fadeDuration,
      fadeOutDuration: const Duration(milliseconds: 100),
      memCacheWidth: mw,
      memCacheHeight: mh,
      placeholder: (BuildContext context, String _) {
        return MediaShimmerBox(
          width: width,
          height: height,
          borderRadius: borderRadius,
        );
      },
      errorWidget: (BuildContext context, String url, Object err) {
        return ColoredBox(
          color: Colors.black12,
          child: SizedBox(
            width: width,
            height: height,
            child: const Icon(Icons.broken_image_outlined, size: 32),
          ),
        );
      },
    );
    if (borderRadius <= 0) {
      return img;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: img,
    );
  }
}

/// Сетка вложений в комментарии (до 3 снимков): «таблетка» [BorderRadius.circular(26)], cover, тап → [FeedFullscreenGallery].
class FeedCommentAttachmentGrid extends StatelessWidget {
  const FeedCommentAttachmentGrid({
    super.key,
    required this.urls,
    this.thumb = 120,
    this.maxTileHeight = 200,
  });

  final List<String> urls;

  /// Верхняя граница ширины ячейки в сетке 2–3 фото.
  final double thumb;

  /// Высота превью при нескольких вложениях (одно фото — полная полоса до [_kStripMaxH]).
  final double maxTileHeight;

  static const double _kPillR = 26;
  static const double _kStripMaxH = 350;

  void _openGallery(BuildContext context, int index) {
    if (!context.mounted) {
      return;
    }
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => FeedFullscreenGallery(
          urls: urls,
          initialIndex: index < 0
              ? 0
              : (index >= urls.length ? urls.length - 1 : index),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) {
      return const SizedBox.shrink();
    }
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints bc) {
          final double maxW = bc.maxWidth.isFinite && bc.maxWidth > 0
              ? bc.maxWidth
              : thumb * 3;
          final int n = urls.length;

          if (n == 1) {
            final String u = urls[0];
            return Container(
              constraints: const BoxConstraints(
                minWidth: double.infinity,
                maxHeight: _kStripMaxH,
              ),
              width: maxW,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_kPillR),
                child: GestureDetector(
                  onTap: () => _openGallery(context, 0),
                  child: ProgressiveCachedImage(
                    imageUrl: u,
                    width: maxW,
                    height: _kStripMaxH,
                    fit: BoxFit.cover,
                    borderRadius: 0,
                    memCacheHeightMaxPx: 600,
                  ),
                ),
              ),
            );
          }

          final int cols = n >= 3 ? 3 : n;
          const double gap = 8;
          final double cellW = cols > 0
              ? ((maxW - gap * (cols - 1)) / cols).clamp(48.0, thumb)
              : thumb;
          final double tileH = maxTileHeight.clamp(88.0, _kStripMaxH);

          return Container(
            constraints: const BoxConstraints(
              minWidth: double.infinity,
              maxHeight: _kStripMaxH,
            ),
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: gap,
              runSpacing: gap,
              children: List<Widget>.generate(n, (int i) {
                final String u = urls[i];
                return ClipRRect(
                  borderRadius: BorderRadius.circular(_kPillR),
                  child: GestureDetector(
                    onTap: () => _openGallery(context, i),
                    child: ProgressiveCachedImage(
                      imageUrl: u,
                      width: cellW,
                      height: tileH,
                      fit: BoxFit.cover,
                      borderRadius: 0,
                      memCacheHeightMaxPx: 600,
                    ),
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }
}
