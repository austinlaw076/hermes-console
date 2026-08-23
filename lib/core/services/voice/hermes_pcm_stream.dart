import 'dart:async';

import 'package:flutter/services.dart';

/// Formato publicado por `/api/audio/speak-stream`.
///
/// Hermes Agent main produce PCM signed int16 little-endian. El servidor
/// publica frecuencia y canales en el frame `start`; Android valida ambos
/// antes de crear el AudioTrack para que un servidor roto no pueda reservar un
/// buffer arbitrario.
class HermesPcmFormat {
  const HermesPcmFormat({required this.sampleRate, required this.channels});

  static const int minSampleRate = 8000;
  static const int maxSampleRate = 96000;

  final int sampleRate;
  final int channels;

  bool get isSupported =>
      sampleRate >= minSampleRate &&
      sampleRate <= maxSampleRate &&
      channels == 1;
}

/// Fallo de un write nativo con telemetría suficiente para decidir si repetir.
///
/// [acceptedBytes] cuenta bytes que AudioTrack aceptó durante esa llamada.
/// [mayHavePlayed] también cubre PCM aceptado por llamadas anteriores. Si ambos
/// son falsos, el cliente puede usar el POST completo sin riesgo de duplicar
/// audio; de lo contrario debe conservar el resultado parcial.
class HermesPcmWriteException implements Exception {
  const HermesPcmWriteException({
    required this.acceptedBytes,
    required this.mayHavePlayed,
    required this.cause,
  });

  final int acceptedBytes;
  final bool mayHavePlayed;
  final Object cause;

  bool get acceptedAny => acceptedBytes > 0 || mayHavePlayed;

  @override
  String toString() =>
      'HermesPcmWriteException('
      'acceptedBytes: $acceptedBytes, mayHavePlayed: $mayHavePlayed, '
      'cause: $cause)';
}

/// Sink pequeño e inyectable para que el protocolo WebSocket no dependa del
/// MethodChannel en sus pruebas.
abstract interface class HermesPcmStreamSink {
  int get generation;

  Future<void> configure(HermesPcmFormat format);

  /// Aplica backpressure: el Future termina cuando AudioTrack ha aceptado el
  /// bloque, no simplemente cuando el MethodChannel lo ha encolado.
  Future<void> write(Uint8List pcm16le);

  /// Congela el mismo AudioTrack sin vaciar los frames ya aceptados.
  Future<void> pause();

  /// Continúa el AudioTrack pausado conservando exactamente su cola.
  Future<void> resume();

  /// Espera a que se reproduzcan los frames aceptados y libera AudioTrack.
  Future<void> finish();

  /// Corta, vacía e invalida la generación sin esperar al drenado.
  Future<void> stop();
}

typedef HermesPcmStreamSinkFactory = HermesPcmStreamSink Function();

/// Implementación Android sobre `AudioTrack.MODE_STREAM`.
///
/// Cada instancia recibe una generación monotónica. El lado nativo exige esa
/// generación en configure/write/pause/resume/finish/stop, por lo que una
/// respuesta tardía de un WebSocket cancelado no puede escribir en el
/// reproductor siguiente.
class MethodChannelHermesPcmStreamSink implements HermesPcmStreamSink {
  MethodChannelHermesPcmStreamSink({MethodChannel? channel, int? generation})
    : _channel = channel ?? const MethodChannel(channelName),
      generation = generation ?? _nextGeneration();

  static const String channelName = 'hermes/pcm_stream';
  static const int maxChunkBytes = 1024 * 1024;
  static int _generationSeed = 0;

  static int _nextGeneration() {
    _generationSeed += 1;
    return _generationSeed;
  }

  final MethodChannel _channel;

  @override
  final int generation;

  Future<void> _tail = Future<void>.value();
  Future<void> _controlTail = Future<void>.value();
  bool _configured = false;
  bool _finished = false;
  bool _paused = false;
  bool _pausedHandoffWriteClaimed = false;
  int _pendingWrites = 0;
  bool _stopped = false;

  Future<void> _serial(Future<void> Function() operation) {
    final previous = _tail;
    final current = previous.then<void>((_) async {
      if (_stopped) return;
      await operation();
    });
    _tail = current.then<void>((_) {}, onError: (_, _) {});
    return current;
  }

  Future<void> _serialControl(Future<void> Function() operation) {
    final previous = _controlTail;
    final current = previous.then<void>((_) async {
      if (_stopped) return;
      await operation();
    });
    _controlTail = current.then<void>((_) {}, onError: (_, _) {});
    return current;
  }

