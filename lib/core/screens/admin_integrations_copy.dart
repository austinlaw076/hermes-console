import 'package:flutter/widgets.dart';

import '../l10n/app_locale_resolve.dart';

/// Copy ES/EN/zh_Hant tipada de la superficie de integraciones 0.20.
///
/// No se decide por región ni por dispositivo: sigue el locale efectivo de la
/// aplicación igual que el resto de superficies localizadas.
final class AdminIntegrationsCopy {
  final AppLocaleKind _kind;

  const AdminIntegrationsCopy._(this._kind);

  factory AdminIntegrationsCopy.of(BuildContext context) =>
      AdminIntegrationsCopy._(
        AppLocaleResolve.fromLocale(Localizations.localeOf(context)),
      );

  String _t(String es, String en, [String? zh]) =>
      AppLocaleResolve.pick(_kind, es: es, en: en, zh: zh);

  String get screenTitle =>
      _t('Integraciones del servidor', 'Server integrations', '伺服器整合');
  String get entryTitle =>
      _t('Integraciones del servidor', 'Server integrations', '伺服器整合');
  String get entryBody => _t('MCP manual, OAuth, webhooks y estado A2A del servidor.', 'Manual MCP, OAuth, webhooks and server-side A2A status.', '手動 MCP、OAuth、webhook 及伺服器端 A2A 狀態。');
  String get sectionLabel =>
      _t('Secciones de integraciones', 'Integration sections', '整合部分');
  String get mcpTab => 'MCP';
  String get webhooksTab => 'Webhooks';
  String get serverTab => _t('Servidor', 'Server', '伺服器');
  String get readOnly => _t('Esta instancia es de solo lectura. Puedes consultar el estado, pero los cambios del servidor están desactivados.', 'This instance is read-only. You can inspect state, but server changes are disabled.', '此執行個體為唯讀。你可以檢視狀態，但已停用伺服器變更。');
  String get refresh => _t('Actualizar', 'Refresh', '重新整理');
  String get retry => _t('Reintentar', 'Retry', '重試');
  String get cancel => _t('Cancelar', 'Cancel', '取消');
  String get close => _t('Cerrar', 'Close', '關閉');
  String get done => _t('Listo', 'Done', '完成');
  String get copy => _t('Copiar', 'Copy', '複製');
  String get copied => _t('Copiado.', 'Copied.', '已複製。');
  String get delete => _t('Eliminar', 'Delete', '刪除');
  String get moreOptions => _t('Más opciones', 'More options', '更多選項');

