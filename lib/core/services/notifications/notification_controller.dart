import 'dart:async';

import 'package:hermes_android/core/services/notifications/notification_service.dart';
import 'package:hermes_android/core/services/run_registry.dart';

/// Capa semántica entre los eventos SSE de ejecución y NotificationService.
/// Traduce RunRecord a notificaciones Android sin duplicar la lógica de
/// notificación ni interferir con BackgroundListener (que solo actúa en segundo
/// plano; este controlador actúa desde TaskCenterScreen mientras la app está
/// en primer plano).
///
/// Reglas de ruido:
///   • message.delta        → nunca notificar
///   • tool.started/done    → debounce 5 s + intervalo mínimo 15 s
///   • approval.request     → siempre (bypassa supresión en foreground)
///   • terminales           → siempre (completed/failed/cancelled)
class NotificationController {
  final RunNotificationFacade _notif;
  /// ID de la conexión activa. Se propaga al payload de todas las
  /// notificaciones para que el tap pueda navegar al run correcto.
  final String? _connId;

  // Timers de debounce de progreso activos, indexados por runId.
  final Map<String, Timer> _progressTimers = {};
  // Última vez que se disparó una notificación de progreso por runId.
  final Map<String, DateTime> _lastProgressAt = {};

  // runId del run que emitió la última notificación de aprobación.
  // Solo se cancela la aprobación si el run que termina es el mismo.
  String? _pendingApprovalRunId;

  static const _debounce = Duration(seconds: 5);
  static const _minProgressInterval = Duration(seconds: 15);

  NotificationController(this._notif, {this._connId});

  // ── API pública ─────────────────────────────────────────────────────────────

  /// Llamado cuando el servidor acepta el run (SSE aún no iniciado).
  /// No notifica: en foreground el usuario ya ve la tarjeta en la lista.
  void notifyRunStarted(RunRecord run) {}

  /// Llamado en tool.started/completed con progressLabel actualizado.
  /// Debouncea 5 s y respeta un intervalo mínimo de 15 s para no saturar.
  void notifyRunProgress(RunRecord run) {
    if (!_notif.notifyRuns) return;
    _progressTimers[run.runId]?.cancel();
    _progressTimers[run.runId] = Timer(_debounce, () async {
      _progressTimers.remove(run.runId);
      final last = _lastProgressAt[run.runId];
      if (last != null &&
          DateTime.now().difference(last) < _minProgressInterval) {
        return;
      }
      _lastProgressAt[run.runId] = DateTime.now();
      await _notif.runLive(
        runId: run.runId,
        title: _truncate(run.prompt),
        body: run.progressLabel ?? 'Ejecutando…',
        connId: _connId,
        sessionId: run.sessionId,
      );
    });
  }

  /// Llamado cuando llega approval.request por SSE.
  /// Siempre bypassa la supresión en foreground (accionable + sensible al tiempo).
  void notifyRunWaitingApproval(RunRecord run) {
    _clearTimers(run.runId);
    _pendingApprovalRunId = run.runId;
    _notif.approvalPending(
      tool: run.progressLabel ?? 'herramienta',
      connId: _connId,
      sessionId: run.sessionId,
      sessionTitle: _truncate(run.prompt),
      runId: run.runId,
    );
  }

  /// Llamado cuando run.completed llega por SSE.
  void notifyRunFinished(RunRecord run) => _notifyTerminal(run, ok: true);

  /// Llamado cuando run.failed llega por SSE.
  void notifyRunFailed(RunRecord run) => _notifyTerminal(run, ok: false);

  /// Llamado cuando run.cancelled llega por SSE. Cancela la notificación de
  /// progreso sin emitir nueva notificación (fue acción del usuario).
  void notifyRunCancelled(RunRecord run) {
    _clearTimers(run.runId);
    _notif.cancelRun(run.runId);
    _cancelApprovalIfOwner(run.runId);
  }

  /// Cancela cualquier notificación activa para el run (progreso o live).
  void clearRunNotification(String runId) {
    _clearTimers(runId);
    _notif.cancelRun(runId);
  }

  /// Libera todos los timers pendientes. Llamar en dispose() de la pantalla.
  void dispose() {
    for (final t in _progressTimers.values) {
      t.cancel();
    }
    _progressTimers.clear();
    _lastProgressAt.clear();
    _pendingApprovalRunId = null;
  }

  // ── Internos ─────────────────────────────────────────────────────────────────

  void _notifyTerminal(RunRecord run, {required bool ok}) {
    _clearTimers(run.runId);
    _notif.cancelRun(run.runId);
    _cancelApprovalIfOwner(run.runId);
    _notif.runFinished(
      title: _truncate(run.prompt),
      ok: ok,
      connId: _connId,
      sessionId: run.sessionId,
      runId: run.runId,
    );
  }

  /// Cancela la notificación de aprobación solo si este run la emitió.
  void _cancelApprovalIfOwner(String runId) {
    if (_pendingApprovalRunId == runId) {
      _pendingApprovalRunId = null;
      _notif.cancelApproval();
    }
  }

  void _clearTimers(String runId) {
    _progressTimers[runId]?.cancel();
    _progressTimers.remove(runId);
    _lastProgressAt.remove(runId);
  }

  static String _truncate(String s, [int max = 60]) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}
