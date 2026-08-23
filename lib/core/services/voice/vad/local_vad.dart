// VAD local por ventanas fijas (spec 025 F2). Trocea el stream PCM16LE del
// micrófono en ventanas de tamaño fijo (512 muestras a 16kHz por defecto —
// el mismo `windowSize` que usa el modelo Silero), las pasa por un detector
// inyectable y aplica un hangover para decidir cuándo empieza y termina un
// turno de voz.
//
// Determinismo: el hangover se mide en MUESTRAS consumidas del propio flujo
// de audio, no en wall-clock. El mismo audio produce siempre los mismos
// eventos, sea cual sea la velocidad real del reloj (dispositivo o test) —
// eso es lo que lo hace testeable sin `Timer` ni reloj falso.
//
// El detector real (Silero vía sherpa-onnx) vive en [SileroVadDetector] y se
// resuelve con [LocalVad.withSilero], reutilizando la descarga que ya
// gestiona `SherpaSttModelManager` (stt_sherpa.dart) — NO se duplica lógica
// de descarga aquí. Los tests unitarios usan un detector falso inyectado
// directamente en el constructor de [LocalVad].
import 'dart:async';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../stt_sherpa.dart' show SherpaSttModelManager;

/// Ventana estándar de análisis a 16kHz: 512 muestras = 32ms, la misma que
/// usa `SileroVadModelConfig.windowSize` por defecto.
const int kLocalVadWindowSize = 512;

/// Qué representa un [VadEvent].
enum VadEventKind { speechStart, speechEnd }

/// Evento tipado de la máquina habla/silencio de [LocalVad]. Constructores
/// con nombre: `VadEvent.speechStart()` / `VadEvent.speechEnd(voicedSecs)`.
class VadEvent {
  final VadEventKind kind;

  /// Solo tiene sentido en `speechEnd`: segundos de audio clasificado como
  /// voz durante el turno (suma de ventanas con voz — misma semántica que
  /// `voiced_secs` del servidor de referencia, spec 024:
  /// el servidor STT compatible descrito en docs/UPSTREAM_CONTRACT.md).
  final double voicedSecs;

  const VadEvent.speechStart()
      : kind = VadEventKind.speechStart,
        voicedSecs = 0;

  const VadEvent.speechEnd(this.voicedSecs) : kind = VadEventKind.speechEnd;

  @override
  bool operator ==(Object other) =>
      other is VadEvent && other.kind == kind && other.voicedSecs == voicedSecs;

  @override
  int get hashCode => Object.hash(kind, voicedSecs);

  @override
  String toString() => kind == VadEventKind.speechStart
      ? 'VadEvent.speechStart()'
      : 'VadEvent.speechEnd(${voicedSecs.toStringAsFixed(2)}s)';
}

/// Detector inyectable: decide si una ventana de [kLocalVadWindowSize]
/// muestras (Float32, normalizadas a [-1,1]) contiene voz. Se llama una vez
/// por ventana completa, en orden.
typedef VadWindowDetector = bool Function(Float32List window);

/// VAD local: consume un `Stream<Uint8List>` de PCM16LE 16kHz mono (p.ej. el
/// que entrega `AudioRecorder.startStream`), lo trocea en ventanas fijas y
/// emite [VadEvent] según el detector [isSpeech] inyectado.
///
/// - `speechStart`: primera ventana con voz tras estar en silencio.
/// - `speechEnd(voicedSecs)`: llevamos [hangover] sin ventana con voz tras
///   haber visto voz; `voicedSecs` es la suma de ventanas con voz del turno.
///
/// Sin dependencia de reloj real: todo el estado se deriva de muestras
/// consumidas, así que el mismo stream produce siempre la misma secuencia de
/// eventos.
class LocalVad {
  LocalVad({
    required this.isSpeech,
    this.hangover = const Duration(milliseconds: 600),
    this.sampleRate = 16000,
    this.windowSize = kLocalVadWindowSize,
    this.minSpeechWindows = 2,
    void Function()? onDispose,
  }) : _onDispose = onDispose; // ignore: prefer_initializing_formals

  /// Detector de voz por ventana (real o falso, según quien construya).
  final VadWindowDetector isSpeech;

