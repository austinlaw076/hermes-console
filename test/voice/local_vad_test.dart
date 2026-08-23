// Tests unitarios de LocalVad (spec 025 F2, T014/T017). Sin sherpa-onnx: el
// detector es un fake inyectado (bool Function(Float32List)) que decide voz
// según la amplitud codificada en el propio PCM16 de prueba — así los tests
// ejercitan exclusivamente la máquina de estados de
// lib/core/services/voice/vad/local_vad.dart (windowing, debounce de
// arranque, hangover, cómputo de voicedSecs), sin tocar el motor real.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/voice/vad/local_vad.dart';

/// Deja correr la cola de microtareas (los `StreamController` usados aquí
/// son asíncronos por defecto: `add`/`close` no entregan a los listeners de
/// forma síncrona). Mismo patrón que voice_session_test.dart.
Future<void> _flush() => Future<void>.delayed(Duration.zero);

/// Ventana de PCM16LE (512 muestras) toda al mismo nivel: alto (voz) o cero
/// (silencio). El contenido real es irrelevante para la FSM de LocalVad;
/// solo importa que [_fakeIsSpeech] lo clasifique de forma consistente.
Uint8List _window({required bool voiced}) {
  final bytes = Uint8List(kLocalVadWindowSize * 2);
  final bd = ByteData.sublistView(bytes);
  final amplitude = voiced ? 20000 : 0;
  for (var i = 0; i < kLocalVadWindowSize; i++) {
    bd.setInt16(i * 2, amplitude, Endian.little);
  }
  return bytes;
}

bool _fakeIsSpeech(Float32List window) =>
    window.isNotEmpty && window[0].abs() > 0.3;

Uint8List _concat(List<Uint8List> parts) {
  final total = parts.fold<int>(0, (n, p) => n + p.length);
  final out = Uint8List(total);
  var offset = 0;
  for (final p in parts) {
    out.setRange(offset, offset + p.length, p);
    offset += p.length;
  }
  return out;
}

/// Trocea [all] en chunks de tamaños tomados (cíclicamente) de [sizes], NO
/// alineados a `kLocalVadWindowSize * 2` bytes: simula un stream de
/// micrófono real, que no promete tamaños de chunk múltiplos de la ventana.
List<Uint8List> _irregularChunks(Uint8List all, List<int> sizes) {
  final chunks = <Uint8List>[];
  var offset = 0;
  var i = 0;
  while (offset < all.length) {
    final size = math.min(sizes[i % sizes.length], all.length - offset);
    chunks.add(Uint8List.sublistView(all, offset, offset + size));
    offset += size;
    i++;
  }
  return chunks;
}

/// Adjunta [vad] a un stream construido a partir de [chunks] (uno por
/// llamada a `add`), cierra el stream y espera a que se entreguen todos los
/// eventos pendientes.
Future<List<VadEvent>> _drive(LocalVad vad, List<Uint8List> chunks) async {
  final events = <VadEvent>[];
  vad.events.listen(events.add);
  final controller = StreamController<Uint8List>();
  vad.attach(controller.stream);
  for (final chunk in chunks) {
    controller.add(chunk);
  }
  await controller.close();
  await _flush();
  await _flush();
  return events;
}

/// Segundos de voz esperados para [n] ventanas continuas a 16kHz/512.
double _secsFor(int windowCount) => windowCount * kLocalVadWindowSize / 16000;

