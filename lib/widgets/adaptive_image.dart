import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Кастомный плейсхолдер сети (ширина/высота — логические px ячейки).
typedef AdaptiveNetworkPlaceholderBuilder =
    Widget Function(BuildContext context, double width, double height);

/// Кастомный виджет ошибки сети.
typedef AdaptiveNetworkErrorBuilder =
    Widget Function(
      BuildContext context,
      double width,
      double height,
      Object? error,
    );

/// Пресеты [AdaptiveImage.fromSource] для типовых экранов приложения.
enum AdaptiveImageScene {
  /// Универсальный сценарий: ширина до 90 %, без фиксированного кадра.
  generic,

  /// Сообщения в чате: уже по ширине, обрезка [BoxFit.cover].
  chat,

  /// Карточка поста: 16:9, [BoxFit.contain].
  feedPost,

  /// Вакансии и похожие карточки: до 70 %, [BoxFit.contain].
  vacancy,
}

({double maxW, double? ar, BoxFit fit}) _presetForScene(
  AdaptiveImageScene scene,
) {
  switch (scene) {
    case AdaptiveImageScene.chat:
      return (maxW: 0.6, ar: null, fit: BoxFit.cover);
    case AdaptiveImageScene.feedPost:
      return (maxW: 0.9, ar: 16 / 9, fit: BoxFit.contain);
    case AdaptiveImageScene.vacancy:
      return (maxW: 0.7, ar: null, fit: BoxFit.contain);
    case AdaptiveImageScene.generic:
      return (maxW: 0.9, ar: null, fit: BoxFit.contain);
  }
}

/// Универсальное изображение: сеть (кэш + fade) или asset, без искажений пропорций кадра.
///
/// Габариты «рамки» считаются с учётом [MediaQuery.padding] (чёлка, индикатор home),
/// без лишнего [SafeArea] вокруг каждой картинки — оборачивайте экран в [SafeArea] при
/// полноэкранном контенте или включите [wrapInSafeArea].
class AdaptiveImage extends StatelessWidget {
  const AdaptiveImage({
    super.key,
    required this.imageUrl,
    this.isAsset = false,
    this.aspectRatio,
    this.boxFit = BoxFit.contain,
    this.maxWidthPercent = 0.9,
    this.maxHeightPercent,
    this.borderRadius = 0,
    this.memCacheMaxDimension = 2048,
    this.fadeInDuration = const Duration(milliseconds: 320),
    this.fadeOutDuration = const Duration(milliseconds: 100),
    this.filterQuality = FilterQuality.low,
    this.alignment = Alignment.center,
    this.imageAlignment = Alignment.center,
    this.assetCacheWidth,
    this.assetCacheHeight,
    this.assetGaplessPlayback = false,
    this.wrapInSafeArea = false,
    this.networkPlaceholderBuilder,
    this.networkErrorBuilder,
    this.memCacheWidthOverride,
    this.memCacheHeightOverride,
  });

  /// URL или путь к asset (`assets/...`).
  final String imageUrl;

  /// `true` — локальный ресурс через [Image.asset].
  final bool isAsset;

  final double? aspectRatio;
  final BoxFit boxFit;
  final double maxWidthPercent;
  final double? maxHeightPercent;
  final double borderRadius;
  final int memCacheMaxDimension;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;
  final FilterQuality filterQuality;

  /// Выравнивание блока в родителе ([Align]).
  final Alignment alignment;

  /// Выравнивание внутри [Image] / [CachedNetworkImage].
  final Alignment imageAlignment;

  /// Опционально уменьшает декод для asset (фоны, иконки).
  final int? assetCacheWidth;
  final int? assetCacheHeight;
  final bool assetGaplessPlayback;

  /// Оборачивает результат в [SafeArea] (редко нужно внутри уже «безопасных» лейаутов).
  final bool wrapInSafeArea;

  /// Если задано — вместо [CircularProgressIndicator] при загрузке сети.
  final AdaptiveNetworkPlaceholderBuilder? networkPlaceholderBuilder;

  /// Если задано — вместо стандартной иконки ошибки сети.
  final AdaptiveNetworkErrorBuilder? networkErrorBuilder;

