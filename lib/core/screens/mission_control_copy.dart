import 'package:flutter/widgets.dart';

import '../l10n/app_locale_resolve.dart';

final class MissionControlCopy {
  final AppLocaleKind _kind;

  const MissionControlCopy._(this._kind);

  factory MissionControlCopy.of(BuildContext context) => MissionControlCopy._(
    AppLocaleResolve.fromLocale(Localizations.localeOf(context)),
  );

  String _t(String es, String en, [String? zh]) =>
      AppLocaleResolve.pick(_kind, es: es, en: en, zh: zh);

  String get title => 'Bots';
  String get allAgents => _t('Todos los agentes', 'All agents', '所有代理程式');
  String get chooseWorkspace =>
      _t('Elegir espacio de trabajo', 'Choose workspace', '選擇工作區');
  String get workspaces => _t('Espacios de trabajo', 'Workspaces', '工作區');
  String workspaceAgentCount(int count) => AppLocaleResolve.pick(
    _kind,
    es: '$count ${count == 1 ? 'agente' : 'agentes'}',
    en: '$count ${count == 1 ? 'agent' : 'agents'}',
    zh: '$count 個代理程式',
  );
  String get createOrganization =>
      _t('Crear espacio de trabajo', 'Create workspace', '建立工作區');
  String get editOrganization =>
      _t('Editar espacio de trabajo', 'Edit workspace', '編輯工作區');
  String get organizationName =>
      _t('Nombre del espacio de trabajo', 'Workspace name', '工作區名稱');
  String get organizationHint =>
      _t('p. ej. Homelab', 'e.g. Homelab', '例如：Homelab');
  String get chooseProfiles =>
      _t('Selecciona profiles', 'Choose profiles', '選擇設定檔');
  String get save => _t('Guardar', 'Save', '儲存');
  String get cancel => _t('Cancelar', 'Cancel', '取消');
  String get delete => _t('Eliminar', 'Delete', '刪除');
  String get deleteOrganizationTitle =>
      _t('¿Eliminar espacio de trabajo?', 'Delete workspace?', '刪除工作區？');
  String get deleteOrganizationBody => _t(
    'Solo se elimina este espacio local. Los profiles de Hermes no cambian.',
    'Only this local workspace is removed. Hermes profiles are not changed.',
    '只會移除這個本機工作區，Hermes 設定檔不會變更。',
  );
  String get loading =>
      _t('Leyendo el equipo…', 'Reading team state…', '正在讀取團隊狀態…');
  String get retry => _t('Reintentar', 'Retry', '重試');
  String get refresh => _t('Actualizar', 'Refresh', '重新整理');
  String get overview => _t('Resumen', 'Overview', '概覽');
  String get tasks => _t('Tareas', 'Tasks', '工作');
  String get activity => _t('Actividad', 'Activity', '活動');
  String get recentActivity =>
      _t('Actividad reciente', 'Recent activity', '最近活動');
  String get showAllActivity =>
      _t('Ver toda la actividad', 'Show all activity', '顯示所有活動');
  String get showLess => _t('Mostrar menos', 'Show less', '顯示較少');
  String get bots => 'Bots';
  String botCount(int count) => AppLocaleResolve.pick(
    _kind,
    es: '$count bots',
    en: '$count ${count == 1 ? 'bot' : 'bots'}',
    zh: '$count 個 bot',
  );
  String get rooms => _t('Salas', 'Rooms', '房間');
  String get work => _t('Trabajo', 'Work', '工作');
  String get globalWorkTray =>
      _t('Otros pendientes', 'Other pending work', '其他待處理工作');

