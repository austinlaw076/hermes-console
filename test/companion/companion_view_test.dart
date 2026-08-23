import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/companion/data/companion_preferences.dart';
import 'package:hermes_android/core/companion/data/companion_repository.dart';
import 'package:hermes_android/core/companion/models/companion.dart';
import 'package:hermes_android/core/companion/models/companion_animation_state.dart';
import 'package:hermes_android/core/companion/render/companion_view.dart';
import 'package:hermes_android/core/companion/render/spritesheet_renderer.dart';
import 'package:hermes_android/core/companion/state/companion_controller.dart';
import 'package:hermes_android/core/widgets/hermes_spark_mascot.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeController extends CompanionController {
  final Companion? _active;
  _FakeController(this._active, super.repository, super.preferences);

  @override
  Companion? get activeCompanion => _active;
}

Companion _companion() => Companion(
  slug: 'nimbus',
  name: 'Nimbus',
  author: 'team',
  license: 'CC0-1.0',
  spritesheetAsset: 'assets/companions/nimbus/spritesheet.webp',
  frameWidth: 192,
  frameHeight: 208,
  cols: 8,
  rows: 9,
  fps: 8,
  states: const {
    CompanionAnimationState.idle: RowSpec(row: 0, frameCount: 8, loop: true),
  },
);

Future<_FakeController> _fake(Companion? active) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await CompanionPreferences.load();
  return _FakeController(active, CompanionRepository(), prefs);
}

void main() {
  testWidgets('sin controller → fallback HermesSparkMascot', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CompanionView(animate: false)),
    );
    expect(find.byType(HermesSparkMascot), findsOneWidget);
    expect(find.byType(SpritesheetRenderer), findsNothing);
    expect(
      tester.widget<HermesSparkMascot>(find.byType(HermesSparkMascot)).animate,
      isFalse,
    );
  });

  testWidgets('controller sin mascota activa → fallback', (tester) async {
    final controller = await _fake(null);
    await tester.pumpWidget(
      MaterialApp(home: CompanionView(controller: controller)),
    );
    expect(find.byType(HermesSparkMascot), findsOneWidget);
    expect(find.byType(SpritesheetRenderer), findsNothing);
  });

  testWidgets('controller con mascota activa → SpritesheetRenderer', (
    tester,
  ) async {
    final controller = await _fake(_companion());
    await tester.pumpWidget(
      MaterialApp(home: CompanionView(controller: controller)),
    );
    expect(find.byType(SpritesheetRenderer), findsOneWidget);
    expect(find.byType(HermesSparkMascot), findsNothing);
  });

  testWidgets('desactivada → no muestra NADA (ni Spark ni sprite)', (
    tester,
  ) async {
    final controller = await _fake(_companion());
    await controller.setEnabled(false);
    await tester.pumpWidget(
      MaterialApp(home: CompanionView(controller: controller)),
    );
    expect(find.byType(HermesSparkMascot), findsNothing);
    expect(find.byType(SpritesheetRenderer), findsNothing);
  });
}
