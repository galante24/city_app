# city_app

Приложение «Лесосибирск» (Flutter). Сборка и ключи — см. `api_keys.example.json`, `--dart-define-from-file=api_keys.json`.

## Быстрый старт

```bash
flutter pub get
dart run tool/setup.dart
flutter run --dart-define-from-file=api_keys.json
```

## Adaptive images & custom_lint

Сеть и `assets/` для UI: [**`AdaptiveImage`**](lib/widgets/adaptive_image.dart) и гайд [**`docs/IMAGE_GUIDELINES.md`**](docs/IMAGE_GUIDELINES.md). В CI на каждый PR/push в `main` гоняется **`dart run tool/check_adaptive_image_policy.dart`** (см. [`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

### Путь к проекту **без пробелов** (рекомендуется)

Инструмент **`custom_lint`** с локальным пакетом **`packages/city_app_lints`** на Windows часто **ломается**, если каталог содержит пробел (например `C:\My Projects\city_app`). Клонируйте в путь вида **`C:\src\city_app`** или **`C:\Projects\city_app`**.

После клонирования в такой путь:

1. В **`pubspec.yaml`** в `dev_dependencies` добавьте:

   ```yaml
   custom_lint: ^0.7.5
   city_app_lints:
     path: packages/city_app_lints
   ```

2. В **`analysis_options.yaml`** под `analyzer:`:

   ```yaml
   plugins:
     - custom_lint
   errors:
     use_adaptive_image: error
   ```

3. Выполните **`flutter pub get`**.

4. Проверка: **`dart run custom_lint`** — при появлении в `lib/` прямых **`Image.network`** / **`Image.asset`** (кроме [`lib/widgets/adaptive_image.dart`](lib/widgets/adaptive_image.dart)) должны быть ошибки **`use_adaptive_image`**.

Подробности: [`packages/city_app_lints/README.md`](packages/city_app_lints/README.md).

## Документация Flutter

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
