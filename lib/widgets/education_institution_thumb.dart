import 'package:flutter/material.dart';

import 'universal_image_widget.dart';

/// Превью образовательного учреждения (школа, ВУЗ): горизонтальное 4:3 с ограничением высоты.
///
/// Пример для [ListView.builder]: виджет создаётся только для видимых строк;
/// тяжёлые изображения декодируются с [UniversalImageWidget] memCache.
class EducationInstitutionThumb extends StatelessWidget {
  const EducationInstitutionThumb({
    super.key,
    required this.imageUrl,
    this.maxHeight = 140,
    this.borderRadius = 12,
    this.fit = BoxFit.cover,
  });

  final String? imageUrl;
  final double maxHeight;
  final double borderRadius;
  final BoxFit fit;

  static const double _kAspect = 4 / 3;

  @override
  Widget build(BuildContext context) {
    return UniversalImageWidget(
      imageUrl: imageUrl,
      aspectRatio: _kAspect,
      maxHeight: maxHeight,
      borderRadius: borderRadius,
      fit: fit,
      placeholderIcon: Icons.school_outlined,
    );
  }
}
