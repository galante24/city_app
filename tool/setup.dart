// Локальная инициализация: pub get, политика изображений, опционально custom_lint.
// Запуск из корня приложения: dart run tool/setup.dart

import 'dart:io';

Future<void> main(List<String> args) async {
  final String cwd = Directory.current.path;
  if (cwd.contains(' ')) {
    stderr.writeln(
      '[setup] В пути к проекту есть пробел — `dart run custom_lint` может не '
      'разрешить path-зависимость на city_app_lints. Клонируйте в каталог без '
      'пробелов (например C:\\dev\\city_app), см. README.md.',
    );
  }

  final ProcessResult pubGet = await Process.run(
    'flutter',
    <String>['pub', 'get'],
    workingDirectory: cwd,
    runInShell: true,
  );
  stdout.write(pubGet.stdout);
  stderr.write(pubGet.stderr);
  if (pubGet.exitCode != 0) {
    exit(pubGet.exitCode);
  }

  final String pubspec = File(
    '$cwd${Platform.pathSeparator}pubspec.yaml',
  ).readAsStringSync();
  final bool wantsCustomLint =
      pubspec.contains('custom_lint:') && pubspec.contains('city_app_lints');

  if (wantsCustomLint && !cwd.contains(' ')) {
    stdout.writeln('[setup] dart run custom_lint');
    final ProcessResult lint = await Process.run(
      'dart',
      <String>['run', 'custom_lint'],
      workingDirectory: cwd,
      runInShell: true,
    );
    stdout.write(lint.stdout);
    stderr.write(lint.stderr);
    if (lint.exitCode != 0) {
      exit(lint.exitCode);
    }
  } else if (wantsCustomLint && cwd.contains(' ')) {
    stdout.writeln(
      '[setup] Пропуск custom_lint (пробел в пути к репозиторию).',
    );
  }

  stdout.writeln('[setup] dart run tool/check_adaptive_image_policy.dart');
  final ProcessResult policy = await Process.run(
    'dart',
    <String>['run', 'tool/check_adaptive_image_policy.dart'],
    workingDirectory: cwd,
    runInShell: true,
  );
  stdout.write(policy.stdout);
  stderr.write(policy.stderr);
  exit(policy.exitCode);
}
