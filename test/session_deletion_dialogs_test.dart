import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/services/session_deletion.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/session_deletion_dialogs.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

void main() {
  testWidgets('el diálogo Cron separa chat y programación', (tester) async {
    final session = Session.fromJson({
      'id': 'cron_daily_20260717_090000',
      'title': 'Resumen diario',
      'source': 'cron',
    });
    LinkedCronDeletionMode? selected;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        theme: AppTheme.fromId('dark'),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await showCronConversationDeleteDialog(
                  context,
                  session,
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('¿Qué quieres borrar?'), findsOneWidget);
    expect(find.text('Solo chat'), findsOneWidget);
    expect(find.text('Chat y tarea'), findsOneWidget);
    expect(find.text('Conserva activa la tarea programada.'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('cron_delete_conversation_only')),
    );
    await tester.pumpAndSettle();
    expect(selected, LinkedCronDeletionMode.keepSchedule);

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('cron_delete_conversation_and_schedule')),
    );
    await tester.pumpAndSettle();
    expect(selected, LinkedCronDeletionMode.deleteSchedule);
    expect(tester.takeException(), isNull);
  });

  testWidgets('las opciones compactas caben a 320 dp con texto al 200 %', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = Session.fromJson({
      'id': 'cron_daily_20260717_090000',
      'title': 'Resumen diario',
      'source': 'cron',
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        theme: AppTheme.fromId('dark'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showCronConversationDeleteDialog(context, session),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Solo chat'), findsOneWidget);
    expect(find.text('Chat y tarea'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
