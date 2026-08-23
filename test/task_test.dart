import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/task.dart';

void main() {
  group('TaskPriority', () {
    test('fromString returns correct priority for each name', () {
      expect(TaskPriority.fromString('high'), TaskPriority.high);
      expect(TaskPriority.fromString('medium'), TaskPriority.medium);
      expect(TaskPriority.fromString('low'), TaskPriority.low);
    });

    test('fromString falls back to medium for unknown values', () {
      expect(TaskPriority.fromString(null), TaskPriority.medium);
      expect(TaskPriority.fromString(''), TaskPriority.medium);
      expect(TaskPriority.fromString('unknown'), TaskPriority.medium);
    });

    test('labels are in Spanish', () {
      expect(TaskPriority.high.label, 'alta');
      expect(TaskPriority.medium.label, 'media');
      expect(TaskPriority.low.label, 'baja');
    });
  });

  group('TaskStatus', () {
    test('fromString returns correct status for each name', () {
      expect(TaskStatus.fromString('backlog'), TaskStatus.backlog);
      expect(TaskStatus.fromString('inProgress'), TaskStatus.inProgress);
      expect(TaskStatus.fromString('done'), TaskStatus.done);
    });

    test('fromString falls back to backlog for unknown values', () {
      expect(TaskStatus.fromString(null), TaskStatus.backlog);
      expect(TaskStatus.fromString(''), TaskStatus.backlog);
      expect(TaskStatus.fromString('unknown'), TaskStatus.backlog);
    });
  });

  group('Task', () {
    test('fromJson captures all fields (new format with status)', () {
      final t = Task.fromJson({
        'id': 'abc-123',
        'title': 'Revisar logs',
        'priority': 'high',
        'status': 'inProgress',
        'assignee': 'hermes',
        'created_at': 1749476527,
      });

      expect(t.id, 'abc-123');
      expect(t.title, 'Revisar logs');
      expect(t.priority, TaskPriority.high);
      expect(t.status, TaskStatus.inProgress);
      expect(t.assignee, 'hermes');
      expect(t.done, isFalse);
      expect(t.createdAt, 1749476527);
    });

    test('fromJson migrates legacy done=false to backlog', () {
      final t = Task.fromJson({
        'id': 'x',
        'title': 'Cosa',
        'priority': 'medium',
        'done': false,
        'created_at': 0,
      });

      expect(t.status, TaskStatus.backlog);
      expect(t.done, isFalse);
    });

    test('fromJson migrates legacy done=true to done status', () {
      final t = Task.fromJson({
        'id': 'y',
        'title': 'Hecha',
        'priority': 'low',
        'done': true,
        'created_at': 0,
      });

      expect(t.status, TaskStatus.done);
      expect(t.done, isTrue);
    });

    test('fromJson uses defaults for missing fields', () {
      final t = Task.fromJson({'id': 'x', 'title': 'Cosa', 'created_at': 0});

      expect(t.priority, TaskPriority.medium);
      expect(t.status, TaskStatus.backlog);
      expect(t.done, isFalse);
      expect(t.assignee, isNull);
    });

    test('toJson round-trips through fromJson', () {
      const original = Task(
        id: 'round-trip-1',
        title: 'Test task',
        priority: TaskPriority.low,
        status: TaskStatus.done,
        assignee: 'manual',
        createdAt: 1749000000,
      );

      final restored = Task.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.priority, original.priority);
      expect(restored.status, original.status);
      expect(restored.done, original.done);
      expect(restored.assignee, original.assignee);
      expect(restored.createdAt, original.createdAt);
    });

    test('copyWith preserves unmodified fields', () {
      const base = Task(
        id: 'copy-1',
        title: 'Original',
        priority: TaskPriority.high,
        status: TaskStatus.backlog,
        createdAt: 1000,
      );

      final updated = base.copyWith(status: TaskStatus.done);
      expect(updated.id, base.id);
      expect(updated.title, base.title);
      expect(updated.priority, base.priority);
      expect(updated.done, isTrue);
      expect(updated.createdAt, base.createdAt);
    });

    test('copyWith can change priority and title independently', () {
      const base = Task(
        id: 'copy-2',
        title: 'Old',
        priority: TaskPriority.high,
        status: TaskStatus.backlog,
        createdAt: 2000,
      );

      final updated = base.copyWith(title: 'New', priority: TaskPriority.low);
      expect(updated.title, 'New');
      expect(updated.priority, TaskPriority.low);
      expect(updated.done, isFalse);
    });

    test('copyWith can set assignee to null via sentinel', () {
      const base = Task(
        id: 'copy-3',
        title: 'With assignee',
        status: TaskStatus.inProgress,
        assignee: 'hermes',
        createdAt: 3000,
      );

      final cleared = base.copyWith(assignee: null);
      expect(cleared.assignee, isNull);

      // Without passing assignee — should keep original
      final kept = base.copyWith(title: 'Changed');
      expect(kept.assignee, 'hermes');
    });
  });

  group('Task list serialization', () {
    test('listToJsonString and listFromJsonString are inverse operations', () {
      final tasks = [
        const Task(
          id: 'a',
          title: 'A',
          priority: TaskPriority.high,
          status: TaskStatus.backlog,
          createdAt: 100,
        ),
        const Task(
          id: 'b',
          title: 'B',
          priority: TaskPriority.low,
          status: TaskStatus.done,
          assignee: 'hermes',
          createdAt: 200,
        ),
      ];

      final json = Task.listToJsonString(tasks);
      final restored = Task.listFromJsonString(json);

      expect(restored, hasLength(2));
      expect(restored[0].id, 'a');
      expect(restored[0].priority, TaskPriority.high);
      expect(restored[1].done, isTrue);
      expect(restored[1].assignee, 'hermes');
    });

    test('listFromJsonString returns empty list for empty array string', () {
      expect(Task.listFromJsonString('[]'), isEmpty);
    });

    test('listFromJsonString returns empty list for malformed JSON', () {
      expect(Task.listFromJsonString('not-json'), isEmpty);
      expect(Task.listFromJsonString('{]'), isEmpty);
    });

    test('listToJsonString produces valid JSON array', () {
      final json = Task.listToJsonString([
        const Task(id: 'z', title: 'Zzz', createdAt: 0),
      ]);
      final decoded = jsonDecode(json);
      expect(decoded, isA<List>());
      expect((decoded as List).length, 1);
    });
  });
}
