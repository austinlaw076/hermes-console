import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';

void main() {
  testWidgets('el primer contacto pausa el seguimiento antes del arrastre', (
    tester,
  ) async {
    var interactions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatScrollInteractionGuard(
            onPointerDown: (_) => interactions++,
            child: ListView(children: const [SizedBox(height: 1200)]),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(200, 300));
    expect(interactions, 1);
    await gesture.up();
  });

  testWidgets('el salto alinea el inicio de una respuesta larga', (
    tester,
  ) async {
    final controller = ScrollController();
    late RenderBox answerAnchor;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: ListView(
              controller: controller,
              reverse: true,
              children: [
                ChatAnswerAnchor(
                  onLayout: (anchor) => answerAnchor = anchor,
                  child: Container(
                    height: 1200,
                    alignment: Alignment.topLeft,
                    child: const Text('Inicio de la respuesta'),
                  ),
                ),
                const SizedBox(height: 200),
              ],
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.text('Inicio de la respuesta')).dy,
      lessThan(0),
    );
    await scrollChatAnswerToStart(
      answerAnchor,
      controller.position,
      duration: Duration.zero,
    );
    await tester.pump();

    expect(
      tester.getTopLeft(find.text('Inicio de la respuesta')).dy,
      closeTo(0, 1),
    );
  });

  testWidgets('las respuestas anteriores conservan un orden navegable', (
    tester,
  ) async {
    final controller = ScrollController();
    late RenderBox latestAnswer;
    late RenderBox previousAnswer;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: ListView(
              controller: controller,
              reverse: true,
              children: [
                ChatAnswerAnchor(
                  onLayout: (anchor) => latestAnswer = anchor,
                  child: const SizedBox(
                    height: 600,
                    child: Text('Respuesta reciente'),
                  ),
                ),
                const SizedBox(height: 80, child: Text('Pregunta anterior')),
                ChatAnswerAnchor(
                  onLayout: (anchor) => previousAnswer = anchor,
                  child: const SizedBox(
                    height: 700,
                    child: Text('Respuesta anterior'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final latestOffset = chatAnswerStartOffset(
      latestAnswer,
      controller.position,
    );
    final previousOffset = chatAnswerStartOffset(
      previousAnswer,
      controller.position,
    );
    expect(latestOffset, isNotNull);
    expect(previousOffset, greaterThan(latestOffset!));

    await scrollChatAnswerToStart(
      previousAnswer,
      controller.position,
      duration: Duration.zero,
    );
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('Respuesta anterior')).dy,
      closeTo(0, 1),
    );
  });
}
