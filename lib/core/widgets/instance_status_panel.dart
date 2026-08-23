// Estado unificado de la instancia (Gateway / Dashboard / Mobile Bridge /
// Agente local / Notificaciones), presentado como hoja inferior que se abre
// al tocar la línea de estado del app bar de Home.
//
// Diseño deliberado: sondeo SOLO al abrir + botón ↻; cacheado en el estado de
// la hoja; NUNCA en bucle. Sondear el bridge de forma agresiva puede despertar
// Termux en instancias locales y dar falsos "offline".
//
// Reutiliza los caminos ya probados: ApiClient.healthCheck (gateway),
// GET /api/status (dashboard / agente local), BridgeManager.probe (bridge),
// NotificationService.permissionGranted (notificaciones). No promete
// "conectado" si solo respondió otra pieza: cada fila refleja su propio sondeo.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../l10n/app_localizations.dart';
import '../../main.dart';
import '../screens/local_instance_control_screen.dart';
import '../services/bridge_manager.dart';
import '../services/connection_manager.dart';
import '../services/notifications/notification_service.dart';
import '../theme/app_theme.dart';
import '../utils/transport_privacy.dart';
import 'hermes_premium_ui.dart';

/// Abre la hoja inferior de estado para [connection]. Resuelve los servicios
/// desde el [HermesAppState] del contexto que la invoca (no desde el árbol del
/// modal), para no depender de dónde se monte la hoja.
Future<void> showInstanceStatusSheet(
  BuildContext context,
  SavedConnection connection,
) {
  final appState = context.findAncestorStateOfType<HermesAppState>();
  return showHermesFloatingSurface<void>(
    context: context,
    surfaceKey: const ValueKey('instance-status-surface'),
    maxWidth: 520,
    maxHeightFactor: 0.84,
    builder: (_) => _InstanceStatusSheet(
      connection: connection,
      bridgeManager: appState?.bridgeManager,
      notifications: appState?.notifications,
      connManager: appState?.connManager,
    ),
  );
}

enum _Health { ok, warn, bad, unknown }

enum _LabelKind { gateway, dashboard, bridge, localAgent, notifications }

enum _DetailKind {
  connected,
  offline,
  notEnabled,
  needsToken,
  running,
  stopped,
  enabled,
  disabled,
}

class _RawRow {
  final _LabelKind label;
  final _Health health;
  final _DetailKind detail;
  const _RawRow(this.label, this.health, this.detail);
}

class _InstanceStatusSheet extends StatefulWidget {
  final SavedConnection connection;
  final BridgeManager? bridgeManager;
  final NotificationService? notifications;
  final ConnectionManager? connManager;

  const _InstanceStatusSheet({
    required this.connection,
    required this.bridgeManager,
    required this.notifications,
    required this.connManager,
  });

  @override
  State<_InstanceStatusSheet> createState() => _InstanceStatusSheetState();
}

