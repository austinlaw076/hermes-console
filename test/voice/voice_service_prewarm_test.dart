import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/secure_storage.dart';
import 'package:hermes_android/core/services/voice/tts_engine.dart';
import 'package:hermes_android/core/services/voice/voice_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Spec 048 / US2+US3 — VoiceService encadena la precarga del motor de
/// respuesta a `prepareForNarration` sin bloquear, y `prewarmSpeech`
/// normaliza exactamente como `_enqueue` (contracts/engine-prewarm.md).
class _RecordingEngine implements TtsEngine, PrewarmableTts {
  final List<String?> prewarms = [];
  final List<String> spoken = [];
  Completer<void>? prewarmGate;
  Completer<void>? disposeGate;
  Object? prewarmError;
  int disposeCalls = 0;

  @override
  Future<void> prewarm([String? text]) async {
    prewarms.add(text);
    final error = prewarmError;
    if (error != null) throw error;
    final gate = prewarmGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await disposeGate?.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({'app_locale': 'es'}));

  Future<(VoiceService, _RecordingEngine)> service() async {
    final prefs = await SharedPreferences.getInstance();
    final voice = VoiceService(prefs, SecureStorage());
    final engine = _RecordingEngine();
    voice.debugTtsFactory = () => engine;
    return (voice, engine);
  }

  test('prepareForNarration dispara la precarga sin bloquear', () async {
    final (voice, engine) = await service();
    engine.prewarmGate = Completer<void>();

    await voice.prepareForNarration().timeout(
      const Duration(seconds: 1),
      onTimeout: () => fail('prepareForNarration no debe esperar al prewarm'),
    );

    for (var i = 0; i < 50 && engine.prewarms.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(engine.prewarms, [null], reason: 'precarga de motor, sin texto');
    engine.prewarmGate!.complete();
  });

  test(
    '19 prewarm y primera locución comparten una sola construcción TTS',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final voice = VoiceService(prefs, SecureStorage());
      var disposed = false;
      addTearDown(() async {
        if (!disposed) await voice.dispose();
      });
      final releaseBuilder = Completer<void>();
      final engines = <_RecordingEngine>[];
      var builds = 0;
      voice.debugTtsBuilder = () async {
        builds++;
        await releaseBuilder.future;
        final engine = _RecordingEngine();
        engines.add(engine);
        return engine;
      };

      final prewarms = List<Future<void>>.generate(
        19,
        (_) => voice.prewarmResponseTts(),
      );
      for (var i = 0; i < 50 && builds == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(builds, 1);

      await voice.enqueueSpeech('Hola.');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        builds,
        1,
        reason: 'speak debe esperar el builder que ya abrió prewarm',
      );

      releaseBuilder.complete();
      await Future.wait(prewarms);
      await voice.waitSpeechDone();

      expect(builds, 1);
      expect(engines, hasLength(1));
      expect(engines.single.prewarms, hasLength(19));
      expect(engines.single.spoken, ['Hola.']);
      await voice.dispose();
      disposed = true;
      expect(engines.single.disposeCalls, 1);
    },
  );

