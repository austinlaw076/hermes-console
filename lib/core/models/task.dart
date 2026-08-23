import 'dart:convert';
import 'package:flutter/foundation.dart';

enum TaskPriority {
  high('alta'),
  medium('media'),
  low('baja');

  const TaskPriority(this.label);
  final String label;

  static TaskPriority fromString(String? v) {
    return TaskPriority.values.firstWhere(
      (p) => p.name == v,
      orElse: () => TaskPriority.medium,
    );
  }
}

enum TaskStatus {
  backlog('Backlog'),
  inProgress('In progress'),
  done('Done');

  const TaskStatus(this.label);
  final String label;

  static TaskStatus fromString(String? v) {
    return TaskStatus.values.firstWhere(
      (s) => s.name == v,
      orElse: () => TaskStatus.backlog,
    );
  }
}

class Task {
  final String id;
  final String title;
  final TaskPriority priority;

  /// Kanban column. Migrated from legacy `done` bool on first read:
  ///   done==true  → TaskStatus.done
  ///   done==false → TaskStatus.backlog
  final TaskStatus status;

  /// Optional free-form assignee label (e.g. "hermes", "manual", null).
  final String? assignee;

  final int createdAt;

  const Task({
    required this.id,
    required this.title,
    this.priority = TaskPriority.medium,
    this.status = TaskStatus.backlog,
    this.assignee,
    required this.createdAt,
  });

  /// Legacy read-only getter for code that still uses `done`.
  bool get done => status == TaskStatus.done;

  Task copyWith({
    String? title,
    TaskPriority? priority,
    TaskStatus? status,
    Object? assignee = _sentinel,
  }) => Task(
    id: id,
    title: title ?? this.title,
    priority: priority ?? this.priority,
    status: status ?? this.status,
    assignee: assignee == _sentinel ? this.assignee : (assignee as String?),
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'priority': priority.name,
    'status': status.name,
    if (assignee != null) 'assignee': assignee,
    'created_at': createdAt,
  };

  factory Task.fromJson(Map<String, dynamic> j) {
    // Migration: old records have only `done` bool, no `status` field.
    final TaskStatus resolvedStatus;
    if (j.containsKey('status')) {
      resolvedStatus = TaskStatus.fromString(j['status'] as String?);
    } else {
      // Legacy migration: done==true → done column, else → backlog
      final legacyDone = j['done'] as bool? ?? false;
      resolvedStatus = legacyDone ? TaskStatus.done : TaskStatus.backlog;
    }

    return Task(
      id: j['id'] as String? ?? '',
      title: j['title'] as String? ?? '',
      priority: TaskPriority.fromString(j['priority'] as String?),
      status: resolvedStatus,
      assignee: j['assignee'] as String?,
      createdAt: j['created_at'] as int? ?? 0,
    );
  }

  static List<Task> listFromJsonString(String raw) {
    try {
      final list = jsonDecode(raw) as List;
      return list.whereType<Map<String, dynamic>>().map(Task.fromJson).toList();
    } catch (e) {
      debugPrint('[task] excepción silenciada (se devuelve lista vacía): $e');
      return [];
    }
  }

  static String listToJsonString(List<Task> tasks) =>
      jsonEncode(tasks.map((t) => t.toJson()).toList());
}

// Sentinel to distinguish "set to null" from "not provided" in copyWith.
const Object _sentinel = Object();
