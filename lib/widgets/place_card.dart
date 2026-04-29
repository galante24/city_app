import 'package:flutter/material.dart';

import 'universal_image_widget.dart';

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

  @override
  Widget build(BuildContext context) {
    return UniversalImageWidget(
      imageUrl: imageUrl,
      width: size,
      height: size,
      aspectRatio: 1,
      borderRadius: borderRadius,
      fit: BoxFit.cover,
      placeholderIcon: Icons.storefront_outlined,
    );
  }
}
