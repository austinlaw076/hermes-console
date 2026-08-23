// Convierte texto con Markdown en texto apto para LEER EN VOZ ALTA.
//
// Problema: el TTS lee los símbolos literalmente. Una respuesta como
// "## Tendencias\n- **repo/x** — descripción" se oye "almohadilla almohadilla
// Tendencias, guion asterisco asterisco repo barra x…", que suena a basura.
// Aquí quitamos la sintaxis Markdown y dejamos PROSA limpia antes de mandarla al
// motor de voz.
//
// Importante: esto NO toca el texto que se MUESTRA en pantalla (que conserva su
// formato). Solo transforma lo que se envía al TTS. Puro y sin estado: testeable
// sin Flutter.
class SpokenText {
  /// Devuelve [input] sin sintaxis Markdown, listo para hablar. Si tras limpiar
  /// no queda nada audible (p.ej. era solo una URL o una regla horizontal),
  /// devuelve cadena vacía y el llamador NO debe encolarlo.
  static String fromMarkdown(String input) {
    var t = input;

    // Red de seguridad ante salida en modo TUI: algún backend (p.ej. el agente
    // local si se le habla por una terminal) cuela secuencias ANSI y caracteres
    // decorativos —spinner braille (⠹⠸⠼, suena a "puntos"), paneles de caja
    // (│ ─ ┌, suena a "barras"), bloques y figuras— que el TTS leería como
    // basura. No son palabras: fuera siempre, venga de donde venga.
    t = t.replaceAll(
        RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]|\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)'),
        ' ');
    t = t.replaceAll(RegExp('[─-◿⠀-⣿]'), ' ');
    // Controles sueltos (CR/BEL/BS…), conservando tabulador y salto de línea.
    t = t.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), ' ');

    // Bloques de código vallados ```…``` completos: fuera (la policy ya los
    // descarta normalmente; esto es una red de seguridad).
    t = t.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');

    // Imágenes ![alt](url) → alt. Enlaces [texto](url) → texto. (Imágenes antes
    // que enlaces porque comparten sintaxis.)
    t = t.replaceAllMapped(
        RegExp(r'!\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1) ?? '');
    t = t.replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m.group(1) ?? '');

    // URLs sueltas: leerlas en voz alta es ruido. Fuera.
    t = t.replaceAll(RegExp(r'https?://\S+'), ' ');

    // Código en línea `código` → código.
    t = t.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m.group(1) ?? '');

    // Negrita/cursiva/tachado: **x** __x__ *x* _x_ ~~x~~ → x.
    t = t.replaceAllMapped(
        RegExp(r'(\*\*|__|~~|\*|_)(.+?)\1'), (m) => m.group(2) ?? '');

    // Procesado por líneas: encabezados, citas, viñetas, reglas y tablas.
    final out = <String>[];
    for (var line in t.split('\n')) {
      var l = line;

      // Regla horizontal (---, ***, ___): se descarta la línea entera.
      if (RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$').hasMatch(l)) continue;

      // Fila separadora de tabla (|---|:--:|): se descarta.
      if (RegExp(r'^\s*\|?[\s:|-]+\|?\s*$').hasMatch(l) && l.contains('-')) {
        continue;
      }

      // Encabezado: quita las almohadillas iniciales (### Título → Título).
      l = l.replaceFirst(RegExp(r'^\s*#{1,6}\s*'), '');

      // Cita: quita el "> " inicial (puede repetirse: >>).
      l = l.replaceFirst(RegExp(r'^\s*>+\s?'), '');

      // Viñeta o lista numerada al inicio: quita el marcador, conserva el texto.
      l = l.replaceFirst(RegExp(r'^\s*([-*+]|\d+[.)])\s+'), '');

      // Fila de tabla con celdas: convierte las barras en pausas (coma).
      if (l.contains('|')) {
        final cells = l
            .split('|')
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty)
            .toList();
        if (cells.isNotEmpty) l = cells.join(', ');
      }

      out.add(l);
    }
    t = out.join('\n');

    // Símbolos sueltos de Markdown que hayan podido quedar.
    t = t.replaceAll(RegExp(r'[`*_#>|]'), ' ');

    // Normaliza espacios y saltos: colapsa espacios, deja como mucho un salto
    // doble y recorta.
    t = t.replaceAll(RegExp(r'[ \t]+'), ' ');
    t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    t = t.replaceAll(RegExp(r' *\n *'), '\n');
    return t.trim();
  }
}
