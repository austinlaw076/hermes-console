import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/main.dart';

void main() {
  testWidgets('owner notification removes stale routes and preserves root', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('root')),
      ),
    );

    navigatorKey.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('stale chat')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('stale chat'), findsOneWidget);

    pushNotificationOwnerRoute<void>(
      navigatorKey.currentState!,
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Bots owner')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bots owner'), findsOneWidget);
    expect(find.text('stale chat'), findsNothing);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('root'), findsOneWidget);
    expect(find.text('stale chat'), findsNothing);
  });
}
