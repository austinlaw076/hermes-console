enum McpTransport { stdio, http }

enum McpAuthMode { none, oauth, header }

/// Configuración efímera para `POST /api/mcp/servers`.
///
/// Los valores de `environment` y `bearerToken` existen solo mientras se
/// envía el formulario; esta clase no ofrece serialización de persistencia y
/// su representación de depuración nunca imprime secretos.
final class McpServerDraft {
  final String name;
  final McpTransport transport;
  final String command;
  final List<String> args;
  final Map<String, String> environment;
  final Uri? url;
  final McpAuthMode auth;
  final String? bearerToken;

  factory McpServerDraft.stdio({
    required String name,
    required String command,
    List<String> args = const [],
    Map<String, String> environment = const {},
    McpAuthMode auth = McpAuthMode.none,
  }) {
    if (auth != McpAuthMode.none) {
      throw const FormatException('stdio MCP does not support HTTP auth');
    }
    final safeName = _requiredText(name, max: 160);
    final safeCommand = _requiredText(command, max: 800);
    return McpServerDraft._(
      name: safeName,
      transport: McpTransport.stdio,
      command: safeCommand,
      args: _validateArgs(args),
      environment: _validateEnvironment(environment),
      auth: auth,
    );
  }

  factory McpServerDraft.http({
    required String name,
    required String url,
    McpAuthMode auth = McpAuthMode.none,
    String? bearerToken,
  }) {
    final safeName = _requiredText(name, max: 160);
    final parsed = Uri.tryParse(url.trim());
    if (parsed == null ||
        !parsed.hasScheme ||
        !{'http', 'https'}.contains(parsed.scheme.toLowerCase()) ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment) {
      throw const FormatException('Invalid MCP URL');
    }
    final token = bearerToken?.trim();
    if (auth == McpAuthMode.header &&
        (token == null || token.isEmpty || token.toLowerCase() == 'bearer')) {
      throw const FormatException('Bearer token required');
    }
    if (auth != McpAuthMode.header && token != null && token.isNotEmpty) {
      throw const FormatException('Bearer token requires header auth');
    }
    return McpServerDraft._(
      name: safeName,
      transport: McpTransport.http,
      command: '',
      args: const [],
      environment: const {},
      url: parsed,
      auth: auth,
      bearerToken: token,
    );
  }

  const McpServerDraft._({
    required this.name,
    required this.transport,
    required this.command,
    required this.args,
    required this.environment,
    this.url,
    required this.auth,
    this.bearerToken,
  });

  Map<String, dynamic> toRequestJson() => switch (transport) {
    McpTransport.stdio => {
      'name': name,
      'command': command,
      if (args.isNotEmpty) 'args': args,
      if (environment.isNotEmpty) 'env': environment,
      'auth': auth.name,
    },
    McpTransport.http => {
      'name': name,
      'url': url.toString(),
      'auth': auth.name,
      if (auth == McpAuthMode.header) 'bearer_token': bearerToken,
    },
  };

  @override
  String toString() =>
      'McpServerDraft($name, ${transport.name}, ${auth.name}, '
      'secretFields: ${environment.length + (bearerToken == null ? 0 : 1)})';
}

enum McpOAuthStatus {
  starting,
  authorizationRequired,
  approved,
  error,
  expired,
  unknown,
}

final class McpOAuthFlow {
  final String flowId;
  final String serverName;
  final McpOAuthStatus status;
  final Uri? authorizationUri;
  final String? error;
  final List<String> tools;

  McpOAuthFlow({
    required this.flowId,
    required this.serverName,
    required this.status,
    this.authorizationUri,
    this.error,
    List<String> tools = const [],
  }) : tools = List<String>.unmodifiable(tools);

