import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/voice/sherpa_stt_worker.dart';
import 'package:hermes_android/core/services/voice/stt_engine.dart';
import 'package:hermes_android/core/services/voice/stt_sherpa.dart';
import 'package:hermes_android/core/services/voice/voice_latency_trace.dart';
import 'package:record/record.dart';

class _FakeManager extends SherpaSttModelManager {
  @override
  Future<String> tokensPath(SherpaSttModel model) async => '/model/tokens.txt';

  @override
  Future<String> encoderPath(SherpaSttModel model) async =>
      '/model/encoder.onnx';

  @override
  Future<String> decoderPath(SherpaSttModel model) async =>
      '/model/decoder.onnx';

  @override
  Future<String> joinerPath(SherpaSttModel model) async => '/model/joiner.onnx';

  @override
  Future<String> sileroPath() async => '/model/silero.onnx';
}

void _expectDesktopSpeechCaptureConfig() {
  expect(kSherpaSttRecordConfig.encoder, AudioEncoder.pcm16bits);
  expect(kSherpaSttRecordConfig.sampleRate, 16000);
  expect(kSherpaSttRecordConfig.numChannels, 1);
  expect(kSherpaSttRecordConfig.echoCancel, isTrue);
  expect(kSherpaSttRecordConfig.noiseSuppress, isTrue);
  expect(
    kSherpaSttRecordConfig.androidConfig.audioSource,
    AndroidAudioSource.voiceRecognition,
  );
}

class _FakeRuntime implements SherpaSttRuntime {
  final StreamController<Uint8List> audio =
      StreamController<Uint8List>.broadcast();

  int prepareCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  Completer<void>? startGate;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> modelReady() async => true;

  @override
  Future<void> prepare() async {
    prepareCalls++;
  }

