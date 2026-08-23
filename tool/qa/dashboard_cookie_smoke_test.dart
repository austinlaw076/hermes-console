import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';

/// Opt-in smoke probe for a disposable local Hermes Dashboard.
///
/// Credentials are read only from the process environment and never printed:
///
///   HERMES_QA_DASHBOARD_URL=http://127.0.0.1:9119
///   HERMES_QA_DASHBOARD_USER=...
///   HERMES_QA_DASHBOARD_PASSWORD=...
///   flutter test tool/qa/dashboard_cookie_smoke_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // This is an explicitly invoked live smoke, not part of the hermetic suite.
  // Restore the real client after flutter_test installs its 400-only override.
  HttpOverrides.global = null;

  test('password login reaches profiles and native Kanban', () async {
    final environment = Platform.environment;
    final rawUrl = environment['HERMES_QA_DASHBOARD_URL']?.trim() ?? '';
    final username = environment['HERMES_QA_DASHBOARD_USER']?.trim() ?? '';
    final password = environment['HERMES_QA_DASHBOARD_PASSWORD'] ?? '';
    final uri = Uri.tryParse(rawUrl);
    expect(uri, isNotNull, reason: 'Set HERMES_QA_DASHBOARD_URL');
    expect(uri!.hasAuthority, isTrue);
    expect(uri.scheme, anyOf('http', 'https'));
    expect(username, isNotEmpty, reason: 'Set HERMES_QA_DASHBOARD_USER');
    expect(password, isNotEmpty, reason: 'Set HERMES_QA_DASHBOARD_PASSWORD');

    final client = DashboardClient(
      host: uri.host,
      port: uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80),
      useHttps: uri.scheme == 'https',
      basicUser: username,
      basicPass: password,
    );
    try {
      final profiles = await client.getProfiles();
      final board = await client.apiGet('plugins/kanban/board');
      expect(profiles, isA<List>());
      expect(
        board.containsKey('columns') ||
            board.containsKey('tasks') ||
            board.containsKey('board'),
        isTrue,
        reason: 'Kanban response must retain an authoritative board shape',
      );
    } finally {
      client.close();
    }
  });
}
