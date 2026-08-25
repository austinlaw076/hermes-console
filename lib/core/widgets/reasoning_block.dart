import 'package:flutter/material.dart';
import '../l10n/app_locale_resolve.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/markdown_clipboard.dart';

/// Bloque de razonamiento del asistente: discreto, plegado por defecto y
/// claramente separado de la respuesta final (estilo Claude/ChatGPT).
///
/// Recibe el texto de razonamiento ya extraído de `<think>…</think>` por
/// `splitReasoning`. Es solo presentación: no muta contenido ni lo persiste.
class ReasoningBlock extends StatefulWidget {
  /// Texto del razonamiento (sin etiquetas). Puede ir creciendo en streaming.
  final String reasoning;

  /// `true` mientras el modelo sigue razonando (apertura sin cierre).
  final bool inProgress;

  const ReasoningBlock({
    required this.reasoning,
    this.inProgress = false,
    super.key,
  });

  @override
  State<ReasoningBlock> createState() => _ReasoningBlockState();
}

class _ReasoningBlockState extends State<ReasoningBlock> {
  bool _expanded = false;

  AppLocaleKind get _kind =>
      AppLocaleResolve.fromLocale(Localizations.localeOf(context));

  String get _title {
    if (widget.inProgress) {
      return AppLocaleResolve.pick(
        _kind,
        es: 'Pensando…',
        en: 'Thinking…',
        zh: '思考中…',
      );
    }
    return AppLocaleResolve.pick(
      _kind,
      es: 'Razonamiento',
      en: 'Reasoning',
      zh: '推理',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    final displayReasoning = markdownToClipboardText(widget.reasoning).trim();
    final hasText = displayReasoning.isNotEmpty;
    // Mientras piensa sin texto aún, o si nunca hay texto, no es plegable.
    final expandable = hasText;
    final accent = widget.inProgress ? colors.accent : colors.textDisabled;

    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Cabecera fina, casi un separador: el detalle vive bajo demanda.
          Semantics(
            button: expandable,
            enabled: expandable,
            expanded: expandable ? _expanded : null,
            label: _title,
            excludeSemantics: true,
            child: InkWell(
              onTap: expandable
                  ? () => setState(() => _expanded = !_expanded)
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.psychology_alt_outlined,
                        size: 14,
                        color: accent,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        _title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.35,
                          color: widget.inProgress
                              ? colors.accent
                              : colors.textDisabled,
                        ),
                      ),
                      if (expandable) ...[
                        const SizedBox(width: 7),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: Motion.duration(context, Motion.fast),
                          child: Icon(
                            Icons.expand_more,
                            size: 15,
                            color: colors.textDisabled,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: Motion.duration(context, Motion.base),
            curve: Motion.size,
            child: (_expanded && hasText)
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
                    child: Text(
                      displayReasoning,
                      // Texto normal (no monoespaciado): el razonamiento es prosa.
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: colors.textSecondary,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
