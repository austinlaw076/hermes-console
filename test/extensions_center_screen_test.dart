import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/desktop_control_center.dart';
import 'package:hermes_android/core/screens/extensions_center_screen.dart';
import 'package:hermes_android/core/services/desktop_control_gateway.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/hermes_premium_ui.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

class _ExtensionsGateway implements HermesDesktopControlGateway {
  ExtensionsInventory inventory = const ExtensionsInventory(
    plugins: [],
    toolsets: [],
  );
  Object? loadFailure;
  int loadCalls = 0;
  final List<(String, bool)> pluginChanges = [];
  final List<(String, bool, String)> toolsetChanges = [];
  final List<(String, bool)> reloads = [];

  @override
  Future<ExtensionsInventory> extensionsInventory({
    String runtimeSessionId = '',
  }) async {
    loadCalls++;
    if (loadFailure case final failure?) throw failure;
    return inventory;
  }

  @override
  Future<void> setPluginEnabled(String name, bool enabled) async {
    pluginChanges.add((name, enabled));
  }

  @override
  Future<void> setToolsetEnabled(
    String name,
    bool enabled, {
    String runtimeSessionId = '',
  }) async {
    toolsetChanges.add((name, enabled, runtimeSessionId));
  }

  @override
  Future<void> reloadMcp({
    String runtimeSessionId = '',
    required bool confirmed,
  }) async {
    reloads.add((runtimeSessionId, confirmed));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ManagedExtensionsGateway extends _ExtensionsGateway
    implements HermesExtensionManagementGateway {
  final List<(String, bool)> pluginInstalls = [];
  final List<String> pluginUpdates = [];
  final List<String> pluginRemovals = [];
  final List<(String, Map<String, String>)> mcpInstalls = [];
  final List<(String, bool)> mcpChanges = [];
  final List<String> mcpRemovals = [];

  List<DesktopPluginManagementEntry> pluginControls = const [];
  List<DesktopMcpServerEntry> servers = const [];
  List<DesktopMcpCatalogEntry> catalog = const [];

  @override
  Future<List<DesktopPluginManagementEntry>> managedPlugins() async =>
      pluginControls;

  @override
  Future<DesktopExtensionInstallResult> installPlugin(
    String identifier, {
    required bool enable,
  }) async {
    pluginInstalls.add((identifier, enable));
    return const DesktopExtensionInstallResult(accepted: true);
  }

  @override
  Future<void> updatePlugin(String name) async => pluginUpdates.add(name);

  @override
  Future<void> removePlugin(String name) async => pluginRemovals.add(name);

  @override
  Future<List<DesktopMcpServerEntry>> mcpServers() async => servers;

  @override
  Future<List<DesktopMcpCatalogEntry>> mcpCatalog() async => catalog;

  @override
  Future<DesktopExtensionInstallResult> installMcpCatalogEntry(
    String name, {
    Map<String, String> environment = const {},
  }) async {
    mcpInstalls.add((name, Map<String, String>.of(environment)));
    return const DesktopExtensionInstallResult(accepted: true);
  }

  @override
  Future<void> setMcpServerEnabled(String name, bool enabled) async =>
      mcpChanges.add((name, enabled));

  @override
  Future<void> removeMcpServer(String name) async => mcpRemovals.add(name);

  @override
  Future<DesktopMcpProbeResult> testMcpServer(String name) async =>
      const DesktopMcpProbeResult(
        ok: true,
        toolCount: 2,
        authorizationRequired: false,
      );
}

Widget _app(Widget home, {Locale locale = const Locale('es')}) => MaterialApp(
  locale: locale,
  localizationsDelegates: Strings.localizationsDelegates,
  supportedLocales: Strings.supportedLocales,
  theme: AppTheme.fromId('dark'),
  home: home,
);

ExtensionsInventory _inventory() => const ExtensionsInventory(
  plugins: [
    DesktopPluginEntry(
      name: 'memory-tools',
      version: '1.2.0',
      description:
          'Memoria local en /private/host/plugins con sk-supersecret123',
      source: '/home/alice/.hermes/plugins/memory-tools',
      status: 'enabled',
    ),
  ],
  toolsets: [
    DesktopToolsetEntry(
      name: 'web',
      description: 'Herramientas web seguras',
      toolCount: 2,
      enabled: false,
      tools: ['search', 'fetch'],
    ),
  ],
);

DesktopMcpCatalogEntry _catalogEntry() => const DesktopMcpCatalogEntry(
  name: 'filesystem-safe',
  description: 'Acceso acotado a archivos del servidor',
  source: 'hermes-catalog',
  transport: 'stdio',
  authType: 'env',
  command: 'npx',
  args: ['-y', '@modelcontextprotocol/server-filesystem'],
  url: '',
  installUrl: '',
  installRef: '',
  bootstrap: [],
  postInstall: '',
  requiredEnv: [
    DesktopMcpEnvRequirement(
      name: 'MCP_TOKEN',
      prompt: 'Token del servidor',
      required: true,
    ),
  ],
  needsInstall: false,
  installed: false,
  enabled: false,
);

void main() {
  testWidgets('renders typed inventory without paths, secrets or raw JSON', (
    tester,
  ) async {
    final gateway = _ExtensionsGateway()..inventory = _inventory();

    await tester.pumpWidget(
      _app(
        ExtensionsCenterScreen(gateway: gateway, runtimeSessionId: 'runtime-a'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Extensiones'), findsOneWidget);
    expect(find.text('Plugins'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('extensions-section-tools')),
      findsOneWidget,
    );
    expect(find.text('memory-tools'), findsOneWidget);
    expect(find.text('web'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('extensions-section-tools')));
    await tester.pumpAndSettle();
    expect(find.text('web'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('extensions-active-only')));
    await tester.pumpAndSettle();
    expect(find.text('web'), findsNothing);

    expect(find.textContaining('/private/host'), findsNothing);
    expect(find.textContaining('/home/alice'), findsNothing);
    expect(find.textContaining('sk-supersecret'), findsNothing);
    expect(find.textContaining('{"'), findsNothing);
  });

  testWidgets('shows active items first and filters the inventory', (
    tester,
  ) async {
    final gateway = _ExtensionsGateway()
      ..inventory = const ExtensionsInventory(
        plugins: [
          DesktopPluginEntry(
            name: 'zeta-disabled',
            version: '',
            description: '',
            source: '',
            status: 'disabled',
          ),
          DesktopPluginEntry(
            name: 'beta-active',
            version: '',
            description: '',
            source: '',
            status: 'enabled',
          ),
          DesktopPluginEntry(
            name: 'alpha-active',
            version: '',
            description: '',
            source: '',
            status: 'enabled',
          ),
        ],
        toolsets: [],
      );

    await tester.pumpWidget(_app(ExtensionsCenterScreen(gateway: gateway)));
    await tester.pumpAndSettle();

    expect(find.text('zeta-disabled'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('alpha-active')).dy,
      lessThan(tester.getTopLeft(find.text('beta-active')).dy),
    );

    await tester.tap(find.byKey(const ValueKey('extensions-active-only')));
    await tester.pumpAndSettle();
    expect(find.text('zeta-disabled'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('extensions-active-only')));
    await tester.pumpAndSettle();
    expect(find.text('zeta-disabled'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('extensions-search-plugins')),
      'zeta',
    );
    await tester.pumpAndSettle();
    expect(find.text('zeta-disabled'), findsOneWidget);
    expect(find.text('alpha-active'), findsNothing);
    expect(find.text('beta-active'), findsNothing);
  });

  testWidgets('plugin and tool toggles require confirmation and refresh', (
    tester,
  ) async {
    final gateway = _ExtensionsGateway()..inventory = _inventory();

    await tester.pumpWidget(
      _app(
        ExtensionsCenterScreen(gateway: gateway, runtimeSessionId: 'runtime-a'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('plugin-toggle-memory-tools')));
    await tester.pumpAndSettle();
    expect(gateway.pluginChanges, isEmpty);
    await tester.tap(find.text('Confirmar cambio'));
    await tester.pumpAndSettle();
    expect(gateway.pluginChanges, [('memory-tools', false)]);
    expect(gateway.loadCalls, 2);

    await tester.tap(find.byKey(const ValueKey('extensions-section-tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toolset-toggle-web')));
    await tester.pumpAndSettle();
    expect(gateway.toolsetChanges, isEmpty);
    await tester.tap(find.text('Confirmar cambio'));
    await tester.pumpAndSettle();
    expect(gateway.toolsetChanges, [('web', true, 'runtime-a')]);
    expect(gateway.loadCalls, 3);
  });

  testWidgets('MCP reload requires explicit confirmation=true', (tester) async {
    final gateway = _ExtensionsGateway()..inventory = _inventory();

    await tester.pumpWidget(
      _app(
        ExtensionsCenterScreen(gateway: gateway, runtimeSessionId: 'runtime-a'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('extensions-section-mcp')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recargar MCP'));
    await tester.pumpAndSettle();
    expect(gateway.reloads, isEmpty);
    await tester.tap(find.text('Recargar ahora'));
    await tester.pumpAndSettle();

    expect(gateway.reloads, [('runtime-a', true)]);
    expect(gateway.loadCalls, 2);
  });

  testWidgets('read-only disables every mutating control and sends zero RPCs', (
    tester,
  ) async {
    final gateway = _ExtensionsGateway()..inventory = _inventory();

    await tester.pumpWidget(
      _app(
        ExtensionsCenterScreen(
          gateway: gateway,
          runtimeSessionId: 'runtime-a',
          readOnly: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('solo lectura'), findsWidgets);
    final pluginSwitch = tester.widget<Switch>(
      find.byKey(const ValueKey('plugin-toggle-memory-tools')),
    );
    expect(pluginSwitch.onChanged, isNull);

    await tester.tap(find.byKey(const ValueKey('extensions-section-tools')));
    await tester.pumpAndSettle();
    final toolSwitch = tester.widget<Switch>(
      find.byKey(const ValueKey('toolset-toggle-web')),
    );
    expect(toolSwitch.onChanged, isNull);

    await tester.tap(find.byKey(const ValueKey('extensions-section-mcp')));
    await tester.pumpAndSettle();
    final reload = tester.widget<HermesListRow>(
      find.byKey(const ValueKey('extensions-reload-mcp')),
    );
    expect(reload.enabled, isFalse);
    expect(reload.onTap, isNull);
    expect(gateway.pluginChanges, isEmpty);
    expect(gateway.toolsetChanges, isEmpty);
    expect(gateway.reloads, isEmpty);
  });

  testWidgets('unsupported inventory is explicit instead of an empty claim', (
    tester,
  ) async {
    final gateway = _ExtensionsGateway()
      ..loadFailure = const DesktopControlFailure(
        DesktopControlFailureKind.unsupported,
        code: -32601,
      );

    await tester.pumpWidget(_app(ExtensionsCenterScreen(gateway: gateway)));
    await tester.pumpAndSettle();

    expect(
      find.text('Esta versión de Hermes no publica plugins ni herramientas.'),
      findsOneWidget,
    );
    expect(find.text('No hay plugins instalados.'), findsNothing);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('renders extension inventory copy in English', (tester) async {
    final gateway = _ExtensionsGateway();

    await tester.pumpWidget(
      _app(
        ExtensionsCenterScreen(gateway: gateway),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Extensions'), findsOneWidget);
    expect(find.text('No plugins installed.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('extensions-section-tools')));
    await tester.pumpAndSettle();
    expect(find.text('No tool groups published.'), findsOneWidget);
  });

  testWidgets(
    'plugin install validates, reviews and sends one typed mutation',
    (tester) async {
      final gateway = _ManagedExtensionsGateway();

      await tester.pumpWidget(_app(ExtensionsCenterScreen(gateway: gateway)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('extensions-install-plugin')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('extensions-plugin-identifier')),
        'nousresearch/example-plugin',
      );
      await tester.tap(find.text('Revisar e instalar'));
      await tester.pumpAndSettle();

      expect(find.text('Confirmar instalación'), findsOneWidget);
      expect(
        find.textContaining('nousresearch/example-plugin'),
        findsOneWidget,
      );
      expect(gateway.pluginInstalls, isEmpty);

      await tester.tap(find.text('Instalar'));
      await tester.pumpAndSettle();

      expect(gateway.pluginInstalls, [('nousresearch/example-plugin', true)]);
    },
  );

  testWidgets('unsafe plugin source never reaches the management gateway', (
    tester,
  ) async {
    final gateway = _ManagedExtensionsGateway();

    await tester.pumpWidget(_app(ExtensionsCenterScreen(gateway: gateway)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('extensions-install-plugin')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('extensions-plugin-identifier')),
      'http://user:pass@example.test/plugin?token=secret',
    );
    await tester.tap(find.text('Revisar e instalar'));
    await tester.pump();

    expect(
      find.textContaining('Usa owner/repo o una URL Git HTTPS'),
      findsOneWidget,
    );
    expect(gateway.pluginInstalls, isEmpty);
  });

  testWidgets('MCP review keeps credentials ephemeral and sends them once', (
    tester,
  ) async {
    final gateway = _ManagedExtensionsGateway()..catalog = [_catalogEntry()];

    await tester.pumpWidget(_app(ExtensionsCenterScreen(gateway: gateway)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('extensions-section-mcp')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('extensions-open-mcp-catalog')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('filesystem-safe'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('mcp-env-MCP_TOKEN')),
      'test-secret-value',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('mcp-env-MCP_TOKEN')))
          .obscureText,
      isTrue,
    );
    await tester.tap(find.text('Instalar servidor'));
    await tester.pumpAndSettle();

    expect(gateway.mcpInstalls, hasLength(1));
    expect(gateway.mcpInstalls.single.$1, 'filesystem-safe');
    expect(gateway.mcpInstalls.single.$2, {'MCP_TOKEN': 'test-secret-value'});
    expect(find.byKey(const ValueKey('mcp-env-MCP_TOKEN')), findsNothing);
    expect(find.text('test-secret-value'), findsNothing);
  });
}
