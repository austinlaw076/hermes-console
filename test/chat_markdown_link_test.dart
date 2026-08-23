import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';

/// [isAllowedMarkdownLinkScheme] es la allowlist que decide si un enlace
/// tocado dentro del markdown del chat se lanza o se bloquea (hallazgo C3:
/// el texto puede venir de un modelo remoto, no es de confiar sin filtrar).
void main() {
  group('isAllowedMarkdownLinkScheme', () {
    test('permite http y https', () {
      expect(isAllowedMarkdownLinkScheme('http://example.com'), isTrue);
      expect(isAllowedMarkdownLinkScheme('https://example.com/ruta'), isTrue);
    });

    test('permite mailto', () {
      expect(isAllowedMarkdownLinkScheme('mailto:hola@example.com'), isTrue);
    });

    test('bloquea esquemas peligrosos', () {
      expect(isAllowedMarkdownLinkScheme('intent://malicioso'), isFalse);
      expect(isAllowedMarkdownLinkScheme('file:///etc/passwd'), isFalse);
      expect(isAllowedMarkdownLinkScheme('tel:+1234567890'), isFalse);
      expect(isAllowedMarkdownLinkScheme('javascript:alert(1)'), isFalse);
    });

    test('bloquea href nulo o que no parsea', () {
      expect(isAllowedMarkdownLinkScheme(null), isFalse);
      expect(isAllowedMarkdownLinkScheme(''), isFalse);
    });
  });

  group('enlaces de fuentes en respuestas del asistente', () {
    const articleUrl = 'https://www.elmundo.es/espana/2026/07/29/noticia.html';

    Widget host(
      String markdown, {
      bool isStreaming = false,
      ValueChanged<String?>? onTapLink,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: buildAssistantAnswerBlocks(
              markdown,
              isStreaming: isStreaming,
              markdown: (data) => MarkdownBody(
                data: data,
                onTapLink: (text, href, title) => onTapLink?.call(href),
              ),
              callout: (block) => Text('${block.title}: ${block.body}'),
            ),
          ),
        ),
      );
    }

    testWidgets('conserva y permite pulsar un enlace Markdown etiquetado', (
      tester,
    ) async {
      String? opened;
      await tester.pumpWidget(
        host(
          '[Fuente: El Mundo]($articleUrl)',
          onTapLink: (href) => opened = href,
        ),
      );

      await tester.tap(find.text('Fuente: El Mundo', findRichText: true));
      expect(opened, articleUrl);
    });

    testWidgets('GFM convierte una URL desnuda recibida en enlace pulsable', (
      tester,
    ) async {
      String? opened;
      await tester.pumpWidget(
        host(articleUrl, onTapLink: (href) => opened = href),
      );

      await tester.tap(find.text(articleUrl, findRichText: true));
      expect(opened, articleUrl);
    });

    testWidgets('el normalizador de streaming no pierde un enlace completo', (
      tester,
    ) async {
      String? opened;
      await tester.pumpWidget(
        host(
          '[El Mundo]($articleUrl)',
          isStreaming: true,
          onTapLink: (href) => opened = href,
        ),
      );

      await tester.tap(find.text('El Mundo', findRichText: true));
      expect(opened, articleUrl);
    });

    testWidgets('no inventa una URL si el modelo solo entrega la fuente', (
      tester,
    ) async {
      String? opened;
      await tester.pumpWidget(
        host('Fuente: El Mundo', onTapLink: (href) => opened = href),
      );

      await tester.tap(find.text('Fuente: El Mundo', findRichText: true));
      expect(opened, isNull);
    });
  });
}
