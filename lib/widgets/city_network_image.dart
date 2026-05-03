import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'adaptive_image.dart';
import 'media_shimmer_box.dart';

/// Доля ширины экрана по умолчанию (~65%).
const double kCityNetworkImageWidthFraction = 0.65;

/// Если нет [aspectRatio] / intrinsics, для [BoxFit.cover] используем 16:9.
const double kCityNetworkImageDefaultAspectRatio = 16 / 9;

/// Верхняя граница логического размера: ниже — простой цветной плейсхолдер вместо Shimmer.
const double _kCompactPlaceholderMaxSide = 56;

/// Инициалы для аватара (до 2 символов; кириллица и латиница через runes).
String cityUserAvatarInitials(String? raw) {
  final String t = raw?.trim() ?? '';
  if (t.isEmpty) {
    return '?';
  }
  final List<String> parts = t
      .split(RegExp(r'\s+'))
      .where((String e) => e.isNotEmpty)
      .toList();
  String one(String s) {
    if (s.isEmpty) {
      return '';
    }
    final int r = s.runes.first;
    return String.fromCharCode(r);
  }

  if (parts.length >= 2) {
    return (one(parts[0]) + one(parts[1])).toUpperCase();
  }
  final String single = parts.isNotEmpty ? parts[0] : t;
  if (single.runes.length >= 2) {
    final Iterator<int> it = single.runes.iterator;
    it.moveNext();
    final int a = it.current;
    it.moveNext();
    final int b = it.current;
    return (String.fromCharCode(a) + String.fromCharCode(b)).toUpperCase();
  }
  return one(single).toUpperCase();
}

/// Стабильный пастельный фон для плейсхолдера аватара по строке-семени.
Color cityUserAvatarSeedColor(String? seed) {
  final int h = ((seed ?? '').hashCode & 0x7fffffff) % 360;
  return HSVColor.fromAHSV(1, h.toDouble(), 0.32, 0.86).toColor();
}

Color _onAvatarPlaceholderColor(Color bg) {
  return bg.computeLuminance() > 0.55
      ? const Color(0xFF1A1C1E)
      : Colors.white.withValues(alpha: 0.95);
}

