// Textos de las notificaciones, localizados SIN BuildContext.
//
// Las notificaciones se disparan también desde un isolate de segundo plano
// (BackgroundListener) donde no hay `BuildContext` ni `AppLocalizations`. Por
// eso no usamos gen-l10n aquí: resolvemos el idioma con [AppLocaleResolve] y
// devolvemos textos a mano (es / en / zh_Hant). Mantener en sintonía con
// lib/l10n cuando cambie el tono.
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_locale_resolve.dart';

class NotifL10n {
  final AppLocaleKind kind;

  const NotifL10n(this.kind);

  /// Compat: true = español (tests legacy).
  bool get es => kind == AppLocaleKind.es;

  /// Compat constructores legacy.
  const NotifL10n.spanish() : kind = AppLocaleKind.es;
  const NotifL10n.english() : kind = AppLocaleKind.en;
  const NotifL10n.zhHant() : kind = AppLocaleKind.zhHant;

  /// Resuelve desde `app_locale` (system / es / en / zh_Hant).
  factory NotifL10n.of(SharedPreferences prefs) {
    return NotifL10n(AppLocaleResolve.fromPrefs(prefs));
  }

  String _(String es_, String en, [String? zh]) =>
      AppLocaleResolve.pick(kind, es: es_, en: en, zh: zh);

  // ── Marca / genéricos ─────────────────────────────────────────────────────
  String get brand => 'Hermes';
  String get agentTask => _('Tarea del agente', 'Agent task', '代理任務');
  String get privateTitle => _(
        'Nueva actividad en Hermes',
        'New Hermes activity',
        'Hermes 有新活動',
      );
  String get privateBody => _(
        'Abre la aplicación para ver los detalles.',
        'Open the app to view the details.',
        '開啟應用程式以查看詳情。',
      );

  // ── Canales ───────────────────────────────────────────────────────────────
  String get chApprovals => _('Aprobaciones', 'Approvals', '批准');
  String get chApprovalsDesc => _(
        'Permisos que el agente necesita de ti',
        'Permissions the agent needs from you',
        '代理需要你批准的權限',
      );
  String get chReplies => _('Respuestas', 'Replies', '回覆');
  String get chRepliesDesc => _(
        'Cuando el agente termina de responder',
        'When the agent finishes replying',
        '代理完成回覆時',
      );
  String get chRuns => _('Ejecuciones', 'Runs', '執行');
  String get chRunsDesc => _(
        'Estado de las tareas en ejecución',
        'Status of running tasks',
        '執行中任務的狀態',
      );
  String get chTransfers => _('Transferencias', 'Transfers', '傳輸');
  String get chTransfersDesc => _(
        'Progreso de subidas y descargas SFTP',
        'SFTP upload and download progress',
        'SFTP 上傳／下載進度',
      );
  String get chVoice => _('Modo voz', 'Voice mode', '語音模式');
  String get chVoiceDesc => _(
        'Estado del modo voz activo',
        'Active voice mode status',
        '使用中語音模式狀態',
      );

  // ── Aprobaciones ──────────────────────────────────────────────────────────
  String get approvalTitle => _(
        'Hermes necesita tu permiso',
        'Hermes needs your permission',
        'Hermes 需要你的批准',
      );
  String approvalBody(String tool, String where) => _(
        'Decisión pendiente sobre «$tool»$where',
        'Pending decision on “$tool”$where',
        '待決定：$tool$where',
      );

  // ── Ejecuciones ───────────────────────────────────────────────────────────
  String get runCompleted =>
      _('Ejecución completada', 'Run completed', '執行完成');
  String get runFailed =>
      _('Ejecución con errores', 'Run failed', '執行失敗');
  String get kanbanCompleted => _(
        'Tarea de Kanban completada',
        'Kanban task completed',
        'Kanban 任務完成',
      );
  String get kanbanBlocked => _(
        'Tarea de Kanban bloqueada',
        'Kanban task blocked',
        'Kanban 任務已封鎖',
      );
  String get kanbanNeedsAttention => _(
        'Kanban necesita tu atención',
        'Kanban needs your attention',
        'Kanban 需要你留意',
      );
  String get kanbanUpdated => _(
        'Tarea de Kanban actualizada',
        'Kanban task updated',
        'Kanban 任務已更新',
      );

