import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_constants.dart';
import '../config/admin_config.dart';
import '../config/supabase_ready.dart';
import '../services/chat_service.dart';
import '../services/city_data_service.dart';
import '../utils/phone_normalize.dart';
import 'ferry_admin_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<void> _signOut() async {
    if (!supabaseAppReady) {
      return;
    }
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (!supabaseAppReady) {
      return const Scaffold(
        body: Center(child: Text('Supabase не настроен')),
      );
    }
    final User? user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Нет сессии')),
      );
    }
    final String email = user.email ?? '—';
    final bool isEmailAdmin = CityDataService.isCurrentUserAdminSync();

    return FutureBuilder<Map<String, dynamic>?>(
      key: ObjectKey(user.id),
      future: CityDataService.fetchProfileRow(user.id),
      builder: (BuildContext c, AsyncSnapshot<Map<String, dynamic>?> snap) {
        final Map<String, dynamic>? row = snap.data;
        final String fromProfile = (row?['first_name'] as String?)?.trim() ?? '';
        final String fromMeta = (user.userMetadata?['first_name'] as String?)?.trim() ?? '';
        final String displayName = fromProfile.isNotEmpty
            ? fromProfile
            : (fromMeta.isNotEmpty ? fromMeta : '—');

        return Scaffold(
          appBar: AppBar(
            title: const Text('Профиль'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              const Center(
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: kPrimaryBlue,
                  child: Icon(Icons.person, size: 56, color: Colors.white),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  displayName == '—' ? 'Пользователь' : displayName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (snap.connectionState == ConnectionState.waiting)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Text(
                        'Данные пользователя',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Email',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6C6C70),
                        ),
                      ),
                      Text(
                        email,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Имя (таблица profiles)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6C6C70),
                        ),
                      ),
                      Text(
                        fromProfile.isNotEmpty
                            ? fromProfile
                            : (snap.hasData
                                ? '— (добавьте first_name в Supabase / триггер)'
                                : '…'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (fromProfile.isEmpty && fromMeta.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          'Из регистрации: $fromMeta',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6C6C70),
                          ),
                        ),
                      ],
                      if (isEmailAdmin) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          'Админ: $kAdministratorEmail',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF2E7D32),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      const Text(
                        'Телефон в формате +7 (для чатов с контактов)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6C6C70),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _ProfilePhoneE164(
                        key: ValueKey(
                          (row?['phone_e164'] as String? ?? '_')
                              + user.id,
                        ),
                        initial: (row?['phone_e164'] as String?),
                        onSaved: () {
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _signOut,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB71C1C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.logout),
                label: const Text('Выйти'),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.directions_boat, color: kPrimaryBlue),
                title: const Text('Расписание парома (полный экран)'),
                onTap: () async {
                  if (!CityDataService.isCurrentUserAdminSync()) {
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Нужен вход админа: $kAdministratorEmail',
                        ),
                      ),
                    );
                    return;
                  }
                  final bool? saved = await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (BuildContext c) => const FerryAdminScreen(),
                    ),
                  );
                  if (saved == true && mounted) {
                    setState(() {});
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProfilePhoneE164 extends StatefulWidget {
  const _ProfilePhoneE164({super.key, this.initial, required this.onSaved});

  final String? initial;
  final VoidCallback onSaved;

  @override
  State<_ProfilePhoneE164> createState() => _ProfilePhoneE164State();
}

class _ProfilePhoneE164State extends State<_ProfilePhoneE164> {
  late final TextEditingController _c = TextEditingController(text: widget.initial ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String? n = normalizePhoneToE164Ru(_c.text);
    if (n == null && _c.text.trim().isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Введите номер, например +79991234567'),
          ),
        );
      }
      return;
    }
    setState(() => _saving = true);
    try {
      await ChatService.setMyPhoneE164(n);
      if (mounted) {
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Телефон сохранён')),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _c,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              hintText: '+79991234567',
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('OK'),
        ),
      ],
    );
  }
}
