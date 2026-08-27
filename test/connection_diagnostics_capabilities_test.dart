import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hermes_android/core/services/connection_diagnostics.dart';
import 'package:hermes_android/core/services/connection_manager.dart';

SavedConnection _connection() => SavedConnection(
  id: 'diagnostics-test',
  label: 'Diagnostics test',
  host: '127.0.0.1',
  port: 8642,
  apiKey: 'test-key',
  onDeviceLoopback: true,
);

String _capabilities({
  bool? skillsToggle,
  bool? pluginsApi,
  String skillsTogglePath = '/v1/skills/toggle',
}) {
  final features = <String, Object?>{
    'skills_api': true,
    'chat_completions': true,
    if (skillsToggle != null) 'skills_toggle': skillsToggle,
    if (pluginsApi != null) 'plugins_api': pluginsApi,
  };
  final endpoints = <String, Object?>{
    if (skillsToggle != null)
      'skills_toggle': {'method': 'PUT', 'path': skillsTogglePath},
    if (pluginsApi != null)
      'plugins': {'method': 'GET', 'path': '/v1/plugins'},
  };
  return jsonEncode({
    'object': 'hermes.api_server.capabilities',
    'features': features,
    'endpoints': endpoints,
  });
}

Future<({CapabilityMatrix matrix, List<http.Request> requests})> _run(
  String capabilities, {
  int pluginsStatus = 200,
}) async {
  final requests = <http.Request>[];
  final diagnostics = ConnectionDiagnostics(
    httpClient: MockClient((request) async {
      requests.add(request);
      switch (request.url.path) {
        case '/health':
          return http.Response(jsonEncode({'version': '0.20.4'}), 200);
        case '/api/sessions':
        case '/v1/models':
        case '/v1/skills':
        case '/v1/toolsets':
          return http.Response('{}', 200);
        case '/v1/capabilities':
          return http.Response(capabilities, 200);
        case '/v1/plugins':
          return http.Response('{}', pluginsStatus);
        case '/v1/skills/toggle':
          return http.Response('{}', 422);
        case '/v1/chat/completions':
          return http.Response('{}', 400);
        default:
          return http.Response('{}', 404);
      }
    }),
  );

  try {
    final (gateway, version, serverCaps) = await diagnostics.probeGateway(
      _connection(),
    );
    return (
      matrix: diagnostics.buildMatrix(
        gateway,
        const [],
        version,
        serverCaps: serverCaps,
      ),
      requests: requests,
    );
  } finally {
    diagnostics.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'diagnostics does not probe a hard-coded skills toggle write endpoint',
    () async {
      final result = await _run(
        _capabilities(
          skillsToggle: true,
          pluginsApi: true,
          skillsTogglePath: '/v9/server-declared/skills/toggle',
        ),
      );

      expect(
        result.requests.where((request) => request.method == 'PUT'),
        isEmpty,
      );
      expect(
        result.requests.where(
          (request) => request.url.path == '/v1/skills/toggle',
        ),
        isEmpty,
      );
      expect(
        result.requests.where(
          (request) =>
              request.url.path == '/v9/server-declared/skills/toggle',
        ),
        isEmpty,
      );
      expect(result.matrix.skillsToggle, CapState.yes);
      expect(result.matrix.isServerSourced('skillsToggle'), isTrue);
    },
  );

  test('declared true capabilities are authoritative', () async {
    final result = await _run(
      _capabilities(skillsToggle: true, pluginsApi: true),
    );

    expect(result.matrix.skillsToggle, CapState.yes);
    expect(result.matrix.pluginsSupported, CapState.yes);
    expect(result.matrix.isServerSourced('skillsToggle'), isTrue);
    expect(result.matrix.isServerSourced('pluginsSupported'), isTrue);
  });

  test('declared false capabilities are authoritative', () async {
    final result = await _run(
      _capabilities(skillsToggle: false, pluginsApi: false),
    );

    expect(result.matrix.skillsToggle, CapState.no);
    expect(result.matrix.pluginsSupported, CapState.no);
    expect(result.matrix.isServerSourced('skillsToggle'), isTrue);
    expect(result.matrix.isServerSourced('pluginsSupported'), isTrue);
  });

  test('legacy server without toggle feature does not become a false YES', () async {
    final result = await _run(
      _capabilities(),
      pluginsStatus: 404,
    );

    expect(result.matrix.skillsToggle, CapState.unknown);
    expect(result.matrix.isServerSourced('skillsToggle'), isFalse);
    expect(result.matrix.pluginsSupported, CapState.no);
    expect(result.matrix.skillsInstall, CapState.unknown);
  });
}
