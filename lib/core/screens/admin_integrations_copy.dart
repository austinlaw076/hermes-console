import 'package:flutter/widgets.dart';

/// Copy ES/EN tipada de la superficie de integraciones 0.20.
///
/// No se decide por región ni por dispositivo: sigue el locale efectivo de la
/// aplicación igual que el resto de superficies localizadas.
final class AdminIntegrationsCopy {
  final bool _english;

  const AdminIntegrationsCopy._(this._english);

  factory AdminIntegrationsCopy.of(BuildContext context) =>
      AdminIntegrationsCopy._(
        Localizations.localeOf(context).languageCode.toLowerCase() == 'en',
      );

  String get screenTitle =>
      _english ? 'Server integrations' : 'Integraciones del servidor';
  String get entryTitle =>
      _english ? 'Server integrations' : 'Integraciones del servidor';
  String get entryBody => _english
      ? 'Manual MCP, OAuth, webhooks and server-side A2A status.'
      : 'MCP manual, OAuth, webhooks y estado A2A del servidor.';
  String get sectionLabel =>
      _english ? 'Integration sections' : 'Secciones de integraciones';
  String get mcpTab => 'MCP';
  String get webhooksTab => 'Webhooks';
  String get serverTab => _english ? 'Server' : 'Servidor';
  String get readOnly => _english
      ? 'This instance is read-only. You can inspect state, but server changes are disabled.'
      : 'Esta instancia es de solo lectura. Puedes consultar el estado, pero los cambios del servidor están desactivados.';
  String get refresh => _english ? 'Refresh' : 'Actualizar';
  String get retry => _english ? 'Retry' : 'Reintentar';
  String get cancel => _english ? 'Cancel' : 'Cancelar';
  String get close => _english ? 'Close' : 'Cerrar';
  String get done => _english ? 'Done' : 'Listo';
  String get copy => _english ? 'Copy' : 'Copiar';
  String get copied => _english ? 'Copied.' : 'Copiado.';
  String get delete => _english ? 'Delete' : 'Eliminar';
  String get moreOptions => _english ? 'More options' : 'Más opciones';

