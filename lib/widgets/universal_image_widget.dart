import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../utils/image_cache_extent.dart';
import 'universal_image_local_stub.dart'
    if (dart.library.io) 'universal_image_local_io.dart'
    as universal_local;

/// Универсальное превью для карточек (вакансии, заведения, учреждения и др.).
///
/// **Источник:** если заданы [file]/[filePath], они важнее [imageUrl]. На **web** локальный
/// `dart:io` [File] недоступен — используйте URL (в т.ч. blob) или путь, если платформа
/// поддерживает [FileImage].
///
/// **Списки:** в [ListView.builder] виджет строится только для видимых строк; кэш
/// [CachedNetworkImage] и уменьшенный декод ([memCacheWidth]/[memCacheHeight]) снижают
/// пиковую память и нагрузку на raster при скролле.
///
/// **Примеры**
///
/// Вакансия (16:9, ширина строки):
/// `UniversalImageWidget(imageUrl: url, width: w, aspectRatio: 16/9, borderRadius: 16)`
///
/// Заведение (квадрат 80):
/// `UniversalImageWidget(imageUrl: url, width: 80, height: 80, borderRadius: 16)`
///
/// Учебное учреждение (4:3, [maxHeight]):
/// `UniversalImageWidget(imageUrl: url, aspectRatio: 4/3, maxHeight: 140)`
///
/// При тяжёлых карточках дополнительно оберните их в [RepaintBoundary].
class UniversalImageWidget extends StatelessWidget {
  const UniversalImageWidget({
    super.key,
    this.imageUrl,
    this.file,
    this.filePath,
    this.width,
    this.height,
    this.maxHeight,
    this.aspectRatio,
    this.borderRadius = 0,
    this.fit = BoxFit.cover,
    this.fadeDuration = const Duration(milliseconds: 320),
    this.backgroundColor = const Color(0xFFE8EAED),
    this.placeholderIcon = Icons.image_outlined,
    this.placeholderIconColor = const Color(0xFF9AA0A6),
    this.errorIcon = Icons.broken_image_outlined,
    this.memCacheMaxPx = 2048,
  });

  /// URL сетевого изображения.
  final String? imageUrl;

  /// Локальный файл: на **IO** — [dart:io] `File`; на **web** игнорируется (используйте [imageUrl] или blob-URL).
  final Object? file;

  /// Путь к файлу на устройстве (удобно, если нет типа `File` в scope).
  final String? filePath;

  /// Фиксированная ширина; если `null` — берётся из родителя ([LayoutBuilder] / constraints).
  final double? width;

  /// Фиксированная высота; если заданы и [width], и [height], [aspectRatio] и расчёт по высоте не используются.
  final double? height;

  /// Максимальная высота контейнера (после расчёта по [aspectRatio] высота режется сверху).
  final double? maxHeight;

  /// Соотношение сторон контейнера **ширина / высота** (как у [AspectRatio]).
  /// Если `null` и не задана пара [width]+[height], используется [kUniversalImageDefaultAspectRatio].
  final double? aspectRatio;

  final double borderRadius;
  final BoxFit fit;

  /// Плавное появление для сети ([CachedNetworkImage]) и локального [Image.frameBuilder].
  final Duration fadeDuration;

  /// Фон под [BoxFit.contain] и плейсхолдер.
  final Color backgroundColor;
  final IconData placeholderIcon;
  final Color placeholderIconColor;
  final IconData errorIcon;

  /// Верхняя граница декодирования в пикселях (ширина/высота для mem/cache).
  final int memCacheMaxPx;

  static const double kUniversalImageDefaultAspectRatio = 16 / 9;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final MediaQueryData mq = MediaQuery.of(context);
        final double parentW =
            constraints.hasBoundedWidth && constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : mq.size.width;
        final double resolvedW =
            width ??
            (parentW.isFinite && parentW > 0 ? parentW : mq.size.width);
        final double ar = aspectRatio ?? kUniversalImageDefaultAspectRatio;

        double boxW;
        double boxH;
        if (width != null && height != null) {
          boxW = width!;
          boxH = height!;
        } else if (height != null) {
          boxH = height!;
          boxW = width ?? (boxH * ar);
        } else {
          boxW = resolvedW;
          boxH = boxW / ar;
          final double? mh = maxHeight;
          if (mh != null && boxH > mh) {
            boxH = mh;
            boxW = boxH * ar;
          }
        }

