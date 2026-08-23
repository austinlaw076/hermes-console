import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/artifact_export_service.dart';

String _repeat(String value, int count) => List.filled(count, value).join();

void main() {
  test('sanea nombres sin permitir rutas ni traversal', () {
    expect(
      PlatformArtifactExportActions.sanitizeFileName(
        '../../secrets/<panel>:v1?.html',
      ),
      '_panel__v1_.html',
    );
    expect(
      PlatformArtifactExportActions.sanitizeFileName('   '),
      'artifact.txt',
    );
  });

  test('acota nombres largos sin perder un nombre exportable', () {
    final value = PlatformArtifactExportActions.sanitizeFileName(
      '${_repeat('a', 180)}.txt',
    );

    expect(value.length, 120);
    expect(value, isNot(contains('/')));
  });
}
