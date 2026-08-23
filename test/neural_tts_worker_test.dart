import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/voice/neural_tts_worker.dart';
import 'package:hermes_android/core/services/voice/tts_engine.dart';

class _WorkerRequest {
  final String text;
  final Completer<NeuralTtsWorkerAudio> completion = Completer();

  _WorkerRequest(this.text);
}

class _FakeWorker implements NeuralTtsWorker {
  final List<_WorkerRequest> requests = [];
  final StreamController<int> _requestCount = StreamController.broadcast();
  bool disposed = false;

  @override
  Future<NeuralTtsWorkerAudio> synthesize(String text, double speed) {
    final request = _WorkerRequest(text);
    requests.add(request);
    _requestCount.add(requests.length);
    return request.completion.future;
  }

  Future<void> waitForRequests(int count) async {
    if (requests.length >= count) return;
    await _requestCount.stream
        .firstWhere((current) => current >= count)
        .timeout(const Duration(seconds: 1));
  }

  void complete(int index) {
    completeWith(
      index,
      NeuralTtsWorkerAudio(
        samples: Float32List.fromList([0.25, -0.25]),
        sampleRate: 16000,
      ),
    );
  }

  void completeWith(int index, NeuralTtsWorkerAudio audio) {
    requests[index].completion.complete(audio);
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    for (final request in requests) {
      if (!request.completion.isCompleted) {
        request.completion.completeError(StateError('disposed'));
      }
    }
    await _requestCount.close();
  }
}

class _Playback implements TtsAudioPlayback {
  final StreamController<void> _complete = StreamController.broadcast();
  int plays = 0;
  int stops = 0;
  bool disposed = false;
  final List<String> playedPaths = [];

  @override
  Stream<void> get onComplete => _complete.stream;

  @override
  Future<void> playBytes(Uint8List bytes, {required String mimeType}) async {
    plays++;
    scheduleMicrotask(() => _complete.add(null));
  }

  @override
  Future<void> playFile(String path) async {
    plays++;
    playedPaths.add(path);
    scheduleMicrotask(() => _complete.add(null));
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async => disposed = true;

  Future<void> close() => _complete.close();
}

class _BlockingPlayback implements TtsAudioPlayback {
  final StreamController<void> _complete = StreamController<void>.broadcast();
  final StreamController<int> _playCount = StreamController<int>.broadcast();
  int plays = 0;

  @override
  Stream<void> get onComplete => _complete.stream;

  @override
  Future<void> playBytes(Uint8List bytes, {required String mimeType}) async {
    plays++;
    _playCount.add(plays);
  }

  @override
  Future<void> playFile(String path) async {
    plays++;
    _playCount.add(plays);
  }

  Future<void> waitForPlayCount(int count) async {
    if (plays >= count) return;
    await _playCount.stream
        .firstWhere((current) => current >= count)
        .timeout(const Duration(seconds: 1));
  }

  void completeCurrent() => _complete.add(null);

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  Future<void> close() async {
    await _complete.close();
    await _playCount.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'stop hace volver speak sin esperar al generate síncrono del worker',
    () async {
      final worker = _FakeWorker();
      final oldPlayback = _Playback();
      final freshPlayback = _Playback();
      final engine = OnDeviceNeuralTtsEngine(
        modelPath: 'fake.onnx',
        tokensPath: 'fake.tokens',
        dataDirPath: 'fake-data',
        playback: oldPlayback,
        playbackFactory: () => freshPlayback,
        debugWorkerFactory: (_) async => worker,
        debugWaveWriter: (_, sequence) async => '/tmp/fake-$sequence.wav',
      );
      addTearDown(() async {
        await engine.dispose();
        await oldPlayback.close();
        await freshPlayback.close();
      });

      final speaking = engine.speak('Frase pendiente.');
      await worker.waitForRequests(1);
      await engine.stop();

      await speaking.timeout(const Duration(milliseconds: 100));
      expect(worker.requests.single.completion.isCompleted, isFalse);
      expect(oldPlayback.plays + freshPlayback.plays, 0);
    },
  );

  test('reanudar la misma frase reutiliza la inferencia pendiente', () async {
    final worker = _FakeWorker();
    final oldPlayback = _Playback();
    final freshPlayback = _Playback();
    final engine = OnDeviceNeuralTtsEngine(
      modelPath: 'fake.onnx',
      tokensPath: 'fake.tokens',
      dataDirPath: 'fake-data',
      playback: oldPlayback,
      playbackFactory: () => freshPlayback,
      debugWorkerFactory: (_) async => worker,
      debugWaveWriter: (_, sequence) async => '/tmp/fake-$sequence.wav',
    );
    addTearDown(() async {
      await engine.dispose();
      await oldPlayback.close();
      await freshPlayback.close();
    });

    final first = engine.speak('La misma frase.');
    await worker.waitForRequests(1);
    await engine.stop();
    await first.timeout(const Duration(milliseconds: 100));

    final resumed = engine.speak('La misma frase.');
    await pumpEventQueue(times: 2);
    expect(worker.requests, hasLength(1));
    worker.complete(0);
    await resumed.timeout(const Duration(seconds: 1));

    expect(freshPlayback.plays, 1);
  });

