import 'package:flutter/material.dart';

import '../../app_constants.dart';

/// Нижний фон + верхняя «шапка» с [ShaderMask] для плавного перехода.
///
/// Снаружи оберните в [AnimatedOpacity] (500 ms), если нужна смена с светлой темой.
class PortalHomeBackgroundStack extends StatelessWidget {
  const PortalHomeBackgroundStack({super.key});

  @override
  Widget build(BuildContext context) {
    final double w = MediaQuery.sizeOf(context).width;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Image.asset(
          kPortalAssetBgBottom,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
          errorBuilder:
              (BuildContext context, Object _, StackTrace? stackTrace) =>
                  const ColoredBox(
                    color: Color(0xFF141e33),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[Color(0xFF1a2744), Color(0xFF0d1525)],
                        ),
                      ),
                    ),
                  ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (Rect bounds) {
              return LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.white,
                  Colors.white,
                  Colors.white.withValues(alpha: 0),
                ],
                stops: const <double>[0, 0.5, 1],
              ).createShader(bounds);
            },
            child: Image.asset(
              kPortalAssetBgHeader,
              fit: BoxFit.fitWidth,
              width: w,
              alignment: Alignment.topCenter,
              filterQuality: FilterQuality.low,
              gaplessPlayback: true,
              errorBuilder:
                  (BuildContext context, Object _, StackTrace? stackTrace) =>
                      const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}