/// Универсальная сеть-картинка: ограничения, [AspectRatio], скругление, loading/error.
///
/// Рендер через [AdaptiveImage] (единая система кэша, fade, политики изображений).
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
  }) : _mode = _CityNetworkImageMode.standard,
       _squareSize = null,
       _squareBorderRadius = null,
       _avatarInitials = null,
       _avatarColorSeed = null;

  const CityNetworkImage._square({
    super.key,
    required this.imageUrl,
    required double size,
    required double borderRadius,
    this.placeholderColor = const Color(0xFFE8EAED),
    this.errorIcon = Icons.broken_image_outlined,
    String? avatarInitials,
    String? avatarColorSeed,
  }) : maxWidth = size,
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
       _squareBorderRadius = borderRadius,
       _avatarInitials = avatarInitials,
       _avatarColorSeed = avatarColorSeed;

  const CityNetworkImage._viewer({
    super.key,
    required this.imageUrl,
    this.placeholderColor = const Color(0x33000000),
    this.errorIcon = Icons.broken_image_outlined,
  }) : maxWidth = null,
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
       _squareBorderRadius = null,
       _avatarInitials = null,
       _avatarColorSeed = null;

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
  }) : maxWidth = null,
       maxHeight = null,
       widthFraction = 1,
       aspectRatio = null,
       intrinsicWidth = null,
       intrinsicHeight = null,
       _mode = _CityNetworkImageMode.fillParent,
       _squareSize = null,
       _squareBorderRadius = null,
       _avatarInitials = null,
       _avatarColorSeed = null;

  factory CityNetworkImage.square({
    Key? key,
    required String? imageUrl,
    required double size,
    double borderRadius = 0,
    Color placeholderColor = const Color(0xFFE8EAED),
    IconData errorIcon = Icons.broken_image_outlined,
    String? avatarInitials,
    String? avatarColorSeed,
  }) {
    return CityNetworkImage._square(
      key: key,
      imageUrl: imageUrl,
      size: size,
      borderRadius: borderRadius,
      placeholderColor: placeholderColor,
      errorIcon: errorIcon,
      avatarInitials: avatarInitials,
      avatarColorSeed: avatarColorSeed,
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
  final String? _avatarInitials;
  final String? _avatarColorSeed;

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

  bool get _useAvatarStylePlaceholder =>
      _avatarInitials != null && _avatarInitials.isNotEmpty;

  Widget _avatarSolidTile(BuildContext context, double w, double h) {
    final String initials = _avatarInitials!;
    final Color bg = cityUserAvatarSeedColor(_avatarColorSeed ?? initials);
    final double fs = (math.min(w, h) * 0.38).clamp(10.0, 44.0);
    return ColoredBox(
      color: bg,
      child: Center(
        child: Text(
          initials,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontSize: fs,
            fontWeight: FontWeight.w600,
            height: 1,
            color: _onAvatarPlaceholderColor(bg),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? u = imageUrl?.trim();
    if (u == null || u.isEmpty) {
      final double? squareS = _squareSize;
      if (_mode == _CityNetworkImageMode.square &&
          squareS != null &&
          _useAvatarStylePlaceholder) {
        final double s = squareS;
        final double r = _squareBorderRadius ?? 0;
        return ClipRRect(
          borderRadius: BorderRadius.circular(r),
          child: SizedBox(
            width: s,
            height: s,
            child: _avatarSolidTile(context, s, s),
          ),
        );
      }
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
          child: _buildImage(context, u, layoutW: s, layoutH: s, clip: false),
        ),
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double sw = MediaQuery.sizeOf(context).width;
        final double capW = maxWidth ?? double.infinity;
        final double capH = maxHeight ?? 480;
        final double parentW = c.hasBoundedWidth ? c.maxWidth : sw;
        final double w = math.min(parentW * widthFraction, math.min(capW, sw));
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

  /// Круглый аватар: сеть через [AdaptiveImage], fade-in, memCache, без Shimmer —
  /// при загрузке/ошибке — цветной плейсхолдер с инициалами, если задан [placeholderName].
  static Widget avatar({
    required BuildContext context,
    required String? imageUrl,
    required double diameter,
    String? placeholderName,
  }) {
    final String? seed = placeholderName?.trim();
    final String? initials = seed != null && seed.isNotEmpty
        ? cityUserAvatarInitials(seed)
        : null;
    return ClipOval(
      child: CityNetworkImage.square(
        imageUrl: imageUrl,
        size: diameter,
        borderRadius: 0,
        avatarInitials: initials,
        avatarColorSeed: seed ?? initials,
      ),
    );
  }

  bool _compactPlaceholder(double layoutW, double layoutH) {
    if (_useAvatarStylePlaceholder) {
      return false;
    }
    if (!layoutW.isFinite || !layoutH.isFinite) {
      return false;
    }
    return layoutW <= _kCompactPlaceholderMaxSide &&
        layoutH <= _kCompactPlaceholderMaxSide;
  }

  Widget _buildImage(
    BuildContext context,
    String url, {
    required double layoutW,
    required double layoutH,
    bool clip = true,
  }) {
    final bool compact = _compactPlaceholder(layoutW, layoutH);
    final Widget img = SizedBox(
      width: layoutW.isFinite ? layoutW : null,
      height: layoutH.isFinite ? layoutH : null,
      child: AdaptiveImage(
        imageUrl: url,
        maxWidthPercent: 1,
        maxHeightPercent: 1,
        boxFit: boxFit,
        borderRadius: 0,
        imageAlignment: alignment,
        filterQuality: FilterQuality.low,
        fadeInDuration: const Duration(milliseconds: 320),
        fadeOutDuration: const Duration(milliseconds: 80),
        // Совпадает с прежним imageCacheExtentPx: (logical * dpr).round(), верх 2048.
        memCacheMaxDimension: 2048,
        networkPlaceholderBuilder: (BuildContext context, double w, double h) {
          if (_useAvatarStylePlaceholder) {
            return _avatarSolidTile(context, w, h);
          }
          if (compact) {
            return ColoredBox(color: placeholderColor);
          }
          return MediaShimmerBox(
            width: w,
            height: h,
            borderRadius: borderRadius.topLeft.x,
          );
        },
        networkErrorBuilder:
            (BuildContext context, double w, double h, Object? _) {
              if (_useAvatarStylePlaceholder) {
                return _avatarSolidTile(context, w, h);
              }
              return _errorTile(context, w, h);
            },
      ),
    );
    if (clip && borderRadius != BorderRadius.zero) {
      return ClipRRect(borderRadius: borderRadius, child: img);
    }
    return img;
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
