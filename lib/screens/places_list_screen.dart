import 'dart:async';

import 'package:flutter/material.dart';

import '../app_constants.dart';
import '../services/city_data_service.dart';
import '../services/place_service.dart';
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
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Material(
                                color: cs.surface,
                                borderRadius: BorderRadius.circular(16),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: id.isEmpty
                                      ? null
                                      : () async {
                                          await Navigator.of(context)
                                              .push<void>(
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
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        PlaceListCoverImage(
                                          imageUrl: photo != null &&
                                                  photo.isNotEmpty
                                              ? photo
                                              : null,
                                          width: 108,
                                          borderRadius: 12,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: <Widget>[
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: <Widget>[
                                                  Expanded(
                                                    child: Text(
                                                      title,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 17,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: cs.onSurface,
                                                      ),
                                                    ),
                                                  ),
                                                  if (_isAdmin &&
                                                      id.isNotEmpty)
                                                    PopupMenuButton<String>(
                                                      tooltip: 'Управление',
                                                      position:
                                                          PopupMenuPosition
                                                              .under,
                                                      offset:
                                                          const Offset(0, 4),
                                                      padding: EdgeInsets.zero,
                                                      constraints:
                                                          const BoxConstraints(
                                                        minWidth: 40,
                                                        minHeight: 40,
                                                      ),
                                                      shape:
                                                          RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(
                                                          14,
                                                        ),
                                                      ),
                                                      color: cs
                                                          .surfaceContainerHighest,
                                                      icon: Icon(
                                                        Icons
                                                            .settings_outlined,
                                                        size: 22,
                                                        color: cs.primary,
                                                      ),
                                                      onSelected:
                                                          (String v) {
                                                        unawaited(
                                                          _onPlaceAdminMenu(
                                                            v,
                                                            id,
                                                            title,
                                                            desc,
                                                          ),
                                                        );
                                                      },
                                                      itemBuilder:
                                                          (BuildContext ctx) {
                                                        return <PopupMenuEntry<
                                                            String>>[
                                                          PopupMenuItem<
                                                              String>(
                                                            value: 'edit',
                                                            child: Row(
                                                              children:
                                                                  <Widget>[
                                                                Icon(
                                                                  Icons
                                                                      .edit_outlined,
                                                                  size: 22,
                                                                  color: cs
                                                                      .onSurface,
                                                                ),
                                                                const SizedBox(
                                                                  width: 12,
                                                                ),
                                                                const Text(
                                                                  'Редактировать',
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          PopupMenuItem<
                                                              String>(
                                                            value: 'moderator',
                                                            child: Row(
                                                              children:
                                                                  <Widget>[
                                                                Icon(
                                                                  Icons
                                                                      .person_add_outlined,
                                                                  size: 22,
                                                                  color: cs
                                                                      .onSurface,
                                                                ),
                                                                const SizedBox(
                                                                  width: 12,
                                                                ),
                                                                const Text(
                                                                  'Назначить модератора',
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          PopupMenuItem<
                                                              String>(
                                                            value: 'rename',
                                                            child: Row(
                                                              children:
                                                                  <Widget>[
                                                                Icon(
                                                                  Icons
                                                                      .drive_file_rename_outline,
                                                                  size: 22,
                                                                  color: cs
                                                                      .onSurface,
                                                                ),
                                                                const SizedBox(
                                                                  width: 12,
                                                                ),
                                                                const Text(
                                                                  'Переименовать',
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          const PopupMenuDivider(),
                                                          PopupMenuItem<
                                                              String>(
                                                            value: 'delete',
                                                            child: Row(
                                                              children:
                                                                  <Widget>[
                                                                const Icon(
                                                                  Icons
                                                                      .delete_outline,
                                                                  size: 22,
                                                                  color: Color(
                                                                    0xFFC62828,
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                  width: 12,
                                                                ),
                                                                Text(
                                                                  'Удалить заведение',
                                                                  style:
                                                                      TextStyle(
                                                                    color: Colors
                                                                        .red
                                                                        .shade800,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ];
                                                      },
                                                    ),
                                                ],
                                              ),
                                              if (desc.isNotEmpty) ...<Widget>[
                                                const SizedBox(height: 6),
                                                Text(
                                                  desc,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    height: 1.35,
                                                    color: cs.onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(height: 10),
                                              _SubscribeChip(
                                                subscribed: sub,
                                                compact: _isAdmin,
                                                onTap: id.isEmpty
                                                    ? null
                                                    : () => unawaited(
                                                          _toggleSubscribe(id),
                                                        ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          Icons.chevron_right_rounded,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ],
                                    ),
                                  ),
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

class _SubscribeChip extends StatefulWidget {
  const _SubscribeChip({
    required this.subscribed,
    this.onTap,
    this.compact = false,
  });

  final bool subscribed;
  final VoidCallback? onTap;
  final bool compact;

  @override
  State<_SubscribeChip> createState() => _SubscribeChipState();
}

class _SubscribeChipState extends State<_SubscribeChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 1, end: 0.94).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeOut),
      ),
      child: Material(
        color: widget.subscribed
            ? kPrimaryBlue.withValues(alpha: 0.12)
            : kPrimaryBlue,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: widget.onTap == null
              ? null
              : () async {
                  await _c.forward();
                  _c.reverse();
                  widget.onTap!();
                },
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 10 : 14,
              vertical: widget.compact ? 6 : 8,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              transitionBuilder: (Widget child, Animation<double> a) {
                return FadeTransition(
                  opacity: a,
                  child: ScaleTransition(scale: a, child: child),
                );
              },
              child: Row(
                key: ValueKey<bool>(widget.subscribed),
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    widget.subscribed
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                    size: widget.compact ? 16 : 18,
                    color: widget.subscribed ? kPrimaryBlue : Colors.white,
                  ),
                  SizedBox(width: widget.compact ? 5 : 6),
                  Text(
                    widget.subscribed ? 'Вы подписаны' : 'Подписаться',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: widget.compact ? 12 : 13,
                      color: widget.subscribed ? kPrimaryBlue : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