  factory McpOAuthFlow.fromJson(Map<String, dynamic> json) {
    final rawUrl = _optionalText(json['authorization_url'], max: 4096);
    final uri = rawUrl == null ? null : Uri.tryParse(rawUrl);
    final rawTools = json['tools'];
    final tools = <String>[];
    if (rawTools is List) {
      for (final raw in rawTools.take(500)) {
        if (raw is Map) {
          final name = _optionalText(raw['name'], max: 160);
          if (name != null) tools.add(name);
        } else {
          final name = _optionalText(raw, max: 160);
          if (name != null) tools.add(name);
        }
      }
    }
    return McpOAuthFlow(
      flowId: _requiredText(json['flow_id'], max: 256),
      serverName: _optionalText(json['server_name'], max: 160) ?? '',
      status: _oauthStatus(json['status']),
      authorizationUri:
          uri != null &&
              {'http', 'https'}.contains(uri.scheme.toLowerCase()) &&
              uri.host.isNotEmpty &&
              uri.userInfo.isEmpty
          ? uri
          : null,
      error: _optionalText(json['error'], max: 500),
      tools: tools,
    );
  }

  bool get terminal => switch (status) {
    McpOAuthStatus.approved ||
    McpOAuthStatus.error ||
    McpOAuthStatus.expired => true,
    _ => false,
  };

  @override
  String toString() =>
      'McpOAuthFlow($flowId, ${status.name}, tools: ${tools.length})';
}

final class WebhookRoute {
  final String name;
  final String description;
  final List<String> events;
  final String deliver;
  final bool deliverOnly;
  final String prompt;
  final String script;
  final List<String> skills;
  final DateTime? createdAt;
  final Uri? url;
  final bool secretSet;
  final bool enabled;

  WebhookRoute({
    required this.name,
    this.description = '',
    List<String> events = const [],
    this.deliver = 'log',
    this.deliverOnly = false,
    this.prompt = '',
    this.script = '',
    List<String> skills = const [],
    this.createdAt,
    this.url,
    this.secretSet = false,
    this.enabled = true,
  }) : events = List<String>.unmodifiable(events),
       skills = List<String>.unmodifiable(skills);

  factory WebhookRoute.fromJson(Map<String, dynamic> json) => WebhookRoute(
    name: _requiredText(json['name'], max: 160),
    description: _optionalText(json['description'], max: 1000) ?? '',
    events: _stringList(json['events'], maxRows: 100, maxLength: 160),
    deliver: _optionalText(json['deliver'], max: 80) ?? 'log',
    deliverOnly: json['deliver_only'] == true,
    prompt: _optionalText(json['prompt'], max: 12000) ?? '',
    script: _optionalText(json['script'], max: 12000) ?? '',
    skills: _stringList(json['skills'], maxRows: 100, maxLength: 160),
    createdAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
    url: _safeDisplayUri(json['url']),
    secretSet: json['secret_set'] == true,
    enabled: json['enabled'] != false,
  );

  Map<String, dynamic> toSummaryJson() => {
    'name': name,
    'description': description,
    'events': events,
    'deliver': deliver,
    'deliver_only': deliverOnly,
    'prompt': prompt,
    'script': script,
    'skills': skills,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    if (url != null) 'url': url.toString(),
    'secret_set': secretSet,
    'enabled': enabled,
  };

  @override
  String toString() =>
      'WebhookRoute($name, enabled: $enabled, secretSet: $secretSet)';
}

final class WebhookSnapshot {
  final bool enabled;
  final Uri? baseUri;
  final List<WebhookRoute> routes;

  WebhookSnapshot({
    required this.enabled,
    this.baseUri,
    List<WebhookRoute> routes = const [],
  }) : routes = List<WebhookRoute>.unmodifiable(routes);

  factory WebhookSnapshot.fromJson(Map<String, dynamic> json) {
    final routes = <WebhookRoute>[];
    final rawRoutes = json['subscriptions'];
    if (rawRoutes is List) {
      for (final raw in rawRoutes.take(500)) {
        if (raw is Map) {
          try {
            routes.add(WebhookRoute.fromJson(Map<String, dynamic>.from(raw)));
          } on FormatException {
            continue;
          }
        }
      }
    }
    return WebhookSnapshot(
      enabled: json['enabled'] == true,
      baseUri: _safeDisplayUri(json['base_url']),
      routes: routes,
    );
  }