  String get mcpIntro => _english
      ? 'Add a server with the same individual create contract as Hermes Desktop. Values entered here are sent once and are not saved by the app.'
      : 'Añade un servidor con el mismo contrato de alta individual de Hermes Desktop. Los valores introducidos se envían una vez y la app no los guarda.';
  String get addMcp =>
      _english ? 'Add MCP server manually' : 'Añadir servidor MCP manualmente';
  String get addMcpBody => _english
      ? 'Guided setup for a local command or an HTTP endpoint.'
      : 'Configuración guiada para un comando local o un endpoint HTTP.';
  String get noMcpPut => _english
      ? 'Existing servers are never edited by replacing the full MCP map, because redacted credentials could be lost.'
      : 'Los servidores existentes nunca se editan reemplazando el mapa MCP completo, porque podrían perderse credenciales redactadas.';
  String get manualMcpUnavailable => _english
      ? 'This Hermes version does not publish individual MCP provisioning.'
      : 'Esta versión de Hermes no publica el alta individual de MCP.';
  String get mcpFormTitle => _english ? 'New MCP server' : 'Nuevo servidor MCP';
  String get transport => _english ? 'Transport' : 'Transporte';
  String get stdio => _english ? 'Local command' : 'Comando local';
  String get http => 'HTTP';
  String get name => _english ? 'Name' : 'Nombre';
  String get nameHint => _english ? 'e.g. reports' : 'p. ej. reports';
  String get command => _english ? 'Command' : 'Comando';
  String get commandHint => _english ? 'e.g. npx' : 'p. ej. npx';
  String get arguments => _english ? 'Arguments' : 'Argumentos';
  String get argumentsHint => _english
      ? 'One argument per line. No shell parsing is applied.'
      : 'Un argumento por línea. No se interpreta mediante un shell.';
  String get environment =>
      _english ? 'Environment variables' : 'Variables de entorno';
  String get environmentHint => _english
      ? 'Values remain in memory only until this form is submitted or closed.'
      : 'Los valores solo permanecen en memoria hasta enviar o cerrar este formulario.';
  String get variableName => _english ? 'Variable' : 'Variable';
  String get variableValue => _english ? 'Value' : 'Valor';
  String get addVariable => _english ? 'Add variable' : 'Añadir variable';
  String get removeVariable => _english ? 'Remove variable' : 'Quitar variable';
  String get endpointUrl => _english ? 'MCP URL' : 'URL de MCP';
  String get endpointHint => _english
      ? 'HTTPS, or HTTP only on a private LAN/Tailscale address.'
      : 'HTTPS, o HTTP únicamente en una dirección privada LAN/Tailscale.';
  String get authentication => _english ? 'Authentication' : 'Autenticación';
  String get authNone => _english ? 'None' : 'Ninguna';
  String get authHeader => _english ? 'Bearer header' : 'Cabecera Bearer';
  String get authOauth => _english ? 'OAuth in browser' : 'OAuth en navegador';
  String get bearerToken => _english ? 'Bearer token' : 'Token Bearer';
  String get bearerHint => _english
      ? 'Sent once to Hermes and never stored by the app.'
      : 'Se envía una vez a Hermes y la app nunca lo guarda.';
  String get createMcp => _english ? 'Add server' : 'Añadir servidor';
  String get mcpCreated =>
      _english ? 'MCP server added.' : 'Servidor MCP añadido.';
  String get invalidForm => _english
      ? 'Check the highlighted fields and their examples.'
      : 'Revisa los campos marcados y sus ejemplos.';
  String get incompleteEnvironment => _english
      ? 'Each environment row needs both a variable and a value.'
      : 'Cada fila de entorno necesita una variable y un valor.';
  String get authorize => _english ? 'Authorize OAuth' : 'Autorizar OAuth';

  String get oauthTitle =>
      _english ? 'Authorize MCP server' : 'Autorizar servidor MCP';
  String get oauthBody => _english
      ? 'Hermes receives the callback. This app only opens the authorization page and checks the short-lived flow while this window is visible.'
      : 'Hermes recibe el callback. Esta app solo abre la página de autorización y comprueba el flujo temporal mientras esta ventana está visible.';
  String get openBrowser =>
      _english ? 'Open authorization page' : 'Abrir página de autorización';
  String get openingBrowserFailed => _english
      ? 'Android could not open the authorization page.'
      : 'Android no pudo abrir la página de autorización.';
  String get oauthWaiting =>
      _english ? 'Waiting for authorization…' : 'Esperando autorización…';
  String get oauthApproved =>
      _english ? 'Authorization complete.' : 'Autorización completada.';
  String get oauthError => _english
      ? 'Hermes reported an authorization error.'
      : 'Hermes indicó un error de autorización.';
  String get oauthExpired => _english
      ? 'This authorization flow expired. Start it again.'
      : 'Este flujo de autorización caducó. Inícialo de nuevo.';
  String get oauthUnknown => _english
      ? 'Hermes returned an unknown authorization state.'
      : 'Hermes devolvió un estado de autorización desconocido.';
  String oauthTools(int count) => _english
      ? '$count ${count == 1 ? 'tool' : 'tools'} available'
      : '$count ${count == 1 ? 'herramienta disponible' : 'herramientas disponibles'}';

