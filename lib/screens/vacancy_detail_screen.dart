import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_constants.dart';
import '../services/chat_service.dart';
import '../services/city_data_service.dart';
import '../services/job_vacancy_service.dart';
import 'user_chat_thread_screen.dart';

class VacancyDetailScreen extends StatefulWidget {
  const VacancyDetailScreen({
    super.key,
    required this.row,
    required this.accent,
  });

  final Map<String, dynamic> row;
  final Color accent;

  @override
  State<VacancyDetailScreen> createState() => _VacancyDetailScreenState();
}

class _VacancyDetailScreenState extends State<VacancyDetailScreen> {
  bool _busy = false;
  bool? _canDelete;

  String get _id => widget.row['id']?.toString() ?? '';
  String get _authorId => widget.row['author_id']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_resolveCanDelete());
  }

  Future<void> _resolveCanDelete() async {
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) {
      if (mounted) {
        setState(() => _canDelete = false);
      }
      return;
    }
    if (_authorId == me) {
      if (mounted) {
        setState(() => _canDelete = true);
      }
      return;
    }
    if (CityDataService.isCurrentUserAdminSync()) {
      if (mounted) {
        setState(() => _canDelete = true);
      }
      return;
    }
    final Map<String, dynamic>? p = await CityDataService.fetchProfileRow(me);
    final bool admin = p?['is_admin'] == true;
    if (mounted) {
      setState(() => _canDelete = admin);
    }
  }

  Future<void> _openChat() async {
    if (_authorId.isEmpty) {
      return;
    }
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) {
      return;
    }
    if (_authorId == me) {
      return;
    }
    setState(() => _busy = true);
    try {
      final String conv = await ChatService.getOrCreateDirectConversation(_authorId);
      final String name = (await ChatService.displayNameForUserId(_authorId)) ?? 'Чат';
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext c) => UserChatThreadScreen(
            conversationId: conv,
            title: name,
            listItem: null,
          ),
        ),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть чат')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _call(String phone) async {
    final Uri? uri = _telUri(phone);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть звонок')),
        );
      }
    }
  }

  static Uri? _telUri(String raw) {
    final String d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) {
      return null;
    }
    final String e164;
    if (d.length == 11 && d.startsWith('7')) {
      e164 = '+$d';
    } else if (d.length == 10) {
      e164 = '+7$d';
    } else {
      return Uri.tryParse('tel:${raw.trim()}');
    }
    return Uri.parse('tel:$e164');
  }

  Future<void> _delete() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) {
        return AlertDialog(
          title: const Text('Удалить вакансию?'),
          content: const Text('Запись будет удалена без восстановления.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );
    if (ok != true) {
      return;
    }
    setState(() => _busy = true);
    try {
      await JobVacancyService.deleteById(_id);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Вакансия удалена')),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String title = widget.row['title'] as String? ?? '';
    final String desc = widget.row['description'] as String? ?? '';
    final String salary = widget.row['salary'] as String? ?? '';
    final String addr = widget.row['work_address'] as String? ?? '';
    final String phone = widget.row['contact_phone'] as String? ?? '';
    final String? imageUrl = widget.row['image_url'] as String?;
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    final bool isOwner = me != null && me == _authorId;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white,
        title: const Text('Вакансия'),
        actions: <Widget>[
          if (_canDelete == true)
            IconButton(
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Удалить',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (imageUrl != null && imageUrl.isNotEmpty) ...<Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (BuildContext c, Object e, StackTrace? st) => Container(
                    color: widget.accent.withValues(alpha: 0.12),
                    child: Icon(Icons.work_outline, color: widget.accent, size: 48),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1C1C1E),
            ),
          ),
          if (salary.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Зарплата: $salary',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: widget.accent,
              ),
            ),
          ],
          if (addr.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.place_outlined, size: 22, color: Color(0xFF6C6C70)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    addr,
                    style: const TextStyle(fontSize: 16, color: Color(0xFF1C1C1E)),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            'Описание',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            desc,
            style: const TextStyle(
              fontSize: 15,
              height: 1.35,
              color: Color(0xFF3C3C3E),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Контакты',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _call(phone),
            child: Row(
              children: <Widget>[
                const Icon(Icons.phone, color: kPrimaryBlue, size: 22),
                const SizedBox(width: 8),
                Text(
                  phone,
                  style: const TextStyle(
                    fontSize: 18,
                    color: kPrimaryBlue,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: kPrimaryBlue,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (!isOwner && me != null) ...<Widget>[
            FilledButton(
              onPressed: _busy ? null : _openChat,
              style: FilledButton.styleFrom(
                backgroundColor: kPrimaryBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(right: 10),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.chat_bubble_outline, size: 22),
                    ),
                  const Text('Связаться'),
                ],
              ),
            ),
          ] else if (isOwner) ...<Widget>[
            const Text(
              'Это ваша вакансия',
              style: TextStyle(
                color: Color(0xFF6C6C70),
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