void main() {
  group('LocalVad', () {
    test('voz continua produce un único speechStart', () async {
      final vad = LocalVad(isSpeech: _fakeIsSpeech);
      final chunks = List.generate(10, (_) => _window(voiced: true));

      final events = await _drive(vad, chunks);

      expect(events, hasLength(1));
      expect(events.single.kind, VadEventKind.speechStart);
    });

    test('silencio sostenido tras voz (>= hangover) cierra el turno con '
        'voicedSecs correcto', () async {
      final vad = LocalVad(isSpeech: _fakeIsSpeech);
      const voicedWindows = 10;
      // hangover por defecto = 600ms = 9600 muestras = 18.75 ventanas de
      // 512: 25 ventanas de silencio son de sobra para cruzar el umbral.
      final chunks = [
        ...List.generate(voicedWindows, (_) => _window(voiced: true)),
        ...List.generate(25, (_) => _window(voiced: false)),
      ];

      final events = await _drive(vad, chunks);

      expect(events, hasLength(2));
      expect(events[0].kind, VadEventKind.speechStart);
      expect(events[1].kind, VadEventKind.speechEnd);
      // Tolerancia ±1 ventana (32ms a 16kHz/512).
      expect(
        events[1].voicedSecs,
        closeTo(_secsFor(voicedWindows), kLocalVadWindowSize / 16000),
      );
    });

    test('ruido intermitente corto (bajo el mínimo de ventanas) no emite '
        'ningún evento', () async {
      final vad = LocalVad(isSpeech: _fakeIsSpeech); // minSpeechWindows = 2
      // Cada ráfaga es UNA sola ventana con voz rodeada de silencio: nunca
      // llega a 2 ventanas de voz consecutivas, así que nunca se confirma
      // un turno.
      final chunks = <Uint8List>[];
      for (var i = 0; i < 15; i++) {
        chunks.add(_window(voiced: true));
        chunks.addAll(List.generate(3, (_) => _window(voiced: false)));
      }

      final events = await _drive(vad, chunks);

      expect(events, isEmpty);
    });

    test('dos turnos seguidos producen dos pares start/end', () async {
      final vad = LocalVad(isSpeech: _fakeIsSpeech);
      const voicedWindows = 10;
      Iterable<Uint8List> turn() sync* {
        yield* List.generate(voicedWindows, (_) => _window(voiced: true));
        yield* List.generate(25, (_) => _window(voiced: false));
      }

      final chunks = [...turn(), ...turn()];

      final events = await _drive(vad, chunks);

      expect(events, hasLength(4));
      expect(events.map((e) => e.kind).toList(), [
        VadEventKind.speechStart,
        VadEventKind.speechEnd,
        VadEventKind.speechStart,
        VadEventKind.speechEnd,
      ]);
      for (final end in [events[1], events[3]]) {
        expect(
          end.voicedSecs,
          closeTo(_secsFor(voicedWindows), kLocalVadWindowSize / 16000),
        );
      }
    });

    test('chunks de tamaños irregulares (no múltiplos de 512) no pierden '
        'muestras', () async {
      const voicedWindows = 10;
      final referenceBytes = _concat([
        ...List.generate(voicedWindows, (_) => _window(voiced: true)),
        ...List.generate(25, (_) => _window(voiced: false)),
      ]);

      // Referencia: el mismo audio entregado ventana a ventana.
      final reference = await _drive(LocalVad(isSpeech: _fakeIsSpeech), [
        for (var o = 0; o < referenceBytes.length; o += kLocalVadWindowSize * 2)
          Uint8List.sublistView(referenceBytes, o, o + kLocalVadWindowSize * 2),
      ]);

      // Mismo audio, pero trozeado en chunks irregulares (ninguno múltiplo
      // de kLocalVadWindowSize*2 = 1024 bytes).
      final irregular = await _drive(
        LocalVad(isSpeech: _fakeIsSpeech),
        _irregularChunks(referenceBytes, [37, 511, 1300, 999, 5, 2048, 3]),
      );

      expect(irregular, hasLength(2));
      expect(irregular.map((e) => e.kind).toList(), [
        VadEventKind.speechStart,
        VadEventKind.speechEnd,
      ]);
      // Resultado bit-idéntico al de referencia: el trocear en chunks
      // irregulares no debe cambiar ni el número de eventos ni voicedSecs.
      expect(irregular.length, reference.length);
      expect(irregular[1].voicedSecs, reference[1].voicedSecs);
    });
  });
}