  String get webhooksIntro => _english
      ? 'Webhooks are an official Hermes gateway platform. Subscriptions hot-reload after the receiver is enabled.'
      : 'Webhooks es una plataforma oficial del Gateway de Hermes. Las suscripciones se recargan en caliente cuando el receptor está activo.';
  String get webhooksUnavailable => _english
      ? 'This Hermes version does not publish webhook administration.'
      : 'Esta versión de Hermes no publica la administración de webhooks.';
  String get webhookLoadFailed => _english
      ? 'Webhooks could not be loaded.'
      : 'No se pudieron cargar los webhooks.';
  String get webhooksDisabled => _english
      ? 'Webhook receiver disabled'
      : 'Receptor de webhooks desactivado';
  String get webhooksDisabledBody => _english
      ? 'Enable it to accept incoming HTTP events. Hermes may need to restart the Gateway.'
      : 'Actívalo para aceptar eventos HTTP entrantes. Hermes puede necesitar reiniciar el Gateway.';
  String get enableWebhooks =>
      _english ? 'Enable webhooks' : 'Activar webhooks';
  String get enableWarningTitle => _english
      ? 'Enable webhook receiver?'
      : '¿Activar el receptor de webhooks?';
  String get enableWarningBody => _english
      ? 'Hermes may restart the Gateway. Active chats can reconnect while the receiver comes online.'
      : 'Hermes puede reiniciar el Gateway. Los chats activos podrán reconectarse mientras arranca el receptor.';
  String get enable => _english ? 'Enable' : 'Activar';
  String get disable => _english ? 'Disable' : 'Desactivar';
  String get webhooksEnabledRestarting => _english
      ? 'Webhooks enabled; the Gateway is restarting.'
      : 'Webhooks activados; el Gateway se está reiniciando.';
  String get webhooksEnabled =>
      _english ? 'Webhooks enabled.' : 'Webhooks activados.';
  String get webhooksNeedRestart => _english
      ? 'Webhooks are enabled, but the Gateway still needs a restart.'
      : 'Webhooks están activados, pero el Gateway todavía necesita reiniciarse.';
  String get addWebhook => _english ? 'New subscription' : 'Nueva suscripción';
  String get addWebhookBody => _english
      ? 'Create an authenticated route and copy its one-time secret.'
      : 'Crea una ruta autenticada y copia su secreto de una sola visualización.';
  String get noWebhooks => _english
      ? 'No webhook subscriptions yet.'
      : 'Todavía no hay suscripciones webhook.';
  String get webhookFormTitle =>
      _english ? 'New webhook subscription' : 'Nueva suscripción webhook';
  String get description => _english ? 'Description' : 'Descripción';
  String get descriptionHint => _english
      ? 'What this route does (optional)'
      : 'Qué hace esta ruta (opcional)';
  String get prompt => _english ? 'Prompt' : 'Instrucciones';
  String get promptHint => _english
      ? 'Instructions for Hermes when this event arrives (optional)'
      : 'Instrucciones para Hermes cuando llegue el evento (opcional)';
  String get events => _english ? 'Events' : 'Eventos';
  String get eventsHint => _english
      ? 'Comma-separated; empty accepts all events'
      : 'Separados por comas; vacío acepta todos los eventos';
  String get skills => _english ? 'Skills' : 'Skills';
  String get skillsHint => _english
      ? 'Optional, comma-separated skill names'
      : 'Opcional, nombres de skills separados por comas';
  String get delivery => _english ? 'Deliver to' : 'Entregar a';
  String get deliverOnly =>
      _english ? 'Deliver payload only' : 'Entregar solo el payload';
  String get deliverOnlyHint => _english
      ? 'Skips the agent response for channel delivery.'
      : 'Omite la respuesta del agente al entregar en un canal.';
  String deliveryLabel(String value) => switch (value) {
    'log' => _english ? 'Log only' : 'Solo registro',
    'telegram' => 'Telegram',
    'discord' => 'Discord',
    'slack' => 'Slack',
    'email' => _english ? 'Email' : 'Correo',
    'github_comment' => _english ? 'GitHub comment' : 'Comentario de GitHub',
    _ => value,
  };
  String get createWebhook => _english ? 'Create' : 'Crear';
  String get webhookCreated =>
      _english ? 'Subscription created.' : 'Suscripción creada.';
  String get duplicateWebhook => _english
      ? 'A webhook with that name already exists. Delete it explicitly before creating a replacement.'
      : 'Ya existe un webhook con ese nombre. Elimínalo de forma explícita antes de crear otro.';
  String get secretTitle => _english
      ? 'Copy the webhook secret now'
      : 'Copia ahora el secreto del webhook';
  String get secretBody => _english
      ? 'Hermes shows this secret only once. Closing this receipt removes it from the app and it cannot be recovered here.'
      : 'Hermes solo muestra este secreto una vez. Al cerrar este recibo se elimina de la app y no podrá recuperarse aquí.';
  String get webhookUrl => _english ? 'Webhook URL' : 'URL del webhook';
  String get webhookSecret =>
      _english ? 'One-time secret' : 'Secreto de un solo uso';
  String get deleteWebhookTitle =>
      _english ? 'Delete webhook?' : '¿Eliminar webhook?';
  String get deleteWebhookBody => _english
      ? 'This permanently removes the subscription. Existing integrations will stop working.'
      : 'Esto elimina la suscripción de forma permanente. Las integraciones existentes dejarán de funcionar.';
  String get webhookDeleted =>
      _english ? 'Webhook deleted.' : 'Webhook eliminado.';
  String webhookSubtitle(String deliver, List<String> events) {
    final eventText = events.isEmpty
        ? (_english ? 'all events' : 'todos los eventos')
        : events.join(', ');
    return '${deliveryLabel(deliver)} · $eventText';
  }

