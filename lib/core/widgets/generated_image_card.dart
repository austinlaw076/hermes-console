import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'attachment_card.dart';

/// Estado de una imagen generada dentro de la burbuja del asistente (spec 030).
enum GeneratedImageStatus {
  /// Descarga en curso.
  downloading,

  /// Archivo local listo: se muestra la miniatura.
  ready,

  /// Descarga fallida (red/token) — reintentable manualmente.
  error,

  /// El servidor respondió que ya no existe (caché rotada) — sin reintento.
  gone,

  /// El bridge no soporta la descarga (versión < 1.12.0 o sin bridge):
  /// pista de degradación, el texto del mensaje queda intacto (US2).
  unsupported,
}

/// Tarjeta de imagen generada por el agente: miniatura + visor a pantalla
/// completa, o el estado que toque (descargando / error con Reintentar /
/// no disponible / pista de bridge desactualizado). Sin reintentos
/// automáticos: el único disparador de red tras un fallo es el usuario.
class GeneratedImageCard extends StatelessWidget {
  final GeneratedImageStatus status;

  /// Archivo local descargado (requerido cuando [status] es [GeneratedImageStatus.ready]).
  final File? file;

  /// Reintentar la descarga (solo estado [GeneratedImageStatus.error]).
  final VoidCallback? onRetry;

  const GeneratedImageCard({
    required this.status,
    this.file,
    this.onRetry,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    final s = Strings.of(context);
    final child = switch (status) {
      GeneratedImageStatus.ready => _thumbnail(context, s),
      GeneratedImageStatus.downloading => _statusCard(
        context,
        colors,
        leading: SizedBox(
          width: 15,
          height: 15,
          child: CircularProgressIndicator(
            strokeWidth: 1.8,
            color: colors.accent,
          ),
        ),
        text: s.genImgDownloading,
      ),
      GeneratedImageStatus.error => _statusCard(
        context,
        colors,
        leading: Icon(
          Icons.broken_image_outlined,
          size: 17,
          color: colors.warning,
        ),
        text: s.genImgError,
        trailing: TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 40),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          child: Text(
            s.commonRetry,
            style: TextStyle(fontSize: 12, color: colors.accentText),
          ),
        ),
      ),
      GeneratedImageStatus.gone => _statusCard(
        context,
        colors,
        leading: Icon(
          Icons.hide_image_outlined,
          size: 17,
          color: colors.textSecondary,
        ),
        text: s.genImgGone,
      ),
      GeneratedImageStatus.unsupported => _statusCard(
        context,
        colors,
        leading: Icon(
          Icons.image_outlined,
          size: 17,
          color: colors.textSecondary,
        ),
        text: s.genImgHint,
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Align(alignment: Alignment.centerLeft, child: child),
    );
  }

  Widget _thumbnail(BuildContext context, Strings s) {
    final theme = Theme.of(context);
    final colors = theme.hermes;
    final radius = theme.hermesComponents.profile.shape.cardRadius;
    final f = file!;
    return Semantics(
      label: s.genImgSemanticLabel,
      image: true,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showImageViewer(context, f),
        child: Material(
          key: const ValueKey('generated-image-thumbnail'),
          color: colors.surfaceVariant.withValues(alpha: 0.28),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: BorderSide(color: colors.divider.withValues(alpha: 0.55)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 232, maxHeight: 232),
            child: ColoredBox(
              // Garantiza que toda la miniatura, incluidas zonas transparentes
              // del bitmap, sea una superficie táctil y no solo decorativa.
              color: Colors.transparent,
              child: Stack(
                children: [
                  Image.file(
                    f,
                    fit: BoxFit.contain,
                    width: 232,
                    // Decodifica a tamaño de miniatura: una imagen generada
                    // puede ser grande y no hace falta el bitmap completo aquí.
                    cacheWidth: 464,
                    errorBuilder: (ctx, _, _) => _statusCard(
                      ctx,
                      Theme.of(ctx).hermes,
                      leading: Icon(
                        Icons.broken_image_outlined,
                        size: 17,
                        color: Theme.of(ctx).hermes.warning,
                      ),
                      text: Strings.of(ctx).genImgError,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IgnorePointer(
                      child: Container(
                        key: const ValueKey('generated-image-expand'),
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.58),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.open_in_full_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusCard(
    BuildContext context,
    HermesThemeColors colors, {
    required Widget leading,
    required String text,
    Widget? trailing,
  }) {
    final radius = Theme.of(context).hermesComponents.profile.shape.cardRadius;
    return Container(
      key: const ValueKey('generated-image-status'),
      constraints: const BoxConstraints(maxWidth: 320),
      padding: EdgeInsets.fromLTRB(
        10,
        trailing == null ? 8 : 4,
        8,
        trailing == null ? 8 : 4,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceVariant.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: colors.divider.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 8),
          Flexible(
            child: Padding(
              padding: EdgeInsets.only(
                top: trailing == null ? 0 : 6,
                bottom: trailing == null ? 0 : 6,
              ),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