  /// Silencio sostenido (sin ventana con voz) tras haber oído voz que cierra
  /// el turno y dispara `speechEnd`.
  final Duration hangover;

  final int sampleRate;
  final int windowSize;

  /// Ventanas CONSECUTIVAS con voz necesarias para confirmar el arranque de
  /// un turno (debounce de arranque). Filtra blips de ruido de una sola
  /// ventana que el detector clasifica como voz por error; una racha se
  /// rompe (vuelve a cero) en cuanto aparece una ventana sin voz antes de
  /// llegar al umbral, así que ruido intermitente corto nunca confirma turno
  /// ni emite nada. El detector real (Silero) ya aplica su propio
  /// `minSpeechDuration` internamente, pero el detector inyectado (p.ej. en
  /// tests) puede no hacerlo — este debounce es responsabilidad de
  /// [LocalVad], no del detector.
  final int minSpeechWindows;

  final void Function()? _onDispose;

  final StreamController<VadEvent> _events =
      StreamController<VadEvent>.broadcast();

  /// Eventos speechStart/speechEnd derivados del stream adjunto con [attach].
  Stream<VadEvent> get events => _events.stream;

  StreamSubscription<Uint8List>? _sub;

  // Bytes sobrantes de un chunk que no llega a completar una ventana entera
  // (el stream del micro no promete tamaños múltiplos de `windowSize`).
  Uint8List _carry = Uint8List(0);

  bool _inSpeech = false;
  int _voicedWindows = 0;
  int _silentSamplesSinceVoice = 0;

  // Racha de ventanas consecutivas con voz mientras el turno todavía no está
  // confirmado (ver [minSpeechWindows]).
  int _consecutiveVoiced = 0;

  int get _hangoverSamples => (hangover.inMilliseconds * sampleRate) ~/ 1000;

  /// Empieza a consumir `stream`. Sustituye cualquier adjunto previo (y
  /// reinicia el estado del turno en curso, si lo había).
  void attach(Stream<Uint8List> stream) {
    detach();
    _resetTurnState();
    _sub = stream.listen(_onBytes, onDone: detach);
  }

  /// Deja de escuchar el stream actual. [events] sigue abierto: se puede
  /// volver a llamar [attach] con otro stream (p.ej. tras una reconexión).
  void detach() {
    _sub?.cancel();
    _sub = null;
    _carry = Uint8List(0);
  }

  /// Libera recursos definitivamente (cierra [events] y el detector, si
  /// [onDispose] lo gestiona — ver [LocalVad.withSilero]).
  void dispose() {
    detach();
    _events.close();
    _onDispose?.call();
  }

  void _resetTurnState() {
    _inSpeech = false;
    _voicedWindows = 0;
    _silentSamplesSinceVoice = 0;
    _consecutiveVoiced = 0;
  }

  void _onBytes(Uint8List bytes) {
    final merged = _carry.isEmpty
        ? bytes
        : (Uint8List(_carry.length + bytes.length)
          ..setRange(0, _carry.length, _carry)
          ..setRange(_carry.length, _carry.length + bytes.length, bytes));

    final bytesPerWindow = windowSize * 2; // PCM16LE = 2 bytes/muestra
    var offset = 0;
    while (merged.length - offset >= bytesPerWindow) {
      _processWindow(_pcm16ToFloat(merged, offset, windowSize));
      offset += bytesPerWindow;
    }
    _carry = offset == merged.length
        ? Uint8List(0)
        : Uint8List.sublistView(merged, offset);
  }

