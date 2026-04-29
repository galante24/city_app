import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/weather_service.dart' show WeatherCurrent, formatTempC;

/// Иконка по полю `weather[0].main` OpenWeather.
IconData portalWeatherIconFromMain(String? main) {
  final String m = (main ?? 'Clouds').toUpperCase();
  if (m == 'CLEAR') {
    return Icons.wb_sunny;
  }
  if (m.contains('CLOUD')) {
    return Icons.cloud_outlined;
  }
  if (m.contains('RAIN')) {
    return Icons.umbrella;
  }
  if (m.contains('DRIZZLE')) {
    return Icons.grain;
  }
  if (m.contains('THUNDER')) {
    return Icons.thunderstorm;
  }
  if (m.contains('SNOW')) {
    return Icons.ac_unit;
  }
  if (m.contains('MIST') ||
      m.contains('FOG') ||
      m.contains('HAZE') ||
      m.contains('SMOKE') ||
      m.contains('DUST')) {
    return Icons.blur_on;
  }
  return Icons.cloud_outlined;
}

/// Плашка погоды: правый верх, Montserrat w300, лёгкая тень.
class PortalHomeWeatherCorner extends StatelessWidget {
  const PortalHomeWeatherCorner({
    super.key,
    required this.future,
    required this.darkForeground,
  });

  final Future<WeatherCurrent?>? future;
  final bool darkForeground;

  static List<Shadow>? _textShadow(bool dark) {
    if (!dark) {
      return <Shadow>[
        Shadow(
          color: Colors.black.withValues(alpha: 0.12),
          offset: const Offset(0, 1),
          blurRadius: 2,
        ),
      ];
    }
    return const <Shadow>[
      Shadow(color: Color(0x66000000), offset: Offset(0, 1), blurRadius: 4),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final double top = MediaQuery.paddingOf(context).top + 10;
    final Color fg = darkForeground ? Colors.white : const Color(0xFF2C2C2E);
    final TextStyle textStyle = GoogleFonts.montserrat(
      fontSize: 15,
      fontWeight: FontWeight.w300,
      color: fg,
      shadows: _textShadow(darkForeground),
    );

    if (future == null) {
      return Positioned(
        top: top,
        right: 16,
        child: Icon(Icons.cloud_off_outlined, color: fg, size: 22),
      );
    }

    return Positioned(
      top: top,
      right: 16,
      child: FutureBuilder<WeatherCurrent?>(
        future: future,
        builder: (BuildContext context, AsyncSnapshot<WeatherCurrent?> snap) {
          final bool wait =
              snap.connectionState == ConnectionState.waiting && !snap.hasData;
          final WeatherCurrent? c = snap.data;
          final IconData icon = wait
              ? Icons.cloud_outlined
              : portalWeatherIconFromMain(c?.main);
          final String temp = c != null
              ? formatTempC(c.tempC)
              : (wait ? '…' : '—');

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: fg, size: 26),
              const SizedBox(width: 6),
              Text(temp, style: textStyle),
            ],
          );
        },
      ),
    );
  }
}
