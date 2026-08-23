import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/capability_descriptor.dart';
import 'package:hermes_android/core/models/command_descriptor.dart';

CommandDescriptor _descriptor({
  String name = 'compress',
  CommandOrigin origin = CommandOrigin.catalog,
}) => CommandDescriptor(
  canonicalName: name,
  aliases: const ['/SUMMARIZE', 'summarize'],
  description: 'Compress context',
  category: CommandCategory.context,
  origin: origin,
  surface: CommandSurface.remote,
  argumentSpec: CommandArgumentSpec(
    kind: CommandArgumentKind.freeText,
    maxLength: 500,
  ),
  executor: CommandExecutorKind.slashExec,
  capabilityKey: 'slash.exec',
  scope: OperationScope.session,
  risk: OperationRisk.medium,
  availability: CapabilityState.available,
);

void main() {
  test('normaliza canonical y aliases sin tocar argumentos free-text', () {
    final descriptor = _descriptor(name: ' /ComPress ');

    expect(descriptor.canonicalName, 'compress');
    expect(descriptor.aliases, {'summarize'});
    expect(
      descriptor.argumentSpec?.validate('  Release DECISIONS  '),
      'Release DECISIONS',
    );
  });

  test('rechaza nombres mayores de 64 o con separadores de shell', () {
    expect(() => _descriptor(name: 'x' * 65), throwsFormatException);
    expect(() => _descriptor(name: 'compress;rm'), throwsFormatException);
    expect(() => _descriptor(name: 'two words'), throwsFormatException);
  });

  test('precedencia coincide con native adapter catalog completion legacy', () {
    final values = CommandOrigin.values
        .map((origin) => _descriptor(origin: origin).precedence)
        .toList();

    expect(values, [5, 4, 3, 2, 1]);
  });

  test('request de scope session exige runtime y valida epochs', () {
    final descriptor = _descriptor();

    expect(
      () => CommandExecutionRequest(
        executionId: 'exec-1',
        command: descriptor,
        connectionId: 'conn-1',
        connectionEpoch: 1,
        sessionEpoch: 1,
        createdAt: DateTime.utc(2026, 7, 22),
      ),
      throwsFormatException,
    );
  });

  test('respuesta remota conserva solo texto acotado y aceptación tipada', () {
    final result = DesktopCommandRpcResult.fromJson({
      'type': 'exec',
      'output': 'x' * 5000,
      'secret': 'must-not-survive',
    });

    expect(result.kind, DesktopCommandDispatchKind.output);
    expect(result.accepted, DesktopCommandAcceptance.accepted);
    expect(result.output, hasLength(4000));
  });
}
