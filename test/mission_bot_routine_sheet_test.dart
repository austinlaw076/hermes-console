import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/mission_bot_routine_sheet.dart';
import 'package:hermes_android/core/theme/app_theme.dart';

void main() {
  testWidgets(
    'starts with bot, What and When while advanced fields stay hidden',
    (tester) async {
      MissionBotRoutineDraft? submitted;
      await tester.pumpWidget(
        _host(
          onCreate: (draft) async => submitted = draft,
          copy: MissionBotRoutineSheetCopy.es,
        ),
      );

      expect(find.text('Nueva rutina'), findsOneWidget);
      expect(find.text('Hermes QA · @codex-qa'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mission-avatar-geometry-codex-qa')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.smart_toy_outlined), findsNothing);
      expect(find.text('Qué'), findsOneWidget);
      expect(find.text('Cuándo'), findsOneWidget);
      expect(find.text('Cada día · 09:00'), findsOneWidget);
      expect(find.text('Más opciones'), findsOneWidget);
      expect(find.byKey(const ValueKey('mission-routine-name')), findsNothing);
      expect(find.text('Destino'), findsNothing);
      expect(find.text('Modelo'), findsNothing);
      expect(find.text('Start from'), findsNothing);

      await _enter(
        tester,
        const ValueKey('mission-routine-prompt'),
        'Revisa las copias de seguridad',
      );
      await tester.tap(find.byKey(const ValueKey('mission-routine-submit')));
      await tester.pumpAndSettle();

      expect(submitted?.name, isEmpty);
      expect(submitted?.prompt, 'Revisa las copias de seguridad');
      expect(submitted?.schedule, '0 9 * * *');
    },
  );

  for (final row in const <(String, String)>[
    ('Días laborables · 09:00', '0 9 * * 1-5'),
    ('Cada lunes · 09:00', '0 9 * * 1'),
    ('Cada mes · día 1, 09:00', '0 9 1 * *'),
    ('Cada hora', '0 * * * *'),
    ('Cada 15 minutos', '*/15 * * * *'),
  ]) {
    testWidgets('${row.$1} submits its canonical cron expression', (
      tester,
    ) async {
      MissionBotRoutineDraft? submitted;
      await tester.pumpWidget(
        _host(
          onCreate: (draft) async => submitted = draft,
          copy: MissionBotRoutineSheetCopy.es,
        ),
      );
      await _selectSchedule(tester, row.$1);
      await _enter(
        tester,
        const ValueKey('mission-routine-prompt'),
        'Haz el trabajo',
      );

      await tester.tap(find.byKey(const ValueKey('mission-routine-submit')));
      await tester.pumpAndSettle();

      expect(submitted?.schedule, row.$2);
    });
  }

  testWidgets(
    'custom schedule reveals raw cron and optional name is explicit',
    (tester) async {
      MissionBotRoutineDraft? submitted;
      await tester.pumpWidget(
        _host(
          onCreate: (draft) async => submitted = draft,
          copy: MissionBotRoutineSheetCopy.es,
        ),
      );

      await _selectSchedule(tester, 'Personalizado');
      expect(
        find.byKey(const ValueKey('mission-routine-custom-schedule')),
        findsOneWidget,
      );
      final moreOptions = find.byKey(
        const ValueKey('mission-routine-more-options'),
      );
      await tester.ensureVisible(moreOptions);
      await tester.pumpAndSettle();
      await tester.tap(moreOptions);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('mission-routine-name')),
        findsOneWidget,
      );

      await _enter(
        tester,
        const ValueKey('mission-routine-prompt'),
        'Comprueba el nodo',
      );
      await _enter(
        tester,
        const ValueKey('mission-routine-custom-schedule'),
        '7 6 * * 2',
      );
      await _enter(
        tester,
        const ValueKey('mission-routine-name'),
        'Chequeo semanal',
      );
      await tester.tap(find.byKey(const ValueKey('mission-routine-submit')));
      await tester.pumpAndSettle();

      expect(submitted?.name, 'Chequeo semanal');
      expect(submitted?.prompt, 'Comprueba el nodo');
      expect(submitted?.schedule, '7 6 * * 2');
    },
  );

  testWidgets('requires What and the raw expression for a custom schedule', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _host(
        onCreate: (_) async => calls++,
        copy: MissionBotRoutineSheetCopy.es,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('mission-routine-submit')));
    await tester.pump();
    expect(find.text('Escribe qué debe hacer el bot.'), findsOneWidget);
    expect(calls, 0);

    await _enter(tester, const ValueKey('mission-routine-prompt'), 'Haz algo');
    await _selectSchedule(tester, 'Personalizado');
    await tester.tap(find.byKey(const ValueKey('mission-routine-submit')));
    await tester.pump();

    expect(find.text('Escribe una expresión cron.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('async submit blocks a second tap until completion', (
    tester,
  ) async {
    final completion = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      _host(
        onCreate: (_) {
          calls++;
          return completion.future;
        },
        copy: MissionBotRoutineSheetCopy.es,
      ),
    );
    await _enter(
      tester,
      const ValueKey('mission-routine-prompt'),
      'Revisa el estado',
    );

    await tester.tap(find.byKey(const ValueKey('mission-routine-submit')));
    await tester.pump();
    final submitting = tester.widget<FilledButton>(
      find.byKey(const ValueKey('mission-routine-submit')),
    );
    expect(submitting.onPressed, isNull);
    expect(find.text('Creando…'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('mission-routine-submit')),
      warnIfMissed: false,
    );
    expect(calls, 1);

    completion.complete();
    await tester.pumpAndSettle();
    final ready = tester.widget<FilledButton>(
      find.byKey(const ValueKey('mission-routine-submit')),
    );
    expect(ready.onPressed, isNotNull);
    expect(calls, 1);
  });

  testWidgets('callback failure shows only a generic in-place error', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        onCreate: (_) async => throw StateError('secret server detail'),
        copy: MissionBotRoutineSheetCopy.es,
      ),
    );
    await _enter(
      tester,
      const ValueKey('mission-routine-prompt'),
      'Genera un informe',
    );

    await tester.tap(find.byKey(const ValueKey('mission-routine-submit')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mission-routine-submit-error')),
      findsOneWidget,
    );
    expect(
      find.text('No se pudo crear la rutina. Inténtalo de nuevo.'),
      findsOneWidget,
    );
    expect(find.textContaining('secret server detail'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('mission-routine-submit')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('uses injectable English copy', (tester) async {
    await tester.pumpWidget(
      _host(onCreate: (_) async {}, copy: MissionBotRoutineSheetCopy.en),
    );

    expect(find.text('New routine'), findsOneWidget);
    expect(find.text('What'), findsOneWidget);
    expect(find.text('When'), findsOneWidget);
    expect(find.text('More options'), findsOneWidget);
    expect(find.text('Create routine'), findsOneWidget);
  });

  testWidgets('fits 320dp at 200 percent text without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _host(
        onCreate: (_) async {},
        copy: MissionBotRoutineSheetCopy.es,
        textScale: 2,
        width: 320,
        height: 760,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mission-routine-submit')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mission-routine-scroll')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _host({
  required MissionBotRoutineSubmit onCreate,
  required MissionBotRoutineSheetCopy copy,
  double textScale = 1,
  double width = 520,
  double height = 700,
}) => MaterialApp(
  theme: AppTheme.fromId('dark'),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: Material(
              color: Theme.of(context).dialogTheme.backgroundColor,
              child: MissionBotRoutineSheet(
                botProfile: 'codex-qa',
                botDisplayName: 'Hermes QA',
                copy: copy,
                onCreate: onCreate,
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _enter(WidgetTester tester, Key fieldKey, String value) async {
  final field = find.descendant(
    of: find.byKey(fieldKey),
    matching: find.byType(EditableText),
  );
  await tester.enterText(field, value);
  await tester.pump();
}

Future<void> _selectSchedule(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('mission-routine-schedule')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}