  void _processWindow(Float32List window) {
    final speech = isSpeech(window);

    if (!_inSpeech) {
      // Turno todavía sin confirmar: buscamos [minSpeechWindows] ventanas
      // CONSECUTIVAS con voz. Cualquier ventana sin voz antes de llegar al
      // umbral rompe la racha (ruido intermitente corto → nunca confirma,
      // nunca emite nada).
      if (!speech) {
        _consecutiveVoiced = 0;
        return;
      }
      _consecutiveVoiced++;
      if (_consecutiveVoiced < minSpeechWindows) return;
      _inSpeech = true;
      _voicedWindows = _consecutiveVoiced; // incluye las de confirmación
      _silentSamplesSinceVoice = 0;
      _consecutiveVoiced = 0;
      _emit(const VadEvent.speechStart());
      return;
    }

    // Turno confirmado: contamos ventanas con voz y aplicamos el hangover.
    if (speech) {
      _voicedWindows++;
      _silentSamplesSinceVoice = 0;
      return;
    }
    _silentSamplesSinceVoice += windowSize;
    if (_silentSamplesSinceVoice >= _hangoverSamples) {
      final voicedSecs = _voicedWindows * windowSize / sampleRate;
      _resetTurnState();
      _emit(VadEvent.speechEnd(voicedSecs));
    }
  }

  void _emit(VadEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  /// PCM16LE → Float32 [-1,1] (misma conversión que stt_sherpa.dart).
  static Float32List _pcm16ToFloat(
      Uint8List bytes, int byteOffset, int sampleCount) {
    final out = Float32List(sampleCount);
    final bd = ByteData.sublistView(bytes);
    for (var i = 0; i < sampleCount; i++) {
      out[i] = bd.getInt16(byteOffset + i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  /// Construye un [LocalVad] con el detector real (Silero vía sherpa-onnx),
  /// reutilizando la descarga de [SherpaSttModelManager] (comparte el mismo
  /// `silero_vad.onnx` que el STT on-device — ver `stt_sherpa.dart`, no
  /// duplica la gestión de descarga). Devuelve `null` si el modelo VAD
  /// todavía no está descargado: el llamador decide si dispara la descarga o
  /// hace fallback a otro motor (N1 remoto).
  static Future<LocalVad?> withSilero({
    SherpaSttModelManager? manager,
    Duration hangover = const Duration(milliseconds: 600),
    int sampleRate = 16000,
  }) async {
    final mgr = manager ?? SherpaSttModelManager();
    if (!await mgr.sileroReady()) return null;
    final detector = SileroVadDetector(await mgr.sileroPath(), sampleRate);
    return LocalVad(
      isSpeech: detector.call,
      hangover: hangover,
      sampleRate: sampleRate,
      onDispose: detector.free,
    );
  }
}

/// Detector real basado en Silero VAD (sherpa-onnx). Encapsula el
/// `sherpa.VoiceActivityDetector` nativo: alimenta cada ventana con
/// `acceptWaveform` (igual que `SherpaSttEngine._buildVad`/`_onAudio` en
/// stt_sherpa.dart) y expone `isDetected()` como una decisión booleana por
/// ventana. Los segmentos que el motor nativo agrupa por su cuenta se
/// descartan en cada llamada: [LocalVad] lleva su propio hangover y su
/// propio cómputo de `voicedSecs`, así que no los necesita.
///
/// Instancia "callable" (define `call`): se puede pasar directamente donde
/// se espera un [VadWindowDetector].
class SileroVadDetector {
  SileroVadDetector(String sileroModelPath, [int sampleRate = 16000]) {
    if (!_bindingsReady) {
      sherpa.initBindings();
      _bindingsReady = true;
    }
    _vad = sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: sileroModelPath,
          minSilenceDuration: 0.25,
          minSpeechDuration: 0.20,
          maxSpeechDuration: 12.0,
        ),
        sampleRate: sampleRate,
        numThreads: 1,
        debug: false,
      ),
      bufferSizeInSeconds: 30,
    );
  }

  // `sherpa.initBindings()` debe llamarse una sola vez por proceso (según su
  // propio contrato); este flag es independiente del de SherpaSttEngine
  // (misma idea, cada uno guarda el suyo — llamarlo dos veces con la
  // biblioteca ya cargada es inocuo, pero evitamos el trabajo repetido).
  static bool _bindingsReady = false;

  late final sherpa.VoiceActivityDetector _vad;
  bool _freed = false;

  bool call(Float32List window) {
    _vad.acceptWaveform(window);
    _vad.clear(); // no usamos los segmentos que agrupa por su cuenta
    return _vad.isDetected();
  }

  /// Libera el detector nativo. Idempotente.
  void free() {
    if (_freed) return;
    _freed = true;
    _vad.free();
  }
}
