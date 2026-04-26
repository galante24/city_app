import 'dart:async';

import 'package:flutter/material.dart';

import '../app_constants.dart';
import '../services/city_data_service.dart';
import '../services/place_service.dart';
import '../utils/image_cache_extent.dart';
import '../widgets/places_style.dart';
import '../widgets/soft_tab_header.dart';
import '../widgets/weather_app_bar_action.dart';
import 'place_assign_moderator_screen.dart';
import 'place_create_screen.dart';
import 'place_detail_screen.dart';

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
                              'Подпишитесь на новости кафе и магазинов. Управление — для модераторов.',
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
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: photo != null &&
                                                  photo.isNotEmpty
                                              ? Image.network(
                                                  photo,
                                                  width: 72,
                                                  height: 72,
                                                  fit: BoxFit.cover,
                                                  cacheWidth:
                                                      imageCacheExtentPx(
                                                    context,
                                                    72,
                                                  ),
                                                  cacheHeight:
                                                      imageCacheExtentPx(
                                                    context,
                                                    72,
                                                  ),
                                                  errorBuilder:
                                                      (
                                                    BuildContext c,
                                                    Object e,
                                                    StackTrace? st,
                                                  ) =>
                                                          Container(
                                                    width: 72,
                                                    height: 72,
                                                    color: kPrimaryBlue
                                                        .withValues(
                                                      alpha: 0.12,
                                                    ),
                                                    child: const Icon(
                                                      Icons.store_rounded,
                                                      color: kPrimaryBlue,
                                                    ),
                                                  ),
                                                )
                                              : Container(
                                                  width: 72,
                                                  height: 72,
                                                  color: kPrimaryBlue
                                                      .withValues(alpha: 0.12),
                                                  child: const Icon(
                                                    Icons.store_rounded,
                                                    color: kPrimaryBlue,
                                                  ),
                                                ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: <Widget>[
                                              Text(
                                                title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.w800,
                                                  color: cs.onSurface,
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              _SubscribeChip(
                                                subscribed: sub,
                                                onTap: id.isEmpty
                                                    ? null
                                                    : () => unawaited(
                                                          _toggleSubscribe(id),
                                                        ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (_isAdmin && id.isNotEmpty)
                                          IconButton(
                                            tooltip: 'Назначить модератора',
                                            onPressed: () async {
                                              await Navigator.of(context)
                                                  .push<void>(
                                                MaterialPageRoute<void>(
                                                  builder: (BuildContext c) =>
                                                      PlaceAssignModeratorScreen(
                                                    placeId: id,
                                                    placeTitle: title,
                                                  ),
                                                ),
                                              );
                                            },
                                            icon: Icon(
                                              Icons.person_add_rounded,
                                              color: cs.primary,
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
  const _SubscribeChip({required this.subscribed, this.onTap});

  final bool subscribed;
  final VoidCallback? onTap;

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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                    size: 18,
                    color: widget.subscribed ? kPrimaryBlue : Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.subscribed ? 'Вы подписаны' : 'Подписаться',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
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
