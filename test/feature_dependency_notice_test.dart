import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/utils/api_error.dart';
import 'package:hermes_android/core/widgets/feature_dependency_notice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(FeatureDependencyNotice.resetSessionDismissals);

  test('solo errores de autenticación reales piden configurar Dashboard', () {
    expect(
      classifyDashboardDependencyFailure(
        const DashboardAuthException(DashboardAuthFailureCode.loginRequired),
      ),
      DashboardDependencyFailure.credentials,
    );
    expect(
      classifyDashboardDependencyFailure(const DashboardHttpException(403)),
      DashboardDependencyFailure.credentials,
    );

    for (final error in <Object>[
      const DashboardAuthException(
        DashboardAuthFailureCode.rateLimited,
        statusCode: 429,
      ),
      const DashboardAuthException(
        DashboardAuthFailureCode.loginFailed,
        statusCode: 500,
      ),
      const DashboardHttpException(500),
      const FormatException('respuesta rota'),
      Exception('SocketException: red caída'),
    ]) {
      expect(
        classifyDashboardDependencyFailure(error),
        DashboardDependencyFailure.other,
        reason: '$error',
      );
    }
  });

  test('404 solo significa versión antigua para un endpoint versionado', () {
    const error = DashboardHttpException(
      404,
      body: '{"secret":"no debe mostrarse"}',
    );

    expect(error.toString(), 'HTTP 404');
    expect(
      classifyDashboardDependencyFailure(error),
      DashboardDependencyFailure.other,
    );
    expect(
      classifyDashboardDependencyFailure(error, notFoundMeansOldServer: true),
      DashboardDependencyFailure.serverVersion,
    );
  });

  testWidgets('un aviso descartado no reaparece durante la sesión', (
    tester,
  ) async {
    Widget host() => MaterialApp(
      theme: AppTheme.fromId('dark'),
      home: const Scaffold(
        body: FeatureDependencyNotice(
          noticeId: 'dashboard-test',
          kind: FeatureDependencyKind.dashboard,
          title: 'Dashboard',
          message: 'Necesita credenciales',
        ),
      ),
    );

    await tester.pumpWidget(host());
    expect(find.text('Dashboard'), findsOneWidget);
    final surface = tester.widget<Material>(
      find.byKey(const ValueKey('dependency-notice-dashboard-test')),
    );
    expect(surface.elevation, greaterThanOrEqualTo(3));

    await tester.tap(
      find.byKey(const ValueKey('dependency-dismiss-dashboard-test')),
    );
    await tester.pump();
    expect(find.text('Dashboard'), findsNothing);

    await tester.pumpWidget(host());
    expect(find.text('Dashboard'), findsNothing);
  });
}
