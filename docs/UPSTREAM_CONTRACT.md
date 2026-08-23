# Contrato con upstream (Hermes Agent / Nous)

Hermes Console es un **cliente** de un agente de terceros self-hosted (Hermes,
de Nous Research). Por tanto, inevitablemente "sigue" a Hermes: si Nous cambia
su API, CLI, instalador o puertos, hay que actualizar la app. Este documento
lista **exactamente qué depende de upstream y dónde tocarlo**, para que mantener
sea un cambio de una línea y no una caza del tesoro.

Principio de diseño: **fallar suave, no petar.** Toda dependencia de upstream
debe degradar a un estado honesto ("no disponible", "necesita X") en vez de
crashear. La adaptación y sus límites se describen en
[`ARCHITECTURE.md`](ARCHITECTURE.md) y en la matriz de capacidades de este
documento.

Fuentes de verdad del contrato (no inventar endpoints):
- `docs/API_AUDIT.md` — endpoints reales de hermes-agent (sondeados en vivo).
- `../docs/MOBILE_BRIDGE_SPEC.md` (workspace) — contrato del Mobile Bridge.

---

## 1. Puertos y endpoints (loopback / red)

| Qué | Valor | Dónde en el código |
|---|---|---|
| Gateway (API server, Bearer) | `:8642` | `AgentRuntimeConsts.localGatewayPort`; `SavedConnection.baseUrl` |
| Dashboard / Admin (API web) | `:9119` | `AgentRuntimeConsts.localDashboardPort`; `dashboardUrl` |
| Mobile Bridge | `:9131` (deriva del host) | `BridgeManager.derivedBridgeUrl` |
| Progreso de instalación (local) | `:8643` | `AgentRuntimeConsts.localInstallPort` |

Si Hermes cambia un puerto por defecto → actualizar la constante correspondiente.

## 2. Dashboard API (lo que usa la app)

`DashboardClient` / `ConnectionManager`. Auth: token de sesión scrapeado del
HTML (`window.__HERMES_SESSION_TOKEN__`), enviado en `X-Hermes-Session-Token`.
Endpoints usados: `/api/status`, `/api/profiles` (+`/{name}/soul`, POST/PATCH/
DELETE), `/api/skills`, `/api/model/info|options|set`, `/api/cron/jobs`,
`/api/logs`, `/api/config`, `/api/env`, `/api/sessions`. Escalado por perfil con
`?profile=`. **Si un endpoint cambia de forma/nombre**, está centralizado en
`connection_manager.dart` (buscar `apiGet/apiPost('...')`).

⚠️ **Modelo principal NO se aísla por perfil**: `POST /api/model/set?profile=X`
cambia el modelo del gateway en ejecución (hay un solo gateway). La app avisa
antes (confirmación en `profiles_screen` y `models_screen`). No es un bug de la
app, es la semántica de Hermes.

## 3. Gateway API (Bearer = `API_SERVER_KEY`)

`/v1/runs` (+`/{id}`, `/{id}/approval`), `/v1/capabilities`, `/v1/skills`,
`/v1/toolsets`, chat SSE. El gateway NO lista runs (405) ni los conserva tras
completar (404 expired) → registro local en `RunRegistry`. Ver `API_AUDIT.md`.

## 4. Mobile Bridge (`bridge/hermes_bridge.py`)

Provisión automática con la `API_SERVER_KEY` (`POST /bridge/provision`). Token
del bridge persistente (sobrevive reinicios). Gestiona skills/SOUL/memoria/cron.

⚠️ **Comandos de skills**: el bridge DEBE usar el CLI de Hermes, no `npx skills`
(que NO toca el almacén de skills de Hermes y da falso éxito). Correcto:
- instalar: `hermes skills install --yes <owner/repo>`
- quitar: `hermes skills uninstall <name>` (pide [y/N], sin flag --yes → se pasa
  "y" por stdin; OJO: devuelve rc=0 también si se cancela → éxito por el texto
  "Uninstalled"). Ver `skills_install`/`skills_remove` en `hermes_bridge.py`.