  /// Явные лимиты растра для [CachedNetworkImage] (иначе считаются из [memCacheMaxDimension]).
  final int? memCacheWidthOverride;
  final int? memCacheHeightOverride;

  /// Фабрика: угадывает asset/сеть и подставляет пресет [scene].
  factory AdaptiveImage.fromSource(
    String source, {
    Key? key,
    bool isNetwork = true,
    AdaptiveImageScene scene = AdaptiveImageScene.generic,
    bool? isAsset,
    BoxFit? boxFit,
    double? maxWidthPercent,
    double? maxHeightPercent,
    double? aspectRatio,
    double borderRadius = 0,
    Alignment alignment = Alignment.center,
    Alignment imageAlignment = Alignment.center,
    int? assetCacheWidth,
    int? assetCacheHeight,
    bool assetGaplessPlayback = false,
    bool wrapInSafeArea = false,
    AdaptiveNetworkPlaceholderBuilder? networkPlaceholderBuilder,
    AdaptiveNetworkErrorBuilder? networkErrorBuilder,
    int? memCacheWidthOverride,
    int? memCacheHeightOverride,
  }) {
    final String trimmed = source.trim();
    final bool inferredAsset = _inferIsAsset(trimmed, isNetwork);
    final bool useAsset = isAsset ?? inferredAsset;
    final ({double maxW, double? ar, BoxFit fit}) p = _presetForScene(scene);
    return AdaptiveImage(
      key: key,
      imageUrl: source,
      isAsset: useAsset,
      aspectRatio: aspectRatio ?? p.ar,
      boxFit: boxFit ?? p.fit,
      maxWidthPercent: maxWidthPercent ?? p.maxW,
      maxHeightPercent: maxHeightPercent,
      borderRadius: borderRadius,
      alignment: alignment,
      imageAlignment: imageAlignment,
      assetCacheWidth: assetCacheWidth,
      assetCacheHeight: assetCacheHeight,
      assetGaplessPlayback: assetGaplessPlayback,
      wrapInSafeArea: wrapInSafeArea,
      networkPlaceholderBuilder: networkPlaceholderBuilder,
      networkErrorBuilder: networkErrorBuilder,
      memCacheWidthOverride: memCacheWidthOverride,
      memCacheHeightOverride: memCacheHeightOverride,
    );
  }

