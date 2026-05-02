import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Сжатие JPEG перед загрузкой в Supabase (мобильные / десктоп). На web — без изменений.
Future<XFile> compressFeedImageIfSupported(XFile file) async {
  if (kIsWeb) {
    return file;
  }
  final String path = file.path;
  if (path.isEmpty) {
    return file;
  }
  final String lower = path.toLowerCase();
  if (!lower.endsWith('.jpg') &&
      !lower.endsWith('.jpeg') &&
      !lower.endsWith('.png') &&
      !lower.endsWith('.webp')) {
    return file;
  }
  try {
    final Directory tmp = await getTemporaryDirectory();
    final String outPath = p.join(
      tmp.path,
      'feed_cmp_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    final XFile? out = await FlutterImageCompress.compressAndGetFile(
      path,
      outPath,
      quality: 78,
      minWidth: 1600,
      minHeight: 1600,
      format: CompressFormat.jpeg,
    );
    return out ?? file;
  } on Object {
    return file;
  }
}
