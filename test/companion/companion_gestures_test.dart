import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/companion/data/companion_preferences.dart';
import 'package:hermes_android/core/companion/data/companion_repository.dart';
import 'package:hermes_android/core/companion/models/companion.dart';
import 'package:hermes_android/core/companion/models/companion_animation_state.dart';
import 'package:hermes_android/core/companion/models/companion_presence_level.dart';
import 'package:hermes_android/core/companion/render/companion_home_mascot.dart';
import 'package:hermes_android/core/companion/render/companion_view.dart';
import 'package:hermes_android/core/companion/state/companion_controller.dart';
import 'package:hermes_android/core/widgets/hermes_spark_mascot.dart';
import 'package:shared_preferences/shared_preferences.dart';

Companion _pet(String slug, String name) => Companion(
  slug: slug,
  name: name,
  author: 'Hermes team',
  license: 'CC0-1.0',
  spritesheetAsset: 'assets/companions/$slug/spritesheet.webp',
  frameWidth: 192,
  frameHeight: 208,
  cols: 8,
  rows: 9,
  fps: 8,
  states: const {
    CompanionAnimationState.idle: RowSpec(row: 0, frameCount: 8, loop: true),
  },
);

class _FakeRepo extends CompanionRepository {
  final List<Companion> _all;
  _FakeRepo(this._all);
  @override
  Future<List<Companion>> loadAll() async => _all;
}

Future<CompanionController> _controller(List<Companion> pets) async {
  final prefs = await CompanionPreferences.load();
  final c = CompanionController(_FakeRepo(pets), prefs);
  await c.init();
  return c;
}

