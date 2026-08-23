import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/voice/conversation/voice_conversation_runtime.dart';
import 'package:hermes_android/core/services/voice/voice_phase.dart';

void main() {
  group('VoiceConversationRuntime', () {
    late VoiceConversationRuntime runtime;

    setUp(() {
      runtime = VoiceConversationRuntime();
    });

    test('el binding distingue conexion perfil y sesiones propietarias', () {
      const first = VoiceTurnBinding(
        7,
        11,
        3,
        identity: VoiceConversationIdentity(
          connectionId: 'demo-node',
          ownerProfile: 'default',
          storedSessionId: 'stored-1',
          runtimeSessionId: 'runtime-1',
        ),
      );
      const otherProfile = VoiceTurnBinding(
        7,
        11,
        3,
        identity: VoiceConversationIdentity(
          connectionId: 'demo-node',
          ownerProfile: 'work',
          storedSessionId: 'stored-1',
          runtimeSessionId: 'runtime-1',
        ),
      );
      const otherConnection = VoiceTurnBinding(
        7,
        11,
        3,
        identity: VoiceConversationIdentity(
          connectionId: 'secondary-node',
          ownerProfile: 'default',
          storedSessionId: 'stored-1',
          runtimeSessionId: 'runtime-1',
        ),
      );

      expect(first, isNot(otherProfile));
      expect(first, isNot(otherConnection));
      expect(<VoiceTurnBinding>{
        first,
        otherProfile,
        otherConnection,
      }, hasLength(3));
    });

    test('dos runtimes con epochs iguales rechazan el owner ajeno', () {
      final firstRuntime = VoiceConversationRuntime();
      final secondRuntime = VoiceConversationRuntime();
      final first = firstRuntime.start(
        backendRunning: true,
        identity: const VoiceConversationIdentity(
          connectionId: 'demo-node',
          ownerProfile: 'default',
          storedSessionId: 'shared-id',
        ),
      );
      final second = secondRuntime.start(
        backendRunning: true,
        identity: const VoiceConversationIdentity(
          connectionId: 'demo-node',
          ownerProfile: 'work',
          storedSessionId: 'shared-id',
        ),
      );

      expect(first.conversationEpoch, second.conversationEpoch);
      expect(first.operationEpoch, second.operationEpoch);
      expect(first.turn, second.turn);
      expect(secondRuntime.markBackendTerminal(first), isFalse);
      expect(secondRuntime.markBackendTerminal(second), isTrue);
    });

    test('rebind unknown a identidad resuelta fencea callbacks viejos', () {
      final unknown = runtime.start(backendRunning: true);
      const resolvedIdentity = VoiceConversationIdentity(
        connectionId: 'demo-node',
        ownerProfile: 'default',
        storedSessionId: 'stored-42',
        runtimeSessionId: 'runtime-42',
      );

      final resolved = runtime.rebindIdentity(unknown, resolvedIdentity);

      expect(resolved, isNotNull);
      expect(resolved!.conversationEpoch, unknown.conversationEpoch);
      expect(resolved.operationEpoch, greaterThan(unknown.operationEpoch));
      expect(resolved.turn, unknown.turn);
      expect(resolved.identity, resolvedIdentity);
      expect(runtime.markBackendTerminal(unknown), isFalse);
      expect(runtime.markBackendTerminal(resolved), isTrue);
    });

    test('rebind no oculta un owner fisico ni invalida su ACK', () {
      final current = runtime.start();
      final capture = runtime.claimNormalCapture()!;
      const resolvedIdentity = VoiceConversationIdentity(
        connectionId: 'demo-node',
        ownerProfile: 'default',
        storedSessionId: 'stored-42',
      );

      expect(runtime.rebindIdentity(current, resolvedIdentity), isNull);
      expect(runtime.confirmNormalCapture(capture), isTrue);
      expect(runtime.finishNormalSilence(capture), isTrue);

      final rebound = runtime.rebindIdentity(current, resolvedIdentity);
      expect(rebound, isNotNull);
      expect(rebound!.identity, resolvedIdentity);
      expect(runtime.confirmNormalCapture(capture), isFalse);
    });

    test('Start reentrante conserva el binding y todos los owners', () {
      const originalIdentity = VoiceConversationIdentity(
        connectionId: 'demo-node',
        ownerProfile: 'default',
        storedSessionId: 'stored-1',
      );
      final original = runtime.start(
        backendRunning: true,
        identity: originalIdentity,
      );
      final monitor = runtime.requestBargeMonitor(original)!;
      expect(runtime.confirmBargeMonitor(monitor), isTrue);
      final playback = runtime.preparePlayback(original)!;
      expect(runtime.confirmPlayback(playback), isTrue);

      final repeated = runtime.start(
        identity: const VoiceConversationIdentity(
          connectionId: 'secondary-node',
          ownerProfile: 'other',
          storedSessionId: 'stored-2',
        ),
      );

      expect(repeated, same(original));
      expect(repeated.identity, originalIdentity);
      expect(runtime.state.captureOwner, VoiceCaptureOwner.fullDuplex);
      expect(runtime.state.playbackOwner, VoicePlaybackOwner.streaming);
      expect(runtime.releaseBargeMonitor(monitor), isTrue);
      expect(runtime.beginPlaybackDrain(playback), isTrue);
      expect(runtime.finishPlaybackDrain(playback), isTrue);
    });

    test('publica listening solo tras el ACK de la captura vigente', () {
      runtime.start();

      final capture = runtime.claimNormalCapture();
      expect(capture, isNotNull);
      expect(runtime.state.phase, VoicePhase.idle);
      expect(runtime.state.captureOwner, VoiceCaptureOwner.normalStarting);

      expect(runtime.confirmNormalCapture(capture!), isTrue);
      expect(runtime.state.phase, VoicePhase.listening);
      expect(runtime.state.captureOwner, VoiceCaptureOwner.normal);
    });

    test('un ACK stale posterior a Exit no puede reabrir el micro', () {
      runtime.start();
      final capture = runtime.claimNormalCapture()!;

      runtime.exit();

      expect(runtime.confirmNormalCapture(capture), isFalse);
      expect(runtime.state.lifecycle, VoiceRuntimeLifecycle.inactive);
      expect(runtime.state.captureOwner, VoiceCaptureOwner.none);
      expect(runtime.state.phase, VoicePhase.idle);
    });

    test('silencio idle rearma sin proyectar transcribing', () {
      runtime.start();
      final capture = runtime.claimNormalCapture()!;
      runtime.confirmNormalCapture(capture);

      expect(runtime.finishNormalSilence(capture), isTrue);
      expect(runtime.state.phase, VoicePhase.idle);
      expect(runtime.state.transcriptionOwner, VoiceTranscriptionOwner.none);
      expect(runtime.state.rearmReady, isTrue);

      final next = runtime.claimNormalCapture();
      expect(next, isNotNull);
      expect(runtime.claimNormalCapture(), isNull);
    });

    test('el rearme espera terminal backend y drain físico', () {
      runtime.start();
      final capture = runtime.claimNormalCapture()!;
      runtime.confirmNormalCapture(capture);
      runtime.beginNormalTranscription(capture);
      final turn = runtime.finishNormalTranscription(
        capture,
        'dime las noticias',
      )!;

      expect(runtime.state.phase, VoicePhase.thinking);
      expect(runtime.markBackendRunning(turn), isTrue);
      final playback = runtime.preparePlayback(turn)!;
      expect(runtime.state.phase, VoicePhase.thinking);
      expect(runtime.confirmPlayback(playback), isTrue);
      expect(runtime.state.phase, VoicePhase.speaking);

      expect(runtime.markBackendTerminal(turn), isTrue);
      expect(runtime.state.rearmReady, isFalse);
      expect(runtime.claimNormalCapture(), isNull);

      expect(runtime.beginPlaybackDrain(playback), isTrue);
      expect(runtime.state.rearmReady, isFalse);
      expect(runtime.finishPlaybackDrain(playback), isTrue);
      expect(runtime.state.phase, VoicePhase.idle);
      expect(runtime.state.rearmReady, isTrue);
      expect(runtime.claimNormalCapture(), isNotNull);
    });

    test('barge conserva un solo recorder hasta endpoint', () {
      final original = runtime.start(backendRunning: true);
      final monitor = runtime.requestBargeMonitor(original)!;

      expect(runtime.confirmBargeMonitor(monitor), isTrue);
      expect(runtime.state.captureOwner, VoiceCaptureOwner.fullDuplex);
      expect(runtime.state.phase, VoicePhase.thinking);
      expect(runtime.claimNormalCapture(), isNull);

      expect(runtime.beginBargeSpeech(monitor), isTrue);
      expect(runtime.state.captureOwner, VoiceCaptureOwner.fullDuplex);
      expect(runtime.state.phase, VoicePhase.thinking);
      expect(runtime.beginBargeTranscription(monitor), isTrue);
      expect(runtime.state.captureOwner, VoiceCaptureOwner.none);
      expect(
        runtime.state.transcriptionOwner,
        VoiceTranscriptionOwner.fullDuplex,
      );
      expect(runtime.state.phase, VoicePhase.transcribing);

      final correction = runtime.finishBargeTranscription(
        monitor,
        'y también las de ayer',
      );
      expect(correction, isNotNull);
      expect(correction, isNot(original));
      expect(runtime.state.backendState, VoiceBackendState.submitting);
      expect(runtime.state.phase, VoicePhase.thinking);
    });

    test('terminal viejo no finaliza el turno creado por barge-in', () {
      final original = runtime.start(backendRunning: true);
      final monitor = runtime.requestBargeMonitor(original)!;
      runtime.confirmBargeMonitor(monitor);
      runtime.beginBargeSpeech(monitor);
      runtime.beginBargeTranscription(monitor);
      final correction = runtime.finishBargeTranscription(
        monitor,
        'corrige el enfoque',
      )!;

      expect(runtime.markBackendTerminal(original), isFalse);
      expect(runtime.state.currentTurn, correction);
      expect(runtime.state.backendState, VoiceBackendState.submitting);
      expect(runtime.state.rearmReady, isFalse);
    });

    test('drain tardío de barge sobrevive al nuevo submit sin rearmar', () {
      runtime.start();
      final capture = runtime.claimNormalCapture()!;
      runtime.confirmNormalCapture(capture);
      runtime.beginNormalTranscription(capture);
      final first = runtime.finishNormalTranscription(capture, 'primero')!;
      runtime.markBackendRunning(first);
      final oldPlayback = runtime.preparePlayback(first)!;
      runtime.confirmPlayback(oldPlayback);

      final monitor = runtime.requestBargeMonitor(first)!;
      runtime.confirmBargeMonitor(monitor);
      runtime.beginBargeSpeech(monitor);
      expect(runtime.state.playbackOwner, VoicePlaybackOwner.draining);
      expect(runtime.state.rearmReady, isFalse);
      runtime.beginBargeTranscription(monitor);
      final second = runtime.finishBargeTranscription(monitor, 'segundo')!;

      expect(runtime.finishPlaybackDrain(oldPlayback), isTrue);
      expect(runtime.state.currentTurn, second);
      expect(runtime.state.backendState, VoiceBackendState.submitting);
      expect(runtime.state.phase, VoicePhase.thinking);
      expect(runtime.state.playbackOwner, VoicePlaybackOwner.none);
      expect(runtime.state.rearmReady, isFalse);
    });

    test('aprobación bloquea owners y resolverla rearma una sola vez', () {
      final turn = runtime.start(backendRunning: true);

      final waiting = runtime.waitForInput(turn);
      expect(waiting, isNotNull);
      expect(runtime.state.phase, VoicePhase.waitingPermission);
      expect(runtime.requestBargeMonitor(turn), isNull);
      expect(runtime.claimNormalCapture(), isNull);

      expect(
        runtime.resolveInput(waiting!.binding, backendRunning: false),
        isTrue,
      );
      expect(runtime.state.phase, VoicePhase.idle);
      expect(runtime.state.rearmReady, isTrue);
      expect(runtime.claimNormalCapture(), isNotNull);
      expect(runtime.claimNormalCapture(), isNull);
    });

    test('Pause y privacidad invalidan callbacks sin auto-resume', () {
      runtime.start();
      final capture = runtime.claimNormalCapture()!;
      runtime.confirmNormalCapture(capture);

      runtime.pauseByUser();
      expect(runtime.state.lifecycle, VoiceRuntimeLifecycle.userPaused);
      expect(runtime.state.captureOwner, VoiceCaptureOwner.none);
      expect(runtime.confirmNormalCapture(capture), isFalse);
      expect(runtime.state.rearmReady, isFalse);

      runtime.resumeByUser();
      expect(runtime.state.rearmReady, isTrue);
      final resumed = runtime.claimNormalCapture()!;
      runtime.confirmNormalCapture(resumed);

      runtime.hardPauseForPrivacy();
      expect(runtime.state.lifecycle, VoiceRuntimeLifecycle.privacyPaused);
      expect(runtime.state.captureOwner, VoiceCaptureOwner.none);
      expect(runtime.state.rearmReady, isFalse);
      runtime.releasePrivacyFence();
      expect(runtime.state.lifecycle, VoiceRuntimeLifecycle.userPaused);
      expect(runtime.state.rearmReady, isFalse);
    });

    test('Pause conserva un stream PCM reanudable y su mismo token', () {
      final turn = runtime.start(backendRunning: true);
      final playback = runtime.preparePlayback(turn)!;
      runtime.confirmPlayback(playback);

      runtime.pauseByUser(preservePlayback: true);
      expect(runtime.state.lifecycle, VoiceRuntimeLifecycle.userPaused);
      expect(runtime.state.playbackOwner, VoicePlaybackOwner.paused);

      runtime.resumeByUser(resumePlayback: true);
      expect(runtime.state.lifecycle, VoiceRuntimeLifecycle.running);
      expect(runtime.state.playbackOwner, VoicePlaybackOwner.streaming);
      expect(runtime.state.phase, VoicePhase.speaking);
      expect(runtime.beginPlaybackDrain(playback), isTrue);
      expect(runtime.finishPlaybackDrain(playback), isTrue);
    });

    test(
      'Pause conserva preparing y Resume restaura exactamente ese owner',
      () {
        final turn = runtime.start(backendRunning: true);
        final playback = runtime.preparePlayback(turn)!;

        final pause = runtime.pauseByUser(preservePlayback: true)!;
        expect(pause.playbackPreserved, isTrue);
        expect(runtime.state.playbackOwner, VoicePlaybackOwner.paused);

        expect(runtime.resumeByUser(), isNull);
        expect(runtime.state.lifecycle, VoiceRuntimeLifecycle.userPaused);
        expect(runtime.state.playbackOwner, VoicePlaybackOwner.paused);

        expect(runtime.resumeByUser(resumePlayback: true), turn);
        expect(runtime.state.playbackOwner, VoicePlaybackOwner.preparing);
        expect(runtime.confirmPlayback(playback), isTrue);
        expect(runtime.state.playbackOwner, VoicePlaybackOwner.streaming);
      },
    );

    test('Pause terminal conserva owner hasta ACK de drain', () {
      final turn = runtime.start();
      final playback = runtime.preparePlayback(turn)!;
      runtime.confirmPlayback(playback, owner: VoicePlaybackOwner.fallback);

      final pause = runtime.pauseByUser()!;
      expect(pause.playbackPreserved, isFalse);
      expect(pause.playbackDrainToken, playback);
      expect(runtime.state.playbackOwner, VoicePlaybackOwner.draining);
      expect(runtime.resumeByUser(), isNull);
      expect(runtime.finishPlaybackDrain(playback), isTrue);
      expect(runtime.resumeByUser(), turn);
    });

    test('nunca expone dos owners de AudioRecord o playback', () {
      final turn = runtime.start(backendRunning: true);
      final monitor = runtime.requestBargeMonitor(turn)!;
      runtime.confirmBargeMonitor(monitor);

      expect(runtime.claimNormalCapture(), isNull);
      final playback = runtime.preparePlayback(turn)!;
      expect(runtime.preparePlayback(turn), isNull);
      expect(runtime.confirmPlayback(playback), isTrue);
      expect(runtime.state.hasSingleOwnerInvariant, isTrue);
    });

    test('toolCall gana la proyeccion sin cortar el playback activo', () {
      final turn = runtime.start(backendRunning: true);
      final playback = runtime.preparePlayback(turn)!;
      runtime.confirmPlayback(playback);

      expect(runtime.markToolActive(turn, active: true), isTrue);
      expect(runtime.state.phase, VoicePhase.toolCall);
      expect(runtime.state.playbackOwner, VoicePlaybackOwner.streaming);

      expect(runtime.markToolActive(turn, active: false), isTrue);
      expect(runtime.state.phase, VoicePhase.speaking);
      expect(runtime.state.playbackOwner, VoicePlaybackOwner.streaming);
    });

    test('fallo de start queda cerrado hasta Retry explícito', () {
      runtime.start();
      final capture = runtime.claimNormalCapture()!;

      expect(runtime.failNormalCapture(capture), isTrue);
      expect(runtime.confirmNormalCapture(capture), isFalse);
      expect(runtime.state.rearmReady, isFalse);
      expect(runtime.requestRearmAfterFailure(), isTrue);
      expect(runtime.requestRearmAfterFailure(), isFalse);
      expect(runtime.claimNormalCapture(), isNotNull);
    });

    test('fallo STT libera owner y callbacks pausados quedan stale', () {
      runtime.start();
      final capture = runtime.claimNormalCapture()!;
      runtime.confirmNormalCapture(capture);
      runtime.beginNormalTranscription(capture);

      expect(runtime.failTranscription(capture), isTrue);
      expect(runtime.state.transcriptionOwner, VoiceTranscriptionOwner.none);
      expect(runtime.state.rearmReady, isTrue);

      final next = runtime.claimNormalCapture()!;
      runtime.confirmNormalCapture(next);
      runtime.beginNormalTranscription(next);
      runtime.pauseByUser();
      expect(runtime.failTranscription(next), isFalse);
      expect(runtime.state.rearmReady, isFalse);
    });

    test('queued y fallo de submit no se convierten en running stale', () {
      runtime.start();
      final capture = runtime.claimNormalCapture()!;
      runtime.confirmNormalCapture(capture);
      runtime.beginNormalTranscription(capture);
      final turn = runtime.finishNormalTranscription(capture, 'hola')!;

      expect(runtime.markSubmissionQueued(turn), isTrue);
      expect(runtime.state.backendState, VoiceBackendState.queued);
      expect(runtime.failSubmission(turn), isTrue);
      expect(runtime.state.rearmReady, isTrue);
      expect(runtime.markBackendRunning(turn), isFalse);
    });

    test('fallo de submit conserva rearme mientras cierra full-duplex', () {
      runtime.start();
      final capture = runtime.claimNormalCapture()!;
      runtime.confirmNormalCapture(capture);
      runtime.beginNormalTranscription(capture);
      final turn = runtime.finishNormalTranscription(capture, 'hola')!;
      final monitor = runtime.requestBargeMonitor(turn)!;
      runtime.confirmBargeMonitor(monitor);

      expect(runtime.failSubmission(turn), isTrue);
      expect(runtime.state.rearmRequested, isTrue);
      expect(runtime.state.rearmReady, isFalse);

      expect(runtime.releaseBargeMonitor(monitor), isTrue);
      expect(runtime.state.rearmRequested, isTrue);
      expect(runtime.state.rearmReady, isTrue);
    });

    test('waitingInput rota binding y no admite running tardío', () {
      final turn = runtime.start(backendRunning: true);
      final waiting = runtime.waitForInput(turn)!;

      expect(waiting.binding, isNot(turn));
      expect(runtime.markBackendRunning(turn), isFalse);
      expect(runtime.markBackendRunning(waiting.binding), isFalse);
      expect(
        runtime.resolveInput(waiting.binding, backendRunning: false),
        isTrue,
      );
    });

    test('waitingInput no libera playback antes del teardown', () {
      final turn = runtime.start(backendRunning: true);
      final playback = runtime.preparePlayback(turn)!;
      runtime.confirmPlayback(playback);

      final waiting = runtime.waitForInput(turn)!;
      expect(waiting.playbackDrainToken, isNotNull);
      expect(runtime.state.playbackOwner, VoicePlaybackOwner.draining);
      expect(runtime.state.phase, VoicePhase.waitingPermission);
      expect(
        runtime.resolveInput(waiting.binding, backendRunning: false),
        isTrue,
      );
      expect(runtime.state.rearmReady, isFalse);
      expect(runtime.finishPlaybackDrain(waiting.playbackDrainToken!), isTrue);
      expect(runtime.state.rearmReady, isTrue);
    });

    test('preparation failure y drain físico gobiernan el rearme', () {
      final turn = runtime.start();
      final preparing = runtime.preparePlayback(turn)!;
      expect(runtime.failPlaybackPreparation(preparing), isTrue);
      expect(runtime.state.rearmReady, isTrue);

      final playback = runtime.preparePlayback(turn)!;
      runtime.confirmPlayback(playback);
      expect(runtime.abortPlayback(playback), isTrue);
      expect(runtime.state.playbackOwner, VoicePlaybackOwner.draining);
      expect(runtime.state.rearmReady, isFalse);
      expect(runtime.requestRearmAfterFailure(), isFalse);
      expect(runtime.finishPlaybackDrain(playback), isTrue);
      expect(runtime.state.rearmReady, isTrue);
    });

    test('Stop-and-talk busy conserva el run para redirect o cola', () {
      final oldTurn = runtime.start(backendRunning: true);
      final monitor = runtime.requestBargeMonitor(oldTurn)!;
      runtime.confirmBargeMonitor(monitor);
      final playback = runtime.preparePlayback(oldTurn)!;
      runtime.confirmPlayback(playback);

      final claim = runtime.requestManualInterruptionCapture(oldTurn)!;

      expect(claim.binding, isNot(oldTurn));
      expect(claim.shouldInterruptBackend, isFalse);
      expect(claim.cancelledPlayback, isTrue);
      expect(claim.playbackDrainToken, isNotNull);
      expect(runtime.state.backendState, VoiceBackendState.running);
      expect(runtime.state.captureOwner, VoiceCaptureOwner.normalStarting);
      expect(runtime.state.playbackOwner, VoicePlaybackOwner.draining);
      expect(runtime.requestManualInterruptionCapture(claim.binding), isNull);
      expect(runtime.releaseBargeMonitor(monitor), isFalse);
      expect(runtime.finishPlaybackDrain(playback), isFalse);

      expect(runtime.confirmNormalCapture(claim.captureToken), isTrue);
      expect(runtime.state.phase, VoicePhase.listening);
      expect(runtime.markBackendTerminal(claim.binding), isTrue);
      expect(runtime.state.backendState, VoiceBackendState.idle);
      expect(runtime.finishPlaybackDrain(claim.playbackDrainToken!), isTrue);
      expect(runtime.state.phase, VoicePhase.listening);
    });

    test('Stop-and-talk idle captura sin inventar interrupt', () {
      final turn = runtime.start();
      final claim = runtime.requestManualInterruptionCapture(turn)!;

      expect(claim.shouldInterruptBackend, isFalse);
      expect(claim.cancelledPlayback, isFalse);
      expect(runtime.state.backendState, VoiceBackendState.idle);
      expect(runtime.confirmNormalCapture(claim.captureToken), isTrue);
    });

    test('App Lock fencea binding y Play explícito adopta el nuevo', () {
      final oldTurn = runtime.start(backendRunning: true);
      final privacyTurn = runtime.hardPauseForPrivacy()!;

      expect(privacyTurn.turn, oldTurn.turn);
      expect(
        privacyTurn.conversationEpoch,
        greaterThan(oldTurn.conversationEpoch),
      );
      expect(runtime.markBackendTerminal(oldTurn), isFalse);
      expect(runtime.releasePrivacyFence(), privacyTurn);
      expect(runtime.state.rearmReady, isFalse);
      expect(runtime.resumeByUser(), privacyTurn);
      expect(runtime.markBackendTerminal(privacyTurn), isTrue);
      expect(runtime.claimNormalCapture(), isNotNull);
    });

    test('App Lock repetido conserva la misma valla de privacidad', () {
      runtime.start(backendRunning: true);

      final first = runtime.hardPauseForPrivacy()!;
      final second = runtime.hardPauseForPrivacy()!;

      expect(second, same(first));
      expect(second.conversationEpoch, first.conversationEpoch);
      expect(second.operationEpoch, first.operationEpoch);
      expect(runtime.state.lifecycle, VoiceRuntimeLifecycle.privacyPaused);
    });

    test('Exit repetido conserva fence y el primero puede finalizar', () {
      runtime.start(backendRunning: true);

      final first = runtime.beginExit()!;
      final second = runtime.beginExit()!;

      expect(second, same(first));
      expect(runtime.state.lifecycle, VoiceRuntimeLifecycle.exiting);
      expect(runtime.finishExit(first), isTrue);
      expect(runtime.state.lifecycle, VoiceRuntimeLifecycle.inactive);
    });

    test('App Lock durante Exit no sustituye ni invalida su fence', () {
      runtime.start(backendRunning: true);
      final fence = runtime.beginExit()!;

      expect(runtime.hardPauseForPrivacy(), same(fence));
      expect(runtime.state.lifecycle, VoiceRuntimeLifecycle.exiting);
      expect(runtime.state.currentTurn, same(fence));
      expect(runtime.finishExit(fence), isTrue);
      expect(runtime.state.lifecycle, VoiceRuntimeLifecycle.inactive);
    });

    test(
      'Exit en dos fases conserva owners hasta teardown y fencea callbacks',
      () {
        runtime.start();
        final capture = runtime.claimNormalCapture()!;
        runtime.confirmNormalCapture(capture);

        final fence = runtime.beginExit()!;
        expect(runtime.state.lifecycle, VoiceRuntimeLifecycle.exiting);
        expect(runtime.state.captureOwner, VoiceCaptureOwner.normal);
        expect(runtime.confirmNormalCapture(capture), isFalse);
        expect(runtime.finishExit(fence), isTrue);
        expect(runtime.state.lifecycle, VoiceRuntimeLifecycle.inactive);
      },
    );
  });
}
