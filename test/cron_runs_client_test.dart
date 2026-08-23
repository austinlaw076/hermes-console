import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/cron_runs_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('bloquea dashboard HTTP público antes de crear el cliente', () {
    var hits = 0;
    final client = MockClient((_) async {
      hits++;
      return http.Response('{}', 200);
    });

    expect(
      () => CronRunsClient(
        host: 'dashboard.example.com',
        httpClientOverride: client,
      ),
      throwsArgumentError,
    );
    expect(hits, 0);
  });

  test('mantiene HTTP privado y HTTPS remotos compatibles', () {
    final privateClient = CronRunsClient(host: '192.168.1.20');
    final secureClient = CronRunsClient(
      host: 'dashboard.example.com',
      port: 443,
      useHttps: true,
    );
    addTearDown(privateClient.close);
    addTearDown(secureClient.close);

    expect(privateClient.baseUrl, 'http://192.168.1.20:9119');
    expect(secureClient.baseUrl, 'https://dashboard.example.com:443');
  });
}
