import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/utils/assistant_suggestions.dart';
import 'package:hermes_android/core/widgets/hermes_suggestions.dart';

void main() {
  test('proyecta solo el cierre explicito y limpia el conector suelto', () {
    final projection = projectAssistantSuggestions('''
Resumen con una lista normal:
1. Primer hecho
2. Segundo hecho

Si quieres, te lo convierto en:
- **versión corta (10 minutos de lectura)**,
- **versión por regiones (Madrid/Cataluña/Andalucía...)**, o
- solo “hechos duros” sin contexto político/cultural.
''');

    expect(projection.body, contains('1. Primer hecho'));
    expect(projection.body, isNot(contains('Si quieres')));
    expect(projection.suggestions, [
      'versión corta (10 minutos de lectura)',
      'versión por regiones (Madrid/Cataluña/Andalucía...)',
      'solo “hechos duros” sin contexto político/cultural',
    ]);
  });

  test('no interpreta una lista normal y acepta un cierre con una opcion', () {
    final normal = projectAssistantSuggestions('- uno\n- dos\n- tres');
    final one = projectAssistantSuggestions(
      'Texto\n\nSi quieres, puedo:\n- resumirlo',
    );

    expect(normal.hasSuggestions, isFalse);
    expect(normal.body, '- uno\n- dos\n- tres');
    expect(one.body, 'Texto');
    expect(one.suggestions, ['resumirlo']);
  });

  test('retira un conector suelto entre las opciones', () {
    final projection = projectAssistantSuggestions('''
Texto

Si te sirve, puedo dejarlo como:
— resumen ejecutivo
.o
— lista de tareas
''');

    expect(projection.body, 'Texto');
    expect(projection.suggestions, ['resumen ejecutivo', 'lista de tareas']);
  });

  test('acepta cierres explícitos alternativos sin tocar listas normales', () {
    final projection = projectAssistantSuggestions('''
Respuesta principal.

También puedo dejarlo listo como:
- checklist de QA
- plan de implementación
''');

    expect(projection.body, 'Respuesta principal.');
    expect(projection.suggestions, [
      'checklist de QA',
      'plan de implementación',
    ]);
  });

  test(
    'proyecta una oferta final española sin bullets y retira su divisor',
    () {
      final projection = projectAssistantSuggestions('''
Resultado estable.

---

Si quieres, en el siguiente paso te preparo un plan detallado.
''');

      expect(projection.body, 'Resultado estable.');
      expect(projection.suggestions, ['Prepara un plan detallado']);
    },
  );

  test('proyecta una oferta final inglesa sin bullets', () {
    final projection = projectAssistantSuggestions('''
The result is ready.

If you want, next I can prepare a compact checklist.
''');

    expect(projection.body, 'The result is ready.');
    expect(projection.suggestions, ['Prepare a compact checklist']);
  });

  test('compacta la oferta larga que produce el chat real', () {
    final projection = projectAssistantSuggestions('''
Orden recomendado.

---

Si quieres, en el siguiente paso te preparo un **plan de recorte con números concretos por escenario** (conservador / medio / agresivo) y el set de comandos de Zerobyte con valores exactos para aplicarlo sin riesgo operacional (incluye qué se perdería y qué no).
''');

    expect(projection.body, 'Orden recomendado.');
    expect(projection.suggestions, [
      'Prepara un plan de recorte con números concretos por escenario',
    ]);
  });

  test('una mención intermedia o un verbo desconocido no se convierten', () {
    const middle =
        'Lo resolvemos si quieres, pero antes hay que revisar el servidor.';
    const unknown =
        'Resultado.\n\n---\n\nSi quieres, mañana coordinamos el despliegue.';

    final middleProjection = projectAssistantSuggestions(middle);
    final unknownProjection = projectAssistantSuggestions(unknown);

    expect(middleProjection.hasSuggestions, isFalse);
    expect(middleProjection.body, middle);
    expect(unknownProjection.hasSuggestions, isFalse);
    expect(unknownProjection.body, unknown, reason: 'no borra el divisor');
  });

  test('solo proyecta la oferta cuando es el último párrafo', () {
    const source =
        'Si quieres, te preparo un plan.\n\nPero este es el cierre real.';
    final projection = projectAssistantSuggestions(source);

    expect(projection.hasSuggestions, isFalse);
    expect(projection.body, source);
  });

  test('no convierte cierres de más de tres acciones en un rail parcial', () {
    final projection = projectAssistantSuggestions('''
Respuesta principal.

¿Cuál prefieres?
1) resumen breve
2) checklist
3) tabla comparativa
4) plan paso a paso
''');

    expect(projection.body, contains('¿Cuál prefieres?'));
    expect(projection.suggestions, isEmpty);
  });

  test('no oculta código, errores ni bloques con más de cuatro opciones', () {
    final code = projectAssistantSuggestions('''
```dart
throw StateError('fallo');
```

Si quieres, puedo:
- explicarlo
''');
    final error = projectAssistantSuggestions('''
Error: no se pudo completar la operación.

Si quieres, puedo:
- reintentarlo
''');
    final tooMany = projectAssistantSuggestions('''
Texto.

Puedes elegir:
1. uno
2. dos
3. tres
4. cuatro
5. cinco
''');

    expect(code.hasSuggestions, isFalse);
    expect(error.hasSuggestions, isFalse);
    expect(tooMany.hasSuggestions, isFalse);
  });

  testWidgets('las sugerencias ejecutan el callback y muestran feedback', (
    tester,
  ) async {
    String? selected;
    final completer = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.fromId('dark'),
        home: Scaffold(
          body: HermesSuggestions(
            suggestions: const ['Versión corta', 'Solo hechos'],
            onSelected: (value) async {
              selected = value;
              await completer.future;
              return true;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Versión corta'));
    await tester.pump();

    expect(selected, 'Versión corta');
    expect(find.byKey(const ValueKey('suggestion-sending')), findsOneWidget);
    completer.complete();
    await tester.pump();
    expect(find.byKey(const ValueKey('suggestion-sending')), findsNothing);
    expect(find.byKey(const ValueKey('suggestion-sent')), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('assistant-suggestion-0')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('a 320 dp usa un rail horizontal de sugerencias compactas', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.fromId('dark'),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(size: Size(320, 640)),
            child: SizedBox(
              width: 320,
              child: HermesSuggestions(
                suggestions: const [
                  'Una sugerencia deliberadamente larga que debe seguir visible',
                  'Otra opción',
                ],
                onSelected: (_) async => true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('assistant-suggestions-rail')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('assistant-suggestions-row')),
      findsOneWidget,
    );
    expect(find.byType(Wrap), findsNothing);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.byType(Card), findsNothing);
    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(Divider), findsNothing);
    final rail = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('assistant-suggestions-rail')),
    );
    expect(rail.scrollDirection, Axis.horizontal);
    final longButton = tester.getSize(
      find.byKey(const ValueKey('assistant-suggestion-0')),
    );
    expect(longButton.width, lessThanOrEqualTo(250));
    expect(longButton.height, 48);
    final longLabel = tester.widget<Text>(
      find.text('Una sugerencia deliberadamente larga que debe seguir visible'),
    );
    expect(longLabel.maxLines, 1);
    expect(longLabel.softWrap, isFalse);
    expect(longLabel.overflow, TextOverflow.ellipsis);
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('assistant-suggestion-1')))
          .dx,
      lessThan(320),
      reason: 'la segunda acción debe asomar para descubrir el carrusel',
    );

    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('assistant-suggestions-rail')),
      matching: find.byType(Scrollable),
    );
    final scrollState = tester.state<ScrollableState>(scrollable);
    expect(scrollState.position.maxScrollExtent, greaterThan(0));
    await tester.drag(
      find.byKey(const ValueKey('assistant-suggestions-rail')),
      const Offset(-120, 0),
    );
    await tester.pump();
    expect(scrollState.position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('las sugerencias admiten texto al 200 por ciento', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.fromId('dark'),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: SizedBox(
              width: 320,
              child: HermesSuggestions(
                suggestions: const [
                  'Preparar un plan detallado con todos los siguientes pasos',
                  'Solo hechos',
                ],
                onSelected: (_) async => true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    final longButton = tester.getSize(
      find.byKey(const ValueKey('assistant-suggestion-0')),
    );
    expect(longButton.width, lessThanOrEqualTo(250));
    expect(longButton.height, greaterThanOrEqualTo(48));
    expect(longButton.height, lessThan(64));
    expect(tester.takeException(), isNull);
  });

  testWidgets('movimiento reducido usa feedback estático e inmediato', (
    tester,
  ) async {
    final gate = Completer<bool>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.fromId('dark'),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: HermesSuggestions(
              suggestions: const ['Continuar'],
              onSelected: (_) => gate.future,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Continuar'));
    await tester.pump();

    final switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    );
    expect(switcher.duration, Duration.zero);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);

    gate.complete(true);
    await tester.pump();
  });

  for (final themeId in ['dark', 'light']) {
    testWidgets('las pills respetan el tema $themeId', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.fromId(themeId),
          home: Scaffold(
            body: HermesSuggestions(
              suggestions: const ['Continuar', 'Ver detalles'],
              onSelected: (_) async => true,
            ),
          ),
        ),
      );

      final finder = find.byKey(const ValueKey('assistant-suggestion-0'));
      final colors = Theme.of(tester.element(finder)).hermes;
      final button = tester.widget<OutlinedButton>(finder);
      expect(
        button.style?.foregroundColor?.resolve(const <WidgetState>{}),
        colors.textPrimary,
      );
      expect(
        button.style?.side?.resolve(const <WidgetState>{})?.color,
        colors.divider.withValues(alpha: 0.62),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sin acciones no deja rail ni superficie vacía', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.fromId('dark'),
        home: Scaffold(
          body: HermesSuggestions(
            suggestions: const [],
            onSelected: (_) async => true,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('assistant-suggestions-rail')),
      findsNothing,
    );
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('un rechazo no muestra check y vuelve a habilitar la pill', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.fromId('dark'),
        home: Scaffold(
          body: HermesSuggestions(
            suggestions: const ['Reintentar'],
            onSelected: (_) async {
              calls++;
              return false;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Reintentar'));
    await tester.pump();

    expect(calls, 1);
    expect(find.byKey(const ValueKey('suggestion-sent')), findsNothing);
    expect(find.byKey(const ValueKey('suggestion-rejected')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 701));
    final button = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('assistant-suggestion-0')),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('un doble toque solo dispara una solicitud', (tester) async {
    final gate = Completer<bool>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.fromId('dark'),
        home: Scaffold(
          body: HermesSuggestions(
            suggestions: const ['Continuar'],
            onSelected: (_) {
              calls++;
              return gate.future;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Continuar'));
    await tester.tap(find.text('Continuar'));
    await tester.pump();

    expect(calls, 1);
    gate.complete(true);
    await tester.pump();
  });

  testWidgets('el rail muestra como máximo tres pills táctiles de 48 dp', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.fromId('dark'),
        home: Scaffold(
          body: HermesSuggestions(
            suggestions: const ['Uno', 'Dos', 'Tres', 'Cuatro'],
            onSelected: (_) async => true,
          ),
        ),
      ),
    );

    expect(find.byType(OutlinedButton), findsNWidgets(3));
    for (var index = 0; index < 3; index++) {
      expect(
        tester
            .getSize(find.byKey(ValueKey('assistant-suggestion-$index')))
            .height,
        48,
      );
    }
    expect(
      tester.getSemantics(find.bySemanticsLabel('Uno')),
      matchesSemantics(
        label: 'Uno',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasSelectedState: true,
        isSelected: false,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  test(
    'solo ofrece acciones en el último assistant terminal y chat limpio',
    () {
      bool allowed({
        bool latest = true,
        bool terminal = true,
        bool busy = false,
        bool writable = true,
        bool composerEmpty = true,
        bool attachmentsEmpty = true,
      }) => canOfferAssistantSuggestions(
        isLatestAssistant: latest,
        isTerminal: terminal,
        chatBusy: busy,
        writable: writable,
        composerEmpty: composerEmpty,
        attachmentsEmpty: attachmentsEmpty,
      );

      expect(allowed(), isTrue);
      expect(allowed(latest: false), isFalse, reason: 'mensaje histórico');
      expect(allowed(terminal: false), isFalse, reason: 'run activo');
      expect(allowed(busy: true), isFalse, reason: 'chat ocupado');
      expect(allowed(writable: false), isFalse, reason: 'solo lectura');
      expect(allowed(composerEmpty: false), isFalse, reason: 'borrador');
      expect(allowed(attachmentsEmpty: false), isFalse, reason: 'adjuntos');
    },
  );

  test(
    'el cierre no se duplica al virtualizar una respuesta de más de 5200',
    () {
      final prefix = List.generate(
        170,
        (index) => 'Párrafo $index con contenido estable para el viewport.\n\n',
      ).join();
      final source =
          '$prefix'
          'Si quieres, puedo:\n'
          '- resumirlo\n'
          '- convertirlo en tareas';
      final projection = projectAssistantSuggestions(source);
      final chunks = splitAssistantMarkdownForViewport(source);

      expect(source.length, greaterThan(5200));
      expect(chunks.length, greaterThan(1));
      expect(projection.suggestions, ['resumirlo', 'convertirlo en tareas']);
      final renderedBody = [
        ...chunks.take(chunks.length - 1),
        stripAssistantSuggestionsFromTerminalChunk(chunks.last),
      ].join();
      expect(renderedBody, projection.body);
      expect(renderedBody, isNot(contains('Si quieres, puedo:')));
    },
  );
}
