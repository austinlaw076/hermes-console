import 'dart:convert';

import 'package:flutter/foundation.dart';

enum HomeWidgetConnectionState {
  unconfigured,
  noInstance,
  connecting,
  connected,
  error,
  disconnected,
}

enum HomeWidgetAgentState {
  idle,
  thinking,
  streaming,
  toolExecution,
  waitingApproval,
  error,
  disconnected,
}

enum HomeWidgetTheme { light, dark, oled }

/// Secret-free snapshot consumed by the Android Glance widget.
///
/// The model intentionally owns validation and serialization so Flutter,
/// tests and Kotlin all project the same bounded contract. It never accepts a
/// URL, prompt, response, credential or reasoning field.
@immutable
class HermesHomeWidgetSnapshot {
  static const schemaVersion = 1;
  static const storagePrefix = 'hermes_widget_';
  static const atomicStorageKey = '${storagePrefix}atomic_snapshot_v1';
  static const staleAfter = Duration(minutes: 15);

  const HermesHomeWidgetSnapshot({
    this.configured = false,
    this.instanceId,
    this.instanceLabel,
    this.connectionState = HomeWidgetConnectionState.unconfigured,
    this.model,
    this.provider,
    this.sessionId,
    this.sessionTitle,
    this.agentState = HomeWidgetAgentState.disconnected,
    this.toolName,
    this.contextUsed,
    this.contextMax,
    this.contextPercent,
    this.inputTokens,
    this.outputTokens,
    this.cacheReadTokens,
    this.cacheWriteTokens,
    this.firstTokenLatencyMs,
    this.lastActivityAtMs,
    this.updatedAtMs = 0,
    this.theme = HomeWidgetTheme.dark,
    this.showAdvancedMetrics = true,
  });

  static const empty = HermesHomeWidgetSnapshot();

  final bool configured;
  final String? instanceId;
  final String? instanceLabel;
  final HomeWidgetConnectionState connectionState;
  final String? model;
  final String? provider;
  final String? sessionId;
  final String? sessionTitle;
  final HomeWidgetAgentState agentState;
  final String? toolName;
  final int? contextUsed;
  final int? contextMax;
  final int? contextPercent;
  final int? inputTokens;
  final int? outputTokens;

  /// Optional future-compatible fields. Hermes currently publishes these only
  /// on some usage surfaces/providers; callers must leave them null otherwise.
  final int? cacheReadTokens;
  final int? cacheWriteTokens;

  /// Client-observed submit-to-first-token latency, only when measured by the
  /// active chat. It is not synthesized from total duration.
  final int? firstTokenLatencyMs;

  /// Real activity time for the current session. This is distinct from
  /// [updatedAtMs], which only timestamps publication/staleness.
  final int? lastActivityAtMs;
  final int updatedAtMs;
  final HomeWidgetTheme theme;
  final bool showAdvancedMetrics;

  bool isStaleAt(int nowMs) =>
      updatedAtMs <= 0 || nowMs - updatedAtMs > staleAfter.inMilliseconds;

  int? get cachePercent {
    final read = cacheReadTokens;
    final input = inputTokens;
    if (read == null || input == null) return null;
    final prompt = input + read + (cacheWriteTokens ?? 0);
    if (read <= 0 || prompt <= 0) return null;
    return ((read / prompt) * 100).round().clamp(0, 100);
  }

  HermesHomeWidgetSnapshot copyWith({
    bool? configured,
    String? instanceId,
    bool clearInstanceId = false,
    String? instanceLabel,
    bool clearInstanceLabel = false,
    HomeWidgetConnectionState? connectionState,
    String? model,
    bool clearModel = false,
    String? provider,
    bool clearProvider = false,
    String? sessionId,
    bool clearSessionId = false,
    String? sessionTitle,
    bool clearSessionTitle = false,
    HomeWidgetAgentState? agentState,
    String? toolName,
    bool clearToolName = false,
    int? contextUsed,
    bool clearContextUsed = false,
    int? contextMax,
    bool clearContextMax = false,
    int? contextPercent,
    bool clearContextPercent = false,
    int? inputTokens,
    bool clearInputTokens = false,
    int? outputTokens,
    bool clearOutputTokens = false,
    int? cacheReadTokens,
    bool clearCacheReadTokens = false,
    int? cacheWriteTokens,
    bool clearCacheWriteTokens = false,
    int? firstTokenLatencyMs,
    bool clearFirstTokenLatencyMs = false,
    int? lastActivityAtMs,
    bool clearLastActivityAtMs = false,
    int? updatedAtMs,
    HomeWidgetTheme? theme,
    bool? showAdvancedMetrics,
  }) => HermesHomeWidgetSnapshot(
    configured: configured ?? this.configured,
    instanceId: clearInstanceId ? null : instanceId ?? this.instanceId,
    instanceLabel: clearInstanceLabel
        ? null
        : instanceLabel ?? this.instanceLabel,
    connectionState: connectionState ?? this.connectionState,
    model: clearModel ? null : model ?? this.model,
    provider: clearProvider ? null : provider ?? this.provider,
    sessionId: clearSessionId ? null : sessionId ?? this.sessionId,
    sessionTitle: clearSessionTitle ? null : sessionTitle ?? this.sessionTitle,
    agentState: agentState ?? this.agentState,
    toolName: clearToolName ? null : toolName ?? this.toolName,
    contextUsed: clearContextUsed ? null : contextUsed ?? this.contextUsed,
    contextMax: clearContextMax ? null : contextMax ?? this.contextMax,
    contextPercent: clearContextPercent
        ? null
        : contextPercent ?? this.contextPercent,
    inputTokens: clearInputTokens ? null : inputTokens ?? this.inputTokens,
    outputTokens: clearOutputTokens ? null : outputTokens ?? this.outputTokens,
    cacheReadTokens: clearCacheReadTokens
        ? null
        : cacheReadTokens ?? this.cacheReadTokens,
    cacheWriteTokens: clearCacheWriteTokens
        ? null
        : cacheWriteTokens ?? this.cacheWriteTokens,
    firstTokenLatencyMs: clearFirstTokenLatencyMs
        ? null
        : firstTokenLatencyMs ?? this.firstTokenLatencyMs,
    lastActivityAtMs: clearLastActivityAtMs
        ? null
        : lastActivityAtMs ?? this.lastActivityAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    theme: theme ?? this.theme,
    showAdvancedMetrics: showAdvancedMetrics ?? this.showAdvancedMetrics,
  );

