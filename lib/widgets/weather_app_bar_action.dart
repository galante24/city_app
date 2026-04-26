import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../app_constants.dart';
import '../config/weather_config.dart';
import '../services/weather_service.dart';

IconData _weatherIconDataFromCode(String? icon) {
  final String i = icon ?? '';
  if (i.isEmpty) {
    return Icons.cloud_outlined;
  }
  if (i.contains('n') && i.startsWith('01')) {
    return Icons.nightlight_round;
  }
  if (i.startsWith('01')) {
    return Icons.wb_sunny;
  }
  if (i.startsWith('02') || i.startsWith('03') || i.startsWith('04')) {
    return Icons.wb_cloudy;
  }
  if (i.startsWith('09') || i.startsWith('10')) {
    return Icons.umbrella;
  }
  if (i.startsWith('11')) {
    return Icons.thunderstorm;
  }
  if (i.startsWith('13')) {
    return Icons.ac_unit;
  }
  if (i.startsWith('50')) {
    return Icons.blur_on;
  }
  return Icons.cloud_outlined;
}

/// Компактная кнопка погоды (иконка + °C) и bottom sheet с прогнозом.
class WeatherAppBarAction extends StatefulWidget {
  const WeatherAppBarAction({
    super.key,
    this.compact = false,
    this.onLightBackground = false,
  });

  /// В узком режиме без названия города (для симметрии заголовка AppBar).
  final bool compact;

  /// Светлая шапка (белый фон): иконки/индикатор в цвете [kPrimaryBlue].
  final bool onLightBackground;

  @override
  State<WeatherAppBarAction> createState() => _WeatherAppBarActionState();
}

class _WeatherAppBarActionState extends State<WeatherAppBarAction> {
  Future<WeatherCurrent?>? _currentFuture;
  @override
  void initState() {
    super.initState();
    if (WeatherService.hasApiKey) {
      _currentFuture = WeatherService.fetchCurrent();
    }
  }

