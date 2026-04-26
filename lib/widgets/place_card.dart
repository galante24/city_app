import 'package:flutter/material.dart';

import 'vacancy_card.dart';

/// Превью фото заведения в списке: соотношение 16∶9, [BoxFit.cover] — как у вакансий.
class PlaceListCoverImage extends StatelessWidget {
  const PlaceListCoverImage({
    super.key,
    required this.imageUrl,
    this.width = 108,
    this.borderRadius = 12,
  });

  final String? imageUrl;
  final double width;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return VacancyCoverImage(
      imageUrl: imageUrl,
      width: width,
      borderRadius: borderRadius,
    );
  }
}