  test('dispose libera el worker propietario', () async {
    final worker = _FakeWorker();
    final playback = _Playback();
    final replacement = _Playback();
    final engine = OnDeviceNeuralTtsEngine(
      modelPath: 'fake.onnx',
      tokensPath: 'fake.tokens',
      dataDirPath: 'fake-data',
      playback: playback,
      playbackFactory: () => replacement,
      debugWorkerFactory: (_) async => worker,
      debugWaveWriter: (_, sequence) async => '/tmp/fake-$sequence.wav',
    );
    addTearDown(() async {
      await playback.close();
      await replacement.close();
    });

    final speaking = engine.speak('Pendiente.');
    await worker.waitForRequests(1);
    await engine.dispose();
    await speaking;

    expect(worker.disposed, isTrue);
  });

  test('dispose descarta un worker que todavía está arrancando', () async {
    final worker = _FakeWorker();
    final workerReady = Completer<NeuralTtsWorker>();
    final factoryCalled = Completer<void>();
    final playback = _Playback();
    final replacement = _Playback();
    final engine = OnDeviceNeuralTtsEngine(
      modelPath: 'fake.onnx',
      tokensPath: 'fake.tokens',
      dataDirPath: 'fake-data',
      playback: playback,
      playbackFactory: () => replacement,
      debugWorkerFactory: (_) {
        factoryCalled.complete();
        return workerReady.future;
      },
    );
    addTearDown(() async {
      await playback.close();
      await replacement.close();
    });

    final speaking = engine.speak('Arranque pendiente.');
    await factoryCalled.future.timeout(const Duration(seconds: 1));
    final disposing = engine.dispose();
    workerReady.complete(worker);

    await disposing.timeout(const Duration(seconds: 1));
    await speaking.timeout(const Duration(seconds: 1));
    expect(worker.disposed, isTrue);
    expect(worker.requests, isEmpty);
    expect(playback.plays + replacement.plays, 0);
  });

  test(
    'reproduce la ruta WAV y metadatos producidos dentro del isolate',
    () async {
      final worker = _FakeWorker();
      final playback = _Playback();
      final replacement = _Playback();
      final engine = OnDeviceNeuralTtsEngine(
        modelPath: 'fake.onnx',
        tokensPath: 'fake.tokens',
        dataDirPath: 'fake-data',
        playback: playback,
        playbackFactory: () => replacement,
        debugWorkerFactory: (_) async => worker,
      );
      addTearDown(() async {
        await engine.dispose();
        await playback.close();
        await replacement.close();
      });

      final speaking = engine.speak('Audio desde isolate.');
      await worker.waitForRequests(1);
      worker.completeWith(
        0,
        NeuralTtsWorkerAudio(
          samples: Float32List(0),
          sampleRate: 24000,
          wavePath: '/tmp/hermes-worker-test.wav',
          sampleCount: 24000,
          audible: true,
        ),
      );
      await speaking.timeout(const Duration(seconds: 1));

      expect(playback.playedPaths, ['/tmp/hermes-worker-test.wav']);
      expect(replacement.playedPaths, isEmpty);
    },
  );

  test(
    'prefetch sintetiza la siguiente frase durante la reproducción',
    () async {
      final playback = _BlockingPlayback();
      final replacement = _BlockingPlayback();
      final synthesized = <String>[];
      final firstSentence =
          'Primera frase ${List.filled(24, 'detallada').join(' ')}.';
      final secondSentence =
          'Segunda frase ${List.filled(24, 'continúa').join(' ')}.';
      final engine = OnDeviceNeuralTtsEngine(
        modelPath: 'fake.onnx',
        tokensPath: 'fake.tokens',
        dataDirPath: 'fake-data',
        playback: playback,
        playbackFactory: () => replacement,
        debugSynthesizer: (text, _) async {
          synthesized.add(text);
          return NeuralTtsAudio(
            samples: Float32List.fromList([0.25, -0.25]),
            sampleRate: 16000,
          );
        },
        debugWaveWriter: (_, sequence) async => '/tmp/fake-$sequence.wav',
      );
      addTearDown(() async {
        await engine.dispose();
        await playback.close();
        await replacement.close();
      });

      final speaking = engine.speak('$firstSentence $secondSentence');
      await playback.waitForPlayCount(1);
      await pumpEventQueue(times: 2);

      expect(
        synthesized,
        [firstSentence, secondSentence],
        reason: 'la segunda síntesis debe solaparse con el primer playback',
      );
      expect(playback.plays, 1);

      playback.completeCurrent();
      await playback.waitForPlayCount(2);
      playback.completeCurrent();
      await speaking.timeout(const Duration(seconds: 1));
    },
  );
}
