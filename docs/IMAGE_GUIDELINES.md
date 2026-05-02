# Руководство по изображениям в city_app

## Правило

**Все изображения из сети или из `assets/` должны отображаться через [`AdaptiveImage`](../lib/widgets/adaptive_image.dart)** (или [`AdaptiveImage.fromSource`](../lib/widgets/adaptive_image.dart) с пресетом сцены). Прямые вызовы `Image.network` и `Image.asset` не используются; политика проверяется скриптом `tool/check_adaptive_image_policy.dart`. Опционально можно подключить пакет [`packages/city_app_lints`](../packages/city_app_lints/README.md) и **custom_lint** (если путь к проекту без пробелов в имени папки).

Исключения допускаются только внутри самой реализации `adaptive_image.dart`.

## Зачем

- Единое масштабирование с учётом вырезов (`MediaQuery.padding`), без «рваных» пропорций.
- Кэш и плавное появление для сети (`cached_network_image`).
- Индикатор загрузки и иконка ошибки в одном стиле.

## Примеры

### Сеть, универсальный размер

```dart
AdaptiveImage(
  imageUrl: url,
  maxWidthPercent: 0.9,
  boxFit: BoxFit.contain,
)
```

### Пресет «чат» (0.6 ширины, `BoxFit.cover`)

```dart
AdaptiveImage.fromSource(
  messageImageUrl,
  scene: AdaptiveImageScene.chat,
)
```

### Пресет «пост» (16:9, 90 % ширины)

```dart
AdaptiveImage.fromSource(
  coverUrl,
  scene: AdaptiveImageScene.feedPost,
)
```

### Локальный asset

```dart
AdaptiveImage(
  imageUrl: 'assets/app_icon.png',
  isAsset: true,
  maxWidthPercent: 1,
  boxFit: BoxFit.cover,
)
```

### Supabase Storage → URL → виджет

```dart
import '../services/supabase_image_service.dart';
import '../widgets/adaptive_image.dart';

final String url = SupabaseImageService.getPublicUrl('posts', '2025/photo.jpg');
AdaptiveImage(imageUrl: url, scene: AdaptiveImageScene.feedPost);
```

Убедитесь, что `Supabase.initialize` уже выполнен и `supabaseAppReady == true`; иначе `getPublicUrl` вернёт пустую строку.

## Шаблон нового экрана

Скопируйте [`lib/templates/page_with_images.template.dart`](../lib/templates/page_with_images.template.dart) в `lib/screens/` и адаптируйте.

## Проверка без IDE

```bash
dart run tool/check_adaptive_image_policy.dart
```

Скрипт ищет запрещённые конструкторы в `lib/` (дублирует политику линтера в CI).

## Дальнейшие улучшения

- Жесты зума (`InteractiveViewer` / `photo_view`) для полноэкранного просмотра.
- Прелоадинг соседних кадров в `PageView` / ленте.
- BlurHash / LQIP в placeholder.