  /// Эвристика: `assets/`, отсутствие схемы `http(s)` → asset.
  static bool _inferIsAsset(String trimmed, bool isNetwork) {
    if (!isNetwork) {
      return true;
    }
    if (trimmed.startsWith('assets/')) {
      return true;
    }
    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('//')) {
      return false;
    }
    return !trimmed.contains('://');
  }

  static double _safeContentWidth(MediaQueryData mq) {
    final double w = mq.size.width - mq.padding.left - mq.padding.right;
    return w > 0 ? w : mq.size.width;
  }

  static double _safeContentHeight(MediaQueryData mq) {
    final double h = mq.size.height - mq.padding.top - mq.padding.bottom;
    return h > 0 ? h : mq.size.height;
  }

  int _memCachePx(double logicalSide, MediaQueryData mq) {
    return (logicalSide * mq.devicePixelRatio).round().clamp(
      1,
      memCacheMaxDimension,
    );
  }

  Widget _wrapRadius({required Widget child}) {
    if (borderRadius <= 0) {
      return child;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _errorTile(double w, double h) {
    return ColoredBox(
      color: const Color(0x14000000),
      child: SizedBox(
        width: w,
        height: h,
        child: const Center(
          child: Icon(Icons.error, size: 40, color: Colors.black54),
        ),
      ),
    );
  }

  Widget _placeholder(double w, double h) {
    return SizedBox(
      width: w,
      height: h,
      child: const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }

  Widget _networkCore({
    required BuildContext context,
    required String url,
    required double layoutW,
    required double layoutH,
    required MediaQueryData mq,
  }) {
    final int mw = memCacheWidthOverride ?? _memCachePx(layoutW, mq);
    final int mh = memCacheHeightOverride ?? _memCachePx(layoutH, mq);
    return CachedNetworkImage(
      imageUrl: url,
      width: layoutW,
      height: layoutH,
      fit: boxFit,
      alignment: imageAlignment,
      filterQuality: filterQuality,
      fadeInDuration: fadeInDuration,
      fadeOutDuration: fadeOutDuration,
      memCacheWidth: mw,
      memCacheHeight: mh,
      placeholder: (BuildContext context, String url) =>
          networkPlaceholderBuilder?.call(context, layoutW, layoutH) ??
          _placeholder(layoutW, layoutH),
      errorWidget: (BuildContext context, String url, Object? error) =>
          networkErrorBuilder?.call(context, layoutW, layoutH, error) ??
          _errorTile(layoutW, layoutH),
    );
  }

  Widget _assetCore({
    required String path,
    required double layoutW,
    required double layoutH,
  }) {
    return Image.asset(
      path,
      width: layoutW,
      height: layoutH,
      fit: boxFit,
      alignment: imageAlignment,
      filterQuality: filterQuality,
      cacheWidth: assetCacheWidth,
      cacheHeight: assetCacheHeight,
      gaplessPlayback: assetGaplessPlayback,
      errorBuilder:
          (BuildContext context, Object error, StackTrace? stackTrace) {
            return _errorTile(layoutW, layoutH);
          },
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
                tween: Tween<double>(begin: 0, end: 1),
                duration: fadeInDuration,
                curve: Curves.easeOut,
                builder: (BuildContext context, double opacity, Widget? _) {
                  return Opacity(opacity: opacity, child: child);
                },
              );
            }
            // Пока первый кадр не готов — лёгкий индикатор (asset обычно мгновенен).
            return _placeholder(layoutW, layoutH);
          },
    );
  }

  /// Рамка с заданным [aspectRatio]: вписывается в maxW×maxH без выхода за границы.
  ({double w, double h}) _cellForAspect(double maxW, double maxH, double ar) {
    double w = maxW;
    double h = w / ar;
    if (h > maxH) {
      h = maxH;
      w = h * ar;
    }
    return (w: w, h: h);
  }

  Widget _buildSized(
    BuildContext context, {
    required BoxConstraints constraints,
    required MediaQueryData mq,
    required String path,
  }) {
    final double safeW = _safeContentWidth(mq);
    final double safeH = _safeContentHeight(mq);

    final double parentW =
        constraints.hasBoundedWidth && constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : safeW;
    final double parentH =
        constraints.hasBoundedHeight && constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : safeH;

    final double pctW = maxWidthPercent.clamp(0.01, 1.0);
    final double maxW = math.min(parentW, safeW * pctW);

    final double pctH = (maxHeightPercent ?? 0.7).clamp(0.01, 1.0);
    final double maxH = math.min(
      parentH.isFinite ? parentH : safeH * pctH,
      safeH * pctH,
    );

    final double effMaxW = math.max(1, maxW);
    final double effMaxH = math.max(1, maxH);

    late final double layoutW;
    late final double layoutH;

    final double? ar = aspectRatio;
    if (ar != null && ar > 0) {
      final ({double w, double h}) cell = _cellForAspect(effMaxW, effMaxH, ar);
      layoutW = cell.w;
      layoutH = cell.h;
    } else {
      layoutW = effMaxW;
      layoutH = effMaxH;
    }

    Widget core = isAsset
        ? _assetCore(path: path, layoutW: layoutW, layoutH: layoutH)
        : _networkCore(
            context: context,
            url: path,
            layoutW: layoutW,
            layoutH: layoutH,
            mq: mq,
          );

    if (ar != null && ar > 0) {
      core = SizedBox(
        width: layoutW,
        height: layoutH,
        child: AspectRatio(aspectRatio: ar, child: core),
      );
    }

    return _wrapRadius(
      child: Align(alignment: alignment, child: core),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String path = imageUrl.trim();
    if (path.isEmpty) {
      return const Center(
        child: Icon(Icons.error, size: 40, color: Colors.black54),
      );
    }

    Widget tree = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final MediaQueryData mq = MediaQuery.of(context);
        return _buildSized(
          context,
          constraints: constraints,
          mq: mq,
          path: path,
        );
      },
    );

    if (wrapInSafeArea) {
      tree = SafeArea(child: tree);
    }

    return tree;
  }
}
