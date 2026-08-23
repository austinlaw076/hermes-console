import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hermes_android/core/services/agent_runtime/agent_runtime.dart';
import 'package:hermes_android/core/services/agent_runtime/local_termux_agent_provider.dart';
import 'package:hermes_android/core/services/platform/android_apps.dart';

/// AppBridge falso para tests: paquetes "instalados" configurables.
class FakeAppBridge implements AppBridge {
  final Set<String> installed;
  String? lastFdroid;
  String? lastLaunched;
  String? lastTermuxCommand;
  bool? lastTermuxBackground;
  String? lastForegroundCommand;
  String? lastProbeCommand;
  String? probeResult; // stdout simulado de la sonda de Termux
  bool termuxOk;

  FakeAppBridge({Set<String>? installed, this.termuxOk = false})
    : installed = installed ?? {};

  @override
  Future<bool> isInstalled(String package) async => installed.contains(package);

  @override
  Future<bool> launch(String package) async {
    lastLaunched = package;
    return installed.contains(package);
  }

  @override
  Future<bool> runInTermux(String command, {bool background = true}) async {
    lastTermuxCommand = command;
    lastTermuxBackground = background;
    return termuxOk;
  }

  @override
  Future<bool> launchTermuxForeground(String command) async {
    lastForegroundCommand = command;
    return termuxOk;
  }

  @override
  Future<String?> probeTermux(String command) async {
    lastProbeCommand = command;
    return probeResult;
  }

  @override
  Future<bool> installFromFDroid(String package) async {
    lastFdroid = package;
    return true;
  }

  @override
  Future<DeviceInfo> deviceInfo() async => DeviceInfo.unknown;
}

