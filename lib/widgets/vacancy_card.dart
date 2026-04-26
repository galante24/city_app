import 'package:flutter/material.dart';

import '../utils/image_cache_extent.dart';

/// Превью обложки; карточка строки списка — виджет `CloudInkCard` в `app_card_styles.dart`.

/// Ширина : высота превью вакансии (единый стиль списка и детального экрана).
const double kVacancyCoverAspectRatio = 16 / 9;

double _coverHeightForWidth(double w) => w / kVacancyCoverAspectRatio;

/// Превью фото вакансии: фиксированное соотношение сторон, [BoxFit.cover], скругление.
///
/// [width] — для строки списка; если `null`, ширина берётся из родителя ([LayoutBuilder]).
class VacancyCoverImage extends StatelessWidget {
  const VacancyCoverImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.borderRadius = 16,
    this.fit = BoxFit.cover,
    this.letterboxColor,
  });

  final String? imageUrl;
  final double? width;
  final double borderRadius;
  /// В карточках списка — [BoxFit.cover]; на экране деталей — [BoxFit.contain].
  final BoxFit fit;
  /// Фон при [BoxFit.contain] (поля по краям без искажения).
  final Color? letterboxColor;

  static Widget _grayPlaceholder({required bool compact}) {
    return ColoredBox(
      color: const Color(0xFFE8EAED),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: compact ? 28 : 40,
          color: const Color(0xFF9AA0A6),
        ),
      ),
    );
  }

  Widget _imageLayer(BuildContext context, double layoutW) {
    final String? url = imageUrl?.trim();
    final bool hasUrl = url != null && url.isNotEmpty;
    final int cw = imageCacheExtentPx(context, layoutW);
    final int ch = imageCacheExtentPx(context, _coverHeightForWidth(layoutW));
    final bool compact = width != null;

    if (!hasUrl) {
      return _grayPlaceholder(compact: compact);
    }

    final Widget net = Image.network(
      url,
      fit: fit,
      alignment: Alignment.center,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: cw,
      cacheHeight: ch,
      loadingBuilder: (
        BuildContext context,
        Widget child,
        ImageChunkEvent? progress,
      ) {
        if (progress == null) {
          return child;
        }
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _grayPlaceholder(compact: compact),
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
        );
      },
      errorBuilder:
          (BuildContext context, Object error, StackTrace? stackTrace) =>
              _grayPlaceholder(compact: compact),
    );
    if (fit == BoxFit.contain) {
      return ColoredBox(
        color: letterboxColor ?? const Color(0xFFE8EAED),
        child: net,
      );
    }
    return net;
  }

  Widget _framed(BuildContext context, double layoutW) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: AspectRatio(
        aspectRatio: kVacancyCoverAspectRatio,
        child: _imageLayer(context, layoutW),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (width != null) {
      return SizedBox(width: width, child: _framed(context, width!));
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double layoutW = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return _framed(context, layoutW);
      },
    );
  }
}