Future<void> _pump(
  WidgetTester tester,
  CompanionController c, {
  VoidCallback? onOpen,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: CompanionHomeMascot(
            controller: c,
            baseMood: HermesSparkMood.idle,
            size: 76,
            accent: const Color(0xFFE8821C),
            onOpenMascotas: onOpen ?? () {},
            semanticLabel: 'Pet — open Pets',
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(finder);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tap abre el bottom sheet con las 3 acciones', (tester) async {
    final c = await _controller([_pet('nimbus', 'Nimbus')]);
    await _pump(tester, c);

    await tester.tap(find.byType(CompanionHomeMascot));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Cambiar mascota'), findsOneWidget);
    expect(find.text('Apagar mascota'), findsOneWidget);
    expect(find.text('Abrir Mascotas'), findsOneWidget);
  });

  testWidgets('long-press abre el bottom sheet con las 3 acciones', (
    tester,
  ) async {
    final c = await _controller([_pet('nimbus', 'Nimbus')]);
    await _pump(tester, c);

    await tester.longPress(find.byType(CompanionHomeMascot));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Cambiar mascota'), findsOneWidget);
    expect(find.text('Apagar mascota'), findsOneWidget);
    expect(find.text('Abrir Mascotas'), findsOneWidget);
  });

  testWidgets('"Apagar mascota" desactiva el Companion', (tester) async {
    final c = await _controller([_pet('nimbus', 'Nimbus')]);
    await _pump(tester, c);
    expect(c.enabled, isTrue);

    await tester.longPress(find.byType(CompanionHomeMascot));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Apagar mascota'));
    await tester.pump();

    expect(c.enabled, isFalse);
  });

  testWidgets('"Abrir Mascotas" invoca el callback de navegación', (
    tester,
  ) async {
    final c = await _controller([_pet('nimbus', 'Nimbus')]);
    var opened = 0;
    await _pump(tester, c, onOpen: () => opened++);

    await tester.longPress(find.byType(CompanionHomeMascot));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Abrir Mascotas'));
    await tester.pump();

    expect(opened, 1);
  });

  testWidgets('con el Companion apagado no hay objetivo táctil (sin sheet)', (
    tester,
  ) async {
    final c = await _controller([_pet('nimbus', 'Nimbus')]);
    await c.setEnabled(false);
    await _pump(tester, c);

    // warnIfMissed:false — apagado NO hay objetivo táctil (es lo que validamos).
    await tester.longPress(
      find.byType(CompanionHomeMascot),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Apagado: ninguna acción del sheet debe aparecer.
    expect(find.text('Apagar mascota'), findsNothing);
  });

  testWidgets('presencia off oculta la mascota del Home y elimina sus gestos', (
    tester,
  ) async {
    final c = await _controller([_pet('nimbus', 'Nimbus')]);
    await c.setPresenceLevel(CompanionPresenceLevel.off);
    await _pump(tester, c);

    expect(find.byType(CompanionView), findsNothing);
    expect(tester.getSize(find.byType(CompanionHomeMascot)), Size.zero);
    expect(find.bySemanticsLabel('Pet — open Pets'), findsNothing);

    await tester.longPress(
      find.byType(CompanionHomeMascot),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Apagar mascota'), findsNothing);
  });

  testWidgets('no muestra una mascota antes de cargar off persistido', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      CompanionPreferences.presenceLevelKey: CompanionPresenceLevel.off.id,
    });
    final prefs = await CompanionPreferences.load();
    final c = CompanionController(_FakeRepo(const []), prefs);

    await _pump(tester, c);
    expect(c.isInitialized, isFalse);
    expect(find.byType(CompanionView), findsNothing);
    expect(find.bySemanticsLabel('Pet — open Pets'), findsNothing);

    await c.init();
    await tester.pump();
    expect(c.presenceLevel, CompanionPresenceLevel.off);
    expect(find.byType(CompanionView), findsNothing);
  });

  testWidgets('presencia minimal y full conservan el render del Home', (
    tester,
  ) async {
    final c = await _controller([_pet('nimbus', 'Nimbus')]);

    for (final level in const [
      CompanionPresenceLevel.minimal,
      CompanionPresenceLevel.full,
    ]) {
      await c.setPresenceLevel(level);
      await _pump(tester, c);
      expect(
        find.descendant(
          of: find.byType(CompanionHomeMascot),
          matching: find.byType(CompanionView),
        ),
        findsOneWidget,
        reason: 'el nivel ${level.name} debe mantener la mascota visible',
      );
      expect(find.bySemanticsLabel('Pet — open Pets'), findsOneWidget);
    }
  });

  testWidgets(
    'cambiar off a minimal vuelve a mostrar la mascota sin remontar',
    (tester) async {
      final c = await _controller([_pet('nimbus', 'Nimbus')]);
      await c.setPresenceLevel(CompanionPresenceLevel.off);
      await _pump(tester, c);
      expect(find.byType(CompanionView), findsNothing);

      await c.setPresenceLevel(CompanionPresenceLevel.minimal);
      await tester.pump();

      expect(find.byType(CompanionView), findsOneWidget);
      expect(find.bySemanticsLabel('Pet — open Pets'), findsOneWidget);
    },
  );

  testWidgets('doble tap reproduce el saludo sin lanzar excepción', (
    tester,
  ) async {
    final c = await _controller([_pet('nimbus', 'Nimbus')]);
    await _pump(tester, c);

    await _doubleTap(tester, find.byType(CompanionHomeMascot));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200)); // revierte el wave

    expect(tester.takeException(), isNull);
  });

  testWidgets('doble tap repetido no deja timers colgados ni excepciones', (
    tester,
  ) async {
    final c = await _controller([_pet('nimbus', 'Nimbus')]);
    await _pump(tester, c);

    final finder = find.byType(CompanionHomeMascot);
    for (var i = 0; i < 5; i++) {
      await _doubleTap(tester, finder);
      await tester.pump(
        const Duration(milliseconds: 40),
      ); // dentro del cooldown
    }
    // Tras el saludo vuelve a reposo; sin timers pendientes ni fugas.
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desmontar durante el saludo cancela el timer (sin setState tras '
      'dispose)', (tester) async {
    final c = await _controller([_pet('nimbus', 'Nimbus')]);
    await _pump(tester, c);

    await _doubleTap(tester, find.byType(CompanionHomeMascot));
    await tester.pump(const Duration(milliseconds: 40));
    // Reemplaza el árbol → desmonta el State con el timer del saludo aún vivo.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    await tester.pump(
      const Duration(seconds: 2),
    ); // el timer viejo no debe tocar nada
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reduce-motion: el doble tap no lanza ni cuelga (sin saludo infinito)',
    (tester) async {
      final c = await _controller([_pet('nimbus', 'Nimbus')]);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(800, 600),
              disableAnimations: true,
            ),
            child: Scaffold(
              body: Center(
                child: CompanionHomeMascot(
                  controller: c,
                  baseMood: HermesSparkMood.idle,
                  size: 76,
                  accent: const Color(0xFFE8821C),
                  onOpenMascotas: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await _doubleTap(tester, find.byType(CompanionHomeMascot));
      // Sin animación lúdica: pumpAndSettle no debe colgarse esperando un timer.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
