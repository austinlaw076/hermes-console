import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Fixture local y sintético para el recorrido manual de Spec 047.
///
/// No contiene secretos ni registra prompts/respuestas. Expone únicamente los
/// contratos HTTP/JSON-RPC que necesita el emulador de revisión. Se ejecuta en
/// el host y Android lo alcanza mediante 10.0.2.2.
final class Spec047Fixture {
  Spec047Fixture({required this.gatewayPort, required this.dashboardPort});

  final int gatewayPort;
  final int dashboardPort;
  static const int bridgePort = 9131;

  final Map<String, List<Map<String, dynamic>>> _messages = {
    'qa-context-long': [
      {
        'id': 'qa-message-user-1',
        'role': 'user',
        'content': 'Comprueba el renderizado y el uso de contexto.',
      },
      {
        'id': 'qa-message-assistant-1',
        'role': 'assistant',
        'content':
            'Respuesta sintética lista. Abre Contexto para revisar el uso de '
            'esta sesión QA.',
      },
    ],
  };
  final Map<String, String> _runtimeToStored = {};
  final Map<String, int> _requestCounts = {};
  var _runtimeSerial = 0;
  var _contextUsed = 12345;
  var _compressionEnabled = true;
  var _compressionThreshold = 0.72;
  var _compressionTargetRatio = 0.45;
  var _compressionProtectLastN = 12;

