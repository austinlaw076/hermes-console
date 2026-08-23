import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../models/interactive_prompt.dart';
import '../services/interactive_prompt_reducer.dart';
import '../theme/app_theme.dart';
import 'hermes_premium_ui.dart';

/// Inline tactile surface for Hermes Desktop 0.19 blocking requests.
///
/// Text controllers live only for this keyed card. Sensitive inputs are
/// cleared before invoking [onSubmit] and again during disposal; they never
/// enter restoration, preferences, transcript messages, or diagnostics.
class InteractivePromptCard extends StatefulWidget {
  final InteractivePromptEntry entry;
  final bool busy;
  final void Function(String value) onSubmit;
  final VoidCallback onCancel;

  const InteractivePromptCard({
    required this.entry,
    required this.busy,
    required this.onSubmit,
    required this.onCancel,
    super.key,
  });

  @override
  State<InteractivePromptCard> createState() => _InteractivePromptCardState();
}

class _InteractivePromptCardState extends State<InteractivePromptCard> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;

  InteractivePromptRequest get _request => widget.entry.request!;

  bool get _isTerminalRead =>
      _request.kind == InteractivePromptKind.terminalRead;

  void _submit([String? explicitValue]) {
    if (widget.busy) return;
    final value = explicitValue ?? _controller.text;
    if (!_isTerminalRead && value.trim().isEmpty) return;
    _controller.clear();
    widget.onSubmit(value);
  }

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    final strings = Strings.of(context);
    final request = _request;
    final title = switch (request.kind) {
      InteractivePromptKind.clarify => strings.interactiveClarifyTitle,
      InteractivePromptKind.sudo => strings.interactiveSudoTitle,
      InteractivePromptKind.secret => strings.interactiveSecretTitle,
      InteractivePromptKind.terminalRead => strings.interactiveTerminalTitle,
    };
    final icon = switch (request.kind) {
      InteractivePromptKind.clarify => Icons.help_outline_rounded,
      InteractivePromptKind.sudo => Icons.admin_panel_settings_outlined,
      InteractivePromptKind.secret => Icons.key_outlined,
      InteractivePromptKind.terminalRead => Icons.terminal_rounded,
    };

    return HermesInlineActivity(
      title: title,
      leading: Icon(icon, size: 20, color: colors.warning),
      status: widget.busy
          ? Semantics(
              label: strings.chaStatusWaiting,
              liveRegion: true,
              child: SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.warning,
                ),
              ),
            )
          : null,
      detail: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _requestBody(context, request, colors),
      ),
      actions: [
        TextButton.icon(
          onPressed: widget.busy ? null : widget.onCancel,
          icon: const Icon(Icons.stop_circle_outlined, size: 18),
          label: Text(strings.interactiveCancel),
        ),
        FilledButton.icon(
          onPressed: widget.busy ? null : _submit,
          icon: Icon(
            _isTerminalRead ? Icons.refresh_rounded : Icons.send_rounded,
            size: 17,
          ),
          label: Text(
            _isTerminalRead
                ? strings.interactiveRetry
                : strings.interactiveSend,
          ),
        ),
      ],
      semanticLabel: title,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
    );
  }

  List<Widget> _requestBody(
    BuildContext context,
    InteractivePromptRequest request,
    HermesThemeColors colors,
  ) {
    final strings = Strings.of(context);
    switch (request) {
      case ClarifyPromptRequest(:final question, :final choices):
        return [
          Text(
            question,
            style: TextStyle(color: colors.textPrimary, fontSize: 13),
          ),
          if (choices.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final choice in choices)
                  OutlinedButton(
                    onPressed: widget.busy ? null : () => _submit(choice),
                    child: Text(choice),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          _input(strings.interactiveAnswerHint, sensitive: false),
        ];
      case SudoPromptRequest():
        return [_input(strings.interactivePasswordHint, sensitive: true)];
      case SecretPromptRequest(:final envVar, :final prompt):
        return [
          Text(
            prompt,
            style: TextStyle(color: colors.textPrimary, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            envVar,
            style: TextStyle(
              color: colors.textSecondary,
              fontFamily: 'monospace',
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 10),
          _input(strings.interactiveSecretHint, sensitive: true),
        ];
      case TerminalReadPromptRequest():
        return [
          Text(
            strings.interactiveTerminalBody,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ];
    }
  }

  Widget _input(String hint, {required bool sensitive}) => TextField(
    controller: _controller,
    enabled: !widget.busy,
    obscureText: sensitive && _obscure,
    autocorrect: false,
    enableSuggestions: !sensitive,
    textInputAction: TextInputAction.send,
    onSubmitted: (_) => _submit(),
    decoration: InputDecoration(
      hintText: hint,
      isDense: true,
      suffixIcon: sensitive
          ? IconButton(
              onPressed: widget.busy
                  ? null
                  : () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            )
          : null,
    ),
  );
}
