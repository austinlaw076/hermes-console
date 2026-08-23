import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/utils/semantic_markdown.dart';

void main() {
  group('enhanceCommandBlocks', () {
    test('convierte comandos Windows planos en bloques con lenguaje', () {
      const input = 'En CMD:\ndir\n\nEn PowerShell:\nGet-ChildItem -Force';
      expect(
        enhanceCommandBlocks(input),
        'En CMD:\n\n```bat\ndir\n```\n\nEn PowerShell:\n\n'
        '```powershell\nGet-ChildItem -Force\n```',
      );
    });

    test('agrupa comandos consecutivos del mismo shell', () {
      expect(enhanceCommandBlocks('pwd\nls -la'), '```bash\npwd\nls -la\n```');
    });

    test('no toca prosa ni palabras ambiguas dentro de una frase', () {
      const input = 'Puedes usar dir para ver el directorio.\nTodo está listo.';
      expect(enhanceCommandBlocks(input), input);
    });

    test('respeta bloques existentes y es idempotente', () {
      const input = '```bat\ndir\n```';
      expect(enhanceCommandBlocks(input), input);
      expect(
        enhanceCommandBlocks(enhanceCommandBlocks('dir')),
        '```bat\ndir\n```',
      );
    });
  });

  group('enhanceHeadings', () {
    test('texto sin etiquetas queda intacto (cero cambios)', () {
      const input = 'Una respuesta normal, sin secciones especiales.';
      expect(enhanceHeadings(input), input);
    });

    test('promueve una línea-etiqueta conocida a encabazado ##', () {
      const input = 'Estado:\nTodo correcto.';
      expect(enhanceHeadings(input), '## Estado\nTodo correcto.');
    });

    test('reconoce etiquetas en inglés y multi-palabra', () {
      expect(enhanceHeadings('Next steps:\nDeploy.'), '## Next steps\nDeploy.');
    });

    test('admite negrita alrededor de la etiqueta', () {
      expect(
        enhanceHeadings('**Conclusión:**\nListo.'),
        '## Conclusión\nListo.',
      );
    });

    test('NO toca una etiqueta con contenido inline (conservador)', () {
      const input = 'Estado: todo bien y seguimos.';
      expect(enhanceHeadings(input), input);
    });

    test('etiqueta ad-hoc corta se promueve a subsección ###', () {
      expect(
        enhanceHeadings('Restart medido:\nreal 0m1,182s'),
        '### Restart medido\nreal 0m1,182s',
      );
      expect(
        enhanceHeadings('Puerto/API:\n0.0.0.0:8642'),
        '### Puerto/API\n0.0.0.0:8642',
      );
      expect(enhanceHeadings('Dice:\nalgo'), '### Dice\nalgo');
    });

    test('la whitelist sigue dando sección principal ##', () {
      expect(enhanceHeadings('Estado:\nok'), '## Estado\nok');
    });

    test('NO promueve una oración larga terminada en dos puntos', () {
      const input = 'Para resumir todo lo que hemos visto hasta aquí:\nx';
      expect(enhanceHeadings(input), input);
    });

    test('NO promueve algo con pinta de URL/código', () {
      const input = 'https://example.com/api:\nx';
      expect(enhanceHeadings(input), input);
    });

    test('no toca el interior de un bloque de código', () {
      const input = '```\nEstado:\n```';
      expect(enhanceHeadings(input), input);
    });

    test('es idempotente', () {
      const input = 'Resumen:\nx';
      final once = enhanceHeadings(input);
      expect(enhanceHeadings(once), once);
    });
  });

  group('enhanceImplicitLists', () {
    test('cabecera con dos puntos + ≥2 líneas cortas → viñetas', () {
      const input =
          'He visto referencias o texto con:\npassphrase estándar\nrutas de tokens\nSSH key info';
      expect(
        enhanceImplicitLists(input),
        'He visto referencias o texto con:\n\n- passphrase estándar\n- rutas de tokens\n- SSH key info',
      );
    });

    test('una sola línea tras la cabecera NO se convierte en lista', () {
      const input = 'Resultado:\ntodo bien';
      expect(enhanceImplicitLists(input), input);
    });

    test('NO toca líneas largas (oraciones)', () {
      const input =
          'Detalles:\nesta es una frase claramente larga que no es un item\notra frase igual de larga que tampoco lo es';
      expect(enhanceImplicitLists(input), input);
    });

    test('respeta el código y las viñetas ya existentes', () {
      const input = '```\nlista:\nuno\ndos\n```';
      expect(enhanceImplicitLists(input), input);
    });

    test('es idempotente', () {
      const input = 'Con:\nuno dos\ntres cuatro';
      final once = enhanceImplicitLists(input);
      expect(enhanceImplicitLists(once), once);
    });

    // Regresión real (captura del usuario): el modelo pone una línea EN BLANCO
    // entre "Mejor:" y los ítems; antes no se detectaba la lista y quedaban
    // líneas sueltas sin viñeta.
    test('cabecera + línea en blanco + ítems → viñetas', () {
      const input =
          'Mejor:\n\nlista de archivos relevantes\nerror exacto\ncomando que falla';
      expect(
        enhanceImplicitLists(input),
        'Mejor:\n\n- lista de archivos relevantes\n- error exacto\n- comando que falla',
      );
    });

    test('ítems que terminan como oración (.) NO se convierten', () {
      const input = 'Notas:\n\nesto es una frase normal.\nesto otra frase.';
      expect(enhanceImplicitLists(input), input);
    });
  });

  group('enhanceDefinitionLists', () {
    test('≥2 líneas clave: descripción → viñetas con clave en negrita', () {
      const input =
          'Memoria inyectada: útil pero sin verificación.\nagentmemory: incompleto para homelab.\nskills: contaminadas con historia.';
      expect(
        enhanceDefinitionLists(input),
        '- **Memoria inyectada:** útil pero sin verificación.\n'
        '- **agentmemory:** incompleto para homelab.\n'
        '- **skills:** contaminadas con historia.',
      );
    });

    test('una sola línea clave:valor NO se agrupa', () {
      const input = 'Versión: 0.17.0';
      expect(enhanceDefinitionLists(input), input);
    });

    test('NO se traga las etiquetas de hallazgo (callout)', () {
      const input = 'Problema: el venv está roto.\nError: faltan símbolos.';
      expect(enhanceDefinitionLists(input), input);
    });

    test('respeta el código', () {
      const input = '```\nkey: value\nother: thing\n```';
      expect(enhanceDefinitionLists(input), input);
    });
  });

  group('enhanceHeadings — título sin dos puntos', () {
    test('título corto aislado se promueve a ###', () {
      const input = 'algo previo.\n\nResumen honesto\n\nEl cuerpo va aquí.';
      expect(
        enhanceHeadings(input),
        'algo previo.\n\n### Resumen honesto\n\nEl cuerpo va aquí.',
      );
    });

    test('NO promueve una frase corta que termina en punto', () {
      const input = 'x\n\nNo lo he tocado.\n\ny';
      expect(enhanceHeadings(input), input);
    });

    test('NO promueve una línea con minúscula inicial', () {
      const input = 'x\n\nresumen honesto\n\ny';
      expect(enhanceHeadings(input), input);
    });

    test('NO promueve la última línea (no introduce contenido)', () {
      const input = 'cuerpo largo aquí.\n\nFinal Limpio';
      expect(enhanceHeadings(input), input);
    });
  });

  group('splitContentBlocks', () {
    test('sin hallazgos devuelve un único bloque Markdown intacto', () {
      const input = 'Párrafo uno.\n\nPárrafo dos.';
      final blocks = splitContentBlocks(input);
      expect(blocks, hasLength(1));
      expect(blocks.first, isA<MarkdownContentBlock>());
      expect((blocks.first as MarkdownContentBlock).text, input);
    });

    test('extrae un hallazgo Warning como callout', () {
      const input =
          'Texto previo.\n\nWarning: el venv está roto\n\nTexto posterior.';
      final blocks = splitContentBlocks(input);
      expect(blocks, hasLength(3));
      expect(blocks[0], isA<MarkdownContentBlock>());
      final c = blocks[1] as CalloutContentBlock;
      expect(c.kind, CalloutKind.warning);
      expect(c.title, 'Warning');
      expect(c.body, 'el venv está roto');
      expect(blocks[2], isA<MarkdownContentBlock>());
    });

    test('Error mapea a CalloutKind.error', () {
      final blocks = splitContentBlocks('Error: no se pudo conectar');
      expect((blocks.single as CalloutContentBlock).kind, CalloutKind.error);
    });

    test('Problema/Conflicto/Issue mapean a warning', () {
      for (final label in ['Problema', 'Conflicto', 'Issue', 'Bug']) {
        final blocks = splitContentBlocks('$label: algo');
        expect(
          (blocks.single as CalloutContentBlock).kind,
          CalloutKind.warning,
          reason: label,
        );
      }
    });

    test('cuerpo multilínea hasta la línea en blanco', () {
      const input = 'Problema: línea uno\nlínea dos\n\nResto.';
      final blocks = splitContentBlocks(input);
      final c = blocks[0] as CalloutContentBlock;
      expect(c.body, 'línea uno\nlínea dos');
    });

    test('NO confunde un elemento de lista con un hallazgo', () {
      const input = '- Error: dentro de una lista';
      final blocks = splitContentBlocks(input);
      expect(blocks.single, isA<MarkdownContentBlock>());
    });

    test('NO crea callout sin cuerpo (etiqueta sola)', () {
      final blocks = splitContentBlocks('Error:');
      expect(blocks.single, isA<MarkdownContentBlock>());
    });

    test('ignora hallazgos dentro de bloques de código', () {
      const input = '```\nError: esto es código\n```';
      final blocks = splitContentBlocks(input);
      expect(blocks.single, isA<MarkdownContentBlock>());
    });
  });

  group('enhanceEvidence', () {
    test('envuelve una ruta absoluta en código inline', () {
      expect(
        enhanceEvidence('Vive en /home/demo/.hermes/memory/ ahí.'),
        'Vive en `/home/demo/.hermes/memory/` ahí.',
      );
    });

    test('envuelve rutas de home (~/...)', () {
      expect(
        enhanceEvidence('Mira ~/.config/app/settings.'),
        'Mira `~/.config/app/settings`.',
      );
    });

    test('no toca rutas ya en código inline', () {
      const input = 'Ruta `/etc/hosts` lista.';
      expect(enhanceEvidence(input), input);
    });

    test('no toca el interior de vallas de código', () {
      const input = '```\n/usr/bin/python\n```';
      expect(enhanceEvidence(input), input);
    });

    test('no confunde fracciones ni "y/o"', () {
      const input = 'Era 5/6 y/o algo más.';
      expect(enhanceEvidence(input), input);
    });

    test('no toca una URL (se deja como enlace)', () {
      const input = 'Visita https://example.com/path/to/page hoy.';
      expect(enhanceEvidence(input), input);
    });

    test('es idempotente', () {
      const input = 'Config en /var/lib/app/data aquí.';
      final once = enhanceEvidence(input);
      expect(enhanceEvidence(once), once);
    });
  });
}
