# city_app_lints

Правило **`use_adaptive_image`**: запрещает `Image.network` и `Image.asset` вне `lib/widgets/adaptive_image.dart`.

## Подключение (опционально)

1. В корне приложения `city_app` в `pubspec.yaml` добавьте в `dev_dependencies`:

   ```yaml
   custom_lint: ^0.7.5
   city_app_lints:
     path: packages/city_app_lints
   ```

2. В `analysis_options.yaml`:

   ```yaml
   analyzer:
     plugins:
       - custom_lint
     errors:
       use_adaptive_image: error
   ```

3. Выполните `flutter pub get` и `dart run custom_lint`.

**Ограничение:** у некоторых версий `custom_lint` на Windows путь к проекту с **пробелом** в имени каталога приводит к ошибке разрешения `path:`. В этом случае используйте только:

```bash
dart run tool/check_adaptive_image_policy.dart
```

(из каталога `city_app`).
