import 'package:flutter/material.dart';

import '../app_constants.dart';
import 'lesosibirsk_bus_static_data.dart';

const Color _kTextPrimary = Color(0xFF1C1C1E);
const Color _kTextSecondary = Color(0xFF6C6C70);
const Color _kCardBg = Color(0xFFFFFFFF);

/// Цвета блока автобусов: в тёмной теме — [ColorScheme], иначе фиксированные светлые.
final class _BusUiColors {
  _BusUiColors(this.context);

  final BuildContext context;

  ColorScheme get cs => Theme.of(context).colorScheme;

  bool get dark => Theme.of(context).brightness == Brightness.dark;

  Color get cardBg => dark ? cs.surface : _kCardBg;

  Color get textPrimary => dark ? cs.onSurface : _kTextPrimary;

  Color get textSecondary => dark ? cs.onSurfaceVariant : _kTextSecondary;

  Color get chipUnselectedBg =>
      dark ? cs.surfaceContainerLow : const Color(0xFFF2F2F7);

  Color get chipTimeBg =>
      dark ? cs.surfaceContainerHigh : const Color(0xFFF2F2F7);
}

class LesosibirskBusesSection extends StatelessWidget {
  const LesosibirskBusesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final List<SimpleBusRoute> others = lesosibirskOtherBusRoutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: const _Route7ListTile(),
        ),
        ...others.map(
          (SimpleBusRoute r) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SimpleRouteTile(route: r),
          ),
        ),
      ],
    );
  }
}

class _Route7ListTile extends StatelessWidget {
  const _Route7ListTile();

  static const String _title = 'Военкомат — Новоенисейск';

  @override
  Widget build(BuildContext context) {
    final _BusUiColors u = _BusUiColors(context);
    final String? hours = lesosibirskRoute7WorkHoursLabel;
    return Material(
      color: u.cardBg,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: () => _Route7DetailSheet.open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: kLesosibirskRoute7Color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.directions_bus_filled,
                  color: kLesosibirskRoute7Color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '№ 7',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: u.textSecondary,
                      ),
                    ),
                    Text(
                      _title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: u.textPrimary,
                        height: 1.2,
                      ),
                    ),
                    if (hours != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          hours,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: u.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Route7DetailSheet {
  static void open(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext c) {
        final _BusUiColors sheetU = _BusUiColors(c);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.92,
          minChildSize: 0.35,
          builder: (BuildContext _, ScrollController sc) {
            return ListView(
              controller: sc,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: <Widget>[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: <Widget>[
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: kLesosibirskRoute7Color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.directions_bus_filled,
                        color: kLesosibirskRoute7Color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '№ 7  ${_Route7ListTile._title}',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: sheetU.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (lesosibirskRoute7WorkHoursLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    child: Text(
                      lesosibirskRoute7WorkHoursLabel!,
                      style: TextStyle(
                        color: sheetU.textSecondary,
                        fontSize: 15,
                      ),
                    ),
                  ),
                const _Route7ScheduleExpandable(),
              ],
            );
          },
        );
      },
    );
  }
}

class _Route7ScheduleExpandable extends StatefulWidget {
  const _Route7ScheduleExpandable();

  @override
  State<_Route7ScheduleExpandable> createState() =>
      _Route7ScheduleExpandableState();
}

class _Route7ScheduleExpandableState extends State<_Route7ScheduleExpandable> {
  int _dir = 0;

  @override
  Widget build(BuildContext context) {
    final _BusUiColors u = _BusUiColors(context);
    final String leftA =
        _dir == 0 ? 'Военкомат' : 'Микрорайон «А»';
    const String rightB = 'Спорткомплекс';
    final List<String> leftT =
        _dir == 0 ? route7NorthVoen : route7SouthMkr;
    final List<String> rightT =
        _dir == 0 ? route7NorthSport : route7SouthSport;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _DirChip(
                label: 'Северное\nнаправление',
                selected: _dir == 0,
                arrowColor: const Color(0xFF27AE60),
                icon: Icons.north_east,
                onTap: () => setState(() => _dir = 0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DirChip(
                label: 'Южное\nнаправление',
                selected: _dir == 1,
                arrowColor: kPrimaryBlue,
                icon: Icons.south_west,
                onTap: () => setState(() => _dir = 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _StopTimes(name: leftA, times: leftT),
        const SizedBox(height: 20),
        _StopTimes(name: rightB, times: rightT),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            'Время отправления с остановок «$leftA» и «$rightB» '
            'в выбранном направлении.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: u.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _DirChip extends StatelessWidget {
  const _DirChip({
    required this.label,
    required this.selected,
    required this.arrowColor,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final Color arrowColor;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final _BusUiColors u = _BusUiColors(context);
    return Material(
      color: selected
          ? kPrimaryBlue.withValues(alpha: 0.1)
          : u.chipUnselectedBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 18, color: arrowColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? kPrimaryBlue : u.textSecondary,
                    height: 1.2,
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

class _SimpleRouteTile extends StatelessWidget {
  const _SimpleRouteTile({required this.route});
  final SimpleBusRoute route;

  @override
  Widget build(BuildContext context) {
    final _BusUiColors u = _BusUiColors(context);
    return Material(
      color: u.cardBg,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: () => _openRouteDetail(context, route),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: route.color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.directions_bus_filled,
                  color: route.color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '№ ${route.number}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: u.textSecondary,
                      ),
                    ),
                    Text(
                      route.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: u.textPrimary,
                        height: 1.2,
                      ),
                    ),
                    if (route.workHoursLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          route.workHoursLabel!,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: u.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openRouteDetail(BuildContext context, SimpleBusRoute r) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext c) {
        final _BusUiColors sheetU = _BusUiColors(c);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.92,
          minChildSize: 0.35,
          builder: (BuildContext _, ScrollController sc) {
            return ListView(
              controller: sc,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: <Widget>[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: <Widget>[
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: r.color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.directions_bus_filled,
                        color: r.color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '№ ${r.number}  ${r.title}',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: sheetU.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (r.workHoursLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 16),
                    child: Text(
                      r.workHoursLabel!,
                      style: TextStyle(
                        color: sheetU.textSecondary,
                        fontSize: 15,
                      ),
                    ),
                  ),
                _StopTimes(
                  name: r.labelA,
                  times: r.timesA,
                ),
                const SizedBox(height: 20),
                _StopTimes(
                  name: r.labelB,
                  times: r.timesB,
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _StopTimes extends StatelessWidget {
  const _StopTimes({required this.name, required this.times});
  final String name;
  final List<String> times;

  @override
  Widget build(BuildContext context) {
    final _BusUiColors u = _BusUiColors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          name,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: kPrimaryBlue,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: times
              .map(
                (String t) => Chip(
                  label: Text(t),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: u.chipTimeBg,
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
