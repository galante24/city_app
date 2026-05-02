import 'package:flutter/material.dart';

import '../app_constants.dart';
import '../theme/city_theme.dart' show CityTheme;

/// Цвет иконки «назад» / действий у чистого заголовка.
Color cleanHeaderIconColor(BuildContext context) {
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  return dark ? CityTheme.kDarkNavIconMuted : kPineGreen;
}

/// Заголовок экрана без «таблетки», точки и полоски — текст над фоном.
class CleanFloatingHeader extends StatelessWidget {
  const CleanFloatingHeader({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
    this.bottom,
  });

  final String title;
  final Widget? leading;
  final Widget? trailing;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color titleColor = dark ? Colors.white : kPineGreen;
    final double topInset = MediaQuery.paddingOf(context).top;
    final bool hasLeading = leading != null;
    return Padding(
      padding: EdgeInsets.only(
        top: topInset + 8,
        left: hasLeading ? 4 : 20,
        right: 8,
        bottom: bottom == null ? 14 : 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (hasLeading) leading!,
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                    letterSpacing: -0.6,
                    height: 1.05,
                  ),
                ),
              ),
              if (trailing != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 4),
                  child: trailing!,
                ),
            ],
          ),
          if (bottom != null) ...<Widget>[const SizedBox(height: 6), bottom!],
        ],
      ),
    );
  }
}
