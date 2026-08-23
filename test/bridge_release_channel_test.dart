import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/bridge_release_channel.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _packaged = 'VERSION = "1.16.0"\nprint("packaged")\n';
const _remote = 'VERSION = "1.17.0"\nprint("remote")\n';

void main() {
  test('usa una release remota superior íntegra y de origen fijo', () async {
    final bytes = utf8.encode(_remote);
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url == BridgeReleaseChannel.manifestUri) {
        return http.Response(
          jsonEncode(_manifest(bytes: bytes, version: '1.17.0')),
          200,
        );
      }
      if (request.url == BridgeReleaseChannel.payloadUri) {
        return http.Response.bytes(bytes, 200);
      }
      return http.Response('', 404);
    });

    final release = await _channel(client).resolve();

    expect(release.remote, isTrue);
    expect(release.version, '1.17.0');
    expect(release.source, _remote);
    expect(release.sha256, sha256.convert(bytes).toString());
    expect(requests, [
      BridgeReleaseChannel.manifestUri,
      BridgeReleaseChannel.payloadUri,
    ]);
  });

  test('la comprobación de target no descarga el payload', () async {
    final bytes = utf8.encode(_remote);
    var payloadRequests = 0;
    final client = MockClient((request) async {
      if (request.url == BridgeReleaseChannel.manifestUri) {
        return http.Response(
          jsonEncode(_manifest(bytes: bytes, version: '1.17.0')),
          200,
        );
      }
      payloadRequests++;
      return http.Response.bytes(bytes, 200);
    });

    final target = await _channel(client).resolveTarget();

    expect(target.remote, isTrue);
    expect(target.version, '1.17.0');
    expect(payloadRequests, 0);
  });

  test('hash incorrecto descarta el payload y usa el asset', () async {
    final bytes = utf8.encode(_remote);
    final client = MockClient((request) async {
      if (request.url == BridgeReleaseChannel.manifestUri) {
        final manifest = _manifest(bytes: bytes, version: '1.17.0');
        manifest['sha256'] = List.filled(64, '0').join();
        return http.Response(jsonEncode(manifest), 200);
      }
      return http.Response.bytes(bytes, 200);
    });

    expect(await _channel(client).resolve(), _isPackaged);
  });

  test('VERSION distinta a la del manifiesto descarta el remoto', () async {
    final bytes = utf8.encode(
      'VERSION = "1.18.0"\nprint("payload equivocado")\n',
    );
    final client = _releaseClient(bytes: bytes, version: '1.17.0');

    expect(await _channel(client).resolve(), _isPackaged);
  });

  test('release remota igual o inferior no descarga ni degrada', () async {
    var payloadRequests = 0;
    final bytes = utf8.encode('VERSION = "1.15.0"\n');
    final client = MockClient((request) async {
      if (request.url == BridgeReleaseChannel.manifestUri) {
        return http.Response(
          jsonEncode(_manifest(bytes: bytes, version: '1.15.0')),
          200,
        );
      }
      payloadRequests++;
      return http.Response.bytes(bytes, 200);
    });

    expect(await _channel(client).resolve(), _isPackaged);
    expect(payloadRequests, 0);
  });

  test(
    'release remota idéntica conserva origen remoto para instalación corta',
    () async {
      final bytes = utf8.encode(_packaged);
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        if (request.url == BridgeReleaseChannel.manifestUri) {
          return http.Response(
            jsonEncode(_manifest(bytes: bytes, version: '1.16.0')),
            200,
          );
        }
        return http.Response.bytes(bytes, 200);
      });

      final release = await _channel(client).resolve();

      expect(release.remote, isTrue);
      expect(release.version, '1.16.0');
      expect(release.source, _packaged);
      expect(requests, [
        BridgeReleaseChannel.manifestUri,
        BridgeReleaseChannel.payloadUri,
      ]);
    },
  );

  test(
    'release que exige una app posterior usa fallback sin payload',
    () async {
      var payloadRequests = 0;
      final bytes = utf8.encode(_remote);
      final manifest = _manifest(bytes: bytes, version: '1.17.0');
      manifest['min_app_build'] = 904;
      final client = MockClient((request) async {
        if (request.url == BridgeReleaseChannel.manifestUri) {
          return http.Response(jsonEncode(manifest), 200);
        }
        payloadRequests++;
        return http.Response.bytes(bytes, 200);
      });

      expect(await _channel(client).resolve(), _isPackaged);
      expect(payloadRequests, 0);
    },
  );

  test(
    'manifiesto inválido, con extras o demasiado grande usa fallback',
    () async {
      final invalidManifests = <Object>[
        {
          'schema': 2,
          'version': '1.17.0',
          'sha256': List.filled(64, '0').join(),
          'size': 10,
        },
        {
          'schema': 1,
          'version': 'v1.17',
          'sha256': List.filled(64, '0').join(),
          'size': 10,
        },
        {
          ..._manifest(bytes: utf8.encode(_remote), version: '1.17.0'),
          'url': 'https://evil.example/bridge.py',
        },
        'x' * (BridgeReleaseChannel.maxManifestBytes + 1),
      ];

      for (final body in invalidManifests) {
        final client = MockClient(
          (_) async =>
              http.Response(body is String ? body : jsonEncode(body), 200),
        );
        expect(
          await _channel(client).resolve(),
          _isPackaged,
          reason: 'Debe rechazar $body',
        );
      }
    },
  );

  test('size imposible evita descargar un payload excesivo', () async {
    var payloadRequests = 0;
    final manifest = _manifest(bytes: utf8.encode(_remote), version: '1.17.0');
    manifest['size'] = BridgeReleaseChannel.maxPayloadBytes + 1;
    final client = MockClient((request) async {
      if (request.url == BridgeReleaseChannel.manifestUri) {
        return http.Response(jsonEncode(manifest), 200);
      }
      payloadRequests++;
      return http.Response.bytes(utf8.encode(_remote), 200);
    });

    expect(await _channel(client).resolve(), _isPackaged);
    expect(payloadRequests, 0);
  });

  test('404 y timeout de red usan fallback sin propagar', () async {
    expect(
      await _channel(MockClient((_) async => http.Response('', 404))).resolve(),
      _isPackaged,
    );

    final never = Completer<http.Response>();
    final timedOut = _channel(
      MockClient((_) => never.future),
      timeout: const Duration(milliseconds: 5),
    );
    expect(await timedOut.resolve(), _isPackaged);
  });

  test('rechaza redirects aunque apunten al payload esperado', () async {
    final client = MockClient(
      (_) async => http.Response(
        '',
        302,
        headers: {'location': BridgeReleaseChannel.payloadUri.toString()},
      ),
    );

    expect(await _channel(client).resolve(), _isPackaged);
  });

  test(
    'el timeout es total aunque el servidor entregue bytes lentamente',
    () async {
      final channel = _channel(
        _SlowlorisClient(),
        timeout: const Duration(milliseconds: 8),
      );

      expect(
        channel.resolve().timeout(const Duration(milliseconds: 80)),
        completion(_isPackaged),
      );
    },
  );

  test('tamaño real distinto al manifiesto usa fallback', () async {
    final bytes = utf8.encode(_remote);
    final manifest = _manifest(bytes: bytes, version: '1.17.0');
    manifest['size'] = bytes.length + 1;
    final client = MockClient((request) async {
      if (request.url == BridgeReleaseChannel.manifestUri) {
        return http.Response(jsonEncode(manifest), 200);
      }
      return http.Response.bytes(bytes, 200);
    });

    expect(await _channel(client).resolve(), _isPackaged);
  });
}

BridgeReleaseChannel _channel(
  http.Client client, {
  Duration timeout = const Duration(seconds: 1),
}) => BridgeReleaseChannel(
  httpClient: client,
  loadPackagedSource: () async => _packaged,
  loadAppBuild: () async => 903,
  requestTimeout: timeout,
);

MockClient _releaseClient({required List<int> bytes, required String version}) {
  return MockClient((request) async {
    if (request.url == BridgeReleaseChannel.manifestUri) {
      return http.Response(
        jsonEncode(_manifest(bytes: bytes, version: version)),
        200,
      );
    }
    return http.Response.bytes(bytes, 200);
  });
}

Map<String, Object> _manifest({
  required List<int> bytes,
  required String version,
}) => {
  'schema': 1,
  'version': version,
  'min_app_build': 903,
  'sha256': sha256.convert(bytes).toString(),
  'size': bytes.length,
};

final _isPackaged = isA<BridgeRelease>()
    .having((release) => release.remote, 'remote', isFalse)
    .having((release) => release.version, 'version', '1.16.0')
    .having((release) => release.source, 'source', _packaged);

class _SlowlorisClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.periodic(
        const Duration(milliseconds: 3),
        (_) => const [0x20],
      ),
      200,
      request: request,
    );
  }
}
