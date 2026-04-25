import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
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
  int _profileReload = 0;
  bool _scheduledMetadataSync = false;

  Future<void> _signOut() async {
    if (!supabaseAppReady) {
      return;
    }
    await Supabase.instance.client.auth.signOut();
  }

  static String _fullNameFromSources(
    Map<String, dynamic>? row,
    User user,
  ) {
    final String fn = (row?['first_name'] as String?)?.trim() ?? '';
    final String ln = (row?['last_name'] as String?)?.trim() ?? '';
    final String fromRow = <String>[fn, ln].where((String e) => e.isNotEmpty).join(' ').trim();
    if (fromRow.isNotEmpty) {
      return fromRow;
    }
    final String mfn = (user.userMetadata?['first_name'] as String?)?.trim() ?? '';
    final String mln = (user.userMetadata?['last_name'] as String?)?.trim() ?? '';
    final String fromMeta = <String>[mfn, mln].where((String e) => e.isNotEmpty).join(' ').trim();
    if (fromMeta.isNotEmpty) {
      return fromMeta;
    }
    return '—';
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
      key: ValueKey<String>('${user.id}_$_profileReload'),
      future: CityDataService.fetchProfileRow(user.id),
      builder: (BuildContext c, AsyncSnapshot<Map<String, dynamic>?> snap) {
        if (snap.connectionState == ConnectionState.done && !_scheduledMetadataSync) {
          _scheduledMetadataSync = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final bool upd = await CityDataService.syncProfileFromAuthMetadata(user);
            if (upd && mounted) {
              setState(() => _profileReload++);
            }
          });
        }
        final Map<String, dynamic>? row = snap.data;
        final String fullName = _fullNameFromSources(row, user);
        final String? rawUser = row?['username'] as String?;
        final String nickForDisplay = (rawUser == null || rawUser.trim().isEmpty)
            ? ''
            : (rawUser.startsWith('@') ? rawUser.substring(1) : rawUser).trim();
        final String phoneRaw = (row?['phone_e164'] as String?)?.trim() ?? '';
        final String phoneDisplay = phoneRaw.isEmpty
            ? ''
            : (phoneRaw.startsWith('+') ? phoneRaw : '+$phoneRaw');

        return Scaffold(
          backgroundColor: const Color(0xFFF2F2F7),
          appBar: AppBar(
            title: const Text('Профиль'),
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            foregroundColor: const Color(0xFF1A1A1A),
            centerTitle: true,
            titleTextStyle: const TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: <Widget>[
              const SizedBox(height: 8),
              const Center(
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: kPrimaryBlue,
                  child: Icon(Icons.person, size: 56, color: Colors.white),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  fullName == '—' ? 'Пользователь' : fullName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (snap.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: LinearProgressIndicator(minHeight: 2, borderRadius: BorderRadius.all(Radius.circular(2))),
                  ),
                ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text(
                      'Данные',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 17,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Видны вам; ник — всем в чатах',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _LabeledField(
                      label: 'Email',
                      child: Text(
                        email,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _LabeledField(
                      label: 'Имя и фамилия',
                      child: Text(
                        fullName == '—' ? 'Укажите в профиле или при регистрации' : fullName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: fullName == '—' ? const Color(0xFF8E8E93) : const Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _LabeledField(
                      label: 'Дата рождения',
                      child: _ProfileBirthDate(
                        key: ValueKey<String>(
                          'bd_${row?['birth_date']?.toString() ?? ''}_$user.id$_profileReload',
                        ),
                        initialIso: row?['birth_date']?.toString(),
                        onSaved: () {
                          setState(() => _profileReload++);
                        },
                      ),
                    ),
                    if (isEmailAdmin) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        'Админ: $kAdministratorEmail',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF2E7D32),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Divider(height: 28),
                    _NickBlock(
                      username: nickForDisplay,
                      userId: user.id,
                      profileReload: _profileReload,
                      initialForEdit: row?['username'] as String?,
                      onSaved: () => setState(() => _profileReload++),
                    ),
                    const SizedBox(height: 16),
                    _PhoneBlock(
                      phoneDisplay: phoneDisplay,
                      userId: user.id,
                      profileReload: _profileReload,
                      initialForEdit: row?['phone_e164'] as String?,
                      onSaved: () => setState(() => _profileReload++),
                    ),
                  ],
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

class _NickBlock extends StatelessWidget {
  const _NickBlock({
    required this.username,
    required this.userId,
    required this.profileReload,
    required this.initialForEdit,
    required this.onSaved,
  });

  final String username;
  final String userId;
  final int profileReload;
  final String? initialForEdit;
  final VoidCallback onSaved;

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Скопировано в буфер')),
      );
    }
  }

  Future<void> _share(String text) async {
    await Share.share(
      'Мой ник в чате: $text',
      subject: 'Ник',
    );
  }

  @override
  Widget build(BuildContext context) {
    final String at = username.isEmpty ? '—' : '@$username';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Ник в чате',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6C6C70),
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Латиница, цифры и _; 3–32 символа. Виден всем в чатах.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Flexible(
                    child: SelectableText(
                      at,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Скопировать',
                    onPressed: username.isEmpty
                        ? null
                        : () => _copy(context, '@$username'),
                    icon: const Icon(Icons.copy_outlined, size: 22, color: kPrimaryBlue),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    tooltip: 'Поделиться',
                    onPressed: username.isEmpty
                        ? null
                        : () => _share('@$username'),
                    icon: const Icon(Icons.share_outlined, size: 22, color: kPrimaryBlue),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Изменить ник',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 6),
        _ProfileUsername(
          key: ValueKey<String>(
            '${initialForEdit ?? ''}_${userId}_$profileReload',
          ),
          initial: initialForEdit,
          onSaved: onSaved,
        ),
      ],
    );
  }
}

class _PhoneBlock extends StatelessWidget {
  const _PhoneBlock({
    required this.phoneDisplay,
    required this.userId,
    required this.profileReload,
    required this.initialForEdit,
    required this.onSaved,
  });

  final String phoneDisplay;
  final String userId;
  final int profileReload;
  final String? initialForEdit;
  final VoidCallback onSaved;

  Future<void> _copy(BuildContext context, String text) async {
    if (text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Номер скопирован')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Телефон',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6C6C70),
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Виден только вам. В списке чатов и у других не показывается.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Flexible(
                    child: SelectableText(
                      phoneDisplay.isEmpty ? 'не указан' : phoneDisplay,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: phoneDisplay.isEmpty ? const Color(0xFF8E8E93) : const Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Скопировать',
                    onPressed: phoneDisplay.isEmpty ? null : () => _copy(context, phoneDisplay),
                    icon: const Icon(Icons.copy_outlined, size: 22, color: kPrimaryBlue),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Изменить номер',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 6),
        _ProfilePhoneE164(
          key: ValueKey<String>(
            'ph_${initialForEdit ?? ''}_$userId$profileReload',
          ),
          initial: initialForEdit,
          onSaved: onSaved,
        ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6C6C70),
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _ProfileUsername extends StatefulWidget {
  const _ProfileUsername({super.key, this.initial, required this.onSaved});

  final String? initial;
  final VoidCallback onSaved;

  @override
  State<_ProfileUsername> createState() => _ProfileUsernameState();
}

class _ProfileUsernameState extends State<_ProfileUsername> {
  late TextEditingController _c;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(
      text: widget.initial == null || widget.initial!.isEmpty
          ? ''
          : (widget.initial!.startsWith('@') ? widget.initial! : '@${widget.initial!}'),
    );
  }

  @override
  void didUpdateWidget(covariant _ProfileUsername oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initial != oldWidget.initial) {
      final String want = widget.initial == null || widget.initial!.isEmpty
          ? ''
          : (widget.initial!.startsWith('@') ? widget.initial! : '@${widget.initial!}');
      if (want != _c.text) {
        _c.text = want;
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String _normalizedInput() {
    String s = _c.text.trim();
    if (s.startsWith('@')) {
      s = s.substring(1);
    }
    return s;
  }

  Future<void> _save() async {
    final String s = _normalizedInput();
    if (s.isEmpty) {
      setState(() => _saving = true);
      try {
        await ChatService.setMyUsername(null);
        if (mounted) {
          widget.onSaved();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ник сброшен')),
          );
        }
      } on PostgrestException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message.isNotEmpty ? e.message : 'Ошибка сохранения ника')),
          );
        }
      } on Object {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось сохранить ник. Проверьте сеть и SQL-миграции.')),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _saving = false);
        }
      }
      return;
    }
    if (!RegExp(r'^[a-z0-9_]{3,32}$').hasMatch(s)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ник: 3–32 символа, латиница, цифры, подчёркивание _'),
          ),
        );
      }
      return;
    }
    setState(() => _saving = true);
    try {
      await ChatService.setMyUsername(s);
      if (mounted) {
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ник сохранён')),
        );
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        final String m = e.message;
        final bool taken = m.toLowerCase().contains('taken') || m.toLowerCase().contains('username');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              m.isNotEmpty
                  ? (taken ? 'Ник занят, выберите другой' : m)
                  : 'Ошибка сохранения',
            ),
          ),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить ник')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  InputDecoration _deco(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF2F2F7),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E5EA), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kPrimaryBlue, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _c,
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            keyboardType: TextInputType.text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            decoration: _deco('@nickname'),
            onSubmitted: (_) => _save(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Сохранить'),
        ),
      ],
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
  late TextEditingController _c;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initial ?? '');
  }

  @override
  void didUpdateWidget(covariant _ProfilePhoneE164 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initial != oldWidget.initial) {
      _c.text = widget.initial ?? '';
    }
  }

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
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.message.isNotEmpty
                  ? e.message
                  : 'Не удалось сохранить телефон. Выполните миграцию 009 (RLS) в Supabase.',
            ),
          ),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось сохранить. Проверьте сеть и права RLS (миграция 009).'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  InputDecoration _deco() {
    return InputDecoration(
      hintText: '+79991234567',
      filled: true,
      fillColor: const Color(0xFFF2F2F7),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E5EA), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kPrimaryBlue, width: 1.4),
      ),
    );
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
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            decoration: _deco(),
            onSubmitted: (_) => _save(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}

