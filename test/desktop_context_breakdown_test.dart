import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/desktop_context_breakdown.dart';

void main() {
  test('parsea el contrato 0.19 y calcula porcentaje ausente', () {
    final breakdown = DesktopContextBreakdown.fromJson(const {
      'categories': [
        {'id': 'system_prompt', 'label': 'System prompt', 'tokens': 1200},
        {'id': 'conversation', 'label': 'Conversation', 'tokens': 3800},
      ],
      'context_used': 5000,
      'context_max': 20000,
      'estimated_total': 4900,
      'model': 'openai/gpt-5.5',
    });

    expect(breakdown.contextPercent, 25);
    expect(breakdown.categories, hasLength(2));
    expect(breakdown.categories.last.tokens, 3800);
    expect(breakdown.model, 'openai/gpt-5.5');
  });

  test('descarta categorías hostiles y acota porcentaje', () {
    final breakdown = DesktopContextBreakdown.fromJson({
      'categories': [
        {'id': '../secret', 'label': 'bad', 'tokens': 20},
        {'id': 'rules', 'label': 'Rules', 'tokens': -1},
        {'id': 'memory', 'label': 'Memory', 'tokens': 400},
        {'id': 'memory', 'label': 'Memory newest', 'tokens': 500},
        'not-a-map',
      ],
      'context_used': 500,
      'context_max': 1000,
      'context_percent': 900,
      'model': List.filled(300, 'x').join(),
    });

    expect(breakdown.contextPercent, 100);
    expect(breakdown.categories, hasLength(1));
    expect(breakdown.categories.single.tokens, 500);
    expect(breakdown.model, hasLength(160));
  });

  test('rechaza una raíz de categorías incompatible', () {
    expect(
      () => DesktopContextBreakdown.fromJson(const {'categories': 'private'}),
      throwsFormatException,
    );
  });
}
