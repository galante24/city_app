import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_ready.dart';

/// Пуши при упоминании в комментарии к задаче ([notify-task-mention]).
class TaskPushService {
  TaskPushService._();

  static Future<void> notifyMentionsIfNeeded({
    required String taskId,
    required String taskTitle,
    required List<String> mentionedUserIds,
  }) async {
    if (!supabaseAppReady || mentionedUserIds.isEmpty) {
      return;
    }
    try {
      await Supabase.instance.client.functions.invoke(
        'notify-task-mention',
        body: <String, dynamic>{
          'task_id': taskId,
          'task_title': taskTitle,
          'mentioned_user_ids': mentionedUserIds,
        },
      );
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('[TaskPushService] notify-task-mention: $e');
      }
    }
  }
}