  factory HermesHomeWidgetSnapshot.fromMap(Map<Object?, Object?> map) {
    final version = _safeInt(map['schema_version']);
    if (version != schemaVersion) return empty;
    final used = _safeNonNegativeInt(map['context_used']);
    final max = _safePositiveInt(map['context_max']);
    final suppliedPercent = _safeNonNegativeInt(map['context_percent']);
    final percent = max == null || used == null
        ? null
        : (suppliedPercent ?? ((used / max) * 100).round()).clamp(0, 100);
    return HermesHomeWidgetSnapshot(
      configured: _safeBool(map['configured']),
      instanceId: _safeText(map['instance_id'], 256, opaque: true),
      instanceLabel: _safeText(map['instance_label'], 64),
      connectionState: _enumByName(
        HomeWidgetConnectionState.values,
        map['connection_state'],
        HomeWidgetConnectionState.unconfigured,
      ),
      model: _safeText(map['model'], 96),
      provider: _safeText(map['provider'], 64),
      sessionId: _safeText(map['session_id'], 256, opaque: true),
      sessionTitle: _safeText(map['session_title'], 96),
      agentState: _enumByName(
        HomeWidgetAgentState.values,
        map['agent_state'],
        HomeWidgetAgentState.disconnected,
      ),
      toolName: _safeText(map['tool_name'], 64),
      contextUsed: used,
      contextMax: max,
      contextPercent: percent,
      inputTokens: _safeNonNegativeInt(map['input_tokens']),
      outputTokens: _safeNonNegativeInt(map['output_tokens']),
      cacheReadTokens: _safeNonNegativeInt(map['cache_read_tokens']),
      cacheWriteTokens: _safeNonNegativeInt(map['cache_write_tokens']),
      firstTokenLatencyMs: _safeNonNegativeInt(map['first_token_latency_ms']),
      lastActivityAtMs: _safeNonNegativeInt(map['last_activity_at_ms']),
      updatedAtMs: _safeNonNegativeInt(map['updated_at_ms']) ?? 0,
      theme: _enumByName(
        HomeWidgetTheme.values,
        map['theme'],
        HomeWidgetTheme.dark,
      ),
      showAdvancedMetrics: map.containsKey('show_advanced_metrics')
          ? _safeBool(map['show_advanced_metrics'])
          : true,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'schema_version': schemaVersion,
    'configured': configured,
    'instance_id': _safeText(instanceId, 256, opaque: true),
    'instance_label': _safeText(instanceLabel, 64),
    'connection_state': connectionState.name,
    'model': _safeText(model, 96),
    'provider': _safeText(provider, 64),
    'session_id': _safeText(sessionId, 256, opaque: true),
    'session_title': _safeText(sessionTitle, 96),
    'agent_state': agentState.name,
    'tool_name': _safeText(toolName, 64),
    'context_used': _safeNonNegativeInt(contextUsed),
    'context_max': _safePositiveInt(contextMax),
    'context_percent': contextPercent?.clamp(0, 100),
    'input_tokens': _safeNonNegativeInt(inputTokens),
    'output_tokens': _safeNonNegativeInt(outputTokens),
    'cache_read_tokens': _safeNonNegativeInt(cacheReadTokens),
    'cache_write_tokens': _safeNonNegativeInt(cacheWriteTokens),
    'first_token_latency_ms': _safeNonNegativeInt(firstTokenLatencyMs),
    'last_activity_at_ms': _safeNonNegativeInt(lastActivityAtMs),
    'updated_at_ms': _safeNonNegativeInt(updatedAtMs) ?? 0,
    'theme': theme.name,
    'show_advanced_metrics': showAdvancedMetrics,
  };

  Map<String, Object?> toStorageMap() => <String, Object?>{
    for (final entry in toMap().entries)
      '$storagePrefix${entry.key}': entry.value,
  };

  String toAtomicStorageValue() => jsonEncode(toMap());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HermesHomeWidgetSnapshot && mapEquals(toMap(), other.toMap());

  @override
  int get hashCode => Object.hashAll(toMap().entries);
}

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is String) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
  }
  return fallback;
}

bool _safeBool(Object? value) => value == true;

int? _safeInt(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  if (value is String) return int.tryParse(value);
  return null;
}

int? _safeNonNegativeInt(Object? value) {
  final parsed = _safeInt(value);
  return parsed == null || parsed < 0 ? null : parsed;
}

int? _safePositiveInt(Object? value) {
  final parsed = _safeNonNegativeInt(value);
  return parsed == null || parsed == 0 ? null : parsed;
}

String? _safeText(Object? value, int maxLength, {bool opaque = false}) {
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  if (opaque && !RegExp(r'^[A-Za-z0-9._:@+-]+$').hasMatch(trimmed)) {
    return null;
  }
  return trimmed.length <= maxLength
      ? trimmed
      : trimmed.substring(0, maxLength);
}