  String get a2aIntro => _english
      ? 'A2A runs entirely on the Hermes host. Android only reports the official platform status and does not add another protocol client.'
      : 'A2A funciona íntegramente en el host de Hermes. Android solo muestra el estado oficial de la plataforma y no añade otro cliente de protocolo.';
  String get a2aUnavailable => _english
      ? 'This server does not publish its platform catalog.'
      : 'Este servidor no publica su catálogo de plataformas.';
  String get a2aNotPublished => _english
      ? 'A2A is not published by this Hermes installation.'
      : 'Esta instalación de Hermes no publica A2A.';
  String get a2aTitle => 'A2A';
  String get configured => _english ? 'Configured' : 'Configurado';
  String get notConfigured => _english ? 'Not configured' : 'Sin configurar';
  String get running => _english ? 'Gateway running' : 'Gateway en ejecución';
  String get stopped => _english ? 'Gateway stopped' : 'Gateway detenido';
  String get active => _english ? 'Enabled' : 'Activo';
  String get inactive => _english ? 'Disabled' : 'Desactivado';
  String a2aState(String state) => switch (state) {
    'connected' => _english ? 'Connected' : 'Conectado',
    'connecting' => _english ? 'Connecting' : 'Conectando',
    'retrying' => _english ? 'Retrying' : 'Reintentando',
    'pending_restart' => _english ? 'Pending restart' : 'Reinicio pendiente',
    'not_configured' => _english ? 'Not configured' : 'Sin configurar',
    'gateway_stopped' => _english ? 'Gateway stopped' : 'Gateway detenido',
    'startup_failed' => _english ? 'Startup failed' : 'Error al iniciar',
    'disconnected' => _english ? 'Disconnected' : 'Desconectado',
    'fatal' => _english ? 'Fatal error' : 'Error fatal',
    'disabled' => _english ? 'Disabled' : 'Desactivado',
    _ => _english ? 'Status unavailable' : 'Estado no disponible',
  };

  String get unsupported => _english
      ? 'This operation is not available on the connected Hermes version.'
      : 'Esta operación no está disponible en la versión de Hermes conectada.';
  String get forbidden => _english
      ? 'The current Dashboard credentials do not allow this operation.'
      : 'Las credenciales actuales del Dashboard no permiten esta operación.';
  String get unavailable => _english
      ? 'Hermes could not complete the operation right now.'
      : 'Hermes no pudo completar la operación ahora mismo.';
  String get invalidResponse => _english
      ? 'Hermes returned an invalid integration response.'
      : 'Hermes devolvió una respuesta de integración no válida.';
  String get rejected => _english
      ? 'Hermes rejected the values or the server state changed.'
      : 'Hermes rechazó los valores o cambió el estado del servidor.';
}
