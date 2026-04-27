import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/image_cache_extent.dart';

/// Доля ширины экрана по умолчанию (~65%).
const double kCityNetworkImageWidthFraction = 0.65;

/// Если нет [aspectRatio] / intrinsics, для [BoxFit.cover] используем 16:9.
const double kCityNetworkImageDefaultAspectRatio = 16 / 9;

/// Универсальная сеть-картинка: ограничения, [AspectRatio], скругление, loading/error.
///
/// **Размеры в БД (рекомендация):** рядом с `url` хранить `image_width` / `image_height`
/// (int, пиксели оригинала) — из Edge Function при загрузке или после декодирования
/// на клиенте. Передать в [intrinsicWidth] / [intrinsicHeight] для стабильного
/// [AspectRatio] и предсказуемой вёрстки.
class CityNetworkImage extends StatelessWidget {
  const CityNetworkImage({
    super.key,
    required this.imageUrl,
    this.maxWidth,
    this.maxHeight = 520,
    this.widthFraction = kCityNetworkImageWidthFraction,
    this.boxFit = BoxFit.contain,
    this.borderRadius = BorderRadius.zero,
    this.aspectRatio,
    this.intrinsicWidth,
    this.intrinsicHeight,
    this.alignment = Alignment.center,
    this.placeholderColor = const Color(0xFFE8EAED),
    this.errorIcon = Icons.broken_image_outlined,
  })  : _mode = _CityNetworkImageMode.standard,
        _squareSize = null,
        _squareBorderRadius = null;

  const CityNetworkImage._square({
    super.key,
    required this.imageUrl,
    required double size,
    required double borderRadius,
    this.placeholderColor = const Color(0xFFE8EAED),
    this.errorIcon = Icons.broken_image_outlined,
  })  : maxWidth = size,
        maxHeight = size,
        widthFraction = 1,
        boxFit = BoxFit.cover,
        borderRadius = BorderRadius.zero,
        aspectRatio = 1,
        intrinsicWidth = null,
        intrinsicHeight = null,
        alignment = Alignment.center,
        _mode = _CityNetworkImageMode.square,
        _squareSize = size,
        _squareBorderRadius = borderRadius;

  const CityNetworkImage._viewer({
    super.key,
    required this.imageUrl,
    this.placeholderColor = const Color(0x33000000),
    this.errorIcon = Icons.broken_image_outlined,
  })  : maxWidth = null,
        maxHeight = null,
        widthFraction = 1,
        boxFit = BoxFit.contain,
        borderRadius = BorderRadius.zero,
        aspectRatio = null,
        intrinsicWidth = null,
        intrinsicHeight = null,
        alignment = Alignment.center,
        _mode = _CityNetworkImageMode.viewer,
        _squareSize = null,
        _squareBorderRadius = null;

  /// Заполняет пространство родителя (уже задан [AspectRatio] / [SizedBox]).
  /// Внутреннего [AspectRatio] нет — только [ClipRRect] и сеть-изображение.
  const CityNetworkImage.fillParent({
    super.key,
    required this.imageUrl,
    this.boxFit = BoxFit.cover,
    this.borderRadius = BorderRadius.zero,
    this.alignment = Alignment.center,
    this.placeholderColor = const Color(0xFFE8EAED),
    this.errorIcon = Icons.broken_image_outlined,
  })  : maxWidth = null,
        maxHeight = null,
        widthFraction = 1,
        aspectRatio = null,
        intrinsicWidth = null,
        intrinsicHeight = null,
        _mode = _CityNetworkImageMode.fillParent,
        _squareSize = null,
        _squareBorderRadius = null;

  factory CityNetworkImage.square({
    Key? key,
    required String? imageUrl,
    required double size,
    double borderRadius = 0,
    Color placeholderColor = const Color(0xFFE8EAED),
    IconData errorIcon = Icons.broken_image_outlined,
  }) {
    return CityNetworkImage._square(
      key: key,
      imageUrl: imageUrl,
      size: size,
      borderRadius: borderRadius,
      placeholderColor: placeholderColor,
      errorIcon: errorIcon,
    );
  }

  factory CityNetworkImage.viewer({
    Key? key,
    required String imageUrl,
    Color placeholderColor = const Color(0x33000000),
    IconData errorIcon = Icons.broken_image_outlined,
  }) {
    return CityNetworkImage._viewer(
      key: key,
      imageUrl: imageUrl,
      placeholderColor: placeholderColor,
      errorIcon: errorIcon,
    );
  }

