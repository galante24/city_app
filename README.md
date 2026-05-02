# city_app

Приложение «Лесосибирск» (Flutter + Supabase).

## Быстрый старт

1. Установите [Flutter](https://docs.flutter.dev/get-started/install) (stable).
2. Склонируйте репозиторий. **Для опционального [custom_lint](https://pub.dev/packages/custom_lint)** используйте путь **без пробелов** в имени каталога, например `C:\Projects\city_app`, а не `C:\My Projects\city_app` — иначе `dart run custom_lint` может не найти path-зависимость `packages/city_app_lints`.
3. В корне приложения выполните:

```bash
dart run tool/setup.dart
```

Скрипт выполнит `flutter pub get`, при подключённом в `pubspec.yaml` пакете `custom_lint` и пути без пробелов — `dart run custom_lint`, затем **`dart run tool/check_adaptive_image_policy.dart`** (запрет прямых `Image.network` / `Image.asset` в `lib/`).

Вручную:

```bash
flutter pub get
dart run tool/check_adaptive_image_policy.dart
```

Ключи Supabase и др.: см. `api_keys.example.json`, запуск с `--dart-define-from-file=api_keys.json`.

## Политика изображений

Все сетевые и asset-картинки в `lib/` должны идти через [`AdaptiveImage`](lib/widgets/adaptive_image.dart). Подробности: [docs/IMAGE_GUIDELINES.md](docs/IMAGE_GUIDELINES.md).

### Подключение custom_lint (путь без пробелов)

1. Убедитесь, что каталог клона **не содержит пробелов** в полном пути.
2. В `pubspec.yaml` в `dev_dependencies` добавьте:

```yaml
  custom_lint: ^0.7.5
  city_app_lints:
    path: packages/city_app_lints
```

3. В `analysis_options.yaml` в секции `analyzer:`:

```yaml
analyzer:
  plugins:
    - custom_lint
  errors:
    use_adaptive_image: error
```

4. Выполните `flutter pub get`, затем `dart run custom_lint`. При нарушении (прямой `Image.asset` / `Image.network` вне `lib/widgets/adaptive_image.dart`) анализатор сообщит правилом **`use_adaptive_image`**.

Полный README пакета линтов: [packages/city_app_lints/README.md](packages/city_app_lints/README.md).

## CI

Workflow [`.github/workflows/flutter_ci.yml`](.github/workflows/flutter_ci.yml) на **pull_request** и **push** в `main`/`master` запускает `dart run tool/check_adaptive_image_policy.dart` и `flutter analyze`.
