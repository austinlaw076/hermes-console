import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/hermes_file_tree.dart';

void main() {
  test('parsea un árbol de terminal sin consultar el filesystem', () {
    final nodes = parseHermesFileTree('''
src/
├── app/
│   └── main.dart
└── README.md
''');

    expect(nodes, isNotNull);
    expect(nodes, hasLength(1));
    expect(nodes!.single.name, 'src');
    expect(nodes.single.isDirectory, isTrue);
    expect(nodes.single.children, hasLength(2));
    expect(nodes.single.children.first.children.single.name, 'main.dart');
  });

  test('acepta punto como raíz implícita de un árbol de terminal', () {
    final nodes = parseHermesFileTree('''
.
├── lib/
│   └── main.dart
└── README.md
''');

    expect(nodes, isNotNull);
    expect(nodes, hasLength(2));
    expect(nodes!.first.name, 'lib');
    expect(nodes.first.children.single.name, 'main.dart');
    expect(nodes.last.name, 'README.md');
  });

  test('rechaza saltos de profundidad y limita nombres', () {
    expect(parseHermesFileTree('root/\n      orphan.txt'), isNull);
    final nodes = parseHermesFileTree('${'a' * 190}.txt', maxNameLength: 24);
    expect(nodes!.single.name.length, 24);
    expect(nodes.single.name, endsWith('…'));
  });

  testWidgets('expande y contrae carpetas sin una tarjeta exterior', (
    tester,
  ) async {
    final nodes = parseHermesFileTree('src/\n  main.dart')!;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.hermesRedDark,
        home: Scaffold(body: HermesFileTree(nodes: nodes)),
      ),
    );

    expect(find.byKey(const ValueKey('hermes-file-tree')), findsOneWidget);
    expect(find.text('main.dart'), findsOneWidget);

    await tester.tap(find.text('src'));
    await tester.pump();
    expect(find.text('main.dart'), findsNothing);
  });
}
