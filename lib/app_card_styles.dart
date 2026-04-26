import 'package:flutter/material.dart';

/// Радиус «облачных» карточек (вакансии, заведения, новости, подработка, чаты).
const double kCloudCardRadius = 20;

/// Зазор между карточками в вертикальных списках (12–16).
const double kCloudListSpacing = 14;

Color cloudCardFillColor(BuildContext context) {
  final ThemeData t = Theme.of(context);
  if (t.brightness == Brightness.dark) {
    return t.colorScheme.surface;
  }
  return Colors.white;
}

List<BoxShadow> cloudCardBoxShadows(BuildContext context) {
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  return <BoxShadow>[
    BoxShadow(
      color: Colors.black.withValues(alpha: dark ? 0.32 : 0.08),
      blurRadius: 15,
      offset: const Offset(0, 6),
    ),
  ];
}

/// Единая декорация парящей карточки: белая подложка, лёгкая рамка, тень.
BoxDecoration cloudCardDecoration(
  BuildContext context, {
  double radius = kCloudCardRadius,
}) {
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: cloudCardFillColor(context),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: Colors.grey.withValues(alpha: dark ? 0.22 : 0.1),
      width: 1,
    ),
    boxShadow: cloudCardBoxShadows(context),
  );
}

/// Карточка с эффектом нажатия ([InkWell]) поверх [cloudCardDecoration].
class CloudInkCard extends StatelessWidget {
  const CloudInkCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.radius = kCloudCardRadius,
    this.padding,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final BorderRadius br = BorderRadius.circular(radius);
    return Container(
      decoration: cloudCardDecoration(context, radius: radius),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: br,
          child: padding != null
              ? Padding(padding: padding!, child: child)
              : child,
        ),
      ),
    );
  }
}