  @override
  String toString() =>
      'WebhookSnapshot(enabled: $enabled, routes: ${routes.length})';
}

final class WebhookDraft {
  final String name;
  final String description;
  final List<String> events;
  final String prompt;
  final String script;
  final List<String> skills;
  final String deliver;
  final bool deliverOnly;
  final String? deliverChatId;
  final String? secret;

  factory WebhookDraft({
    required String name,
    String description = '',
    List<String> events = const [],
    String prompt = '',
    String script = '',
    List<String> skills = const [],
    String deliver = 'log',
    bool deliverOnly = false,
    String? deliverChatId,
    String? secret,
  }) {
    final normalizedName = name.trim().toLowerCase().replaceAll(' ', '-');
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]*$').hasMatch(normalizedName) ||
        normalizedName.length > 160) {
      throw const FormatException('Invalid webhook name');
    }
    final safeDeliver = _requiredText(deliver, max: 80);
    if (deliverOnly && safeDeliver == 'log') {
      throw const FormatException('Direct delivery requires a target');
    }
    final safeSecret = _optionalText(secret, max: 8192);
    return WebhookDraft._(
      name: normalizedName,
      description: _boundedText(description, max: 1000),
      events: _cleanUniqueStrings(events, maxRows: 100, maxLength: 160),
      prompt: _boundedText(prompt, max: 12000),
      script: _boundedText(script, max: 12000),
      skills: _cleanUniqueStrings(skills, maxRows: 100, maxLength: 160),
      deliver: safeDeliver,
      deliverOnly: deliverOnly,
      deliverChatId: _optionalText(deliverChatId, max: 512),
      secret: safeSecret,
    );
  }

  const WebhookDraft._({
    required this.name,
    required this.description,
    required this.events,
    required this.prompt,
    required this.script,
    required this.skills,
    required this.deliver,
    required this.deliverOnly,
    this.deliverChatId,
    this.secret,
  });

  Map<String, dynamic> toRequestJson() => {
    'name': name,
    if (description.isNotEmpty) 'description': description,
    'events': events,
    if (prompt.isNotEmpty) 'prompt': prompt,
    if (script.isNotEmpty) 'script': script,
    'skills': skills,
    'deliver': deliver,
    'deliver_only': deliverOnly,
    if (deliverChatId != null) 'deliver_chat_id': deliverChatId,
    if (secret != null) 'secret': secret,
  };

  @override
  String toString() =>
      'WebhookDraft($name, events: ${events.length}, hasSecret: ${secret != null})';
}

final class WebhookCreateReceipt {
  final WebhookRoute route;
  final String secret;

  const WebhookCreateReceipt({required this.route, required this.secret});

  factory WebhookCreateReceipt.fromJson(Map<String, dynamic> json) =>
      WebhookCreateReceipt(
        route: WebhookRoute.fromJson(json),
        secret: _requiredText(json['secret'], max: 8192),
      );

  @override
  String toString() =>
      'WebhookCreateReceipt(${route.name}, secret: <one-shot>)';
}

final class WebhookEnableResult {
  final bool ok;
  final bool enabled;
  final bool restartStarted;
  final bool needsRestart;

  const WebhookEnableResult({
    required this.ok,
    required this.enabled,
    required this.restartStarted,
    required this.needsRestart,
  });

  factory WebhookEnableResult.fromJson(Map<String, dynamic> json) =>
      WebhookEnableResult(
        ok: json['ok'] == true,
        enabled: json['enabled'] == true,
        restartStarted: json['restart_started'] == true,
        needsRestart: json['needs_restart'] == true,
      );
}

/// Estado no sensible de la plataforma A2A publicada por Hermes Agent.
///
/// A2A sigue siendo completamente server-side. Este modelo solo proyecta la
/// fila oficial de `/api/messaging/platforms`; no contiene configuración,
/// credenciales, peers ni endpoints de transporte.
final class A2aServerCapability {
  final bool enabled;
  final bool configured;
  final bool gatewayRunning;
  final String state;

