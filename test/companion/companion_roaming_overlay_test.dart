import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/companion/data/companion_preferences.dart';
import 'package:hermes_android/core/companion/data/companion_repository.dart';
import 'package:hermes_android/core/companion/models/companion.dart';
import 'package:hermes_android/core/companion/render/companion_roaming_overlay.dart';
import 'package:hermes_android/core/companion/render/companion_view.dart';
import 'package:hermes_android/core/companion/state/companion_controller.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/hermes_spark_mascot.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptyRepo extends CompanionRepository {
  @override
  Future<List<Companion>> loadAll() async => const [];
}

Future<CompanionController> _controller({
  bool roaming = false,
  bool showOnHome = true,
}) async {
  SharedPreferences.setMockInitialValues({
    CompanionPreferences.roamingEnabledKey: roaming,
    CompanionPreferences.showOnHomeKey: showOnHome,
  });
  final prefs = await CompanionPreferences.load();
  final controller = CompanionController(_EmptyRepo(), prefs);
  await controller.init();
  return controller;
}

Future<void> _pump(
  WidgetTester tester,
  CompanionController controller, {
  bool reduceMotion = false,
  bool keyboardVisible = false,
  Duration minPause = const Duration(milliseconds: 1400),
  Duration maxPause = const Duration(milliseconds: 3600),
  Duration minTravel = const Duration(milliseconds: 2200),
  Duration maxTravel = const Duration(milliseconds: 5200),
  VoidCallback? onPetTap,
  ValueChanged<Offset>? onTravelFrame,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.fromId('dark'),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: const Size(300, 500),
            disableAnimations: reduceMotion,
            viewInsets: EdgeInsets.only(bottom: keyboardVisible ? 280 : 0),
          ),
          child: SizedBox(
            width: 300,
            height: 500,
            child: CompanionRoamingOverlay(
              controller: controller,
              random: math.Random(7),
              minPause: minPause,
              maxPause: maxPause,
              minTravel: minTravel,
              maxTravel: maxTravel,
              onPetTap: onPetTap,
              petSemanticLabel: 'Mascota — abrir acciones',
              onTravelFrame: onTravelFrame,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('apagado por defecto no monta la mascota', (tester) async {
    final controller = await _controller();
    await _pump(tester, controller);

    expect(find.byKey(const ValueKey('companion-roaming-pet')), findsNothing);
  });

  testWidgets('opt-in monta una sola mascota dentro de los límites', (
    tester,
  ) async {
    final controller = await _controller(roaming: true);
    await _pump(tester, controller);

    expect(find.byKey(const ValueKey('companion-roaming-pet')), findsOneWidget);
    final travel = tester.widget<ValueListenableBuilder<Offset>>(
      find.byKey(const ValueKey('companion-roaming-position')),
    );
    expect(travel.valueListenable.value.dx, inInclusiveRange(10, 232));
    expect(travel.valueListenable.value.dy, 10);
    expect(find.byType(AnimatedPositioned), findsNothing);
    expect(find.byType(TweenAnimationBuilder<Offset>), findsNothing);
    final ignoreAncestors = find.ancestor(
      of: find.byKey(const ValueKey('companion-roaming-pet')),
      matching: find.byType(IgnorePointer),
    );
    expect(ignoreAncestors, findsWidgets);
    expect(
      tester
          .widgetList<IgnorePointer>(ignoreAncestors)
          .any((widget) => widget.ignoring),
      isTrue,
    );
  });

  testWidgets('ocultarla en Inicio suprime también el paseo', (tester) async {
    final controller = await _controller(roaming: true, showOnHome: false);
    await _pump(tester, controller);

    expect(find.byKey(const ValueKey('companion-roaming-pet')), findsNothing);
    expect(controller.enabled, isTrue);
  });

  testWidgets('el sprite móvil recibe el toque cuando tiene acciones', (
    tester,
  ) async {
    final controller = await _controller(roaming: true);
    var taps = 0;
    await _pump(tester, controller, onPetTap: () => taps++);

    await tester.tap(find.byKey(const ValueKey('companion-roaming-pet')));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('al pasear usa run y vuelve a idle durante la pausa', (
    tester,
  ) async {
    final controller = await _controller(roaming: true);
    await _pump(
      tester,
      controller,
      minPause: const Duration(milliseconds: 10),
      maxPause: const Duration(milliseconds: 10),
      minTravel: const Duration(milliseconds: 100),
      maxTravel: const Duration(milliseconds: 100),
    );

    final before = tester
        .widget<ValueListenableBuilder<Offset>>(
          find.byKey(const ValueKey('companion-roaming-position')),
        )
        .valueListenable
        .value;
    await tester.pump(const Duration(milliseconds: 10));
    expect(
      tester.widget<CompanionView>(find.byType(CompanionView)).mood,
      HermesSparkMood.thinking,
    );

    await tester.pump(const Duration(milliseconds: 51));
    final travelling = tester.widget<ValueListenableBuilder<Offset>>(
      find.byKey(const ValueKey('companion-roaming-position')),
    );
    expect(travelling.valueListenable.value.dy, 10);
    expect(travelling.valueListenable.value.dx, isNot(before.dx));

    await tester.pump(const Duration(milliseconds: 50));
    expect(
      tester.widget<CompanionView>(find.byType(CompanionView)).mood,
      HermesSparkMood.idle,
    );
  });

  testWidgets('presupuesto de paseo limita el trabajo a 20 pasos por segundo', (
    tester,
  ) async {
    final controller = await _controller(roaming: true);
    final travelFrames = <Offset>[];
    await _pump(
      tester,
      controller,
      minPause: const Duration(milliseconds: 10),
      maxPause: const Duration(milliseconds: 10),
      minTravel: const Duration(seconds: 5),
      maxTravel: const Duration(seconds: 5),
      onTravelFrame: travelFrames.add,
    );

    await tester.pump(const Duration(milliseconds: 10));
    travelFrames.clear();
    await tester.pump(const Duration(seconds: 1));

    expect(travelFrames, isNotEmpty);
    expect(
      travelFrames.length,
      lessThanOrEqualTo(20),
      reason: 'el paseo no debe volver a seguir cada vsync de un panel 120 Hz',
    );
    expect(find.byType(TweenAnimationBuilder<Offset>), findsNothing);
  });

  testWidgets('reduce motion conserva una mascota estática sin frames', (
    tester,
  ) async {
    final controller = await _controller(roaming: true);
    await _pump(tester, controller, reduceMotion: true);

    final view = tester.widget<CompanionView>(find.byType(CompanionView));
    expect(view.mood, HermesSparkMood.idle);
    expect(view.animate, isFalse);
  });

  testWidgets('el teclado oculta el paseo', (tester) async {
    final controller = await _controller(roaming: true);
    await _pump(tester, controller, keyboardVisible: true);

    expect(find.byKey(const ValueKey('companion-roaming-pet')), findsNothing);
  });

  testWidgets('la pista admite altura intrínseca dentro de un ListView', (
    tester,
  ) async {
    final controller = await _controller(roaming: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.fromId('dark'),
        home: Scaffold(
          body: ListView(
            children: [
              CompanionRoamingOverlay(
                controller: controller,
                random: math.Random(7),
                child: const SizedBox(
                  height: 118,
                  child: ColoredBox(color: Colors.black),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('companion-roaming-pet')), findsOneWidget);
  });
}
