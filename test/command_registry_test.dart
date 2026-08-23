import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/capability_descriptor.dart';
import 'package:hermes_android/core/models/command_descriptor.dart';
import 'package:hermes_android/core/services/command_registry.dart';

CommandDescriptor _local({
  required String name,
  CommandOrigin origin = CommandOrigin.native,
  CommandExecutorKind executor = CommandExecutorKind.native,
  String? capabilityKey,
  Iterable<String> aliases = const [],
  CommandSurface surface = CommandSurface.sheet,
}) => CommandDescriptor(
  canonicalName: name,
  aliases: aliases,
  category: CommandCategory.context,
  origin: origin,
  surface: surface,
  argumentSpec: CommandArgumentSpec(
    kind: CommandArgumentKind.freeText,
    maxLength: 500,
  ),
  executor: executor,
  capabilityKey: capabilityKey,
  scope: OperationScope.session,
  risk: OperationRisk.medium,
  availability: CapabilityState.available,
);

CommandRegistry _registry({Iterable<CommandDescriptor> native = const []}) =>
    CommandRegistry(
      connectionId: 'conn-047',
      backendIdentity: BackendIdentity(family: 'hermes', version: '0.19.0'),
      nativeDescriptors: native,
      now: () => DateTime.utc(2026, 7, 22),
    );

void main() {
  test('adapter tipado gana al catálogo y conserva aliases', () {
    final registry = _registry(
      native: [
        _local(
          name: 'compress',
          origin: CommandOrigin.typedAdapter,
          executor: CommandExecutorKind.typedRpc,
          capabilityKey: 'slash.exec',
        ),
      ],
    );
    registry.replaceCatalog(
      DesktopCommandCatalog.fromJson({
        'commands': [
          {
            'name': '/compress',
            'aliases': ['/summarize'],
            'category': 'context',
            'scope': 'session',
            'risk': 'medium',
          },
        ],
      }),
    );

    final exact = registry.resolve('/compress');
    final alias = registry.resolve('/SUMMARIZE');
    expect(exact.kind, CommandResolutionKind.found);
    expect(exact.descriptor?.origin, CommandOrigin.typedAdapter);
    expect(alias.kind, CommandResolutionKind.found);
    expect(alias.descriptor?.canonicalName, 'compress');
    expect(alias.matchedAlias, isTrue);
  });

  test('colisión semántica incompatible queda conflict y no ejecutable', () {
    final registry = _registry(
      native: [
        _local(
          name: 'status',
          executor: CommandExecutorKind.native,
          surface: CommandSurface.navigation,
        ),
      ],
    );
    registry.replaceCatalog(
      DesktopCommandCatalog.fromJson({
        'pairs': [
          ['/status', 'Remote status'],
        ],
      }),
    );

    final resolution = registry.resolve('status');
    expect(resolution.kind, CommandResolutionKind.conflict);
    expect(resolution.descriptor?.availability, CapabilityState.forbidden);
    expect(resolution.descriptor?.surface, CommandSurface.unavailable);
  });

  test('completion desconocida nunca concede available ni entra al índice', () {
    final registry = _registry();
    registry.replaceCompletions(
      SlashCompletionBatch.fromJson({
        'replace_from': 1,
        'items': [
          {'text': 'extension-cmd', 'display': '/extension-cmd'},
        ],
      }, input: '/ext'),
    );

    expect(
      registry.resolve('extension-cmd').kind,
      CommandResolutionKind.unknown,
    );
    expect(
      registry.completionSuggestions.single.availability,
      CapabilityState.unknown,
    );
  });

  test('catálogo real categories/pairs/canon se normaliza sin raw maps', () {
    final catalog = DesktopCommandCatalog.fromJson({
      'categories': [
        {
          'name': 'Session',
          'pairs': [
            ['/usage', 'Show usage'],
          ],
        },
      ],
      'pairs': [
        ['/usage', 'Show usage'],
        ['/gif-search', 'Synthetic skill'],
      ],
      'canon': {'/u': '/usage', '/usage': '/usage'},
      'skill_count': 1,
    });

    expect(catalog.commands, hasLength(2));
    expect(
      catalog.commands
          .firstWhere((entry) => entry.canonicalName == 'usage')
          .aliases,
      contains('u'),
    );
    expect(catalog.skillCount, 1);
  });

  test('exceso de comandos queda partial y acotado, nunca lanza', () {
    final catalog = DesktopCommandCatalog.fromJson({
      'commands': List.generate(
        501,
        (index) => {'name': 'cmd$index', 'description': 'Synthetic'},
      ),
    });

    expect(catalog.partial, isTrue);
    expect(catalog.commands, hasLength(500));
  });
}
