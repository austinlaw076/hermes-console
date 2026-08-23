import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:hermes_android/core/companion/data/companion_preferences.dart';
import 'package:hermes_android/core/companion/data/companion_repository.dart';
import 'package:hermes_android/core/companion/models/companion.dart';
import 'package:hermes_android/core/companion/models/companion_animation_state.dart';
import 'package:hermes_android/core/companion/models/companion_presence_level.dart';
import 'package:hermes_android/core/companion/render/companion_presence.dart';
import 'package:hermes_android/core/companion/state/companion_controller.dart';
import 'package:hermes_android/core/screens/companion/mascotas_screen.dart';
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

/// Mascota con estado `wave` y filas EXTRA para ejercitar el probador.
Companion _petTester(
  String slug,
  String name, {
  List<RowSpec> extras = const [],
}) => Companion(
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
    CompanionAnimationState.wave: RowSpec(row: 3, frameCount: 4, loop: false),
  },
  extraRows: extras,
);

/// Repo de prueba que evita la carga real de assets.
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

Future<void> _pumpScreen(WidgetTester tester, CompanionController c) async {
  // Viewport alto: el ListView construye todos los ítems (incl. la 3ª mascota).
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: MascotasScreen(controller: c),
    ),
  );
  // pump() (no pumpAndSettle): los sprites/Spark tienen animaciones en bucle.
  await tester.pump();
}

