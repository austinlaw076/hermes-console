// Adaptador de plataforma para apps externas e instalación del agente local.
//
// La UI y los providers NUNCA tocan intents directamente: pasan por esta
// interfaz. La impl real usa un MethodChannel nativo ("hermes/android_apps")
// para detectar/abrir paquetes y lanzar Termux, y `url_launcher` para los
// enlaces de F-Droid. En tests se inyecta una implementación falsa.
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Contrato de operaciones sobre apps externas (mockeable en tests).
abstract class AppBridge {
  /// ¿Está instalado el paquete? (PackageManager).
  Future<bool> isInstalled(String package);

  /// Abre la app por su paquete. Devuelve false si no se pudo.
  Future<bool> launch(String package);

  /// Lanza un comando en Termux (RUN_COMMAND). Best-effort: false si no es
  /// posible (Termux sin allow-external-apps / sin permiso).
  ///
  /// [background] true (por defecto): corre sin abrir terminal; la app muestra
  /// el progreso leyendo el log por localhost. La app no debe usar false en
  /// flujos de usuario.
  Future<bool> runInTermux(String command, {bool background = true});

  /// Abre Termux como ACTIVIDAD en primer plano ejecutando [command]. A
  /// diferencia de [runInTermux] (que usa RunCommandService y EXIGE
  /// allow-external-apps), TermuxActivity acepta los extras de comando sin esa
  /// propiedad, así que es la vía para el bootstrap que precisamente la activa.
  /// Best-effort: false si Termux no está o el intent no se resuelve.
  Future<bool> launchTermuxForeground(String command);

  /// Ejecuta [command] en Termux y DEVUELVE su stdout (vía el PendingIntent de
  /// resultado de RUN_COMMAND). A diferencia de [runInTermux] (fire-and-forget),
  /// permite SONDEAR el sistema de archivos de Termux —p. ej. saber si el agente
  /// Hermes está instalado aunque esté parado—, algo imposible desde la app de
  /// otro modo. Devuelve null si Termux no responde, falta el permiso/propiedad
  /// allow-external-apps, o se agota el tiempo. El comando debe ser corto y sin
  /// efectos (idempotente): es una sonda, no una acción.
  Future<String?> probeTermux(String command);

  /// Abre la ficha de F-Droid del paquete: intenta `market://` y cae a la web.
  Future<bool> installFromFDroid(String package);

  /// Características del dispositivo (RAM, ABIs) para filtrar modelos.
  Future<DeviceInfo> deviceInfo();
}

/// Características del dispositivo relevantes para la inferencia local.
class DeviceInfo {
  final int totalRamBytes;
  final int availRamBytes;
  final List<String> abis;
  final int freeDiskBytes;

  const DeviceInfo({
    required this.totalRamBytes,
    required this.availRamBytes,
    required this.abis,
    this.freeDiskBytes = 0,
  });

  double get totalRamGb => totalRamBytes / (1024 * 1024 * 1024);
  double get freeDiskGb => freeDiskBytes / (1024 * 1024 * 1024);
  bool get isArm64 => abis.contains('arm64-v8a');

  /// 64 bits (arm64 o x86_64): requisito mínimo para el agente local.
  bool get is64bit =>
      abis.any((a) => a == 'arm64-v8a' || a == 'x86_64' || a == 'arm64');
  bool get known => totalRamBytes > 0;

  static const DeviceInfo unknown = DeviceInfo(
    totalRamBytes: 0,
    availRamBytes: 0,
    abis: [],
  );
}

/// Implementación real sobre el MethodChannel nativo + url_launcher.
class AndroidApps implements AppBridge {
  static const MethodChannel _channel = MethodChannel('hermes/android_apps');

  const AndroidApps();

  @override
  Future<bool> isInstalled(String package) async {
    try {
      final ok = await _channel.invokeMethod<bool>('isInstalled', {
        'package': package,
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> launch(String package) async {
    try {
      final ok = await _channel.invokeMethod<bool>('launch', {
        'package': package,
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> runInTermux(String command, {bool background = true}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('runInTermux', {
        'command': command,
        'background': background,
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<String?> probeTermux(String command) async {
    try {
      return await _channel.invokeMethod<String>('probeTermux', {
        'command': command,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> launchTermuxForeground(String command) async {
    try {
      final ok = await _channel.invokeMethod<bool>('launchTermuxForeground', {
        'command': command,
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> installFromFDroid(String package) async {
    final market = Uri.parse('market://details?id=$package');
    if (await canLaunchUrl(market)) {
      if (await launchUrl(market, mode: LaunchMode.externalApplication)) {
        return true;
      }
    }
    return launchUrl(
      fdroidWebUrl(package),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Future<DeviceInfo> deviceInfo() async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('deviceInfo');
      if (m == null) return DeviceInfo.unknown;
      return DeviceInfo(
        totalRamBytes: (m['totalRamBytes'] as num?)?.toInt() ?? 0,
        availRamBytes: (m['availRamBytes'] as num?)?.toInt() ?? 0,
        abis:
            (m['abis'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        freeDiskBytes: (m['freeDiskBytes'] as num?)?.toInt() ?? 0,
      );
    } on PlatformException {
      return DeviceInfo.unknown;
    } on MissingPluginException {
      return DeviceInfo.unknown;
    }
  }

  /// URL web de la ficha de F-Droid (fallback cuando no hay cliente F-Droid).
  static Uri fdroidWebUrl(String package) =>
      Uri.parse('https://f-droid.org/en/packages/$package/');
}