  // ── Respuestas ────────────────────────────────────────────────────────────
  String replyTitle(String? session) {
    final s = session?.trim() ?? '';
    if (s.isEmpty) {
      return _('Hermes respondió', 'Hermes replied', 'Hermes 已回覆');
    }
    return _(
      'Hermes respondió en $s',
      'Hermes replied in $s',
      'Hermes 已在 $s 回覆',
    );
  }

  String get replyReadyBody => _(
        'Respuesta lista. Toca para abrir.',
        'Reply ready. Tap to open.',
        '回覆已就緒。點一下開啟。',
      );

  String replyFailedTitle(String? session) {
    final s = session?.trim() ?? '';
    if (s.isEmpty) {
      return _(
        'Hermes encontró un problema',
        'Hermes hit a problem',
        'Hermes 遇到問題',
      );
    }
    return _('Problema en $s', 'Problem in $s', '$s 出現問題');
  }

  String get replyFailedBody => _(
        'El agente no pudo completar la tarea.',
        'The agent could not complete the task.',
        '代理未能完成任務。',
      );

  // ── Agente local ──────────────────────────────────────────────────────────
  String get localInstalled => _(
        'Hermes local instalado',
        'Local Hermes installed',
        '本機 Hermes 已安裝',
      );
  String get localInstallError => _(
        'Error al instalar Hermes local',
        'Error installing local Hermes',
        '安裝本機 Hermes 時出錯',
      );
  String get localInstalledBody => _(
        'El agente Hermes local se instaló en el dispositivo.',
        'The local Hermes agent was installed on the device.',
        '本機 Hermes 代理已安裝到此裝置。',
      );
  String get localInstallErrorBody => _(
        'No se pudo completar la instalación.',
        'Could not complete installation.',
        '未能完成安裝。',
      );
  String get localRemoved => _(
        'Hermes local eliminado',
        'Local Hermes removed',
        '本機 Hermes 已移除',
      );
  String get localRemoveError => _(
        'Error al eliminar Hermes local',
        'Error removing local Hermes',
        '移除本機 Hermes 時出錯',
      );
  String get localRemovedBody => _(
        'El agente Hermes local se eliminó del dispositivo.',
        'The local Hermes agent was removed from the device.',
        '本機 Hermes 代理已從此裝置移除。',
      );
  String get localRemoveErrorBody => _(
        'No se pudieron eliminar algunos archivos.',
        'Some files could not be removed.',
        '部分檔案未能移除。',
      );

  // ── Prueba ────────────────────────────────────────────────────────────────
  String get testTitle => 'Hermes Console';
  String get testBody => _(
        'Las notificaciones funcionan. Te avisaré de aprobaciones, ejecuciones y respuestas.',
        'Notifications are working. I will notify you of approvals, runs and replies.',
        '通知正常。會在批准、執行與回覆時通知你。',
      );

  // ── Acciones ──────────────────────────────────────────────────────────────
  String get actApprove => _('Aprobar', 'Approve', '批准');
  String get actDeny => _('Rechazar', 'Deny', '拒絕');
  String get actOpen => _('Abrir', 'Open', '開啟');

  // ── Servicio en segundo plano ─────────────────────────────────────────────
  String get bgChannel => _(
        'Servicio en segundo plano',
        'Background service',
        '背景服務',
      );
  String get bgChannelDesc => _(
        'Mantiene a Hermes activo con la app cerrada',
        'Keeps Hermes active while the app is closed',
        '應用程式關閉時仍保持 Hermes 運作',
      );
  String get bgActive => _(
        'Activo en segundo plano',
        'Active in the background',
        '背景運作中',
      );
  String bgWatching(int n) => _(
        'Vigilando $n ejecución(es)',
        'Watching $n run(s)',
        '正在監察 $n 項執行',
      );
  String get bgStop => _('Detener', 'Stop', '停止');

