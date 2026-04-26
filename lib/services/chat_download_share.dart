import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Скачать по URL во временный файл и открыть системное меню «поделиться» (можно сохранить).
Future<void> shareNetworkFileToDevice({
  required BuildContext context,
  required String url,
  required String suggestedName,
}) async {
  final http.Response r = await http.get(Uri.parse(url));
  if (r.statusCode != 200) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить ($url)')),
      );
    }
    return;
  }
  final Directory dir = await getTemporaryDirectory();
  final String safe = suggestedName.replaceAll(RegExp(r'[^\w\.\-]+'), '_');
  final File f = File('${dir.path}/$safe');
  await f.writeAsBytes(r.bodyBytes);
  if (!context.mounted) {
    return;
  }
  await Share.shareXFiles(<XFile>[XFile(f.path)], subject: safe);
}
