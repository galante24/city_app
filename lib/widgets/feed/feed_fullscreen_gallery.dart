import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

/// Полноэкранная галерея: [PhotoView] + [enablePanAlways] — свободный pan при зуме;
/// [PhotoViewGestureDetectorScope] — приоритет жестов зума над горизонтальным листанием;
/// при увеличении / смещении [PageView] блокируется; двойной тап и инерция — из [photo_view].
class FeedFullscreenGallery extends StatefulWidget {
  const FeedFullscreenGallery({
    super.key,
    required this.urls,
    this.initialIndex = 0,
  });

  final List<String> urls;
  final int initialIndex;

  @override
  State<FeedFullscreenGallery> createState() => _FeedFullscreenGalleryState();
}

class _FeedFullscreenGalleryState extends State<FeedFullscreenGallery> {
  late final PageController _pageController;
  late int _index;
  late final List<PhotoViewController> _photoControllers;
  final List<StreamSubscription<PhotoViewControllerValue>> _scaleSubs =
      <StreamSubscription<PhotoViewControllerValue>>[];

  final Map<int, double> _scaleBaselineByPage = <int, double>{};

  bool _galleryPagingLocked = false;

  @override
  void initState() {
    super.initState();
    final List<String> urls = widget.urls;
    _index = widget.initialIndex.clamp(0, urls.length - 1);
    _pageController = PageController(initialPage: _index);
    _photoControllers = List<PhotoViewController>.generate(
      urls.length,
      (_) => PhotoViewController(),
    );
    for (int i = 0; i < urls.length; i++) {
      final StreamSubscription<PhotoViewControllerValue> sub =
          _photoControllers[i].outputStateStream.listen(
            (PhotoViewControllerValue v) => _onPhotoValueChanged(i, v),
          );
      _scaleSubs.add(sub);
    }
  }

  @override
  void dispose() {
    for (final StreamSubscription<PhotoViewControllerValue> s in _scaleSubs) {
      unawaited(s.cancel());
    }
    _scaleSubs.clear();
    for (final PhotoViewController c in _photoControllers) {
      c.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  void _setPagingLocked(bool locked) {
    if (_galleryPagingLocked == locked) {
      return;
    }
    setState(() => _galleryPagingLocked = locked);
  }

  void _onPhotoValueChanged(int pageIndex, PhotoViewControllerValue v) {
    if (!mounted || pageIndex != _index) {
      return;
    }
    final double? sc = v.scale;
    if (sc == null) {
      return;
    }
    if (!_scaleBaselineByPage.containsKey(pageIndex)) {
      _scaleBaselineByPage[pageIndex] = sc;
      _setPagingLocked(false);
      return;
    }
    final double base = _scaleBaselineByPage[pageIndex]!;
    const double tol = 0.04;
    final bool scaleAwayFromBaseline =
        sc > base * (1.0 + tol) || sc < base * (1.0 - tol);
    final bool panned = v.position.distance > 2.0;
    _setPagingLocked(scaleAwayFromBaseline || panned);
  }

  void _onScaleStateChanged(PhotoViewScaleState state) {
    if (!mounted) {
      return;
    }
    if (state.isScaleStateZooming) {
      _setPagingLocked(true);
      return;
    }
    if (state == PhotoViewScaleState.initial) {
      _setPagingLocked(false);
    }
  }

  void _onGalleryPageChanged(int i) {
    setState(() {
      _index = i;
      _galleryPagingLocked = false;
      _scaleBaselineByPage.remove(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<String> urls = widget.urls;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.78),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: RepaintBoundary(
              child: PhotoViewGestureDetectorScope(
                axis: Axis.horizontal,
                child: PageView.builder(
                  controller: _pageController,
                  physics: _galleryPagingLocked
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
                  onPageChanged: _onGalleryPageChanged,
                  itemCount: urls.length,
                  itemBuilder: (BuildContext context, int i) {
                    return RepaintBoundary(
                      child: ClipRect(
                        child: PhotoView(
                          imageProvider: CachedNetworkImageProvider(urls[i]),
                          controller: _photoControllers[i],
                          enablePanAlways: true,
                          wantKeepAlive: true,
                          gaplessPlayback: true,
                          minScale: PhotoViewComputedScale.contained,
                          maxScale: PhotoViewComputedScale.covered * 4,
                          initialScale: PhotoViewComputedScale.contained,
                          basePosition: Alignment.center,
                          filterQuality: FilterQuality.medium,
                          backgroundDecoration: const BoxDecoration(
                            color: Colors.transparent,
                          ),
                          scaleStateChangedCallback: _onScaleStateChanged,
                          loadingBuilder:
                              (BuildContext context, ImageChunkEvent? event) {
                                final double? p =
                                    event == null ||
                                        event.expectedTotalBytes == null
                                    ? null
                                    : event.cumulativeBytesLoaded /
                                          (event.expectedTotalBytes ?? 1);
                                return Center(
                                  child: SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: CircularProgressIndicator(
                                      color: Colors.white70,
                                      value: p,
                                    ),
                                  ),
                                );
                              },
                          errorBuilder:
                              (BuildContext ctx, Object err, StackTrace? st) {
                                return const Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: Colors.white54,
                                    size: 64,
                                  ),
                                );
                              },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
              child: Row(
                children: <Widget>[
                  Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      tooltip: 'Закрыть',
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text(
                            '${_index + 1} / ${urls.length}',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
