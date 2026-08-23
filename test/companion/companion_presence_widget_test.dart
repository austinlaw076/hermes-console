import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/companion/data/companion_preferences.dart';
import 'package:hermes_android/core/companion/data/companion_repository.dart';
import 'package:hermes_android/core/companion/models/companion.dart';
import 'package:hermes_android/core/companion/models/companion_presence_level.dart';
import 'package:hermes_android/core/companion/render/companion_presence.dart';
import 'package:hermes_android/core/companion/render/companion_view.dart';
import 'package:hermes_android/core/companion/state/companion_controller.dart';
import 'package:hermes_android/core/companion/state/companion_presence_controller.dart';
import 'package:hermes_android/core/widgets/hermes_spark_mascot.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Repo de prueba sin IO real: sin importadas (importedRoot null), catálogo vacío
// → CompanionView cae a HermesSparkMascot (procedural, sin IO).
class _Repo extends CompanionRepository {
  @override
  Future<Directory?> importedRoot() async => null;
  @override
  Future<List<Companion>> loadAll() async => const [];
}

Future<(CompanionController, CompanionPresenceController)> _build() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = CompanionPreferences(await SharedPreferences.getInstance());
  final companion = CompanionController(_Repo(), prefs);
  await companion.init();
  return (companion, CompanionPresenceController());
}

Future<void> _pump(
  WidgetTester tester,
  CompanionController companion,
  CompanionPresenceController presence, {
  bool showLabel = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: CompanionPresence(
            presence: presence,
            companion: companion,
            showLabel: showLabel,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('habilitado → renderiza la mascota', (tester) async {
    final (companion, presence) = await _build();
    addTearDown(presence.dispose);
    await _pump(tester, companion, presence);
    expect(find.byType(CompanionView), findsOneWidget);
  });

  testWidgets('deshabilitado → invisible (shrink)', (tester) async {
    final (companion, presence) = await _build();
    addTearDown(presence.dispose);
    await companion.setEnabled(false);
    await _pump(tester, companion, presence);
    expect(find.byType(CompanionView), findsNothing);
  });

  testWidgets('nivel full + showLabel + thinking → muestra "Pensando…"', (
    tester,
  ) async {
    final (companion, presence) = await _build();
    addTearDown(presence.dispose);
    await companion.setPresenceLevel(CompanionPresenceLevel.full);
    presence.onEvent(PresenceEvent.messageSent); // salto breve
    presence.debugSettleTransient(); // decae el salto → pensando
    await _pump(tester, companion, presence, showLabel: true);
    expect(find.text('Pensando…'), findsOneWidget);
  });

  testWidgets('nivel minimal: no muestra texto aunque se pida', (tester) async {
    final (companion, presence) = await _build(); // default minimal
    addTearDown(presence.dispose);
    presence.onEvent(PresenceEvent.messageSent);
    presence.debugSettleTransient(); // decae el salto, evita timer pendiente
    await _pump(tester, companion, presence, showLabel: true);
    expect(find.text('Pensando…'), findsNothing);
    expect(find.byType(CompanionView), findsOneWidget); // mascota sí
  });

  testWidgets('nivel off → invisible', (tester) async {
    final (companion, presence) = await _build();
    addTearDown(presence.dispose);
    await companion.setPresenceLevel(CompanionPresenceLevel.off);
    await _pump(tester, companion, presence);
    expect(find.byType(CompanionView), findsNothing);
  });

  testWidgets('tap → petTapped (mood pasa a success)', (tester) async {
    final (companion, presence) = await _build();
    addTearDown(presence.dispose);
    await _pump(tester, companion, presence);
    expect(presence.mood, HermesSparkMood.idle);
    await tester.tap(find.byType(CompanionView));
    await tester.pump();
    expect(presence.mood, HermesSparkMood.success);
    // Deja expirar el timer de saludo para no dejar timers pendientes.
    await tester.pump(const Duration(milliseconds: 1300));
    expect(presence.mood, HermesSparkMood.idle);
  });

  testWidgets('reduce-motion: monta sin excepción', (tester) async {
    final (companion, presence) = await _build();
    addTearDown(presence.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Center(
              child: CompanionPresence(
                presence: presence,
                companion: companion,
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
