import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/hermes_floating_notice.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
  theme: AppTheme.fromId('dark'),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: child,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('floating notice opens its destination from the whole card', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      _host(
        HermesFloatingNotice(
          noticeKey: const ValueKey('reply-ready'),
          icon: Icons.check_circle_outline,
          tint: Colors.green,
          title: 'Respuesta lista',
          body: 'Hermes termino el trabajo.',
          actionLabel: 'Ir',
          dismissLabel: 'Descartar',
          onOpen: () => opened++,
          onDismissed: () {},
        ),
        reduceMotion: true,
      ),
    );

    expect(find.text('Respuesta lista'), findsOneWidget);
    expect(find.text('Hermes termino el trabajo.'), findsOneWidget);
    expect(find.text('Ir'), findsOneWidget);
    expect(find.byTooltip('Descartar'), findsOneWidget);

    await tester.tap(
      find
          .ancestor(
            of: find.text('Respuesta lista'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await tester.pump();
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('horizontal swipe only dismisses the floating notice', (
    tester,
  ) async {
    var visible = true;
    var dismissed = 0;
    var opened = 0;

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => visible
              ? HermesFloatingNotice(
                  noticeKey: const ValueKey('approval-pending'),
                  icon: Icons.verified_user_outlined,
                  tint: Colors.orange,
                  title: 'Necesita tu permiso',
                  actionLabel: 'Ir',
                  dismissLabel: 'Descartar',
                  onOpen: () => opened++,
                  onDismissed: () {
                    dismissed++;
                    setState(() => visible = false);
                  },
                )
              : const SizedBox.shrink(),
        ),
        reduceMotion: true,
      ),
    );

    await tester.drag(
      find.byKey(const ValueKey('approval-pending')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();

    expect(dismissed, 1);
    expect(opened, 0);
    expect(find.text('Necesita tu permiso'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismiss is isolated from the open action', (tester) async {
    var opened = 0;
    var dismissed = 0;
    await tester.pumpWidget(
      _host(
        HermesFloatingNotice(
          noticeKey: const ValueKey('isolated-actions'),
          icon: Icons.task_alt,
          tint: Colors.blue,
          title: 'Tarea terminada',
          body: 'El resultado ya esta disponible.',
          actionLabel: 'Ir',
          dismissLabel: 'Descartar',
          onOpen: () => opened++,
          onDismissed: () => dismissed++,
        ),
        reduceMotion: true,
      ),
    );

    final actionRect = tester.getRect(
      find.byKey(const ValueKey('floating-notice-action')),
    );
    final dismissRect = tester.getRect(
      find.byKey(const ValueKey('floating-notice-dismiss')),
    );
    expect(dismissRect.width, greaterThanOrEqualTo(48));
    expect(dismissRect.height, greaterThanOrEqualTo(48));
    expect(actionRect.right, lessThan(dismissRect.left));

    await tester.tap(find.byKey(const ValueKey('floating-notice-dismiss')));
    await tester.pump();
    expect(dismissed, 1);
    expect(opened, 0);
    expect(tester.takeException(), isNull);
  });
}
