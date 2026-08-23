import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/widgets/hermes_drawer.dart';

void main() {
  test('las superficies globales habilitan el gesto lateral del drawer', () {
    const paths = <String>[
      'lib/core/screens/home_dashboard_screen.dart',
      'lib/core/screens/session_list_screen.dart',
      'lib/core/screens/chat_screen.dart',
    ];

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('drawerEnableOpenDragGesture: true,'),
        reason: path,
      );
      expect(
        source,
        contains('drawerEdgeDragWidth: HermesDrawer.edgeDragWidth(context),'),
        reason: path,
      );
    }
  });

  testWidgets('la banda suma el borde reservado por Android y 48 dp', (
    tester,
  ) async {
    late double width;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          systemGestureInsets: EdgeInsets.only(left: 24),
        ),
        child: Builder(
          builder: (context) {
            width = HermesDrawer.edgeDragWidth(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(width, 72);
  });

  test('la exclusión nativa es acotada y solo la gobiernan rutas con drawer', () {
    final native = File(
      'android/app/src/main/kotlin/com/hermesagent/hermes_android/MainActivity.kt',
    ).readAsStringSync();
    expect(native, contains('systemGestureExclusionRects'));
    expect(native, contains('200 * density'));
    expect(native, contains('Rect(0, top, width, top + height)'));

    for (final path in const <String>[
      'lib/core/screens/home_dashboard_screen.dart',
      'lib/core/screens/session_list_screen.dart',
      'lib/core/screens/chat_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('DrawerGestureExclusion.setEnabled'),
        reason: path,
      );
    }
  });
}
