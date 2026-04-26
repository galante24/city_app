import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_constants.dart';
import '../config/supabase_ready.dart';
import '../services/app_theme_controller.dart';
import '../services/city_data_service.dart';
import '../services/notification_prefs.dart';
import '../widgets/profile_edit_fields.dart';
import '../widgets/soft_tab_header.dart';
import '../widgets/weather_app_bar_action.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  int _profileReload = 0;
  bool? _notifOff;

  @override
  void initState() {
    super.initState();
    unawaited(
      NotificationPrefs.areGloballyDisabled().then((bool v) {
        if (mounted) {
          setState(() => _notifOff = v);
        }
      }),
    );
  }

  Widget _settingsBody({
    required Map<String, dynamic>? row,
    required User user,
    required String nickForDisplay,
    required String phoneDisplay,
    required AsyncSnapshot<Map<String, dynamic>?> snap,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final Color primaryText = cs.onSurface;
    final Color secondaryText = cs.onSurface.withValues(alpha: 0.65);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        kScreenHorizontalPadding,
        8,
        kScreenHorizontalPadding,
        32,
      ),
      children: <Widget>[
        if (snap.connectionState == ConnectionState.waiting)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(
              minHeight: 2,
              borderRadius: const BorderRadius.all(Radius.circular(2)),
              color: cs.primary,
            ),
          ),
        ListenableBuilder(
          listenable: appThemeController,
          builder: (BuildContext context, Widget? _) {
            return SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: appThemeController.useDarkTheme,
              onChanged: (bool v) {
                unawaited(appThemeController.setDarkTheme(v));
              },
              title: const Text('Тёмная тема'),
              subtitle: const Text(
                'Оформление приложения в тёмных тонах (сохраняется на устройстве)',
              ),
              activeThumbColor: cs.primary,
            );
          },
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _notifOff == true,
          onChanged: _notifOff == null
              ? null
              : (bool v) async {
                  final bool off = v;
                  await NotificationPrefs.setGloballyDisabled(off);
                  if (mounted) {
                    setState(() {
                      _notifOff = off;
                    });
                  }
                },
          title: const Text('Отключить уведомления'),
          subtitle: const Text(
            'Не показывать в шторке уведомления о новых сообщениях (на этом устройстве)',
          ),
          activeThumbColor: cs.primary,
        ),
        const SizedBox(height: 20),
        Text(
          'Изменение данных',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: primaryText,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Дата рождения, ник в чате и номер телефона',
          style: TextStyle(
            fontSize: 13,
            color: secondaryText,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        ProfileBirthDate(
          key: ValueKey<String>(
            'bd_${row?['birth_date']?.toString() ?? ''}_${user.id}_$_profileReload',
          ),
          initialIso: row?['birth_date']?.toString(),
          onSaved: () => setState(() => _profileReload++),
        ),
        const SizedBox(height: 20),
        NickBlock(
          username: nickForDisplay,
          userId: user.id,
          profileReload: _profileReload,
          initialForEdit: row?['username'] as String?,
          onSaved: () => setState(() => _profileReload++),
        ),
        const SizedBox(height: 20),
        PhoneBlock(
          phoneDisplay: phoneDisplay,
          userId: user.id,
          profileReload: _profileReload,
          initialForEdit: row?['phone_e164'] as String?,
          onSaved: () => setState(() => _profileReload++),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!supabaseAppReady) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SoftTabHeader(
              leading: const SoftHeaderBackButton(),
              title: 'Настройки',
              trailing: const SoftHeaderWeatherWithAction(),
            ),
            const Expanded(
              child: Center(child: Text('Supabase не настроен')),
            ),
          ],
        ),
      );
    }
    final User? user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SoftTabHeader(
              leading: const SoftHeaderBackButton(),
              title: 'Настройки',
              trailing: const SoftHeaderWeatherWithAction(),
            ),
            const Expanded(child: Center(child: Text('Нет сессии'))),
          ],
        ),
      );
    }
    return FutureBuilder<Map<String, dynamic>?>(
      key: ValueKey<String>('st_${user.id}_$_profileReload'),
      future: CityDataService.fetchProfileRow(user.id),
      builder: (BuildContext c, AsyncSnapshot<Map<String, dynamic>?> snap) {
        final Map<String, dynamic>? row = snap.data;
        final String? rawUser = row?['username'] as String?;
        final String nickForDisplay =
            (rawUser == null || rawUser.trim().isEmpty)
            ? ''
            : (rawUser.startsWith('@') ? rawUser.substring(1) : rawUser).trim();
        final String phoneRaw = (row?['phone_e164'] as String?)?.trim() ?? '';
        final String phoneDisplay = phoneRaw.isEmpty
            ? ''
            : (phoneRaw.startsWith('+') ? phoneRaw : '+$phoneRaw');
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SoftTabHeader(
                leading: const SoftHeaderBackButton(),
                title: 'Настройки',
                trailing: const SoftHeaderWeatherWithAction(),
              ),
              Expanded(
                child: _settingsBody(
                  row: row,
                  user: user,
                  nickForDisplay: nickForDisplay,
                  phoneDisplay: phoneDisplay,
                  snap: snap,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
