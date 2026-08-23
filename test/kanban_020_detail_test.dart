import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/kanban.dart';

void main() {
  test('detalle 0.20 conserva historial rico sin exponer stored_path', () {
    final detail = KanbanTaskDetail.fromJson({
      'task': {
        'id': 't_020',
        'title': 'Investigar regresión',
        'body': 'Cuerpo completo',
        'status': 'blocked',
        'model_override': 'gpt-5.6',
        'provider_override': 'openai',
        'reasoning_effort': 'high',
        'diagnostics': [
          {
            'kind': 'worker_crash_loop',
            'severity': 'critical',
            'title': 'El worker falla repetidamente',
            'detail': 'Tres ejecuciones terminaron con error.',
            'count': 3,
            'run_id': 41,
            'actions': [
              {
                'kind': 'reassign',
                'label': 'Reasignar',
                'suggested': true,
                'payload': {'reclaim_first': true},
              },
            ],
          },
        ],
      },
      'comments': [
        {
          'id': 7,
          'task_id': 't_020',
          'author': 'tester',
          'body': 'Reproducido en QA',
          'created_at': 1700,
        },
      ],
      'events': [
        {
          'id': 9,
          'task_id': 't_020',
          'kind': 'worker_failed',
          'payload': {'reason': 'timeout'},
          'created_at': 1800,
          'run_id': 41,
        },
      ],
      'attachments': [
        {
          'id': 11,
          'task_id': 't_020',
          'filename': 'trace.txt',
          'content_type': 'text/plain',
          'size': 1234,
          'uploaded_by': 'tester',
          'stored_path': '/home/server/private/trace.txt',
          'created_at': 1750,
        },
      ],
      'links': {
        'parents': ['t_parent'],
        'children': ['t_child'],
      },
      'child_results': [
        {
          'id': 't_child',
          'title': 'Subtarea',
          'status': 'done',
          'latest_summary': 'Completada',
          'result': 'OK',
        },
      ],
      'runs': [
        {
          'id': 41,
          'task_id': 't_020',
          'profile': 'default',
          'status': 'failed',
          'worker_pid': 999,
          'started_at': 1710,
          'ended_at': 1790,
          'outcome': 'error',
          'summary': 'Falló al ejecutar',
          'error': 'timeout',
          'metadata': {'attempt': 3},
        },
      ],
    });

    expect(detail.task.id, 't_020');
    expect(detail.task.modelOverride, 'gpt-5.6');
    expect(detail.task.providerOverride, 'openai');
    expect(detail.task.reasoningEffort, 'high');
    expect(detail.comments.single.body, 'Reproducido en QA');
    expect(detail.events.single.payload, {'reason': 'timeout'});
    expect(detail.attachments.single.id, '11');
    expect(detail.attachments.single.filename, 'trace.txt');
    expect(
      detail.attachments.single.toString(),
      isNot(contains('/home/server')),
    );
    expect(detail.links.parents, ['t_parent']);
    expect(detail.supports(KanbanTaskDetailCapability.attachments), isTrue);
    expect(detail.childResults.single.latestSummary, 'Completada');
    expect(detail.runs.single.id, 41);
    expect(detail.runs.single.metadata, {'attempt': 3});

    final diagnostic = detail.diagnostics.single;
    expect(diagnostic.severity, KanbanDiagnosticSeverity.critical);
    expect(diagnostic.actions.single.kind, 'reassign');
    expect(diagnostic.actions.single.suggested, isTrue);

    expect(
      () => detail.comments.add(detail.comments.single),
      throwsUnsupportedError,
    );
    expect(
      () => detail.events.single.payload['extra'] = true,
      throwsUnsupportedError,
    );
  });

  test('detalle legacy degrada a listas vacías y conserva la tarjeta', () {
    final detail = KanbanTaskDetail.fromJson({
      'id': 'legacy',
      'title': 'Legacy',
      'status': 'todo',
    });

    expect(detail.task.id, 'legacy');
    expect(detail.comments, isEmpty);
    expect(detail.events, isEmpty);
    expect(detail.attachments, isEmpty);
    expect(detail.runs, isEmpty);
    expect(detail.diagnostics, isEmpty);
    expect(detail.links.parents, isEmpty);
    expect(detail.capabilities, isEmpty);
  });

  test('nombre seguro de adjunto nunca conserva segmentos de ruta', () {
    const attachment = KanbanAttachment(
      id: '7',
      filename: '../../private\\trace.txt',
    );

    expect(attachment.safeFilename, 'trace.txt');
    expect(attachment.safeFilename, isNot(contains('private')));
    expect(attachment.toString(), isNot(contains('private')));
  });

  test('model-options, decompose y bulk conservan resultados oficiales', () {
    final options = KanbanModelOptions.fromJson({
      'providers': [
        {
          'slug': 'openai',
          'label': 'OpenAI',
          'models': ['gpt-5.6', ''],
        },
      ],
    });
    final decompose = KanbanDecomposeResult.fromJson({
      'ok': true,
      'task_id': 'parent',
      'fanout': true,
      'child_ids': ['a', 'b'],
    });
    final bulk = KanbanBulkResult.fromJson({
      'results': [
        {'id': 'a', 'ok': true},
        {'id': 'b', 'ok': false, 'error': 'conflict'},
      ],
    });

    expect(options.providers.single.models, ['gpt-5.6']);
    expect(decompose.childIds, ['a', 'b']);
    expect(bulk.succeeded.single.id, 'a');
    expect(bulk.failed.single.error, 'conflict');
  });

  test('log e inspección toleran valores ausentes del servidor', () {
    final log = KanbanTaskLog.fromJson({
      'task_id': 't_020',
      'exists': true,
      'size_bytes': 9000,
      'content': 'tail',
      'truncated': true,
      'path': '/server/path/ignored.log',
    });
    final inspection = KanbanRunInspection.fromJson({
      'run_id': 41,
      'alive': true,
      'pid': 999,
      'cpu_percent': 12.5,
      'memory_rss_bytes': 4096,
      'num_threads': 4,
      'status': 'sleeping',
      'cmdline': ['python', 'worker.py'],
    });

    expect(log.content, 'tail');
    expect(log.truncated, isTrue);
    expect(log.toString(), isNot(contains('/server/path')));
    expect(inspection.alive, isTrue);
    expect(inspection.cpuPercent, 12.5);
    expect(inspection.command, ['python', 'worker.py']);
  });
}
