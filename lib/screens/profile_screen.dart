import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_constants.dart';
import '../config/admin_config.dart';
import '../config/supabase_ready.dart';
import '../services/city_data_service.dart';
import '../widgets/soft_tab_header.dart';
import '../widgets/weather_app_bar_action.dart';
import 'account_settings_screen.dart';
import 'ferry_admin_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _profileReload = 0;
  bool _scheduledMetadataSync = false;
  bool _uploadingAvatar = false;

  Future<void> _pickAndUploadAvatar() async {
    if (!supabaseAppReady || _uploadingAvatar) {
      return;
    }
    final ImagePicker p = ImagePicker();
    final XFile? f = await p.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 88,
    );
    if (f == null) {
      return;
    }
    setState(() => _uploadingAvatar = true);
    try {
      final String url = await CityDataService.uploadProfileAvatar(f);
      await CityDataService.setMyAvatarUrl(url);
      if (mounted) {
        setState(() {
          _profileReload++;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Фото профиля обновлено')));
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Не удалось загрузить: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
      }
    }
  }

  Future<void> _signOut() async {
    if (!supabaseAppReady) {
      return;
    }
    await Supabase.instance.client.auth.signOut();
  }

  static String _fullNameFromSources(Map<String, dynamic>? row, User user) {
    final String fn = (row?['first_name'] as String?)?.trim() ?? '';
    final String ln = (row?['last_name'] as String?)?.trim() ?? '';
    final String fromRow = <String>[
      fn,
      ln,
    ].where((String e) => e.isNotEmpty).join(' ').trim();
    if (fromRow.isNotEmpty) {
      return fromRow;
    }
    final String mfn =
        (user.userMetadata?['first_name'] as String?)?.trim() ?? '';
    final String mln =
        (user.userMetadata?['last_name'] as String?)?.trim() ?? '';
    final String fromMeta = <String>[
      mfn,
      mln,
    ].where((String e) => e.isNotEmpty).join(' ').trim();
    if (fromMeta.isNotEmpty) {
      return fromMeta;
    }
    return '—';
  }

  static String _birthDisplayText(String? iso) {
    if (iso == null || iso.isEmpty) {
      return '—';
    }
    final String s = iso.length >= 10 ? iso.substring(0, 10) : iso;
    final List<String> p = s.split('-');
    if (p.length == 3) {
      return '${p[2]}.${p[1]}.${p[0]}';
    }
    return '—';
  }

  Future<void> _copyToClipboard(String label, String text) async {
    if (text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$label скопирован в буфер')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!supabaseAppReady) {
      return const Scaffold(body: Center(child: Text('Supabase не настроен')));
    }
    final User? user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Нет сессии')));
    }
    final String email = user.email ?? '—';
    final bool isEmailAdmin = CityDataService.isCurrentUserAdminSync();

    return FutureBuilder<Map<String, dynamic>?>(
      key: ValueKey<String>('${user.id}_$_profileReload'),
      future: CityDataService.fetchProfileRow(user.id),
      builder: (BuildContext c, AsyncSnapshot<Map<String, dynamic>?> snap) {
        if (snap.connectionState == ConnectionState.done &&
            !_scheduledMetadataSync) {
          _scheduledMetadataSync = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final bool upd = await CityDataService.syncProfileFromAuthMetadata(
              user,
            );
            if (upd && mounted) {
              setState(() => _profileReload++);
            }
          });
        }
        final Map<String, dynamic>? row = snap.data;
        final String fullName = _fullNameFromSources(row, user);
        final String? rawUser = row?['username'] as String?;
        final String nickForDisplay =
            (rawUser == null || rawUser.trim().isEmpty)
            ? ''
            : (rawUser.startsWith('@') ? rawUser.substring(1) : rawUser).trim();
        final String phoneRaw = (row?['phone_e164'] as String?)?.trim() ?? '';
        final String phoneDisplay = phoneRaw.isEmpty
            ? ''
            : (phoneRaw.startsWith('+') ? phoneRaw : '+$phoneRaw');

        final String? avatarUrl = (row?['avatar_url'] as String?)?.trim();
        final String nickLine = nickForDisplay.isEmpty
            ? '—'
            : '@$nickForDisplay';
        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F7),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SoftTabHeader(
                title: 'Аккаунт',
                trailing: SoftHeaderWeatherWithAction(
                  action: IconButton(
                    icon: Icon(
                      Icons.settings_outlined,
                      color: kSoftHeaderActionIconColor,
                      size: 26,
                    ),
                    onPressed: () async {
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (BuildContext c) =>
                              const AccountSettingsScreen(),
                        ),
                      );
                      if (mounted) {
                        setState(() => _profileReload++);
                      }
                    },
                    tooltip: 'Настройки',
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    kScreenHorizontalPadding,
                    8,
                    kScreenHorizontalPadding,
                    32,
                  ),
                  children: <Widget>[
              const SizedBox(height: 4),
              Center(
                child: GestureDetector(
                  onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      CircleAvatar(
                        radius: 52,
                        backgroundColor: kPrimaryBlue,
                        backgroundImage:
                            avatarUrl != null && avatarUrl.isNotEmpty
                            ? NetworkImage(avatarUrl)
                            : null,
                        child: avatarUrl == null || avatarUrl.isEmpty
                            ? const Icon(
                                Icons.person,
                                size: 56,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      if (_uploadingAvatar)
                        const Positioned.fill(
                          child: ColoredBox(
                            color: Color(0x66000000),
                            child: Center(
                              child: SizedBox(
                                width: 32,
                                height: 32,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Material(
                          color: kPrimaryBlue,
                          shape: const CircleBorder(),
                          elevation: 2,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _uploadingAvatar
                                ? null
                                : _pickAndUploadAvatar,
                            child: const Padding(
                              padding: EdgeInsets.all(7),
                              child: Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
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
                    color: kAppTextPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (snap.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      borderRadius: BorderRadius.all(Radius.circular(2)),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                'Информация о вас',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: kPrimaryBlue.withValues(alpha: 0.95),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: kAppCardSurface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text(
                      'Данные',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 17,
                        color: kAppTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Видны вам; ник — всем в чатах',
                      style: TextStyle(
                        fontSize: 13,
                        color: kAppTextSecondary,
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
                          color: kAppTextPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _LabeledField(
                      label: 'Имя и фамилия',
                      child: Text(
                        fullName == '—'
                            ? 'Укажите в профиле или при регистрации'
                            : fullName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: fullName == '—'
                              ? kAppTextSecondary
                              : kAppTextPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _LabeledField(
                      label: 'Дата рождения',
                      child: Text(
                        _birthDisplayText(row?['birth_date']?.toString()),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: kAppTextPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _LabeledField(
                      label: 'Ник в чате',
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              nickLine,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: kAppTextPrimary,
                              ),
                            ),
                          ),
                          if (nickForDisplay.isNotEmpty)
                            IconButton(
                              tooltip: 'Скопировать',
                              onPressed: () =>
                                  _copyToClipboard('Ник', '@$nickForDisplay'),
                              icon: const Icon(
                                Icons.copy_outlined,
                                size: 22,
                                color: kPrimaryBlue,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Латиница, цифры и _; 3–32 символа. Виден всем в чатах.',
                      style: TextStyle(
                        fontSize: 12,
                        color: kAppTextSecondary.withValues(alpha: 0.9),
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _LabeledField(
                      label: 'Телефон',
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              phoneDisplay.isEmpty ? 'не указан' : phoneDisplay,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: phoneDisplay.isEmpty
                                    ? kAppTextSecondary
                                    : kAppTextPrimary,
                              ),
                            ),
                          ),
                          if (phoneDisplay.isNotEmpty)
                            IconButton(
                              tooltip: 'Скопировать',
                              onPressed: () =>
                                  _copyToClipboard('Номер', phoneDisplay),
                              icon: const Icon(
                                Icons.copy_outlined,
                                size: 22,
                                color: kPrimaryBlue,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Виден только вам. В списке чатов и у других не показывается.',
                      style: TextStyle(
                        fontSize: 12,
                        color: kAppTextSecondary.withValues(alpha: 0.9),
                        height: 1.2,
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
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

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
            color: kAppTextSecondary,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
