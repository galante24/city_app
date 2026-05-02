import 'package:flutter/material.dart';

import 'clean_screen_header.dart' show cleanHeaderIconColor;

/// Для иконок справа у шапок: согласовано с чистым заголовком.
Color softHeaderTrailingIconColor(BuildContext context) =>
    cleanHeaderIconColor(context);

const double kSoftHeaderBottomRadius = 24;

/// Кнопка «назад» для вторичных экранов в том же стиле, что и [SoftTabHeader].
class SoftHeaderBackButton extends StatelessWidget {
  const SoftHeaderBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_rounded, size: 26),
      color: cleanHeaderIconColor(context),
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      tooltip: 'Назад',
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Шапка вкладки: блок с скруглением снизу, жирный заголовок, точка, градиент.
///
/// Экраны из [Navigator.push]: [leading] — обычно [SoftHeaderBackButton],
/// справа — [SoftHeaderWeatherWithAction] или иконка действия.
class SoftTabHeader extends StatelessWidget {
  const SoftTabHeader({
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
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final double topInset = MediaQuery.paddingOf(context).top;
    final bool hasLeading = leading != null;
    final Color headerBg = isDark ? cs.surfaceContainerHigh : cs.surface;
    final Color titleColor = cs.onSurface;
    final Color shadow = isDark
        ? Colors.black.withValues(alpha: 0.35)
        : const Color(0xFF0A0A0A).withValues(alpha: 0.06);
    return Container(
      decoration: BoxDecoration(
        color: headerBg,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(kSoftHeaderBottomRadius),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: shadow,
            blurRadius: isDark ? 10 : 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(
          top: topInset + 8,
          left: hasLeading ? 4 : 20,
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
                if (hasLeading) leading!,
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
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: titleColor,
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
                            decoration: BoxDecoration(
                              color: cs.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _HeaderUnderline(color: cs.primary, thick: isDark),
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
            if (bottom != null) ...<Widget>[const SizedBox(height: 4), bottom!],
          ],
        ),
      ),
    );
  }
}

class _HeaderUnderline extends StatelessWidget {
  const _HeaderUnderline({required this.color, this.thick = false});

  final Color color;
  final bool thick;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: thick ? 184 : 168,
        height: thick ? 4 : 3,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          gradient: LinearGradient(
            colors: <Color>[
              color,
              color.withValues(alpha: 0.35),
              color.withValues(alpha: 0),
            ],
            stops: const <double>[0, 0.42, 1],
          ),
        ),
      ),
    );
  }
}
