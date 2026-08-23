import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/desktop_compression_result.dart';
import 'package:hermes_android/core/models/desktop_session_snapshot.dart';

Map<String, dynamic> _validResult() => {
  'status': 'compressed',
  'removed': 4,
  'before_messages': 6,
  'after_messages': 2,
  'before_tokens': 179492,
  'after_tokens': 4821,
  'summary': {
    'noop': false,
    'headline': 'Compressed: 6 → 2 messages',
    'token_line': 'Approx request size: ~179,492 → ~4,821 tokens',
  },
  'usage': {
    'calls': 12,
    'total': 201000,
    'context_used': 4821,
    'context_max': 200000,
  },
  'info': {
    'stored_session_id': '20260722_094311_continuation',
    'model': 'openai/gpt-5.5-codex',
    'usage': {'context_used': 4821, 'context_max': 200000},
  },
  'messages': [
    {'role': 'user', 'content': 'Resumen de la conversación anterior'},
    {'role': 'assistant', 'content': 'Contexto conservado'},
  ],
};

void main() {
  test('parsea transcript, métricas y continuación durable de Hermes 0.19', () {
    final result = DesktopCompressionResult.fromJson(_validResult());

    expect(result.status, 'compressed');
    expect(result.removed, 4);
    expect(result.beforeMessages, 6);
    expect(result.afterMessages, 2);
    expect(result.beforeTokens, 179492);
    expect(result.afterTokens, 4821);
    expect(result.summary.noop, isFalse);
    expect(result.usage?.contextUsed, 4821);
    expect(result.info.storedSessionId, '20260722_094311_continuation');
    expect(result.messages, hasLength(2));
    expect(result.messages.first.role, DesktopSessionMessageRole.user);
    expect(result.messages.last.text, 'Contexto conservado');
  });

  test('rechaza respuestas parciales o transcripts inconsistentes', () {
    final missingSummary = _validResult()..remove('summary');
    expect(
      () => DesktopCompressionResult.fromJson(missingSummary),
      throwsFormatException,
    );

    final invalidMessage = _validResult()
      ..['messages'] = [
        {'content': 'sin role'},
        {'role': 'assistant', 'content': 'respuesta'},
      ];
    expect(
      () => DesktopCompressionResult.fromJson(invalidMessage),
      throwsFormatException,
    );

    final invalidCount = _validResult()..['after_messages'] = 3;
    expect(
      () => DesktopCompressionResult.fromJson(invalidCount),
      throwsFormatException,
    );
  });
}