  @override
  Future<void> configure(HermesPcmFormat format) {
    if (_configured || _finished || _stopped) {
      return Future<void>.error(
        StateError('PCM stream cannot be configured in its current state'),
      );
    }
    if (!format.isSupported) {
      return Future<void>.error(
        ArgumentError(
          'Unsupported PCM format: '
          '${format.sampleRate} Hz, ${format.channels} channel(s)',
        ),
      );
    }
    _configured = true;
    return _serial(
      () => _channel.invokeMethod<void>('configure', {
        'generation': generation,
        'sample_rate': format.sampleRate,
        'channels': format.channels,
      }),
    );
  }

  @override
  Future<void> write(Uint8List pcm16le) {
    if (!_configured ||
        _finished ||
        (_paused && _pausedHandoffWriteClaimed) ||
        _stopped) {
      return Future<void>.error(StateError('PCM stream is not writable'));
    }
    if (pcm16le.isEmpty ||
        pcm16le.length.isOdd ||
        pcm16le.length > maxChunkBytes) {
      return Future<void>.error(
        ArgumentError(
          'PCM chunks must be non-empty, sample-aligned and at most '
          '$maxChunkBytes bytes',
        ),
      );
    }
    // Pause puede ganar la carrera después de que SpeechStream haya liberado
    // su gate pero antes de entrar aquí. Ese bloque ya está acotado y es el
    // único que se entrega al writer nativo, cuyo waitForUserResume lo retiene.
    // Una segunda llamada pausada se rechaza para no crear una cola Dart libre.
    _pendingWrites += 1;
    if (_paused) _pausedHandoffWriteClaimed = true;
    // Copia defensiva: el frame WebSocket puede reutilizar su backing buffer
    // después de que vuelva el callback.
    final bytes = Uint8List.fromList(pcm16le);
    final write = _serial(() async {
      try {
        final result = await _channel.invokeMapMethod<String, Object?>(
          'write',
          {'generation': generation, 'pcm': bytes},
        );
        if (result?['cancelled'] == true) {
          throw HermesPcmWriteException(
            acceptedBytes: 0,
            mayHavePlayed: false,
            cause: StateError('Native PCM write was cancelled'),
          );
        }
        final acceptedBytes = (result?['acceptedBytes'] as num?)?.toInt();
        final mayHavePlayed = result?['mayHavePlayed'] == true;
        if (acceptedBytes != bytes.length) {
          throw HermesPcmWriteException(
            acceptedBytes: acceptedBytes?.clamp(0, bytes.length).toInt() ?? 0,
            mayHavePlayed: mayHavePlayed,
            cause: StateError('Native PCM write returned incomplete telemetry'),
          );
        }
      } on PlatformException catch (error) {
        final details = error.details;
        if (details is! Map) rethrow;
        final acceptedBytes = (details['acceptedBytes'] as num?)?.toInt();
        final mayHavePlayed = details['mayHavePlayed'];
        if (acceptedBytes == null || mayHavePlayed is! bool) rethrow;
        throw HermesPcmWriteException(
          acceptedBytes: acceptedBytes.clamp(0, bytes.length).toInt(),
          mayHavePlayed: mayHavePlayed,
          cause: error,
        );
      }
    });
    return write.whenComplete(() {
      _pendingWrites -= 1;
    });
  }

  @override
  Future<void> pause() {
    if (!_configured || _stopped) {
      return Future<void>.error(StateError('PCM stream is not pausable'));
    }
    if (_paused) return _controlTail;
    _paused = true;
    // Si write ya entró, ese es el único bloque que Pause puede mantener. Si
    // aún no entró, queda un único permiso para cerrar la carrera del handoff.
    _pausedHandoffWriteClaimed = _pendingWrites > 0;
    // Control usa una cola separada: finish puede ocupar [_tail] mientras
    // drena, pero Pause debe alcanzar ese mismo AudioTrack inmediatamente.
    return _serialControl(
      () => _channel.invokeMethod<void>('pause', {'generation': generation}),
    );
  }

  @override
  Future<void> resume() {
    if (!_configured || _stopped) {
      return Future<void>.error(StateError('PCM stream is not resumable'));
    }
    if (!_paused) return _controlTail;
    _paused = false;
    _pausedHandoffWriteClaimed = false;
    return _serialControl(
      () => _channel.invokeMethod<void>('resume', {'generation': generation}),
    );
  }

  @override
  Future<void> finish() {
    if (!_configured || _stopped) return Future<void>.value();
    if (_paused) {
      return Future<void>.error(
        StateError('PCM stream must resume before finishing'),
      );
    }
    if (_finished) return _tail;
    _finished = true;
    return _serial(
      () => _channel.invokeMethod<void>('finish', {'generation': generation}),
    );
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _finished = true;
    _paused = false;
    _pausedHandoffWriteClaimed = false;
    // No espera [_tail]: stop debe poder liberar un AudioTrack cuyo write o
    // finish está bloqueado por backpressure. La generación hace inertes los
    // MethodChannel tardíos que ya estuviesen en vuelo.
    await _channel.invokeMethod<void>('stop', {'generation': generation});
  }
}
