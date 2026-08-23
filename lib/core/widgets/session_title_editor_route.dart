import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'hermes_premium_ui.dart';

/// Abre un editor de título como ruta modal propia.
///
/// No usa `showDialog`: desmontar un `EditableText` todavía enfocado desde el
/// overlay de un diálogo ha provocado `_dependents.isEmpty` en Android. La ruta
/// conserva el overlay estable del Navigator, libera el foco antes de cerrarse
/// y presenta visualmente una ventana flotante centrada.
Future<String?> showSessionTitleEditorRoute(
  BuildContext context, {
  required String initialTitle,
}) {
  return showHermesFloatingSurface<String>(
    context: context,
    surfaceKey: const ValueKey('session-title-editor-surface'),
    maxWidth: 420,
    builder: (_) => _SessionTitleEditor(initialTitle: initialTitle),
  );
}

class _SessionTitleEditor extends StatefulWidget {
  const _SessionTitleEditor({required this.initialTitle});

  final String initialTitle;

  @override
  State<_SessionTitleEditor> createState() => _SessionTitleEditorState();
}

class _SessionTitleEditorState extends State<_SessionTitleEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialTitle,
  );
  final FocusNode _focusNode = FocusNode();
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _close([String? result]) async {
    if (_closing) return;
    _closing = true;
    _focusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  void deactivate() {
    _focusNode.unfocus();
    super.deactivate();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.slRenameTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('session-title-editor-field'),
            controller: _controller,
            focusNode: _focusNode,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(labelText: strings.slRenameLabel),
            onSubmitted: (_) => _close(_controller.text),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(onPressed: _close, child: Text(strings.commonCancel)),
              FilledButton(
                onPressed: () => _close(_controller.text),
                child: Text(strings.slRenameSave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
