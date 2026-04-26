import 'package:flutter/material.dart';

import '../app_constants.dart';

/// Заголовок секции в стиле «Сервисы»: крупный текст, синяя точка, градиентная линия.
class PlacesSectionHeader extends StatelessWidget {
  const PlacesSectionHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: kPrimaryBlue,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                  letterSpacing: -0.6,
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 14),
        const PlacesGradientDivider(),
        const SizedBox(height: 18),
      ],
    );
  }
}

class PlacesGradientDivider extends StatelessWidget {
  const PlacesGradientDivider({super.key, this.height = 2});

  final double height;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                kPrimaryBlue.withValues(alpha: 0.15),
                kPrimaryBlue,
                cs.tertiary.withValues(alpha: 0.85),
                kPrimaryBlue.withValues(alpha: 0.12),
              ],
              stops: const <double>[0.0, 0.35, 0.72, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

/// Карточка-блок для группы кнопок модератора.
class PlacesModeratorActionCard extends StatelessWidget {
  const PlacesModeratorActionCard({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: kPrimaryBlue.withValues(alpha: 0.22),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
