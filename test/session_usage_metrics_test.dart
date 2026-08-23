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

void main() {
  testWidgets('el resumen separa cached tokens y Cache % reales', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient(
      baseUrl: 'http://127.0.0.1:8642',
      apiKey: 'test-only',
      httpClient: MockClient(
        (_) async => http.Response(jsonEncode({'data': <Object>[]}), 200),
      ),
    );
    final connection = SavedConnection(
      id: 'usage-metrics',
      label: 'Usage',
      host: '127.0.0.1',
      port: 8642,
      apiKey: 'test-only',
    );
    const session = Session(
      id: 'session-usage',
      title: 'Usage',
      model: 'model-a',
      source: 'mobile',
      messageCount: 2,
      isActive: false,
      preview: '',
      startedAt: 100,
      inputTokens: 100,
      outputTokens: 25,
      cacheReadTokens: 50,
      cacheWriteTokens: 50,
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        theme: AppTheme.fromId('dark'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: SessionDetailScreen(
          connection: connection,
          session: session,
          observedFirstTokenLatencyMs: 840,
          client: api,
          skipInitialSessionRefresh: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('tokens en caché'), findsOneWidget);
    expect(find.text('50'), findsNWidgets(2));
    expect(find.text('caché %'), findsOneWidget);
    expect(find.text('25.0%'), findsOneWidget);
    expect(find.text('TTFT · medido por la app'), findsWidgets);
    expect(find.text('840 ms'), findsOneWidget);
  });
}
