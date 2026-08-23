// Elección de modo de uso (primera ejecución o desde el estado vacío del home):
//
//   A) Usar Hermes en este móvil   → agente local (Termux controlable / app)
//   B) Conectarme a mis instancias → cliente remoto (InstanceEditScreen)
//
// Explica claro la diferencia agente-local vs cliente-remoto. Al completar un
// modo (conexión guardada o app local abierta) llama a [onDone].
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../config/flavor.dart';
import '../../services/connection_manager.dart';
import '../../theme/app_theme.dart';
import '../../widgets/hermes_ui.dart';
import 'connect_chooser_screen.dart';
import 'local_agent_setup_screen.dart';
import 'local_uninstall_screen.dart';
import '../../widgets/hermes_app_bar.dart';

class WelcomeModeScreen extends StatefulWidget {
  final ConnectionManager connManager;

  /// Se llama cuando el usuario completó un modo (p.ej. guardó una conexión).
  final VoidCallback onDone;

  const WelcomeModeScreen({
    required this.connManager,
    required this.onDone,
    super.key,
  });

  @override
  State<WelcomeModeScreen> createState() => _WelcomeModeScreenState();
}

// Stateful para que `hasLocal` se recalcule al VOLVER de instalar o
// desinstalar: como StatelessWidget la pantalla seguía mostrando la tarjeta
// "agente ya instalado" sobre un agente recién desinstalado (spec 028 A-008).
class _WelcomeModeScreenState extends State<WelcomeModeScreen> {
  Future<void> _openRemote(BuildContext context) async {
    // Chooser "ambos por igual": escanear QR o introducir manualmente.
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ConnectChooserScreen(
          connManager: widget.connManager,
          onDone: widget.onDone,
        ),
      ),
    );
  }

  Future<void> _openLocal(BuildContext context) async {
    final connected = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LocalAgentSetupScreen(connManager: widget.connManager),
      ),
    );
    if (connected == true) {
      widget.onDone();
    } else if (mounted) {
      // Refleja el estado real (p.ej. instalación cancelada/parcial).
      setState(() {});
    }
  }

  Future<void> _openUninstall(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LocalUninstallScreen(connManager: widget.connManager),
      ),
    );
    // Al volver, el agente puede ya no existir: recalcular `hasLocal`.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    final str = Strings.of(context);
    // Solo cabe un agente local por dispositivo: si ya hay uno, no ofrecemos
    // instalar/añadir otro (se muestra como ya configurado).
    final hasLocal = widget.connManager
        .getConnections()
        .any((c) => c.kind == InstanceKind.localhost);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: HermesAppBar(
        title: Text(
          str.wlcScreenTitle,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            letterSpacing: 1,
            color: colors.accentHover,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Text(
              str.wlcSubtitle,
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
            const SizedBox(height: 18),
            // La opción de instancia local solo existe en el flavor `full`.
            // En `play` (Google Play, solo-remoto) se ofrece únicamente remoto.
            if (kLocalAgentEnabled) ...[
              if (hasLocal)
                _LocalAlreadySetCard(
                  colors: colors,
                  onConnect: () => _openLocal(context),
                  onUninstall: () => _openUninstall(context),
                )
              else
                _ModeCard(
                  colors: colors,
                  icon: Icons.smartphone_rounded,
                  title: str.wlcLocalTitle,
                  body: str.wlcLocalBody,
                  cta: str.wlcLocalCta,
                  onTap: () => _openLocal(context),
                ),
              const SizedBox(height: 14),
            ],
            _ModeCard(
              colors: colors,
              icon: Icons.dns_rounded,
              title: str.wlcRemoteTitle,
              body: str.wlcRemoteBody,
              cta: str.wlcRemoteCta,
              onTap: () => _openRemote(context),
            ),
            const SizedBox(height: 18),
            // Permite entrar a la app sin configurar nada todavía; el home tolera
            // el estado vacío y siempre se puede añadir una instancia después.
            Center(
              child: TextButton(
                onPressed: widget.onDone,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Text(
                  str.wlcSkipLater,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sustituye a la tarjeta de "usar en este móvil" cuando ya hay un agente local
/// configurado: solo cabe uno por dispositivo. Muestra dos acciones directas:
/// conectar al agente ya instalado o desinstalarlo.
class _LocalAlreadySetCard extends StatelessWidget {
  final HermesThemeColors colors;
  final VoidCallback onConnect;
  final VoidCallback onUninstall;

  const _LocalAlreadySetCard({
    required this.colors,
    required this.onConnect,
    required this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceVariant.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.divider.withValues(alpha: 0.22),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: colors.success,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        Strings.of(context).wlcInstalledTitle,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  Strings.of(context).wlcInstalledBody,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                HermesPrimaryButton(
                  label: Strings.of(context).wlcConnectLabel,
                  icon: Icons.bolt_rounded,
                  onTap: onConnect,
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: colors.divider.withValues(alpha: 0.22),
          ),
          TextButton.icon(
            onPressed: onUninstall,
            icon: Icon(Icons.delete_outline, size: 15, color: colors.error),
            label: Text(
              Strings.of(context).wlcUninstallLabel,
              style: TextStyle(color: colors.error, fontSize: 13),
            ),
            style: TextButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final HermesThemeColors colors;
  final IconData icon;
  final String title;
  final String body;
  final String cta;
  final VoidCallback onTap;

  const _ModeCard({
    required this.colors,
    required this.icon,
    required this.title,
    required this.body,
    required this.cta,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Animación de entrada (fade + leve subida), sin iconos en caja.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - t)),
          child: child,
        ),
      ),
      child: PressableScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.surfaceVariant.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colors.divider.withValues(alpha: 0.22),
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Icono limpio, sin caja.
                  Icon(icon, color: colors.accent, size: 30),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                body,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    cta,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: colors.accent,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.arrow_forward_rounded,
                      size: 16, color: colors.accent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
