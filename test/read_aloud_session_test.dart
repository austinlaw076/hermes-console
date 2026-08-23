import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/voice/read_aloud_session.dart';
import 'package:hermes_android/core/services/voice/speech_renderer.dart';

void main() {
  const chunks = [
    ReadAloudChunk('Primera frase.', NarrationPause.none),
    ReadAloudChunk('Segunda frase.', NarrationPause.medium),
    ReadAloudChunk('Tercera frase.', NarrationPause.long),
  ];

  group('ReadAloudSession', () {
    test('pausa conserva el chunk que estaba reproduciéndose', () {
      final session = ReadAloudSession();
      final epoch = session.begin(
        messageKey: 'session:message',
        revision: 'r1',
        chunks: chunks,
        origin: ReadAloudOrigin.manual,
      );

      session.markPlaying(epoch);
      session.pause(discard: false);

      expect(session.snapshot.phase, ReadAloudPhase.paused);
      expect(session.snapshot.cursor, 0);
      expect(session.snapshot.messageKey, 'session:message');
      expect(session.snapshot.epoch, isNot(epoch));
    });

    test('reanuda en la frase interrumpida y avanza solo al completarla', () {
      final session = ReadAloudSession();
      var epoch = session.begin(
        messageKey: 'm',
        revision: 'r1',
        chunks: chunks,
        origin: ReadAloudOrigin.manual,
      );
      session.markPlaying(epoch);
      session.completeChunk(epoch);
      session.markPlaying(epoch);
      session.pause(discard: false);

      epoch = session.resume();
      expect(session.snapshot.cursor, 1);
      expect(session.currentChunk?.text, 'Segunda frase.');

      session.markPlaying(epoch);
      session.completeChunk(epoch);
      expect(session.snapshot.cursor, 2);
      expect(session.currentChunk?.text, 'Tercera frase.');
    });

    test('un completion de una epoch antigua no pisa la sesión nueva', () {
      final session = ReadAloudSession();
      final stale = session.begin(
        messageKey: 'a',
        revision: 'r1',
        chunks: chunks,
        origin: ReadAloudOrigin.manual,
      );
      final current = session.begin(
        messageKey: 'b',
        revision: 'r2',
        chunks: chunks,
        origin: ReadAloudOrigin.manual,
      );

      session.completeChunk(stale);

      expect(session.snapshot.messageKey, 'b');
      expect(session.snapshot.cursor, 0);
      expect(session.snapshot.epoch, current);
    });

    test('detener y reiniciar descarta identidad, chunks y cursor', () {
      final session = ReadAloudSession();
      final epoch = session.begin(
        messageKey: 'm',
        revision: 'r1',
        chunks: chunks,
        origin: ReadAloudOrigin.manual,
      );
      session.markPlaying(epoch);
      session.completeChunk(epoch);

      session.pause(discard: true);

      expect(session.snapshot.phase, ReadAloudPhase.idle);
      expect(session.snapshot.messageKey, isNull);
      expect(session.snapshot.chunks, isEmpty);
      expect(session.snapshot.cursor, 0);
    });

    test('cambiar la revisión no reanuda un cursor obsoleto', () {
      final session = ReadAloudSession();
      final first = session.begin(
        messageKey: 'm',
        revision: 'r1',
        chunks: chunks,
        origin: ReadAloudOrigin.manual,
      );
      session.markPlaying(first);
      session.completeChunk(first);
      session.pause(discard: false);

      session.begin(
        messageKey: 'm',
        revision: 'r2',
        chunks: const [ReadAloudChunk('Texto corregido.', NarrationPause.long)],
        origin: ReadAloudOrigin.manual,
      );

      expect(session.snapshot.cursor, 0);
      expect(session.snapshot.revision, 'r2');
      expect(session.currentChunk?.text, 'Texto corregido.');
    });
  });

  group('chunkNarrationSegments', () {
    test('limita longitud y conserva la pausa solo en el último chunk', () {
      final chunks = chunkNarrationSegments(const [
        NarrationSegment(
          'Una frase deliberadamente larga que debe dividirse por palabras '
          'sin perder ninguna parte del contenido ni cortar caracteres.',
          NarrationSourceKind.paragraph,
          NarrationPause.long,
        ),
      ], maxChars: 48);

      expect(chunks.length, greaterThan(1));
      expect(chunks.every((chunk) => chunk.text.length <= 48), isTrue);
      expect(
        chunks
            .take(chunks.length - 1)
            .every((chunk) => chunk.pauseAfter == NarrationPause.none),
        isTrue,
      );
      expect(chunks.last.pauseAfter, NarrationPause.long);
    });
  });
}