class _ProfileBirthDate extends StatefulWidget {
  const _ProfileBirthDate({super.key, this.initialIso, required this.onSaved});

  final String? initialIso;
  final VoidCallback onSaved;

  @override
  State<_ProfileBirthDate> createState() => _ProfileBirthDateState();
}

class _ProfileBirthDateState extends State<_ProfileBirthDate> {
  DateTime? _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _date = _parseInitial(widget.initialIso);
  }

  @override
  void didUpdateWidget(covariant _ProfileBirthDate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialIso != oldWidget.initialIso) {
      _date = _parseInitial(widget.initialIso);
    }
  }

  static DateTime? _parseInitial(String? iso) {
    if (iso == null || iso.isEmpty) {
      return null;
    }
    final String s = iso.length >= 10 ? iso.substring(0, 10) : iso;
    try {
      final List<String> p = s.split('-');
      if (p.length == 3) {
        return DateTime(
          int.parse(p[0]),
          int.parse(p[1]),
          int.parse(p[2]),
        );
      }
    } on Object {
      return null;
    }
    return null;
  }

  String _label() {
    if (_date == null) {
      return 'Не выбрана';
    }
    return '${_date!.day.toString().padLeft(2, '0')}.'
        '${_date!.month.toString().padLeft(2, '0')}.'
        '${_date!.year}';
  }

  Future<void> _pick() async {
    final DateTime now = DateTime.now();
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime(now.year - 20, 1, 1),
      firstDate: DateTime(1920, 1, 1),
      lastDate: now,
    );
    if (d != null) {
      setState(() => _date = d);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await CityDataService.setMyBirthDate(_date);
      if (mounted) {
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Дата рождения сохранена')),
        );
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.message.isNotEmpty
                  ? e.message
                  : 'Нет столбца birth_date — выполните миграцию 009 в Supabase.',
            ),
          ),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить дату')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _clear() async {
    setState(() => _date = null);
    setState(() => _saving = true);
    try {
      await CityDataService.setMyBirthDate(null);
      if (mounted) {
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Дата сброшена')),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сбросить')),
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Material(
            color: const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _saving ? null : _pick,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.calendar_today_outlined, size: 20, color: Color(0xFF6C6C70)),
                    const SizedBox(width: 10),
                    Text(
                      _label(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        if (_date != null)
          IconButton(
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            ),
            onPressed: _saving ? null : _clear,
            icon: const Icon(Icons.clear, size: 20),
            tooltip: 'Сбросить',
          ),
        const SizedBox(width: 2),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}
