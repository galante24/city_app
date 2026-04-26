import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../app_card_styles.dart';
import '../app_constants.dart';
import '../main_shell_navigation.dart';
import '../services/task_service.dart';
import '../utils/author_embed.dart';
import '../utils/social_time_format.dart';
import '../widgets/city_main_navigation_bar.dart';
import '../widgets/social_header.dart';
import '../widgets/soft_tab_header.dart';
import '../widgets/weather_app_bar_action.dart';
import 'task_detail_screen.dart';
import 'task_form_screen.dart';

class TasksListScreen extends StatefulWidget {
  const TasksListScreen({super.key});

  @override
  State<TasksListScreen> createState() => _TasksListScreenState();
}

class _TasksListScreenState extends State<TasksListScreen> {
  final TextEditingController _search = TextEditingController();
  final ValueNotifier<String> _searchQuery = ValueNotifier<String>('');
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    unawaited(_load());
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
    final List<Map<String, dynamic>> list = await TaskService.fetchAll();
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
      final String p = (m['phone'] as String? ?? '').toLowerCase();
      final String priceStr = (m['price']?.toString() ?? '').toLowerCase();
      return t.contains(q) ||
          d.contains(q) ||
          p.contains(q) ||
          priceStr.contains(q);
    }).toList();
  }

  String? _cardPriceLabel(dynamic raw) {
    if (raw == null) {
      return null;
    }
    final num? n = raw is num ? raw : num.tryParse(raw.toString());
    if (n == null || n <= 0) {
      return null;
    }
    final NumberFormat fmt = NumberFormat.currency(
      locale: 'ru',
      symbol: '₽',
      decimalDigits: 0,
    );
    return fmt.format(n);
  }

  Color _accentForId(String id) {
    const List<Color> palette = <Color>[
      Color(0xFF3D9B4C),
      Color(0xFF0288D1),
      Color(0xFF7E57C2),
      Color(0xFFFF9800),
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

  Future<void> _share(Map<String, dynamic> m) async {
    final String title = m['title'] as String? ?? 'Задача';
    final String desc = m['description'] as String? ?? '';
    await Share.share('$title\n\n$desc', subject: title);
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
            title: 'Услуги и задачи',
            trailing: SoftHeaderWeatherWithAction(
              action: Icon(
                Icons.task_alt_rounded,
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
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: CloudInkCard(
                    onTap: () async {
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (BuildContext c) => const TaskFormScreen(),
                        ),
                      );
                      if (mounted) {
                        await _load();
                      }
                    },
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.add_task_rounded,
                          size: 40,
                          color: kPrimaryBlue,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Подать объявление',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Найти исполнителя или предложить услугу',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface.withValues(alpha: 0.65),
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
                          child: const Icon(
                            Icons.chevron_right,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
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
                            final List<Map<String, dynamic>> shown = _filtered(q);
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
                                final String title = m['title'] as String? ?? '';
                                final String authorId =
                                    m['author_id']?.toString() ?? '';
                                final String? priceLine = _cardPriceLabel(
                                  m['price'],
                                );
                                final Color accent = _accentForId(
                                  id.isEmpty ? title : id,
                                );
                                return CloudInkCard(
                                  onTap: () async {
                                    await Navigator.of(context).push<void>(
                                      MaterialPageRoute<void>(
                                        builder: (BuildContext c) =>
                                            TaskDetailScreen(
                                          row: m,
                                          accent: accent,
                                        ),
                                      ),
                                    );
                                    if (mounted) {
                                      await _load();
                                    }
                                  },
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: <Widget>[
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: accent.withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          Icons.task_alt_rounded,
                                          color: accent,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            if (authorId.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 8,
                                                ),
                                                child: SocialHeader(
                                                  userId: authorId,
                                                  author: authorMapFromRow(m),
                                                  createdAt: parseIsoUtc(
                                                    m['created_at'] as String?,
                                                  ),
                                                  dense: true,
                                                ),
                                              ),
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
                                            if (priceLine != null) ...<Widget>[
                                              const SizedBox(height: 6),
                                              Text(
                                                priceLine,
                                                style: const TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.w900,
                                                  color: Color(0xFF2E7D32),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () =>
                                            unawaited(_share(m)),
                                        icon: Icon(
                                          Icons.share_outlined,
                                          color: cs.primary,
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ],
                                  ),
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
