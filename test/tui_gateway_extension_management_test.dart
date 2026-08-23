import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_control_gateway.dart';
import 'package:hermes_android/core/services/tui_gateway_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

SavedConnection _connection({bool readOnly = false}) => SavedConnection(
  id: 'extensions-management',
  label: 'Extensions management',
  host: '127.0.0.1',
  port: 8642,
  apiKey: 'gateway-test-key',
  dashboardUrl: 'http://127.0.0.1:9119',
  readOnly: readOnly,
  kind: InstanceKind.vps,
);

DashboardClient _dashboard(http.Client client) => DashboardClient(
  host: '127.0.0.1',
  port: 9119,
  manualToken: 'dashboard-test-token',
  httpClientOverride: client,
);

Map<String, dynamic> _body(http.Request request) => request.body.isEmpty
    ? const <String, dynamic>{}
    : Map<String, dynamic>.from(jsonDecode(request.body) as Map);

void main() {
  test('uses the authenticated typed Dashboard extension endpoints', () async {
    final requests = <http.Request>[];
    final dashboardHttp = MockClient((request) async {
      requests.add(request);
      final payload = switch ((request.method, request.url.path)) {
        ('GET', '/api/dashboard/plugins/hub') => {
          'plugins': [
            {
              'name': 'git-plugin',
              'source': 'git',
              'runtime_status': 'enabled',
              'can_update_git': true,
              'can_remove': true,
              'auth_required': false,
              'path': '/private/server/path',
            },
          ],
        },
        ('POST', '/api/dashboard/agent-plugins/install') => {
          'ok': true,
          'plugin_name': 'git-plugin',
        },
        ('POST', '/api/dashboard/agent-plugins/git-plugin/update') => {
          'ok': true,
        },
        ('DELETE', '/api/dashboard/agent-plugins/git-plugin') => {'ok': true},
        ('GET', '/api/mcp/servers') => {
          'servers': [
            {
              'name': 'server-a',
              'transport': 'http',
              'url': 'https://mcp.example.test',
              'enabled': true,
              'tools': ['search'],
            },
          ],
        },
        ('GET', '/api/mcp/catalog') => {
          'entries': [
            {
              'name': 'catalog-a',
              'source': 'hermes-catalog',
              'transport': 'stdio',
              'command': 'npx',
              'args': ['server-a'],
              'required_env': [
                {'name': 'MCP_TOKEN', 'prompt': 'Token', 'required': true},
              ],
            },
          ],
        },
        ('POST', '/api/mcp/catalog/install') => {
          'ok': true,
          'name': 'catalog-a',
          'background': false,
        },
        ('PUT', '/api/mcp/servers/server-a/enabled') => {
          'ok': true,
          'name': 'server-a',
          'enabled': false,
        },
        ('DELETE', '/api/mcp/servers/server-a') => {'ok': true},
        ('POST', '/api/mcp/servers/server-a/test') => {
          'ok': true,
          'tools': ['search'],
        },
        _ => <String, dynamic>{},
      };
      return http.Response(jsonEncode(payload), 200);
    });
    final dashboard = _dashboard(dashboardHttp);
    final client = TuiGatewayClient(_connection(), dashboard: dashboard);
    addTearDown(client.close);

    final plugins = await client.managedPlugins();
    final pluginInstall = await client.installPlugin(
      'nousresearch/git-plugin',
      enable: true,
    );
    await client.updatePlugin('git-plugin');
    await client.removePlugin('git-plugin');
    final servers = await client.mcpServers();
    final catalog = await client.mcpCatalog();
    final mcpInstall = await client.installMcpCatalogEntry(
      'catalog-a',
      environment: {'MCP_TOKEN': 'ephemeral-test-value'},
    );
    await client.setMcpServerEnabled('server-a', false);
    await client.removeMcpServer('server-a');
    final probe = await client.testMcpServer('server-a');

    expect(plugins.single.name, 'git-plugin');
    expect(plugins.single.toString(), isNot(contains('/private/server')));
    expect(pluginInstall.accepted, isTrue);
    expect(servers.single.endpointLabel, 'https://mcp.example.test');
    expect(catalog.single.requiredEnv.single.name, 'MCP_TOKEN');
    expect(mcpInstall.accepted, isTrue);
    expect(probe.toolCount, 1);

    http.Request request(String method, String path) => requests.singleWhere(
      (request) => request.method == method && request.url.path == path,
    );

    expect(_body(request('POST', '/api/dashboard/agent-plugins/install')), {
      'identifier': 'nousresearch/git-plugin',
      'force': false,
      'enable': true,
    });
    expect(_body(request('POST', '/api/mcp/catalog/install')), {
      'name': 'catalog-a',
      'env': {'MCP_TOKEN': 'ephemeral-test-value'},
      'enable': true,
    });
    expect(_body(request('PUT', '/api/mcp/servers/server-a/enabled')), {
      'enabled': false,
    });
    expect(
      requests.every(
        (request) =>
            request.headers['x-hermes-session-token'] == 'dashboard-test-token',
      ),
      isTrue,
    );
  });

  test('read-only and unsafe plugin inputs fail before any request', () async {
    var calls = 0;
    final dashboardHttp = MockClient((request) async {
      calls++;
      return http.Response('{}', 200);
    });
    final client = TuiGatewayClient(
      _connection(readOnly: true),
      dashboard: _dashboard(dashboardHttp),
    );
    addTearDown(client.close);

    expect(
      () => client.installPlugin('nousresearch/plugin', enable: true),
      throwsA(
        isA<DesktopControlFailure>().having(
          (error) => error.kind,
          'kind',
          DesktopControlFailureKind.forbidden,
        ),
      ),
    );
    expect(calls, 0);

    final writable = TuiGatewayClient(
      _connection(),
      dashboard: _dashboard(dashboardHttp),
    );
    addTearDown(writable.close);
    expect(
      () => writable.installPlugin(
        'https://user:pass@example.test/plugin?token=secret',
        enable: true,
      ),
      throwsA(
        isA<DesktopControlFailure>().having(
          (error) => error.kind,
          'kind',
          DesktopControlFailureKind.rejected,
        ),
      ),
    );
    expect(calls, 0);
  });

  test(
    'unsupported Dashboard responses are typed and redact the body',
    () async {
      final client = TuiGatewayClient(
        _connection(),
        dashboard: _dashboard(
          MockClient(
            (_) async => http.Response(
              '{"detail":"token-secret at /private/server/path"}',
              404,
            ),
          ),
        ),
      );
      addTearDown(client.close);

      Object? failure;
      try {
        await client.managedPlugins();
      } catch (error) {
        failure = error;
      }

      expect(failure, isA<DesktopControlFailure>());
      expect(
        (failure! as DesktopControlFailure).kind,
        DesktopControlFailureKind.unsupported,
      );
      expect('$failure', isNot(contains('token-secret')));
      expect('$failure', isNot(contains('/private/server')));
    },
  );
}