  final String? imageUrl;
  final double? maxWidth;
  final double? maxHeight;
  final double widthFraction;
  final BoxFit boxFit;
  final BorderRadius borderRadius;
  final double? aspectRatio;
  final int? intrinsicWidth;
  final int? intrinsicHeight;
  final Alignment alignment;
  final Color placeholderColor;
  final IconData errorIcon;
  final _CityNetworkImageMode _mode;
  final double? _squareSize;
  final double? _squareBorderRadius;

  double? get _resolvedAspect {
    if (intrinsicWidth != null &&
        intrinsicHeight != null &&
        intrinsicHeight! > 0) {
      return intrinsicWidth! / intrinsicHeight!;
    }
    if (aspectRatio != null) {
      return aspectRatio;
    }
    if (_mode == _CityNetworkImageMode.square) {
      return 1;
    }
    if (boxFit == BoxFit.cover && _mode == _CityNetworkImageMode.standard) {
      return kCityNetworkImageDefaultAspectRatio;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final String? u = imageUrl?.trim();
    if (u == null || u.isEmpty) {
      return _errorTile(context, 120, 120);
    }

    if (_mode == _CityNetworkImageMode.viewer) {
      final Size sz = MediaQuery.sizeOf(context);
      return Center(
        child: SizedBox(
          width: sz.width,
          height: sz.height,
          child: _buildImage(
            context,
            u,
            layoutW: sz.width,
            layoutH: sz.height,
            clip: false,
          ),
        ),
      );
    }

    if (_mode == _CityNetworkImageMode.fillParent) {
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final double w = c.hasBoundedWidth && c.maxWidth.isFinite
              ? c.maxWidth
              : MediaQuery.sizeOf(context).width;
          final double h = c.hasBoundedHeight && c.maxHeight.isFinite
              ? c.maxHeight
              : MediaQuery.sizeOf(context).height;
          return ClipRRect(
            borderRadius: borderRadius,
            child: _buildImage(
              context,
              u,
              layoutW: math.max(1, w),
              layoutH: math.max(1, h),
              clip: false,
            ),
          );
        },
      );
    }

    if (_mode == _CityNetworkImageMode.square) {
      final double s = _squareSize!;
      final double r = _squareBorderRadius ?? 0;
      return ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: SizedBox(
          width: s,
          height: s,
          child: _buildImage(
            context,
            u,
            layoutW: s,
            layoutH: s,
            clip: false,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double sw = MediaQuery.sizeOf(context).width;
        final double capW = maxWidth ?? double.infinity;
        final double capH = maxHeight ?? 480;
        final double parentW = c.hasBoundedWidth ? c.maxWidth : sw;
        final double w = math.min(
          parentW * widthFraction,
          math.min(capW, sw),
        );
        final double h = math.min(capH, sw * 0.9);
        final double? ar = _resolvedAspect;

        if (ar != null) {
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: w, maxHeight: h),
              child: AspectRatio(
                aspectRatio: ar,
                child: ClipRRect(
                  borderRadius: borderRadius,
                  child: _buildImage(
                    context,
                    u,
                    layoutW: w,
                    layoutH: w / ar,
                    clip: false,
                  ),
                ),
              ),
            ),
          );
        }

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: w, maxHeight: h),
            child: ClipRRect(
              borderRadius: borderRadius,
              child: _buildImage(
                context,
                u,
                layoutW: w,
                layoutH: h,
                clip: false,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Круглый аватар (вместо [Image.network] внутри [ClipOval]).
  static Widget avatar({
    required BuildContext context,
    required String? imageUrl,
    required double diameter,
  }) {
    return ClipOval(
      child: CityNetworkImage.square(
        imageUrl: imageUrl,
        size: diameter,
        borderRadius: 0,
      ),
    );
  }

  Widget _buildImage(
    BuildContext context,
    String url, {
    required double layoutW,
    required double layoutH,
    bool clip = true,
  }) {
    final int cw = imageCacheExtentPx(context, layoutW);
    final int ch = imageCacheExtentPx(context, layoutH);
    final Widget img = Image.network(
      url,
      fit: boxFit,
      alignment: alignment,
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
        return _loading(placeholderColor, layoutW, layoutH);
      },
      errorBuilder: (BuildContext context, Object e, StackTrace? st) {
        return _errorTile(context, layoutW, layoutH);
      },
    );
    if (clip && borderRadius != BorderRadius.zero) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: img,
      );
    }
    return img;
  }

  Widget _loading(Color color, double w, double h) {
    return ColoredBox(
      color: color,
      child: SizedBox(
        width: w,
        height: h,
        child: const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }

  Widget _errorTile(BuildContext context, double w, double h) {
    return ColoredBox(
      color: placeholderColor,
      child: Icon(
        errorIcon,
        size: math.min(40, w * 0.2 + 8),
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

enum _CityNetworkImageMode { standard, square, viewer, fillParent }
