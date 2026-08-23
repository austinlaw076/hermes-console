import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/voice/hermes_pcm_stream.dart';

Map<String, Object> _successfulWrite(MethodCall call) {
  final pcm = (call.arguments as Map)['pcm'] as Uint8List;
  return <String, Object>{
    'acceptedBytes': pcm.length,
    'mayHavePlayed': pcm.isNotEmpty,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/hermes_pcm_stream');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('configure, writes and finish preserve order and generation', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'write') return _successfulWrite(call);
      return null;
    });
    final sink = MethodChannelHermesPcmStreamSink(
      channel: channel,
      generation: 41,
    );

    await sink.configure(const HermesPcmFormat(sampleRate: 24000, channels: 1));
    await sink.write(Uint8List.fromList([1, 0, 2, 0]));
    await sink.write(Uint8List.fromList([3, 0]));
    await sink.finish();

    expect(calls.map((call) => call.method), [
      'configure',
      'write',
      'write',
      'finish',
    ]);
    for (final call in calls) {
      expect((call.arguments as Map)['generation'], 41);
    }
    expect((calls.first.arguments as Map)['sample_rate'], 24000);
    expect((calls.first.arguments as Map)['channels'], 1);
  });

  test('a pending native write backpressures the following write', () async {
    final firstWrite = Completer<void>();
    var writesSeen = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'write') {
        writesSeen += 1;
        if (writesSeen == 1) await firstWrite.future;
        return _successfulWrite(call);
      }
      return null;
    });
    final sink = MethodChannelHermesPcmStreamSink(
      channel: channel,
      generation: 42,
    );
    await sink.configure(const HermesPcmFormat(sampleRate: 24000, channels: 1));

    final one = sink.write(Uint8List.fromList([1, 0]));
    final two = sink.write(Uint8List.fromList([2, 0]));
    await Future<void>.delayed(Duration.zero);
    expect(writesSeen, 1);

    firstWrite.complete();
    await Future.wait([one, two]);
    expect(writesSeen, 2);
  });

  test('Pause y Resume sortean un write bloqueado sin deadlock', () async {
    final writeBlocked = Completer<void>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'write') {
        await writeBlocked.future;
        return _successfulWrite(call);
      }
      return null;
    });
    final sink = MethodChannelHermesPcmStreamSink(
      channel: channel,
      generation: 420,
    );
    await sink.configure(const HermesPcmFormat(sampleRate: 24000, channels: 1));

    final write = sink.write(Uint8List.fromList([1, 0, 2, 0]));
    await Future<void>.delayed(Duration.zero);
    final pause = sink.pause();
    final resume = sink.resume();
    await Future<void>.delayed(Duration.zero);

    await Future.wait([pause, resume]).timeout(const Duration(seconds: 1));
    expect(calls, ['configure', 'write', 'pause', 'resume']);

    writeBlocked.complete();
    await write.timeout(const Duration(seconds: 1));

    await sink.write(Uint8List.fromList([3, 0]));
    expect(calls.last, 'write');
    await sink.stop();
  });

  test('Pause admite un solo bloque de handoff y no abre cola PCM', () async {
    final writeEntered = Completer<void>();
    final releaseWrite = Completer<void>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'write') {
        if (!writeEntered.isCompleted) writeEntered.complete();
        await releaseWrite.future;
        return _successfulWrite(call);
      }
      if (call.method == 'resume' && !releaseWrite.isCompleted) {
        releaseWrite.complete();
      }
      return null;
    });
    final sink = MethodChannelHermesPcmStreamSink(
      channel: channel,
      generation: 423,
    );
    await sink.configure(const HermesPcmFormat(sampleRate: 24000, channels: 1));
    await sink.pause();

    final handoff = sink.write(Uint8List.fromList([1, 0, 2, 0]));
    await writeEntered.future.timeout(const Duration(seconds: 1));
    await expectLater(sink.write(Uint8List.fromList([3, 0])), throwsStateError);
    expect(calls.where((method) => method == 'write'), hasLength(1));

    await sink.resume().timeout(const Duration(seconds: 1));
    await handoff.timeout(const Duration(seconds: 1));
    expect(calls, ['configure', 'pause', 'write', 'resume']);
    await sink.stop();
  });

  test(
    'Pause conserva la generación mientras finish drena en nativo',
    () async {
      final finishEntered = Completer<void>();
      final finishBlocked = Completer<void>();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'write') return _successfulWrite(call);
        if (call.method == 'finish') {
          finishEntered.complete();
          await finishBlocked.future;
        }
        return null;
      });
      final sink = MethodChannelHermesPcmStreamSink(
        channel: channel,
        generation: 421,
      );
      await sink.configure(
        const HermesPcmFormat(sampleRate: 24000, channels: 1),
      );
      await sink.write(Uint8List.fromList([1, 0, 2, 0]));

      final finish = sink.finish();
      await finishEntered.future.timeout(const Duration(seconds: 1));
      await sink.pause().timeout(const Duration(seconds: 1));
      await sink.resume().timeout(const Duration(seconds: 1));

      expect(calls.map((call) => call.method), [
        'configure',
        'write',
        'finish',
        'pause',
        'resume',
      ]);
      expect(
        calls.map((call) => (call.arguments as Map)['generation']).toSet(),
        {421},
      );
      expect(calls.where((call) => call.method == 'configure'), hasLength(1));
      expect(calls.where((call) => call.method == 'stop'), isEmpty);

      finishBlocked.complete();
      await finish.timeout(const Duration(seconds: 1));
    },
  );

  test(
    'una pausa reanudada mantiene el write y finish drena después',
    () async {
      var paused = false;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'pause':
            paused = true;
            return null;
          case 'resume':
            paused = false;
            return null;
          case 'write':
            // El writer nativo retiene el bloque en waitForUserResume hasta que
            // Resume despierte; nunca lo pierde ni lo duplica.
            while (paused) {
              await Future<void>.delayed(const Duration(milliseconds: 5));
            }
            return _successfulWrite(call);
          default:
            return null;
        }
      });
      final sink = MethodChannelHermesPcmStreamSink(
        channel: channel,
        generation: 431,
      );
      await sink.configure(
        const HermesPcmFormat(sampleRate: 24000, channels: 1),
      );

      await sink.pause();
      final write = sink.write(Uint8List.fromList([1, 0, 2, 0]));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sink.resume();

      await write.timeout(const Duration(seconds: 2));
      await sink.finish().timeout(const Duration(seconds: 2));
      expect(calls, ['configure', 'pause', 'write', 'resume', 'finish']);
      await sink.stop();
    },
  );

  test(
    'un timeout de pausa nativo cancela el write sin colgar el stream',
    () async {
      var paused = false;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'pause':
            paused = true;
            return null;
          case 'resume':
            paused = false;
            return null;
          case 'write':
            // Contrato nativo acotado: si la pausa del usuario supera el máximo,
            // el writer libera el AudioTrack y reporta el bloque como cancelado
            // (cero bytes aceptados) en lugar de retener el track abierto.
            var waitedMs = 0;
            while (paused && waitedMs < 200) {
              await Future<void>.delayed(const Duration(milliseconds: 5));
              waitedMs += 5;
            }
            if (paused) {
              return const <String, Object>{
                'cancelled': true,
                'acceptedBytes': 0,
                'mayHavePlayed': false,
              };
            }
            return _successfulWrite(call);
          default:
            return null;
        }
      });
      final sink = MethodChannelHermesPcmStreamSink(
        channel: channel,
        generation: 432,
      );
      await sink.configure(
        const HermesPcmFormat(sampleRate: 24000, channels: 1),
      );

      await sink.pause();
      final write = sink.write(Uint8List.fromList([1, 0, 2, 0]));
      // Sin resume: el timeout nativo resuelve el write como rechazo limpio.
      await expectLater(
        write.timeout(const Duration(seconds: 2)),
        throwsA(
          isA<HermesPcmWriteException>()
              .having((error) => error.acceptedBytes, 'acceptedBytes', 0)
              .having((error) => error.mayHavePlayed, 'mayHavePlayed', isFalse),
        ),
      );
      // El sink sigue respondiendo: stop libera sin deadlock aunque la pausa
      // nunca se reanudó.
      await sink.resume();
      await sink.stop().timeout(const Duration(seconds: 2));
      expect(calls.first, 'configure');
      expect(calls, containsAllInOrder(['pause', 'write', 'resume', 'stop']));
    },
  );

  test('el nativo acota la pausa de usuario y la extensión del drain', () {
    final source = File(
      'android/app/src/main/kotlin/com/hermesagent/hermes_android/'
      'HermesPcmStreamHandler.kt',
    ).readAsStringSync();

    expect(source, contains('"pause" -> pause(generation, result)'));
    expect(source, contains('"resume" -> resume(generation, result)'));
    expect(source, contains('const val USER_PAUSE_MAX_MS = 45_000L'));
    expect(source, contains('const val MAX_DRAIN_PAUSE_EXTENSION_MS'));
    // El timeout de pausa libera e invalida el stream desde el propio writer.
    expect(
      source,
      contains('pcm user pause timeout gen=\${stream.generation}'),
    );
    expect(
      source,
      contains('deadline += min(userWaitNanos, max(0L, extensionBudget))'),
    );
    expect(source, contains('stream.userPaused.set(false)'));
    expect(source, isNot(contains('"pause" -> writer.execute')));
  });

  test('stop bypasses a blocked write and is idempotent', () async {
    final writeBlocked = Completer<void>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'write') await writeBlocked.future;
      if (call.method == 'write') return _successfulWrite(call);
      return null;
    });
    final sink = MethodChannelHermesPcmStreamSink(
      channel: channel,
      generation: 43,
    );
    await sink.configure(const HermesPcmFormat(sampleRate: 24000, channels: 1));
    final write = sink.write(Uint8List.fromList([1, 0]));
    await Future<void>.delayed(Duration.zero);

    await sink.stop();
    await sink.stop();
    expect(calls, ['configure', 'write', 'stop']);

    writeBlocked.complete();
    await write;
  });

  test(
    'invalid formats and unaligned chunks never reach native code',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });

      final badFormat = MethodChannelHermesPcmStreamSink(
        channel: channel,
        generation: 44,
      );
      await expectLater(
        badFormat.configure(
          const HermesPcmFormat(sampleRate: 24000, channels: 2),
        ),
        throwsArgumentError,
      );

      final sink = MethodChannelHermesPcmStreamSink(
        channel: channel,
        generation: 45,
      );
      await sink.configure(
        const HermesPcmFormat(sampleRate: 24000, channels: 1),
      );
      await expectLater(
        sink.write(Uint8List.fromList([1])),
        throwsArgumentError,
      );

      expect(calls, hasLength(1));
      expect(calls.single.method, 'configure');
    },
  );

  test('native write telemetry preserves zero-byte focus loss', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'write') {
        throw PlatformException(
          code: 'pcm_focus_lost',
          message: 'Audio focus lost',
          details: const <String, Object>{
            'acceptedBytes': 0,
            'mayHavePlayed': false,
          },
        );
      }
      return null;
    });
    final sink = MethodChannelHermesPcmStreamSink(
      channel: channel,
      generation: 46,
    );
    await sink.configure(const HermesPcmFormat(sampleRate: 24000, channels: 1));

    await expectLater(
      sink.write(Uint8List.fromList([1, 0, 2, 0])),
      throwsA(
        isA<HermesPcmWriteException>()
            .having((error) => error.acceptedBytes, 'acceptedBytes', 0)
            .having((error) => error.mayHavePlayed, 'mayHavePlayed', isFalse),
      ),
    );
  });

  test('native cancelled write is explicit zero-byte rejection', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'write') {
        return const <String, Object>{
          'cancelled': true,
          'acceptedBytes': 0,
          'mayHavePlayed': false,
        };
      }
      return null;
    });
    final sink = MethodChannelHermesPcmStreamSink(
      channel: channel,
      generation: 460,
    );
    await sink.configure(const HermesPcmFormat(sampleRate: 24000, channels: 1));

    await expectLater(
      sink.write(Uint8List.fromList([1, 0, 2, 0])),
      throwsA(
        isA<HermesPcmWriteException>()
            .having((error) => error.acceptedBytes, 'acceptedBytes', 0)
            .having((error) => error.mayHavePlayed, 'mayHavePlayed', isFalse),
      ),
    );
  });

  test('native write telemetry preserves a partial accepted block', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'write') {
        throw PlatformException(
          code: 'pcm_write_failed',
          message: 'AudioTrack failed',
          details: const <String, Object>{
            'acceptedBytes': 2,
            'mayHavePlayed': true,
          },
        );
      }
      return null;
    });
    final sink = MethodChannelHermesPcmStreamSink(
      channel: channel,
      generation: 47,
    );
    await sink.configure(const HermesPcmFormat(sampleRate: 24000, channels: 1));

    await expectLater(
      sink.write(Uint8List.fromList([1, 0, 2, 0])),
      throwsA(
        isA<HermesPcmWriteException>()
            .having((error) => error.acceptedBytes, 'acceptedBytes', 2)
            .having((error) => error.acceptedAny, 'acceptedAny', isTrue),
      ),
    );
  });
}
