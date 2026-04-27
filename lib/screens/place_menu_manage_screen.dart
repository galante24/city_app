import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_constants.dart';
import '../services/place_service.dart';
import '../widgets/city_network_image.dart';
import '../widgets/soft_tab_header.dart';
import '../widgets/weather_app_bar_action.dart';
import 'place_menu_item_edit_screen.dart';

String _manageCategoryLabel(String? raw) {
  final String t = raw?.trim() ?? '';
  return t.isEmpty ? 'Другое' : t;
}

String _shortMoney(num? v) {
  if (v == null) {
    return '—';
  }
  if (v == v.roundToDouble()) {
    return NumberFormat.currency(
      locale: 'ru_RU',
      symbol: '₽',
      decimalDigits: 0,
    ).format(v);
  }
  return NumberFormat.currency(
    locale: 'ru_RU',
    symbol: '₽',
    decimalDigits: 2,
  ).format(v);
}

/// Управление позициями меню (модераторы / админ).
class PlaceMenuManageScreen extends StatefulWidget {
  const PlaceMenuManageScreen({
    super.key,
    required this.placeId,
    required this.placeTitle,
  });

  final String placeId;
  final String placeTitle;

  @override
  State<PlaceMenuManageScreen> createState() => _PlaceMenuManageScreenState();
}

class _PlaceMenuManageScreenState extends State<PlaceMenuManageScreen> {
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final List<Map<String, dynamic>> list =
        await PlaceService.fetchMenuItems(widget.placeId);
    if (mounted) {
      setState(() {
        _items = list;
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    final bool? ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext c) => PlaceMenuItemEditScreen(
          placeId: widget.placeId,
        ),
      ),
    );
    if (ok == true && mounted) {
      await _load();
    }
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final bool? ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext c) => PlaceMenuItemEditScreen(
          placeId: widget.placeId,
          existing: row,
        ),
      ),
    );
    if (ok == true && mounted) {
      await _load();
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> row) async {
    final String title = (row['title'] as String?)?.trim() ?? '';
    final String id = row['id']?.toString() ?? '';
    if (id.isEmpty) {
      return;
    }
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Удалить позицию?'),
          content: Text(
            title.isEmpty
                ? 'Позиция будет удалена без восстановления.'
                : '«$title» будет удалена без восстановления.',
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
      await PlaceService.deleteMenuItem(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Удалено')),
        );
        await _load();
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

    final Map<String, List<Map<String, dynamic>>> grouped =
        <String, List<Map<String, dynamic>>>{};
    for (final Map<String, dynamic> m in _items) {
      final String k = _manageCategoryLabel(m['category'] as String?);
      grouped.putIfAbsent(k, () => <Map<String, dynamic>>[]).add(m);
    }
    final List<String> keys = grouped.keys.toList()
      ..sort(
        (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()),
      );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SoftTabHeader(
            leading: const SoftHeaderBackButton(),
            title: 'Управление меню',
            trailing: const SoftHeaderWeatherWithAction(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              widget.placeTitle,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _items.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(32),
                            children: <Widget>[
                              Text(
                                'Пока нет позиций. Нажмите +, чтобы добавить первую.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: cs.onSurfaceVariant,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                            itemCount: keys.length,
                            itemBuilder: (BuildContext c, int section) {
                              final String key = keys[section];
                              final List<Map<String, dynamic>> rows =
                                  grouped[key]!;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  Padding(
                                    padding: EdgeInsets.only(
                                      top: section == 0 ? 0 : 20,
                                      bottom: 10,
                                    ),
                                    child: Text(
                                      key,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: kPrimaryBlue,
                                      ),
                                    ),
                                  ),
                                  ...rows.map((Map<String, dynamic> row) {
                                    final String title =
                                        (row['title'] as String?)?.trim() ??
                                            '—';
                                    final dynamic pr = row['price'];
                                    final num? price = pr is num ? pr : null;
                                    final String? photo =
                                        (row['photo_url'] as String?)
                                            ?.trim();
                                    final bool ok =
                                        row['is_available'] != false;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: Material(
                                        color: cs.surface,
                                        elevation: 0,
                                        shadowColor: Colors.transparent,
                                        borderRadius: BorderRadius.circular(20),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            boxShadow: <BoxShadow>[
                                              BoxShadow(
                                                color: Colors.black.withValues(
                                                  alpha: 0.06,
                                                ),
                                                blurRadius: 12,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: InkWell(
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            onTap: () => unawaited(_edit(row)),
                                            child: Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: <Widget>[
                                                  photo != null && photo.isNotEmpty
                                                      ? CityNetworkImage.square(
                                                          imageUrl: photo,
                                                          size: 72,
                                                          borderRadius: 14,
                                                        )
                                                      : ClipRRect(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                            14,
                                                          ),
                                                          child: SizedBox(
                                                            width: 72,
                                                            height: 72,
                                                            child: ColoredBox(
                                                              color: kPrimaryBlue
                                                                  .withValues(
                                                                alpha: 0.1,
                                                              ),
                                                              child: const Icon(
                                                                Icons
                                                                    .fastfood_outlined,
                                                                color:
                                                                    kPrimaryBlue,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: <Widget>[
                                                        Text(
                                                          title,
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            fontSize: 16,
                                                            color: ok
                                                                ? cs.onSurface
                                                                : cs.onSurface
                                                                    .withValues(
                                                                    alpha:
                                                                        0.5,
                                                                  ),
                                                          ),
                                                        ),
                                                        const SizedBox(height: 4),
                                                        Text(
                                                          _shortMoney(price),
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            fontSize: 15,
                                                            color: kPrimaryBlue
                                                                .withValues(
                                                              alpha:
                                                                  ok ? 1 : 0.45,
                                                            ),
                                                          ),
                                                        ),
                                                        if (!ok)
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .only(
                                                              top: 4,
                                                            ),
                                                            child: Text(
                                                              'Нет в наличии',
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                color: cs
                                                                    .onSurfaceVariant,
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.delete_outline,
                                                      color: Color(0xFFC62828),
                                                    ),
                                                    onPressed: () =>
                                                        unawaited(
                                                      _confirmDelete(row),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Добавить',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