  String get mcpIntro => _t('Añade un servidor con el mismo contrato de alta individual de Hermes Desktop. Los valores introducidos se envían una vez y la app no los guarda.', 'Add a server with the same individual create contract as Hermes Desktop. Values entered here are sent once and are not saved by the app.', '新增伺服器，使用與 Hermes Desktop 相同的個別建立合約。此處輸入的值只會傳送一次，應用程式不會儲存這些值。');
  String get addMcp =>
      _t('Añadir servidor MCP manualmente', 'Add MCP server manually', '手動新增 MCP 伺服器');
  String get addMcpBody => _t('Configuración guiada para un comando local o un endpoint HTTP.', 'Guided setup for a local command or an HTTP endpoint.', '為本機指令或 HTTP 端點提供引導式設定。');
  String get noMcpPut => _t('Los servidores existentes nunca se editan reemplazando el mapa MCP completo, porque podrían perderse credenciales redactadas.', 'Existing servers are never edited by replacing the full MCP map, because redacted credentials could be lost.', '現有伺服器絕不會透過替換完整 MCP 對應表來編輯，因為這可能會遺失已遮蔽的認證資料。');
  String get manualMcpUnavailable => _t('Esta versión de Hermes no publica el alta individual de MCP.', 'This Hermes version does not publish individual MCP provisioning.', '此 Hermes 版本不提供個別 MCP 佈建。');
  String get mcpFormTitle => _t('Nuevo servidor MCP', 'New MCP server', '新增 MCP 伺服器');
  String get transport => _t('Transporte', 'Transport', '傳輸方式');
  String get stdio => _t('Comando local', 'Local command', '本機指令');
  String get http => 'HTTP';
  String get name => _t('Nombre', 'Name', '名稱');
  String get nameHint => _t('p. ej. reports', 'e.g. reports', '例如：報告');
  String get command => _t('Comando', 'Command', '指令');
  String get commandHint => _t('p. ej. npx', 'e.g. npx', '例如 npx');
  String get arguments => _t('Argumentos', 'Arguments', '引數');
  String get argumentsHint => _t('Un argumento por línea. No se interpreta mediante un shell.', 'One argument per line. No shell parsing is applied.', '每行一個引數。不會進行 Shell 解析。');
  String get environment =>
      _t('Variables de entorno', 'Environment variables', '環境變數');
  String get environmentHint => _t('Los valores solo permanecen en memoria hasta enviar o cerrar este formulario.', 'Values remain in memory only until this form is submitted or closed.', '值只會保留在記憶體中，直至提交或關閉此表格。');
  String get variableName => _t('Variable', 'Variable', '變數');
  String get variableValue => _t('Valor', 'Value', '值');
  String get addVariable => _t('Añadir variable', 'Add variable', '新增變數');
  String get removeVariable => _t('Quitar variable', 'Remove variable', '移除變數');
  String get endpointUrl => _t('URL de MCP', 'MCP URL', 'MCP URL');
  String get endpointHint => _t('HTTPS, o HTTP únicamente en una dirección privada LAN/Tailscale.', 'HTTPS, or HTTP only on a private LAN/Tailscale address.', 'HTTPS，或只可在私人 LAN/Tailscale 位址使用 HTTP。');
  String get authentication => _t('Autenticación', 'Authentication', '認證');
  String get authNone => _t('Ninguna', 'None', '無');
  String get authHeader => _t('Cabecera Bearer', 'Bearer header', 'Bearer 標頭');
  String get authOauth => _t('OAuth en navegador', 'OAuth in browser', '在瀏覽器中進行 OAuth');
  String get bearerToken => _t('Token Bearer', 'Bearer token', 'Bearer 權杖');
  String get bearerHint => _t('Se envía una vez a Hermes y la app nunca lo guarda.', 'Sent once to Hermes and never stored by the app.', '只會傳送一次至 Hermes，應用程式永不會儲存。');
  String get createMcp => _t('Añadir servidor', 'Add server', '新增伺服器');
  String get mcpCreated =>
      _t('Servidor MCP añadido.', 'MCP server added.', '已新增 MCP 伺服器。');
  String get invalidForm => _t('Revisa los campos marcados y sus ejemplos.', 'Check the highlighted fields and their examples.', '請檢查以醒目顯示的欄位及其範例。');
  String get incompleteEnvironment => _t('Cada fila de entorno necesita una variable y un valor.', 'Each environment row needs both a variable and a value.', '每個環境列都需要變數和值。');
  String get authorize => _t('Autorizar OAuth', 'Authorize OAuth', '授權 OAuth');

  String get oauthTitle =>
      _t('Autorizar servidor MCP', 'Authorize MCP server', '授權 MCP 伺服器');
  String get oauthBody => _t('Hermes recibe el callback. Esta app solo abre la página de autorización y comprueba el flujo temporal mientras esta ventana está visible.', 'Hermes receives the callback. This app only opens the authorization page and checks the short-lived flow while this window is visible.', 'Hermes 會接收回呼。此應用程式只會開啟授權頁面，並在此視窗可見期間檢查短暫流程。');
  String get openBrowser =>
      _t('Abrir página de autorización', 'Open authorization page', '開啟授權頁面');
  String get openingBrowserFailed => _t('Android no pudo abrir la página de autorización.', 'Android could not open the authorization page.', 'Android 無法開啟授權頁面。');
  String get oauthWaiting =>
      _t('Esperando autorización…', 'Waiting for authorization…', '正在等待授權…');
  String get oauthApproved =>
      _t('Autorización completada.', 'Authorization complete.', '授權完成。');
  String get oauthError => _t('Hermes indicó un error de autorización.', 'Hermes reported an authorization error.', 'Hermes 回報授權錯誤。');
  String get oauthExpired => _t('Este flujo de autorización caducó. Inícialo de nuevo.', 'This authorization flow expired. Start it again.', '此授權流程已過期。請重新開始。');
  String get oauthUnknown => _t('Hermes devolvió un estado de autorización desconocido.', 'Hermes returned an unknown authorization state.', 'Hermes 傳回不明的授權狀態。');
  String oauthTools(int count) => AppLocaleResolve.pick(
        _kind,
        es:
            '$count ${count == 1 ? 'herramienta disponible' : 'herramientas disponibles'}',
        en: '$count ${count == 1 ? 'tool' : 'tools'} available',
        zh: count == 1 ? '$count 個可用工具' : '$count 個可用工具',
      );

