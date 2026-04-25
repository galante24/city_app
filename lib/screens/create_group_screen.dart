import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../app_constants.dart';
import '../config/supabase_ready.dart';
import '../models/conversation_list_item.dart';
import '../services/chat_service.dart';
import 'user_chat_thread_screen.dart';

/// Создание группы: название, открытая (все участники приглашают) / закрытая (только модерации).
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _name = TextEditingController();
  bool _isOpen = true;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _showErr(String text) {
    final String t = text.length > 220 ? '${text.substring(0, 220)}…' : text;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t)),
    );
  }

  Future<void> _create() async {
    if (!supabaseAppReady) {
      return;
    }
    final String t = _name.text.trim();
    if (t.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Введите название')),
        );
      }
      return;
    }
    setState(() => _loading = true);
    try {
      final String id = await ChatService.createGroupConversation(
        title: t,
        isOpen: _isOpen,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext c) => UserChatThreadScreen(
            conversationId: id,
            title: t,
            listItem: ConversationListItem(
              id: id,
              title: t,
              subtitle: '',
              timeText: '',
              sortKeyMs: 0,
              isGroup: true,
              isOpen: _isOpen,
              myRole: 'owner',
              groupName: t,
            ),
          ),
        ),
      );
    } on PostgrestException catch (e) {
      if (mounted) {
        _showErr(
          e.message.isNotEmpty
              ? e.message
              : (e.details != null && e.details.toString().trim().isNotEmpty
                  ? e.details.toString()
                  : (e.hint != null && e.hint!.trim().isNotEmpty
                      ? e.hint!
                      : 'Ошибка сервера при создании группы')),
        );
      }
    } on StateError catch (e) {
      if (mounted) {
        _showErr(e.message);
      }
    } on Object catch (e) {
      if (mounted) {
        _showErr('Не удалось создать: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новая группа'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          const Text('Название'),
          const SizedBox(height: 6),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Напр. «Соседи»',
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 20),
          const Text('Тип'),
          const SizedBox(height: 6),
          SwitchListTile(
            value: _isOpen,
            onChanged: (bool v) {
              setState(() => _isOpen = v);
            },
            title: Text(_isOpen ? 'Открытая' : 'Закрытая'),
            subtitle: Text(
              _isOpen
                  ? 'Любой участник может добавлять из контактов и по поиску'
                  : 'Добавлять только владелец и модераторы',
            ),
            activeThumbColor: kPrimaryBlue,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _create,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Создать'),
          ),
        ],
      ),
    );
  }
}
