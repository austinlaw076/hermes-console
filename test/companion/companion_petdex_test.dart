import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:hermes_android/core/companion/companion_links.dart';
import 'package:hermes_android/core/companion/data/companion_preferences.dart';
import 'package:hermes_android/core/companion/data/companion_repository.dart';
import 'package:hermes_android/core/companion/models/companion.dart';
import 'package:hermes_android/core/companion/models/companion_animation_state.dart';
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

class _FakeRepo extends CompanionRepository {
  final List<Companion> _all;
  _FakeRepo(this._all);
  @override
  Future<List<Companion>> loadAll() async => _all;
}

Future<CompanionController> _controller() async {
  final prefs = await CompanionPreferences.load();
  final c = CompanionController(_FakeRepo([_pet('nimbus', 'Nimbus')]), prefs);
  await c.init();
  return c;
}

/// Launcher espía: registra la URL solicitada y NO realiza ninguna red/descarga.
class _SpyLauncher {
  int calls = 0;
  Uri? lastUri;
  bool result;
  _SpyLauncher({this.result = true});
  Future<bool> call(Uri uri) async {
    calls++;
    lastUri = uri;
    return result;
  }
}

Future<void> _pump(
  WidgetTester tester,
  CompanionController c, {
  required _SpyLauncher launcher,
  required bool verified,
}) async {
  // Viewport muy alto: el ListView construye todo (incl. la fila de Petdex).
  tester.view.physicalSize = const Size(1000, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: MascotasScreen(
        controller: c,
        launcher: launcher.call,
        petdexVerified: verified,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('la fila "Ver Petdex" está presente', (tester) async {
    final c = await _controller();
    await _pump(tester, c, launcher: _SpyLauncher(), verified: false);
    expect(find.text('Ver Petdex'), findsOneWidget);
  });

  testWidgets('sin verificar: pulsar NO abre nada y avisa de pendiente', (
    tester,
  ) async {
    final c = await _controller();
    final spy = _SpyLauncher();
    await _pump(tester, c, launcher: spy, verified: false);

    await tester.tap(find.text('Ver Petdex'));
    await tester.pump();

    // No se solicitó abrir ninguna URL → 0 aperturas, 0 red, 0 descarga.
    expect(spy.calls, 0);
    expect(
      find.text('Enlace de Petdex pendiente de verificación.'),
      findsOneWidget,
    );
  });

  testWidgets('verificada: pulsar solicita abrir exactamente kPetdexUrl', (
    tester,
  ) async {
    final c = await _controller();
    final spy = _SpyLauncher(result: true);
    await _pump(tester, c, launcher: spy, verified: true);

    await tester.tap(find.text('Ver Petdex'));
    await tester.pump();

    expect(spy.calls, 1);
    expect(spy.lastUri.toString(), kPetdexUrl);
    // Sin error: el launcher devolvió true.
    expect(find.text('No se pudo abrir Petdex.'), findsNothing);
  });

  testWidgets('verificada: si la apertura falla, muestra aviso de error', (
    tester,
  ) async {
    final c = await _controller();
    final spy = _SpyLauncher(result: false);
    await _pump(tester, c, launcher: spy, verified: true);

    await tester.tap(find.text('Ver Petdex'));
    await tester.pump();

    expect(spy.calls, 1);
    expect(find.text('No se pudo abrir Petdex.'), findsOneWidget);
  });

  // Bloque 2: la verificación del 2026-06-25 confirmó la URL canónica y
  // habilitó el enlace externo (ver docs/PETDEX_CONTRACT.md).
  test('contrato verificado: URL canónica de Petdex y enlace habilitado', () {
    expect(kPetdexUrl, 'https://petdex.dev');
    expect(kPetdexUrlVerified, isTrue);
  });
}
