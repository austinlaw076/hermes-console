import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/secure_storage.dart';
import 'package:hermes_android/core/services/voice/read_aloud_session.dart';
import 'package:hermes_android/core/services/voice/tts_engine.dart';
import 'package:hermes_android/core/services/voice/voice_service.dart';
import 'package:hermes_android/core/services/voice/voice_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PendingSpeech {
  final String text;
  final Completer<void> completion = Completer<void>();

  _PendingSpeech(this.text);
}

class _ControllableTts implements TtsEngine {
  final List<_PendingSpeech> speeches = [];
  final List<Completer<void>> stops = [];
  final StreamController<int> _speechCount = StreamController.broadcast();
  int disposeCount = 0;

  @override
  Future<void> speak(String text) {
    final pending = _PendingSpeech(text);
    speeches.add(pending);
    _speechCount.add(speeches.length);
    return pending.completion.future;
  }

  Future<void> waitForSpeeches(int count) async {
    if (speeches.length >= count) return;
    await _speechCount.stream
        .firstWhere((current) => current >= count)
        .timeout(const Duration(seconds: 1));
  }

  @override
  Future<void> stop() {
    final pending = Completer<void>();
    stops.add(pending);
    return pending.future;
  }

  void releaseStops() {
    for (final stop in stops) {
      if (!stop.isCompleted) stop.complete();
    }
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
    releaseStops();
    for (final speech in speeches) {
      if (!speech.completion.isCompleted) speech.completion.complete();
    }
    await _speechCount.close();
  }
}