Future<void> _expandAdvanced(WidgetTester tester) async {
  await tester.tap(find.text('Opciones avanzadas'));
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renderiza la lista con la opción por defecto y las mascotas', (
    tester,
  ) async {
    final c = await _controller([
      _pet('nimbus', 'Nimbus'),
      _pet('pixel', 'Pixel'),
      _pet('violet', 'Violet'),
    ]);
    await _pumpScreen(tester, c);

    expect(find.text('Mascotas'), findsOneWidget); // AppBar
    expect(find.text('Por defecto (Spark)'), findsWidgets);
    expect(find.text('Nimbus'), findsOneWidget);
    expect(find.text('Pixel'), findsOneWidget);
    expect(find.text('Violet'), findsOneWidget);
    expect(find.byType(CompanionPresence), findsNothing);
  });

  testWidgets('seleccionar una mascota persiste la selección', (tester) async {
    final c = await _controller([_pet('nimbus', 'Nimbus')]);
    await _pumpScreen(tester, c);

    expect(c.selectedSlug, isNull);
    await tester.tap(find.text('Nimbus'));
    await tester.pump();

    expect(c.selectedSlug, 'nimbus');
    expect(c.activeCompanion?.slug, 'nimbus');
  });

  testWidgets('presencia apagada y completa controlan la visibilidad', (
    tester,
  ) async {
    final c = await _controller([_pet('nimbus', 'Nimbus')]);
    await _pumpScreen(tester, c);

    expect(c.enabled, isTrue); // ON por defecto
    await tester.tap(find.text('Apagada'));
    await tester.pump();

    expect(c.enabled, isFalse);
    expect(c.presenceLevel, CompanionPresenceLevel.off);

    await tester.tap(find.text('Completa'));
    await tester.pump();

    expect(c.enabled, isTrue);
    expect(c.presenceLevel, CompanionPresenceLevel.full);
  });

  testWidgets('puede ocultarse solo en Inicio sin apagar la presencia', (
    tester,
  ) async {
    final c = await _controller([_pet('nimbus', 'Nimbus')]);
    await _pumpScreen(tester, c);

    final tile = find.byKey(const ValueKey('pet-show-on-home'));
    expect(tile, findsOneWidget);
    expect(c.showOnHome, isTrue);

    final toggle = tester.widget<Switch>(
      find.descendant(of: tile, matching: find.byType(Switch)),
    );
    toggle.onChanged!(false);
    await tester.pump();

    expect(c.showOnHome, isFalse);
    expect(c.enabled, isTrue);
    expect(c.presenceLevel, CompanionPresenceLevel.minimal);
  });

  testWidgets('el slider persiste un tamaño continuo', (tester) async {
    final c = await _controller([_pet('nimbus', 'Nimbus')]);
    await _pumpScreen(tester, c);

    final slider = tester.widget<Slider>(
      find.descendant(
        of: find.byKey(const ValueKey('pet-size-slider')),
        matching: find.byType(Slider),
      ),
    );
    slider.onChanged!(1.4);
    await tester.pump();
    slider.onChangeEnd!(1.4);
    await tester.pump();

    expect(c.sizeMultiplier, closeTo(1.4, 0.001));
  });

  testWidgets('la velocidad se ajusta solo desde opciones avanzadas', (
    tester,
  ) async {
    final c = await _controller([_petTester('nimbus', 'Nimbus')]);
    await c.select('nimbus');
    await _pumpScreen(tester, c);

    expect(find.text('VELOCIDAD DE ANIMACIÓN'), findsNothing);
    await _expandAdvanced(tester);

    final slider = tester.widget<Slider>(
      find.descendant(
        of: find.byKey(const ValueKey('pet-animation-speed-nimbus')),
        matching: find.byType(Slider),
      ),
    );
    slider.onChanged!(0.5);
    await tester.pump();
    slider.onChangeEnd!(0.5);
    await tester.pump();

    expect(c.animationSpeed, closeTo(0.5, 0.001));
  });

  testWidgets('el paseo es opt-in y se puede activar desde Mascotas', (
    tester,
  ) async {
    final c = await _controller([_pet('nimbus', 'Nimbus')]);
    await _pumpScreen(tester, c);

    expect(c.roamingEnabled, isFalse);
    await _expandAdvanced(tester);
    final roamingTile = find.ancestor(
      of: find.text('Mascota en movimiento'),
      matching: find.byType(SwitchListTile),
    );
    final roamingSwitch = tester.widget<Switch>(
      find.descendant(of: roamingTile, matching: find.byType(Switch)),
    );
    roamingSwitch.onChanged!(true);
    await tester.pump();

    expect(c.roamingEnabled, isTrue);
  });

  testWidgets('no muestra el logo como mascota', (tester) async {
    final c = await _controller([_pet('nimbus', 'Nimbus')]);
    await _pumpScreen(tester, c);

    final logoImages = find.byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName.toLowerCase().contains('logo'),
    );
    expect(logoImages, findsNothing);
  });

  testWidgets('fallback seguro: sin selección renderiza sin errores', (
    tester,
  ) async {
    final c = await _controller([_pet('nimbus', 'Nimbus')]);
    await _pumpScreen(tester, c);

    // selectedSlug null → preview grande cae a Spark; la pantalla no peta.
    expect(c.selectedSlug, isNull);
    expect(tester.takeException(), isNull);
    expect(find.byType(MascotasScreen), findsOneWidget);
  });

  // --- Probador de animaciones (Bloque 2) ---

  testWidgets('probador: extras sin metadata se etiquetan como "Extra N"', (
    tester,
  ) async {
    final c = await _controller([
      _petTester(
        'nimbus',
        'Nimbus',
        extras: const [
          RowSpec(row: 5, frameCount: 8, loop: false),
          RowSpec(row: 6, frameCount: 6, loop: false),
        ],
      ),
    ]);
    await c.select('nimbus');
    await _pumpScreen(tester, c);
    await _expandAdvanced(tester);

    expect(find.text('Extra 1'), findsOneWidget);
    expect(find.text('Extra 2'), findsOneWidget);
    expect(find.textContaining('Anim '), findsNothing); // ya no "Anim 6"
  });

  testWidgets('probador: un extra con nombre del pet.json usa ese nombre', (
    tester,
  ) async {
    final c = await _controller([
      _petTester(
        'nimbus',
        'Nimbus',
        extras: const [
          RowSpec(row: 5, frameCount: 8, loop: false, label: 'Bailar'),
        ],
      ),
    ]);
    await c.select('nimbus');
    await _pumpScreen(tester, c);
    await _expandAdvanced(tester);

    expect(find.text('Bailar'), findsOneWidget);
    expect(find.text('Extra 1'), findsNothing);
  });

  testWidgets('probador: controles Bucle y Detener visibles con mascota '
      'seleccionada', (tester) async {
    final c = await _controller([_petTester('nimbus', 'Nimbus')]);
    await c.select('nimbus');
    await _pumpScreen(tester, c);
    await _expandAdvanced(tester);

    expect(find.text('Bucle'), findsOneWidget);
    expect(find.text('Detener'), findsOneWidget);
  });

  testWidgets('probador: "Saltar" deshabilitado si la mascota no lo define', (
    tester,
  ) async {
    final c = await _controller([_petTester('nimbus', 'Nimbus')]);
    await c.select('nimbus');
    await _pumpScreen(tester, c);
    await _expandAdvanced(tester);

    final jump = tester.widget<InkWell>(
      find.ancestor(of: find.text('Saltar'), matching: find.byType(InkWell)),
    );
    expect(jump.onTap, isNull);
    final idle = tester.widget<InkWell>(
      find.ancestor(of: find.text('Reposo'), matching: find.byType(InkWell)),
    );
    expect(idle.onTap, isNotNull);
  });

  testWidgets('probador: tocar una animación y luego Detener no lanza', (
    tester,
  ) async {
    final c = await _controller([_petTester('nimbus', 'Nimbus')]);
    await c.select('nimbus');
    await _pumpScreen(tester, c);
    await _expandAdvanced(tester);

    tester
        .widget<InkWell>(
          find.ancestor(
            of: find.text('Saludar'),
            matching: find.byType(InkWell),
          ),
        )
        .onTap!();
    await tester.pump();
    tester
        .widget<TextButton>(
          find.ancestor(
            of: find.text('Detener'),
            matching: find.byType(TextButton),
          ),
        )
        .onPressed!();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('probador: reduce-motion deshabilita el toggle de Bucle', (
    tester,
  ) async {
    final c = await _controller([_petTester('nimbus', 'Nimbus')]);
    await c.select('nimbus');
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(1000, 2400),
            disableAnimations: true,
          ),
          child: MascotasScreen(controller: c),
        ),
      ),
    );
    await tester.pump();
    await _expandAdvanced(tester);

    final loopSwitch = tester.widget<Switch>(
      find.byKey(const Key('companion-loop-switch')),
    );
    expect(loopSwitch.onChanged, isNull);
  });
}
