import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/admin_integrations.dart';

void main() {
  group('McpServerDraft', () {
    test('stdio serializa valores efímeros y redacta toString', () {
      final draft = McpServerDraft.stdio(
        name: 'filesystem',
        command: 'npx',
        args: const ['-y', '@modelcontextprotocol/server-filesystem'],
        environment: const {'MCP_SECRET': 'ephemeral-value'},
      );

      expect(draft.toRequestJson(), {
        'name': 'filesystem',
        'command': 'npx',
        'args': ['-y', '@modelcontextprotocol/server-filesystem'],
        'env': {'MCP_SECRET': 'ephemeral-value'},
        'auth': 'none',
      });
      expect('$draft', isNot(contains('ephemeral-value')));
    });

    test('HTTP soporta OAuth o bearer y rechaza combinaciones ambiguas', () {
      final oauth = McpServerDraft.http(
        name: 'reports',
        url: 'https://mcp.example/mcp',
        auth: McpAuthMode.oauth,
      );
      final bearer = McpServerDraft.http(
        name: 'private',
        url: 'https://mcp.example/private',
        auth: McpAuthMode.header,
        bearerToken: 'Bearer secret-once',
      );

      expect(oauth.toRequestJson()['auth'], 'oauth');
      expect(bearer.toRequestJson()['bearer_token'], 'Bearer secret-once');
      expect('$bearer', isNot(contains('secret-once')));
      expect(
        () => McpServerDraft.http(
          name: 'bad',
          url: 'https://mcp.example',
          auth: McpAuthMode.header,
        ),
        throwsFormatException,
      );
      expect(
        () => McpServerDraft.stdio(
          name: 'bad',
          command: 'npx',
          auth: McpAuthMode.oauth,
        ),
        throwsFormatException,
      );
      expect(
        () => McpServerDraft.http(
          name: 'leaky',
          url: 'https://mcp.example/mcp?token=secret',
        ),
        throwsFormatException,
      );
    });
  });

  test('OAuth parsea estados oficiales sin conservar códigos', () {
    final flow = McpOAuthFlow.fromJson({
      'flow_id': 'flow-1',
      'server_name': 'reports',
      'status': 'authorization_required',
      'authorization_url': 'https://idp.example/authorize?state=safe',
      'error': null,
      'code': 'must-not-be-read',
      'tools': ['search'],
    });

    expect(flow.status, McpOAuthStatus.authorizationRequired);
    expect(flow.authorizationUri?.host, 'idp.example');
    expect(flow.tools, ['search']);
    expect('$flow', isNot(contains('must-not-be-read')));
    expect(() => flow.tools.add('write'), throwsUnsupportedError);
  });

  test('webhooks separan resumen y secreto one-shot', () {
    final snapshot = WebhookSnapshot.fromJson({
      'enabled': true,
      'base_url': 'https://agent.example',
      'subscriptions': [
        {
          'name': 'deploy',
          'description': 'Deploy hook',
          'events': ['push'],
          'deliver': 'log',
          'skills': ['github'],
          'url': 'https://agent.example/webhooks/deploy',
          'secret_set': true,
          'enabled': true,
        },
      ],
    });
    final receipt = WebhookCreateReceipt.fromJson({
      ...snapshot.routes.single.toSummaryJson(),
      'secret': 'one-shot-secret',
    });

    expect(snapshot.enabled, isTrue);
    expect(snapshot.routes.single.events, ['push']);
    expect(receipt.secret, 'one-shot-secret');
    expect('$snapshot', isNot(contains('one-shot-secret')));
    expect('$receipt', isNot(contains('one-shot-secret')));
  });

  test('WebhookDraft normaliza nombre y valida delivery', () {
    final draft = WebhookDraft(
      name: 'Deploy Hook',
      description: 'CI',
      events: const ['push', ' push ', ''],
      skills: const ['github'],
    );

    expect(draft.name, 'deploy-hook');
    expect(draft.toRequestJson(), {
      'name': 'deploy-hook',
      'description': 'CI',
      'events': ['push'],
      'skills': ['github'],
      'deliver': 'log',
      'deliver_only': false,
    });
    expect(
      () => WebhookDraft(name: 'x', deliver: 'log', deliverOnly: true),
      throwsFormatException,
    );
  });
}
