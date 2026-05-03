// Инициализация окружения разработчика: pub get, политика изображений, подсказка custom_lint.
//
// Запуск из корня приложения: dart run tool/setup.dart

import 'dart:io';

Future<void> main(List<String> args) async {
  final String cwd = Directory.current.path;
  stdout.writeln('setup: cwd=$cwd');

  if (cwd.contains(' ')) {
    stderr.writeln(
      'Внимание: путь к проекту содержит пробел. Пакет custom_lint + city_app_lints '
      'часто не резолвится (см. packages/city_app_lints/README.md). '
      'Рекомендуется клонировать в каталог без пробелов, например C:\\src\\city_app.',
    );
  } else {
    stdout.writeln(
      'Путь без пробелов — при желании подключите custom_lint по README.md '
      '(раздел «Adaptive images & custom_lint»).',
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

  final ProcessResult policy = await Process.run(
    'dart',
    <String>['run', 'tool/check_adaptive_image_policy.dart'],
    workingDirectory: cwd,
    runInShell: true,
  );
  stdout.write(policy.stdout);
  stderr.write(policy.stderr);
  if (policy.exitCode != 0) {
    exit(policy.exitCode);
  }

  final File pubspec = File('$cwd${Platform.pathSeparator}pubspec.yaml');
  if (pubspec.existsSync()) {
    final String yaml = pubspec.readAsStringSync();
    final bool hasCustomLint =
        yaml.contains('custom_lint:') && yaml.contains('city_app_lints');
    if (hasCustomLint) {
      stdout.writeln(
        'setup: в pubspec найдены custom_lint и city_app_lints — проверка плагина…',
      );
      final ProcessResult lint = await Process.run(
        'dart',
        <String>['run', 'custom_lint'],
        workingDirectory: cwd,
        runInShell: true,
      );
      stdout.write(lint.stdout);
      stderr.write(lint.stderr);
      if (lint.exitCode != 0) {
        stderr.writeln(
          'setup: custom_lint завершился с кодом ${lint.exitCode}',
        );
        exit(lint.exitCode);
      }
    } else {
      stdout.writeln(
        'setup: custom_lint не подключён в pubspec — пропуск dart run custom_lint.',
      );
    }
  }

  stdout.writeln('setup: готово.');
}
