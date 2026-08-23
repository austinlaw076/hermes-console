import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/admin_integrations.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_control_gateway.dart';
import 'package:hermes_android/core/services/tui_gateway_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

SavedConnection _connection({bool readOnly = false}) => SavedConnection(
  id: 'admin-integrations',
  label: 'QA',
  host: '127.0.0.1',
  port: 8642,
  apiKey: 'gateway-test-key',
  dashboardUrl: 'http://127.0.0.1:9119',
  readOnly: readOnly,
);

DashboardClient _dashboard(http.Client client) => DashboardClient(
  host: '127.0.0.1',
  port: 9119,
  manualToken: 'dashboard-test-token',
  httpClientOverride: client,
);

Map<String, dynamic> _body(http.Request request) => request.body.isEmpty
    ? const {}
    : Map<String, dynamic>.from(jsonDecode(request.body) as Map);

void main() {
  test('MCP create y OAuth usan contratos 0.20', () async {
    final requests = <http.Request>[];
    final client = TuiGatewayClient(
      _connection(),
      dashboard: _dashboard(
        MockClient((request) async {
          requests.add(request);
          final payload = switch ((request.method, request.url.path)) {
            ('POST', '/api/mcp/servers') => {
              'name': 'reports',
              'transport': 'http',
              'url': 'https://mcp.example/mcp',
              'auth': 'oauth',
              'enabled': true,
            },
            ('POST', '/api/mcp/servers/reports/auth') => {
              'flow_id': 'flow-1',
              'server_name': 'reports',
              'status': 'authorization_required',
              'authorization_url': 'https://idp.example/authorize',
            },
            ('GET', '/api/mcp/oauth/flows/flow-1') => {
              'flow_id': 'flow-1',
              'server_name': 'reports',
              'status': 'approved',
              'tools': ['search'],
            },
            _ => <String, dynamic>{},
          };
          return http.Response(jsonEncode(payload), 200);
        }),
      ),
    );
    addTearDown(client.close);

    final server = await client.addMcpServer(
      McpServerDraft.http(
        name: 'reports',
        url: 'https://mcp.example/mcp',
        auth: McpAuthMode.oauth,
      ),
    );
    final started = await client.startMcpOAuth('reports');
    final completed = await client.mcpOAuthFlow('flow-1');

    expect(server.name, 'reports');
    expect(started.status, McpOAuthStatus.authorizationRequired);
    expect(completed.status, McpOAuthStatus.approved);
    expect(_body(requests.first), {
      'name': 'reports',
      'url': 'https://mcp.example/mcp',
      'auth': 'oauth',
    });
  });

  test('webhooks CRUD conserva secreto solo en receipt', () async {
    final requests = <http.Request>[];
    final client = TuiGatewayClient(
      _connection(),
      dashboard: _dashboard(
        MockClient((request) async {
          requests.add(request);
          final payload = switch ((request.method, request.url.path)) {
            ('GET', '/api/webhooks') => {
              'enabled': false,
              'base_url': 'http://127.0.0.1:8642',
              'subscriptions': <dynamic>[],
            },
            ('POST', '/api/webhooks/enable') => {
              'ok': true,
              'enabled': true,
              'restart_started': true,
              'needs_restart': false,
            },
            ('POST', '/api/webhooks') => {
              'name': 'deploy-hook',
              'events': ['push'],
              'deliver': 'log',
              'url': 'http://127.0.0.1:8642/webhooks/deploy-hook',
              'secret_set': true,
              'enabled': true,
              'secret': 'one-shot-secret',
            },
            ('PUT', '/api/webhooks/deploy-hook/enabled') => {
              'ok': true,
              'name': 'deploy-hook',
              'enabled': false,
            },
            ('DELETE', '/api/webhooks/deploy-hook') => {'ok': true},
            _ => <String, dynamic>{},
          };
          return http.Response(jsonEncode(payload), 200);
        }),
      ),
    );
    addTearDown(client.close);

    expect((await client.webhookSnapshot()).enabled, isFalse);
    final enable = await client.enableWebhooks();
    final receipt = await client.createWebhook(
      WebhookDraft(name: 'Deploy Hook', events: const ['push']),
    );
    await client.setWebhookEnabled('deploy-hook', false);
    await client.removeWebhook('deploy-hook');

    expect(enable.restartStarted, isTrue);
    expect(receipt.secret, 'one-shot-secret');
    expect('$receipt', isNot(contains('one-shot-secret')));
    expect(_body(requests[2]), {
      'name': 'deploy-hook',
      'events': ['push'],
      'skills': <dynamic>[],
      'deliver': 'log',
      'deliver_only': false,
    });
  });

  test('read-only bloquea mutaciones antes de la red', () async {
    var calls = 0;
    final client = TuiGatewayClient(
      _connection(readOnly: true),
      dashboard: _dashboard(
        MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      ),
    );
    addTearDown(client.close);

    expect(
      () => client.addMcpServer(
        McpServerDraft.stdio(name: 'local', command: 'npx'),
      ),
      throwsA(
        isA<DesktopControlFailure>().having(
          (failure) => failure.kind,
          'kind',
          DesktopControlFailureKind.forbidden,
        ),
      ),
    );
    expect(
      () => client.createWebhook(WebhookDraft(name: 'blocked')),
      throwsA(isA<DesktopControlFailure>()),
    );
    expect(calls, 0);
  });
}
