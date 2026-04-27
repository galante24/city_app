import 'package:flutter/material.dart';

import 'city_network_image.dart';

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
    return hasUrl
        ? CityNetworkImage.square(
            imageUrl: url,
            size: size,
            borderRadius: borderRadius,
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: SizedBox(
              width: size,
              height: size,
              child: _grayPlaceholder(),
            ),
          );
  }
}