  @override
  Future<Stream<Uint8List>> startStream() async {
    startCalls++;
    await startGate?.future;
    return audio.stream;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

class _FakeWorker implements SherpaSttWorker {
  final StreamController<SherpaSttWorkerUpdate> updatesController =
      StreamController<SherpaSttWorkerUpdate>.broadcast();
  Completer<void>? prepareGate;
  Completer<void>? flushGate;
  List<String> flushSegments = const [];
  List<String> acceptSegments = const [];

  final List<int> acceptedGenerations = [];
  final List<int> acceptedLengths = [];
  final List<int> flushGenerations = [];
  int prepareCalls = 0;
  int disposeCalls = 0;

  @override
  Stream<SherpaSttWorkerUpdate> get updates => updatesController.stream;

  @override
  Future<void> prepare() async {
    prepareCalls++;
    await prepareGate?.future;
  }

  @override
  void accept(Uint8List pcm16, {required int generation}) {
    acceptedGenerations.add(generation);
    acceptedLengths.add(pcm16.length);
    if (acceptSegments.isNotEmpty) {
      emit(generation: generation, segments: acceptSegments);
    }
  }

  @override
  Future<List<String>> flush({required int generation}) async {
    flushGenerations.add(generation);
    await flushGate?.future;
    return flushSegments;
  }

  void emit({
    required int generation,
    double level = 0.5,
    bool speechDetected = true,
    bool? acousticSpeechEvidence,
    List<String> segments = const [],
  }) {
    updatesController.add(
      SherpaSttWorkerUpdate(
        generation: generation,
        level: level,
        speechDetected: speechDetected,
        acousticSpeechEvidence:
            acousticSpeechEvidence ??
            (speechDetected && level >= SherpaDesktopSpeechGate.levelThreshold),
        segments: segments,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (!updatesController.isClosed) await updatesController.close();
  }
}

class _ManualVoiceTurnTimer implements Timer {
  _ManualVoiceTurnTimer(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _active ? 0 : 1;
}

class _ManualVoiceTurnTimers {
  final List<_ManualVoiceTurnTimer> created = [];

  Timer create(Duration duration, void Function() callback) {
    final timer = _ManualVoiceTurnTimer(duration, callback);
    created.add(timer);
    return timer;
  }
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

Uint8List _pcm16Wav(Uint8List pcm) {
  final wav = Uint8List(44 + pcm.length);
  final data = ByteData.sublistView(wav);

  void tag(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      wav[offset + index] = value.codeUnitAt(index);
    }
  }

  tag(0, 'RIFF');
  data.setUint32(4, 36 + pcm.length, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  data.setUint32(40, pcm.length, Endian.little);
  wav.setRange(44, wav.length, pcm);
  return wav;
}

SherpaSttEngine _engine(
  _FakeRuntime runtime,
  _FakeWorker worker, {
  void Function(SherpaSttWorkerConfig config)? onConfig,
  VoiceTurnTimerFactory? timerFactory,
}) => SherpaSttEngine(
  model: sherpaModelByKind(SherpaModelKind.whisperBase),
  manager: _FakeManager(),
  runtime: runtime,
  timerFactory: timerFactory,
  workerFactory: (config) async {
    onConfig?.call(config);
    return worker;
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dictado local captura habla con el preset acústico de Desktop', () {
    _expectDesktopSpeechCaptureConfig();
  });

  test('el gate Desktop rechaza picos aislados y exige mayoria 8 de 10', () {
    final gate = SherpaDesktopSpeechGate();
    final high = SherpaDesktopSpeechGate.levelThreshold + 0.01;
    final low = SherpaDesktopSpeechGate.levelThreshold - 0.01;

    for (final level in <double>[high, low, low, high, low, low, high, low]) {
      expect(gate.acceptLevelFrame(level), isFalse);
    }
    expect(gate.hasEvidence, isFalse);

    gate.reset();
    for (final level in <double>[
      high,
      high,
      low,
      high,
      high,
      high,
      low,
      high,
      high,
    ]) {
      expect(gate.acceptLevelFrame(level), isFalse);
    }
    expect(gate.acceptLevelFrame(high), isTrue);
    expect(gate.hasEvidence, isTrue);
  });

  test('el gate conserva frames de 30 ms entre chunks PCM desalineados', () {
    final gate = SherpaDesktopSpeechGate();
    final samples = Float32List(
      SherpaDesktopSpeechGate.frameSamples *
          SherpaDesktopSpeechGate.majorityWindow,
    );
    samples.fillRange(0, samples.length, 0.03);

    expect(
      gate.accept(
        Float32List.sublistView(samples, 0, 1000),
        speechDetected: true,
      ),
      isFalse,
    );
    expect(
      gate.accept(Float32List.sublistView(samples, 1000), speechDetected: true),
      isTrue,
    );
    expect(gate.hasEvidence, isTrue);
  });

  test('ruido sin Silero no prearma una alucinacion posterior', () {
    final gate = SherpaDesktopSpeechGate();
    final loudNoise = Float32List(
      SherpaDesktopSpeechGate.frameSamples *
          SherpaDesktopSpeechGate.majorityWindow,
    );
    loudNoise.fillRange(0, loudNoise.length, 0.08);

    expect(gate.accept(loudNoise, speechDetected: false), isFalse);
    expect(gate.hasEvidence, isFalse);

    final quietFalsePositive = Float32List(
      SherpaDesktopSpeechGate.frameSamples,
    );
    quietFalsePositive.fillRange(0, quietFalsePositive.length, 0.005);
    expect(gate.accept(quietFalsePositive, speechDetected: true), isFalse);
    expect(gate.hasEvidence, isFalse);
  });

  test('publica capture ready solo después del ACK de startStream', () async {
    final runtime = _FakeRuntime()..startGate = Completer<void>();
    final worker = _FakeWorker();
    final engine = _engine(runtime, worker);
    var readyCalls = 0;

    final done = engine
        .listen(onCaptureReady: () => readyCalls++)
        .drain<void>();
    await _waitFor(() => runtime.startCalls == 1);
    expect(readyCalls, 0);

    runtime.startGate!.complete();
    await _waitFor(() => readyCalls == 1);

    await engine.stop();
    await done.timeout(const Duration(seconds: 1));
    await engine.dispose();
    await runtime.audio.close();
  });

  test('cierra a los 12 s sin proyectar fin de habla inexistente', () async {
    final timers = _ManualVoiceTurnTimers();
    final runtime = _FakeRuntime();
    final worker = _FakeWorker();
    var speechEnds = 0;
    final engine = _engine(runtime, worker, timerFactory: timers.create);
    final done = engine.listen(onSpeechEnd: () => speechEnds++).drain<void>();
    await _waitFor(() => runtime.startCalls == 1 && timers.created.isNotEmpty);

    expect(timers.created.single.duration, kVoiceTurnIdleSilenceTimeout);
    timers.created.single.fire();

    await _waitFor(() => runtime.stopCalls == 1);
    await done.timeout(const Duration(seconds: 1));
    expect(speechEnds, 0);

    await engine.dispose();
    await runtime.audio.close();
  });

  test('la primera detección de voz cancela el idle', () async {
    final timers = _ManualVoiceTurnTimers();
    final runtime = _FakeRuntime();
    final worker = _FakeWorker();
    final engine = _engine(runtime, worker, timerFactory: timers.create);
    final done = engine.listen().drain<void>();
    await _waitFor(
      () =>
          runtime.startCalls == 1 &&
          worker.prepareCalls == 1 &&
          timers.created.isNotEmpty,
    );

    worker.emit(generation: 1, speechDetected: true);
    await Future<void>.delayed(Duration.zero);
    expect(timers.created.single.isActive, isFalse);
    timers.created.single.fire();
    expect(runtime.stopCalls, 0);

    await engine.stop();
    await done.timeout(const Duration(seconds: 1));
    await engine.dispose();
    await runtime.audio.close();
  });

  test('Sherpa traza última voz, endpoint, STT y final causalmente', () async {
    final runtime = _FakeRuntime();
    final worker = _FakeWorker()..flushSegments = const ['turno'];
    final records = <VoiceLatencyRecord>[];
    var nowMicros = 1000;
    final trace = VoiceLatencyTrace.testing(
      runId: 'abcdef0123456789',
      nowMicros: () => nowMicros += 100,
      onRecord: records.add,
    );
    trace.beginTurn(
      route: VoiceLatencyRoute.phone,
      scenario: VoiceLatencyScenario.normal,
      sttTopology: VoiceSttTopology.recordThenTranscribe,
      lastAboveAvailability: VoiceLatencyAvailability.measured,
    );
    final engine = SherpaSttEngine(
      model: sherpaModelByKind(SherpaModelKind.whisperBase),
      manager: _FakeManager(),
      runtime: runtime,
      silenceTimeout: Duration.zero,
      workerFactory: (_) async => worker,
    );

    await trace.runScoped(() async {
      final done = engine.listen().drain<void>();
      await _waitFor(() => runtime.startCalls == 1 && worker.prepareCalls == 1);
      worker.emit(generation: 1, speechDetected: true);
      worker.emit(generation: 1, speechDetected: false);
      await done.timeout(const Duration(seconds: 1));
    });

    expect(
      records.map((record) => record.point),
      containsAllInOrder(const <VoiceLatencyPoint>[
        VoiceLatencyPoint.speechLastAboveThreshold,
        VoiceLatencyPoint.speechEndpoint,
        VoiceLatencyPoint.sttStarted,
        VoiceLatencyPoint.sttFinal,
      ]),
    );
    await engine.dispose();
    await runtime.audio.close();
  });

  test(
    'transcribe el WAV full-duplex local sin abrir otro micrófono',
    () async {
      final runtime = _FakeRuntime();
      final worker = _FakeWorker()..flushSegments = const ['Cállate'];
      final engine = _engine(runtime, worker);
      final pcm = Uint8List.fromList(const [1, 0, 2, 0, 3, 0, 4, 0]);

      expect(await engine.transcribeCapturedWav(_pcm16Wav(pcm)), 'Cállate');
      expect(runtime.startCalls, 0);
      expect(runtime.stopCalls, 0);
      expect(worker.prepareCalls, 1);
      expect(worker.acceptedGenerations, hasLength(1));
      expect(worker.acceptedLengths, [pcm.length]);
      expect(worker.flushGenerations, worker.acceptedGenerations);

      await engine.dispose();
      await runtime.audio.close();
    },
  );

  test(
    'conserva segmentos emitidos al aceptar antes del flush final',
    () async {
      final runtime = _FakeRuntime();
      final worker = _FakeWorker()
        ..acceptSegments = const ['Busca las tareas pendientes']
        ..flushSegments = const ['y dime qué queda por publicar'];
      final engine = _engine(runtime, worker);
      final pcm = Uint8List.fromList(const [1, 0, 2, 0, 3, 0, 4, 0]);

      expect(
        await engine.transcribeCapturedWav(_pcm16Wav(pcm)),
        'Busca las tareas pendientes y dime qué queda por publicar',
      );

      await engine.dispose();
      await runtime.audio.close();
    },
  );

  test('rechaza WAV incompatible antes de crear el worker', () async {
    final runtime = _FakeRuntime();
    final worker = _FakeWorker();
    final engine = _engine(runtime, worker);

    await expectLater(
      engine.transcribeCapturedWav(Uint8List.fromList(const [1, 2, 3])),
      throwsFormatException,
    );
    expect(worker.prepareCalls, 0);
    expect(runtime.startCalls, 0);

    await engine.dispose();
    await runtime.audio.close();
  });

  test(
    'abre el micro mientras prepara el worker sin bloquear Flutter',
    () async {
      final runtime = _FakeRuntime();
      final worker = _FakeWorker()..prepareGate = Completer<void>();
      SherpaSttWorkerConfig? config;
      final engine = _engine(
        runtime,
        worker,
        onConfig: (value) => config = value,
      );
      final done = engine.listen().drain<void>();

      await _waitFor(() => worker.prepareCalls == 1);
      var eventLoopAdvanced = false;
      scheduleMicrotask(() => eventLoopAdvanced = true);
      await Future<void>.delayed(Duration.zero);

      expect(eventLoopAdvanced, isTrue);
      expect(runtime.startCalls, 1);
      expect(config?.language, 'es');
      expect(config?.encoderPath, '/model/encoder.onnx');

      runtime.audio.add(Uint8List.fromList(const [0, 0]));
      await _waitFor(() => worker.acceptedGenerations.isNotEmpty);

      worker.prepareGate!.complete();
      await engine.stop();
      await done;
      await engine.dispose();
      await runtime.audio.close();
    },
  );

  test('conserva el PCM recibido antes de que exista el worker', () async {
    final runtime = _FakeRuntime();
    final worker = _FakeWorker();
    final workerGate = Completer<SherpaSttWorker>();
    final engine = SherpaSttEngine(
      model: sherpaModelByKind(SherpaModelKind.whisperBase),
      manager: _FakeManager(),
      runtime: runtime,
      workerFactory: (_) => workerGate.future,
    );
    final done = engine.listen().drain<void>();

    await _waitFor(() => runtime.startCalls == 1);
    runtime.audio.add(Uint8List.fromList(const [1, 0, 2, 0]));
    await Future<void>.delayed(Duration.zero);
    expect(worker.acceptedGenerations, isEmpty);

    workerGate.complete(worker);
    await _waitFor(() => worker.acceptedGenerations.length == 1);

    await engine.stop();
    await done;
    await engine.dispose();
    await runtime.audio.close();
  });

  test('stop durante arranque drena el PCM antes de cerrar el final', () async {
    final runtime = _FakeRuntime();
    final worker = _FakeWorker()
      ..flushSegments = const ['frase conservada']
      ..flushGate = Completer<void>();
    final workerGate = Completer<SherpaSttWorker>();
    final engine = SherpaSttEngine(
      model: sherpaModelByKind(SherpaModelKind.whisperBase),
      manager: _FakeManager(),
      runtime: runtime,
      workerFactory: (_) => workerGate.future,
    );
    final resultsFuture = engine.listen().toList();

    await _waitFor(() => runtime.startCalls == 1);
    runtime.audio.add(Uint8List.fromList(const [1, 0, 2, 0]));
    await Future<void>.delayed(Duration.zero);
    expect(worker.acceptedGenerations, isEmpty);

    var stopCompleted = false;
    final stopping = engine.stop().whenComplete(() => stopCompleted = true);
    await Future<void>.delayed(Duration.zero);
    final completedBeforeWorker = stopCompleted;

    workerGate.complete(worker);
    await _waitFor(
      () =>
          worker.acceptedGenerations.isNotEmpty &&
          worker.flushGenerations.isNotEmpty,
    );
    worker.emit(
      generation: worker.acceptedGenerations.single,
      level: 0.5,
      speechDetected: true,
    );
    await Future<void>.delayed(Duration.zero);
    worker.flushGate!.complete();
    await stopping;
    final results = await resultsFuture;

    expect(completedBeforeWorker, isFalse);
    expect(worker.acceptedGenerations, hasLength(1));
    expect(results.last.text, 'frase conservada');
    expect(results.last.isFinal, isTrue);

    await engine.dispose();
    await runtime.audio.close();
  });

  test('no descarta dictados largos mientras arranca el worker', () async {
    final runtime = _FakeRuntime();
    final worker = _FakeWorker();
    final workerGate = Completer<SherpaSttWorker>();
    final engine = SherpaSttEngine(
      model: sherpaModelByKind(SherpaModelKind.whisperBase),
      manager: _FakeManager(),
      runtime: runtime,
      workerFactory: (_) => workerGate.future,
    );
    final done = engine.listen().drain<void>();

    await _waitFor(() => runtime.startCalls == 1);
    runtime.audio.add(Uint8List(16000 * 2 * 16));
    await Future<void>.delayed(Duration.zero);
    expect(worker.acceptedGenerations, isEmpty);

    workerGate.complete(worker);
    await _waitFor(() => worker.acceptedGenerations.length == 1);

    await engine.stop();
    await done;
    await engine.dispose();
    await runtime.audio.close();
  });

  test('stop conserva updates del worker que ya estaban en tránsito', () async {
    final runtime = _FakeRuntime();
    final worker = _FakeWorker()..flushGate = Completer<void>();
    final engine = _engine(runtime, worker);
    final results = <SttResult>[];
    final done = Completer<void>();
    engine.listen().listen(results.add, onDone: done.complete);

    await _waitFor(() => runtime.startCalls == 1);
    runtime.audio.add(Uint8List.fromList(const [0, 0]));
    await _waitFor(() => worker.acceptedGenerations.isNotEmpty);
    final generation = worker.acceptedGenerations.single;

    final stopping = engine.stop();
    await _waitFor(() => worker.flushGenerations.isNotEmpty);
    worker.emit(generation: generation, segments: const ['último segmento']);
    await Future<void>.delayed(Duration.zero);
    worker.flushGate!.complete();

    await stopping;
    await done.future;
    expect(results.last.text, 'último segmento');
    expect(results.last.isFinal, isTrue);

    await engine.dispose();
    await runtime.audio.close();
  });

  test(
    'filtra ruido Whisper por segmento sin borrar el dictado válido',
    () async {
      final runtime = _FakeRuntime();
      final worker = _FakeWorker();
      final engine = _engine(runtime, worker);
      final results = <SttResult>[];
      final done = Completer<void>();
      engine.listen().listen(results.add, onDone: done.complete);

      await _waitFor(() => runtime.startCalls == 1);
      runtime.audio.add(Uint8List.fromList(const [0, 0]));
      await _waitFor(() => worker.acceptedGenerations.isNotEmpty);
      final generation = worker.acceptedGenerations.single;
      worker.emit(
        generation: generation,
        segments: const [
          'abre las noticias',
          'Gracias',
          'Adiós',
          'Thanks for watching',
        ],
      );
      await _waitFor(() => results.isNotEmpty);

      expect(results.single.text, 'abre las noticias Gracias Adiós');
      await engine.stop();
      await done.future;
      expect(results.last.text, 'abre las noticias Gracias Adiós');
      expect(results.last.isFinal, isTrue);

      await engine.dispose();
      await runtime.audio.close();
    },
  );

  test(
    'descarta texto Whisper sin evidencia acústica del umbral Desktop',
    () async {
      final runtime = _FakeRuntime();
      final worker = _FakeWorker()
        ..flushSegments = const ['de decir las noticias de hoy en España'];
      final engine = _engine(runtime, worker);
      final results = <SttResult>[];
      final done = Completer<void>();
      engine.listen().listen(results.add, onDone: done.complete);

      await _waitFor(() => runtime.startCalls == 1);
      runtime.audio.add(Uint8List.fromList(const [0, 0]));
      await _waitFor(() => worker.acceptedGenerations.isNotEmpty);
      final generation = worker.acceptedGenerations.single;

      worker.emit(
        generation: generation,
        level: 0.05,
        speechDetected: true,
        acousticSpeechEvidence: false,
        segments: const ['Me siento'],
      );
      await Future<void>.delayed(Duration.zero);
      expect(results, isEmpty);

      await engine.stop();
      await done.future;
      expect(results, hasLength(1));
      expect(results.single.text, isEmpty);
      expect(results.single.isFinal, isTrue);

      await engine.dispose();
      await runtime.audio.close();
    },
  );

  test(
    'solo aplica updates de la generación activa y flush conserva orden',
    () async {
      final runtime = _FakeRuntime();
      final worker = _FakeWorker();
      final levels = <double>[];
      final engine = SherpaSttEngine(
        model: sherpaModelByKind(SherpaModelKind.whisperBase),
        manager: _FakeManager(),
        runtime: runtime,
        workerFactory: (_) async => worker,
        onLevel: levels.add,
      );

      final firstResults = <SttResult>[];
      final firstDone = Completer<void>();
      engine.listen().listen(firstResults.add, onDone: firstDone.complete);
      await _waitFor(() => runtime.startCalls == 1);

      runtime.audio.add(Uint8List.fromList(const [0, 0]));
      await _waitFor(() => worker.acceptedGenerations.isNotEmpty);
      final firstGeneration = worker.acceptedGenerations.single;
      worker.emit(
        generation: firstGeneration + 100,
        segments: const ['resultado obsoleto'],
      );
      worker.emit(generation: firstGeneration, segments: const ['hola']);
      await _waitFor(() => firstResults.isNotEmpty);

      expect(firstResults.single.text, 'hola');
      expect(firstResults.single.isFinal, isFalse);
      expect(levels, isNotEmpty);

      worker.flushSegments = const ['final'];
      await engine.stop();
      await firstDone.future;
      expect(worker.flushGenerations, [firstGeneration]);
      expect(firstResults.last.text, 'hola final');
      expect(firstResults.last.isFinal, isTrue);

      worker.flushSegments = const [];
      final secondResults = <SttResult>[];
      final secondDone = Completer<void>();
      engine.listen().listen(secondResults.add, onDone: secondDone.complete);
      await _waitFor(() => runtime.startCalls == 2);
      runtime.audio.add(Uint8List.fromList(const [0, 0]));
      await _waitFor(() => worker.acceptedGenerations.length == 2);
      final secondGeneration = worker.acceptedGenerations.last;
      expect(secondGeneration, isNot(firstGeneration));

      worker.emit(generation: firstGeneration, segments: const ['tarde']);
      worker.emit(generation: secondGeneration, segments: const ['nuevo']);
      await _waitFor(() => secondResults.isNotEmpty);
      expect(secondResults.single.text, 'nuevo');

      await engine.stop();
      await secondDone.future;
      await Future.wait([engine.dispose(), engine.dispose()]);
      expect(worker.prepareCalls, 2);
      expect(worker.disposeCalls, 1);
      expect(runtime.disposeCalls, 1);
      await runtime.audio.close();
    },
  );

  test(
    'el worker real se puede liberar varias veces antes de cargar modelos',
    () async {
      final worker = await IsolateSherpaSttWorker.start(
        const SherpaSttWorkerConfig(
          tokensPath: '/unused/tokens.txt',
          encoderPath: '/unused/encoder.onnx',
          decoderPath: '/unused/decoder.onnx',
          joinerPath: '',
          sileroPath: '/unused/silero.onnx',
          language: 'es',
          transducer: false,
          numThreads: 2,
        ),
      );

      final first = worker.dispose();
      final second = worker.dispose();
      expect(identical(first, second), isTrue);
      await Future.wait([first, second]);
      await expectLater(worker.dispose(), completes);
      await expectLater(
        worker.prepare(),
        throwsA(isA<SherpaSttWorkerException>()),
      );
    },
  );
}