  String get addToMissionControl =>
      _t('Añadir a Bots', 'Add to Bots', '加入 Bots');
  String get createAgent => _t('Nuevo agente', 'New agent', '新增代理程式');
  String get createAgentDescription => _t(
    'Crea un profile real de Hermes con su modelo y capacidades.',
    'Create a real Hermes profile with its own model and capabilities.',
    '建立一個具備專屬模型及能力的真正 Hermes 個人檔案。',
  );
  String get createRoom => _t('Crear sala', 'Create room', '建立房間');
  String get createRoomDescription => _t(
    'Elige entre 2 y 6 bots y abre su sala de coordinación.',
    'Choose 2–6 bots and open their coordination room.',
    '選擇 2–6 個 bots，開啟它們的協調房間。',
  );
  String get startTeam => _t('Crear tu equipo', 'Build your team', '建立你的團隊');
  String get newAgent => _t('Nuevo agente', 'New agent', '新增代理程式');
  String get botChat => 'Bot Chat';
  String get botDetails => _t('Detalles del bot', 'Bot details', 'Bot 詳情');
  String get noBots => _t(
    'Un bot es un compañero con nombre propio, memoria, skills y chat propios. Crea el primero para empezar.',
    'A bot is a named teammate with its own memory, skills and chat. Create the first one to get started.',
    'Bot 是一位有名稱的隊友，擁有自己的記憶、技能和聊天功能。建立第一個 Bot 以開始使用。',
  );
  String get botNeedsYou => _t('te necesita', 'needs you', '需要你');
  String get needMoreBots => _t(
    'Crea otro bot antes de abrir una sala.',
    'Create another bot before opening a room.',
    '開啟房間前，請先建立另一個 Bot。',
  );
  String get needTwoAgents => _t(
    'Crea al menos dos bots antes de abrir una sala de equipo.',
    'Create at least two bots before opening a team room.',
    '開啟團隊房間前，請至少建立兩個 Bot。',
  );
  String get searchAgents => _t('Buscar bots', 'Search bots', '搜尋 Bots');
  String get clearSearch => _t('Borrar búsqueda', 'Clear search', '清除搜尋');
  String get activeNow => _t('Activos ahora', 'Active now', '目前活躍');
  String get otherBots => _t('Otros bots', 'Other bots', '其他 Bots');
  String get allBots => _t('Todos los bots', 'All bots', '所有 Bots');
  String get searchResults => _t('Resultados', 'Results', '結果');
  String showHiddenBots(int count) =>
      _t('Mostrar ocultos ($count)', 'Show hidden ($count)', '顯示隱藏項目 ($count)');
  String get hideHiddenBots => _t('Ocultar ocultos', 'Hide hidden', '隱藏隱藏項目');
  String get pinBot => _t('Fijar arriba', 'Pin to top', '釘選到頂部');
  String get unpinBot => _t('Dejar de fijar', 'Unpin', '取消釘選');
  String get hideBot => _t('Ocultar de Bots', 'Hide from Bots', '從 Bots 隱藏');
  String get showBot => _t('Mostrar en Bots', 'Show in Bots', '在 Bots 顯示');
  String get botRosterUpdateFailed => _t(
    'Hermes no pudo actualizar este bot.',
    'Hermes did not update this bot.',
    'Hermes 沒有更新此 Bot。',
  );
  String get noMatchingAgents =>
      _t('No hay bots que coincidan', 'No matching bots', '沒有符合的 Bots');
  String get roomCoordinator => _t('Coordinador', 'Coordinator', '協調員');
  String get roomSelectionHint =>
      _t('Elige de 2 a 6 bots.', 'Choose 2 to 6 bots.', '選擇 2 至 6 個 Bots。');
  String roomSelectionCount(int count) =>
      _t('$count de 6 seleccionados', '$count of 6 selected', '已選擇 $count/6');
  String agentCreated(String name) => _t(
    'Bot @$name creado. Añádelo a una sala cuando quieras.',
    'Bot @$name created. Add it to a room when you are ready.',
    'Bot @$name 已建立。準備好後，將其加入房間。',
  );
  String get editRoom => _t('Editar sala', 'Edit room', '編輯房間');
  String get roomName => _t('Nombre de la sala', 'Room name', '房間名稱');
  String get roomHint => _t('p. ej. homelab', 'e.g. homelab', '例如 homelab');
  String get roomPurpose => _t('Objetivo', 'Purpose', '用途');
  String get roomPurposeHint => _t(
    'p. ej. Mantener producción estable',
    'e.g. Keep production stable',
    '例如保持正式環境穩定',
  );
  String get roomNameInvalid => _t(
    'Escribe un nombre después del símbolo #.',
    'Enter a name after the # symbol.',
    '請在 # 符號後輸入名稱。',
  );
  String get roomManager => _t('Manager de la sala', 'Room manager', '房間管理員');
  String get roomMembers => _t('Miembros de la sala', 'Room members', '房間成員');
  String get roomCoordinatorShort => _t('Coordinador', 'Coordinator', '協調員');
  String get roomTeam => _t('Equipo', 'Team', '團隊');
  String get roomSummary => _t('Resumen', 'Summary', '摘要');
  String get roomTasks => _t('Tareas de la sala', 'Room tasks', '房間任務');
  String get roomActivity =>
      _t('Actividad de la sala', 'Room activity', '房間活動');
  String get roomReady => _t('Preparada', 'Ready', '準備就緒');
  String get roomActive => _t('Activa', 'Active', '進行中');
  String get roomReview => _t('En revisión', 'In review', '審核中');
  String get roomBlocked => _t('Bloqueada', 'Blocked', '受阻');
  String get roomNoPurpose =>
      _t('Sin objetivo definido', 'No goal defined yet', '尚未定義目標');
  String get roomNoActivity => _t(
    'Todavía no hay actividad publicada para esta sala.',
    'No activity has been published for this room yet.',
    '此房間尚未發佈任何活動。',
  );
  String talkToCoordinator(String profile) =>
      _t('Hablar con @$profile', 'Talk to @$profile', '與 @$profile 對話');
  String get roomNoLinkedWork =>
      _t('Sin trabajo enlazado todavía', 'No linked work yet', '尚未有已連結的工作');
  String roomMemberCount(int count) => AppLocaleResolve.pick(
    _kind,
    es: '$count ${count == 1 ? 'miembro' : 'miembros'}',
    en: '$count ${count == 1 ? 'member' : 'members'}',
    zh: '$count 位成員',
  );
  String roomHomeSummary(int agents, int rooms) => AppLocaleResolve.pick(
    _kind,
    es: '$agents ${agents == 1 ? 'agente' : 'agentes'} · $rooms ${rooms == 1 ? 'sala' : 'salas'}',
    en: '$agents ${agents == 1 ? 'agent' : 'agents'} · $rooms ${rooms == 1 ? 'room' : 'rooms'}',
    zh: '$agents 個代理程式 · $rooms 個房間',
  );
  String roomCount(int count) => AppLocaleResolve.pick(
    _kind,
    es: '$count ${count == 1 ? 'sala' : 'salas'}',
    en: '$count ${count == 1 ? 'room' : 'rooms'}',
    zh: '$count 個房間',
  );
  String attentionSummary(int approvals, int blocked) => AppLocaleResolve.pick(
    _kind,
    es: '$approvals ${approvals == 1 ? 'aprobación' : 'aprobaciones'} · $blocked bloqueados',
    en: '$approvals ${approvals == 1 ? 'approval' : 'approvals'} · $blocked blocked',
    zh: '$approvals 項審批 · $blocked 項已封鎖',
  );
  String get noRooms => _t(
    'Crea una sala para empezar a hablar con tu equipo.',
    'Create a room to start talking with your team.',
    '建立房間，開始與團隊交流。',
  );
  String get openRoom => _t('Abrir sala', 'Open room', '開啟房間');
  String get linkedWork => _t('tareas enlazadas', 'linked tasks', '已連結的任務');
  String unavailableTaskLink(String boardId, String taskId) => _t(
    'Tablero $boardId · $taskId · no cargada',
    'Board $boardId · $taskId · not loaded',
    '看板 $boardId · $taskId · 未載入',
  );
  String get unavailableLinkedWork => _t(
    'Trabajo enlazado no disponible',
    'Linked work unavailable',
    '已連結的工作無法使用',
  );
  String get roomContract => _t(
    'El coordinador recibe tus mensajes y reparte el trabajo confirmado al equipo.',
    'The coordinator receives your messages and assigns confirmed work to the team.',
    '協調員會接收你的訊息，並將已確認的工作分配給團隊。',
  );
  String get deleteRoomTitle => _t('¿Eliminar sala?', 'Delete room?', '刪除房間？');
  String get deleteRoomBody => _t(
    'Solo se elimina esta sala. Sus chats y tareas se conservan.',
    'Only this room is removed. Its chats and tasks are kept.',
    '只會移除此房間。其聊天內容和任務會保留。',
  );
  String get roomOperationPending => _t(
    'Finaliza o recupera la tarea pendiente antes de editar o eliminar esta sala.',
    'Finish or recover the pending Room task before editing or deleting this Room.',
    '編輯或刪除此房間前，請先完成或復原待處理的房間任務。',
  );
  String get needsYou => _t('Necesita tu atención', 'Needs you', '需要你處理');
  String get usage => _t('Uso', 'Usage', '使用量');
  String get profilesUnavailable => _t(
    'Esta instalación de Hermes no publica profiles.',
    'This Hermes installation does not publish profiles.',
    '此 Hermes 安裝並不會發佈個人檔案。',
  );
  String get roomsBrowseOnly => _t(
    'Hermes no puede verificar el equipo ahora. Las salas guardadas siguen visibles en modo consulta.',
    'Hermes cannot verify the team right now. Saved rooms remain visible in browse-only mode.',
    'Hermes 目前無法驗證團隊。已儲存的房間仍會以僅供瀏覽模式顯示。',
  );
  String get offline => _t(
    'Hermes no está disponible. Los datos existentes del equipo siguen visibles.',
    'Hermes is unavailable. Existing team data remains visible.',
    'Hermes 無法使用。現有團隊資料仍會顯示。',
  );
  String get staleData => _t(
    'Algunos datos del equipo pueden estar desactualizados.',
    'Some team data may be out of date.',
    '部分團隊資料可能已過時。',
  );
  String get noProfiles => _t(
    'No hay bots disponibles aquí.',
    'No bots are available here.',
    '這裏沒有可用的 Bots。',
  );
  String get noTasks => _t(
    'Todavía no hay tareas aquí.',
    'There are no tasks here yet.',
    '這裡暫時沒有任務。',
  );
  String get kanbanUnavailable => _t(
    'El tablero de tareas no está disponible en esta instalación de Hermes.',
    'The task board is not available on this Hermes installation.',
    '此 Hermes 安裝版本不提供任務看板。',
  );
  String get noActivity => _t(
    'Hermes no ha publicado actividad reciente para este ámbito.',
    'Hermes has not published recent activity for this scope.',
    'Hermes 尚未發佈此範圍的近期活動。',
  );
  String get noApprovals => _t(
    'No hay aprobaciones observadas pendientes.',
    'No observed approvals need attention.',
    '沒有需要跟進的已觀察審批。',
  );
  String get openChat => _t('Abrir chat', 'Open chat', '開啟聊天');
  String get review => _t('Revisar', 'Review', '檢視');
  String get openKanban => _t('Tablero completo', 'Full task board', '完整任務看板');
  String get manageProfiles => _t('Gestionar bots', 'Manage bots', '管理 Bots');
  String get editProfile => _t('Editar profile', 'Edit profile', '編輯個人資料');
  String get routines => _t('Rutinas', 'Routines', '常規');
  String get memory => _t('Memoria', 'Memory', '記憶');
  String get skills => 'Skills';
  String get soul => 'SOUL';
  String get recentSessions =>
      _t('Sesiones recientes', 'Recent sessions', '最近工作階段');
  String get modelUnavailable =>
      _t('Modelo no publicado', 'Model not published', '模型未有發佈');
  String get costUnavailable =>
      _t('Coste no publicado', 'Cost not published', '費用未有發佈');
  String get partialCost =>
      _t('Cobertura parcial', 'Partial coverage', '部分涵蓋範圍');
  String get staleProfiles => _t(
    'Algunos profiles guardados ya no existen. Edita la organización para actualizarla.',
    'Some saved profiles no longer exist. Edit the organization to update it.',
    '部分已儲存的設定檔已不存在。編輯組織以更新。',
  );
  String unattributedSessions(int count) => AppLocaleResolve.pick(
    _kind,
    es: '$count ${count == 1 ? 'sesión no publicó' : 'sesiones no publicaron'} su profile propietario. Solo se incluyen en el uso global.',
    en: '$count session${count == 1 ? '' : 's'} did not publish a profile owner. They are included only in overall usage.',
    zh: '$count 個工作階段未公佈 profile 擁有者，只計入整體使用量。',
  );
  String get working => _t('trabajando', 'working', '工作中');
  String get approvals => _t('aprobaciones', 'approvals', '審批');
  String get blocked => _t('bloqueados', 'blocked', '已封鎖');
  String get tokens => _t('tokens', 'tokens', 'tokens');
  String get input => 'input';
  String get output => 'output';
  String get cached => _t('caché', 'cached', '已快取');
  String get reasoning => 'reasoning';
  String get unknown => _t('Desconocido', 'Unknown', '未知');
  String get profileLabel => 'Profile';
  String get modelLabel => _t('Modelo', 'Model', '模型');
  String get managerLabel => 'Manager';
  String get tokensUnavailable =>
      _t('Tokens no publicados', 'Tokens not published', 'tokens 未發佈');

