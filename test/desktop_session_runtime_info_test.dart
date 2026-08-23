import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/desktop_session_snapshot.dart';

void main() {
  test('session.info identical is structurally equal across parses', () {
    final first = DesktopSessionRuntimeInfo.fromJson(const {
      'model': 'gpt-5.5',
      'provider': 'openai-codex',
      'fast': false,
      'project': {'id': 'project-a', 'name': 'Project A'},
      'usage': {'context_used': 500, 'context_max': 1000},
      'future_scalar': 4,
    });
    final second = DesktopSessionRuntimeInfo.fromJson(const {
      'model': 'gpt-5.5',
      'provider': 'openai-codex',
      'fast': false,
      'project': {'id': 'project-a', 'name': 'Project A'},
      'usage': {'context_used': 500, 'context_max': 1000},
      'future_scalar': 4,
    });

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });

  test('session.info changes only when a semantic field changes', () {
    final normal = DesktopSessionRuntimeInfo.fromJson(const {
      'model': 'gpt-5.5',
      'usage': {'context_used': 500, 'context_max': 1000},
    });
    final fast = DesktopSessionRuntimeInfo.fromJson(const {
      'model': 'gpt-5.5',
      'fast': true,
      'usage': {'context_used': 500, 'context_max': 1000},
    });

    expect(normal, isNot(fast));
  });

  test('system prompt remains discarded from equality and raw state', () {
    final first = DesktopSessionRuntimeInfo.fromJson(const {
      'model': 'gpt-5.5',
      'system_prompt': 'private prompt one',
    });
    final second = DesktopSessionRuntimeInfo.fromJson(const {
      'model': 'gpt-5.5',
      'system_prompt': 'private prompt two',
    });

    expect(first, second);
    expect(first.raw, isNot(contains('system_prompt')));
  });
}
