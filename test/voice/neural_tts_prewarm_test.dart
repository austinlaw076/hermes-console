import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/voice/neural_tts_worker.dart';
import 'package:hermes_android/core/services/voice/tts_engine.dart';

/// Spec 048 / US2+US3 — precarga del motor neuronal
/// (contracts/engine-prewarm.md): `prewarm()` paga el arranque del worker
/// durante la espera del agente y `prewarm(texto)` deja la primera frase
/// sintetizada en el caché sin reproducir nada.
class _CountingWorker implements NeuralTtsWorker {
  _CountingWorker(this.onSynth);

  final void Function(String text) onSynth;
  int disposeCalls = 0;

  @override
  Future<NeuralTtsWorkerAudio> synthesize(String text, double speed) async {
    onSynth(text);
    return NeuralTtsWorkerAudio(
      samples: Float32List.fromList([0.2, -0.2, 0.2]),
      sampleRate: 16000,
    );
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

class _Playback implements TtsAudioPlayback {
  final _completions = StreamController<void>.broadcast();
  int playCount = 0;

  @override
  Stream<void> get onComplete => _completions.stream;

  @override
  Future<void> playBytes(Uint8List bytes, {required String mimeType}) async {
    playCount++;
    scheduleMicrotask(() => _completions.add(null));
  }

  @override
  Future<void> playFile(String path) async {
    playCount++;
    scheduleMicrotask(() => _completions.add(null));
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  test('prewarm arranca el worker una vez y speak lo reutiliza', () async {
    var factoryCalls = 0;
    final synthesized = <String>[];
    final playback = _Playback();
    final engine = OnDeviceNeuralTtsEngine(
      modelPath: 'unused.onnx',
      tokensPath: 'unused.tokens',
      dataDirPath: 'unused-data',
      playback: playback,
      playbackFactory: () => _Playback(),
      debugWorkerFactory: (config) async {
        factoryCalls++;
        return _CountingWorker(synthesized.add);
      },
      debugWaveWriter: (audio, sequence) async =>
          '/tmp/hermes-pw-$sequence.wav',
    );
    addTearDown(engine.dispose);

    await engine.prewarm();
    expect(factoryCalls, 1);
    expect(playback.playCount, 0, reason: 'prewarm jamás reproduce audio');

    await engine.speak('Hola mundo.');
    expect(factoryCalls, 1, reason: 'speak reutiliza el worker precargado');
    expect(playback.playCount, greaterThan(0));
  });

  test('prewarm tras dispose no arranca ningún worker', () async {
    var factoryCalls = 0;
    final engine = OnDeviceNeuralTtsEngine(
      modelPath: 'unused.onnx',
      tokensPath: 'unused.tokens',
      dataDirPath: 'unused-data',
      playback: _Playback(),
      playbackFactory: _Playback.new,
      debugWorkerFactory: (config) async {
        factoryCalls++;
        return _CountingWorker((_) {});
      },
    );

    await engine.dispose();
    await engine.prewarm();

    expect(factoryCalls, 0);
  });

  test('prewarm con texto sintetiza al caché y speak lo consume', () async {
    var factoryCalls = 0;
    final synthesized = <String>[];
    final playback = _Playback();
    final engine = OnDeviceNeuralTtsEngine(
      modelPath: 'unused.onnx',
      tokensPath: 'unused.tokens',
      dataDirPath: 'unused-data',
      playback: playback,
      playbackFactory: () => _Playback(),
      debugWorkerFactory: (config) async {
        factoryCalls++;
        return _CountingWorker(synthesized.add);
      },
      debugWaveWriter: (audio, sequence) async =>
          '/tmp/hermes-pw-$sequence.wav',
    );
    addTearDown(engine.dispose);

    // `_sentences` agrupa frases cortas en un bloque ≤240 chars: el primer
    // elemento (y clave de caché) es ese bloque completo.
    await engine.prewarm('Primera frase. Segunda frase.');
    expect(factoryCalls, 1);
    expect(synthesized, ['Primera frase. Segunda frase.']);
    expect(playback.playCount, 0);

    await engine.speak('Primera frase. Segunda frase.');
    expect(synthesized, [
      'Primera frase. Segunda frase.',
    ], reason: 'speak consume el caché: cero síntesis duplicada');
    expect(playback.playCount, 1);
  });
}