  void _openSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return const _WeatherForecastSheet();
      },
    ).then((_) {
      if (!WeatherService.hasApiKey) {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _currentFuture = WeatherService.fetchCurrent();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!WeatherService.hasApiKey) {
      return IconButton(
        icon: const Icon(Icons.cloud_off, size: 22),
        tooltip: 'Погода недоступна',
        onPressed: () {
          showModalBottomSheet<void>(
            context: context,
            backgroundColor: Colors.transparent,
            builder: (BuildContext c) {
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Material(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                    bottom: Radius.circular(20),
                  ),
                  color: kNewsScaffoldBg,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const Text(
                          'Прогноз погоды',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Сейчас прогноз погоды недоступен. Попробуйте позже.',
                          style: TextStyle(
                            fontSize: 15,
                            color: kNewsTextPrimary,
                            height: 1.35,
                          ),
                        ),
                        if (kDebugMode) ...<Widget>[
                          const SizedBox(height: 12),
                          Text(
                            'Для разработчика: задайте OPENWEATHER_API_KEY при сборке '
                            '(dart-define или api_keys.json).',
                            style: TextStyle(
                              fontSize: 12,
                              color: kNewsTextSecondary,
                              height: 1.35,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('Закрыть'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    }

    return FutureBuilder<WeatherCurrent?>(
      future: _currentFuture,
      builder: (BuildContext context, AsyncSnapshot<WeatherCurrent?> snap) {
        final WeatherCurrent? c = snap.data;
        final bool loading =
            snap.connectionState == ConnectionState.waiting && !snap.hasData;
        final String tempText = c != null
            ? formatTempC(c.tempC)
            : (snap.hasError ||
                      (snap.connectionState == ConnectionState.done &&
                          c == null)
                  ? '—'
                  : '…');

        final bool compact = widget.compact;
        final bool lightBg = widget.onLightBackground;
        return Tooltip(
          message: 'Погода: $kWeatherCityNameRu (Open-Weather Map)',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openSheet,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 2 : 6,
                  vertical: compact ? 4 : 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (loading)
                      SizedBox(
                        width: compact ? 16 : 18,
                        height: compact ? 16 : 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: lightBg ? kPrimaryBlue : Colors.white,
                        ),
                      )
                    else
                      Icon(
                        c != null
                            ? _weatherIconDataFromCode(c.iconCode)
                            : Icons.cloud_outlined,
                        size: compact ? 18 : 20,
                        color: lightBg ? kPrimaryBlue : null,
                      ),
                    const SizedBox(width: 3),
                    Text(
                      tempText,
                      style: TextStyle(
                        fontSize: compact ? 12 : 13,
                        fontWeight: FontWeight.w600,
                        color: lightBg ? kPrimaryBlue : null,
                      ),
                    ),
                    if (!compact) ...<Widget>[
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 70),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            kWeatherCityNameRu,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color:
                                  (IconTheme.of(context).color ??
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurface)
                                      .withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Погода в шапке вкладки плюс опциональное действие справа (иконка, [IconButton] и т.д.).
class SoftHeaderWeatherWithAction extends StatelessWidget {
  const SoftHeaderWeatherWithAction({super.key, this.action});

  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.only(right: 4),
          child: WeatherAppBarAction(
            compact: true,
            onLightBackground: true,
          ),
        ),
        ?action,
      ],
    );
  }
}

const Color kNewsScaffoldBg = Color(0xFFF2F2F7);
const Color kNewsTextSecondary = Color(0xFF6C6C70);
const Color kNewsTextPrimary = Color(0xFF1C1C1E);

class _WeatherForecastSheet extends StatefulWidget {
  const _WeatherForecastSheet();

  @override
  State<_WeatherForecastSheet> createState() => _WeatherForecastSheetState();
}

class _WeatherForecastSheetState extends State<_WeatherForecastSheet> {
  late final Future<List<WeatherDayForecast>> _forecastFuture;

  @override
  void initState() {
    super.initState();
    _forecastFuture = WeatherService.fetchForecastDays(totalDays: 3);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (BuildContext context, ScrollController scroll) {
        return FutureBuilder<List<WeatherDayForecast>>(
          future: _forecastFuture,
          builder:
              (
                BuildContext context,
                AsyncSnapshot<List<WeatherDayForecast>> snap,
              ) {
                return Container(
                  decoration: const BoxDecoration(
                    color: kNewsScaffoldBg,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 16,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const SizedBox(height: 8),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: kNewsTextSecondary.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              Icons.location_on,
                              color: kPrimaryBlue,
                              size: 22,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              kWeatherCityNameRu,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: kNewsTextPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (snap.connectionState == ConnectionState.waiting)
                        const Expanded(
                          child: Center(
                            child: CircularProgressIndicator(
                              color: kPrimaryBlue,
                            ),
                          ),
                        )
                      else if (snap.hasError ||
                          snap.data == null ||
                          snap.data!.isEmpty)
                        Expanded(
                          child: Center(
                            child: Text(
                              'Не удалось загрузить прогноз',
                              style: TextStyle(
                                color: kNewsTextSecondary,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: ListView(
                            controller: scroll,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            children: <Widget>[
                              for (final WeatherDayForecast d in snap.data!)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Material(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    elevation: 0,
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 4,
                                          ),
                                      leading: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          openWeatherIconUrl(d.iconCode),
                                          width: 48,
                                          height: 48,
                                          fit: BoxFit.contain,
                                          errorBuilder:
                                              (
                                                _,
                                                Object error,
                                                StackTrace? stackTrace,
                                              ) {
                                                return Icon(
                                                  _weatherIconDataFromCode(
                                                    d.iconCode,
                                                  ),
                                                  size: 40,
                                                  color: kPrimaryBlue,
                                                );
                                              },
                                        ),
                                      ),
                                      title: Text(
                                        d.label,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: kNewsTextPrimary,
                                        ),
                                      ),
                                      subtitle: d.description.isNotEmpty
                                          ? Text(
                                              d.description,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: kNewsTextSecondary,
                                              ),
                                            )
                                          : null,
                                      trailing: Text(
                                        '${formatTempC(d.tempMinC)} / ${formatTempC(d.tempMaxC)}',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: kPrimaryBlue,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () => Navigator.pop(context),
                              style: FilledButton.styleFrom(
                                backgroundColor: kPrimaryBlue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Закрыть'),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
        );
      },
    );
  }
}
