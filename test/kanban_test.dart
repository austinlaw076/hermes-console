import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/kanban.dart';

void main() {
  group('KanbanBoard.fromJson', () {
    test('parsea columnas y tarjetas del board de Hermes', () {
      final board = KanbanBoard.fromJson({
        'latest_event_id': 42,
        'columns': [
          {
            'name': 'todo',
            'tasks': [
              {
                'id': 't1',
                'title': 'Primera',
                'body': 'cuerpo',
                'status': 'todo',
                'priority': 3, // el servidor manda priority como ENTERO
                'assignee': 'nous',
                'comment_count': 2,
                'progress': {'done': 1, 'total': 3},
              },
            ],
          },
          {'name': 'done', 'tasks': []},
        ],
      });

      expect(board.latestEventId, 42);
      expect(board.columns.length, 2);
      expect(board.taskCount, 1);

      final t = board.columns.first.tasks.single;
      expect(t.id, 't1');
      expect(t.title, 'Primera');
      expect(t.status, 'todo');
      expect(t.priority, 'high');
      expect(t.assignee, 'nous');
      expect(t.commentCount, 2);
      expect(t.progressDone, 1);
      expect(t.progressTotal, 3);
      expect(t.hasProgress, isTrue);
    });

    test('tolera campos ausentes con valores por defecto', () {
      final board = KanbanBoard.fromJson({
        'columns': [
          {
            'name': 'triage',
            'tasks': [
              {'id': 'x', 'title': 'Solo título'},
            ],
          },
        ],
      });
      final t = board.columns.first.tasks.single;
      expect(t.body, '');
      expect(t.status, 'todo');
      expect(t.priority, isNull);
      expect(t.commentCount, 0);
      expect(t.hasProgress, isFalse);
      expect(board.latestEventId, 0);
    });
  });

  group('KanbanTask', () {
    test('isBlocked por status o block_reason', () {
      final byStatus = KanbanTask.fromJson({
        'id': '1',
        'title': 'a',
        'status': 'blocked',
      });
      expect(byStatus.isBlocked, isTrue);

      final byReason = KanbanTask.fromJson({
        'id': '2',
        'title': 'b',
        'status': 'todo',
        'block_reason': 'espera dependencia',
      });
      expect(byReason.isBlocked, isTrue);

      final notBlocked = KanbanTask.fromJson({
        'id': '3',
        'title': 'c',
        'status': 'todo',
      });
      expect(notBlocked.isBlocked, isFalse);
    });

    test('copyWith cambia sólo el status', () {
      final t = KanbanTask.fromJson({
        'id': '1',
        'title': 'a',
        'status': 'todo',
        'priority': 1, // entero del servidor
      });
      final moved = t.copyWith(status: 'done');
      expect(moved.status, 'done');
      expect(moved.id, '1');
      expect(moved.title, 'a');
      expect(moved.priority, 'low');
    });

    test('priority entero ↔ etiqueta (fix del HTTP 422)', () {
      // Etiqueta → entero (lo que se manda al servidor).
      expect(kanbanPriorityToInt('high'), 3);
      expect(kanbanPriorityToInt('normal'), 2);
      expect(kanbanPriorityToInt('low'), 1);
      expect(kanbanPriorityToInt(null), 0);
      // Entero del servidor → etiqueta (lo que se muestra). 0 → sin chip.
      expect(kanbanPriorityLabel(3), 'high');
      expect(kanbanPriorityLabel(2), 'normal');
      expect(kanbanPriorityLabel(1), 'low');
      expect(kanbanPriorityLabel(0), isNull);
      expect(kanbanPriorityLabel(null), isNull);
    });

    test(
      'detalle conserva cuerpo, resultado y tiempos del recurso completo',
      () {
        final task = KanbanTask.fromJson({
          'id': 'detail',
          'title': 'Detalle',
          'body': 'Cuerpo completo',
          'status': 'done',
          'result': 'Resultado final',
          'latest_summary': 'Resumen completo',
          'created_at': 10,
          'started_at': '20',
          'completed_at': 30.8,
        });

        expect(task.body, 'Cuerpo completo');
        expect(task.result, 'Resultado final');
        expect(task.latestSummary, 'Resumen completo');
        expect(task.createdAt, 10);
        expect(task.startedAt, 20);
        expect(task.completedAt, 30);
        expect(task.copyWith(status: 'archived').result, 'Resultado final');
      },
    );
  });

  group('filtros móviles', () {
    KanbanTask task(String id, String status, {String? assignee}) => KanbanTask(
      id: id,
      title: 'Tarea $id',
      body: id == 'needle' ? 'Texto buscable' : '',
      status: status,
      assignee: assignee,
    );

    test('conserva cinco grupos humanos y archivo separado', () {
      expect(
        kanbanMobileGroupFor(task('a', 'blocked')),
        KanbanMobileGroup.attention,
      );
      expect(
        kanbanMobileGroupFor(task('b', 'running')),
        KanbanMobileGroup.working,
      );
      expect(
        kanbanMobileGroupFor(task('c', 'ready', assignee: 'default')),
        KanbanMobileGroup.queued,
      );
      expect(kanbanMobileGroupFor(task('d', 'todo')), KanbanMobileGroup.notes);
      expect(kanbanMobileGroupFor(task('e', 'done')), KanbanMobileGroup.done);
      expect(
        kanbanMobileGroupFor(task('f', 'archived')),
        KanbanMobileGroup.archived,
      );
    });

    test('búsqueda es local y archivo queda oculto salvo filtro explícito', () {
      final active = task('needle', 'todo');
      final archived = task('old', 'archived');

      expect(kanbanTaskMatchesFilter(active, query: 'BUSCABLE'), isTrue);
      expect(kanbanTaskMatchesFilter(active, query: 'missing'), isFalse);
      expect(kanbanTaskMatchesFilter(archived), isFalse);
      expect(
        kanbanTaskMatchesFilter(archived, group: KanbanMobileGroup.archived),
        isTrue,
      );
    });
  });

  test('catálogo multi-board exige slugs válidos e infiere el actual', () {
    final catalog = KanbanBoardCatalog.fromJson({
      'boards': [
        {'slug': 'default', 'name': 'Personal'},
        {'slug': 'project', 'name': 'Project', 'is_current': true},
        {'slug': ''},
      ],
    });

    expect(catalog.boards.map((board) => board.slug), ['default', 'project']);
    expect(catalog.current, 'project');
  });

  group('reglas de movimiento', () {
    test('running no es un destino movible por el cliente', () {
      expect(kKanbanMovableStatuses.contains('running'), isFalse);
    });

    test('estados editables sí son movibles', () {
      for (final s in [
        'triage',
        'todo',
        'ready',
        'blocked',
        'review',
        'done',
      ]) {
        expect(kKanbanMovableStatuses.contains(s), isTrue, reason: s);
      }
    });
  });

  test('kanbanColumnLabel mapea nombres conocidos y capitaliza el resto', () {
    expect(kanbanColumnLabel('todo'), 'To Do');
    expect(kanbanColumnLabel('running'), 'Running');
    expect(kanbanColumnLabel('custom'), 'Custom');
    expect(kanbanColumnLabel(''), '—');
  });
}
