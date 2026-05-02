// ШАБЛОН: скопируйте файл в `lib/screens/...` и переименуйте в реальный экран.
//
// Для добавления изображения **всегда** используйте [AdaptiveImage] или
// [AdaptiveImage.fromSource] — не вызывайте [Image.network] / [Image.asset]
// напрямую (см. docs/IMAGE_GUIDELINES.md и `dart run tool/check_adaptive_image_policy.dart`).
//
// ignore_for_file: unused_element, unreachable_from_main

import 'package:flutter/material.dart';

import '../services/supabase_image_service.dart';
import '../widgets/adaptive_image.dart';

/// Пример экрана с картинками в разных контекстах (подставьте свои URL/пути).
class PageWithImagesTemplate extends StatelessWidget {
  const PageWithImagesTemplate({super.key});

  static const String _sampleAsset = 'assets/app_icon.png';

  @override
  Widget build(BuildContext context) {
    // Пример URL из Storage (замените bucket и путь на реальные).
    final String publicUrl = SupabaseImageService.getPublicUrl(
      'avatars',
      'user/profile.png',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Шаблон: изображения')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text('Чат (пресет):'),
          const SizedBox(height: 8),
          AdaptiveImage.fromSource(
            publicUrl.isNotEmpty ? publicUrl : 'https://picsum.photos/800/600',
            scene: AdaptiveImageScene.chat,
          ),
          const SizedBox(height: 24),
          const Text('Пост 16:9 (пресет):'),
          const SizedBox(height: 8),
          AdaptiveImage.fromSource(
            publicUrl.isNotEmpty ? publicUrl : 'https://picsum.photos/800/450',
            scene: AdaptiveImageScene.feedPost,
          ),
          const SizedBox(height: 24),
          const Text('Вакансия (пресет):'),
          const SizedBox(height: 8),
          AdaptiveImage.fromSource(
            publicUrl.isNotEmpty ? publicUrl : 'https://picsum.photos/600/400',
            scene: AdaptiveImageScene.vacancy,
          ),
          const SizedBox(height: 24),
          const Text('Локальный asset:'),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: AdaptiveImage(
              imageUrl: _sampleAsset,
              isAsset: true,
              maxWidthPercent: 0.5,
              boxFit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }
}
