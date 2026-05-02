import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

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
    this.filterQuality = FilterQuality.low,
  });

  final String imageUrl;
  final double width;
  final double height;
  final BoxFit fit;
  final double borderRadius;
  final Duration fadeDuration;
  final int memCacheMaxPx;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    final int mw = progressiveImageMemDim(context, width, maxPx: memCacheMaxPx);
    final int mh = progressiveImageMemDim(
      context,
      height,
      maxPx: memCacheMaxPx,
    );
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

/// Сетка вложений в комментарии (до 3 снимков).
class FeedCommentAttachmentGrid extends StatelessWidget {
  const FeedCommentAttachmentGrid({
    super.key,
    required this.urls,
    required this.thumb,
    required this.onPhotoTap,
  });

  final List<String> urls;
  final double thumb;
  final void Function(int index) onPhotoTap;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) {
      return const SizedBox.shrink();
    }
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints bc) {
          final double maxW = bc.maxWidth.isFinite ? bc.maxWidth : thumb * 3;
          final int n = urls.length;
          final int cols = n >= 3 ? 3 : n;
          const double gap = 5;
          final double cellW = cols > 0
              ? ((maxW - gap * (cols - 1)) / cols).clamp(48.0, thumb)
              : thumb;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: List<Widget>.generate(n, (int i) {
              final String u = urls[i];
              return Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: () => onPhotoTap(i),
                  borderRadius: BorderRadius.circular(8),
                  child: ProgressiveCachedImage(
                    imageUrl: u,
                    width: cellW,
                    height: cellW,
                    fit: BoxFit.cover,
                    borderRadius: 8,
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
