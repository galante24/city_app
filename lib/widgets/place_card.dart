import 'package:flutter/material.dart';

import '../utils/image_cache_extent.dart';

/// Квадратное превью заведения в списке (обложка / логотип).
class PlaceListSquareThumb extends StatelessWidget {
  const PlaceListSquareThumb({
    super.key,
    required this.imageUrl,
    this.size = 80,
    this.borderRadius = 16,
  });

  final String? imageUrl;
  final double size;
  final double borderRadius;

  static Widget _grayPlaceholder() {
    return const ColoredBox(
      color: Color(0xFFE8EAED),
      child: Center(
        child: Icon(
          Icons.storefront_outlined,
          size: 32,
          color: Color(0xFF9AA0A6),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? url = imageUrl?.trim();
    final bool hasUrl = url != null && url.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: hasUrl
            ? Image.network(
                url,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                width: size,
                height: size,
                cacheWidth: imageCacheExtentPx(context, size),
                cacheHeight: imageCacheExtentPx(context, size),
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
                      _grayPlaceholder(),
                      const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ],
                  );
                },
                errorBuilder:
                    (BuildContext context, Object error, StackTrace? st) =>
                        _grayPlaceholder(),
              )
            : _grayPlaceholder(),
      ),
    );
  }
}
