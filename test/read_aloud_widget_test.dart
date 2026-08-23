import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/voice/read_aloud_session.dart';
import 'package:hermes_android/core/services/voice/speech_renderer.dart';
import 'package:hermes_android/core/services/voice/voice_settings.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/read_aloud_button.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

void main() {
  const chunks = [ReadAloudChunk('Texto.', NarrationPause.long)];

  Widget host(
    ValueNotifier<ReadAloudSnapshot> state, {
    ReadAloudStopBehavior behavior = ReadAloudStopBehavior.pauseAndResume,
    VoidCallback? onB,
  }) => MaterialApp(
    locale: const Locale('es'),
    localizationsDelegates: Strings.localizationsDelegates,
    supportedLocales: Strings.supportedLocales,
    theme: AppTheme.fromId('dark'),
    home: Scaffold(
      body: Row(
        children: [
          for (final key in const ['a', 'b', 'c'])
            ReadAloudButton(
              key: ValueKey('speaker-$key'),
              messageKey: key,
              state: state,
              stopBehavior: behavior,
              onPressed: key == 'b' ? onB : () {},
            ),
        ],
      ),
    ),
  );

  testWidgets('solo el mensaje propietario muestra Pausar', (tester) async {
    final state = ValueNotifier<ReadAloudSnapshot>(
      const ReadAloudSnapshot(
        phase: ReadAloudPhase.playing,
        messageKey: 'b',
        revision: 'r1',
        chunks: chunks,
        cursor: 0,
        epoch: 1,
        origin: ReadAloudOrigin.manual,
      ),
    );
    addTearDown(state.dispose);
    await tester.pumpWidget(host(state));

    expect(find.bySemanticsLabel('Pausar lectura'), findsOneWidget);
    expect(find.bySemanticsLabel('Leer en voz alta'), findsNWidgets(2));
  });

  testWidgets('la pausa cambia a Continuar y conserva un único propietario', (
    tester,
  ) async {
    final state = ValueNotifier<ReadAloudSnapshot>(
      const ReadAloudSnapshot(
        phase: ReadAloudPhase.paused,
        messageKey: 'b',
        revision: 'r1',
        chunks: chunks,
        cursor: 0,
        epoch: 2,
        origin: ReadAloudOrigin.manual,
      ),
    );
    addTearDown(state.dispose);
    await tester.pumpWidget(host(state));

    expect(find.bySemanticsLabel('Continuar lectura'), findsOneWidget);
    expect(find.bySemanticsLabel('Leer en voz alta'), findsNWidgets(2));
  });

  testWidgets('el modo reiniciar usa Detener y el botón mantiene 48 dp', (
    tester,
  ) async {
    var taps = 0;
    final state = ValueNotifier<ReadAloudSnapshot>(
      const ReadAloudSnapshot(
        phase: ReadAloudPhase.preparing,
        messageKey: 'b',
        revision: 'r1',
        chunks: chunks,
        cursor: 0,
        epoch: 1,
        origin: ReadAloudOrigin.manual,
      ),
    );
    addTearDown(state.dispose);
    await tester.pumpWidget(
      host(
        state,
        behavior: ReadAloudStopBehavior.stopAndRestart,
        onB: () => taps++,
      ),
    );

    final stop = find.bySemanticsLabel('Parar lectura');
    expect(stop, findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('speaker-b'))),
      const Size(48, 48),
    );
    await tester.tap(stop);
    expect(taps, 1);
  });
}