  const A2aServerCapability({
    required this.enabled,
    required this.configured,
    required this.gatewayRunning,
    required this.state,
  });

  static A2aServerCapability? tryFromPlatformsJson(Map<String, dynamic> json) {
    final rawPlatforms = json['platforms'];
    if (rawPlatforms is! List) return null;
    for (final raw in rawPlatforms.take(100)) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final id = _optionalText(row['id'], max: 80)?.toLowerCase();
      if (id != 'a2a') continue;
      final rawState = _optionalText(row['state'], max: 80)?.toLowerCase();
      const allowedStates = {
        'connected',
        'connecting',
        'retrying',
        'disabled',
        'not_configured',
        'pending_restart',
        'gateway_stopped',
        'startup_failed',
        'disconnected',
        'fatal',
      };
      return A2aServerCapability(
        enabled: row['enabled'] == true,
        configured: row['configured'] == true,
        gatewayRunning: row['gateway_running'] == true,
        state: allowedStates.contains(rawState) ? rawState! : 'unknown',
      );
    }
    return null;
  }

  @override
  String toString() =>
      'A2aServerCapability(enabled: $enabled, configured: $configured, '
      'gatewayRunning: $gatewayRunning, state: $state)';
}

String _requiredText(Object? raw, {required int max}) {
  final value = _optionalText(raw, max: max);
  if (value == null) throw const FormatException('Required value missing');
  return value;
}

String _boundedText(String raw, {required int max}) {
  final value = raw.trim();
  if (value.length > max || value.contains('\u0000')) {
    throw const FormatException('Value out of bounds');
  }
  return value;
}

String? _optionalText(Object? raw, {required int max}) {
  if (raw == null) return null;
  final value = raw.toString().trim();
  if (value.isEmpty) return null;
  if (value.length > max || value.contains('\u0000')) {
    throw const FormatException('Value out of bounds');
  }
  return value;
}

List<String> _validateArgs(List<String> args) {
  if (args.length > 80) throw const FormatException('Too many MCP args');
  return List<String>.unmodifiable(
    args.map((value) => _requiredText(value, max: 800)),
  );
}

Map<String, String> _validateEnvironment(Map<String, String> environment) {
  if (environment.length > 40) {
    throw const FormatException('Too many MCP environment values');
  }
  final result = <String, String>{};
  for (final entry in environment.entries) {
    final key = entry.key.trim();
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,127}$').hasMatch(key) ||
        entry.value.length > 8192 ||
        entry.value.contains('\u0000')) {
      throw const FormatException('Invalid MCP environment value');
    }
    result[key] = entry.value;
  }
  return Map<String, String>.unmodifiable(result);
}

McpOAuthStatus _oauthStatus(Object? raw) => switch (raw?.toString()) {
  'starting' => McpOAuthStatus.starting,
  'authorization_required' => McpOAuthStatus.authorizationRequired,
  'approved' => McpOAuthStatus.approved,
  'error' => McpOAuthStatus.error,
  'expired' => McpOAuthStatus.expired,
  _ => McpOAuthStatus.unknown,
};

List<String> _stringList(
  Object? raw, {
  required int maxRows,
  required int maxLength,
}) {
  if (raw is! List) return const [];
  return _cleanUniqueStrings(
    raw.take(maxRows).map((item) => item.toString()),
    maxRows: maxRows,
    maxLength: maxLength,
  );
}

List<String> _cleanUniqueStrings(
  Iterable<String> values, {
  required int maxRows,
  required int maxLength,
}) {
  final result = <String>[];
  final seen = <String>{};
  for (final raw in values.take(maxRows)) {
    final value = _optionalText(raw, max: maxLength);
    if (value != null && seen.add(value)) result.add(value);
  }
  return List<String>.unmodifiable(result);
}

Uri? _safeDisplayUri(Object? raw) {
  final value = _optionalText(raw, max: 4096);
  if (value == null) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  return uri;
}