void main() {
  group('LocalTermuxAgentProvider', () {
    // Cliente que simula "no hay agente en localhost" (rechazo).
    http.Client refused() =>
        MockClient((_) async => http.Response('nope', 503));

    test('notInstalled cuando Termux no está y no hay agente', () async {
      final p = LocalTermuxAgentProvider(
        apps: FakeAppBridge(),
        client: refused(),
      );
      expect(await p.status(), AgentRuntimeStatus.notInstalled);
    });

    test('needsSetup cuando Termux está pero el agente no responde', () async {
      final p = LocalTermuxAgentProvider(
        apps: FakeAppBridge(installed: {AgentRuntimeConsts.termuxPackage}),
        client: refused(),
      );
      expect(await p.status(), AgentRuntimeStatus.needsSetup);
    });

    test('ready cuando el dashboard local responde /api/status OK', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/api/status') {
          return http.Response('{"online":true}', 200);
        }
        return http.Response('nope', 404);
      });
      final p = LocalTermuxAgentProvider(apps: FakeAppBridge(), client: client);
      expect(await p.status(), AgentRuntimeStatus.ready);
    });

    // Regresión: el agente local corre como dashboard en :9119 y su salud está
    // en /api/status. Sondear /health (sólo del gateway :8642) daba 404 aunque
    // el agente estuviera vivo, forzando el flujo de instalación.
    test(
      'NO se detecta si sólo responde /health (debe sondear /api/status)',
      () async {
        final client = MockClient((req) async {
          if (req.url.path == '/health') {
            return http.Response('ok', 200);
          }
          return http.Response('nope', 404);
        });
        final p = LocalTermuxAgentProvider(
          apps: FakeAppBridge(),
          client: client,
        );
        expect(await p.isAgentRunning(), isFalse);
      },
    );

    test('installCommand es el instalador documentado', () {
      final p = LocalTermuxAgentProvider(apps: FakeAppBridge());
      expect(p.installCommand, contains('install.sh'));
    });
  });

  group('AgentRuntimeConsts — comandos del wizard manual (ADR-006)', () {
    test('URL canónica es la oficial nousresearch (no la raw de GitHub)', () {
      expect(
        AgentRuntimeConsts.installerUrl,
        'https://hermes-agent.nousresearch.com/install.sh',
      );
      expect(
        AgentRuntimeConsts.installCommand,
        contains('hermes-agent.nousresearch.com'),
      );
      expect(
        AgentRuntimeConsts.installCommand,
        isNot(contains('raw.githubusercontent')),
      );
    });

    test(
      'el fallback es la raw de GitHub y NO aparece en la ruta principal',
      () {
        expect(
          AgentRuntimeConsts.installerUrlFallback,
          contains('raw.githubusercontent.com'),
        );
        expect(
          AgentRuntimeConsts.installerUrlFallback,
          isNot(AgentRuntimeConsts.installerUrl),
        );
      },
    );

    test('paquetes base = lista oficial de Termux + curl', () {
      const cmd = AgentRuntimeConsts.basePackagesCommand;
      for (final pkg in [
        'git',
        'python',
        'clang',
        'rust',
        'make',
        'pkg-config',
        'libffi',
        'openssl',
        'nodejs',
        'ripgrep',
        'ffmpeg',
        'curl',
        'libjpeg-turbo',
        'python-pillow',
      ]) {
        expect(cmd, contains(pkg), reason: 'falta $pkg');
      }
      expect(cmd, startsWith('pkg install -y'));
    });

    test('el wrapper instala Pillow precompilado y evita prompts de dpkg', () {
      final w = AgentRuntimeConsts.installWrapperCommand;
      // python-pillow: Pillow precompilado, evita el build roto de la wheel.
      expect(w, contains('python-pillow'));
      // libjpeg-turbo: dependencia nativa de imagen de Pillow.
      expect(w, contains('libjpeg-turbo'));
      // En background no hay terminal: confold evita el prompt de dpkg que
      // bloquearía la instalación al tocar archivos de config.
      expect(w, contains('Dpkg::Options::="--force-confold"'));
      // El skip de deps ya instaladas también exige la libjpeg presente, para
      // reparar instalaciones previas que no la tenían.
      expect(w, contains(r'ls "$PREFIX"/lib/libjpeg.so*'));
    });

    test('NO se instalan extras no soportados en Termux', () {
      final all = [
        AgentRuntimeConsts.basePackagesCommand,
        AgentRuntimeConsts.installCommand,
        AgentRuntimeConsts.installWrapperCommand,
      ].join('\n');
      expect(all, isNot(contains('.[all]')));
      expect(all.toLowerCase(), isNot(contains('docker')));
      expect(all.toLowerCase(), isNot(contains('playwright')));
    });

    test('update y setup interactivo queda deshabilitado', () {
      expect(
        AgentRuntimeConsts.updateCommand,
        'pkg update -y && pkg upgrade -y',
      );
      expect(AgentRuntimeConsts.setupCommand, '# interactive setup disabled');
      expect(AgentRuntimeConsts.changeRepoCommand, 'termux-change-repo');
    });

    test('el wrapper automático endurece el timeout y separa etapas', () {
      final w = AgentRuntimeConsts.installWrapperCommand;
      expect(w, contains('timeout -k 10 -s TERM'));
      expect(w, contains('run 1800 bash "\$LOGD/inst.sh" --skip-setup'));
      expect(w, isNot(contains('run 270 bash')));
      expect(w, contains('@@STAGE Actualizando Termux'));
      expect(w, contains('@@STAGE Instalando dependencias base'));
      expect(w, contains('@@STAGE Verificando'));
      // El fallback de URL solo vive en la ruta automática (wrapper).
      expect(w, contains('raw.githubusercontent.com'));
    });

    test('el wrapper crea config minima sin setup interactivo', () {
      final w = AgentRuntimeConsts.installWrapperCommand;
      expect(w, contains(r'mkdir -p "$HOME/.hermes"'));
      expect(w, contains('config.yaml'));
      expect(w, contains('model:'));
      expect(w, contains('provider: "custom"'));
      expect(w, contains('base_url: "http://127.0.0.1:11434/v1"'));
      expect(w, contains('chmod 600'));
    });

    test('el wrapper tiene lock de instancia única (evita doble apt lock)', () {
      final w = AgentRuntimeConsts.installWrapperCommand;
      expect(w, contains('LOCK="\$LOGD/inst.pid"'));
      expect(w, contains('kill -0 "\$OLD"'));
      // Sale en silencio si ya hay una instancia viva.
      expect(w, contains('exit 0'));
      // El lock se comprueba ANTES de truncar el log (no pisar el progreso de la
      // instancia en curso).
      expect(
        w.indexOf('LOCK="\$LOGD/inst.pid"'),
        lessThan(w.indexOf(': > "\$LOG"')),
      );
    });

    test('el servidor de log guarda el PID directo de python3', () {
      final w = AgentRuntimeConsts.installWrapperCommand;
      expect(w, contains('srv(){ python3 -m http.server 8643'));
      expect(w, isNot(contains('srv(){ ( python3 -m http.server 8643')));
    });

    test('la espera de paquetes tiene fallback si pgrep -x no existe', () {
      final w = AgentRuntimeConsts.installWrapperCommand;
      expect(w, contains('pgrep_exact(){ pgrep -x "\$1"'));
      expect(w, contains(r'pgrep "^$1$"'));
      expect(w, contains('while pgrep_exact pkg || pgrep_exact apt'));
    });

    test('cancelar mata el wrapper y compiladores hijos best-effort', () {
      final c = AgentRuntimeConsts.cancelInstallCommand;
      expect(c, contains(r'kill -- -"$(cat "$P/inst.pid")"'));
      expect(c, contains(r'pkill -f "$P/inst.sh"'));
      expect(c, contains('pkill -f "http.server 8643"'));
      expect(c, contains('pkill -f "pip install"'));
      expect(c, contains('pkill -f "cargo build"'));
      expect(c, contains('pkill -f "maturin"'));
      expect(c, contains('pkill -f "rustc"'));
      expect(c, contains('@@EXIT 130'));
    });

    // TODO(pr-4-clean-cli-ux): activar cuando Opus añada
    // AgentRuntimeConsts.stopAgentCommand.
    //
    // test('stopAgentCommand detiene el gateway y confirma STOPPED', () {
    //   final c = AgentRuntimeConsts.stopAgentCommand;
    //   expect(c, contains('pkill -TERM -f "hermes gateway"'));
    //   expect(c, contains('pkill -KILL -f "hermes"'));
    //   expect(c, contains('STOPPED'));
    // });

    test('la ruta automática ejecuta los comandos permitidos pero NUNCA los '
        'interactivos (ADR-007)', () {
      final w = AgentRuntimeConsts.installWrapperCommand;
      // Permitidos en automático.
      expect(w, contains('pkg update'));
      expect(w, contains('pkg install -y git python'));
      expect(w, contains('install.sh'));
      expect(w, contains('--skip-setup'));
      // Verificación REAL del entorno, no del wrapper de Termux: `command -v
      // hermes` acierta con el wrapper aunque el venv esté vacío (pip cortado por
      // OOM). Comprobamos que hermes_cli importe en el python del venv.
      expect(w, contains('import hermes_cli'));
      expect(w, contains(r'"$VHERMES" version'));
      // Interactivos: jamás en el wrapper.
      expect(w, isNot(contains('termux-change-repo')));
      expect(w, isNot(contains('hermes setup')));
    });
  });

  group('AgentRuntimeConsts — writeConfigCommand', () {
    test('genera comando con model.provider, model.default y .env', () {
      final cmd = AgentRuntimeConsts.writeConfigCommand(
        provider: 'openai',
        model: 'gpt-4o',
        apiKey: 'test-api-key',
      );
      expect(cmd, contains('base64'));
      expect(cmd, contains('config.yaml'));
      expect(cmd, contains('chmod 600'));
      expect(cmd, contains('CONFIG_DONE'));
      expect(cmd, contains('provider'));
      expect(cmd, contains('default'));
      expect(cmd, contains('.env'));
      expect(cmd, contains(base64.encode(utf8.encode('OPENAI_API_KEY'))));
    });

    test('para ollama (apiKey vacío) no incluye api_key', () {
      final cmd = AgentRuntimeConsts.writeConfigCommand(
        provider: 'ollama',
        model: 'llama3',
        apiKey: '',
      );
      expect(cmd, isNot(contains('api_key')));
      expect(cmd, contains('config.yaml'));
      expect(cmd, contains('CONFIG_DONE'));
    });

    test('para ollama con baseUrl incluye base_url', () {
      final cmd = AgentRuntimeConsts.writeConfigCommand(
        provider: 'ollama',
        model: 'phi3:mini',
        apiKey: '',
        baseUrl: 'http://127.0.0.1:11434',
      );
      expect(cmd, contains('base_url'));
      expect(cmd, contains(base64.encode(utf8.encode('custom'))));
      expect(cmd, contains(base64.encode(utf8.encode('phi3:mini'))));
      expect(
        cmd,
        contains(base64.encode(utf8.encode('http://127.0.0.1:11434/v1'))),
      );
      expect(cmd, isNot(contains('api_key')));
    });

    test('sin baseUrl no incluye base_url', () {
      final cmd = AgentRuntimeConsts.writeConfigCommand(
        provider: 'openai',
        model: 'gpt-4o',
        apiKey: 'test-api-key',
      );
      expect(cmd, isNot(contains('base_url')));
    });

    test('la api_key no aparece en texto plano — se codifica en base64', () {
      const key = 'test-secret-key-abc123';
      final cmd = AgentRuntimeConsts.writeConfigCommand(
        provider: 'openai',
        model: 'gpt-4o',
        apiKey: key,
      );
      expect(cmd, isNot(contains(key)));
      final b64 = base64.encode(utf8.encode(key));
      expect(cmd, contains(b64));
    });

    test('el provider y el modelo se codifican en base64', () {
      final cmd = AgentRuntimeConsts.writeConfigCommand(
        provider: 'anthropic',
        model: 'claude-opus-4-8',
        apiKey: 'test-anthropic-key',
      );
      expect(cmd, contains(base64.encode(utf8.encode('anthropic'))));
      expect(cmd, contains(base64.encode(utf8.encode('claude-opus-4-8'))));
    });

    test('configura el entorno Termux correctamente', () {
      final cmd = AgentRuntimeConsts.writeConfigCommand(
        provider: 'openai',
        model: 'gpt-4o',
        apiKey: 'test-api-key',
      );
      expect(cmd, contains('/data/data/com.termux/files/usr'));
      expect(cmd, contains('/data/data/com.termux/files/home'));
      expect(cmd, contains('mkdir -p'));
    });

    // Cada provider con API key escribe SU variable de entorno (no el patrón
    // por defecto cuando difiere). Fuente: docs oficiales de configuración.
    test('cada provider con API key usa su variable de entorno correcta', () {
      const cases = {
        'anthropic': 'ANTHROPIC_API_KEY',
        'openai': 'OPENAI_API_KEY',
        'openrouter': 'OPENROUTER_API_KEY',
        'gemini': 'GOOGLE_API_KEY',
        'deepseek': 'DEEPSEEK_API_KEY',
        'mistral': 'MISTRAL_API_KEY',
        'minimax': 'MINIMAX_API_KEY',
        'xai': 'XAI_API_KEY',
        'kimi-coding': 'KIMI_API_KEY',
        'huggingface': 'HF_API_KEY',
        'azure-foundry': 'AZURE_API_KEY',
      };
      cases.forEach((provider, envVar) {
        expect(
          AgentRuntimeConsts.envVarFor(provider),
          envVar,
          reason: 'envVarFor($provider) debe ser $envVar',
        );
        final cmd = AgentRuntimeConsts.writeConfigCommand(
          provider: provider,
          model: 'm',
          apiKey: 'k',
        );
        expect(
          cmd,
          contains(base64.encode(utf8.encode(envVar))),
          reason: '$provider debe escribir $envVar en .env',
        );
        expect(cmd, contains(base64.encode(utf8.encode(provider))));
      });
    });

    test('un provider desconocido cae al patrón <PROVIDER>_API_KEY', () {
      expect(AgentRuntimeConsts.envVarFor('foo-bar'), 'FOO_BAR_API_KEY');
    });

    test('provider OAuth omite el bloque .env (token vía hermes auth)', () {
      for (final provider in [
        'nous',
        'codex',
        'qwen-oauth',
        'minimax-oauth',
        'xai-oauth',
      ]) {
        final cmd = AgentRuntimeConsts.writeConfigCommand(
          provider: provider,
          model: '',
          apiKey: '',
          isOAuth: true,
        );
        // Sin .env: no escribe ninguna variable de API key.
        expect(
          cmd,
          isNot(contains('_API_KEY')),
          reason: '$provider no debe escribir variables de API key',
        );
        expect(
          cmd,
          isNot(contains(r'>> "$ENVF"')),
          reason: '$provider no debe escribir en .env',
        );
        // Sí fija el provider en config.yaml.
        expect(cmd, contains(base64.encode(utf8.encode(provider))));
        expect(cmd, contains('config.yaml'));
        expect(cmd, contains('CONFIG_DONE'));
      }
    });

    test('OAuth sin modelo no emite la línea default', () {
      final cmd = AgentRuntimeConsts.writeConfigCommand(
        provider: 'nous',
        model: '',
        apiKey: '',
        isOAuth: true,
      );
      expect(cmd, isNot(contains('default:')));
      expect(cmd, contains('provider:'));
    });
  });

  group('AgentRuntimeConsts — oauthCommand', () {
    test('codex se mapea a `hermes auth add openai-codex --type oauth`', () {
      final cmd = AgentRuntimeConsts.oauthCommand(provider: 'codex');
      expect(cmd, contains('hermes auth add openai-codex --type oauth'));
      // `hermes login` está retirado; no debe usarse.
      expect(cmd, isNot(contains('hermes login')));
    });

    test(
      'los providers OAuth usan `hermes auth add … --type oauth` (device flow)',
      () {
        const expected = {
          'nous': 'hermes auth add nous --type oauth',
          'xai-oauth': 'hermes auth add xai-oauth --type oauth',
        };
        expected.forEach((provider, fragment) {
          final cmd = AgentRuntimeConsts.oauthCommand(provider: provider);
          expect(cmd, contains(fragment), reason: provider);
          expect(cmd, contains('--no-browser'));
          expect(cmd, isNot(contains('hermes login')));
        });
      },
    );

    test('oauthCommand fija el PATH del venv', () {
      final cmd = AgentRuntimeConsts.oauthCommand(provider: 'nous');
      expect(cmd, contains('venv/bin'));
      expect(cmd, contains(r'export PATH='));
    });

    test(
      'oauthCommand sirve su log por localhost (:8644) y marca inicio/fin',
      () {
        final cmd = AgentRuntimeConsts.oauthCommand(provider: 'nous');
        expect(cmd, contains('http.server 8644'));
        expect(cmd, contains('@@OAUTH_START'));
        expect(cmd, contains('@@OAUTH_DONE'));
      },
    );

    test(
      'oauthCommand instala wrappers de navegador que emiten @@OAUTH_URL',
      () {
        final cmd = AgentRuntimeConsts.oauthCommand(provider: 'nous');
        // Shims para los abridores de URL más comunes.
        expect(cmd, contains('xdg-open'));
        expect(cmd, contains('termux-open-url'));
        // El wrapper escribe el marcador que captura la Consola.
        expect(cmd, contains('@@OAUTH_URL'));
      },
    );

    test(
      'oauthCommand fuerza salida sin buffer (URL llega al log en vivo)',
      () {
        final cmd = AgentRuntimeConsts.oauthCommand(provider: 'nous');
        expect(cmd, contains('PYTHONUNBUFFERED=1'));
        expect(cmd, contains('stdbuf -oL'));
      },
    );

    test('oauthProgressUrl apunta a localhost:8644/oauth.log', () {
      expect(
        AgentRuntimeConsts.oauthProgressUrl,
        contains('127.0.0.1:8644/oauth.log'),
      );
    });
  });

  group('LocalTermuxAgentProvider — OAuth', () {
    test('runOAuthFlow lanza el comando OAuth en segundo plano', () async {
      final fake = FakeAppBridge(termuxOk: true);
      final p = LocalTermuxAgentProvider(apps: fake);
      await p.runOAuthFlow(provider: 'nous');
      expect(
        fake.lastTermuxCommand,
        contains('hermes auth add nous --type oauth'),
      );
      // background:true → sin terminal; la URL se sirve por localhost (:8644)
      // y la app la lee con fetchOAuthLog.
      expect(fake.lastTermuxBackground, isTrue);
    });
  });

  group('AndroidApps', () {
    test('fdroidWebUrl construye la URL de la ficha', () {
      final uri = AndroidApps.fdroidWebUrl('com.example.app');
      expect(
        uri.toString(),
        'https://f-droid.org/en/packages/com.example.app/',
      );
    });
  });

  group('AgentRuntimeConsts — desinstalación', () {
    test('uninstallCommand para procesos ANTES de borrar archivos', () {
      final u = AgentRuntimeConsts.uninstallCommand;
      final stopIdx = u.indexOf('@@STAGE parando');
      final deleteIdx = u.indexOf('@@STAGE borrando');
      expect(
        stopIdx,
        lessThan(deleteIdx),
        reason: 'debe parar procesos antes de borrar archivos',
      );
    });

    test('uninstallCommand NO borra la caché de pip', () {
      final u = AgentRuntimeConsts.uninstallCommand;
      expect(u, isNot(contains('.cache/pip')));
      expect(u, isNot(contains('cache/pip')));
    });

    test('uninstallCommand borra los directorios conocidos de Hermes', () {
      final u = AgentRuntimeConsts.uninstallCommand;
      expect(u, contains(r'$HOME/.hermes'));
      expect(u, contains(r'$HOME/.hermes-install'));
      expect(u, contains(r'$PREFIX/bin/hermes'));
    });

    test('uninstallCommand elimina ~/.hermes y el binario del PATH', () {
      final u = AgentRuntimeConsts.uninstallCommand;
      expect(u, matches(RegExp(r'rm -rf.*\.hermes')));
      expect(u, matches(RegExp(r'rm -f.*bin/hermes')));
      // ~/.hermes (dir principal) ANTES que ~/.hermes-install (temporal).
      final hermesIdx = u.indexOf(r'rm -rf "$HOME/.hermes"');
      final installIdx = u.indexOf(r'rm -rf "$HOME/.hermes-install"');
      expect(hermesIdx, greaterThanOrEqualTo(0));
      expect(hermesIdx, lessThan(installIdx));
    });

    test(
      'uninstallCommand mata el servidor de progreso de instalación (8643)',
      () {
        final u = AgentRuntimeConsts.uninstallCommand;
        // Apunta al pidfile del INSTALADOR, no al del propio desinstalador.
        expect(u, contains(r'$HOME/.hermes-install/srv.pid'));
        // Usa kill -9 (SIGKILL inmediato) para garantizar que el puerto queda libre.
        expect(u, contains('http.server 8643'));
        expect(u, contains('kill -9'));
      },
    );

    test('uninstallCommand emite @@EXIT 0 o @@EXIT 1 y @@DONE', () {
      final u = AgentRuntimeConsts.uninstallCommand;
      expect(u, contains('@@EXIT \$REMAIN'));
      expect(u, contains('@@DONE'));
      expect(u, contains('REMAIN=0'));
      expect(u, contains('REMAIN=1'));
    });

    test('cancelUninstallCommand emite @@EXIT 130', () {
      final c = AgentRuntimeConsts.cancelUninstallCommand;
      expect(c, contains('@@EXIT 130'));
      expect(c, contains('@@DONE'));
    });

    test('uninstallProgressUrl apunta a localhost:8643', () {
      expect(
        AgentRuntimeConsts.uninstallProgressUrl,
        contains('127.0.0.1:8643'),
      );
      expect(AgentRuntimeConsts.uninstallProgressUrl, contains('progress.log'));
    });

    test('uninstallCommand verifica restos con @@WARN', () {
      final u = AgentRuntimeConsts.uninstallCommand;
      expect(u, contains('@@WARN'));
      expect(u, contains('@@STAGE verificando'));
    });

    test('uninstallCommand mata procesos con TERM luego KILL', () {
      final u = AgentRuntimeConsts.uninstallCommand;
      final termIdx = u.indexOf('pkill -TERM');
      final killIdx = u.indexOf('pkill -KILL');
      expect(
        termIdx,
        lessThan(killIdx),
        reason: 'debe enviar TERM antes que KILL (graceful shutdown)',
      );
    });

    test('uninstallCommand mata pidfiles y puertos locales del runtime', () {
      final u = AgentRuntimeConsts.uninstallCommand;
      expect(u, contains(r'$HOME/.hermes/dashboard.pid'));
      expect(u, contains(r'$HOME/.hermes/gateway.pid'));
      expect(u, contains(r'$HOME/.hermes/bridge.pid'));
      for (final port in ['9119', '8642', '9131', '11434']) {
        expect(u, contains(port), reason: 'falta limpiar puerto $port');
      }
      expect(u, contains('kill_ports TERM'));
      expect(u, contains('kill_ports KILL'));
      expect(u, contains('@@WARN puerto'));
    });
  });

  group('AgentRuntimeConsts — stop y logs', () {
    test('stopAgentCommand envía TERM antes que KILL (graceful shutdown)', () {
      // Ignora las líneas de comentario (un comentario explica por qué se evita
      // `pkill -KILL -f "hermes"`, y ese literal en el comentario engañaba al
      // indexOf). Validamos el ORDEN funcional real de las señales.
      final s = AgentRuntimeConsts.stopAgentCommand
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('#'))
          .join('\n');
      final termIdx = s.indexOf('pkill -TERM');
      final killIdx = s.indexOf('pkill -KILL');
      expect(
        termIdx,
        lessThan(killIdx),
        reason: 'debe enviar TERM antes que KILL',
      );
    });

    test('stopAgentCommand mata gateway y dashboard, emite STOPPED', () {
      final s = AgentRuntimeConsts.stopAgentCommand;
      expect(s, contains('hermes gateway'));
      expect(s, contains('hermes dashboard'));
      expect(s, contains('STOPPED'));
    });

    test('stopAgentCommand fija el entorno Termux', () {
      final s = AgentRuntimeConsts.stopAgentCommand;
      expect(s, contains('/data/data/com.termux/files/usr'));
      expect(s, contains('export PATH'));
    });

    test('readLogsCommand lee las últimas 30 líneas de gateway.out', () {
      final r = AgentRuntimeConsts.readLogsCommand;
      expect(r, contains('tail -30'));
      expect(r, contains('gateway.out'));
      expect(r, contains('(sin logs)'));
    });
  });

  group('LocalTermuxAgentProvider — stopAgent', () {
    test(
      'stopAgent llama runInTermux con stopAgentCommand en background',
      () async {
        final fake = FakeAppBridge(termuxOk: true);
        final p = LocalTermuxAgentProvider(apps: fake);
        await p.stopAgent();
        expect(fake.lastTermuxCommand, contains('STOPPED'));
        expect(fake.lastTermuxBackground, isTrue);
      },
    );
  });

  group('AgentRuntimeConsts — ollama', () {
    test(
      'installOllamaCommand usa el paquete nativo de Termux (pkg install)',
      () {
        // NO el binario glibc de GitHub (404 + no corre en bionic): el paquete de
        // Termux es la vía correcta y la arquitectura la elige apt.
        final cmd = AgentRuntimeConsts.installOllamaCommand;
        expect(cmd, contains('pkg install -y ollama'));
        expect(cmd, isNot(contains('github.com/ollama/ollama/releases')));
      },
    );

    test('installOllamaCommand es idempotente (OLLAMA_YA_INSTALADO)', () {
      final cmd = AgentRuntimeConsts.installOllamaCommand;
      expect(cmd, contains('OLLAMA_YA_INSTALADO'));
      expect(cmd, contains('command -v ollama'));
    });

    test('installOllamaCommand limpia un binario stub roto previo', () {
      // El 404 antiguo dejaba un "ollama" de 9 bytes que daba falso positivo.
      final cmd = AgentRuntimeConsts.installOllamaCommand;
      expect(cmd, contains('wc -c'));
      expect(cmd, contains('rm -f "\$DEST"'));
    });

    test('installOllamaCommand emite OLLAMA_INSTALADO / OLLAMA_ERROR', () {
      final cmd = AgentRuntimeConsts.installOllamaCommand;
      expect(cmd, contains('OLLAMA_INSTALADO'));
      expect(cmd, contains('OLLAMA_ERROR'));
    });

    test('installOllamaCommand fija el entorno Termux', () {
      final cmd = AgentRuntimeConsts.installOllamaCommand;
      expect(cmd, contains('/data/data/com.termux/files/usr'));
      expect(cmd, contains('/data/data/com.termux/files/home'));
    });

    test('startOllamaCommand arranca en :11434 y es idempotente', () {
      final cmd = AgentRuntimeConsts.startOllamaCommand;
      expect(cmd, contains('11434'));
      expect(cmd, contains('OLLAMA_YA_ACTIVO'));
      expect(cmd, contains('nohup ollama serve'));
      expect(cmd, contains('OLLAMA_INICIADO'));
      expect(cmd, contains('OLLAMA_ERROR'));
    });

    test('startOllamaCommand fija el entorno Termux', () {
      final cmd = AgentRuntimeConsts.startOllamaCommand;
      expect(cmd, contains('/data/data/com.termux/files/usr'));
      expect(cmd, contains('/data/data/com.termux/files/home'));
    });

    test('ollamaPullCommand incluye el tag del modelo', () {
      final cmd = AgentRuntimeConsts.ollamaPullCommand('phi3:mini');
      expect(cmd, contains('ollama pull'));
      expect(cmd, contains('phi3:mini'));
    });

    test('ollamaPullCommand usa tags distintos para modelos distintos', () {
      final a = AgentRuntimeConsts.ollamaPullCommand('qwen2.5:0.5b');
      final b = AgentRuntimeConsts.ollamaPullCommand('llama3.1:8b');
      expect(a, contains('qwen2.5:0.5b'));
      expect(b, contains('llama3.1:8b'));
      expect(a, isNot(contains('llama3.1:8b')));
    });

    test('ollamaPullCommand fija el entorno Termux', () {
      final cmd = AgentRuntimeConsts.ollamaPullCommand('mistral:7b');
      expect(cmd, contains('/data/data/com.termux/files/usr'));
      expect(cmd, contains('/data/data/com.termux/files/home'));
    });

    test('stopOllamaCommand envía TERM antes de KILL', () {
      final cmd = AgentRuntimeConsts.stopOllamaCommand;
      expect(cmd, contains('pkill -TERM ollama'));
      expect(cmd, contains('pkill -KILL ollama'));
    });

    test('stopOllamaCommand incluye sleep entre TERM y KILL', () {
      final cmd = AgentRuntimeConsts.stopOllamaCommand;
      final termIdx = cmd.indexOf('pkill -TERM ollama');
      final killIdx = cmd.indexOf('pkill -KILL ollama');
      final sleepIdx = cmd.indexOf('sleep 2');
      expect(sleepIdx, greaterThan(termIdx));
      expect(killIdx, greaterThan(sleepIdx));
    });

    test('stopOllamaCommand no falla si ollama no está activo (|| true)', () {
      final cmd = AgentRuntimeConsts.stopOllamaCommand;
      expect(cmd, contains('|| true'));
    });
  });

  group('LocalTermuxAgentProvider — ollama', () {
    test(
      'installOllama lanza runInTermux en background con comando correcto',
      () async {
        final fake = FakeAppBridge(termuxOk: true);
        final p = LocalTermuxAgentProvider(apps: fake);
        final result = await p.installOllama();
        expect(result, isTrue);
        expect(fake.lastTermuxCommand, contains('OLLAMA_INSTALADO'));
        expect(fake.lastTermuxCommand, contains('pkg install -y ollama'));
        expect(fake.lastTermuxBackground, isTrue);
      },
    );

    test(
      'startOllama lanza runInTermux en background con ollama serve',
      () async {
        final fake = FakeAppBridge(termuxOk: true);
        final p = LocalTermuxAgentProvider(apps: fake);
        await p.startOllama();
        expect(fake.lastTermuxCommand, contains('ollama serve'));
        expect(fake.lastTermuxBackground, isTrue);
      },
    );

    test(
      'pullOllamaModel lanza runInTermux en background con el tag correcto',
      () async {
        final fake = FakeAppBridge(termuxOk: true);
        final p = LocalTermuxAgentProvider(apps: fake);
        await p.pullOllamaModel('phi3:mini');
        expect(fake.lastTermuxCommand, contains('ollama pull'));
        expect(fake.lastTermuxCommand, contains('phi3:mini'));
        expect(fake.lastTermuxBackground, isTrue);
      },
    );

    test('configureWithOllama llama configureAgent con provider ollama, '
        'apiKey vacío y baseUrl :11434', () async {
      final fake = FakeAppBridge(termuxOk: true);
      final p = LocalTermuxAgentProvider(apps: fake);
      await p.configureWithOllama('phi3:mini');
      final cmd = fake.lastTermuxCommand!;
      // Los valores se codifican en base64 (ver writeConfigCommand).
      expect(cmd, contains('config.yaml'));
      expect(cmd, contains(base64.encode(utf8.encode('custom'))));
      expect(cmd, contains(base64.encode(utf8.encode('phi3:mini'))));
      expect(
        cmd,
        contains(base64.encode(utf8.encode('http://127.0.0.1:11434/v1'))),
      );
      // api_key vacío → sin campo api_key en el yaml
      expect(cmd, isNot(contains('api_key')));
      expect(fake.lastTermuxBackground, isTrue);
    });

    test('isOllamaRunning devuelve false cuando ollama no responde', () async {
      final p = LocalTermuxAgentProvider(
        apps: FakeAppBridge(),
        client: MockClient((_) async => throw Exception('connection refused')),
      );
      expect(await p.isOllamaRunning(), isFalse);
    });

    test(
      'isOllamaRunning devuelve true cuando :11434 responde con 2xx',
      () async {
        final p = LocalTermuxAgentProvider(
          apps: FakeAppBridge(),
          client: MockClient(
            (_) async => http.Response('Ollama is running', 200),
          ),
        );
        expect(await p.isOllamaRunning(), isTrue);
      },
    );

    test(
      'isOllamaModelAvailable detecta el modelo por prefijo en /api/tags',
      () async {
        final p = LocalTermuxAgentProvider(
          apps: FakeAppBridge(),
          client: MockClient((req) async {
            if (req.url.path == '/api/tags') {
              return http.Response(
                '{"models":[{"name":"phi3:mini","size":2200000000}]}',
                200,
              );
            }
            return http.Response('', 404);
          }),
        );
        expect(await p.isOllamaModelAvailable('phi3:mini'), isTrue);
        expect(await p.isOllamaModelAvailable('mistral:7b'), isFalse);
      },
    );

    test(
      'stopOllama lanza runInTermux en background con pkill ollama',
      () async {
        final fake = FakeAppBridge(termuxOk: true);
        final p = LocalTermuxAgentProvider(apps: fake);
        await p.stopOllama();
        expect(fake.lastTermuxCommand, contains('pkill'));
        expect(fake.lastTermuxCommand, contains('ollama'));
        expect(fake.lastTermuxBackground, isTrue);
      },
    );
  });

  group('AgentRuntimeConsts — startAgentCommand con Mobile Bridge', () {
    test('startAgentCommand arranca el dashboard en :9119 (API real)', () {
      final s = AgentRuntimeConsts.startAgentCommand;
      expect(s, contains('dashboard --no-open --skip-build --port 9119'));
    });

    test('startAgentCommand NO arranca el gateway de mensajería (:8642)', () {
      // `hermes gateway` es mensajería (no expone HTTP en :8642); arrancarlo solo
      // generaba zombies. La API la sirve el dashboard. No debe lanzarse.
      final s = AgentRuntimeConsts.startAgentCommand;
      expect(s, isNot(contains('gateway run :8642')));
    });

    test('startAgentCommand guarda el PID del dashboard', () {
      final s = AgentRuntimeConsts.startAgentCommand;
      expect(s, contains('dashboard.pid'));
    });

    test('startAgentCommand intenta arrancar el bridge en puerto 9131', () {
      final s = AgentRuntimeConsts.startAgentCommand;
      expect(s, contains('9131'));
      expect(s, contains('hermes_bridge.py'));
    });

    test(
      'startAgentCommand usa --bind 127.0.0.1 para el bridge (solo local)',
      () {
        final s = AgentRuntimeConsts.startAgentCommand;
        expect(s, contains('--bind 127.0.0.1'));
      },
    );

    test(
      'startAgentCommand guarda PID del bridge para no duplicar instancias',
      () {
        final s = AgentRuntimeConsts.startAgentCommand;
        expect(s, contains('bridge.pid'));
      },
    );

    test('startAgentCommand no bloquea si el script del bridge no existe', () {
      // El bucle for busca rutas conocidas; si ninguna existe, sigue sin error.
      final s = AgentRuntimeConsts.startAgentCommand;
      expect(s, contains('[ -f '));
      expect(s, contains('echo STARTED'));
    });

    test(
      'startAgentCommand usa venv de hermes si está disponible para python',
      () {
        final s = AgentRuntimeConsts.startAgentCommand;
        // La variable VENV apunta al venv del instalador; el comando usa $VENV/bin/python3
        expect(s, contains('VENV'));
        expect(s, contains('BPYTHON'));
      },
    );

    // Bug 2: el PATH debe priorizar el venv para que `python3`/`hermes` no caigan
    // en el binario del sistema (que no tiene hermes_cli → dashboard sin web_dist).
    test('startAgentCommand antepone el venv al PATH (Bug 2)', () {
      final s = AgentRuntimeConsts.startAgentCommand;
      expect(s, contains(r'export PATH="$VENV/bin:'));
      // La resolución de web_dist usa el python del venv, no el del sistema.
      expect(s, contains(r'VPYTHON="$VENV/bin/python3"'));
      expect(s, contains(r'"$VPYTHON" -c'));
      expect(s, isNot(contains(r'HERMES_PKG="$(python3 -c')));
    });

    test('startAgentCommand expone el servidor de diagnóstico en :8645', () {
      final s = AgentRuntimeConsts.startAgentCommand;
      // Tras arrancar el dashboard, sirve ~/.hermes (gateway.out) ~60 s para que
      // la Consola pueda diagnosticar fallos de arranque.
      expect(s, contains('http.server 8645'));
      expect(s, contains(r'--directory "$HOME/.hermes"'));
    });
  });

  group('AgentRuntimeConsts — stopAgentCommand (PATH venv)', () {
    test('stopAgentCommand incluye el venv en el PATH (mismo que start)', () {
      final c = AgentRuntimeConsts.stopAgentCommand;
      expect(c, contains('venv/bin'));
      expect(c, contains(r'export PATH='));
    });
  });
}
