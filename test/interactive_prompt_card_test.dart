import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/interactive_prompt.dart';
import 'package:hermes_android/core/services/interactive_prompt_reducer.dart';
import 'package:hermes_android/core/widgets/accent_card.dart';
import 'package:hermes_android/core/widgets/hermes_premium_ui.dart';
import 'package:hermes_android/core/widgets/interactive_prompt_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

InteractivePromptEntry _entry(InteractivePromptRequest request) =>
    InteractivePromptEntry(
      key: request.key,
      request: request,
      status: InteractivePromptStatus.pending,
    );

Widget _app(
  InteractivePromptEntry entry,
  void Function(String) onSubmit, {
  bool busy = false,
  VoidCallback? onCancel,
  TextScaler textScaler = TextScaler.noScaling,
}) => MaterialApp(
  locale: const Locale('es'),
  localizationsDelegates: const [
    Strings.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: Strings.supportedLocales,
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(size: const Size(390, 844), textScaler: textScaler),
      child: InteractivePromptCard(
        entry: entry,
        busy: busy,
        onSubmit: onSubmit,
        onCancel: onCancel ?? () {},
      ),
    ),
  ),
);

void main() {
  testWidgets('secret se oculta y se limpia antes del callback', (
    tester,
  ) async {
    final key = InteractivePromptKey(
      runtimeSessionId: 'runtime-a',
      requestId: 'secret-a',
    );
    String? submitted;
    await tester.pumpWidget(
      _app(
        _entry(
          SecretPromptRequest(
            key: key,
            envVar: 'DEPLOY_TOKEN',
            prompt: 'Introduce el token',
          ),
        ),
        (value) => submitted = value,
      ),
    );

    expect(find.byType(HermesInlineActivity), findsOneWidget);
    expect(find.byType(AccentCard), findsNothing);
    const value = 'widget-secret-value';
    await tester.enterText(find.byType(TextField), value);
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isTrue,
    );
    await tester.tap(find.text('Enviar'));
    await tester.pump();

    expect(submitted, value);
    expect(find.text(value), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
    submitted = null;
  });

  testWidgets('cancelar conserva el callback y busy bloquea toda respuesta', (
    tester,
  ) async {
    final key = InteractivePromptKey(
      runtimeSessionId: 'runtime-a',
      requestId: 'busy-a',
    );
    var cancelled = false;
    String? submitted;
    await tester.pumpWidget(
      _app(
        _entry(
          ClarifyPromptRequest(
            key: key,
            question: '¿Qué rama?',
            choices: const ['main'],
          ),
        ),
        (value) => submitted = value,
        busy: true,
        onCancel: () => cancelled = true,
      ),
    );

    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Detener tarea'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Enviar'))
          .onPressed,
      isNull,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.text('main'));
    await tester.tap(find.text('Detener tarea'));
    await tester.tap(find.text('Enviar'));
    await tester.pump();

    expect(submitted, isNull);
    expect(cancelled, isFalse);
  });

  testWidgets('clarify permite responder con una opción sin escribir', (
    tester,
  ) async {
    final key = InteractivePromptKey(
      runtimeSessionId: 'runtime-a',
      requestId: 'clarify-a',
    );
    String? submitted;
    await tester.pumpWidget(
      _app(
        _entry(
          ClarifyPromptRequest(
            key: key,
            question: '¿Qué rama?',
            choices: const ['main', 'qa'],
          ),
        ),
        (value) => submitted = value,
      ),
    );

    await tester.tap(find.text('qa'));
    await tester.pump();
    expect(submitted, 'qa');
  });

  testWidgets('terminal read explica la política y reintenta vacío', (
    tester,
  ) async {
    final key = InteractivePromptKey(
      runtimeSessionId: 'runtime-a',
      requestId: 'terminal-a',
    );
    String? submitted;
    await tester.pumpWidget(
      _app(
        _entry(TerminalReadPromptRequest(key: key)),
        (value) => submitted = value,
      ),
    );

    expect(find.textContaining('no posee una terminal'), findsOneWidget);
    await tester.tap(find.text('Reintentar respuesta segura'));
    await tester.pump();
    expect(submitted, isEmpty);
  });

  testWidgets('acciones mantienen 48 dp y escala 2 no desborda', (
    tester,
  ) async {
    final key = InteractivePromptKey(
      runtimeSessionId: 'runtime-a',
      requestId: 'scale-a',
    );
    await tester.pumpWidget(
      _app(
        _entry(TerminalReadPromptRequest(key: key)),
        (_) {},
        textScaler: const TextScaler.linear(2),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.widgetWithText(TextButton, 'Detener tarea')).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester
          .getSize(
            find.widgetWithText(FilledButton, 'Reintentar respuesta segura'),
          )
          .height,
      greaterThanOrEqualTo(48),
    );
  });
}