  // Editor del bot (identidad visible del profile: nombre, cara y sprite).
  String get editBotTitle => _t('Editar bot', 'Edit bot', '編輯 Bot');
  String get botDisplayName => _t('Nombre visible', 'Display name', '顯示名稱');
  String get botDisplayNameHint =>
      _t('p. ej. Investigador', 'e.g. Researcher', '例如：Researcher');
  String get botShapeLabel => _t('Forma', 'Shape', '形狀');
  String get botColorLabel => _t('Color', 'Color', '顏色');
  String get botFaceFallbackHint => _t(
    'La forma y el color solo se usan si el bot no tiene sprite.',
    'Shape and color are only used when the bot has no sprite.',
    '當 Bot 沒有 sprite 時，才會使用形狀和顏色。',
  );
  String get botSpriteLabel => 'Sprite';
  String get botSpriteHint => _t(
    'El sprite se convierte en la imagen de este bot.',
    'The sprite becomes this bot\'s picture.',
    'Sprite 會成為此 bot 的圖片。',
  );
  String get botSpriteNone => _t('Sin sprite', 'No sprite', '沒有 Sprite');
  String get botSpriteSearchHint =>
      _t('Buscar sprites…', 'Search sprites…', '搜尋 Sprite…');
  String get botSpriteEmpty => _t(
    'No hay sprites disponibles.',
    'No sprites available.',
    '沒有可用的 Sprite。',
  );
  String get botSpriteUnsupported => _t(
    'Esta instalación de Hermes no admite sprites por profile.',
    'This Hermes installation does not support profile sprites.',
    '此 Hermes 安裝不支援個人檔案 Sprite。',
  );
  String get botEditorSaved => _t('Bot actualizado', 'Bot updated', 'Bot 已更新');
  String get botEditorSaveFailed => _t(
    'Hermes no aplicó los cambios.',
    'Hermes did not apply the changes.',
    'Hermes 沒有套用變更。',
  );

