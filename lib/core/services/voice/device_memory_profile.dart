import 'dart:io';

/// Perfil de memoria del dispositivo (spec 048/US4).
///
/// Decide si los modelos pesados de voz (Sherpa/Whisper + Piper/ONNX) pueden
/// permanecer residentes entre turnos. La lectura es de `/proc/meminfo` (sin
/// permisos ni dependencias) y cualquier fallo degrada a "no elegible", que
/// conserva la serialización protectora vigente.
class DeviceMemoryProfile {
  const DeviceMemoryProfile({required this.memTotalBytes});

  final int memTotalBytes;

  /// Umbral conservador: 7,5 GiB de RAM total. El estado caliente medido en la
  /// Spec 044 rondó 1,6-1,9 GB de PSS/RSS; por debajo de este umbral no hay
  /// evidencia de margen y se mantiene la serialización.
  static const int residencyThresholdBytes = 7864320 * 1024; // 7,5 GiB

  bool get residencyEligible => memTotalBytes >= residencyThresholdBytes;

  static final RegExp _memTotal = RegExp(r'^MemTotal:\s*(\d+)\s*kB');

  /// Lee el total de memoria una vez. [meminfoPath] es inyectable en tests.
  static DeviceMemoryProfile read({String meminfoPath = '/proc/meminfo'}) {
    try {
      for (final line in File(meminfoPath).readAsLinesSync()) {
        final match = _memTotal.firstMatch(line.trim());
        if (match != null) {
          return DeviceMemoryProfile(
            memTotalBytes: int.parse(match.group(1)!) * 1024,
          );
        }
      }
    } catch (_) {
      // Ilegible/corrupto → no elegible, sin excepciones.
    }
    return const DeviceMemoryProfile(memTotalBytes: 0);
  }
}
