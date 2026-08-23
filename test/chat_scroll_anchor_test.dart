import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresión de la mecánica de scroll-anchoring del chat (ver
/// `_captureScrollAnchor` / `_settleScroll` en chat_screen.dart).
///
/// En una lista `reverse: true`, el mensaje en streaming (index 0) crece y
/// empuja hacia arriba lo que el usuario está leyendo. Anclando a un item
/// visible (index >= 1) y compensando su desplazamiento, la lectura queda fija.
void main() {
  // Reproduce fielmente la heurística de la pantalla: ancla = item montado de
  // menor índice >= 1; compensación = jumpTo(pixels + (dyAntes - dyDespués)).
  late ScrollController controller;
  final keys = <int, GlobalKey>{};
  GlobalKey keyFor(int i) => keys.putIfAbsent(i, () => GlobalKey());

  ({int index, double dy})? capture() {
    if (!controller.hasClients) return null;
    final pos = controller.position;
    if (pos.pixels <= pos.minScrollExtent + 100) return null; // sigue el fondo
    int best = -1;
    RenderBox? bestBox;
    for (final e in keys.entries) {
      if (e.key < 1) continue;
      final ctx = e.value.currentContext;
      final box = ctx?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      if (best == -1 || e.key < best) {
        best = e.key;
        bestBox = box;
      }
    }
    if (best == -1 || bestBox == null) return null;
    return (index: best, dy: bestBox.localToGlobal(Offset.zero).dy);
  }

  void settle(({int index, double dy})? anchor) {
    if (anchor == null) return;
    final box = keys[anchor.index]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final delta = anchor.dy - box.localToGlobal(Offset.zero).dy;
    if (delta.abs() < 0.5 || delta.abs() > 4000) return;
    final pos = controller.position;
    final target = (pos.pixels + delta).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    controller.jumpTo(target);
  }

  Future<void> pumpList(
    WidgetTester tester,
    ValueNotifier<double> item0Height,
  ) async {
    controller = ScrollController();
    keys.clear();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<double>(
            valueListenable: item0Height,
            builder: (_, h0, _) => ListView.builder(
              controller: controller,
              reverse: true,
              itemCount: 30,
              itemBuilder: (c, i) => KeyedSubtree(
                key: keyFor(i),
                child: SizedBox(
                  height: i == 0 ? h0 : 80.0,
                  child: Text('item $i'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('leyendo arriba: la lectura no se mueve al crecer el mensaje', (
    tester,
  ) async {
    final h0 = ValueNotifier<double>(100);
    await pumpList(tester, h0);

    controller.jumpTo(400); // el usuario sube a leer
    await tester.pump();

    final probe = find.text('item 6'); // algo que está leyendo
    final yBefore = tester.getTopLeft(probe).dy;

    final anchor = capture(); // mide ANTES (layout viejo)
    h0.value = 220; // llegan varios tokens: el mensaje en curso crece +120
    await tester.pump();
    settle(anchor); // compensa tras pintar
    await tester.pump();

    final yAfter = tester.getTopLeft(probe).dy;
    expect(
      (yAfter - yBefore).abs(),
      lessThan(1.5),
      reason: 'el contenido leído debe quedarse en su sitio',
    );
  });

  testWidgets('cerca del fondo: no se ancla (deja seguir al mensaje nuevo)', (
    tester,
  ) async {
    final h0 = ValueNotifier<double>(100);
    await pumpList(tester, h0);

    // El usuario está pegado al fondo (offset 0 en reverse).
    expect(controller.position.pixels, lessThanOrEqualTo(100));
    final anchor = capture();
    expect(anchor, isNull); // no anclamos: el auto-scroll seguirá al fondo
  });
}
