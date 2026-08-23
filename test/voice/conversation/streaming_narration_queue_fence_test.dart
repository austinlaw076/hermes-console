import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/voice/conversation/streaming_narration_queue.dart';

/// Spec 048 / US1 — valla de reproducción (contracts/narration-fence.md).
///
/// La cola solo invalida la reproducción (`revisionChanged`) cuando la
/// divergencia cae POR DEBAJO de la valla fijada por el controlador; una
/// divergencia en o después de la valla sustituye la cola pendiente sin
/// tocar revisión ni cursor.
void main() {
  StreamingNarrationQueue queue() => StreamingNarrationQueue(language: 'es');

  test('append puro sigue sin cambiar la revisión con valla activa', () {
    final q = queue();
    q.observe('Uno. ');
    expect(q.chunks.map((c) => c.text), ['Uno.']);
    q.markPlaybackThrough(1);

    final update = q.observe('Uno. Dos y ');

    expect(update.revisionChanged, isFalse);
    expect(q.cursor, 0);
  });

  test('divergencia por delante de la valla no invalida la reproducción', () {
    final q = queue();
    q.observe('Uno. Dos. Tres.', terminal: true);
    expect(q.chunks.map((c) => c.text), ['Uno.', 'Dos.', 'Tres.']);
    final revision = q.revision;
    expect(q.completeCurrent(revision), isTrue); // cursor = 1
    q.markPlaybackThrough(2); // lote sonando: [1, 2)

    final update = q.observe('Uno. Dos. Tres cambiado.', terminal: true);

    expect(update.revisionChanged, isFalse);
    expect(q.revision, revision);
    expect(q.cursor, 1);
    expect(q.chunks.map((c) => c.text), ['Uno.', 'Dos.', 'Tres cambiado.']);
    // La completion del lote sonando sigue siendo válida.
    expect(q.completeCurrent(revision), isTrue);
    expect(q.current?.text, 'Tres cambiado.');
  });

  test('divergencia exactamente en la valla tampoco invalida', () {
    final q = queue();
    q.observe('Uno. Dos.', terminal: true);
    final revision = q.revision;
    q.markPlaybackThrough(1); // solo "Uno." comprometido

    final update = q.observe('Uno. Dos cambiado.', terminal: true);

    expect(update.revisionChanged, isFalse);
    expect(q.revision, revision);
    expect(q.chunks.map((c) => c.text), ['Uno.', 'Dos cambiado.']);
  });

  test('divergencia bajo la valla conserva la semántica de corte', () {
    final q = queue();
    q.observe('Uno. Dos. Tres.', terminal: true);
    final revision = q.revision;
    expect(q.completeCurrent(revision), isTrue); // cursor = 1
    q.markPlaybackThrough(2);

    final update = q.observe('Cero. Dos. Tres.', terminal: true);

    expect(update.revisionChanged, isTrue);
    expect(q.revision, isNot(revision));
    expect(q.cursor, 0);
    expect(q.completeCurrent(revision), isFalse);
  });

  test('la valla se clampa a la cola y nunca baja del cursor', () {
    final q = queue();
    q.observe('Uno. Dos.', terminal: true);
    final revision = q.revision;
    expect(q.completeCurrent(revision), isTrue); // cursor = 1
    q.markPlaybackThrough(99); // clamp a chunks.length

    final update = q.observe('Uno. Dos cambiado. Tres.', terminal: true);

    // Divergencia en 1 < valla(2): toca el chunk comprometido → corta.
    expect(update.revisionChanged, isTrue);

    q.markPlaybackThrough(0); // clamp al cursor vigente
    expect(() => q.completeCurrent(q.revision), returnsNormally);
  });

  test('reset y silence reinician la valla', () {
    final q = queue();
    q.observe('Uno. Dos.', terminal: true);
    q.markPlaybackThrough(2);
    q.reset();

    q.observe('Nuevo turno. Sigue.', terminal: true);
    final revision = q.revision;
    // Sin valla nueva, una divergencia en 0 no debe heredar la valla vieja:
    // divergencia 0 ≥ valla(0 tras reset) → sin corte.
    final update = q.observe('Nuevo turno distinto. Sigue.', terminal: true);
    expect(update.revisionChanged, isFalse);
    expect(q.revision, revision);

    q.markPlaybackThrough(2);
    q.silence();
    // silence() reinicia la valla al cursor: la siguiente revisión decide
    // desde cero sin arrastrar compromiso de reproducción.
    final after = q.observe('Otra cosa completamente. Final.', terminal: true);
    expect(after.revisionChanged, isFalse);
  });
}