class _InstanceStatusSheetState extends State<_InstanceStatusSheet> {
  bool _loading = false;
  bool _provisioning = false; // habilitando el bridge (tryProvision)
  bool _provisionFailed = false;
  List<_RawRow>? _rows;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  /// Habilita el bridge bajo demanda: pide el token al gateway/dashboard
  /// (`tryProvision`, best-effort) y vuelve a sondear. Cierra el caso de la
  /// provisión silenciosa que falla tras instalar la instancia local: el
  /// usuario lo ve "no habilitado" y lo arregla con un toque, sin pasos
  /// manuales ni tocar el flujo de instalación.
  Future<void> _provisionBridge() async {
    final mgr = widget.bridgeManager;
    if (mgr == null || _provisioning || _loading) return;
    setState(() {
      _provisioning = true;
      _provisionFailed = false;
    });
    bool ok;
    try {
      ok = await mgr.tryProvision(widget.connection.id);
    } catch (e) {
      debugPrint(
        '[instance-status] excepción silenciada (fallback: ok = false): $e',
      );
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _provisioning = false;
      _provisionFailed = !ok;
    });
    await _probe();
  }

  /// Cuando la provisión falla en local, la causa suele ser token o proceso
  /// caído: reiniciar el agente local re-despliega y re-arranca el bridge con
  /// la key canónica. Cierra la hoja y abre el control de la instancia local.
  void _openLocalControl() {
    final mgr = widget.connManager;
    if (mgr == null) return;
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute(
        builder: (_) => LocalInstanceControlScreen(
          connection: widget.connection,
          connManager: mgr,
        ),
      ),
    );
  }

  Future<void> _probe() async {
    if (_loading) return;
    setState(() => _loading = true);

    final conn = widget.connection;
    final isLocal = conn.kind == InstanceKind.localhost;
    final rows = <_RawRow>[];

    // 1. Gateway / Agente local ────────────────────────────────────────────
    if (isLocal) {
      final ok = await _reachable('${conn.effectiveDashboardUrl}/api/status');
      rows.add(
        _RawRow(
          _LabelKind.localAgent,
          ok ? _Health.ok : _Health.bad,
          ok ? _DetailKind.running : _DetailKind.stopped,
        ),
      );
    } else {
      // El panel solo indica "¿está vivo el servidor?", NO valida el token (de
      // eso se encarga el alta de la conexión). Antes usaba `healthCheck()`
      // estricto, que exige `/health`==200 Y `/api/sessions`==200; pero el
      // dashboard responde **302** en `/health` (redirección a login), así que
      // una instancia remota perfectamente viva —con el chat funcionando— salía
      // como "offline". Un `/health` alcanzable (cualquier código < 500, incluido
      // 302/401) significa que el servidor está ahí.
      final gw = await _reachable('${conn.gatewayUrl}/health');
      rows.add(
        _RawRow(
          _LabelKind.gateway,
          gw ? _Health.ok : _Health.bad,
          gw ? _DetailKind.connected : _DetailKind.offline,
        ),
      );

      final dash = await _reachable('${conn.effectiveDashboardUrl}/api/status');
      rows.add(
        _RawRow(
          _LabelKind.dashboard,
          dash ? _Health.ok : _Health.bad,
          dash ? _DetailKind.connected : _DetailKind.offline,
        ),
      );
    }

    // 2. Mobile Bridge ─────────────────────────────────────────────────────
    if (widget.bridgeManager != null) {
      // El Mobile Bridge es OPCIONAL y en instancias remotas (p.ej. la .40) casi
      // nunca está desplegado: el puerto 9131 puede estar cerrado y, si el
      // firewall DESCARTA los paquetes en vez de rechazarlos, el sondeo se cuelga
      // hasta el timeout del socket. Como las filas se pintan en un único setState
      // al final, ese cuelgue dejaba TODO el panel en "Comprobando…" sin mostrar
      // nada. Acotamos el sondeo para que el panel siempre se renderice.
      final st = await widget.bridgeManager!
          .probe(conn.id)
          .timeout(
            const Duration(seconds: 6),
            onTimeout: () => BridgeState.unknown,
          );
      final (_Health h, _DetailKind d) = switch (st.status) {
        BridgeStatus.connected => (_Health.ok, _DetailKind.connected),
        BridgeStatus.needsToken ||
        BridgeStatus.authFailed => (_Health.warn, _DetailKind.needsToken),
        _ => (_Health.unknown, _DetailKind.notEnabled),
      };
      rows.add(_RawRow(_LabelKind.bridge, h, d));
    }

    // 3. Notificaciones ────────────────────────────────────────────────────
    if (widget.notifications != null) {
      final notif = await widget.notifications!.permissionGranted();
      rows.add(
        _RawRow(
          _LabelKind.notifications,
          notif ? _Health.ok : _Health.warn,
          notif ? _DetailKind.enabled : _DetailKind.disabled,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  /// GET de solo lectura: responde (cualquier código) ⇒ alcanzable.
  Future<bool> _reachable(String url) async {
    final client = http.Client();
    try {
      final safeUrl = TransportPrivacy.requireAllowed(url);
      final res = await client
          .get(Uri.parse(safeUrl))
          .timeout(const Duration(seconds: 6));
      return res.statusCode >= 200 && res.statusCode < 500;
    } catch (e) {
      debugPrint('[instance-status] excepción silenciada (se asume false): $e');
      return false;
    } finally {
      client.close();
    }
  }

  String _labelText(_LabelKind k, Strings s) => switch (k) {
    _LabelKind.gateway => 'Gateway',
    _LabelKind.dashboard => 'Dashboard',
    _LabelKind.bridge => 'Mobile Bridge',
    _LabelKind.localAgent => s.statusLocalAgent,
    _LabelKind.notifications => s.statusNotifications,
  };

  String _detailText(_DetailKind k, Strings s) => switch (k) {
    _DetailKind.connected => s.statusConnected,
    _DetailKind.offline => s.statusOffline,
    _DetailKind.notEnabled => s.statusNotEnabled,
    _DetailKind.needsToken => s.statusNeedsToken,
    _DetailKind.running => s.statusRunning,
    _DetailKind.stopped => s.statusStopped,
    _DetailKind.enabled => s.statusEnabled,
    _DetailKind.disabled => s.statusDisabled,
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    final s = Strings.of(context);
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 12, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.statusPanelTitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      color: colors.accentHover,
                    ),
                  ),
                ),
                if (_loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: s.statusRefresh,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                    color: colors.accentHover,
                    onPressed: _probe,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_rows == null && _loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  s.statusChecking,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              )
            else
              for (final r in _rows ?? const <_RawRow>[])
                _rowTile(r, colors, s),
          ],
        ),
      ),
    );
  }

  Widget _rowTile(_RawRow r, HermesThemeColors colors, Strings s) {
    final (IconData icon, Color color) = switch (r.health) {
      _Health.ok => (Icons.circle, colors.success),
      _Health.warn => (Icons.circle, colors.warning),
      _Health.bad => (Icons.circle, colors.error),
      _Health.unknown => (Icons.circle_outlined, colors.textSecondary),
    };

    final isLocal = widget.connection.kind == InstanceKind.localhost;
    final isBridge = r.label == _LabelKind.bridge;
    final bridgeDown = isBridge && r.health != _Health.ok;

    // En LOCAL el bridge no conectado se intenta habilitar in situ (provisión);
    // si ya falló, se ofrece reiniciar el agente. En REMOTO no hay instalador:
    // solo una nota de que corre en el servidor.
    final canProvision =
        bridgeDown &&
        isLocal &&
        widget.bridgeManager != null &&
        !_provisionFailed;
    final canRestart =
        bridgeDown && isLocal && _provisionFailed && widget.connManager != null;
    // REMOTO: no podemos reiniciar un proceso en el servidor, pero sí
    // "reparar" el enlace re-provisionando el token con la API key del gateway
    // (el fallo típico: el bridge corre en el servidor pero el token de la app
    // está caducado/ausente). Análogo al reparador de las instancias locales.
    final canRepairRemote =
        bridgeDown &&
        !isLocal &&
        widget.bridgeManager != null &&
        widget.connection.apiKey.trim().isNotEmpty;

    final Widget trailing;
    if (canProvision && _provisioning) {
      trailing = Text(
        s.statusBridgeEnabling,
        style: TextStyle(fontSize: 12, color: colors.accentHover),
      );
    } else if (canProvision) {
      trailing = Text(
        s.statusBridgeEnable,
        style: TextStyle(fontSize: 12, color: colors.accentHover),
      );
    } else if (bridgeDown && isLocal && _provisionFailed) {
      trailing = Text(
        s.statusBridgeFailed,
        style: TextStyle(fontSize: 12, color: colors.warning),
      );
    } else {
      trailing = Text(
        _detailText(r.detail, s),
        style: TextStyle(fontSize: 12, color: colors.textSecondary),
      );
    }

    final mainRow = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _labelText(r.label, s),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          trailing,
          if (canProvision) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: colors.accentHover),
          ],
        ],
      ),
    );

    final row = canProvision
        ? InkWell(
            onTap: _provisioning ? null : _provisionBridge,
            child: mainRow,
          )
        : mainRow;

    // Sub-línea: acción de reinicio (local, tras fallo) o nota de servidor
    // (remoto). Si no aplica, devolvemos solo la fila.
    Widget? sub;
    if (canRestart) {
      sub = Padding(
        padding: const EdgeInsets.only(left: 21, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: _openLocalControl,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.restart_alt,
                      size: 15,
                      color: colors.accentHover,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      s.statusBridgeRestart,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.accentHover,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Text(
              s.statusBridgeRestartHint,
              style: TextStyle(fontSize: 11, color: colors.textSecondary),
            ),
          ],
        ),
      );
    } else if (bridgeDown && !isLocal) {
      final repairing = _provisioning;
      sub = Padding(
        padding: const EdgeInsets.only(left: 21, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (canRepairRemote)
              InkWell(
                onTap: repairing ? null : _provisionBridge,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        repairing ? Icons.hourglass_top : Icons.healing,
                        size: 15,
                        color: colors.accentHover,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        repairing
                            ? s.statusBridgeRepairing
                            : s.statusBridgeRepair,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.accentHover,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Text(
              // Tras un intento fallido, la causa ya no es el token: el bridge
              // no está desplegado en el servidor.
              _provisionFailed
                  ? s.statusBridgeServerHint
                  : s.statusBridgeRepairHint,
              style: TextStyle(fontSize: 11, color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    if (sub == null) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [row, sub],
    );
  }
}
