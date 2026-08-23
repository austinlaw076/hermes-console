import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/reasoning_block.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

/// Verifica que el razonamiento (`<think>…`) se renderiza como bloque discreto
/// y separado de la respuesta final, por la ruta real ([AssistantMarkdownView]).
void main() {
  Widget host(String data, {bool isStreaming = false}) {
    return MaterialApp(
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      locale: const Locale('es'),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.hermesRedDark,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: AssistantMarkdownView(data: data, isStreaming: isStreaming),
          ),
        ),
      ),
    );
  }

  testWidgets('separa el razonamiento de la respuesta y oculta la etiqueta', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        '<think>El usuario pregunta la hora. Calculo y respondo.</think>'
        'Son las tres de la tarde.',
      ),
    );
    // El bloque de razonamiento existe (plegado) y la respuesta es visible.
    expect(find.byType(ReasoningBlock), findsOneWidget);
    expect(find.text('Razonamiento'), findsOneWidget);
    expect(find.textContaining('Son las tres'), findsOneWidget);
    // La etiqueta cruda nunca debe verse y, plegado, tampoco el razonamiento.
    expect(find.textContaining('<think>'), findsNothing);
    expect(find.textContaining('El usuario pregunta'), findsNothing);
  });

  testWidgets('al expandir muestra el texto del razonamiento', (tester) async {
    await tester.pumpWidget(host('<think>Paso 1. Paso 2.</think>Hecho.'));
    await tester.tap(find.byType(ReasoningBlock));
    await tester.pumpAndSettle();
    expect(find.textContaining('Paso 1. Paso 2.'), findsOneWidget);
  });

  testWidgets('streaming: <think> abierto muestra estado "Pensando…"', (
    tester,
  ) async {
    await tester.pumpWidget(
      host('<think>sigo razonando sobre la respuesta', isStreaming: true),
    );
    expect(find.byType(ReasoningBlock), findsOneWidget);
    expect(find.text('Pensando…'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('el disclosure de razonamiento conserva 48 dp', (tester) async {
    await tester.pumpWidget(
      host('<think>Paso publicado.</think>Respuesta final.'),
    );

    final disclosure = find.descendant(
      of: find.byType(ReasoningBlock),
      matching: find.byType(InkWell),
    );
    expect(disclosure, findsOneWidget);
    expect(tester.getSize(disclosure).height, greaterThanOrEqualTo(48));
  });

  testWidgets('detalle limpia Markdown y anuncia el estado del disclosure', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        '<think>## Plan\n\n- **Paso** `uno`</think>'
        'Respuesta final.',
      ),
    );

    Semantics disclosureSemantics() => tester
        .widgetList<Semantics>(
          find.descendant(
            of: find.byType(ReasoningBlock),
            matching: find.byType(Semantics),
          ),
        )
        .singleWhere((widget) => widget.properties.label == 'Razonamiento');

    expect(disclosureSemantics().properties.expanded, isFalse);
    await tester.tap(find.text('Razonamiento'));
    await tester.pumpAndSettle();

    expect(disclosureSemantics().properties.expanded, isTrue);
    expect(find.textContaining('Plan'), findsOneWidget);
    expect(find.textContaining('Paso'), findsOneWidget);
    expect(find.textContaining('uno'), findsOneWidget);
    expect(find.textContaining('##'), findsNothing);
    expect(find.textContaining('**'), findsNothing);
    expect(find.textContaining('`'), findsNothing);
  });

  testWidgets('sin razonamiento no se renderiza el bloque', (tester) async {
    await tester.pumpWidget(host('Respuesta normal sin razonamiento.'));
    expect(find.byType(ReasoningBlock), findsNothing);
    expect(find.textContaining('Respuesta normal'), findsOneWidget);
  });
}