  // ── Modo voz ──────────────────────────────────────────────────────────────
  String get voiceTitle => _('Modo voz', 'Voice mode', '語音模式');
  String get vListening => _('Escuchando…', 'Listening…', '正在聽…');
  String get vTranscribing =>
      _('Transcribiendo…', 'Transcribing…', '正在轉寫…');
  String get vThinking => _('Pensando…', 'Thinking…', '思考中…');
  String get vTool => _(
        'Ejecutando una herramienta…',
        'Running a tool…',
        '正在執行工具…',
      );
  String get vWaitingApproval => _(
        'Necesita aprobación',
        'Needs approval',
        '需要批准',
      );
  String get vSpeaking => _('Hablando…', 'Speaking…', '正在說…');
  String get vError => _('Error en modo voz', 'Voice mode error', '語音模式錯誤');
  String get voiceActive => _(
        'Puedes seguir hablando · toca para abrir Hermes',
        'Keep talking · tap to open Hermes',
        '可以繼續說 · 點一下開啟 Hermes',
      );
  String get voicePaused => _(
        'Conversación en pausa · pulsa Continuar o abre Hermes',
        'Conversation paused · tap Continue or open Hermes',
        '對話已暫停 · 按繼續或開啟 Hermes',
      );
  String get voiceWaitingApproval => _(
        'Hermes necesita aprobación · pulsa Revisar',
        'Hermes needs approval · tap Review',
        'Hermes 需要批准 · 按檢視',
      );
  String get voiceOpenHintActive => _(
        'Sigue hablando · toca para abrir Hermes',
        'Keep talking · tap to open Hermes',
        '繼續說 · 點一下開啟 Hermes',
      );
  String get voiceOpenHintPaused => _(
        'Pulsa Continuar o toca para abrir Hermes',
        'Tap Continue or tap to open Hermes',
        '按繼續或點一下開啟 Hermes',
      );
  String get voiceOpenHintApproval => _(
        'Pulsa Revisar para aprobar en Hermes',
        'Tap Review to approve in Hermes',
        '按檢視以在 Hermes 批准',
      );
  String get voiceCardListening => _('Escuchando', 'Listening', '正在聽');
  String get voiceCardPaused => _('En pausa', 'Paused', '已暫停');
  String get voiceCardWaitingApproval => _(
        'Necesita aprobación',
        'Needs approval',
        '需要批准',
      );
  String get voiceCardMicActive => _(
        'Micrófono activo',
        'Microphone active',
        '麥克風開啟',
      );
  String get voiceCardMicPaused => _(
        'Micrófono pausado',
        'Microphone paused',
        '麥克風已暫停',
      );
  String get voiceCardOrbDescription => _(
        'Estado de voz de Hermes',
        'Hermes voice status',
        'Hermes 語音狀態',
      );
  String get voiceCardDurationDescription => _(
        'Duración de la conversación',
        'Conversation duration',
        '對話時長',
      );
  String get voicePause => _('Pausar', 'Pause', '暫停');
  String get voiceContinue => _('Continuar', 'Continue', '繼續');
  String get voiceReviewApproval => _('Revisar', 'Review', '檢視');
  String get voiceEnd => _('Terminar', 'End', '結束');
  String get voiceEndConversation => _(
        'Terminar conversación',
        'End conversation',
        '結束對話',
      );
  String get readAloudPlaying => _(
        'Leyendo respuesta',
        'Reading response',
        '正在朗讀回覆',
      );
  String get readAloudPaused => _(
        'Lectura en pausa',
        'Reading paused',
        '朗讀已暫停',
      );
}
