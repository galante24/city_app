import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_ready.dart';

/// Публичные URL файлов в Supabase Storage для отображения через [AdaptiveImage].
///
/// После [Supabase.initialize] и установки [supabaseAppReady] клиент гарантированно
/// доступен; до инициализации вызов вернёт пустую строку (чтобы не падать на splash).
class SupabaseImageService {
  SupabaseImageService._();

  /// Собирает публичный URL объекта в бакете. [filePath] — путь внутри бакета без
  /// ведущего «/» (лишний слэш обрезается).
  static String getPublicUrl(String bucketName, String filePath) {
    if (!supabaseAppReady) {
      return '';
    }
    final String path = filePath.startsWith('/')
        ? filePath.substring(1)
        : filePath;
    return Supabase.instance.client.storage.from(bucketName).getPublicUrl(path);
  }
}
