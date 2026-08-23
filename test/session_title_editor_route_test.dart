import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/session_title_editor_route.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

void main() {
  Future<void> pumpHost(
    WidgetTester tester, {
    ValueChanged<String?>? onResult,
  }) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        theme: AppTheme.fromId('dark'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const ValueKey('open-session-title-editor'),
                onPressed: () async {
                  final result = await showSessionTitleEditorRoute(
                    context,
                    initialTitle: 'Título actual',
                  );
                  onResult?.call(result);
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('la ruta flotante cancela y guarda sin desmontar el foco', (
    tester,
  ) async {
    final results = <String?>[];
    await pumpHost(tester, onResult: results.add);

    await tester.tap(find.byKey(const ValueKey('open-session-title-editor')));
    await tester.pumpAndSettle();

    final surface = find.byKey(const ValueKey('session-title-editor-surface'));
    final field = find.byKey(const ValueKey('session-title-editor-field'));
    expect(surface, findsOneWidget);
    expect(tester.getSize(surface).width, lessThanOrEqualTo(328));
    expect(tester.widget<TextField>(field).focusNode?.hasFocus, isTrue);

    await tester.enterText(field, 'No guardar');
    await tester.tap(find.text('Cancelar'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(surface, findsNothing);
    expect(results, [null]);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('open-session-title-editor')));
    await tester.pumpAndSettle();
    await tester.enterText(field, 'Título nuevo');
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(surface, findsNothing);
    expect(results, [null, 'Título nuevo']);
    expect(tester.takeException(), isNull);
  });
}
