import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Aviso breve que flota sobre la pantalla actual sin bloquearla.
///
/// Se usa para eventos que llegan desde otra parte de la app (respuesta lista,
/// run terminado o aprobacion pendiente). El gesto horizontal solo descarta el
/// aviso visible; nunca resuelve ni modifica la accion remota que lo origino.
class HermesFloatingNotice extends StatelessWidget {
  const HermesFloatingNotice({
    required this.noticeKey,
    required this.icon,
    required this.tint,
    required this.title,
    required this.actionLabel,
    required this.dismissLabel,
    required this.onOpen,
    required this.onDismissed,
    this.body = '',
    super.key,
  });

  final Key noticeKey;
  final IconData icon;
  final Color tint;
  final String title;
  final String body;
  final String actionLabel;
  final String dismissLabel;
  final VoidCallback onOpen;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.hermes;
    final profile = theme.hermesComponents.profile;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final radius = profile.shape.cardRadius.clamp(16.0, 22.0);

    final notice = Dismissible(
      key: noticeKey,
      // Solo hacia el borde final: no compite con el gesto Android de volver
      // que nace en el borde inicial de la pantalla.
      direction: DismissDirection.endToStart,
      resizeDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 140),
      movementDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      confirmDismiss: (_) async {
        // El propietario retira el OverlayEntry de inmediato. Devolver false
        // evita que Dismissible intente reconstruirse ya marcado como borrado
        // durante el mismo frame en que desaparece el overlay.
        onDismissed();
        return false;
      },
      child: Semantics(
        container: true,
        button: true,
        label: body.trim().isEmpty ? title : '$title. $body',
        hint: actionLabel,
        child: Material(
          color: colors.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 14,
          shadowColor: Colors.black.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpen,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: colors.divider.withValues(alpha: 0.78),
                ),
                borderRadius: BorderRadius.circular(radius),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ColoredBox(color: tint, child: const SizedBox(width: 4)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                      child: Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tint.withValues(alpha: 0.13),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: tint, size: 20),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 11, 12, 11),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0,
                              ),
                            ),
                            if (body.trim().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.textSecondary,
                                  height: 1.3,
                                ),
                              ),
                            ],
                            const SizedBox(height: 7),
                            Row(
                              key: const ValueKey('floating-notice-action'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  actionLabel,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: tint,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  color: tint,
                                  size: 16,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      width: 52,
                      alignment: Alignment.topCenter,
                      decoration: BoxDecoration(
                        border: BorderDirectional(
                          start: BorderSide(
                            color: colors.divider.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                      child: IconButton(
                        key: const ValueKey('floating-notice-dismiss'),
                        onPressed: onDismissed,
                        tooltip: dismissLabel,
                        constraints: const BoxConstraints.tightFor(
                          width: 48,
                          height: 48,
                        ),
                        icon: Icon(
                          Icons.close_rounded,
                          color: colors.textSecondary,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (reduceMotion) return notice;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: notice,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, -12 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}
