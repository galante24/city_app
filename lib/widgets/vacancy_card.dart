import 'package:flutter/material.dart';

import 'universal_image_widget.dart';

/// Превью обложки; карточка строки списка — виджет `CloudInkCard` в `app_card_styles.dart`.

/// Ширина : высота превью вакансии (единый стиль списка и детального экрана).
const double kVacancyCoverAspectRatio = 16 / 9;

/// Превью фото вакансии: фиксированное соотношение сторон, [BoxFit.cover], скругление.
///
/// [width] — для строки списка; если `null`, ширина берётся из родителя ([LayoutBuilder]).
class VacancyCoverImage extends StatelessWidget {
  const VacancyCoverImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.borderRadius = 16,
    this.fit = BoxFit.cover,
    this.letterboxColor,
  });

  final String? imageUrl;
  final double? width;
  final double borderRadius;

  /// В карточках списка — [BoxFit.cover]; на экране деталей — [BoxFit.contain].
  final BoxFit fit;

  /// Фон при [BoxFit.contain] (поля по краям без искажения).
  final Color? letterboxColor;

  @override
  Widget build(BuildContext context) {
    return UniversalImageWidget(
      imageUrl: imageUrl,
      width: width,
      aspectRatio: kVacancyCoverAspectRatio,
      borderRadius: borderRadius,
      fit: fit,
      backgroundColor: letterboxColor ?? const Color(0xFFE8EAED),
      placeholderIcon: Icons.image_outlined,
    );
  }
}