  String get webhooksIntro => _t('Webhooks es una plataforma oficial del Gateway de Hermes. Las suscripciones se recargan en caliente cuando el receptor está activo.', 'Webhooks are an official Hermes gateway platform. Subscriptions hot-reload after the receiver is enabled.', 'Webhooks 是 Hermes 的官方閘道平台。啟用接收器後，訂閱會自動熱重載。');
  String get webhooksUnavailable => _t('Esta versión de Hermes no publica la administración de webhooks.', 'This Hermes version does not publish webhook administration.', '此 Hermes 版本不提供 Webhook 管理功能。');
  String get webhookLoadFailed => _t('No se pudieron cargar los webhooks.', 'Webhooks could not be loaded.', '無法載入 Webhook。');
  String get webhooksDisabled => _t('Receptor de webhooks desactivado', 'Webhook receiver disabled', 'Webhook 接收器已停用');
  String get webhooksDisabledBody => _t('Actívalo para aceptar eventos HTTP entrantes. Hermes puede necesitar reiniciar el Gateway.', 'Enable it to accept incoming HTTP events. Hermes may need to restart the Gateway.', '啟用後即可接收傳入的 HTTP 事件。Hermes 可能需要重新啟動 Gateway。');
  String get enableWebhooks =>
      _t('Activar webhooks', 'Enable webhooks', '啟用 Webhook');
  String get enableWarningTitle => _t('¿Activar el receptor de webhooks?', 'Enable webhook receiver?', '啟用 Webhook 接收器？');
  String get enableWarningBody => _t('Hermes puede reiniciar el Gateway. Los chats activos podrán reconectarse mientras arranca el receptor.', 'Hermes may restart the Gateway. Active chats can reconnect while the receiver comes online.', 'Hermes 可能會重新啟動 Gateway。接收器啟動期間，現有聊天可以重新連線。');
  String get enable => _t('Activar', 'Enable', '啟用');
  String get disable => _t('Desactivar', 'Disable', '停用');
  String get webhooksEnabledRestarting => _t('Webhooks activados; el Gateway se está reiniciando.', 'Webhooks enabled; the Gateway is restarting.', 'Webhook 已啟用；Gateway 正在重新啟動。');
  String get webhooksEnabled =>
      _t('Webhooks activados.', 'Webhooks enabled.', 'Webhook 已啟用。');
  String get webhooksNeedRestart => _t('Webhooks están activados, pero el Gateway todavía necesita reiniciarse.', 'Webhooks are enabled, but the Gateway still needs a restart.', 'Webhook 已啟用，但 Gateway 仍需要重新啟動。');
  String get addWebhook => _t('Nueva suscripción', 'New subscription', '新增訂閱');
  String get addWebhookBody => _t('Crea una ruta autenticada y copia su secreto de una sola visualización.', 'Create an authenticated route and copy its one-time secret.', '建立需要驗證的路由，並複製其一次性密鑰。');
  String get noWebhooks => _t('Todavía no hay suscripciones webhook.', 'No webhook subscriptions yet.', '尚未有 Webhook 訂閱。');
  String get webhookFormTitle =>
      _t('Nueva suscripción webhook', 'New webhook subscription', '新增 Webhook 訂閱');
  String get description => _t('Descripción', 'Description', '描述');
  String get descriptionHint => _t('Qué hace esta ruta (opcional)', 'What this route does (optional)', '此路由的功能（可選）');
  String get prompt => _t('Instrucciones', 'Prompt', '提示詞');
  String get promptHint => _t('Instrucciones para Hermes cuando llegue el evento (opcional)', 'Instructions for Hermes when this event arrives (optional)', '事件到達時給 Hermes 的指示（可選）');
  String get events => _t('Eventos', 'Events', '事件');
  String get eventsHint => _t('Separados por comas; vacío acepta todos los eventos', 'Comma-separated; empty accepts all events', '以逗號分隔；留空即接受所有事件');
  String get skills => _t('Skills', 'Skills', '技能');
  String get skillsHint => _t('Opcional, nombres de skills separados por comas', 'Optional, comma-separated skill names', '可選，以逗號分隔的技能名稱');
  String get delivery => _t('Entregar a', 'Deliver to', '傳送至');
  String get deliverOnly =>
      _t('Entregar solo el payload', 'Deliver payload only', '僅傳送負載內容');
  String get deliverOnlyHint => _t('Omite la respuesta del agente al entregar en un canal.', 'Skips the agent response for channel delivery.', '透過頻道傳送時略過代理回應。');
  String deliveryLabel(String value) => switch (value) {
    'log' => _t('Solo registro', 'Log only', '僅記錄'),
    'telegram' => 'Telegram',
    'discord' => 'Discord',
    'slack' => 'Slack',
    'email' => _t('Correo', 'Email', '電郵'),
    'github_comment' => _t('Comentario de GitHub', 'GitHub comment', 'GitHub 評論'),
    _ => value,
  };
  String get createWebhook => _t('Crear', 'Create', '建立');
  String get webhookCreated =>
      _t('Suscripción creada.', 'Subscription created.', '訂閱已建立。');
  String get duplicateWebhook => _t('Ya existe un webhook con ese nombre. Elimínalo de forma explícita antes de crear otro.', 'A webhook with that name already exists. Delete it explicitly before creating a replacement.', '已有同名的 Webhook。請先明確刪除它，然後再建立替代項目。');
  String get secretTitle => _t('Copia ahora el secreto del webhook', 'Copy the webhook secret now', '立即複製 Webhook 密鑰');
  String get secretBody => _t('Hermes solo muestra este secreto una vez. Al cerrar este recibo se elimina de la app y no podrá recuperarse aquí.', 'Hermes shows this secret only once. Closing this receipt removes it from the app and it cannot be recovered here.', 'Hermes 只會顯示此密鑰一次。關閉此頁面會將其從應用程式中移除，而且無法在此處復原。');
  String get webhookUrl => _t('URL del webhook', 'Webhook URL', 'Webhook URL');
  String get webhookSecret =>
      _t('Secreto de un solo uso', 'One-time secret', '一次性密鑰');
  String get deleteWebhookTitle =>
      _t('¿Eliminar webhook?', 'Delete webhook?', '刪除 Webhook？');
  String get deleteWebhookBody => _t('Esto elimina la suscripción de forma permanente. Las integraciones existentes dejarán de funcionar.', 'This permanently removes the subscription. Existing integrations will stop working.', '此操作會永久移除訂閱。現有整合將會停止運作。');
  String get webhookDeleted =>
      _t('Webhook eliminado.', 'Webhook deleted.', 'Webhook 已刪除。');
  String webhookSubtitle(String deliver, List<String> events) {
    final eventText = events.isEmpty
        ? (_t('todos los eventos', 'all events', '所有事件'))
        : events.join(', ');
    return '${deliveryLabel(deliver)} · $eventText';
  }

