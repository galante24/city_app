import 'package:flutter/widgets.dart';

/// Логические пиксели → пиксели растра для `memCacheWidth` / `memCacheHeight`
/// ([CachedNetworkImage] и др.).
/// Уменьшает декодирование и память без видимой потери в списках и превью.
int imageCacheExtentPx(BuildContext context, double logicalPixels) {
  final double dpr = MediaQuery.devicePixelRatioOf(context);
  final int n = (logicalPixels * dpr).round();
  if (n < 1) {
    return 1;
  }
  if (n > 2048) {
    return 2048;
  }
  return n;
}
