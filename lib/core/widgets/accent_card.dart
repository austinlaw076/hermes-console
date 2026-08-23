import 'package:flutter/material.dart';

/// Card container with rounded corners, an optional uniform hairline border
/// and an optional colored accent strip hugging the left edge.
///
/// Flutter cannot paint a [BoxDecoration] that combines `borderRadius` with a
/// non-uniform [Border] whose sides differ in color: the box paints its
/// background, then aborts before painting the border and the child, leaving
/// a blank card. Any card that wants the "amber left edge" look must render
/// the strip as a child (done here with a clipped [Stack]) instead of using
/// `Border(left: ...)`.
class AccentCard extends StatelessWidget {
  final Color? accent;
  final double accentWidth;
  final Color? background;
  final Color? borderColor;
  final BorderRadius borderRadius;
  final List<BoxShadow>? boxShadow;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final Widget child;

  const AccentCard({
    super.key,
    this.accent,
    this.accentWidth = 2,
    this.background,
    this.borderColor,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.boxShadow,
    this.margin,
    this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final padded = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: background,
        borderRadius: borderRadius,
        border: borderColor != null ? Border.all(color: borderColor!) : null,
        boxShadow: boxShadow,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: accent == null
            ? padded
            : Stack(
                children: [
                  padded,
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: accentWidth,
                    child: ColoredBox(color: accent!),
                  ),
                ],
              ),
      ),
    );
  }
}
