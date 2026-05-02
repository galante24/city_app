import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_card_styles.dart';
import '../app_constants.dart' show kPrimaryBlue, listingFloorAreaWithSuffix;
import '../main_shell_navigation.dart';
import '../models/real_estate_listing_kind.dart';
import '../services/real_estate_listing_service.dart';
import '../widgets/city_main_navigation_bar.dart';
import '../widgets/city_network_image.dart';
import '../widgets/soft_tab_header.dart';
import '../widgets/weather_app_bar_action.dart';
import 'real_estate_category_detail_screen.dart';
import 'real_estate_category_form_screen.dart';

class RealEstateCategoryListingsScreen extends StatefulWidget {
  const RealEstateCategoryListingsScreen({super.key, required this.kind});

  final RealEstateListingKind kind;

  @override
  State<RealEstateCategoryListingsScreen> createState() =>
      _RealEstateCategoryListingsScreenState();
}

class _RealEstateCategoryListingsScreenState
    extends State<RealEstateCategoryListingsScreen> {
  final TextEditingController _search = TextEditingController();
  final ValueNotifier<String> _searchQuery = ValueNotifier<String>('');
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  bool _loading = true;

  RealEstateListingKind get _k => widget.kind;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_load());
      }
    });
  }

  @override
  void dispose() {
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    _searchQuery.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchQuery.value = _search.text.trim().toLowerCase();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final List<Map<String, dynamic>> list =
        await RealEstateListingService.fetchAll(_k);
    if (mounted) {
      setState(() {
        _rows = list;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _filtered(String q) {
    if (q.isEmpty) {
      return List<Map<String, dynamic>>.from(_rows);
    }
    return _rows.where((Map<String, dynamic> m) {
      final String t = (m['title'] as String? ?? '').toLowerCase();
      final String d = (m['description'] as String? ?? '').toLowerCase();
      final String p = (m['price'] as String? ?? '').toLowerCase();
      final String a = RealEstateListingService.addressFromRow(m).toLowerCase();
      final String f = RealEstateListingService.floorAreaFromRow(
        m,
      ).toLowerCase();
      return t.contains(q) ||
          d.contains(q) ||
          p.contains(q) ||
          a.contains(q) ||
          f.contains(q);
    }).toList();
  }

  String _formatDate(String? iso) {
    if (iso == null) {
      return '';
    }
    final DateTime? d = DateTime.tryParse(iso);
    if (d == null) {
      return '';
    }
    final DateTime l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}.${l.month.toString().padLeft(2, '0')}.${l.year}';
  }

  Color _accentForId(String id) {
    final List<Color> palette = <Color>[
      _k.accentColor,
      const Color(0xFF0288D1),
      const Color(0xFF43A047),
      const Color(0xFF7E57C2),
      const Color(0xFFFF9800),
    ];
    int h = 0;
    for (int i = 0; i < id.length; i++) {
      h = (h + id.codeUnitAt(i) * 17) & 0x7fffffff;
    }
    return palette[h % palette.length];
  }

  void _onMainBottomNav(int index) {
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
    MainShellNavigation.goToTab(index);
  }

  Future<void> _shareListing(Map<String, dynamic> m) async {
    final String title = m['title'] as String? ?? _k.listTitle;
    final String price = m['price'] as String? ?? '';
    final String addr = RealEstateListingService.addressFromRow(m);
    final List<String> lines = <String>['${_k.shareCategoryLabel}: $title'];
    if (price.isNotEmpty) {
      lines.add('Цена: $price');
    }
    if (addr.isNotEmpty) {
      lines.add('Адрес: $addr');
    }
    final String fa = RealEstateListingService.floorAreaFromRow(m);
    final String faDisp = listingFloorAreaWithSuffix(fa);
    if (faDisp.isNotEmpty) {
      lines.add('Квадратура: $faDisp');
    }
    await Share.share(lines.join('\n'), subject: title);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      bottomNavigationBar: CityMainNavigationBar(
        selectedIndex: 2,
        onDestinationSelected: _onMainBottomNav,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SoftTabHeader(
            leading: const SoftHeaderBackButton(),
            title: _k.listTitle,
            trailing: SoftHeaderWeatherWithAction(
              action: Icon(
                _k.headerIcon,
                size: 28,
                color: softHeaderTrailingIconColor(context),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Поиск объявлений',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: cs.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 4,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: _PostListingCard(
                    kind: _k,
                    onOpen: () async {
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (BuildContext c) =>
                              RealEstateCategoryFormScreen(kind: _k),
                        ),
                      );
                      if (mounted) {
                        await _load();
                      }
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'Объявления',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : ValueListenableBuilder<String>(
                          valueListenable: _searchQuery,
                          builder: (BuildContext context, String q, Widget? _) {
                            final List<Map<String, dynamic>> shown = _filtered(
                              q,
                            );
                            if (shown.isEmpty) {
                              return Center(
                                child: Text(
                                  'Пока нет объявлений',
                                  style: TextStyle(
                                    color: cs.onSurfaceVariant,
                                    fontSize: 16,
                                  ),
                                ),
                              );
                            }
                            return ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              itemCount: shown.length,
                              separatorBuilder: (BuildContext c, int i) =>
                                  const SizedBox(height: kCloudListSpacing),
                              itemBuilder: (BuildContext c, int i) {
                                final Map<String, dynamic> m = shown[i];
                                final String id = m['id']?.toString() ?? '';
                                final String title =
                                    m['title'] as String? ?? '';
                                final String price =
                                    m['price'] as String? ?? '';
                                final String addr =
                                    RealEstateListingService.addressFromRow(m);
                                final String fa =
                                    RealEstateListingService.floorAreaFromRow(
                                      m,
                                    );
                                final String? floorLine = fa.isEmpty
                                    ? null
                                    : listingFloorAreaWithSuffix(fa);
                                final String? imageUrl =
                                    m['image_url'] as String?;
                                final String created =
                                    m['created_at'] as String? ?? '';
                                final Color accent = _accentForId(
                                  id.isEmpty ? title : id,
                                );
                                return _EstateListingTile(
                                  title: title,
                                  price: price,
                                  floorLine: floorLine,
                                  address: addr,
                                  dateLabel: _formatDate(created),
                                  imageUrl: imageUrl,
                                  accent: accent,
                                  placeholderIcon: _k.headerIcon,
                                  onShare: () => unawaited(_shareListing(m)),
                                  onTap: () async {
                                    await Navigator.of(context).push<void>(
                                      MaterialPageRoute<void>(
                                        builder: (BuildContext c) =>
                                            RealEstateCategoryDetailScreen(
                                              kind: _k,
                                              row: m,
                                              accent: accent,
                                            ),
                                      ),
                                    );
                                    if (mounted) {
                                      await _load();
                                    }
                                  },
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PostListingCard extends StatelessWidget {
  const _PostListingCard({required this.kind, required this.onOpen});

  final RealEstateListingKind kind;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return CloudInkCard(
      onTap: onOpen,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: <Widget>[
          Icon(kind.headerIcon, size: 40, color: kPrimaryBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Выставить объявление',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  kind.postCardSubtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.65),
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: kPrimaryBlue,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chevron_right, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _EstateListingTile extends StatelessWidget {
  const _EstateListingTile({
    required this.title,
    required this.price,
    this.floorLine,
    required this.address,
    required this.dateLabel,
    required this.imageUrl,
    required this.accent,
    required this.placeholderIcon,
    required this.onShare,
    required this.onTap,
  });

  final String title;
  final String price;
  final String? floorLine;
  final String address;
  final String dateLabel;
  final String? imageUrl;
  final Color accent;
  final IconData placeholderIcon;
  final VoidCallback onShare;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return CloudInkCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          imageUrl != null && imageUrl!.isNotEmpty
              ? CityNetworkImage.square(
                  imageUrl: imageUrl,
                  size: 64,
                  borderRadius: 10,
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _listingImagePlaceholder(accent, 64, placeholderIcon),
                ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                if (price.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    'Цена: $price',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: kPrimaryBlue,
                    ),
                  ),
                ],
                if (floorLine != null && floorLine!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    'Квадратура: $floorLine',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                ],
                if (address.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.place_outlined,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (dateLabel.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    dateLabel,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.share_outlined, color: cs.primary),
            tooltip: 'Поделиться',
            onPressed: onShare,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: cs.onSurfaceVariant.withValues(alpha: 0.8),
          ),
        ],
      ),
    );
  }
}

Widget _listingImagePlaceholder(Color accent, double size, IconData icon) {
  return Container(
    width: size,
    height: size,
    color: accent.withValues(alpha: 0.12),
    child: Icon(icon, color: accent, size: 28),
  );
}
