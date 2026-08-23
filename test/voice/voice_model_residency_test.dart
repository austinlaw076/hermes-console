import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/secure_storage.dart';
import 'package:hermes_android/core/services/voice/device_memory_profile.dart';
import 'package:hermes_android/core/services/voice/stt_engine.dart';
import 'package:hermes_android/core/services/voice/tts_engine.dart';
import 'package:hermes_android/core/services/voice/voice_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Spec 048 / US4 — residencia de modelos según memoria
/// (contracts/model-residency.md): con memoria holgada los handoffs
/// escuchar↔hablar conservan los motores; con memoria justa o presión se
/// mantiene la serialización actual; salir del modo voz libera SIEMPRE.
class _SpyStt extends SttEngine {
  int stopCalls = 0;
  int disposeCalls = 0;

  @override
  bool get supportsPartials => true;

  @override
  Future<bool> available() async => true;

  @override
  Stream<SttResult> listen({
    String localeId = 'es_ES',
    void Function()? onSpeechEnd,
    void Function()? onCaptureReady,
    bool continuous = false,
  }) {
    onCaptureReady?.call();
    return const Stream<SttResult>.empty();
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

class _SpyTts implements TtsEngine, PrewarmableTts {
  int disposeCalls = 0;
  int prewarmCalls = 0;

  @override
  Future<void> prewarm([String? text]) async {
    prewarmCalls++;
  }

  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

class _BlockingTts extends _SpyTts {
  Completer<void> speaking = Completer<void>();

  @override
  Future<void> speak(String text) => speaking.future;

  @override
  Future<void> stop() async {
    if (!speaking.isCompleted) speaking.complete();
  }
}

class _ManualIdleTimer implements VoiceIdleTimer {
  final void Function() _callback;
  bool _cancelled = false;

  _ManualIdleTimer(this._callback);

  @override
  void cancel() => _cancelled = true;

  void fire() {
    if (!_cancelled) _callback();
  }
}

class _ManualIdleScheduler {
  final List<_ManualIdleTimer> timers = <_ManualIdleTimer>[];

  VoiceIdleTimer create(Duration _, void Function() callback) {
    final timer = _ManualIdleTimer(callback);
    timers.add(timer);
    return timer;
  }
}

const _bigDevice = DeviceMemoryProfile(memTotalBytes: 16 * 1024 * 1024 * 1024);
const _smallDevice = DeviceMemoryProfile(memTotalBytes: 4 * 1024 * 1024 * 1024);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({'app_locale': 'es'}));

  Future<(VoiceService, _SpyStt, _SpyTts)> service(
    DeviceMemoryProfile profile, {
    VoiceIdleTimerFactory? idleTimerFactory,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final voice = VoiceService(
      prefs,
      SecureStorage(),
      idleTimerFactory: idleTimerFactory,
    );
    final stt = _SpyStt();
    final tts = _SpyTts();
    voice.debugSttFactory = () => stt;
    voice.debugTtsFactory = () => tts;
    voice.debugMemoryProfile = profile;
    // Materializa ambos motores como haría una sesión de voz real.
    voice.startDictation();
    await voice.enqueueSpeech('Hola.');
    await voice.waitSpeechDone();
    return (voice, stt, tts);
  }

  test('con memoria holgada los handoffs conservan los motores', () async {
    final (voice, stt, tts) = await service(_bigDevice);
    expect(voice.serializesHeavyLocalVoiceModels, isFalse);

    await voice.prepareForNarration();
    expect(stt.stopCalls, 1, reason: 'parar el dictado, no liberar el modelo');
    expect(stt.disposeCalls, 0);

    await voice.releaseTtsForListening();
    expect(tts.disposeCalls, 0, reason: 'el worker TTS queda residente');
  });

  test('con memoria justa se conserva la serialización actual', () async {
    final (voice, stt, tts) = await service(_smallDevice);
    expect(voice.serializesHeavyLocalVoiceModels, isTrue);

    await voice.prepareForNarration();
    expect(stt.disposeCalls, 1);

    await voice.releaseTtsForListening();
    expect(tts.disposeCalls, 1);
  });

  test(
    'la presión de memoria fuerza serialización desde el siguiente handoff',
    () async {
      final (voice, stt, tts) = await service(_bigDevice);

      await voice.onMemoryPressure();
      expect(voice.serializesHeavyLocalVoiceModels, isTrue);

      await voice.prepareForNarration();
      expect(stt.disposeCalls, 1);
      expect(tts.disposeCalls, 0);
    },
  );

  test('cancelar el dictado con residencia conserva el modelo', () async {
    final (voice, stt, tts) = await service(_bigDevice);

    await voice.cancelDictation();

    expect(stt.stopCalls, 1, reason: 'el micrófono se cierra siempre');
    expect(
      stt.disposeCalls,
      0,
      reason:
          'stop-and-talk/pausa no deben pagar una recarga de modelo '
          '(fuga vista en la validación física: ~3,7 s tras interrumpir)',
    );
    expect(tts.disposeCalls, 0);
  });

  test('cancelar el dictado sin residencia destruye como siempre', () async {
    final (voice, stt, _) = await service(_smallDevice);

    await voice.cancelDictation();

    expect(stt.disposeCalls, 1);
  });

  test('salir del modo voz libera siempre y limpia la presión', () async {
    final (voice, stt, tts) = await service(_bigDevice);
    await voice.onMemoryPressure();

    await voice.disposeSttForVoiceExit();
    await voice.disposeTtsForVoiceExit();

    expect(stt.disposeCalls, 1);
    expect(tts.disposeCalls, 1);
    expect(
      voice.serializesHeavyLocalVoiceModels,
      isFalse,
      reason: 'la presión es por sesión de voz: la siguiente empieza limpia',
    );
  });

  test('idle de 90 s evacua ONNX y STT local de forma determinista', () async {
    final scheduler = _ManualIdleScheduler();
    final (voice, stt, tts) = await service(
      _bigDevice,
      idleTimerFactory: scheduler.create,
    );

    await voice.cancelDictation();
    expect(scheduler.timers, isNotEmpty);
    expect(stt.disposeCalls, 0);
    expect(tts.disposeCalls, 0);

    scheduler.timers.last.fire();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(stt.disposeCalls, 1);
    expect(tts.disposeCalls, 1);
  });

  test('reutilizar antes del idle cancela la expulsión pendiente', () async {
    final scheduler = _ManualIdleScheduler();
    final (voice, stt, tts) = await service(
      _bigDevice,
      idleTimerFactory: scheduler.create,
    );

    await voice.cancelDictation();
    final staleTimer = scheduler.timers.last;
    voice.startDictation();
    staleTimer.fire();
    await Future<void>.delayed(Duration.zero);

    expect(stt.disposeCalls, 0);
    expect(tts.disposeCalls, 0);
  });

  test('memory pressure no evacua durante conversación activa', () async {
    final (voice, stt, tts) = await service(_bigDevice);
    voice.setVoiceConversationActive(true);

    await voice.onMemoryPressure();
    expect(stt.disposeCalls, 0);
    expect(tts.disposeCalls, 0);

    voice.setVoiceConversationActive(false);
    await voice.cancelDictation();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(stt.disposeCalls, 1);
    expect(tts.disposeCalls, 1);
  });

  test(
    'onTrimMemory ignora UI_HIDDEN: background no es presión real',
    () async {
      final (voice, stt, tts) = await service(_bigDevice);

      await voice.onTrimMemory(20); // TRIM_MEMORY_UI_HIDDEN

      expect(
        voice.serializesHeavyLocalVoiceModels,
        isFalse,
        reason: 'ir a background no debe reactivar la serialización',
      );
      await voice.cancelDictation();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(stt.disposeCalls, 0);
      expect(tts.disposeCalls, 0);
    },
  );

  test(
    'onTrimMemory en background con conversación activa conserva los modelos',
    () async {
      final (voice, stt, tts) = await service(_bigDevice);
      voice.setVoiceConversationActive(true);

      await voice.onTrimMemory(40); // TRIM_MEMORY_BACKGROUND

      expect(voice.serializesHeavyLocalVoiceModels, isFalse);
      expect(stt.disposeCalls, 0);
      expect(tts.disposeCalls, 0);
    },
  );

  test('onTrimMemory RUNNING_LOW es presión real y sí reacciona', () async {
    final (voice, stt, tts) = await service(_bigDevice);

    await voice.onTrimMemory(10); // TRIM_MEMORY_RUNNING_LOW

    expect(voice.serializesHeavyLocalVoiceModels, isTrue);
    await voice.prepareForNarration();
    expect(stt.disposeCalls, 1);
    expect(tts.disposeCalls, 0);
  });

  test(
    'onTrimMemory en background sin conversación mantiene la evacuación',
    () async {
      final (voice, _, _) = await service(_bigDevice);

      await voice.onTrimMemory(40); // TRIM_MEMORY_BACKGROUND

      expect(
        voice.serializesHeavyLocalVoiceModels,
        isTrue,
        reason: 'sin voz activa la presión del sistema sigue mandando',
      );
    },
  );

  test(
    'Pause libera la lease y los modelos sin borrar la ruta congelada',
    () async {
      final scheduler = _ManualIdleScheduler();
      final (voice, stt, tts) = await service(
        _bigDevice,
        idleTimerFactory: scheduler.create,
      );
      voice.setVoiceConversationActive(true);
      final route = voice.activeVoiceRoute;

      voice.setVoiceConversationAudioLeaseActive(false);
      expect(voice.activeVoiceRoute, same(route));
      expect(
        stt.disposeCalls,
        0,
        reason: 'el recorder real sigue siendo owner',
      );
      await voice.cancelDictation();
      expect(scheduler.timers, isNotEmpty);
      scheduler.timers.last.fire();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(stt.disposeCalls, 1);
      expect(tts.disposeCalls, 1);

      voice.setVoiceConversationAudioLeaseActive(true);
      expect(voice.activeVoiceRoute, same(route));

      voice.setVoiceConversationActive(false);
      expect(voice.activeVoiceRoute, isNull);
      voice.setVoiceConversationAudioLeaseActive(true);
      await voice.onMemoryPressure();
      expect(stt.disposeCalls, 1, reason: 'Exit rechaza una lease tardía');
      expect(tts.disposeCalls, 1, reason: 'Exit rechaza una lease tardía');
    },
  );

  test(
    'una lectura pausada conserva ONNX incluso con memory pressure',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final scheduler = _ManualIdleScheduler();
      final tts = _BlockingTts();
      final voice = VoiceService(
        prefs,
        SecureStorage(),
        idleTimerFactory: scheduler.create,
      )..debugTtsFactory = () => tts;

      await voice.toggleReadAloud(
        messageKey: 'assistant:paused',
        revision: '1',
        markdown: 'Primera frase. Segunda frase.',
      );
      await Future<void>.delayed(Duration.zero);
      await voice.toggleReadAloud(
        messageKey: 'assistant:paused',
        revision: '1',
        markdown: 'Primera frase. Segunda frase.',
      );

      await voice.onMemoryPressure();
      expect(tts.disposeCalls, 0);

      await voice.stopAndDiscardReadAloud();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(tts.disposeCalls, 1);
    },
  );
}
