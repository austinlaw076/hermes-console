import 'package:flutter/material.dart';

import '../../l10n/app_locale_resolve.dart';
import '../../widgets/hermes_spark_mascot.dart';
import '../models/companion_presence_level.dart';
import '../state/companion_controller.dart';
import '../state/companion_presence_controller.dart';
import 'companion_view.dart';

/// Presencia **mini y no invasiva** del Companion (feature 006): una mascota
/// pequeña (28–36 px) que refleja el ánimo de [CompanionPresenceController] y,
/// opcionalmente, un texto de estado ("Pensando…", "Esperando permiso…").
///
/// Reutiliza [CompanionView] (misma mascota activa/escala). Reglas:
/// - Si el Companion está **deshabilitado** → invisible (`SizedBox.shrink`).
/// - **reduce-motion**: el ánimo se sigue reflejando; el render no fuerza loops
///   nuevos (no se inyecta `replayToken` salvo en one-shots ya disparados).
/// - **Tap** → `petTapped` (saludo), sin abrir nada pesado (D6).
/// - No bloquea la UI subyacente más allá de su propia área.
class CompanionPresence extends StatelessWidget {
  final CompanionPresenceController presence;
  final CompanionController companion;

  /// Tamaño de la mascota mini (D5: 28–36 px).
  final double size;

  /// Muestra el texto de estado junto a la mascota (modo "completa").
  final bool showLabel;

  const CompanionPresence({
    super.key,
    required this.presence,
    required this.companion,
    this.size = 32,
    this.showLabel = false,
  });

  static String? labelFor(
    HermesSparkMood mood, [
    AppLocaleKind kind = AppLocaleKind.es,
  ]) {
    switch (mood) {
      case HermesSparkMood.thinking:
        return AppLocaleResolve.pick(
          kind,
          es: 'Pensando…',
          en: 'Thinking…',
          zh: '思考中…',
        );
      case HermesSparkMood.waiting:
        return AppLocaleResolve.pick(
          kind,
          es: 'Esperando permiso…',
          en: 'Waiting for permission…',
          zh: '等待權限…',
        );
      case HermesSparkMood.connecting:
        return AppLocaleResolve.pick(
          kind,
          es: 'Conectando…',
          en: 'Connecting…',
          zh: '連線中…',
        );
      case HermesSparkMood.offline:
        return AppLocaleResolve.pick(
          kind,
          es: 'Sin conexión',
          en: 'Offline',
          zh: '離線',
        );
      case HermesSparkMood.idle:
      case HermesSparkMood.success:
      case HermesSparkMood.error:
      case HermesSparkMood.jump:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([presence, companion]),
      builder: (context, _) {
        // Invisible si el Companion está apagado o el nivel de presencia es off.
        if (!companion.isInitialized ||
            !companion.enabled ||
            !companion.presenceLevel.isVisible) {
          return const SizedBox.shrink();
        }

        final mood = presence.mood;
        final mascot = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => presence.onEvent(PresenceEvent.petTapped),
          child: CompanionView(
            mood: mood,
            size: size,
            controller: companion,
            replayToken: presence.replayToken,
          ),
        );

        // El texto solo aparece en nivel "completa".
        if (!showLabel || !companion.presenceLevel.showsLabel) return mascot;
        final kind =
            AppLocaleResolve.fromLocale(Localizations.localeOf(context));
        final label = labelFor(mood, kind);
        if (label == null) return mascot;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            mascot,
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        );
      },
    );
  }
}
