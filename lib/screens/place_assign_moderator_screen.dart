import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_constants.dart';
import '../services/chat_service.dart';
import '../services/place_service.dart';
import '../widgets/soft_tab_header.dart';
import '../widgets/weather_app_bar_action.dart';

class PlaceAssignModeratorScreen extends StatefulWidget {
  const PlaceAssignModeratorScreen({
    super.key,
    required this.placeId,
    required this.placeTitle,
  });

  final String placeId;
  final String placeTitle;

  @override
  State<PlaceAssignModeratorScreen> createState() =>
      _PlaceAssignModeratorScreenState();
}

class _PlaceAssignModeratorScreenState extends State<PlaceAssignModeratorScreen> {
  final TextEditingController _q = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = <Map<String, dynamic>>[];
  bool _searching = false;
  Set<String> _existingMods = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_loadMods());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _loadMods() async {
    final List<String> ids =
        await PlaceService.fetchModeratorUserIds(widget.placeId);
    if (mounted) {
      setState(() => _existingMods = ids.toSet());
    }
  }

  void _onQueryChanged(String raw) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () async {
      final String q = raw.trim();
      if (q.length < 2) {
        if (mounted) {
          setState(() => _results = <Map<String, dynamic>>[]);
        }
        return;
      }
      setState(() => _searching = true);
      final List<Map<String, dynamic>> list =
          await ChatService.searchProfilesForChat(q);
      if (mounted) {
        setState(() {
          _results = list;
          _searching = false;
        });
      }
    });
  }

  Future<void> _addModerator(String userId, String label) async {
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    if (userId == me) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нельзя назначить себя')),
      );
      return;
    }
    if (_existingMods.contains(userId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label уже модератор')),
      );
      return;
    }
    try {
      await PlaceService.addModerator(widget.placeId, userId);
      if (mounted) {
        setState(() => _existingMods.add(userId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label назначен модератором')),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SoftTabHeader(
            leading: const SoftHeaderBackButton(),
            title: 'Назначить',
            trailing: const SoftHeaderWeatherWithAction(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              widget.placeTitle,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _q,
              decoration: InputDecoration(
                hintText: 'Поиск по нику (username)',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: _onQueryChanged,
            ),
          ),
          const SizedBox(height: 8),
          if (_searching)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _results.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const Divider(height: 1),
              itemBuilder: (BuildContext c, int i) {
                final Map<String, dynamic> m = _results[i];
                final String id = m['id']?.toString() ?? '';
                final String? u = m['username'] as String?;
                final String nick = (u == null || u.isEmpty) ? '—' : '@$u';
                final bool already = _existingMods.contains(id);
                return ListTile(
                  title: Text(nick),
                  subtitle: Text(
                    '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim(),
                  ),
                  trailing: already
                      ? Icon(Icons.check_circle, color: cs.primary)
                      : IconButton(
                          icon: const Icon(Icons.person_add_alt_rounded),
                          color: kPrimaryBlue,
                          onPressed: id.isEmpty
                              ? null
                              : () => unawaited(_addModerator(id, nick)),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