        final String? url = imageUrl?.trim();
        final ImageProvider? localProvider = universal_local
            .universalLocalImageProvider(file: file, filePath: filePath);
        final bool hasNet = url != null && url.isNotEmpty;
        final bool hasLocal = localProvider != null;

        if (!hasNet && !hasLocal) {
          return _clip(context, boxW, boxH, _fallback(compact: boxH < 100));
        }

        final int memW = imageCacheExtentPx(
          context,
          boxW,
        ).clamp(1, memCacheMaxPx);
        final int memH = imageCacheExtentPx(
          context,
          boxH,
        ).clamp(1, memCacheMaxPx);

        final Widget imageChild = hasLocal
            ? _LocalFadeImage(
                provider: localProvider,
                fit: fit,
                fadeDuration: fadeDuration,
                memW: memW,
                memH: memH,
                width: boxW,
                height: boxH,
                placeholder: _placeholder(compact: boxH < 100),
                errorWidget: _error(compact: boxH < 100),
              )
            : CachedNetworkImage(
                imageUrl: url!,
                width: boxW,
                height: boxH,
                fit: fit,
                filterQuality: FilterQuality.low,
                fadeInDuration: fadeDuration,
                fadeOutDuration: const Duration(milliseconds: 80),
                memCacheWidth: memW,
                memCacheHeight: memH,
                placeholder: (BuildContext context, String _) =>
                    _placeholder(compact: boxH < 100),
                errorWidget: (BuildContext context, String _, Object _) =>
                    _error(compact: boxH < 100),
              );

        final Widget layered = fit == BoxFit.contain
            ? ColoredBox(color: backgroundColor, child: imageChild)
            : imageChild;

        return _clip(context, boxW, boxH, layered);
      },
    );
  }

  Widget _clip(BuildContext context, double w, double h, Widget child) {
    if (borderRadius <= 0) {
      return SizedBox(width: w, height: h, child: child);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(width: w, height: h, child: child),
    );
  }

  Widget _fallback({required bool compact}) {
    return ColoredBox(
      color: backgroundColor,
      child: Center(
        child: Icon(
          placeholderIcon,
          size: compact ? 28 : 40,
          color: placeholderIconColor,
        ),
      ),
    );
  }

  Widget _placeholder({required bool compact}) {
    return ColoredBox(
      color: backgroundColor,
      child: Center(
        child: SizedBox(
          width: compact ? 22 : 28,
          height: compact ? 22 : 28,
          child: CircularProgressIndicator(
            strokeWidth: compact ? 2 : 2.5,
            color: placeholderIconColor,
          ),
        ),
      ),
    );
  }

  Widget _error({required bool compact}) {
    return ColoredBox(
      color: backgroundColor,
      child: Center(
        child: Icon(
          errorIcon,
          size: compact ? 28 : 40,
          color: placeholderIconColor,
        ),
      ),
    );
  }
}

class _LocalFadeImage extends StatelessWidget {
  const _LocalFadeImage({
    required this.provider,
    required this.fit,
    required this.fadeDuration,
    required this.memW,
    required this.memH,
    required this.width,
    required this.height,
    required this.placeholder,
    required this.errorWidget,
  });

  final ImageProvider provider;
  final BoxFit fit;
  final Duration fadeDuration;
  final int memW;
  final int memH;
  final double width;
  final double height;
  final Widget placeholder;
  final Widget errorWidget;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: ResizeImage(
        provider,
        width: memW,
        height: memH,
        allowUpscaling: false,
      ),
      fit: fit,
      filterQuality: FilterQuality.low,
      width: width,
      height: height,
      gaplessPlayback: true,
      errorBuilder: (BuildContext context, Object _, StackTrace? stackTrace) =>
          errorWidget,
      frameBuilder:
          (
            BuildContext context,
            Widget child,
            int? frame,
            bool wasSynchronouslyLoaded,
          ) {
            if (wasSynchronouslyLoaded) {
              return child;
            }
            if (frame != null) {
              return TweenAnimationBuilder<double>(
                duration: fadeDuration,
                curve: Curves.easeOut,
                tween: Tween<double>(begin: 0, end: 1),
                builder: (BuildContext context, double opacity, Widget? _) {
                  return Opacity(opacity: opacity, child: child);
                },
              );
            }
            return placeholder;
          },
    );
  }
}
