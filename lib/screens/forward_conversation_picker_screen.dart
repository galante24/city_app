import 'package:flutter/material.dart';

import '../config/supabase_ready.dart';
import '../models/conversation_list_item.dart';
import '../widgets/conversation_pick_list.dart';

/// Выбор чата для пересылки сообщений (текущий чат из списка исключается).
class ForwardConversationPickerScreen extends StatelessWidget {
  const ForwardConversationPickerScreen({
    super.key,
    required this.excludeConversationId,
  });

  final String excludeConversationId;

  @override
  Widget build(BuildContext context) {
    if (!supabaseAppReady) {
      return Scaffold(
        appBar: AppBar(title: const Text('Переслать в…')),
        body: const Center(child: Text('Supabase не настроен')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Переслать в…'),
        surfaceTintColor: Colors.transparent,
      ),
      body: ConversationPickList(
        excludeConversationId: excludeConversationId,
        emptyMessage:
            'Нет других чатов. Создайте диалог или группу в списке чатов.',
        onPick: (ConversationListItem item) {
          Navigator.pop<ConversationListItem>(context, item);
        },
      ),
    );
  }
}