Future<VoiceService> _service(
  _ControllableTts engine, {
  ReadAloudStopBehavior behavior = ReadAloudStopBehavior.pauseAndResume,
}) async {
  SharedPreferences.setMockInitialValues({
    'voice_read_aloud_stop_behavior': behavior.id,
  });
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final service = VoiceService(prefs, SecureStorage());
  service.debugTtsFactory = () => engine;
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('salir de voz libera el motor TTS una sola vez', () async {
    final engine = _ControllableTts();
    final service = await _service(engine);
    addTearDown(service.dispose);

    await service.enqueueSpeech('Respuesta en curso.');
    await engine.waitForSpeeches(1);
    final firstExit = service.disposeTtsForVoiceExit();
    final secondExit = service.disposeTtsForVoiceExit();
    await Future.wait([firstExit, secondExit]);

    expect(engine.disposeCount, 1);
    expect(service.speaking.value, isFalse);
  });

  test('pausa publica estado antes de que stop nativo termine', () async {
    final engine = _ControllableTts();
    final service = await _service(engine);
    addTearDown(service.dispose);

    await service.toggleReadAloud(
      messageKey: 'chat:m1',
      revision: 'r1',
      markdown: 'Primera frase. Segunda frase.',
    );
    await engine.waitForSpeeches(1);
    expect(service.readAloud.value.phase, ReadAloudPhase.playing);

    await service.toggleReadAloud(
      messageKey: 'chat:m1',
      revision: 'r1',
      markdown: 'Primera frase. Segunda frase.',
    );

    expect(engine.stops, hasLength(1));
    expect(engine.stops.single.isCompleted, isFalse);
    expect(service.readAloud.value.phase, ReadAloudPhase.paused);
    expect(service.readAloud.value.cursor, 0);
    expect(service.speaking.value, isFalse);
    engine.releaseStops();
  });

  test(
    'reanuda la frase interrumpida y un finally viejo no avanza cursor',
    () async {
      final engine = _ControllableTts();
      final service = await _service(engine);
      addTearDown(service.dispose);
      const args = (
        messageKey: 'chat:m1',
        revision: 'r1',
        markdown: 'Primera frase. Segunda frase.',
      );

      await service.toggleReadAloud(
        messageKey: args.messageKey,
        revision: args.revision,
        markdown: args.markdown,
      );
      await engine.waitForSpeeches(1);
      await service.toggleReadAloud(
        messageKey: args.messageKey,
        revision: args.revision,
        markdown: args.markdown,
      );
      await service.toggleReadAloud(
        messageKey: args.messageKey,
        revision: args.revision,
        markdown: args.markdown,
      );
      await pumpEventQueue();
      expect(engine.speeches, hasLength(1));
      engine.releaseStops();
      await engine.waitForSpeeches(2);

      expect(engine.speeches[0].text, 'Primera frase.');
      expect(engine.speeches[1].text, 'Primera frase.');
      engine.speeches[0].completion.complete();
      await pumpEventQueue();
      expect(service.readAloud.value.cursor, 0);

      engine.speeches[1].completion.complete();
      await engine.waitForSpeeches(3);
      expect(engine.speeches[2].text, 'Segunda frase.');
      engine.speeches[2].completion.complete();
      await pumpEventQueue();
      expect(service.readAloud.value.phase, ReadAloudPhase.idle);
    },
  );

  test('detener y reiniciar descarta el cursor', () async {
    final engine = _ControllableTts();
    final service = await _service(
      engine,
      behavior: ReadAloudStopBehavior.stopAndRestart,
    );
    addTearDown(service.dispose);

    await service.toggleReadAloud(
      messageKey: 'chat:m1',
      revision: 'r1',
      markdown: 'Primera. Segunda.',
    );
    await engine.waitForSpeeches(1);
    await service.toggleReadAloud(
      messageKey: 'chat:m1',
      revision: 'r1',
      markdown: 'Primera. Segunda.',
    );
    expect(service.readAloud.value.phase, ReadAloudPhase.idle);

    await service.toggleReadAloud(
      messageKey: 'chat:m1',
      revision: 'r1',
      markdown: 'Primera. Segunda.',
    );
    await pumpEventQueue();
    expect(
      engine.speeches,
      hasLength(1),
      reason: 'el stop anterior debe asentarse antes de reiniciar el motor',
    );
    engine.releaseStops();
    await engine.waitForSpeeches(2);
    expect(engine.speeches[0].text, 'Primera.');
    expect(engine.speeches[1].text, 'Primera.');
  });

  test('cambiar de mensaje espera el stop y arranca B en un toque', () async {
    final engine = _ControllableTts();
    final service = await _service(engine);
    addTearDown(service.dispose);

    await service.toggleReadAloud(
      messageKey: 'chat:a',
      revision: 'a1',
      markdown: 'Mensaje A.',
    );
    await engine.waitForSpeeches(1);
    await service.toggleReadAloud(
      messageKey: 'chat:b',
      revision: 'b1',
      markdown: 'Mensaje B.',
    );
    await pumpEventQueue();
    expect(engine.speeches, hasLength(1));
    engine.releaseStops();
    await engine.waitForSpeeches(2);

    expect(service.readAloud.value.messageKey, 'chat:b');
    engine.speeches[0].completion.complete();
    await pumpEventQueue();
    expect(service.readAloud.value.messageKey, 'chat:b');
    expect(service.readAloud.value.phase, ReadAloudPhase.playing);
  });

  test(
    'al terminar, otro toque reproduce de nuevo desde el principio',
    () async {
      final engine = _ControllableTts();
      final service = await _service(engine);
      addTearDown(service.dispose);

      const args = (
        messageKey: 'chat:replay',
        revision: 'r1',
        markdown: 'Primera. Segunda.',
      );
      await service.toggleReadAloud(
        messageKey: args.messageKey,
        revision: args.revision,
        markdown: args.markdown,
      );
      await engine.waitForSpeeches(1);
      engine.speeches[0].completion.complete();
      await engine.waitForSpeeches(2);
      engine.speeches[1].completion.complete();
      await pumpEventQueue();
      expect(service.readAloud.value.phase, ReadAloudPhase.idle);

      await service.toggleReadAloud(
        messageKey: args.messageKey,
        revision: args.revision,
        markdown: args.markdown,
      );
      await engine.waitForSpeeches(3);

      expect(engine.speeches[2].text, 'Primera.');
      expect(service.readAloud.value.phase, ReadAloudPhase.playing);
    },
  );

  test(
    'un evento done automático repetido no vuelve a leer la revisión',
    () async {
      final engine = _ControllableTts();
      final service = await _service(engine);
      addTearDown(service.dispose);

      await service.startAutoRead(
        messageKey: 'chat:auto',
        revision: 'r1',
        markdown: 'Respuesta terminada.',
      );
      await engine.waitForSpeeches(1);
      engine.speeches.single.completion.complete();
      await pumpEventQueue();
      expect(service.readAloud.value.phase, ReadAloudPhase.idle);

      await service.startAutoRead(
        messageKey: 'chat:auto',
        revision: 'r1',
        markdown: 'Respuesta terminada.',
      );
      await pumpEventQueue();

      expect(engine.speeches, hasLength(1));
    },
  );

  test('espera el lease de playback antes de hablar', () async {
    final engine = _ControllableTts();
    final service = await _service(engine);
    addTearDown(service.dispose);
    final lease = Completer<bool>();
    service.prepareReadAloudPlayback = () => lease.future;

    await service.toggleReadAloud(
      messageKey: 'chat:lease',
      revision: 'r1',
      markdown: 'Audio protegido.',
    );
    await pumpEventQueue();
    expect(engine.speeches, isEmpty);

    lease.complete(true);
    await engine.waitForSpeeches(1);
    expect(engine.speeches.single.text, 'Audio protegido.');
  });

  test('controles de sistema pausan, reanudan y terminan ReadAloud', () async {
    final engine = _ControllableTts();
    final service = await _service(engine);
    addTearDown(service.dispose);

    await service.toggleReadAloud(
      messageKey: 'chat:system',
      revision: 'r1',
      markdown: 'Primera. Segunda.',
    );
    await engine.waitForSpeeches(1);
    await service.pauseReadAloudFromSystemControl();
    expect(service.readAloud.value.phase, ReadAloudPhase.paused);

    engine.releaseStops();
    await service.resumeReadAloudFromSystemControl();
    await engine.waitForSpeeches(2);
    expect(service.readAloud.value.phase, ReadAloudPhase.playing);

    await service.stopAndDiscardReadAloud();
    expect(service.readAloud.value.phase, ReadAloudPhase.idle);
  });
}
