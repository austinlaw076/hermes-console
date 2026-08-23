import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/hermes_app_bar.dart';

Widget _scaffold(String themeId) => MaterialApp(
  theme: AppTheme.fromId(themeId),
  home: const Scaffold(appBar: HermesAppBar(title: Text('Sesiones'))),
);

void main() {
  testWidgets('tema terminal (Dracula) pone el título en MAYÚSCULAS', (
    tester,
  ) async {
    await tester.pumpWidget(_scaffold('dracula'));
    expect(find.text('SESIONES'), findsOneWidget);
    expect(find.text('Sesiones'), findsNothing);
  });

  testWidgets('tema no terminal (Graphite) deja el título tal cual', (
    tester,
  ) async {
    await tester.pumpWidget(_scaffold('graphite'));
    expect(find.text('Sesiones'), findsOneWidget);
    expect(find.text('SESIONES'), findsNothing);
  });

  testWidgets('título compuesto: solo el primer Text va en MAYÚSCULAS', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.fromId('dracula'),
        home: const Scaffold(
          appBar: HermesAppBar(
            title: Column(
              children: [Text('skills'), Text('69 activas · /api/skills')],
            ),
          ),
        ),
      ),
    );
    // El título (primer Text) se transforma; el subtítulo queda intacto.
    expect(find.text('SKILLS'), findsOneWidget);
    expect(find.text('skills'), findsNothing);
    expect(find.text('69 activas · /api/skills'), findsOneWidget);
  });
}
