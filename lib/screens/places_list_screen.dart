import 'dart:async';

import 'package:flutter/material.dart';

import '../app_card_styles.dart';
import '../app_constants.dart';
import '../services/city_data_service.dart';
import '../services/place_service.dart';
import '../widgets/city_network_image.dart';
import '../widgets/place_card.dart';
import '../widgets/places_style.dart';
import '../widgets/soft_tab_header.dart';
import '../widgets/weather_app_bar_action.dart';
import 'place_assign_moderator_screen.dart';
import 'place_create_screen.dart';
import 'place_detail_screen.dart';
import 'place_edit_basic_screen.dart';

class PlacesListScreen extends StatefulWidget {
  const PlacesListScreen({super.key});

  @override
  State<PlacesListScreen> createState() => _PlacesListScreenState();
}

class _PlacesListScreenState extends State<PlacesListScreen> {
  List<Map<String, dynamic>> _places = <Map<String, dynamic>>[];
  Set<String> _subscribed = <String>{};
  bool _loading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final bool admin = await CityDataService.isProfilesOrEmailAdmin();
    final List<Map<String, dynamic>> list = await PlaceService.fetchPlaces();
    final Set<String> sub = await PlaceService.fetchMySubscribedPlaceIds();
    if (mounted) {
      setState(() {
        _isAdmin = admin;
        _places = list;
        _subscribed = sub;
        _loading = false;
      });
    }
  }

  Future<void> _toggleSubscribe(String placeId) async {
    final bool on = _subscribed.contains(placeId);
    try {
      if (on) {
        await PlaceService.unsubscribe(placeId);
        _subscribed.remove(placeId);
      } else {
        await PlaceService.subscribe(placeId);
        _subscribed.add(placeId);
      }
      if (mounted) {
        setState(() {});
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Подписка: $e')));
      }
    }
  }

  Future<void> _openEditBasic(String id, String title, String description) async {
    final bool? ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext c) => PlaceEditBasicScreen(
          placeId: id,
          initialTitle: title,
          initialDescription: description,
        ),
      ),
    );
    if (ok == true && mounted) {
      await _load();
    }
  }

  Future<void> _openAssignModerator(String id, String title) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => PlaceAssignModeratorScreen(
          placeId: id,
          placeTitle: title,
        ),
      ),
    );
    if (mounted) {
      await _load();
    }
  }

  Future<void> _quickRenamePlace(String id, String currentTitle) async {
    final TextEditingController c = TextEditingController(text: currentTitle);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Переименовать'),
          content: TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Название',
              border: OutlineInputBorder(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
    final String next = c.text.trim();
    c.dispose();
    if (ok != true || !mounted || next.isEmpty) {
      return;
    }
    try {
      await PlaceService.updatePlace(id, <String, dynamic>{'title': next});
      if (!mounted) {
        return;
      }
      await _load();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Название обновлено')),
      );
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  Future<void> _confirmDeletePlace(String id, String title) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Удалить заведение?'),
          content: Text(
            '«$title» будет удалено без восстановления вместе с привязанными данными.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) {
      return;
    }
    try {
      await PlaceService.deletePlace(id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заведение удалено')),
      );
      await _load();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  Future<void> _openRemoveModerator(String placeId, String title) async {
    final bool admin = await CityDataService.isProfilesOrEmailAdmin();
    if (!mounted) {
      return;
    }
    if (!admin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Доступно только администратору')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (BuildContext c) => _RemovePlaceModeratorsDialog(
        placeId: placeId,
        placeTitle: title,
      ),
    );
  }

  Future<void> _onPlaceAdminMenu(
    String value,
    String id,
    String title,
    String description,
  ) async {
    if (value == 'edit') {
      await _openEditBasic(id, title, description);
    } else if (value == 'moderator') {
      await _openAssignModerator(id, title);
    } else if (value == 'remove_moderator') {
      await _openRemoveModerator(id, title);
    } else if (value == 'rename') {
      await _quickRenamePlace(id, title);
    } else if (value == 'delete') {
      await _confirmDeletePlace(id, title);
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
            title: 'Заведения',
            trailing: SoftHeaderWeatherWithAction(
              action: Icon(
                Icons.storefront_rounded,
                size: 28,
                color: softHeaderTrailingIconColor(context),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      children: <Widget>[
                        const PlacesSectionHeader(
                          title: 'Городские заведения',
                          subtitle:
                              'Кафе, магазины и сервисы города. Подписка на ленту заведения.',
                        ),
                        if (_isAdmin) ...<Widget>[
                          FilledButton.icon(
                            onPressed: () async {
                              await Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (BuildContext c) =>
                                      const PlaceCreateScreen(),
                                ),
                              );
                              if (mounted) {
                                await _load();
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: kPrimaryBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text(
                              'Добавить заведение',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        if (_places.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 32),
                            child: Center(
                              child: Text(
                                'Пока нет заведений',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          )
                        else
                          ..._places.map((Map<String, dynamic> m) {
                            final String id = m['id']?.toString() ?? '';
                            final String title = m['title'] as String? ?? '';
                            final String desc =
                                (m['description'] as String?)?.trim() ?? '';
                            final String? photo =
                                m['photo_url'] as String? ?? m['cover_url'] as String?;
                            final bool sub = _subscribed.contains(id);
                            return Padding(
                              padding: const EdgeInsets.only(
                                bottom: kCloudListSpacing,
                              ),
                              child: CloudInkCard(
                                radius: 24,
                                onTap: id.isEmpty
                                    ? null
                                    : () async {
                                        await Navigator.of(context).push<void>(
                                          MaterialPageRoute<void>(
                                            builder: (BuildContext c) =>
                                                PlaceDetailScreen(
                                              placeId: id,
                                            ),
                                          ),
                                        );
                                        if (mounted) {
                                          await _load();
                                        }
                                      },
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: <Widget>[
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        14,
                                        14,
                                        14,
                                        14,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          PlaceListSquareThumb(
                                            imageUrl: photo != null &&
                                                    photo.isNotEmpty
                                                ? photo
                                                : null,
                                            size: 80,
                                            borderRadius: 16,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Padding(
                                              padding: EdgeInsets.only(
                                                right:
                                                    _isAdmin && id.isNotEmpty
                                                        ? 36
                                                        : 0,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: <Widget>[
                                                  Text(
                                                    title,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 19,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      height: 1.2,
                                                      letterSpacing: -0.2,
                                                      color: cs.onSurface,
                                                    ),
                                                  ),
                                                  if (desc.isNotEmpty) ...<Widget>[
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      desc,
                                                      maxLines: 2,
                                                      overflow: TextOverflow
                                                          .ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        height: 1.35,
                                                        color: cs
                                                            .onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ],
                                                  const SizedBox(height: 12),
                                                  _PlaceSubscribeControl(
                                                    subscribed: sub,
                                                    enabled: id.isNotEmpty,
                                                    onPressed: () =>
                                                        unawaited(
                                                      _toggleSubscribe(id),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_isAdmin && id.isNotEmpty)
                                      Positioned(
                                        top: 4,
                                        right: 2,
                                        child: PopupMenuButton<String>(
                                          tooltip: 'Управление',
                                          position: PopupMenuPosition.under,
                                          offset: const Offset(0, 4),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 36,
                                            minHeight: 36,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          color: cs.surfaceContainerHighest,
                                          icon: Icon(
                                            Icons.settings_outlined,
                                            size: 20,
                                            color: cs.onSurfaceVariant
                                                .withValues(alpha: 0.45),
                                          ),
                                          onSelected: (String v) {
                                            unawaited(
                                              _onPlaceAdminMenu(
                                                v,
                                                id,
                                                title,
                                                desc,
                                              ),
                                            );
                                          },
                                          itemBuilder: (BuildContext ctx) {
                                            return <PopupMenuEntry<String>>[
                                              PopupMenuItem<String>(
                                                value: 'edit',
                                                child: Row(
                                                  children: <Widget>[
                                                    Icon(
                                                      Icons.edit_outlined,
                                                      size: 22,
                                                      color: cs.onSurface,
                                                    ),
                                                    const SizedBox(width: 12),
                                                    const Text('Редактировать'),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuItem<String>(
                                                value: 'moderator',
                                                child: Row(
                                                  children: <Widget>[
                                                    Icon(
                                                      Icons.person_add_outlined,
                                                      size: 22,
                                                      color: cs.onSurface,
                                                    ),
                                                    const SizedBox(width: 12),
                                                    const Text(
                                                      'Назначить модератора',
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuItem<String>(
                                                value: 'remove_moderator',
                                                child: Row(
                                                  children: <Widget>[
                                                    Icon(
                                                      Icons.person_remove,
                                                      size: 22,
                                                      color: cs.onSurface,
                                                    ),
                                                    const SizedBox(width: 12),
                                                    const Text(
                                                      'Убрать модератора',
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuItem<String>(
                                                value: 'rename',
                                                child: Row(
                                                  children: <Widget>[
                                                    Icon(
                                                      Icons
                                                          .drive_file_rename_outline,
                                                      size: 22,
                                                      color: cs.onSurface,
                                                    ),
                                                    const SizedBox(width: 12),
                                                    const Text('Переименовать'),
                                                  ],
                                                ),
                                              ),
                                              const PopupMenuDivider(),
                                              PopupMenuItem<String>(
                                                value: 'delete',
                                                child: Row(
                                                  children: <Widget>[
                                                    const Icon(
                                                      Icons.delete_outline,
                                                      size: 22,
                                                      color: Color(0xFFC62828),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Text(
                                                      'Удалить заведение',
                                                      style: TextStyle(
                                                        color: Colors
                                                            .red.shade800,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ];
                                          },
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceSubscribeControl extends StatelessWidget {
  const _PlaceSubscribeControl({
    required this.subscribed,
    required this.enabled,
    required this.onPressed,
  });

  final bool subscribed;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    if (!enabled) {
      return const SizedBox.shrink();
    }
    if (subscribed) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.notifications_active_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                ),
                const SizedBox(width: 8),
                Text(
                  'Вы подписаны',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Подписаться'),
        style: FilledButton.styleFrom(
          backgroundColor: kPrimaryBlue.withValues(alpha: 0.12),
          foregroundColor: kPrimaryBlue,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class _RemovePlaceModeratorsDialog extends StatefulWidget {
  const _RemovePlaceModeratorsDialog({
    required this.placeId,
    required this.placeTitle,
  });

  final String placeId;
  final String placeTitle;

  @override
  State<_RemovePlaceModeratorsDialog> createState() =>
      _RemovePlaceModeratorsDialogState();
}

class _RemovePlaceModeratorsDialogState
    extends State<_RemovePlaceModeratorsDialog> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = PlaceService.fetchPlaceModeratorsWithProfiles(widget.placeId);
    });
  }

  String _label(Map<String, dynamic> row) {
    final String? u = row['username'] as String?;
    if (u != null && u.trim().isNotEmpty) {
      return '@${u.trim()}';
    }
    final String fn = (row['first_name'] as String?)?.trim() ?? '';
    final String ln = (row['last_name'] as String?)?.trim() ?? '';
    final String name = '$fn $ln'.trim();
    if (name.isNotEmpty) {
      return name;
    }
    final String id = row['user_id']?.toString() ?? '';
    if (id.length >= 8) {
      return 'Пользователь ${id.substring(0, 8)}…';
    }
    return 'Пользователь';
  }

  String _subtitle(Map<String, dynamic> row, String label) {
    final String fn = (row['first_name'] as String?)?.trim() ?? '';
    final String ln = (row['last_name'] as String?)?.trim() ?? '';
    final String full = '$fn $ln'.trim();
    final String? u = row['username'] as String?;
    final String nick = (u != null && u.trim().isNotEmpty) ? '@${u.trim()}' : '';
    if (label.startsWith('@')) {
      return full.isNotEmpty ? full : '';
    }
    if (nick.isNotEmpty && label != nick) {
      return nick;
    }
    return '';
  }

  String? _avatarUrl(Map<String, dynamic> row) {
    final String? s = (row['avatar_url'] as String?)?.trim();
    if (s == null || s.isEmpty) {
      return null;
    }
    return s;
  }

  Future<void> _confirmRemove(Map<String, dynamic> row) async {
    final String uid = row['user_id']?.toString() ?? '';
    if (uid.isEmpty) {
      return;
    }
    final String label = _label(row);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) {
        return AlertDialog(
          title: const Text('Снять модератора?'),
          content: Text(
            '$label больше не сможет управлять меню и постами этого заведения.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Снять'),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) {
      return;
    }
    try {
      await PlaceService.removeModerator(widget.placeId, uid);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Модератор успешно снят')),
      );
      _reload();
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
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 20),
          decoration: cloudCardDecoration(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Текущие модераторы',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.placeTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.25,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kAppScaffoldBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _future,
                    builder: (
                      BuildContext context,
                      AsyncSnapshot<List<Map<String, dynamic>>> snap,
                    ) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      final List<Map<String, dynamic>> list =
                          snap.data ?? <Map<String, dynamic>>[];
                      if (list.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Нет назначенных модераторов',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: list.length,
                        separatorBuilder: (BuildContext context, int index) =>
                            const SizedBox(height: kCloudListSpacing),
                        itemBuilder: (BuildContext c, int i) {
                          final Map<String, dynamic> row = list[i];
                          final String lab = _label(row);
                          final String sub = _subtitle(row, lab);
                          return _ModeratorCloudTile(
                            label: lab,
                            subtitle: sub,
                            avatarUrl: _avatarUrl(row),
                            onRemove: () => unawaited(_confirmRemove(row)),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeratorCloudTile extends StatelessWidget {
  const _ModeratorCloudTile({
    required this.label,
    required this.subtitle,
    required this.avatarUrl,
    required this.onRemove,
  });

  final String label;
  final String subtitle;
  final String? avatarUrl;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    const double side = 52;
    return Container(
      decoration: cloudCardDecoration(context),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: <Widget>[
          avatarUrl != null && avatarUrl!.trim().isNotEmpty
              ? CityNetworkImage.square(
                  imageUrl: avatarUrl,
                  size: side,
                  borderRadius: 14,
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: side,
                    height: side,
                    child: ColoredBox(
                      color: kPrimaryBlue.withValues(alpha: 0.12),
                      child: Icon(
                        Icons.person_rounded,
                        color: kPrimaryBlue,
                        size: 28,
                      ),
                    ),
                  ),
                ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                if (subtitle.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Снять с роли',
            onPressed: onRemove,
            icon: Icon(
              Icons.person_remove_rounded,
              color: cs.primary,
            ),
          ),
        ],
      ),
    );
  }
}