  test(
    'una segunda frontera invalida el prewarm que espera un disposal previo',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final voice = VoiceService(prefs, SecureStorage());
      final engines = <_RecordingEngine>[];
      voice.debugTtsFactory = () {
        final engine = _RecordingEngine();
        engines.add(engine);
        return engine;
      };
      addTearDown(voice.dispose);

      await voice.prewarmResponseTts();
      expect(engines, hasLength(1));
      final first = engines.single;
      final releaseDispose = Completer<void>();
      first.disposeGate = releaseDispose;

      var firstDisposalCompleted = false;
      final firstDisposal = voice.disposeTtsForVoiceExit().whenComplete(() {
        firstDisposalCompleted = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(firstDisposalCompleted, isFalse);

      final stalePrewarm = voice.prewarmResponseTts();
      final privacyBoundary = voice.disposeTtsForVoiceExit();
      releaseDispose.complete();

      await Future.wait([firstDisposal, privacyBoundary, stalePrewarm]);
      await Future<void>.delayed(Duration.zero);

      expect(
        engines,
        hasLength(1),
        reason: 'App Lock/Exit no puede publicar TTS tras confirmar teardown',
      );
      expect(first.disposeCalls, 1);
    },
  );

  test(
    'Exit invalida el lote reservado antes de que pueda abrir otro TTS',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final voice = VoiceService(prefs, SecureStorage());
      final engine = _RecordingEngine();
      final releaseBuilder = Completer<void>();
      var builds = 0;
      voice.debugTtsBuilder = () async {
        builds++;
        await releaseBuilder.future;
        return engine;
      };
      addTearDown(voice.dispose);

      final lease = voice.beginConversationSpeechLease();
      expect(
        await voice.enqueueConversationSpeech(
          lease,
          'Lote que estaba sonando.',
        ),
        isTrue,
      );
      for (var attempt = 0; attempt < 50 && builds == 0; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(builds, 1);

      expect(voice.endConversationSpeechLease(lease), isTrue);
      expect(
        await voice.enqueueConversationSpeech(
          lease,
          'Lote precalentado que ya no pertenece a la conversación.',
        ),
        isFalse,
      );

      final nextLease = voice.beginConversationSpeechLease();
      releaseBuilder.complete();
      await voice.waitSpeechDone();

      expect(
        engine.spoken,
        isEmpty,
        reason:
            'una lease nueva no puede adoptar una locución pendiente de la '
            'conversación que ya salió',
      );
      expect(
        await voice.enqueueConversationSpeech(
          nextLease,
          'Lote de la conversación nueva.',
        ),
        isTrue,
      );
      await voice.waitSpeechDone();
      expect(engine.spoken, ['Lote de la conversación nueva.']);

      expect(voice.endConversationSpeechLease(nextLease), isTrue);
      await voice.disposeTtsForVoiceExit();
      expect(engine.disposeCalls, 1);
    },
  );

  test('un prewarm que falla queda silenciado', () async {
    final (voice, engine) = await service();
    engine.prewarmError = Exception('modelo no descargado');

    await voice.prepareForNarration();
    for (var i = 0; i < 50 && engine.prewarms.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(engine.prewarms, [null]);
    // La siguiente locución sigue funcionando con normalidad.
    await voice.enqueueSpeech('Hola.');
    await voice.waitSpeechDone();
    expect(engine.spoken, isNotEmpty);
  });

  test('prewarmSpeech normaliza exactamente como enqueueSpeech', () async {
    final (voice, engine) = await service();

    const markdown = '**Hola** [guía](https://example.com). Segunda frase.';
    await voice.prewarmSpeech(markdown);
    await voice.enqueueSpeech(markdown);
    await voice.waitSpeechDone();

    expect(engine.prewarms, hasLength(1));
    expect(
      engine.prewarms.single,
      engine.spoken.single,
      reason: 'la clave de caché debe coincidir con lo que hablará speak()',
    );
    expect(engine.prewarms.single, isNot(contains('**')));
    expect(engine.prewarms.single, isNot(contains('https')));
  });

  test(
    'todos los proveedores reciben importes y horas pronunciables',
    () async {
      final (voice, engine) = await service();

      await voice.enqueueSpeech(
        'Cuesta 0,99€ y empieza a las 14:30. '
        'Consulta https://example.com/private.',
      );
      await voice.waitSpeechDone();

      expect(engine.spoken, hasLength(1));
      expect(engine.spoken.single, contains('0 euros con 99 céntimos'));
      expect(engine.spoken.single, contains('14 y 30'));
      expect(engine.spoken.single, isNot(contains('https')));
    },
  );

  test('prewarmSpeech no toca la cola ni el estado speaking', () async {
    final (voice, engine) = await service();

    await voice.prewarmSpeech('Solo precarga.');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(engine.spoken, isEmpty);
    expect(voice.speaking.value, isFalse);
  });
}
