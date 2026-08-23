import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/subagent_activity.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/accent_card.dart';
import 'package:hermes_android/core/widgets/hermes_premium_ui.dart';
import 'package:hermes_android/core/widgets/subagent_activity_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

final SubagentActivityScope _scope = SubagentActivityScope(
  connectionId: 'connection-card',
  parentSessionId: 'parent-card',
  runtimeSessionId: 'runtime-card',
  turnEpoch: 1,
);

SubagentActivity _nativeActivity({
  String subagentId = 'child-card',
  String childSessionId = 'child-session-card',
  String goalPreview = 'Revisar el proyecto',
  String? summaryPreview,
  SubagentActivityPhase phase = SubagentActivityPhase.running,
}) => SubagentActivity(
  key: SubagentActivityKey(
    scope: _scope,
    identityKind: SubagentIdentityKind.subagent,
    stableId: subagentId,
  ),
  source: SubagentActivitySource.native,
  phase: phase,
  subagentId: subagentId,
  childSessionId: childSessionId,
  details: SubagentActivityDetails(
    goalPreview: goalPreview,
    summaryPreview: summaryPreview,
  ),
);

SubagentActivity _legacyActivity() => SubagentActivity(
  key: SubagentActivityKey(
    scope: _scope,
    identityKind: SubagentIdentityKind.legacyToolCall,
    stableId: 'legacy-call-card',
  ),
  source: SubagentActivitySource.legacyDelegateTask,
  phase: SubagentActivityPhase.running,
  legacyToolCallId: 'legacy-call-card',
  details: const SubagentActivityDetails(),
);

Widget _app({
  required List<SubagentActivity> activities,
  required bool Function(SubagentActivity) canInterrupt,
  bool Function(SubagentActivity)? interruptPending,
  bool Function(SubagentActivity)? openPending,
  ValueChanged<SubagentActivity>? onOpen,
  ValueChanged<SubagentActivity>? onInterrupt,
  TextScaler textScaler = TextScaler.noScaling,
}) => MaterialApp(
  locale: const Locale('es'),
  localizationsDelegates: const [
    Strings.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: Strings.supportedLocales,
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(size: const Size(390, 844), textScaler: textScaler),
      child: SingleChildScrollView(
        child: SubagentActivityCard(
          activities: activities,
          canInterrupt: canInterrupt,
          isInterruptPending: interruptPending,
          isOpenPending: openPending,
          onOpenConversation: onOpen,
          onInterrupt: onInterrupt,
        ),
      ),
    ),
  ),
);

Widget _chatLikeApp({required List<SubagentActivity> activities}) =>
    MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: const [
        Strings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: Strings.supportedLocales,
      home: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Column(
          children: [
            const Expanded(child: SizedBox.expand()),
            SubagentActivityCard(
              activities: activities,
              canInterrupt: (_) => true,
              onOpenConversation: (_) {},
              onInterrupt: (_) {},
            ),
            const SizedBox(height: 72),
          ],
        ),
      ),
    );