  // Creación de bots (paridad con CreateAgentDialog de Hermes Desktop).
  String get createAgentSubtitle => _t(
    'Un compañero con nombre propio, memoria, skills y chat propios. Puede escribir a tus otros agentes.',
    'A named teammate with its own memory, skills, and chat. It can message your other agents.',
    '一個具名隊友，擁有自己的記憶、技能和聊天功能。它可以向你的其他代理程式傳送訊息。',
  );
  String get agentNameLabel => _t('Nombre', 'Name', '名稱');
  String get agentNameHint => 'inbox-triage';
  String get agentNameInvalid => _t(
    'Usa minúsculas, números, guiones y guiones bajos.',
    'Use lowercase letters, numbers, dashes and underscores.',
    '請使用小寫字母、數字、連字號和底線。',
  );
  String get agentNameTaken => _t(
    'Ya existe un agente con este nombre.',
    'An agent with this name already exists.',
    '已經存在使用此名稱的代理程式。',
  );
  String get agentTitleLabel => _t('Título', 'Title', '標題');
  String get agentTitleHint => 'Inbox Triage';
  String get agentDescriptionLabel => _t('Descripción', 'Description', '描述');
  String get agentDescriptionHint => _t(
    '¿En qué debería ayudar este bot?',
    'What should this bot help with?',
    '此 bot 應該協助處理甚麼？',
  );
  String get modelInherited => _t(
    'Heredado del profile de arranque',
    'Inherited from the launch profile',
    '繼承自啟動設定檔',
  );
  String get modelPickerTitle => _t('Elegir modelo', 'Choose model', '選擇模型');
  String get modelCatalogEmpty => _t(
    'Esta instalación de Hermes no publicó un catálogo de modelos. Escribe proveedor y modelo a mano.',
    'This Hermes installation did not publish a model catalog. Enter provider and model manually.',
    '此 Hermes 安裝沒有發布模型目錄。請手動輸入供應商及模型。',
  );
  String get providerLabel => _t('Proveedor', 'Provider', '供應商');
  String get advanced => _t('Avanzado', 'Advanced', '進階');
  String get cloneFromLabel => _t('Clonar de', 'Clone from profile', '從設定檔複製');
  String get cloneFresh => _t(
    'Profile nuevo (skills incluidas)',
    'Fresh profile (bundled skills)',
    '全新設定檔（內置技能）',
  );
  String get shareAuthLabel => _t(
    'Compartir claves y cuentas con el profile principal',
    'Share keys & accounts with the main profile',
    '與主要設定檔共用金鑰及帳戶',
  );
  String get shareAuthHint => _t(
    'Suscripciones, logins OAuth y API keys quedan compartidos (no copiados), así que los refrescos de token nunca se invalidan entre sí. Desmárcalo para una copia aislada.',
    'Subscriptions, OAuth logins, and API keys stay shared (not copied), so token refreshes never invalidate each other. Uncheck for an isolated snapshot copy.',
    '訂閱、OAuth 登入及 API 金鑰會保持共用（不會複製），因此權杖重新整理不會令彼此失效。取消剔選即可建立獨立的快照副本。',
  );
  String get noSkillsLabel => _t(
    'Crear vacío (sin skills incluidas)',
    'Create empty (skip bundled skills)',
    '建立空白（略過內置技能）',
  );
  String get soulOptionalLabel =>
      _t('SOUL.md (opcional)', 'SOUL.md (optional)', 'SOUL.md（可選）');
  String get soulOptionalHint => _t(
    'Déjalo en blanco para autogenerarla a partir de nombre, título y descripción.',
    'Leave blank to auto-generate from name/title/description.',
    '留空即可根據名稱／標題／描述自動產生。',
  );
  String get skillsLoading =>
      _t('Cargando skills…', 'Loading skills…', '正在載入技能…');
  String get skillsUnavailable => _t(
    'El catálogo de skills necesita un gateway más reciente (actualiza Hermes y reinícialo).',
    'The skill catalog needs a newer gateway (update Hermes and restart it).',
    '技能目錄需要較新的閘道（請更新 Hermes 並重新啟動）。',
  );
  String skillsFromSource(String source) => _t(
    'Catálogo de $source: las skills desmarcadas se desactivan tras la creación.',
    'Catalog from $source — unchecked skills are disabled after creation.',
    '目錄來源：$source — 未剔選的技能會在建立後停用。',
  );
  String get createAgentSubmit => _t('Crear agente', 'Create agent', '建立代理人');
  String createAgentError(String detail) => _t(
    'No se pudo crear el agente: $detail',
    'Could not create the agent: $detail',
    '無法建立代理程式：$detail',
  );

