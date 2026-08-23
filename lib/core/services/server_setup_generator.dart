// Generador de artefactos de "setup todo en uno" para el onboarding (paso 1).
//
// Produce dos textos (NO ejecuta nada en el móvil) para que el usuario deje su
// servidor Hermes listo y obtenga el enlace de emparejado:
//   1) agentPrompt  → para pegar al propio agente (Telegram/TUI/Desktop/CLI);
//      pide ejecutar el instalador público y responder con el `hermes://pair`.
//   2) curlCommand  → el mismo instalador para la terminal (SSH).
//
// Ambos caminos convergen en scripts/hermes-mobile-setup.sh (publicado en el
// repo hermes-setup): todo-en-uno, idempotente, imprime el enlace + QR. Esto
// sustituye a los blobs autocontenidos de ~60KB (spec 028 U-23/U-26): un texto
// corto siempre se pega bien (el blob chocaba con MAX_CANON en terminal y con
// el límite de 4096 chars por mensaje de Telegram), es auditable en GitHub
// antes de ejecutarlo, y deja UNA sola fuente de verdad del setup.
//
// Lógica PURA y testeable sin dispositivo: textos constantes, sin assets ni
// red. Reutiliza el formato de enlace de PairingLink SIN modificarlo.
// Ver docs/INSTALLATION.md.
import 'pairing_link.dart';

/// Sistema operativo del equipo que ejecuta Hermes Agent (no del movil).
enum ServerHostPlatform { linux, macos, windows }

class ServerSetupGenerator {
  const ServerSetupGenerator();

  /// Puerto por defecto del gateway API de Hermes.
  static const int gatewayPort = 8642;

  /// Puerto por defecto del Dashboard.
  static const int dashboardPort = 9119;

  /// Puerto por defecto del Mobile Bridge (lo levanta el script de instalación).
  static const int bridgePort = 9131;

  /// URL pública del script de setup todo-en-uno. El repo hermes-setup aloja la
  /// copia publicada de `scripts/hermes-mobile-setup.sh` (y del bridge que ese
  /// script descarga): al cambiar cualquiera de los dos aquí, actualizar el
  /// repo público en el mismo release.
  static const String setupScriptUrl =
      'https://raw.githubusercontent.com/xP3ta/hermes-setup/main/hermes-mobile-setup.sh';

  /// Instalador nativo para Windows PowerShell. No se enruta por Git Bash:
  /// Hermes nativo usa rutas, procesos y persistencia propios de Windows.
  static const String windowsSetupScriptUrl =
      'https://raw.githubusercontent.com/xP3ta/hermes-setup/main/hermes-mobile-setup.ps1';

  /// Comando corto de copia-pega para la terminal del servidor: descarga el
  /// script público (auditable en GitHub) y lo ejecuta. Idempotente: sirve
  /// igual para un servidor virgen que para reinstalar/actualizar el bridge.
  static const String curlCommand = 'curl -fsSL $setupScriptUrl | sh';

  static const String powershellCommand = 'irm $windowsSetupScriptUrl | iex';

  /// Variante invocable desde el shell de herramientas de Hermes en Windows,
  /// que normalmente es Git Bash incluso cuando el host es Windows nativo.
  static const String powershellShellCommand =
      'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '
      '"irm \'$windowsSetupScriptUrl\' | iex"';

  /// URL pública del script de emparejado bajo demanda (U-34): reimprime el
  /// QR/enlace en un servidor ya instalado, sin reinstalar nada. Misma regla
  /// de publicación que [setupScriptUrl]: vive en el repo hermes-setup.
  static const String pairScriptUrl =
      'https://raw.githubusercontent.com/xP3ta/hermes-setup/main/hermes-pair.sh';

  static const String windowsPairScriptUrl =
      'https://raw.githubusercontent.com/xP3ta/hermes-setup/main/hermes-pair.ps1';

