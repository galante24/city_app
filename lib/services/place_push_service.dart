import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_ready.dart';

/// Вызов Edge Function рассылки push подписчикам заведения (FCM на стороне сервера).
class PlacePushService {
  PlacePushService._();

  static Future<void> notifySubscribersIfNeeded(String postId) async {
    if (!supabaseAppReady) {
      return;
    }
    try {
      await Supabase.instance.client.functions.invoke(
        'notify-place-post',
        body: <String, dynamic>{'post_id': postId},
      );
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('[PlacePushService] notify-place-post: $e');
      }
    }
  }
}