  Future<void> run() async {
    final gateway = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      gatewayPort,
    );
    final dashboard = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      dashboardPort,
    );
    final bridge = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      bridgePort,
    );
    gateway.listen(_handleGateway);
    dashboard.listen(_handleDashboard);
    bridge.listen(_handleBridge);
    stdout.writeln(
      'Spec047 fixture ready: gateway=$gatewayPort dashboard=$dashboardPort '
      'bridge=$bridgePort',
    );

    final signal = await ProcessSignal.sigint.watch().first;
    stdout.writeln('Spec047 fixture stopping on $signal');
    stdout.writeln('Structural request counts: ${jsonEncode(_requestCounts)}');
    await Future.wait([
      gateway.close(force: true),
      dashboard.close(force: true),
      bridge.close(force: true),
    ]);
  }

  void _count(String key) {
    _requestCounts.update(key, (value) => value + 1, ifAbsent: () => 1);
  }

  Future<void> _handleGateway(HttpRequest request) async {
    final path = request.uri.path;
    _count('gateway:${request.method}:$path');

    if (request.method == 'GET' && path == '/health') {
      return _json(request.response, {'status': 'ok', 'version': '0.19.0-qa'});
    }
    if (request.method == 'GET' && path == '/api/sessions') {
      final now = DateTime.now().millisecondsSinceEpoch / 1000;
      return _json(request.response, {
        'data': [
          {
            'id': 'qa-context-long',
            'title': 'QA Context Long',
            'model': 'qa-model',
            'source': 'mobile',
            'message_count': _messages['qa-context-long']!.length,
            'is_active': true,
            'preview': 'Synthetic context and Markdown verification',
            'started_at': now - 1800,
            'last_active': now,
            '_lineage_root_id': 'qa-context-long',
            'input_tokens': 12000,
            'output_tokens': 345,
            'api_call_count': 2,
          },
        ],
      });
    }
    final messageMatch = RegExp(
      r'^/api/sessions/([^/]+)/messages$',
    ).firstMatch(path);
    if (request.method == 'GET' && messageMatch != null) {
      final id = Uri.decodeComponent(messageMatch.group(1)!);
      return _json(request.response, {'data': _messages[id] ?? const []});
    }
    if (request.method == 'DELETE' && path.startsWith('/api/sessions/')) {
      return _json(request.response, {'deleted': true});
    }
    if (request.method == 'GET' && path == '/v1/models') {
      return _json(request.response, {
        'object': 'list',
        'data': [
          {'id': 'hermes-agent', 'object': 'model', 'owned_by': 'qa-fixture'},
        ],
      });
    }
    if (request.method == 'GET' && path == '/v1/capabilities') {
      return _json(request.response, {
        'object': 'hermes.api_server.capabilities',
        'version': '0.19.0-qa',
        'features': {
          'chat': true,
          'streaming': true,
          'sessions': true,
          'skills_api': true,
          'toolsets': true,
        },
        'endpoints': {
          'chat': '/v1/chat/completions',
          'sessions': '/api/sessions',
        },
      });
    }
    if (request.method == 'GET' && path == '/v1/skills') {
      return _json(request.response, {
        'skills': [
          {'name': 'qa-synthetic-skill', 'enabled': true},
        ],
      });
    }
    if (request.method == 'GET' && path == '/v1/toolsets') {
      return _json(request.response, {
        'toolsets': [
          {
            'name': 'qa-tools',
            'enabled': true,
            'tools': ['inspect'],
          },
        ],
      });
    }
    if (request.method == 'POST' && path == '/v1/chat/completions') {
      return _json(request.response, {
        'error': {'message': 'Synthetic validation response'},
      }, statusCode: HttpStatus.badRequest);
    }
    return _json(request.response, {'error': 'not_found'}, statusCode: 404);
  }

  Future<void> _handleDashboard(HttpRequest request) async {
    final path = request.uri.path;
    _count('dashboard:${request.method}:$path');

    if (path == '/api/ws' && WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      unawaited(_serveSocket(socket));
      return;
    }
    if (request.method == 'GET' && path == '/') {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(
          '<!doctype html><script>'
          'window.__HERMES_SESSION_TOKEN__="qa-dashboard-token";'
          '</script>',
        );
      return request.response.close();
    }
    if (request.method == 'POST' && path == '/api/auth/ws-ticket') {
      return _json(request.response, {'ticket': 'qa-ws-ticket'});
    }
    if (request.method == 'GET' && path == '/api/status') {
      return _json(request.response, {
        'status': 'ok',
        'version': '0.19.0-qa',
        'release_date': '2026-07-22',
        'gateway_running': true,
        'gateway_state': 'running',
        'active_sessions': 1,
        'config_version': 4,
        'latest_config_version': 4,
        'auth_required': false,
      });
    }
    if (request.method == 'GET' && path == '/api/config') {
      return _json(request.response, _serverConfig());
    }
    if (request.method == 'GET' && path == '/api/config/schema') {
      return _json(request.response, _configSchema());
    }
    if (request.method == 'PUT' && path == '/api/config') {
      final body = await utf8.decoder.bind(request).join();
      final decoded = body.isEmpty ? null : jsonDecode(body);
      final config = decoded is Map ? decoded['config'] : null;
      final compression = config is Map ? config['compression'] : null;
      if (compression is Map) {
        _compressionEnabled = compression['enabled'] is bool
            ? compression['enabled'] as bool
            : _compressionEnabled;
        _compressionThreshold = _numberOr(
          compression['threshold'],
          _compressionThreshold,
        );
        _compressionTargetRatio = _numberOr(
          compression['target_ratio'],
          _compressionTargetRatio,
        );
        _compressionProtectLastN = compression['protect_last_n'] is num
            ? (compression['protect_last_n'] as num).round()
            : _compressionProtectLastN;
      }
      return _json(request.response, {'ok': true, 'config': _serverConfig()});
    }
    if (request.method == 'GET' && path == '/api/model/info') {
      return _json(request.response, {
        'model': 'qa-model',
        'provider': 'qa-provider',
      });
    }
    if (request.method == 'GET' && path == '/api/model/options') {
      return _json(request.response, _modelCatalog());
    }
    if (request.method == 'GET' && path == '/api/profiles') {
      return _json(request.response, {
        'profiles': [
          {'name': 'default', 'is_default': true},
        ],
      });
    }
    if (request.method == 'GET' && path == '/api/skills') {
      return _json(request.response, {
        'skills': [
          {'name': 'qa-synthetic-skill', 'enabled': true},
        ],
      });
    }
    if (request.method == 'GET' && path == '/api/logs') {
      return _json(request.response, {'lines': <String>[]});
    }
    if (request.method == 'GET' && path.startsWith('/api/')) {
      return _json(request.response, <String, dynamic>{});
    }
    if (request.method == 'POST' && path.startsWith('/api/')) {
      return _json(request.response, {'ok': true});
    }
    return _json(request.response, {'error': 'not_found'}, statusCode: 404);
  }

  Future<void> _handleBridge(HttpRequest request) async {
    final path = request.uri.path;
    _count('bridge:${request.method}:$path');
    if (request.method == 'GET' && path == '/bridge/health') {
      return _json(request.response, {
        'status': 'ok',
        'version': '1.18.0',
        'service': 'hermes-mobile-bridge',
      });
    }
    if (request.method == 'GET' && path == '/bridge/capabilities') {
      return _json(request.response, {
        'version': '1.18.0',
        'capabilities': <String, bool>{},
      });
    }
    if (request.method == 'POST' && path == '/bridge/provision') {
      return _json(request.response, {'token': 'qa-bridge-token'});
    }
    return _json(request.response, {'error': 'not_found'}, statusCode: 404);
  }

  Map<String, dynamic> _serverConfig() => {
    'compression': {
      'enabled': _compressionEnabled,
      'threshold': _compressionThreshold,
      'target_ratio': _compressionTargetRatio,
      'protect_last_n': _compressionProtectLastN,
    },
    'qa_fixture': {'preserve': true},
  };

  Map<String, dynamic> _configSchema() => {
    'properties': {
      'compression': {
        'type': 'object',
        'properties': {
          'enabled': {'type': 'boolean'},
          'threshold': {'type': 'number', 'minimum': 0.1, 'maximum': 0.95},
          'target_ratio': {'type': 'number', 'minimum': 0.05, 'maximum': 0.8},
          'protect_last_n': {'type': 'integer', 'minimum': 0, 'maximum': 200},
        },
      },
    },
  };

  Map<String, dynamic> _modelCatalog() => {
    'model': 'qa-model',
    'provider': 'qa-provider',
    'providers': [
      {
        'slug': 'qa-provider',
        'name': 'QA Provider',
        'authenticated': true,
        'models': ['qa-model'],
        'capabilities': {
          'qa-model': {'fast': true, 'reasoning': true},
        },
      },
    ],
  };

  Future<void> _serveSocket(WebSocket socket) async {
    try {
      await for (final raw in socket) {
        if (raw is! String) continue;
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final frame = Map<String, dynamic>.from(decoded);
        final method = frame['method']?.toString() ?? '';
        final id = frame['id'];
        final params = frame['params'] is Map
            ? Map<String, dynamic>.from(frame['params'] as Map)
            : <String, dynamic>{};
        _count('rpc:$method');
        final response = _rpcResult(method, params);
        if (response case _RpcError(:final code, :final message)) {
          socket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'error': {'code': code, 'message': message},
            }),
          );
          continue;
        }
        socket.add(
          jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': response}),
        );
        if (method == 'prompt.submit') {
          unawaited(_emitSyntheticTurn(socket, params));
        }
      }
    } on WebSocketException {
      // El emulador cerró el recorrido. El siguiente socket puede continuar.
    } on FormatException {
      await socket.close(WebSocketStatus.invalidFramePayloadData);
    }
  }

  Object _rpcResult(String method, Map<String, dynamic> params) {
    switch (method) {
      case 'session.resume':
        final stored = _nonEmpty(params['session_id']) ?? 'qa-context-long';
        return _sessionSnapshot(stored);
      case 'session.create':
        final stored = 'qa-created-${DateTime.now().microsecondsSinceEpoch}';
        _messages.putIfAbsent(stored, () => <Map<String, dynamic>>[]);
        final snapshot = _sessionSnapshot(stored);
        snapshot['stored_session_id'] = stored;
        return snapshot;
      case 'session.activate':
        final runtime = _nonEmpty(params['session_id']);
        final stored = runtime == null ? null : _runtimeToStored[runtime];
        if (runtime == null || stored == null) {
          return const _RpcError(4007, 'synthetic session not found');
        }
        return _sessionSnapshot(stored, runtime: runtime);
      case 'session.active_list':
        return {
          'sessions': _runtimeToStored.entries
              .map(
                (entry) => {
                  'session_id': entry.key,
                  'stored_session_id': entry.value,
                  'status': 'idle',
                },
              )
              .toList(),
        };
      case 'prompt.submit':
        return {'status': 'accepted'};
      case 'session.interrupt':
        return {'status': 'interrupted'};
      case 'session.steer':
        return {'status': 'queued'};
      case 'session.context_breakdown':
        return {
          'categories': [
            {'id': 'system', 'label': 'System', 'tokens': 1800},
            {
              'id': 'conversation',
              'label': 'Conversation',
              'tokens': _contextUsed - 1800,
            },
          ],
          'context_used': _contextUsed,
          'context_max': 32768,
          'context_percent': _contextUsed / 32768 * 100,
          'estimated_total': _contextUsed,
          'model': 'qa-model',
        };
      case 'commands.catalog':
        return {
          'revision': 'qa-047',
          'categories': [
            {
              'name': 'Session',
              'pairs': [
                ['/compress', 'Compress context'],
                ['/usage', 'Show context usage'],
              ],
            },
          ],
          'pairs': [
            ['/compress', 'Compress context'],
            ['/usage', 'Show context usage'],
          ],
          'canon': {'/summarize': '/compress'},
        };
      case 'complete.slash':
        return {
          'replace_from': 1,
          'items': [
            {
              'text': 'compress',
              'display': '/compress',
              'meta': 'Compress context',
            },
          ],
        };
      case 'slash.exec':
      case 'command.dispatch':
        _contextUsed = 6200;
        return {
          'type': 'exec',
          'status': 'accepted',
          'name': 'compress',
          'output': 'Synthetic context compression accepted',
        };
      case 'model.options':
        return _modelCatalog();
      case 'config.set':
        final key = params['key']?.toString() ?? '';
        return {
          'key': key,
          'value': params['value'],
          'scope': 'session',
          'confirm_required': false,
        };
      case 'rollback.list':
        return {
          'enabled': true,
          'checkpoints': [
            {
              'hash': 'qa-checkpoint',
              'timestamp': '2026-07-22T12:00:00Z',
              'message': 'Synthetic checkpoint',
            },
          ],
        };
      case 'rollback.diff':
        return {'stat': '1 file', 'diff': '+synthetic safe change'};
      case 'rollback.restore':
        return {'success': true, 'history_removed': 1};
      case 'plugins.manage':
        if (params['action'] == 'list') {
          return {
            'plugins': [
              {'name': 'qa-plugin', 'version': '1.0.0', 'status': 'enabled'},
            ],
          };
        }
        return {'ok': true, 'unchanged': false, 'name': params['name']};
      case 'tools.list':
        return {
          'toolsets': [
            {
              'name': 'qa-tools',
              'description': 'Synthetic tools',
              'tool_count': 1,
              'enabled': true,
              'tools': ['inspect'],
            },
          ],
        };
      case 'tools.configure':
        return {
          'changed': [params['names']],
          'unknown': <Object>[],
        };
      case 'reload.mcp':
        return {'status': 'reloaded'};
      case 'spawn_tree.list':
        return {
          'entries': [
            {
              'path': '/synthetic/spawn-tree.json',
              'session_id': 'runtime-qa',
              'label': 'QA agents',
              'count': 1,
            },
          ],
        };
      case 'process.list':
        return {
          'processes': [
            {
              'session_id': 'qa-process',
              'command': 'synthetic verification',
              'status': 'running',
            },
          ],
        };
      case 'spawn_tree.load':
        return {
          'session_id': 'runtime-qa',
          'label': 'QA agents',
          'subagents': [
            {'id': 'qa-agent', 'status': 'completed'},
          ],
        };
      case 'prompt.background':
        return {'task_id': 'qa-background-task'};
      case 'process.kill':
        return {'killed': true};
      case 'projects.tree':
        return {
          'active_id': 'qa-project',
          'projects': [
            {
              'id': 'qa-project',
              'label': 'Hermes Console QA',
              'sessionCount': 1,
              'repos': <Object>[],
            },
          ],
        };
      case 'projects.project_sessions':
        return {
          'project': {
            'id': 'qa-project',
            'label': 'Hermes Console QA',
            'sessionCount': 1,
            'repos': <Object>[],
          },
        };
      case 'session.cwd.set':
        return {'cwd': params['cwd'], 'branch': 'qa'};
      default:
        return const _RpcError(-32601, 'synthetic method unavailable');
    }
  }

  Map<String, dynamic> _sessionSnapshot(String stored, {String? runtime}) {
    final runtimeId = runtime ?? 'runtime-qa-${++_runtimeSerial}';
    _runtimeToStored[runtimeId] = stored;
    final messages = _messages.putIfAbsent(
      stored,
      () => <Map<String, dynamic>>[],
    );
    return {
      'session_id': runtimeId,
      'resumed': stored,
      'session_key': stored,
      'messages': messages,
      'message_count': messages.length,
      'running': false,
      'status': 'idle',
      'info': {
        'model': 'qa-model',
        'provider': 'qa-provider',
        'reasoning_effort': 'medium',
        'fast': false,
        'running': false,
        'title': stored == 'qa-context-long' ? 'QA Context Long' : 'QA Chat',
        'stored_session_id': stored,
        'desktop_contract': 19,
        'version': '0.19.0-qa',
        'profile_name': 'default',
        'cwd': '/synthetic/project',
        'branch': 'qa',
        'usage': {
          'calls': 2,
          'input': _contextUsed - 345,
          'output': 345,
          'total': _contextUsed,
          'context_used': _contextUsed,
          'context_max': 32768,
          'context_percent': _contextUsed / 32768 * 100,
          'cost_usd': 0.99,
        },
      },
    };
  }

  Future<void> _emitSyntheticTurn(
    WebSocket socket,
    Map<String, dynamic> params,
  ) async {
    final runtime = _nonEmpty(params['session_id']);
    if (runtime == null) return;
    final stored = _runtimeToStored[runtime] ?? 'qa-context-long';
    final prompt = params['text'] is String ? params['text'] as String : '';
    final autoCompact = prompt.contains('QA_AUTO_COMPACT');
    final decimalProbe = prompt.contains('QA_TTS_DECIMAL');
    final markdownProbe = prompt.contains('QA_MARKDOWN');
    if (autoCompact) {
      _contextUsed = 7100;
      _event(socket, runtime, 'status.update', {
        'kind': 'compacting',
        '_lineage_root_id': stored,
      });
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    final (full, chunks) = decimalProbe
        ? (
            'Lectura decimal de prueba: 0,99 €.',
            const ['Lectura decimal de prueba: ', '0,', '99 €.'],
          )
        : markdownProbe
        ? (
            'Modelo recomendado (simple y limpio): **Hermes 0.19**.\n\n'
                'El patrón `**literal**` se conserva dentro del código.',
            const [
              'Modelo recomendado (simple y limpio): *',
              '*Hermes 0.19*',
              '*.',
              '\n\nEl patrón `**literal**` ',
              'se conserva dentro del código.',
            ],
          )
        : (
            'Respuesta sintética completada correctamente.',
            const ['Respuesta sintética ', 'completada correctamente.'],
          );
    _messages.putIfAbsent(stored, () => <Map<String, dynamic>>[])
      ..add({'role': 'user', 'content': prompt})
      ..add({'role': 'assistant', 'content': full});

    _event(socket, runtime, 'message.start', const {});
    for (final chunk in chunks) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      _event(socket, runtime, 'message.delta', {'text': chunk});
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _event(socket, runtime, 'message.complete', {'text': full});
    _event(socket, runtime, 'session.info', {
      'info': _sessionSnapshot(stored, runtime: runtime)['info'],
    });
  }

  void _event(
    WebSocket socket,
    String runtime,
    String type,
    Map<String, dynamic> payload,
  ) {
    if (socket.readyState != WebSocket.open) return;
    socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': 'event',
        'params': {'type': type, 'session_id': runtime, 'payload': payload},
      }),
    );
  }

  Future<void> _json(
    HttpResponse response,
    Object body, {
    int statusCode = HttpStatus.ok,
  }) async {
    response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await response.close();
  }

  double _numberOr(Object? value, double fallback) =>
      value is num ? value.toDouble() : fallback;

  String? _nonEmpty(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

final class _RpcError {
  const _RpcError(this.code, this.message);

  final int code;
  final String message;
}

Future<void> main(List<String> args) async {
  var gatewayPort = 18642;
  var dashboardPort = 19119;
  for (final arg in args) {
    if (arg.startsWith('--gateway-port=')) {
      gatewayPort = int.parse(arg.substring('--gateway-port='.length));
    } else if (arg.startsWith('--dashboard-port=')) {
      dashboardPort = int.parse(arg.substring('--dashboard-port='.length));
    } else {
      stderr.writeln('Unknown argument: $arg');
      exitCode = 64;
      return;
    }
  }
  if (gatewayPort == dashboardPort ||
      gatewayPort < 1024 ||
      dashboardPort < 1024) {
    stderr.writeln('Fixture ports must be distinct and >= 1024.');
    exitCode = 64;
    return;
  }
  await Spec047Fixture(
    gatewayPort: gatewayPort,
    dashboardPort: dashboardPort,
  ).run();
}
