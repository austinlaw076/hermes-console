import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/tui_gateway_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Tui reads A2A from messaging platforms without a mutation', () async {
    final requests = <http.Request>[];
    final client = TuiGatewayClient(
      SavedConnection(
        id: 'a2a-test',
        label: 'QA',
        host: '127.0.0.1',
        port: 8642,
        apiKey: 'gateway-test-key',
        dashboardUrl: 'http://127.0.0.1:9119',
      ),
      dashboard: DashboardClient(
        host: '127.0.0.1',
        port: 9119,
        manualToken: 'dashboard-test-token',
        httpClientOverride: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'platforms': [
                {
                  'id': 'a2a',
                  'enabled': true,
                  'configured': true,
                  'gateway_running': true,
                  'state': 'connected',
                },
              ],
            }),
            200,
          );
        }),
      ),
    );
    addTearDown(client.close);

    final capability = await client.a2aServerCapability();

    expect(capability?.state, 'connected');
    expect(requests, hasLength(1));
    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/api/messaging/platforms');
  });
}
