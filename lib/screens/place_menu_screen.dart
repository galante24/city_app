import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_constants.dart';
import '../services/place_service.dart';
import '../widgets/city_network_image.dart';
import '../widgets/soft_tab_header.dart';
import '../widgets/weather_app_bar_action.dart';
import 'place_menu_manage_screen.dart';

String _menuCategoryLabel(String? raw) {
  final String t = raw?.trim() ?? '';
  return t.isEmpty ? 'Другое' : t;
}

Map<String, List<Map<String, dynamic>>> _groupMenuItems(
  List<Map<String, dynamic>> items,
) {
  final Map<String, List<Map<String, dynamic>>> map =
      <String, List<Map<String, dynamic>>>{};
  for (final Map<String, dynamic> m in items) {
    final String k = _menuCategoryLabel(m['category'] as String?);
    map.putIfAbsent(k, () => <Map<String, dynamic>>[]).add(m);
  }
  for (final List<Map<String, dynamic>> list in map.values) {
    list.sort(
      (Map<String, dynamic> a, Map<String, dynamic> b) =>
          (a['title'] as String? ?? '')
              .toLowerCase()
              .compareTo((b['title'] as String? ?? '').toLowerCase()),
    );
  }
  final List<String> keys = map.keys.toList()
    ..sort(
      (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()),
    );
  return <String, List<Map<String, dynamic>>>{
    for (final String k in keys) k: map[k]!,
  };
}

String _formatMenuMoney(num? v) {
  if (v == null) {
    return '';
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

num? _numField(dynamic v) {
  if (v == null) {
    return null;
  }
  if (v is num) {
    return v;
  }
  if (v is String) {
    return num.tryParse(v.replaceAll(',', '.'));
  }
  return null;
}

/// Бейдж «акция»: старая цена осмысленна и ниже текущей (или цена не задана).
bool _menuItemShowsPromo(num? price, num? oldPrice) {
  if (oldPrice == null || oldPrice <= 0) {
    return false;
  }
  if (price == null) {
    return true;
  }
  return oldPrice > price;
}

/// Витрина «Меню и акции» для гостей и подписчиков.
class PlaceMenuScreen extends StatefulWidget {
  const PlaceMenuScreen({
    super.key,
    required this.placeId,
    required this.placeTitle,
    required this.canManage,
  });

  final String placeId;
  final String placeTitle;
  final bool canManage;

  @override
  State<PlaceMenuScreen> createState() => _PlaceMenuScreenState();
}

class _PlaceMenuScreenState extends State<PlaceMenuScreen> {
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

  Future<void> _openManage() async {
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext c) => PlaceMenuManageScreen(
          placeId: widget.placeId,
          placeTitle: widget.placeTitle,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Map<String, List<Map<String, dynamic>>> grouped =
        _groupMenuItems(_items);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SoftTabHeader(
            leading: const SoftHeaderBackButton(),
            title: 'Меню и акции',
            trailing: SoftHeaderWeatherWithAction(
              action: widget.canManage
                  ? IconButton(
                      icon: Icon(
                        Icons.tune_rounded,
                        color: softHeaderTrailingIconColor(context),
                        size: 26,
                      ),
                      tooltip: 'Управление меню',
                      onPressed: _openManage,
                    )
                  : Icon(
                      Icons.restaurant_menu_rounded,
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
                  : _items.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(32),
                          children: <Widget>[
                            Icon(
                              Icons.restaurant_outlined,
                              size: 64,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Пока нет позиций в меню',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Загляните позже — заведение может ещё наполнять витрину.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.35,
                                color: cs.onSurfaceVariant.withValues(
                                  alpha: 0.85,
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: <Widget>[
                            Text(
                              widget.placeTitle,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Цены и состав уточняйте в заведении.',
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.3,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 20),
                            for (final MapEntry<String,
                                    List<Map<String, dynamic>>> e
                                in grouped.entries) ...<Widget>[
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  e.key,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: kPrimaryBlue,
                                  ),
                                ),
                              ),
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 0.62,
                                ),
                                itemCount: e.value.length,
                                itemBuilder: (BuildContext c, int i) {
                                  return _MenuShowcaseCard(
                                    item: e.value[i],
                                    colorScheme: cs,
                                  );
                                },
                              ),
                              const SizedBox(height: 20),
                            ],
                          ],
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuShowcaseCard extends StatelessWidget {
  const _MenuShowcaseCard({
    required this.item,
    required this.colorScheme,
  });

  final Map<String, dynamic> item;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final String title = (item['title'] as String?)?.trim() ?? 'Без названия';
    final String desc = (item['description'] as String?)?.trim() ?? '';
    final String? photo = (item['photo_url'] as String?)?.trim();
    final bool available = item['is_available'] != false;
    final num? price = _numField(item['price']);
    final num? oldPrice = _numField(item['old_price']);
    final bool promo = _menuItemShowsPromo(price, oldPrice);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (photo != null && photo.isNotEmpty)
                    CityNetworkImage.fillParent(
                      imageUrl: photo,
                      boxFit: BoxFit.cover,
                    )
                  else
                    ColoredBox(
                      color: kPrimaryBlue.withValues(alpha: 0.1),
                      child: const Center(
                        child: Icon(
                          Icons.fastfood_outlined,
                          color: kPrimaryBlue,
                          size: 40,
                        ),
                      ),
                    ),
                if (promo)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE53935),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Text(
                        'АКЦИЯ',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                if (!available)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.45),
                      child: const Center(
                        child: Text(
                          'Нет в наличии',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                          color: available
                              ? colorScheme.onSurface
                              : colorScheme.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                      if (desc.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.25,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (price != null) ...<Widget>[
                        if (promo && oldPrice != null)
                          Text(
                            _formatMenuMoney(oldPrice),
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                              decoration: TextDecoration.lineThrough,
                              decorationColor: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        Text(
                          _formatMenuMoney(price),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color:
                                available ? kPrimaryBlue : colorScheme.outline,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
    );
  }
}
