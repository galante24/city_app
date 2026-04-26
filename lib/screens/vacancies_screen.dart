import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_constants.dart';
import '../main_shell_navigation.dart';
import '../services/job_vacancy_service.dart';
import '../widgets/city_main_navigation_bar.dart';
import '../utils/image_cache_extent.dart';
import '../widgets/soft_tab_header.dart';
import '../widgets/weather_app_bar_action.dart';
import 'vacancy_detail_screen.dart';
import 'vacancy_form_screen.dart';

enum _VacancySort { newest, oldest }

class VacanciesScreen extends StatefulWidget {
  const VacanciesScreen({super.key});

  @override
  State<VacanciesScreen> createState() => _VacanciesScreenState();
}

class _VacanciesScreenState extends State<VacanciesScreen> {
  final TextEditingController _search = TextEditingController();
  /// Поиск: обновление только списка без полного пересборки экрана.
  final ValueNotifier<String> _searchQuery = ValueNotifier<String>('');
  _VacancySort _sort = _VacancySort.newest;
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
    final List<Map<String, dynamic>> list = await JobVacancyService.fetchAll();
    if (mounted) {
      setState(() {
        _rows = list;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _filteredAndSorted(String q) {
    List<Map<String, dynamic>> list = _rows.where((Map<String, dynamic> m) {
      if (q.isEmpty) {
        return true;
      }
      final String t = (m['title'] as String? ?? '').toLowerCase();
      final String d = (m['description'] as String? ?? '').toLowerCase();
      final String s = (m['salary'] as String? ?? '').toLowerCase();
      final String a = (m['work_address'] as String? ?? '').toLowerCase();
      return t.contains(q) || d.contains(q) || s.contains(q) || a.contains(q);
    }).toList();
    list.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      final DateTime? da = DateTime.tryParse(
        (a['created_at'] as String?) ?? '',
      );
      final DateTime? db = DateTime.tryParse(
        (b['created_at'] as String?) ?? '',
      );
      final int cmp = (da ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
        db ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
      return _sort == _VacancySort.newest ? -cmp : cmp;
    });
    return list;
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
    const List<Color> palette = <Color>[
      Color(0xFF0288D1),
      Color(0xFF43A047),
      Color(0xFF7E57C2),
      Color(0xFFFF9800),
      Color(0xFFD13F7A),
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

  Future<void> _shareVacancy(Map<String, dynamic> m) async {
    final String title = m['title'] as String? ?? 'Вакансия';
    final String salary = m['salary'] as String? ?? '';
    final String addr = m['work_address'] as String? ?? '';
    final List<String> lines = <String>['Вакансия: $title'];
    if (salary.isNotEmpty) {
      lines.add('Зарплата: $salary');
    }
    if (addr.isNotEmpty) {
      lines.add('Адрес: $addr');
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
            title: 'Вакансии',
            trailing: SoftHeaderWeatherWithAction(
              action: Icon(
                Icons.work_rounded,
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
                hintText: 'Поиск вакансий',
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: _SuggestVacancyCard(
              onOpen: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (BuildContext c) => const VacancyFormScreen(),
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                Text(
                  'Сортировка: ',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
                ),
                PopupMenuButton<_VacancySort>(
                  initialValue: _sort,
                  tooltip: 'Порядок сортировки',
                  position: PopupMenuPosition.under,
                  offset: const Offset(0, 4),
                  onSelected: (_VacancySort v) {
                    setState(() => _sort = v);
                  },
                  itemBuilder: (BuildContext context) {
                    return <PopupMenuEntry<_VacancySort>>[
                      const PopupMenuItem<_VacancySort>(
                        value: _VacancySort.newest,
                        child: Text('сначала новые'),
                      ),
                      const PopupMenuItem<_VacancySort>(
                        value: _VacancySort.oldest,
                        child: Text('сначала старые'),
                      ),
                    ];
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          _sort == _VacancySort.newest
                              ? 'сначала новые'
                              : 'сначала старые',
                          style: const TextStyle(
                            color: kPrimaryBlue,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Icon(
                          Icons.arrow_drop_down_rounded,
                          color: kPrimaryBlue,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Актуальные вакансии',
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
                      final List<Map<String, dynamic>> shown =
                          _filteredAndSorted(q);
                      if (shown.isEmpty) {
                        return Center(
                          child: Text(
                            'Пока нет вакансий',
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
                        const SizedBox(height: 10),
                    itemBuilder: (BuildContext c, int i) {
                      final Map<String, dynamic> m = shown[i];
                      final String id = m['id']?.toString() ?? '';
                      final String title = m['title'] as String? ?? '';
                      final String salary = m['salary'] as String? ?? '';
                      final String addr = m['work_address'] as String? ?? '';
                      final String? imageUrl = m['image_url'] as String?;
                      final String created = m['created_at'] as String? ?? '';
                      final Color accent = _accentForId(
                        id.isEmpty ? title : id,
                      );
                      return _VacancyListTile(
                        title: title,
                        salary: salary,
                        address: addr,
                        dateLabel: _formatDate(created),
                        imageUrl: imageUrl,
                        accent: accent,
                        onShare: () => unawaited(_shareVacancy(m)),
                        onTap: () async {
                          await Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (BuildContext c) =>
                                  VacancyDetailScreen(row: m, accent: accent),
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

class _SuggestVacancyCard extends StatelessWidget {
  const _SuggestVacancyCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kPrimaryBlue.withValues(alpha: 0.35)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: <Widget>[
              Icon(Icons.work_rounded, size: 40, color: kPrimaryBlue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Предложить вакансию',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Разместите вакансию и найдите подходящих сотрудников',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.65),
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
        ),
      ),
    );
  }
}

class _VacancyListTile extends StatelessWidget {
  const _VacancyListTile({
    required this.title,
    required this.salary,
    required this.address,
    required this.dateLabel,
    required this.imageUrl,
    required this.accent,
    required this.onShare,
    required this.onTap,
  });

  final String title;
  final String salary;
  final String address;
  final String dateLabel;
  final String? imageUrl;
  final Color accent;
  final VoidCallback onShare;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: imageUrl != null && imageUrl!.isNotEmpty
                    ? Image.network(
                        imageUrl!,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        cacheWidth: imageCacheExtentPx(context, 64),
                        cacheHeight: imageCacheExtentPx(context, 64),
                        errorBuilder:
                            (BuildContext c, Object e, StackTrace? st) =>
                                _vacancyImagePlaceholder(accent, 64),
                      )
                    : _vacancyImagePlaceholder(accent, 64),
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
                    if (salary.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        'Зарплата: $salary',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: accent,
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
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
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
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: cs.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _vacancyImagePlaceholder(Color accent, double size) {
  return Container(
    width: size,
    height: size,
    color: accent.withValues(alpha: 0.12),
    child: Icon(Icons.work_outline_rounded, color: accent, size: 28),
  );
}
