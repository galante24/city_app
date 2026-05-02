import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../widgets/media_progressive_image.dart';

/// Вынесенный кэш соотношения сторон по URL — меньше работы при скролле списка.
final Map<String, Size> _chatImageIntrinsicSizeCache = <String, Size>{};

/// Превью изображения в чате: ограничение по ширине экрана, [BoxFit.cover], кэш.
class ChatImageBubble extends StatefulWidget {
  const ChatImageBubble({
    super.key,
    required this.imageUrl,
    required this.isMe,
  });

  final String imageUrl;
  final bool isMe;

  @override
  State<ChatImageBubble> createState() => _ChatImageBubbleState();
}

class _ChatImageBubbleState extends State<ChatImageBubble> {
  static const double _kMaxHeight = 280;
  static const double _kCornerRadius = 14;
  static const Color _kPlaceholderColor = Color(0xFFE0E0E0);

  /// Плейсхолдер до известных пропорций — тот же max width, AR 4:3, без скачка высоты баббла.
  static const double _kPlaceholderAspect = 16 / 9;

  Size? _intrinsic;
  bool _failed = false;
  ImageStream? _dimensionStream;
  ImageStreamListener? _dimensionListener;

  @override
  void initState() {
    super.initState();
    _primeFromCache();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureDimensionsLoading();
  }

  @override
  void didUpdateWidget(ChatImageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _detachDimensionStream();
      _failed = false;
      _intrinsic = null;
      _primeFromCache();
      _ensureDimensionsLoading();
    }
  }

  void _primeFromCache() {
    final String u = widget.imageUrl.trim();
    if (u.isEmpty) {
      _failed = true;
      return;
    }
    final Size? c = _chatImageIntrinsicSizeCache[u];
    if (c != null) {
      _intrinsic = c;
    }
  }

  void _detachDimensionStream() {
    if (_dimensionStream != null && _dimensionListener != null) {
      _dimensionStream!.removeListener(_dimensionListener!);
    }
    _dimensionStream = null;
    _dimensionListener = null;
  }

  void _ensureDimensionsLoading() {
    if (_intrinsic != null || _failed) return;
    final String u = widget.imageUrl.trim();
    if (u.isEmpty) {
      setState(() => _failed = true);
      return;
    }
    if (_dimensionStream != null) return;

    final ImageProvider provider = CachedNetworkImageProvider(u);
    final ImageStream stream = provider.resolve(
      createLocalImageConfiguration(context),
    );
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        stream.removeListener(listener);
        if (!mounted) return;
        final Size sz = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
        _chatImageIntrinsicSizeCache[u] = sz;
        setState(() => _intrinsic = sz);
        _dimensionStream = null;
        _dimensionListener = null;
      },
      onError: (Object exception, StackTrace? stackTrace) {
        stream.removeListener(listener);
        if (!mounted) return;
        setState(() {
          _failed = true;
          _dimensionStream = null;
          _dimensionListener = null;
        });
      },
    );
    _dimensionStream = stream;
    _dimensionListener = listener;
    stream.addListener(listener);
  }

  @override
  void dispose() {
    _detachDimensionStream();
    super.dispose();
  }

  /// Размер прямоугольника с натуральным AR, вписанного в [maxW]×[maxH].
  Size _layoutSize(Size intrinsic, double maxW, double maxH) {
    final double iw = intrinsic.width;
    final double ih = intrinsic.height;
    if (iw <= 0 || ih <= 0 || !iw.isFinite || !ih.isFinite) {
      return Size(maxW, maxH);
    }
    final double ar = iw / ih;
    double h = maxH;
    double w = h * ar;
    if (w > maxW) {
      w = maxW;
      h = w / ar;
    }
    return Size(w, h);
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    final double maxW = mq.size.width * 0.7;
    final Alignment align = widget.isMe
        ? Alignment.centerRight
        : Alignment.centerLeft;

    if (widget.imageUrl.trim().isEmpty || _failed) {
      return RepaintBoundary(
        child: Align(
          alignment: align,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW, maxHeight: _kMaxHeight),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_kCornerRadius),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: 120,
                width: math.min(maxW, 160),
                child: ColoredBox(
                  color: _kPlaceholderColor,
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.grey.shade600,
                    size: 40,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_intrinsic == null) {
      final double placeholderW = math.min(maxW, math.max(100.0, maxW * 0.5));
      final double placeholderH = placeholderW / _kPlaceholderAspect;
      return RepaintBoundary(
        child: Align(
          alignment: align,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW, maxHeight: _kMaxHeight),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_kCornerRadius),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: placeholderW,
                height: math.min(placeholderH, _kMaxHeight),
                child: MediaShimmerBox(
                  width: placeholderW,
                  height: math.min(placeholderH, _kMaxHeight),
                  borderRadius: _kCornerRadius,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final Size box = _layoutSize(_intrinsic!, maxW, _kMaxHeight);
    final double dpr = mq.devicePixelRatio;
    final int memW = (box.width * dpr).round().clamp(1, 4096);
    final int memH = (box.height * dpr).round().clamp(1, 4096);

    return RepaintBoundary(
      child: Align(
        alignment: align,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW, maxHeight: _kMaxHeight),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_kCornerRadius),
            clipBehavior: Clip.antiAlias,
            child: CachedNetworkImage(
              imageUrl: widget.imageUrl,
              width: box.width,
              height: box.height,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
              fadeInDuration: const Duration(milliseconds: 380),
              fadeOutDuration: const Duration(milliseconds: 100),
              memCacheWidth: memW,
              memCacheHeight: memH,
              placeholder: (BuildContext context, String _) {
                return MediaShimmerBox(
                  width: box.width,
                  height: box.height,
                  borderRadius: _kCornerRadius,
                );
              },
              errorWidget: (BuildContext context, String url, Object error) {
                return SizedBox(
                  width: box.width,
                  height: box.height,
                  child: ColoredBox(
                    color: _kPlaceholderColor,
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.grey.shade600,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