void main() {
  testWidgets('hijo nativo abre transcript y detiene solo esa fila', (
    tester,
  ) async {
    final activity = _nativeActivity();
    SubagentActivity? opened;
    SubagentActivity? interrupted;
    await tester.pumpWidget(
      _app(
        activities: [activity],
        canInterrupt: (_) => true,
        onOpen: (value) => opened = value,
        onInterrupt: (value) => interrupted = value,
      ),
    );

    expect(find.byType(HermesInlineActivity), findsOneWidget);
    expect(find.byType(AccentCard), findsNothing);
    expect(
      find.byKey(const ValueKey('subagent-open-child-card')),
      findsNothing,
    );
    await tester.tap(find.text('ver detalles'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('subagent-open-child-card')));
    await tester.tap(find.byKey(const ValueKey('subagent-stop-child-card')));

    expect(opened, same(activity));
    expect(interrupted, same(activity));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('subagent-open-child-card')))
          .height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('subagent-stop-child-card')))
          .height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('pending deshabilita ambas acciones y muestra progreso', (
    tester,
  ) async {
    final activity = _nativeActivity();
    await tester.pumpWidget(
      _app(
        activities: [activity],
        canInterrupt: (_) => true,
        interruptPending: (_) => true,
        openPending: (_) => true,
        onOpen: (_) {},
        onInterrupt: (_) {},
      ),
    );

    await tester.tap(find.text('ver detalles'));
    await tester.pump(const Duration(milliseconds: 250));
    final open = tester.widget<TextButton>(
      find.byKey(const ValueKey('subagent-open-child-card')),
    );
    final stop = tester.widget<TextButton>(
      find.byKey(const ValueKey('subagent-stop-child-card')),
    );
    expect(open.onPressed, isNull);
    expect(stop.onPressed, isNull);
    expect(find.text('Abriendo…'), findsOneWidget);
    expect(find.text('Deteniendo…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
  });

  testWidgets('solo lectura conserva abrir pero oculta detener', (
    tester,
  ) async {
    final activity = _nativeActivity();
    await tester.pumpWidget(
      _app(
        activities: [activity],
        canInterrupt: (_) => false,
        onOpen: (_) {},
        onInterrupt: (_) {},
      ),
    );

    await tester.tap(find.text('ver detalles'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('subagent-open-child-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('subagent-stop-child-card')),
      findsNothing,
    );
  });

  testWidgets('fallback legacy no inventa transcript ni control', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        activities: [_legacyActivity()],
        canInterrupt: (_) => false,
        onOpen: (_) {},
        onInterrupt: (_) {},
      ),
    );

    await tester.tap(find.text('ver detalles'));
    await tester.pumpAndSettle();
    expect(find.text('Abrir conversación'), findsNothing);
    expect(find.text('Detener'), findsNothing);
  });

  testWidgets('detalle corto también permanece plegado por defecto', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        activities: [
          _nativeActivity(subagentId: 'child-1'),
          _nativeActivity(subagentId: 'child-2'),
        ],
        canInterrupt: (_) => false,
      ),
    );

    final scrollables = find.descendant(
      of: find.byType(SubagentActivityCard),
      matching: find.byType(Scrollable),
    );
    expect(scrollables, findsNothing);
    expect(find.text('Revisar el proyecto'), findsNothing);
    expect(find.text('ver detalles'), findsOneWidget);

    await tester.tap(find.text('ver detalles'));
    await tester.pumpAndSettle();

    expect(find.text('Revisar el proyecto'), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byType(SubagentActivityCard),
        matching: find.byType(Scrollable),
      ),
      findsOneWidget,
    );
  });

  testWidgets('muchos subagentes colapsados no desbordan con teclado', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 500);
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _chatLikeApp(
        activities: List.generate(
          8,
          (index) => _nativeActivity(
            subagentId: 'child-$index',
            childSessionId: 'child-session-$index',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(SubagentActivityCard)).height,
      lessThanOrEqualTo(148),
    );
    expect(find.text('ver detalles'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SubagentActivityCard),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
    );

    await tester.tap(find.text('ver detalles'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(SubagentActivityCard)).height,
      lessThanOrEqualTo(208),
    );
  });

  testWidgets('historial largo se despliega en un scroll acotado', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        activities: List.generate(
          8,
          (index) => _nativeActivity(
            subagentId: 'child-$index',
            childSessionId: 'child-session-$index',
          ),
        ),
        canInterrupt: (_) => true,
        onOpen: (_) {},
        onInterrupt: (_) {},
      ),
    );

    await tester.tap(find.text('ver detalles'));
    await tester.pumpAndSettle();

    expect(find.text('ocultar detalles'), findsOneWidget);
    final scroll = find.descendant(
      of: find.byType(SubagentActivityCard),
      matching: find.byType(Scrollable),
    );
    expect(
      tester.state<ScrollableState>(scroll).position.maxScrollExtent,
      greaterThan(0),
    );
  });

  testWidgets('previews Markdown se muestran como texto compacto', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        activities: [
          _nativeActivity(
            goalPreview: '# **Auditar** `Markdown`',
            summaryPreview:
                '## Resultado\n- **Todo** [bien](https://example.com)',
          ),
        ],
        canInterrupt: (_) => false,
      ),
    );

    await tester.tap(find.text('ver detalles'));
    await tester.pumpAndSettle();

    expect(find.text('Auditar Markdown'), findsOneWidget);
    expect(find.textContaining('Resultado'), findsOneWidget);
    expect(find.textContaining('Todo bien'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
    expect(find.textContaining('##'), findsNothing);
    expect(find.textContaining('https://'), findsNothing);
    final detail = tester.widget<Text>(find.textContaining('Todo bien'));
    expect(detail.style?.fontSize, 12);
  });

  testWidgets('estado completado queda neutral y el disclosure mide 48 dp', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        activities: [_nativeActivity(phase: SubagentActivityPhase.completed)],
        canInterrupt: (_) => false,
      ),
    );

    final disclosure = find.ancestor(
      of: find.text('ver detalles'),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(disclosure.first).height, greaterThanOrEqualTo(48));

    await tester.tap(find.text('ver detalles'));
    await tester.pumpAndSettle();

    final completed = tester.widget<Text>(find.text('completado'));
    final colors = Theme.of(
      tester.element(find.byType(SubagentActivityCard)),
    ).hermes;
    expect(completed.style?.color, colors.textSecondary);
    expect(completed.style?.fontSize, 12);
  });

  testWidgets('escala 2 conserva contenido y acciones sin overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        activities: [_nativeActivity()],
        canInterrupt: (_) => true,
        onOpen: (_) {},
        onInterrupt: (_) {},
        textScaler: const TextScaler.linear(2),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('ver detalles'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('subagent-open-child-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('subagent-stop-child-card')),
      findsOneWidget,
    );
  });
}