El dashboard debe correr como **servicio systemd** (`hermes-dashboard.service`),
no como proceso manual, o `hermes update` lo tira. Gateway/bridge ya son
servicios.

## 5. Instalador del agente local

| Qué | Valor | Dónde |
|---|---|---|
| URL del instalador | `hermes-agent.nousresearch.com/install.sh` | `AgentRuntimeConsts.installerUrl` |
| Wrapper (sirve log por localhost) | — | `AgentRuntimeConsts.installWrapperCommand` |
| Etapas (parseo del log) | palabras clave | `_stages` en `local_install_screen.dart` |

El **fin de la instalación NO depende del parseo**: se detecta cuando el agente
responde en `localhost:8642` (`isAgentRunning`). Si el instalador cambia su
salida, la barra de etapas se desincroniza pero la app sigue detectando bien el
fin. Las etapas son "best-effort" cosméticas. Si quieres re-afinar la barra,
toca solo `_stages`.

Pre-flight antes de instalar (`_init`): ABI 64-bit, ~3 GB de disco
(`deviceInfo().freeDiskBytes`, vía `StatFs` nativo en `MainActivity.kt`), y red
(`installerReachable()`). Errores con causa: `_friendlyError` (espacio/red/
libcrypto/rust).

## 5b. Voz neuronal on-device (TTS, modelos de HuggingFace)

La voz que LEE las respuestas puede ser neuronal y 100% on-device (sin nube, sin
clave) vía `sherpa_onnx` + un modelo Piper/VITS descargado en runtime.

| Qué | Valor | Dónde |
|---|---|---|
| Catálogo de voces (ES) | id/url/dirName/onnxFile | `kNeuralVoices` en `tts_model_manager.dart` |
| Origen de los modelos | release `tts-models` de sherpa-onnx (.tar.bz2) | `_ttsRelease` |
| Motor de síntesis | `OnDeviceNeuralTtsEngine` | `tts_engine.dart` |

Cada voz es un único `.tar.bz2` con `<voz>.onnx` + `tokens.txt` +
`espeak-ng-data/`. Se descarga con progreso a disco y se **extrae en un isolate**
(`_extractTarBz2`, bzip2+tar vía `package:archive`). **Fallar suave**: si la voz
elegida no está descargada, `VoiceService._buildOnnxEngine` cae a la voz del
sistema (`DeviceTtsEngine`) en vez de petar. Para añadir una voz: una entrada más
en `kNeuralVoices` (verificar que la URL existe en el release y que `dirName`/
`onnxFile` casan con el contenido del tar). Las libs nativas (`libonnxruntime.so`,
`libsherpa-onnx-*.so`) las aporta el plugin; suben ~30 MB por ABI → **publicar como
AAB / split-per-abi**, no APK universal.

## 6. Termux

`allow-external-apps=true` (en `~/.termux/termux.properties`) es necesario para
RUN_COMMAND. **La app no puede activarlo** (sandbox de Android); guía al usuario
una vez. Paquete `com.termux`; enlace de instalación: F-Droid
(`f-droid.org/packages/com.termux/`), no Google Play (obsoleto).

---

## Checklist "Hermes cambió algo, ¿qué toco?"

- Endpoint del Dashboard → `connection_manager.dart` (+ `API_AUDIT.md`).
- Comando de skills del bridge → `bridge/hermes_bridge.py` (`_hermes()`).
- URL del instalador → `AgentRuntimeConsts.installerUrl`.
- Texto del instalador (barra de progreso) → `_stages` (no bloquea el fin).
- Puerto → `AgentRuntimeConsts` / `BridgeManager`.
- Forma de un payload → el `*.fromJson` correspondiente (parseo defensivo).