  String status(String value) => switch (value) {
    'idle' => _t('Inactivo', 'Idle', '閒置'),
    'thinking' => _t('Pensando', 'Thinking', '思考中'),
    'working' => _t('Trabajando', 'Working', '工作中'),
    'responding' => _t('Respondiendo', 'Responding', '回應中'),
    'blocked' => _t('Bloqueado', 'Blocked', '受阻'),
    'approvalRequired' => _t(
      'Aprobación requerida',
      'Approval required',
      '需要批准',
    ),
    'error' => 'Error',
    _ => unknown,
  };

  String activityLabel(String value) => switch (value) {
    'sessionUpdated' => _t('Sesión activa', 'Session active', '工作階段進行中'),
    'taskCreated' => _t('Tarea creada', 'Task created', '任務已建立'),
    'taskStarted' => _t('Tarea iniciada', 'Task started', '任務已開始'),
    'taskCompleted' => _t('Tarea completada', 'Task completed', '任務已完成'),
    'taskBlocked' => _t('Tarea bloqueada', 'Task blocked', '任務受阻'),
    _ => value,
  };

  String taskStatus(String value) => switch (value) {
    'ready' => _t('lista', 'ready', '就緒'),
    'running' => _t('en curso', 'running', '執行中'),
    'blocked' => _t('bloqueada', 'blocked', '已封鎖'),
    'review' => _t('en revisión', 'review', '審核中'),
    'done' => _t('completada', 'done', '完成'),
    'scheduled' => _t('programada', 'scheduled', '已排程'),
    'todo' => _t('pendiente', 'to do', '待辦'),
    'triage' => _t('triaje', 'triage', '分流'),
    _ => value,
  };
}
