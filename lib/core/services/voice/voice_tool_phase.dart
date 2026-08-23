/// Categoría operacional segura que Modo Voz puede proyectar sin mostrar el
/// nombre técnico, los argumentos o el preview remoto de una herramienta.
enum VoiceToolActivity {
  search,
  browse,
  read,
  write,
  execute,
  install,
  remove,
  coordinate,
  check,
}

/// Resuelve la única línea visible de Voz sin depender de la fase concreta.
///
/// El comentario ya llega sanitizado y cercado al turno por
/// `VoiceUiSurface.publicCommentary`. Pausa es una acción explícita del usuario
/// y conserva precedencia; en cualquier otra fase el comentario público gana
/// frente a la categoría de herramienta o etiqueta segura recibida en
/// [fallbackLabel].
String voiceActivityLineLabel({
  required bool paused,
  required String pausedLabel,
  required String publicCommentary,
  required String fallbackLabel,
}) {
  if (paused) return pausedLabel;
  final commentary = publicCommentary.trim();
  return commentary.isEmpty ? fallbackLabel : commentary;
}

/// Agrupa la etiqueta técnica de una herramienta en una actividad estable.
///
/// La clasificación usa únicamente el nombre allowlisted. Nunca inspecciona el
/// comando, la ruta, la query ni el resultado de la herramienta.
VoiceToolActivity? voiceToolActivity(String toolLabel) {
  final normalized = toolLabel
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)}_${match.group(2)}',
      )
      .toLowerCase();
  final tokens = normalized
      .split(RegExp(r'[^a-z0-9]+'))
      .where((token) => token.isNotEmpty)
      .toSet();
  bool containsAny(List<String> values) => values.any(tokens.contains);

  if (containsAny(const ['delete', 'remove', 'destroy'])) {
    return VoiceToolActivity.remove;
  }
  if (containsAny(const ['install', 'deploy'])) {
    return VoiceToolActivity.install;
  }
  if (containsAny(const [
    'write',
    'create',
    'save',
    'mkdir',
    'touch',
    'edit',
    'patch',
    'apply',
    'modify',
    'update',
    'rename',
    'move',
  ])) {
    return VoiceToolActivity.write;
  }
  if (containsAny(const [
    'browser',
    'browse',
    'navigate',
    'console',
    'click',
    'screenshot',
    'scroll',
  ])) {
    return VoiceToolActivity.browse;
  }
  if (containsAny(const [
    'search',
    'web',
    'fetch',
    'research',
    'google',
    'http',
    'url',
    'query',
    'retrieve',
    'scrape',
    'crawl',
    'lookup',
    'wiki',
    'extract',
    'download',
  ])) {
    return VoiceToolActivity.search;
  }
  if (containsAny(const [
    'delegate',
    'subagent',
    'agent',
    'team',
    'coordinate',
    'orchestrate',
    'orchestrator',
    'orchestration',
    'todo',
    'plan',
  ])) {
    return VoiceToolActivity.coordinate;
  }
  if (containsAny(const [
    'read',
    'open',
    'view',
    'list',
    'grep',
    'find',
    'inspect',
    'analyze',
    'diff',
  ])) {
    return VoiceToolActivity.read;
  }
  if (containsAny(const [
    'run',
    'exec',
    'execute',
    'bash',
    'shell',
    'command',
    'cmd',
    'script',
    'build',
    'make',
    'code',
  ])) {
    return VoiceToolActivity.execute;
  }
  if (containsAny(const [
    'status',
    'check',
    'health',
    'test',
    'verify',
    'probe',
  ])) {
    return VoiceToolActivity.check;
  }
  return null;
}

/// Compatibilidad para consumidores que solo necesitan el wire anterior.
String? voiceToolPhase(String toolLabel) =>
    switch (voiceToolActivity(toolLabel)) {
      VoiceToolActivity.execute => 'exec',
      VoiceToolActivity.remove => 'delete',
      VoiceToolActivity.search => 'search',
      VoiceToolActivity.browse => 'browse',
      VoiceToolActivity.read => 'read',
      VoiceToolActivity.write => 'write',
      VoiceToolActivity.install => 'install',
      VoiceToolActivity.coordinate => 'coordinate',
      VoiceToolActivity.check => 'check',
      null => null,
    };
