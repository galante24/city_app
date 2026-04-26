import 'package:flutter/material.dart';

import '../app_constants.dart';

/// Тёмно-синий заголовок в стиле «мягкого» таба.
const Color kSoftHeaderTitleColor = Color(0xFF0D1B2A);

Color get kSoftHeaderActionIconColor => kPrimaryBlue.withValues(alpha: 0.88);

const double kSoftHeaderBottomRadius = 24;

/// Шапка вкладки: белый блок с скруглением снизу, жирный заголовок, синяя точка,
/// линия с градиентом, опциональная область снизу (например TabBar).
class SoftTabHeader extends StatelessWidget {
  const SoftTabHeader({
    super.key,
    required this.title,
    this.trailing,
    this.bottom,
  });

  final String title;
  final Widget? trailing;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final double topInset = MediaQuery.paddingOf(context).top;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(kSoftHeaderBottomRadius),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF0A0A0A).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(
          top: topInset + 8,
          left: 20,
          right: 4,
          bottom: bottom == null ? 18 : 8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: kSoftHeaderTitleColor,
                                letterSpacing: -0.6,
                                height: 1.05,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: const BoxDecoration(
                              color: Color(0xFF2196F3),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const _HeaderUnderline(),
                    ],
                  ),
                ),
                if (trailing != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 4),
                    child: trailing!,
                  ),
              ],
            ),
            if (bottom != null) ...<Widget>[
              const SizedBox(height: 4),
              bottom!,
            ],
          ],
        ),
      ),
    );
  }
}

class _HeaderUnderline extends StatelessWidget {
  const _HeaderUnderline();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 168,
        height: 3,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          gradient: LinearGradient(
            colors: <Color>[
              kPrimaryBlue,
              kPrimaryBlue.withValues(alpha: 0.35),
              kPrimaryBlue.withValues(alpha: 0),
            ],
            stops: const <double>[0, 0.42, 1],
          ),
        ),
      ),
    );
  }
}
