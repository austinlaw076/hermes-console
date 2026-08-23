import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/navigation/chat_route.dart';

class _RouteProbe extends StatelessWidget {
  const _RouteProbe(this.label, {this.onOpen});

  final String label;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text(label)),
      floatingActionButton: onOpen == null
          ? null
          : FloatingActionButton(onPressed: onOpen, child: const Text('open')),
    );
  }
}

void main() {
  testWidgets('cerrar un chat abierto desde una sección vuelve a Inicio', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (homeContext) => _RouteProbe(
            'Inicio',
            onOpen: () => Navigator.of(homeContext).push<void>(
              MaterialPageRoute<void>(
                builder: (sectionContext) => _RouteProbe(
                  'Conversaciones',
                  onOpen: () => openChatFromHome<void>(
                    sectionContext,
                    builder: (_) => const _RouteProbe('Chat A'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Conversaciones'), findsOneWidget);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Chat A'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Conversaciones'), findsNothing);
    expect(find.text('Chat A'), findsNothing);
  });

  testWidgets('abrir otro chat sustituye la pila de chats anterior', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (homeContext) => _RouteProbe(
            'Inicio',
            onOpen: () => openChatFromHome<void>(
              homeContext,
              builder: (chatAContext) => _RouteProbe(
                'Chat A',
                onOpen: () => openChatFromHome<void>(
                  chatAContext,
                  builder: (_) => const _RouteProbe('Chat B'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Chat A'), findsOneWidget);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Chat B'), findsOneWidget);
    expect(find.text('Chat A'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Chat A'), findsNothing);
    expect(find.text('Chat B'), findsNothing);
  });

  testWidgets('cerrar un Bot Chat vuelve a Mission Control', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (homeContext) => _RouteProbe(
            'Inicio',
            onOpen: () => Navigator.of(homeContext).push<void>(
              MaterialPageRoute<void>(
                builder: (missionContext) => _RouteProbe(
                  'Mission Control',
                  onOpen: () => openChatFromSection<void>(
                    missionContext,
                    builder: (_) => const _RouteProbe('Bot Chat'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Bot Chat'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Mission Control'), findsOneWidget);
    expect(find.text('Inicio'), findsNothing);
    expect(find.text('Bot Chat'), findsNothing);
  });

  testWidgets('Room Chat vuelve al detalle y después a Trabajo', (
    tester,
  ) async {
    BuildContext? missionContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (homeContext) => _RouteProbe(
            'Inicio',
            onOpen: () => Navigator.of(homeContext).push<void>(
              MaterialPageRoute<void>(
                builder: (context) {
                  missionContext = context;
                  return _RouteProbe(
                    'Trabajo',
                    onOpen: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => _RouteProbe(
                          'Detalle #homelab',
                          onOpen: () => openChatFromSection<void>(
                            missionContext!,
                            builder: (_) => const _RouteProbe('Room Chat'),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Room Chat'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Detalle #homelab'), findsOneWidget);
    expect(find.text('Room Chat'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Trabajo'), findsOneWidget);
    expect(find.text('Detalle #homelab'), findsNothing);
  });

  testWidgets('chat normal vuelve a Conversaciones sin revivir otro chat', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (homeContext) => _RouteProbe(
            'Inicio',
            onOpen: () => openChatWithParent<void>(
              homeContext,
              parentBuilder: (_) => const _RouteProbe('Conversaciones'),
              builder: (_) => const _RouteProbe('Chat actual'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Chat actual'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Conversaciones'), findsOneWidget);
    expect(find.text('Inicio'), findsNothing);
    expect(find.text('Chat actual'), findsNothing);
  });
}
