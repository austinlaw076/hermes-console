import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/chat_event_cards.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

/// Render de código/comandos/salida: monoespaciado real y `markdown` prosa que
/// NO debe verse como bloque de código.
void main() {
  Widget host(Widget child) => MaterialApp(
    localizationsDelegates: Strings.localizationsDelegates,
    supportedLocales: Strings.supportedLocales,
    locale: const Locale('es'),
    debugShowCheckedModeBanner: false,
    theme: AppTheme.hermesRedDark,
    home: Scaffold(
      body: Center(child: SizedBox(width: 360, child: child)),
    ),
  );

  // Verdadero si algún Text con el texto buscado se pinta en 'monospace'.
  // Soporta Text plano (estilo en el widget) y Text.rich del resaltado de
  // sintaxis (estilo en el TextSpan raíz).
  bool hasMonoText(WidgetTester tester, Pattern contains) {
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      final span = t.textSpan;
      final plain = t.data ?? span?.toPlainText() ?? '';
      if (!plain.contains(contains)) continue;
      final family =
          t.style?.fontFamily ??
          (span is TextSpan ? span.style?.fontFamily : null);
      if (family == 'monospace') return true;
    }
    return false;
  }

  group('code blocks', () {
    testWidgets('comando Windows plano obtiene bloque y botón copiar', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const AssistantMarkdownView(data: 'Para listar:\ndir')),
      );
      expect(hasMonoText(tester, 'dir'), isTrue);
      expect(find.text('copiar'), findsOneWidget);
      final copyTarget = find
          .ancestor(
            of: find.text('copiar'),
            matching: find.byType(GestureDetector),
          )
          .first;
      expect(tester.getSize(copyTarget).height, greaterThanOrEqualTo(48));
    });

    testWidgets('el cuerpo del code block es monoespaciado', (tester) async {
      await tester.pumpWidget(
        host(
          const AssistantMarkdownView(
            data: '```bash\nsudo pacman -S android-tools\n```',
          ),
        ),
      );
      expect(hasMonoText(tester, 'pacman'), isTrue);
    });

    testWidgets('```markdown con prosa NO se trata como código', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const AssistantMarkdownView(
            data: '```markdown\nResumen del día\nTodo ha ido bien hoy.\n```',
          ),
        ),
      );
      // Sin cabecera de code block (no hay botón copiar) y la prosa es visible.
      expect(find.text('copiar'), findsNothing);
      expect(find.textContaining('Todo ha ido bien'), findsOneWidget);
    });

    testWidgets('```markdown con señales de código sigue siendo bloque', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const AssistantMarkdownView(
            data: '```markdown\nexport KEY=abc; run --now && echo ok\n```',
          ),
        ),
      );
      // Tiene `;`/`=`/`&&` → se mantiene como código (cabecera + copiar).
      expect(find.text('copiar'), findsOneWidget);
    });
  });

  group('chat event cards', () {
    testWidgets('CommandPreviewCard muestra el comando en monoespaciado', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const CommandPreviewCard(
            command: 'curl -s http://127.0.0.1:9119/api',
          ),
        ),
      );
      expect(hasMonoText(tester, 'curl'), isTrue);
    });

    testWidgets('la salida de herramienta se muestra en monoespaciado', (
      tester,
    ) async {
      final info = ChatEventInfo.classify(<String, dynamic>{
        'role': 'tool',
        'tool_name': 'ls',
        'content':
            '{"exit_code":0,"output":"total 24\\nconfig.yaml\\nsoul.md"}',
      });
      await tester.pumpWidget(host(ToolEventCard(info: info)));
      // Expande la tarjeta para revelar el bloque de salida.
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      expect(hasMonoText(tester, 'config.yaml'), isTrue);
    });
  });
}
