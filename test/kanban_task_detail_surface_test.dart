import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/kanban.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/kanban_task_detail_surface.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

void main() {
  Future<void> pumpSurface(
    WidgetTester tester, {
    required KanbanTaskDetail detail,
    bool readOnly = false,
    KanbanCommentAction? onAddComment,
    Size physicalSize = const Size(900, 1600),
    Locale locale = const Locale('es'),
  }) async {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        theme: AppTheme.fromId('dark'),
        home: Scaffold(
          body: KanbanTaskDetailSurface(
            detail: detail,
            readOnly: readOnly,
            onAddComment: onAddComment,
            onUploadAttachment: () async {},
            onDownloadAttachment: (_) async {},
            onDeleteAttachment: (_) async {},
            onInspectRun: (_) async {},
            onTerminateRun: (_) async {},
            onShowLog: () async {},
            onReclaim: () async {},
            onReassign: () async {},
            onSpecify: () async {},
            onDecompose: () async {},
            onConfigureModel: () async {},
            onOpenLinkedTask: (_) async {},
            onArchive: () {},
            onDelete: () {},
            onMove: () {},
            onEdit: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('detalle 0.20 muestra secciones ricas y envía comentario', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? submitted;
    final detail = KanbanTaskDetail.fromJson({
      'task': {
        'id': 't1',
        'title': 'Investigar fallo',
        'body': 'Cuerpo completo',
        'status': 'triage',
        'diagnostics': [
          {
            'kind': 'stuck',
            'severity': 'warning',
            'title': 'Atascada',
            'detail': 'No progresa',
          },
        ],
      },
      'comments': [
        {'id': 1, 'author': 'tester', 'body': 'Reproducido'},
      ],
      'attachments': [
        {'id': 2, 'filename': 'trace.txt', 'size': 12},
      ],
      'runs': [
        {'id': 3, 'status': 'failed', 'ended_at': 100},
      ],
      'events': [
        {
          'id': 4,
          'kind': 'blocked',
          'payload': {'reason': 'timeout'},
        },
      ],
      'links': {
        'parents': ['parent'],
        'children': ['child'],
      },
      'child_results': [
        {'id': 'child', 'title': 'Subtarea', 'status': 'done'},
      ],
    });

    await pumpSurface(
      tester,
      detail: detail,
      onAddComment: (body) async => submitted = body,
    );

    expect(
      find.byKey(const ValueKey('kanban-detail-diagnostics')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('kanban-detail-links')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('kanban-detail-children')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('kanban-detail-comments')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('kanban-detail-attachments')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('kanban-detail-runs')), findsOneWidget);
    expect(find.byKey(const ValueKey('kanban-detail-events')), findsOneWidget);
    expect(find.byKey(const ValueKey('kanban-task-specify')), findsOneWidget);
    expect(find.byKey(const ValueKey('kanban-task-decompose')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('kanban-comment-field')),
      'Nueva pista',
    );
    await tester.tap(find.byKey(const ValueKey('kanban-comment-send')));
    await tester.pump();

    expect(submitted, 'Nueva pista');
    expect(tester.takeException(), isNull);
  });

  testWidgets('zh_Hant muestra texto escrito de Hong Kong', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final detail = KanbanTaskDetail.fromJson({
      'task': {
        'id': 't1',
        'title': 'Investigate',
        'status': 'triage',
        'diagnostics': [
          {'kind': 'stuck', 'severity': 'warning', 'title': 'Stuck'},
        ],
      },
    });

    await pumpSurface(
      tester,
      detail: detail,
      locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    );

    expect(find.text('診斷資料 · 1'), findsOneWidget);
  });

  testWidgets('solo lectura conserva inspección y bloquea mutaciones', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final detail = KanbanTaskDetail.fromJson({
      'task': {'id': 't1', 'title': 'Running', 'status': 'running'},
      'comments': [],
      'attachments': [],
      'runs': [
        {'id': 3, 'status': 'running'},
      ],
      'events': [],
      'links': {},
      'child_results': [],
    });

    await pumpSurface(tester, detail: detail, readOnly: true);

    expect(
      find.byKey(const ValueKey('kanban-detail-read-only')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('kanban-comment-field')), findsNothing);
    expect(
      find.byKey(const ValueKey('kanban-attachment-upload')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('kanban-run-terminate-3')), findsNothing);
    expect(find.byKey(const ValueKey('kanban-task-archive')), findsNothing);
    expect(find.byKey(const ValueKey('kanban-model-override')), findsOneWidget);
    expect(find.byIcon(Icons.monitor_heart_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('respuesta legacy oculta secciones inexistentes', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final detail = KanbanTaskDetail.fromJson({
      'id': 'legacy',
      'title': 'Legacy',
      'status': 'todo',
    });

    await pumpSurface(tester, detail: detail);

    expect(find.byKey(const ValueKey('kanban-detail-comments')), findsNothing);
    expect(
      find.byKey(const ValueKey('kanban-detail-attachments')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('kanban-detail-runs')), findsNothing);
    expect(find.byKey(const ValueKey('kanban-detail-events')), findsNothing);
    expect(find.byKey(const ValueKey('kanban-detail-links')), findsNothing);
    expect(find.byKey(const ValueKey('kanban-detail-children')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ancho estrecho apila acciones y no muestra rutas remotas', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final detail = KanbanTaskDetail.fromJson({
      'task': {'id': 't1', 'title': 'Estrecha', 'status': 'todo'},
      'attachments': [
        {'id': 2, 'filename': '/srv/hermes/private/trace.txt', 'size': 12},
      ],
    });

    await pumpSurface(
      tester,
      detail: detail,
      physicalSize: const Size(320, 1200),
    );

    expect(find.text('trace.txt'), findsOneWidget);
    expect(find.textContaining('/srv/hermes'), findsNothing);
    expect(find.byKey(const ValueKey('kanban-task-archive')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('kanban-task-delete-permanent')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
