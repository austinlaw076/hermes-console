import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/session_detail_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('es'),
  theme: AppTheme.fromId('dark'),
  localizationsDelegates: Strings.localizationsDelegates,
  supportedLocales: Strings.supportedLocales,
  home: child,
);

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int attempts = 80,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    await tester.pump(const Duration(milliseconds: 25));
    if (condition()) return;
  }
  expect(condition(), isTrue);
}

void main() {
  testWidgets('abre, cachea y salta a un artefacto sin otra petición', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var messageRequests = 0;
    final transcript = <Map<String, dynamic>>[
      {
        'role': 'user',
        'message_id': 'fake-path',
        'content': 'Esto solo menciona /managed/fake.txt y no es un artefacto.',
      },
      for (var index = 1; index < 25; index++)
        {
          'role': index.isEven ? 'assistant' : 'user',
          'message_id': 'message-$index',
          'content': 'Mensaje $index ${'contenido ' * 20}',
        },
      {
        'role': 'assistant',
        'message_id': 'artifact-source',
        'content': [
          {'type': 'text', 'text': 'artifact source payload'},
          {
            'type': 'document',
            'artifact_id': 'real-artifact',
            'name': 'informe-real.pdf',
          },
        ],
      },
      for (var index = 26; index < 32; index++)
        {
          'role': 'assistant',
          'message_id': 'message-$index',
          'content': 'Mensaje $index ${'contenido ' * 20}',
        },
    ];
    final api = ApiClient(
      baseUrl: 'http://127.0.0.1:8642',
      apiKey: 'test-key',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/sessions/session-tip/messages') {
          messageRequests++;
          return http.Response(jsonEncode({'data': transcript}), 200);
        }
        if (request.url.path == '/api/sessions/session-tip') {
          return http.Response(
            jsonEncode({
              'session': {
                'id': 'session-tip',
                '_lineage_root_id': 'session-root',
                'title': 'Artifacts',
                'model': 'model-a',
                'source': 'mobile',
                'message_count': transcript.length,
                'is_active': false,
                'started_at': 1784500000,
                'ended_at': 1784500100,
              },
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );

    final connection = SavedConnection(
      id: 'connection-artifacts',
      label: 'Artifacts',
      host: '127.0.0.1',
      port: 8642,
      apiKey: 'test-key',
      kind: InstanceKind.vps,
    );
    const session = Session(
      id: 'session-tip',
      lineageRootId: 'session-root',
      title: 'Artifacts',
      model: 'model-a',
      source: 'mobile',
      messageCount: 32,
      isActive: false,
      preview: '',
      startedAt: 1784500000,
    );

    await tester.pumpWidget(
      _host(
        SessionDetailScreen(
          connection: connection,
          session: session,
          client: api,
        ),
      ),
    );
    final action = find.byTooltip('Artefactos');
    final actionButton = find.ancestor(
      of: action,
      matching: find.byType(IconButton),
    );
    await _pumpUntil(tester, () {
      if (actionButton.evaluate().isEmpty) return false;
      return tester.widget<IconButton>(actionButton).onPressed != null;
    });

    expect(messageRequests, 1);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('1 elemento'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('session-artifact-real-artifact')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('session-artifact-real-artifact')),
    );
    await _pumpUntil(
      tester,
      () =>
          find.textContaining('artifact source payload').evaluate().isNotEmpty,
    );

    await tester.tap(find.byTooltip('Artefactos'));
    await tester.pumpAndSettle();
    expect(find.text('1 elemento'), findsOneWidget);
    expect(messageRequests, 1);
  });
}
