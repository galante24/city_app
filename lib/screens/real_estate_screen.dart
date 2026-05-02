import 'package:flutter/material.dart';

import '../main_shell_navigation.dart';
import '../theme/city_theme.dart';
import '../widgets/city_main_navigation_bar.dart';
import '../widgets/soft_tab_header.dart';
import '../models/real_estate_listing_kind.dart';
import '../widgets/weather_app_bar_action.dart';
import 'garage_listings_screen.dart';
import 'real_estate_category_listings_screen.dart';

class _EstateCategory {
  const _EstateCategory({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.cardColor,
    required this.accentColor,
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;
  final Color cardColor;
  final Color accentColor;
}

/// Категории недвижимости — сетка в стиле экрана «Сервисы», с поддержкой тёмной темы.
class RealEstateScreen extends StatelessWidget {
  const RealEstateScreen({super.key});

  static const List<_EstateCategory> _items = <_EstateCategory>[
    _EstateCategory(
      id: 'garage',
      label: 'Гараж',
      description: 'Для машин и хранения',
      icon: Icons.garage_rounded,
      cardColor: Color(0xFFE3F2FD),
      accentColor: Color(0xFF1565C0),
    ),
    _EstateCategory(
      id: 'dacha',
      label: 'Дача',
      description: 'Для загородного отдыха',
      icon: Icons.holiday_village_rounded,
      cardColor: Color(0xFFFCE4EC),
      accentColor: Color(0xFFC2185B),
    ),
    _EstateCategory(
      id: 'house',
      label: 'Дом',
      description: 'Для жизни и семьи',
      icon: Icons.house_rounded,
      cardColor: Color(0xFFE8F5E9),
      accentColor: Color(0xFF2E7D32),
    ),
    _EstateCategory(
      id: 'apartment',
      label: 'Квартира',
      description: 'Для города и уюта',
      icon: Icons.apartment_rounded,
      cardColor: Color(0xFFFFECB3),
      accentColor: Color(0xFFE65100),
    ),
    _EstateCategory(
      id: 'land',
      label: 'Участок',
      description: 'Для строительства и инвестиций',
      icon: Icons.landscape_rounded,
      cardColor: Color(0xFFFFF9C4),
      accentColor: Color(0xFFF9A825),
    ),
    _EstateCategory(
      id: 'commercial',
      label: 'Коммерческая',
      description: 'Офисы, торговля, склады',
      icon: Icons.business_rounded,
      cardColor: Color(0xFFEDE7F6),
      accentColor: Color(0xFF5E35B1),
    ),
  ];

  static const Color _kDescriptionColor = Color(0xFF6C6C70);

  void _onMainBottomNav(BuildContext context, int index) {
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
    MainShellNavigation.goToTab(index);
  }

  void _onCardTap(BuildContext context, _EstateCategory c) {
    if (c.id == 'garage') {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => const GarageListingsScreen(),
        ),
      );
      return;
    }
    final RealEstateListingKind? kind = RealEstateListingKind.tryParseId(c.id);
    if (kind != null) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              RealEstateCategoryListingsScreen(kind: kind),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${c.label} — раздел в разработке')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      bottomNavigationBar: CityMainNavigationBar(
        selectedIndex: 2,
        onDestinationSelected: (int i) => _onMainBottomNav(context, i),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SoftTabHeader(
            leading: const SoftHeaderBackButton(),
            title: 'Недвижимость',
            trailing: SoftHeaderWeatherWithAction(
              action: Icon(
                Icons.home_work_rounded,
                size: 28,
                color: softHeaderTrailingIconColor(context),
              ),
            ),
          ),
          Expanded(
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: <Widget>[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 0.72,
                        ),
                    delegate: SliverChildBuilderDelegate((
                      BuildContext context,
                      int index,
                    ) {
                      final _EstateCategory c = _items[index];
                      return _EstateCategoryCard(
                        category: c,
                        descriptionColor: _kDescriptionColor,
                        onTap: () => _onCardTap(context, c),
                      );
                    }, childCount: _items.length),
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

class _EstateCategoryCard extends StatelessWidget {
  const _EstateCategoryCard({
    required this.category,
    required this.descriptionColor,
    required this.onTap,
  });

  final _EstateCategory category;
  final Color descriptionColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = category.accentColor;
    final Color cardBg = dark
        ? Color.alphaBlend(
            accent.withValues(alpha: 0.12),
            CityTheme.kDarkSurface,
          )
        : category.cardColor;
    final Color borderColor = dark
        ? accent.withValues(alpha: 0.55)
        : const Color(0xFF0A0A0A).withValues(alpha: 0.05);
    final List<BoxShadow> outerGlow = dark
        ? <BoxShadow>[
            BoxShadow(
              color: accent.withValues(alpha: 0.38),
              blurRadius: 12,
              spreadRadius: 0,
            ),
            BoxShadow(
              color: accent.withValues(alpha: 0.14),
              blurRadius: 22,
              spreadRadius: -4,
              offset: const Offset(0, 4),
            ),
          ]
        : const <BoxShadow>[];
    final Color iconTileBg = dark
        ? Color.alphaBlend(
            accent.withValues(alpha: 0.28),
            CityTheme.kDarkScaffold,
          )
        : Colors.white;
    final List<BoxShadow> iconShadows = dark
        ? <BoxShadow>[
            BoxShadow(
              color: accent.withValues(alpha: 0.22),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ]
        : const <BoxShadow>[
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ];
    final Color titleColor = dark ? cs.onSurface : accent;
    final Color descColor = dark ? cs.onSurfaceVariant : descriptionColor;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: outerGlow,
      ),
      child: Material(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          splashColor: accent.withValues(alpha: 0.12),
          highlightColor: accent.withValues(alpha: 0.08),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: borderColor, width: dark ? 1.25 : 1),
            ),
            child: Stack(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 36),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: iconTileBg,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: iconShadows,
                        ),
                        alignment: Alignment.center,
                        child: Icon(category.icon, size: 28, color: accent),
                      ),
                      const SizedBox(height: 10),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Text(
                          category.label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                            color: titleColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: Text(
                          category.description,
                          textAlign: TextAlign.center,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            height: 1.25,
                            color: descColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 24,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
