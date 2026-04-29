import 'dart:io';

import 'package:flutter/widgets.dart';

ImageProvider? universalLocalImageProvider({Object? file, String? filePath}) {
  if (file is File) {
    return FileImage(file);
  }
  final String? p = filePath?.trim();
  if (p != null && p.isNotEmpty) {
    return FileImage(File(p));
  }
  return null;
}
