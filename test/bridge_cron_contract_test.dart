import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final bridge = File('assets/bridge/hermes_bridge.py').readAsStringSync();
  final runtime = File(
    'lib/core/services/agent_runtime/agent_runtime.dart',
  ).readAsStringSync();

  test('Bridge cron profile-aware queda versionado y registrado', () {
    expect(bridge, contains('VERSION = "1.18.0"'));
    expect(runtime, contains("expectedBridgeVersion = '1.18.0'"));
    expect(bridge, contains('"cron_delete": can_write_target("cron")'));
    expect(
      bridge,
      contains(
        'app.router.add_delete("/bridge/cron/jobs/{job_id}", cron_remove)',
      ),
    );
  });

  test('cron_remove usa perfil y postestado del scope correcto', () {
    expect(bridge, contains('request.query.get("profile")'));
    expect(bridge, contains('_hermes(profile) + ["cron", "remove", job_id]'));
    expect(bridge, contains('_cron_job_present(job_id, profile)'));
    expect(bridge, contains('ok = still_present is False'));
    expect(bridge, isNot(contains('still_present is None and rc == 0')));
  });

  test('allowlist Python coincide exactamente con Dart', () {
    const pattern = r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$';
    expect(bridge, contains('CRON_JOB_ID_RE = re.compile(r"$pattern")'));
    final dart = File(
      'lib/core/services/bridge_client.dart',
    ).readAsStringSync();
    expect(dart, contains("cronJobIdPattern = r'$pattern'"));
  });
}
