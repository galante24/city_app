import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_card_styles.dart';
import '../app_constants.dart';
import '../services/chat_service.dart';
import '../services/city_data_service.dart';
import '../widgets/soft_tab_header.dart';
import '../widgets/weather_app_bar_action.dart';
import '../widgets/city_network_image.dart';
import 'user_chat_thread_screen.dart';

/// Публичный профиль: только просмотр и «Написать». Редактирование — в [ProfileScreen] (вкладка «Аккаунт»).
class PublicUserProfileScreen extends StatefulWidget {
  const PublicUserProfileScreen({
    super.key,
    required this.userId,
    this.fallbackTitle,
  });

  final String userId;
  final String? fallbackTitle;

  @override
  State<PublicUserProfileScreen> createState() =>
      _PublicUserProfileScreenState();
}

class _PublicUserProfileScreenState extends State<PublicUserProfileScreen> {
  Map<String, dynamic>? _row;
  bool _loading = true;
  bool _busyChat = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final Map<String, dynamic>? r = await CityDataService.fetchProfileRow(
      widget.userId,
    );
    if (mounted) {
      setState(() {
        _row = r;
        _loading = false;
      });
    }
  }

  String get _displayName {
    if (_row == null) {
      return widget.fallbackTitle?.trim().isNotEmpty == true
          ? widget.fallbackTitle!.trim()
          : 'Профиль';
    }
    final String fn = (_row!['first_name'] as String?)?.trim() ?? '';
    final String ln = (_row!['last_name'] as String?)?.trim() ?? '';
    final String full = '$fn $ln'.trim();
    if (full.isNotEmpty) {
      return full;
    }
    final String? u = (_row!['username'] as String?)?.trim();
    if (u != null && u.isNotEmpty) {
      return u.startsWith('@') ? u : '@$u';
    }
    return widget.fallbackTitle ?? 'Профиль';
  }

  String? get _usernameLine {
    final String? u = (_row?['username'] as String?)?.trim();
    if (u == null || u.isEmpty) {
      return null;
    }
    return u.startsWith('@') ? u : '@$u';
  }

  String? get _about {
    final String? a = (_row?['about'] as String?)?.trim();
    if (a == null || a.isEmpty) {
      return null;
    }
    return a;
  }

  String? get _avatarUrl {
    final String? u = (_row?['avatar_url'] as String?)?.trim();
    if (u == null || u.isEmpty) {
      return null;
    }
    return u;
  }

  Future<void> _openChat() async {
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null || me == widget.userId) {
      return;
    }
    setState(() => _busyChat = true);
    try {
      final String conv = await ChatService.getOrCreateDirectConversation(
        widget.userId,
      );
      final String name =
          (await ChatService.displayNameForUserId(widget.userId)) ??
          _displayName;
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext c) => UserChatThreadScreen(
            conversationId: conv,
            title: name,
            listItem: null,
            directPeerUserId: widget.userId,
          ),
        ),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Не удалось открыть чат')));
      }
    } finally {
      if (mounted) {
        setState(() => _busyChat = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    final bool canChat = me != null && me != widget.userId;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SoftTabHeader(
            leading: const SoftHeaderBackButton(),
            title: 'Профиль',
            trailing: const SoftHeaderWeatherWithAction(),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: <Widget>[
                      Container(
                        decoration: cloudCardDecoration(context, radius: 22),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: <Widget>[
                            CircleAvatar(
                              radius: 48,
                              backgroundColor: kPrimaryBlue.withValues(
                                alpha: 0.15,
                              ),
                              child:
                                  _avatarUrl != null && _avatarUrl!.isNotEmpty
                                  ? CityNetworkImage.avatar(
                                      context: context,
                                      imageUrl: _avatarUrl,
                                      diameter: 96,
                                      placeholderName: _displayName,
                                    )
                                  : Text(
                                      _displayName.isNotEmpty
                                          ? _displayName[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        fontSize: 36,
                                        fontWeight: FontWeight.w700,
                                        color: kPrimaryBlue,
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _displayName,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface,
                              ),
                            ),
                            if (_usernameLine != null) ...<Widget>[
                              const SizedBox(height: 6),
                              Text(
                                _usernameLine!,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: cs.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (_about != null) ...<Widget>[
                        const SizedBox(height: 16),
                        Container(
                          decoration: cloudCardDecoration(context, radius: 18),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'О себе',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _about!,
                                style: TextStyle(
                                  fontSize: 15,
                                  height: 1.4,
                                  color: cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (canChat) ...<Widget>[
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _busyChat ? null : _openChat,
                          icon: _busyChat
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.chat_bubble_outline_rounded),
                          label: Text(
                            _busyChat ? '…' : 'Написать',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: kPrimaryBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