  String get a2aIntro => _t('A2A funciona íntegramente en el host de Hermes. Android solo muestra el estado oficial de la plataforma y no añade otro cliente de protocolo.', 'A2A runs entirely on the Hermes host. Android only reports the official platform status and does not add another protocol client.', 'A2A 完全在 Hermes 主機上運作。Android 僅回報官方平台狀態，不會新增另一個通訊協定用戶端。');
  String get a2aUnavailable => _t('Este servidor no publica su catálogo de plataformas.', 'This server does not publish its platform catalog.', '此伺服器不會發佈其平台目錄。');
  String get a2aNotPublished => _t('Esta instalación de Hermes no publica A2A.', 'A2A is not published by this Hermes installation.', '此 Hermes 安裝並未發佈 A2A。');
  String get a2aTitle => 'A2A';
  String get configured => _t('Configurado', 'Configured', '已設定');
  String get notConfigured => _t('Sin configurar', 'Not configured', '未設定');
  String get running => _t('Gateway en ejecución', 'Gateway running', '閘道運作中');
  String get stopped => _t('Gateway detenido', 'Gateway stopped', '閘道已停止');
  String get active => _t('Activo', 'Enabled', '已啟用');
  String get inactive => _t('Desactivado', 'Disabled', '已停用');
  String a2aState(String state) => switch (state) {
    'connected' => _t('Conectado', 'Connected', '已連線'),
    'connecting' => _t('Conectando', 'Connecting', '連線中'),
    'retrying' => _t('Reintentando', 'Retrying', '重試中'),
    'pending_restart' => _t('Reinicio pendiente', 'Pending restart', '等候重新啟動'),
    'not_configured' => _t('Sin configurar', 'Not configured', '未設定'),
    'gateway_stopped' => _t('Gateway detenido', 'Gateway stopped', '閘道已停止'),
    'startup_failed' => _t('Error al iniciar', 'Startup failed', '啟動失敗'),
    'disconnected' => _t('Desconectado', 'Disconnected', '已斷線'),
    'fatal' => _t('Error fatal', 'Fatal error', '致命錯誤'),
    'disabled' => _t('Desactivado', 'Disabled', '已停用'),
    _ => _t('Estado no disponible', 'Status unavailable', '狀態無法取得'),
  };

  String get unsupported => _t('Esta operación no está disponible en la versión de Hermes conectada.', 'This operation is not available on the connected Hermes version.', '已連線的 Hermes 版本不支援此操作。');
  String get forbidden => _t('Las credenciales actuales del Dashboard no permiten esta operación.', 'The current Dashboard credentials do not allow this operation.', '目前的 Dashboard 憑證不允許執行此操作。');
  String get unavailable => _t('Hermes no pudo completar la operación ahora mismo.', 'Hermes could not complete the operation right now.', 'Hermes 目前未能完成此操作。');
  String get invalidResponse => _t('Hermes devolvió una respuesta de integración no válida.', 'Hermes returned an invalid integration response.', 'Hermes 傳回了無效的整合回應。');
  String get rejected => _t('Hermes rechazó los valores o cambió el estado del servidor.', 'Hermes rejected the values or the server state changed.', 'Hermes 拒絕了這些值，或伺服器狀態已變更。');
}
