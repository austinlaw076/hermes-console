import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/voice/voice_latency_trace.dart';

void main() {
  group('VoiceLatencyTrace gate', () {
    test('requires both the qa flavor and the explicit trace define', () {
      expect(voiceLatencyTraceAllowed(flavor: 'qa', requested: true), isTrue);
      expect(voiceLatencyTraceAllowed(flavor: 'qa', requested: false), isFalse);
      expect(
        voiceLatencyTraceAllowed(flavor: 'play', requested: true),
        isFalse,
      );
      expect(
        voiceLatencyTraceAllowed(flavor: 'full', requested: true),
        isFalse,
      );
    });
  });

  group('VoiceLatencyTrace records', () {
    late List<VoiceLatencyRecord> records;
    late int nowMicros;
    late VoiceLatencyTrace trace;

    setUp(() {
      records = <VoiceLatencyRecord>[];
      nowMicros = 1000;
      trace = VoiceLatencyTrace.testing(
        runId: '0123456789abcdef',
        nowMicros: () => nowMicros,
        onRecord: records.add,
      );
    });

    test('uses an opaque run id and strictly allowlisted arguments', () {
      final first = trace.beginTurn(
        route: VoiceLatencyRoute.phone,
        scenario: VoiceLatencyScenario.normal,
      );
      nowMicros = 1100;
      expect(first.mark(VoiceLatencyPoint.speechEndpoint), isTrue);
      nowMicros = 1200;
      first.finish();

      final second = trace.beginTurn(
        route: VoiceLatencyRoute.server,
        scenario: VoiceLatencyScenario.bargeIn,
      );

      expect(first.turn, 1);
      expect(second.turn, 2);
      expect(records, isNotEmpty);
      for (final record in records) {
        expect(record.runId, matches(RegExp(r'^[a-f0-9]{16}$')));
        expect(
          record.arguments.keys,
          unorderedEquals(const <String>{
            'run_id',
            'turn',
            'route',
            'scenario',
            'point',
            'elapsed_us',
          }),
        );
        const forbidden = <String>{
          'transcript',
          'text',
          'session',
          'model',
          'url',
          'token',
          'cookie',
          'pcm',
        };
        expect(record.arguments.keys.where(forbidden.contains), isEmpty);
      }
    });

    test(
      'timeline finish preserves immutable records and allows the next turn',
      () {
        trace = VoiceLatencyTrace.testing(
          runId: '0123456789abcdef',
          nowMicros: () => nowMicros,
          onRecord: records.add,
          emitTimeline: true,
        );
        final first = trace.beginTurn(
          route: VoiceLatencyRoute.server,
          scenario: VoiceLatencyScenario.normal,
        );
        final startedArguments = records.single.arguments;

        nowMicros = 1200;
        expect(first.finish, returnsNormally);
        expect(
          startedArguments.keys,
          unorderedEquals(const <String>{
            'run_id',
            'turn',
            'route',
            'scenario',
            'point',
            'elapsed_us',
          }),
        );
        expect(
          () => trace.beginTurn(
            route: VoiceLatencyRoute.server,
            scenario: VoiceLatencyScenario.exit,
          ),
          returnsNormally,
        );
      },
    );

    test('deduplicates points and preserves monotonic event time', () {
      final turn = trace.beginTurn(
        route: VoiceLatencyRoute.phone,
        scenario: VoiceLatencyScenario.normal,
      );
      expect(turn.mark(VoiceLatencyPoint.backendLifecycleAck), isFalse);
      expect(turn.mark(VoiceLatencyPoint.backendTextAccepted), isFalse);
      expect(turn.mark(VoiceLatencyPoint.firstRawSpeechSuffix), isFalse);
      expect(turn.mark(VoiceLatencyPoint.ttsFirstFeed), isFalse);

      expect(turn.mark(VoiceLatencyPoint.submitStarted), isTrue);
      expect(turn.mark(VoiceLatencyPoint.submitAccepted), isTrue);
      nowMicros = 1500;
      expect(turn.mark(VoiceLatencyPoint.backendLifecycleAck), isTrue);
      expect(turn.mark(VoiceLatencyPoint.backendLifecycleAck), isFalse);

      // A defensive clamp prevents a faulty injected clock from making the
      // trace non-monotonic. developer.Timeline.now itself is monotonic.
      nowMicros = 1400;
      expect(turn.mark(VoiceLatencyPoint.backendTextAccepted), isTrue);

      final lifecycle = records.singleWhere(
        (record) => record.point == VoiceLatencyPoint.backendLifecycleAck,
      );
      final text = records.singleWhere(
        (record) => record.point == VoiceLatencyPoint.backendTextAccepted,
      );
      expect(lifecycle.isContent, isFalse);
      expect(text.isContent, isTrue);
      expect(text.elapsedMicros, greaterThanOrEqualTo(lifecycle.elapsedMicros));
    });

    test('flushes only the last above-threshold sample at endpoint', () {
      final turn = trace.beginTurn(
        route: VoiceLatencyRoute.phone,
        scenario: VoiceLatencyScenario.normal,
      );

      nowMicros = 1100;
      expect(turn.observeSpeechAboveThreshold(), isTrue);
      nowMicros = 1250;
      expect(turn.observeSpeechAboveThreshold(), isTrue);
      expect(
        records.map((record) => record.point),
        isNot(contains(VoiceLatencyPoint.speechLastAboveThreshold)),
      );

      nowMicros = 2500;
      expect(turn.mark(VoiceLatencyPoint.speechEndpoint), isTrue);
      final speech = records.singleWhere(
        (record) => record.point == VoiceLatencyPoint.speechLastAboveThreshold,
      );
      final endpoint = records.singleWhere(
        (record) => record.point == VoiceLatencyPoint.speechEndpoint,
      );
      expect(speech.elapsedMicros, 250);
      expect(endpoint.elapsedMicros, 1500);
      expect(endpoint.elapsedMicros - speech.elapsedMicros, 1250);
    });

    test('enforces causal PCM order and keeps audible unavailable', () {
      final turn = trace.beginTurn(
        route: VoiceLatencyRoute.server,
        scenario: VoiceLatencyScenario.normal,
      );

      expect(turn.mark(VoiceLatencyPoint.pcmFirstReceived), isFalse);
      expect(turn.mark(VoiceLatencyPoint.pcmFirstAccepted), isFalse);
      expect(turn.mark(VoiceLatencyPoint.pcmAudibleUnavailable), isFalse);

      expect(turn.mark(VoiceLatencyPoint.submitStarted), isTrue);
      expect(turn.mark(VoiceLatencyPoint.submitAccepted), isTrue);
      expect(turn.mark(VoiceLatencyPoint.backendTextAccepted), isTrue);
      expect(turn.mark(VoiceLatencyPoint.firstRawSpeechSuffix), isTrue);
      expect(turn.mark(VoiceLatencyPoint.ttsFirstFeed), isTrue);

      nowMicros = 1100;
      expect(turn.mark(VoiceLatencyPoint.pcmFirstReceived), isTrue);
      nowMicros = 1200;
      expect(turn.mark(VoiceLatencyPoint.pcmFirstAccepted), isTrue);
      nowMicros = 1300;
      expect(turn.mark(VoiceLatencyPoint.pcmAudibleUnavailable), isTrue);

      expect(
        records.map((record) => record.point),
        containsAllInOrder(const <VoiceLatencyPoint>[
          VoiceLatencyPoint.pcmFirstReceived,
          VoiceLatencyPoint.pcmFirstAccepted,
          VoiceLatencyPoint.pcmAudibleUnavailable,
        ]),
      );
      expect(
        records.where((record) => record.point.name.contains('firstAudible')),
        isEmpty,
      );
    });

    test('Stop and Exit points cannot contaminate a normal turn', () {
      final normal = trace.beginTurn(
        route: VoiceLatencyRoute.phone,
        scenario: VoiceLatencyScenario.normal,
      );
      expect(normal.mark(VoiceLatencyPoint.stopRequested), isFalse);
      expect(normal.mark(VoiceLatencyPoint.exitRequested), isFalse);

      final stop = trace.beginTurn(
        route: VoiceLatencyRoute.phone,
        scenario: VoiceLatencyScenario.stop,
      );
      expect(stop.mark(VoiceLatencyPoint.stopRequested), isTrue);
      expect(stop.mark(VoiceLatencyPoint.audioStopped), isTrue);

      final exit = trace.beginTurn(
        route: VoiceLatencyRoute.phone,
        scenario: VoiceLatencyScenario.exit,
      );
      expect(exit.mark(VoiceLatencyPoint.exitRequested), isTrue);
      expect(exit.mark(VoiceLatencyPoint.micReleased), isTrue);
      expect(exit.mark(VoiceLatencyPoint.audioStopped), isTrue);
      expect(exit.mark(VoiceLatencyPoint.leaseReleased), isTrue);
      expect(exit.mark(VoiceLatencyPoint.leaseReleaseUnavailable), isFalse);
    });

    test('raw suffix, synthesizable availability and feed stay distinct', () {
      final turn = trace.beginTurn(
        route: VoiceLatencyRoute.server,
        scenario: VoiceLatencyScenario.normal,
      );

      expect(turn.mark(VoiceLatencyPoint.firstRawSpeechSuffix), isFalse);
      expect(
        turn.mark(VoiceLatencyPoint.firstSynthesizableChunkUnavailable),
        isFalse,
      );
      expect(turn.mark(VoiceLatencyPoint.ttsFirstFeed), isFalse);
      expect(turn.mark(VoiceLatencyPoint.submitStarted), isTrue);
      expect(turn.mark(VoiceLatencyPoint.submitAccepted), isTrue);
      expect(turn.mark(VoiceLatencyPoint.backendTextAccepted), isTrue);
      expect(turn.mark(VoiceLatencyPoint.firstRawSpeechSuffix), isTrue);
      expect(
        turn.mark(VoiceLatencyPoint.firstSynthesizableChunkUnavailable),
        isTrue,
      );
      expect(turn.mark(VoiceLatencyPoint.ttsFirstFeed), isTrue);

      expect(
        records.map((record) => record.point),
        containsAllInOrder(const <VoiceLatencyPoint>[
          VoiceLatencyPoint.firstRawSpeechSuffix,
          VoiceLatencyPoint.firstSynthesizableChunkUnavailable,
          VoiceLatencyPoint.ttsFirstFeed,
        ]),
      );
    });

    test('lease reconciliation reports unavailable without platform ACK', () {
      final exit = trace.beginTurn(
        route: VoiceLatencyRoute.phone,
        scenario: VoiceLatencyScenario.exit,
      );
      exit.mark(VoiceLatencyPoint.exitRequested);
      exit.mark(VoiceLatencyPoint.audioStopped);
      exit.mark(VoiceLatencyPoint.micReleased);

      expect(completeVoiceLeaseTrace(exit, releaseConfirmed: false), isTrue);
      expect(exit.finished, isTrue);
      expect(
        records.map((record) => record.point),
        contains(VoiceLatencyPoint.leaseReleaseUnavailable),
      );
      expect(
        records.map((record) => record.point),
        isNot(contains(VoiceLatencyPoint.leaseReleased)),
      );
    });

    test('declares streaming topology and keeps last-above unavailable', () {
      final turn = trace.beginTurn(
        route: VoiceLatencyRoute.phone,
        scenario: VoiceLatencyScenario.normal,
        sttTopology: VoiceSttTopology.streaming,
        lastAboveAvailability: VoiceLatencyAvailability.unavailable,
      );

      nowMicros = 1100;
      expect(turn.observeSpeechAboveThreshold(), isFalse);
      expect(turn.mark(VoiceLatencyPoint.speechEndpoint), isFalse);
      expect(turn.mark(VoiceLatencyPoint.sttStarted), isTrue);
      nowMicros = 1200;
      expect(turn.mark(VoiceLatencyPoint.speechEndpoint), isTrue);
      nowMicros = 1300;
      expect(turn.mark(VoiceLatencyPoint.sttFinal), isTrue);

      expect(
        records.map((record) => record.point),
        containsAllInOrder(const <VoiceLatencyPoint>[
          VoiceLatencyPoint.sttStarted,
          VoiceLatencyPoint.speechEndpoint,
          VoiceLatencyPoint.sttFinal,
        ]),
      );
      expect(
        records.map((record) => record.point),
        isNot(contains(VoiceLatencyPoint.speechLastAboveThreshold)),
      );
      for (final record in records) {
        expect(record.arguments['stt_topology'], 'streaming');
        expect(record.arguments['last_above'], 'unavailable');
      }
    });

    test(
      'record-then-transcribe flushes the last measured sample before STT',
      () {
        final turn = trace.beginTurn(
          route: VoiceLatencyRoute.server,
          scenario: VoiceLatencyScenario.bargeIn,
          sttTopology: VoiceSttTopology.recordThenTranscribe,
          lastAboveAvailability: VoiceLatencyAvailability.measured,
        );

        nowMicros = 1100;
        expect(turn.observeSpeechAboveThreshold(), isTrue);
        nowMicros = 1250;
        expect(turn.observeSpeechAboveThreshold(), isTrue);
        expect(turn.mark(VoiceLatencyPoint.sttStarted), isFalse);
        nowMicros = 2000;
        expect(turn.mark(VoiceLatencyPoint.speechEndpoint), isTrue);
        nowMicros = 2100;
        expect(turn.mark(VoiceLatencyPoint.sttStarted), isTrue);
        nowMicros = 2200;
        expect(turn.mark(VoiceLatencyPoint.sttFinal), isTrue);

        final points = records.map((record) => record.point);
        expect(
          points,
          containsAllInOrder(const <VoiceLatencyPoint>[
            VoiceLatencyPoint.speechLastAboveThreshold,
            VoiceLatencyPoint.speechEndpoint,
            VoiceLatencyPoint.sttStarted,
            VoiceLatencyPoint.sttFinal,
          ]),
        );
        final lastAbove = records.singleWhere(
          (record) =>
              record.point == VoiceLatencyPoint.speechLastAboveThreshold,
        );
        expect(lastAbove.elapsedMicros, 250);
        for (final record in records) {
          expect(record.arguments['stt_topology'], 'record_then_transcribe');
          expect(record.arguments['last_above'], 'measured');
        }
      },
    );

    test(
      'client optimistic state never aliases backend acceptance or content',
      () {
        final turn = trace.beginTurn(
          route: VoiceLatencyRoute.server,
          scenario: VoiceLatencyScenario.normal,
          sttTopology: VoiceSttTopology.streaming,
          lastAboveAvailability: VoiceLatencyAvailability.measured,
        );

        expect(turn.mark(VoiceLatencyPoint.clientOptimistic), isTrue);
        expect(turn.mark(VoiceLatencyPoint.clientOptimistic), isFalse);
        expect(
          records.map((record) => record.point),
          isNot(contains(VoiceLatencyPoint.backendAccepted)),
        );
        expect(records.where((record) => record.isContent), isEmpty);

        expect(turn.mark(VoiceLatencyPoint.submitStarted), isTrue);
        expect(turn.mark(VoiceLatencyPoint.submitAccepted), isTrue);
        expect(
          records.map((record) => record.point),
          isNot(contains(VoiceLatencyPoint.backendAccepted)),
          reason: 'local submit acceptance is not a server-authored ACK',
        );
        expect(turn.mark(VoiceLatencyPoint.backendAccepted), isTrue);
        expect(turn.mark(VoiceLatencyPoint.firstAcceptedText), isTrue);

        expect(
          records.map((record) => record.point),
          containsAllInOrder(const <VoiceLatencyPoint>[
            VoiceLatencyPoint.clientOptimistic,
            VoiceLatencyPoint.submitStarted,
            VoiceLatencyPoint.submitAccepted,
            VoiceLatencyPoint.backendAccepted,
            VoiceLatencyPoint.firstAcceptedText,
          ]),
        );
        expect(
          records.where((record) => record.isContent).single.point,
          VoiceLatencyPoint.firstAcceptedText,
        );
      },
    );

    test('bounds suffix and PCM pair histograms without content', () {
      trace = VoiceLatencyTrace.testing(
        runId: '0123456789abcdef',
        nowMicros: () => nowMicros,
        onRecord: records.add,
        histogramCapacity: 3,
      );
      final turn = trace.beginTurn(
        route: VoiceLatencyRoute.server,
        scenario: VoiceLatencyScenario.normal,
        sttTopology: VoiceSttTopology.streaming,
        lastAboveAvailability: VoiceLatencyAvailability.measured,
      );

      for (final latencyMicros in const <int>[10, 20, 30, 30]) {
        final sample = turn.beginSuffixAppendLatency();
        nowMicros += latencyMicros;
        expect(sample.accept(), isTrue);
        expect(sample.accept(), isFalse, reason: 'a pair is accepted once');
      }

      for (final latencyMicros in const <int>[5, 15]) {
        final sample = turn.beginPcmAcceptLatency();
        nowMicros += latencyMicros;
        expect(sample.accept(), isTrue);
      }
      // A receive without a positive write is not a valid PCM pair.
      turn.beginPcmAcceptLatency();
      turn.finish();

      final suffix = records.singleWhere(
        (record) => record.point == VoiceLatencyPoint.suffixAppendLatency,
      );
      final pcm = records.singleWhere(
        (record) => record.point == VoiceLatencyPoint.pcmAcceptLatency,
      );

      expect(suffix.arguments, containsPair('count', 4));
      expect(suffix.arguments, containsPair('dropped', 1));
      expect(suffix.arguments, containsPair('p50_us', 20));
      expect(suffix.arguments, containsPair('p95_us', 30));
      expect(suffix.arguments, containsPair('p99_us', 30));
      expect(suffix.arguments, containsPair('max_us', 30));
      expect(pcm.arguments, containsPair('count', 2));
      expect(pcm.arguments, containsPair('dropped', 0));
      expect(pcm.arguments, containsPair('p50_us', 5));
      expect(pcm.arguments, containsPair('p95_us', 15));
      expect(pcm.arguments, containsPair('p99_us', 15));
      expect(pcm.arguments, containsPair('max_us', 15));

      const baseKeys = <String>{
        'run_id',
        'turn',
        'route',
        'scenario',
        'point',
        'elapsed_us',
        'stt_topology',
        'last_above',
      };
      const summaryKeys = <String>{
        'count',
        'dropped',
        'p50_us',
        'p95_us',
        'p99_us',
        'max_us',
      };
      for (final record in records) {
        final expectedKeys =
            record.point == VoiceLatencyPoint.suffixAppendLatency ||
                record.point == VoiceLatencyPoint.pcmAcceptLatency
            ? <String>{...baseKeys, ...summaryKeys}
            : baseKeys;
        expect(record.arguments.keys, unorderedEquals(expectedKeys));
        expect(
          record.arguments.keys,
          isNot(
            anyOf(
              contains('transcript'),
              contains('text'),
              contains('pcm'),
              contains('url'),
              contains('token'),
              contains('samples'),
            ),
          ),
        );
      }
    });
  });
}
