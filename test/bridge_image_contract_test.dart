import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contrato del endpoint GET /bridge/image (spec 030, bridge >= 1.12.0).
///
/// Igual que server_setup_generator_test.dart con los scripts de setup: el
/// bridge es un artefacto Python empaquetado en assets; estos tests leen el
/// archivo del disco y fijan las garantías de seguridad del contrato
/// (docs/UPSTREAM_CONTRACT.md) para que
/// nadie las relaje sin romper la suite.
void main() {
  final src = File('assets/bridge/hermes_bridge.py').readAsStringSync();

  group('GET /bridge/image — contrato de seguridad (spec 030)', () {
    test('la version empaquetada es 1.18.0 (capacidad detectable)', () {
      expect(src, contains('VERSION = "1.18.0"'));
    });

    test('el handler existe y la ruta esta registrada', () {
      expect(src, contains('async def image_get(request):'));
      expect(src, contains('app.router.add_get("/bridge/image", image_get)'));
    });

    test('exige auth con scope read (funciona en instancias solo-lectura)', () {
      final handler = _handlerBody(src);
      expect(handler, contains('_check_auth(request, "read")'));
    });

    test('guard de basename: rechaza separadores, .. y charset raro', () {
      final handler = _handlerBody(src);
      expect(handler, contains('"/" in name'));
      expect(handler, contains(r'"\\" in name'));
      expect(handler, contains('".." in name'));
      expect(
        src,
        contains(r'_IMAGE_NAME_RE = re.compile(r"^[A-Za-z0-9._-]+$")'),
      );
    });

    test(
      'resolucion canonica bajo el directorio de imagenes (anti-symlink)',
      () {
        expect(
          src,
          contains('IMAGES_DIR = (HERMES_HOME / "cache" / "images").resolve()'),
        );
        final handler = _handlerBody(src);
        expect(handler, contains('(IMAGES_DIR / name).resolve()'));
        expect(handler, contains('_path_is_below(target, IMAGES_DIR)'));
      },
    );

    test('allowlist de extensiones png/jpg/jpeg/webp con content-type', () {
      expect(src, contains('".png": "image/png"'));
      expect(src, contains('".jpg": "image/jpeg"'));
      expect(src, contains('".jpeg": "image/jpeg"'));
      expect(src, contains('".webp": "image/webp"'));
    });

    test('limite de tamano de 20 MB comprobado antes de leer', () {
      expect(src, contains('_IMAGE_MAX_BYTES = 20 * 1024 * 1024'));
      final handler = _handlerBody(src);
      expect(handler, contains('size > _IMAGE_MAX_BYTES'));
      // El stat va antes del read_bytes: el orden en el codigo lo garantiza.
      expect(
        handler.indexOf('stat().st_size'),
        lessThan(handler.indexOf('read_bytes()')),
      );
    });

    test(
      'error generico UNICO para todas las causas (no filtra filesystem)',
      () {
        final handler = _handlerBody(src);
        // Un solo constructor del error, reutilizado en cada rechazo: mismo
        // cuerpo para inexistente / traversal / extension mala / muy grande.
        expect(handler, contains('_err("not_found", "No disponible", 404)'));
        // Ningun otro _err con mensaje distinto dentro del handler.
        final errs = RegExp(r'_err\(').allMatches(handler).length;
        expect(
          errs,
          1,
          reason: 'todos los rechazos deben salir por el mismo _denied()',
        );
      },
    );
  });
}

/// Cuerpo del handler image_get (desde su def hasta el siguiente def top-level).
String _handlerBody(String src) {
  final start = src.indexOf('async def image_get(request):');
  expect(start, greaterThanOrEqualTo(0));
  final rest = src.substring(start);
  final end = rest.indexOf('\nasync def ', 1);
  return end > 0 ? rest.substring(0, end) : rest;
}
