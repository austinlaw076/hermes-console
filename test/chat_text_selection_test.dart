import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_android/core/screens/chat_screen.dart';

void main() {
  testWidgets('un mensaje terminado usa una región estable sin lupa', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatMessageSelectionArea(
            child: Text('una frase con varias palabras'),
          ),
        ),
      ),
    );

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    final area = tester.widget<SelectionArea>(find.byType(SelectionArea));
    expect(
      area.magnifierConfiguration,
      same(TextMagnifierConfiguration.disabled),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('el Markdown terminal permite selección sin EditableText', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AssistantMarkdownView(
            data: 'Una frase terminal que se puede seleccionar.',
          ),
        ),
      ),
    );

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.byType(EditableText), findsNothing);
    expect(
      find.text('Una frase terminal que se puede seleccionar.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('el Markdown en streaming no crea texto seleccionable', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AssistantMarkdownView(
            data: 'Respuesta parcial',
            isStreaming: true,
          ),
        ),
      ),
    );

    expect(find.byType(SelectionArea), findsNothing);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.byType(EditableText), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un mensaje en streaming conserva el mismo árbol estable', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatMessageSelectionArea(
            enabled: false,
            child: Text('respuesta parcial'),
          ),
        ),
      ),
    );

    expect(find.byType(SelectionArea), findsNothing);
    expect(find.text('respuesta parcial'), findsOneWidget);
  });

  testWidgets('deshabilitar selección retira toolbar y región antes del hijo', (
    tester,
  ) async {
    var enabled = true;
    late StateSetter setHostState;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return ChatMessageSelectionArea(
                enabled: enabled,
                child: const Text('respuesta que termina el streaming'),
              );
            },
          ),
        ),
      ),
    );

    await tester.longPress(find.text('respuesta que termina el streaming'));
    await tester.pumpAndSettle();
    final region = tester
        .state<SelectionAreaState>(find.byType(SelectionArea))
        .selectableRegion;
    expect(region.selectionOverlay?.toolbarIsVisible, isTrue);

    setHostState(() => enabled = false);
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea), findsNothing);
    expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
    expect(find.text('respuesta que termina el streaming'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cambiar la identidad de la fila limpia la selección anterior', (
    tester,
  ) async {
    var identity = 1;
    late StateSetter setHostState;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return ChatMessageSelectionArea(
                selectionIdentity: identity,
                child: const Text('fila virtualizada reutilizable'),
              );
            },
          ),
        ),
      ),
    );

    await tester.longPress(find.text('fila virtualizada reutilizable'));
    await tester.pumpAndSettle();
    expect(
      tester
          .state<SelectionAreaState>(find.byType(SelectionArea))
          .selectableRegion
          .selectionOverlay
          ?.toolbarIsVisible,
      isTrue,
    );

    setHostState(() => identity = 2);
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
    expect(
      tester
          .state<SelectionAreaState>(find.byType(SelectionArea))
          .selectableRegion
          .selectionOverlay
          ?.toolbarIsVisible,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'la pulsación larga selecciona sin botón ni superficie intermedia',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AssistantMarkdownView(data: 'Respuesta terminal limpia'),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('chat-select-text')), findsNothing);
      expect(
        find.byKey(const ValueKey('chat-text-selection-dialog')),
        findsNothing,
      );

      await tester.longPress(find.text('Respuesta terminal limpia'));
      await tester.pumpAndSettle();

      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
      expect(find.byType(EditableText), findsNothing);
      final state = tester.state<SelectionAreaState>(
        find.byType(SelectionArea),
      );
      expect(state.selectableRegion.selectionOverlay, isNotNull);
      expect(
        state.selectableRegion.contextMenuButtonItems.any(
          (item) => item.type == ContextMenuButtonType.copy,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('seleccionar no desplaza el mensaje ni el scroll', (
    tester,
  ) async {
    final controller = ScrollController();
    const text = 'Texto estable cerca del borde superior';
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: SizedBox(
            height: 260,
            child: ListView(
              controller: controller,
              reverse: true,
              children: const [
                SizedBox(height: 500),
                ChatMessageSelectionArea(child: Text(text)),
                SizedBox(height: 500),
              ],
            ),
          ),
        ),
      ),
    );
    controller.jumpTo(480);
    await tester.pump();

    final beforeOffset = controller.offset;
    final beforeRect = tester.getRect(find.text(text));
    await tester.longPress(find.text(text));
    await tester.pumpAndSettle();

    expect(controller.offset, closeTo(beforeOffset, 0.01));
    expect(tester.getRect(find.text(text)), beforeRect);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'volver de la ruta limpia selección y toolbar antes de desmontar',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(
                        body: ChatMessageSelectionArea(
                          child: Text('texto seleccionado antes de volver'),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Abrir chat'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir chat'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('texto seleccionado antes de volver'));
      await tester.pumpAndSettle();

      final region = tester
          .state<SelectionAreaState>(find.byType(SelectionArea))
          .selectableRegion;
      expect(region.selectionOverlay?.toolbarIsVisible, isTrue);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);

      Navigator.of(
        tester.element(find.text('texto seleccionado antes de volver')),
      ).pop();
      await tester.pumpAndSettle();

      expect(find.text('Abrir chat'), findsOneWidget);
      expect(find.byType(SelectionArea), findsNothing);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('veinte ciclos de selección desmontan sin dependents', (
    tester,
  ) async {
    for (var cycle = 0; cycle < 20; cycle++) {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AssistantMarkdownView(
              data: 'Texto estable para seleccionar por partes',
            ),
          ),
        ),
      );
      await tester.longPress(
        find.text('Texto estable para seleccionar por partes'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.byType(EditableText), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(find.byType(SelectionArea), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
