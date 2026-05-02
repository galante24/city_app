// Политика: в lib/ не должно быть прямых Image.network / Image.asset (дубль custom_lint).
//
// Запуск из корня приложения: dart run tool/check_adaptive_image_policy.dart

import 'dart:io';

final RegExp _network = RegExp(r'\bImage\.network\s*\(');
final RegExp _asset = RegExp(r'\bImage\.asset\s*\(');

bool _allowedPath(String p) {
  final String n = p.replaceAll(r'\', '/');
  return n.endsWith('lib/widgets/adaptive_image.dart');
}

Future<void> main(List<String> args) async {
  final Directory lib = Directory('lib');
  if (!lib.existsSync()) {
    stderr.writeln('Запускайте из каталога city_app (нет папки lib/).');
    exit(2);
  }

  final List<String> hits = <String>[];
  await for (final FileSystemEntity e in lib.list(
    recursive: true,
    followLinks: false,
  )) {
    if (e is! File || !e.path.endsWith('.dart')) {
      continue;
    }
    if (_allowedPath(e.path)) {
      continue;
    }
    final String content = e.readAsStringSync();
    if (_network.hasMatch(content) || _asset.hasMatch(content)) {
      if (_network.hasMatch(content)) {
        hits.add('${e.path}: Image.network');
      }
      if (_asset.hasMatch(content)) {
        hits.add('${e.path}: Image.asset');
      }
    }
  }

  if (hits.isNotEmpty) {
    stderr.writeln('Найдены запрещённые вызовы (используйте AdaptiveImage):\n');
    for (final String h in hits) {
      stderr.writeln('  $h');
    }
    exit(1);
  }
  stdout.writeln(
    'OK: Image.network / Image.asset в lib/ не найдены (кроме adaptive_image.dart).',
  );
}
