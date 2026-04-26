import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_constants.dart';
import '../config/supabase_ready.dart';
import '../services/city_data_service.dart';
import '../services/notification_prefs.dart';
import '../widgets/profile_edit_fields.dart';

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

  @override
  Widget build(BuildContext context) {
    if (!supabaseAppReady) {
      return const Scaffold(body: Center(child: Text('Supabase не настроен')));
    }
    final User? user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Нет сессии')));
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
          backgroundColor: kAppScaffoldBg,
          appBar: AppBar(
            title: const Text('Настройки'),
            backgroundColor: kPrimaryBlue,
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            centerTitle: true,
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(
              kScreenHorizontalPadding,
              12,
              kScreenHorizontalPadding,
              32,
            ),
            children: <Widget>[
              if (snap.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    borderRadius: BorderRadius.all(Radius.circular(2)),
                  ),
                ),
              SwitchListTile(
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
                activeThumbColor: kPrimaryBlue,
              ),
              const SizedBox(height: 12),
              const Text(
                'Изменение данных',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: kAppTextPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Дата рождения, ник в чате и номер телефона',
                style: TextStyle(
                  fontSize: 13,
                  color: kAppTextSecondary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 16),
              ProfileBirthDate(
                key: ValueKey<String>(
                  'bd_${row?['birth_date']?.toString() ?? ''}_$user.id$_profileReload',
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
          ),
        );
      },
    );
  }
}
