import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/companion/data/companion_preferences.dart';
import 'package:hermes_android/core/companion/data/companion_repository.dart';
import 'package:hermes_android/core/companion/models/companion.dart';
import 'package:hermes_android/core/companion/models/companion_presence_level.dart';
import 'package:hermes_android/core/companion/render/companion_message_presence.dart';
import 'package:hermes_android/core/companion/render/companion_view.dart';
import 'package:hermes_android/core/companion/state/companion_controller.dart';
import 'package:hermes_android/core/widgets/hermes_spark_mascot.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Repo sin IO real: sin importadas, catálogo vacío → CompanionView cae a
// HermesSparkMascot (procedural, sin IO).
class _Repo extends CompanionRepository {
  @override
  Future<Directory?> importedRoot() async => null;
  @override
  Future<List<Companion>> loadAll() async => const [];
}

Future<CompanionController> _build() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = CompanionPreferences(await SharedPreferences.getInstance());
  final companion = CompanionController(_Repo(), prefs);
  await companion.init();
  return companion;
}

Future<void> _pump(
  WidgetTester tester,
  CompanionController companion,
  HermesSparkMood mood, {
  bool animateIdle = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: CompanionMessagePresence(
            companion: companion,
            mood: mood,
            animateIdle: animateIdle,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('nivel full → renderiza la mascota del turno', (tester) async {
    final companion = await _build();
    await companion.setPresenceLevel(CompanionPresenceLevel.full);
    await _pump(tester, companion, HermesSparkMood.thinking);
    expect(find.byType(CompanionView), findsOneWidget);
  });

  testWidgets('el estado vacío puede mantener el reposo animado', (
    tester,
  ) async {
    final companion = await _build();
    await companion.setPresenceLevel(CompanionPresenceLevel.full);
    await _pump(tester, companion, HermesSparkMood.idle, animateIdle: true);

    expect(
      tester.widget<CompanionView>(find.byType(CompanionView)).animate,
      true,
    );
  });

  testWidgets('deshabilitado → invisible (shrink)', (tester) async {
    final companion = await _build();
    await companion.setEnabled(false);
    await _pump(tester, companion, HermesSparkMood.thinking);
    expect(find.byType(CompanionView), findsNothing);
  });

  testWidgets('nivel off → invisible', (tester) async {
    final companion = await _build();
    await companion.setPresenceLevel(CompanionPresenceLevel.off);
    await _pump(tester, companion, HermesSparkMood.idle);
    expect(find.byType(CompanionView), findsNothing);
  });

  testWidgets('nivel minimal → invisible dentro de Chat', (tester) async {
    final companion = await _build(); // default minimal
    await _pump(tester, companion, HermesSparkMood.idle);
    expect(find.byType(CompanionView), findsNothing);
  });

  testWidgets('no intercepta gestos: sin GestureDetector propio', (
    tester,
  ) async {
    final companion = await _build();
    await companion.setPresenceLevel(CompanionPresenceLevel.full);
    await _pump(tester, companion, HermesSparkMood.thinking);
    // La presencia por mensaje es decorativa: no debe envolver en un
    // GestureDetector que robe taps de selección/copy/voz del mensaje.
    expect(
      find.descendant(
        of: find.byType(CompanionMessagePresence),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
    );
  });

  testWidgets('reduce-motion: monta sin excepción', (tester) async {
    final companion = await _build();
    await companion.setPresenceLevel(CompanionPresenceLevel.full);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Center(
              child: CompanionMessagePresence(
                companion: companion,
                mood: HermesSparkMood.thinking,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CompanionView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