  /// One-liner corto que la app ofrece cuando el usuario ya tiene servidor y
  /// solo necesita volver a ver el QR (p. ej. desde el escáner).
  static const String pairCommand = 'curl -fsSL $pairScriptUrl | sh';

  static const String powershellPairCommand = 'irm $windowsPairScriptUrl | iex';

  static String setupCommandFor(ServerHostPlatform platform) =>
      platform == ServerHostPlatform.windows ? powershellCommand : curlCommand;

  static String pairCommandFor(ServerHostPlatform platform) =>
      platform == ServerHostPlatform.windows
      ? powershellPairCommand
      : pairCommand;

  /// Construye el enlace canónico de emparejado reutilizando [PairingLink]
  /// (misma "moneda" que la app ya consume). Útil para validar el formato y
  /// como referencia del que emiten los artefactos.
  static String buildPairingLink({
    required String host,
    required int port,
    required String token,
    bool useHttps = false,
    String? dashboardUrl,
    String? bridgeUrl,
    String? bridgeToken,
    String? label,
  }) {
    return PairingLink(
      host: host,
      port: port,
      token: token,
      label: label,
      useHttps: useHttps,
      dashboardUrl: dashboardUrl,
      bridgeUrl: bridgeUrl,
      bridgeToken: bridgeToken,
    ).build();
  }

  /// Prompt para pegar al agente del usuario. Enmarcado como tarea de primera
  /// parte autorizada por el dueño del dispositivo (para que el agente la
  /// proponga con aprobación, no la rechace por opaca). Pide ejecutar el MISMO
  /// instalador público del camino SSH — el agente puede descargarlo y leerlo
  /// antes — y RESPONDER con el enlace en texto (funciona en cualquier canal,
  /// incluido Telegram, donde el viejo prompt de 60KB ni siquiera cabía).
  static String agentPromptFor(ServerHostPlatform platform) {
    final command = platform == ServerHostPlatform.windows
        ? powershellShellCommand
        : setupCommandFor(platform);
    final shell = platform == ServerHostPlatform.windows
        ? 'Windows PowerShell'
        : 'a POSIX shell';
    final lifecycle = switch (platform) {
      ServerHostPlatform.windows =>
        'native Windows Scheduled Tasks (with a per-user startup fallback)',
      ServerHostPlatform.macos => 'macOS launchd services',
      ServerHostPlatform.linux =>
        'systemd user services (with a portable Unix fallback)',
    };
    return 'First-party setup requested by the device owner from the Hermes '
        'Console app. Goal: get this Hermes server ready for a remote '
        'connection and reply with its pairing link.\n\n'
        'Using $shell on the server (the owner authorized this), run the public '
        'Hermes Console installer:\n\n'
        '    $command\n\n'
        'Feel free to fetch and read the script first — it is short, legible '
        'and hosted in the public hermes-setup repository. It is idempotent and '
        'safe on an '
        'already-configured server: it installs Hermes only if missing, ensures '
        'an API token on the server, and brings up the '
        'gateway (:$gatewayPort), the dashboard (:$dashboardPort) and the '
        'mobile bridge (:$bridgePort) using $lifecycle, listening '
        'on all interfaces so the phone can reach them over Tailscale/LAN. It '
        'does not reset any existing password or key. Before printing anything '
        'sensitive, it verifies the real Gateway, Dashboard and Bridge through '
        'the exact phone-facing address.\n\n'
        'When it finishes it prints a pairing link. Reply ONLY with that link '
        'in plain TEXT (hermes://pair?host=<reachable-ip>&port=$gatewayPort'
        '&token=…&dashboard=http://<reachable-ip>:$dashboardPort'
        '&bridge=http://<reachable-ip>:$bridgePort&bridge_token=…). If the '
        'script fails, reply with the last lines of its output instead.';
  }

  /// Compatibilidad con consumidores anteriores; Linux sigue siendo el valor
  /// por defecto solo para llamadas de codigo que aun no ofrecen selector.
  static final String agentPrompt = agentPromptFor(ServerHostPlatform.linux);
}
