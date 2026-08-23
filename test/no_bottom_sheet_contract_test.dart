import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('user-facing core UI does not introduce modal bottom sheets', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: 'lib must exist');

    final violations = <String>[];
    for (final entity in lib.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = _withoutComments(entity.readAsStringSync());
      if (_bottomSheetSurface.hasMatch(source)) {
        violations.add(entity.path);
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Use showHermesFloatingSurface for user-facing modal UI. '
          'Bottom sheets make controls feel detached from the element that '
          'opened them: ${violations.join(', ')}',
    );
  });
}

final _bottomSheetSurface = RegExp(
  r'\b(?:showModalBottomSheet|showBottomSheet)\s*'
  r'(?:<[^>{}()]*>)?\s*\(|\bBottomSheet\s*\(',
);

String _withoutComments(String source) {
  return source
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'//[^\r\n]*'), '');
}
