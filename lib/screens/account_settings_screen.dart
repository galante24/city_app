import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_constants.dart';
import '../config/supabase_ready.dart';
import '../services/app_session_cleanup.dart';
import '../services/app_theme_controller.dart';
import '../services/city_data_service.dart';
import '../widgets/clean_screen_header.dart';
import '../widgets/profile_edit_fields.dart';
import '../widgets/settings_tablet_card.dart';
import '../widgets/soft_tab_header.dart';
import '../widgets/weather_app_bar_action.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  int _profileReload = 0;

  Future<void> _signOut() async {
    await AppSessionCleanup.signOutEverywhere();
  }

  Widget _notificationTablet({
    required Map<String, dynamic>? row,
    required ColorScheme cs,
    required AsyncSnapshot<Map<String, dynamic>?> snap,
  }) {
    final bool waiting = snap.connectionState == ConnectionState.waiting;
    final bool chat = row?['notify_chat_messages'] != false;
    final bool feed = row?['notify_feed_engagement'] != false;
    final bool news = row?['notify_news_feed'] != false;

    Future<void> save(bool c1, bool c2, bool c3) async {
      try {
        await CityDataService.updateMyNotificationChannels(
          chat: c1,
          feed: c2,
          news: c3,
        );
        if (mounted) {
          setState(() => _profileReload++);
        }
      } on Object catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Не сохранено: $e')));
        }
      }
    }

    return SettingsTabletCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Уведомления',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Сохраняется в профиле и на устройстве.',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurfaceVariant,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: chat,
            onChanged: waiting
                ? null
                : (bool v) => unawaited(save(v, feed, news)),
            title: Text(
              'Чаты',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurface),
            ),
            subtitle: Text(
              'Сообщения в чатах',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: feed,
            onChanged: waiting
                ? null
                : (bool v) => unawaited(save(chat, v, news)),
            title: Text(
              'Лайки',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurface),
            ),
            subtitle: Text(
              'Лайки и комментарии в ленте',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: news,
            onChanged: waiting
                ? null
                : (bool v) => unawaited(save(chat, feed, v)),
            title: Text(
              'Новости',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurface),
            ),
            subtitle: Text(
              'СМИ, важное и посты подписанных заведений',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ),
        ],
      ),
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
      padding: EdgeInsets.fromLTRB(
        kScreenHorizontalPadding,
        4,
        kScreenHorizontalPadding,
        24 + MediaQuery.paddingOf(context).bottom,
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
        SettingsTabletCard(
          child: ListenableBuilder(
            listenable: appThemeController,
            builder: (BuildContext context, Widget? _) {
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: appThemeController.useDarkTheme,
                onChanged: (bool v) {
                  unawaited(appThemeController.setDarkTheme(v));
                },
                title: Text(
                  'Тёмная тема',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurface),
                ),
                subtitle: Text(
                  'Оформление приложения (сохраняется на устройстве)',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              );
            },
          ),
        ),
        _notificationTablet(row: row, cs: cs, snap: snap),
        const SizedBox(height: 8),
        Text(
          'Изменение данных',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: primaryText,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Дата рождения, ник, текст о себе и номер телефона',
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
          style: TextStyle(fontSize: 13, color: secondaryText, height: 1.2),
        ),
        const SizedBox(height: 12),
        SettingsTabletCard(
          child: ProfileBirthDate(
            key: ValueKey<String>(
              'bd_${row?['birth_date']?.toString() ?? ''}_${user.id}_$_profileReload',
            ),
            initialIso: row?['birth_date']?.toString(),
            onSaved: () {
              if (mounted) setState(() => _profileReload++);
            },
          ),
        ),
        SettingsTabletCard(
          child: NickBlock(
            username: nickForDisplay,
            userId: user.id,
            profileReload: _profileReload,
            initialForEdit: row?['username'] as String?,
            onSaved: () {
              if (mounted) setState(() => _profileReload++);
            },
          ),
        ),
        SettingsTabletCard(
          child: AboutBlock(
            key: ValueKey<String>(
              'about_${row?['about']?.toString() ?? ''}_${user.id}_$_profileReload',
            ),
            initialAbout: row?['about'] as String?,
            onSaved: () {
              if (mounted) setState(() => _profileReload++);
            },
          ),
        ),
        SettingsTabletCard(
          child: PhoneBlock(
            phoneDisplay: phoneDisplay,
            userId: user.id,
            profileReload: _profileReload,
            initialForEdit: row?['phone_e164'] as String?,
            onSaved: () {
              if (mounted) setState(() => _profileReload++);
            },
          ),
        ),
        const SizedBox(height: 24),
        Divider(
          height: 1,
          thickness: 1,
          color: cs.outline.withValues(alpha: 0.25),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => unawaited(_signOut()),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFB71C1C),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
          ),
          icon: const Icon(Icons.logout),
          label: const Text('Выйти'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!supabaseAppReady) {
      return Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            CleanFloatingHeader(
              leading: const SoftHeaderBackButton(),
              title: 'Настройки',
              trailing: const SoftHeaderWeatherWithAction(),
            ),
            const Expanded(child: Center(child: Text('Supabase не настроен'))),
          ],
        ),
      );
    }
    final User? user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            CleanFloatingHeader(
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
          resizeToAvoidBottomInset: true,
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              CleanFloatingHeader(
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
